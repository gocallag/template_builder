#!/usr/bin/env bash
set -xeuo pipefail

# Entrypoint for imagebuilder container
# - Reconciles host UID/GID to local runner user
# - Ensures a safe, atomic locked shadow entry for runner when necessary
# - Creates sudoers fragment for passwordless sudo for runner
# - Adds runner to host KVM group if provided
# - Drops to runner via gosu (or runs as root if RUN_AS_ROOT=1)
# - Provides DEBUG_ENTRYPOINT=1 for verbose diagnostics

HOST_UID=${HOST_UID:-1000}
HOST_GID=${HOST_GID:-1000}
HOST_KVM_GID=${HOST_KVM_GID:-$(stat -c "%g" /dev/kvm 2>/dev/null || true)}
LOCKFILE=${LOCKFILE:-/var/lock/entrypoint.lock}
DEBUG=${DEBUG_ENTRYPOINT:-0}

log()  { printf '%s %s\n' "$(date -Is)" "$*" >&2; }
debug(){ [ "${DEBUG:-0}" = "1" ] && log "DEBUG: $*"; }

# Acquire simple lock to avoid concurrent modifications
# open fd 9 for the lockfile; flock will hold it until the script exits
exec 9>"$LOCKFILE" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || { log "Another entrypoint is running; waiting..."; flock 9; }
fi

ensure_group_for_gid() {
  local gid="$1"; local name="$2"
  [ -z "$gid" ] && return 0
  # If a numeric GID already exists in /etc/group, do nothing
  if ! getent group "$gid" >/dev/null 2>&1; then
    log "Creating group $name with GID $gid"
    groupadd -g "$gid" "$name" || true
  else
    debug "Group for GID $gid already exists"
  fi
}

# Create numeric group if missing (best-effort)
ensure_group_for_gid "${HOST_GID}" "hostgroup"

# Create runner user if missing (use numeric group)
if ! id runner >/dev/null 2>&1; then
  log "Creating user runner uid=${HOST_UID} gid=${HOST_GID}"
  useradd -m -u "${HOST_UID}" -o -g "${HOST_GID}" -d /home/runner -s /bin/bash runner || true
else
  debug "User runner already exists"
fi

# Ensure home directory exists and ownership matches host UID/GID
mkdir -p /home/runner
chown "${HOST_UID}:${HOST_GID}" /home/runner || true

# Ensure /etc/passwd has a runner entry (defensive)
if ! getent passwd runner >/dev/null 2>&1; then
  log "Appending runner entry to /etc/passwd"
  printf 'runner:x:%s:%s::/home/runner:/bin/bash\n' "${HOST_UID}" "${HOST_GID}" >> /etc/passwd
fi

# If /etc/shadow is immutable, try to remove immutable flag (best-effort)
if command -v lsattr >/dev/null 2>&1; then
  if lsattr /etc/shadow 2>/dev/null | grep -q 'i'; then
    debug "/etc/shadow has immutable flag; attempting chattr -i"
    if command -v chattr >/dev/null 2>&1; then
      chattr -i /etc/shadow 2>/dev/null || true
    fi
  fi
fi

# Validate nsswitch shadow uses files first (best-effort)
if [ -f /etc/nsswitch.conf ]; then
  if ! grep -E '^shadow:\s*files' /etc/nsswitch.conf >/dev/null 2>&1; then
    log "Warning: /etc/nsswitch.conf does not prefer local shadow files; PAM may consult network sources"
    debug "nsswitch.conf content:"
    debug "$(sed -n '1,120p' /etc/nsswitch.conf 2>/dev/null || true)"
  fi
fi

# Prefer pwconv if available to sync passwd->shadow (silent)
if command -v pwconv >/dev/null 2>&1; then
  debug "Running pwconv to sync passwd->shadow"
  pwconv >/dev/null 2>&1 || true
fi

# Safely ensure runner has an explicit locked password field '!' only when necessary
# - Do not overwrite a non-empty password field
# - If the field is empty, set to '!' atomically
set_locked_shadow_for_runner() {
  local tmp
  tmp="$(mktemp /tmp/shadow.XXXXXX)" || tmp="/tmp/shadow.$$"
  if ! getent shadow runner >/dev/null 2>&1; then
    log "No shadow entry for runner; appending locked entry"
    printf 'runner:!:0:99999:7:::\n' >> /etc/shadow
    return 0
  fi

  # Extract runner line
  local line passfield
  line=$(getent shadow runner || true)
  passfield=$(printf '%s' "$line" | awk -F: '{print $2}')

  if [ -z "$passfield" ]; then
    log "Runner shadow password field is empty; locking it with '!'"
    # Create atomic replacement: only change runner line, leave others intact
    awk -F: -v OFS=: '
      $1=="runner" {
        if ($2=="") $2="!";
        print; next
      }
      { print }
    ' /etc/shadow > "$tmp" && mv "$tmp" /etc/shadow
  else
    debug "Runner shadow password field is non-empty; leaving unchanged"
  fi
}

