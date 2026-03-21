#!/bin/bash
set -euo pipefail
trap '' PIPE

function vendor_collection() {
    local URL="$1"
    local DEST="$2"

    # DEST is like "ansible/windows"
    local NS=$(echo "$DEST" | cut -d/ -f1)
    local COL=$(echo "$DEST" | cut -d/ -f2)

    # Correct Ansible collection path
    local TARGET="collections/ansible_collections/$NS/$COL"

    mkdir -p "$TARGET"

    local BALL_NAME="${NS}.${COL}.tar.gz"

    curl -sSL "$URL" -o "$BALL_NAME"

    # Detect top-level folder quietly
    local COUNT
    COUNT=$(tar -tzf "$BALL_NAME" 2>/dev/null | awk -F/ '{print $1}' | sort -u | wc -l)

    if [[ "$COUNT" -eq 1 ]]; then
        tar -xzf "$BALL_NAME" -C "$TARGET" --strip-components=1 >/dev/null 2>&1
    else
        tar -xzf "$BALL_NAME" -C "$TARGET" >/dev/null 2>&1
    fi

    cat >> requirements.yml <<EOF
  - name: $TARGET
    type: dir
EOF
}

# Clean vendor tree
rm -rf collections
mkdir -p collections/ansible_collections

# Start requirements.yml
cat >> requirements.yml <<EOF
collections:
EOF

# Versions
vendor_collection "https://github.com/ansible-collections/community.proxmox/archive/refs/tags/1.5.0.tar.gz" "community/proxmox"
vendor_collection "https://github.com/ansible-collections/ansible.utils/archive/refs/tags/v6.0.1.tar.gz" "ansible/utils"
vendor_collection "https://github.com/ansible-collections/ansible.posix/archive/refs/tags/2.1.0.tar.gz" "ansible/posix"
vendor_collection "https://github.com/ansible-collections/community.general/archive/refs/tags/12.4.0.tar.gz" "community/general"
vendor_collection "https://github.com/oVirt/ovirt-ansible-collection/releases/download/3.2.2-1/ovirt-ovirt-3.2.2.tar.gz" "ovirt/ovirt"
vendor_collection "https://github.com/ansible-collections/ansible.windows/archive/refs/tags/3.5.0.tar.gz" "ansible/windows"


find collections -type d
cat requirements.yml

echo "Vendoring complete."
