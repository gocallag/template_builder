#!/bin/bash
set -e

HOST_UID=${HOST_UID:-1000}
HOST_GID=${HOST_GID:-1000}
HOST_KVM_GID=$(stat -c "%g" /dev/kvm)

# Create host group if needed
if ! getent group ${HOST_GID} >/dev/null; then
    groupadd -g ${HOST_GID} hostuser
fi

# Create runner user dynamically
if ! id runner >/dev/null 2>&1; then
    useradd -u ${HOST_UID} -g ${HOST_GID} -d /home/runner -s /bin/bash runner
fi

# Ensure home directory exists
mkdir -p /home/runner
chown ${HOST_UID}:${HOST_GID} /home/runner  

# Create kvm group if needed
if ! getent group ${HOST_KVM_GID} >/dev/null; then
    groupadd -g ${HOST_KVM_GID} kvm_host
fi

# Add runner to kvm group
usermod -aG ${HOST_KVM_GID} runner

# Exec as runner with proper TTY handling
exec gosu runner "$@"