# Run the shadow fix and ensure permissions
set_locked_shadow_for_runner
chown root:root /etc/shadow || true
chmod 600 /etc/shadow || true

# Ensure sudoers entry exists and is valid
if [ ! -f /etc/sudoers.d/runner ]; then
  log "Creating /etc/sudoers.d/runner for passwordless sudo"
  cat > /etc/sudoers.d/runner <<'EOF'
Defaults:runner !requiretty
runner ALL=(ALL) NOPASSWD: ALL
EOF
  chmod 0440 /etc/sudoers.d/runner
fi
# Validate sudoers fragment (non-fatal)
if ! visudo -c -f /etc/sudoers.d/runner >/dev/null 2>&1; then
  log "Warning: /etc/sudoers.d/runner failed visudo check"
fi

# Create KVM group for host KVM GID and add runner to it (guarded)
if [ -n "${HOST_KVM_GID}" ]; then
  debug "Ensuring KVM group for GID ${HOST_KVM_GID}"
  ensure_group_for_gid "${HOST_KVM_GID}" "kvm_host"
  # Add by GID: find group name for that GID
  kvm_group=$(getent group "${HOST_KVM_GID}" | cut -d: -f1 || true)
  if [ -n "$kvm_group" ]; then
    usermod -aG "$kvm_group" runner 2>/dev/null || true
  else
    debug "No group name found for GID ${HOST_KVM_GID}; skipping usermod"
  fi
fi

# Ensure runner is in wheel so sudo works on distros using wheel
if getent group wheel >/dev/null 2>&1; then
  usermod -aG wheel runner 2>/dev/null || true
fi

# Final non-fatal sanity checks (log warnings but continue)
if ! getent passwd runner >/dev/null 2>&1; then
  log "WARNING: runner missing passwd entry"
fi
if ! getent shadow runner >/dev/null 2>&1; then
  log "WARNING: runner missing shadow entry"
fi

# Helpful debug output if requested
if [ "${DEBUG:-0}" = "1" ]; then
  log "Post-entrypoint diagnostics:"
  log "UID/GID mapping: HOST_UID=${HOST_UID} HOST_GID=${HOST_GID} HOST_KVM_GID=${HOST_KVM_GID}"
  log "/etc/passwd runner line: $(getent passwd runner || true)"
  log "/etc/shadow runner line: $(getent shadow runner || true)"
  log "/etc/nsswitch.conf shadow line: $(grep '^shadow:' /etc/nsswitch.conf 2>/dev/null || true)"
  log "/dev/kvm: $(ls -l /dev/kvm 2>/dev/null || true)"
fi

# Close lock fd (flock will release on exit; closing fd here releases it now)
exec 9>&- || true

# Build a safe argv array and ensure we never exec with an empty argv
# Prefer explicit provided args; if none, default to an interactive login shell.
cmd=()
if [ "${#@}" -gt 0 ]; then
  # preserve positional args into array safely
  while [ "$#" -gt 0 ]; do
    cmd+=( "$1" )
    shift
  done
fi

if [ "${#cmd[@]}" -eq 0 ]; then
  cmd=(/bin/bash -il)
fi

# Log what we will run
log "Final exec command: ${cmd[*]}"

# If RUN_AS_ROOT=1 run as root, otherwise drop to runner with gosu/runuser/su fallback
if [ "${RUN_AS_ROOT:-0}" = "1" ]; then
  log "RUN_AS_ROOT=1; executing as root: ${cmd[*]}"
  exec "${cmd[@]}"
else
  log "Dropping to runner and executing: ${cmd[*]}"
  if command -v gosu >/dev/null 2>&1; then
    exec gosu runner "${cmd[@]}"
  elif command -v runuser >/dev/null 2>&1; then
    log "gosu missing; falling back to runuser"
    exec runuser -u runner -- "${cmd[@]}"
  elif command -v su >/dev/null 2>&1; then
    log "gosu/runuser missing; falling back to su"
    # Use su to run the command; wrap in a shell to preserve argv semantics
    # Build a safe quoted command string for su -c
    first="${cmd[0]}"
    rest=()
    for ((i=1;i<${#cmd[@]};i++)); do
      rest+=( "$(printf '%q' "${cmd[i]}")" )
    done
    exec su -s /bin/bash runner -c "exec $(printf '%q' "$first") ${rest[*]}"
  else
    log "ERROR: no gosu/runuser/su available to drop privileges; running as root"
    exec "${cmd[@]}"
  fi
fi
