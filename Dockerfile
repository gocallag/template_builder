FROM debian:12
LABEL maintainer="geoffocallaghan"

ENV DEBIAN_FRONTEND=noninteractive

# Core system + Python + Ansible dependencies
RUN apt-get update && apt-get install -y \
    qemu-system-x86 \
    qemu-utils \
    qemu-kvm \
    libguestfs-tools \
    supermin \
    linux-image-amd64 \
    dracut \
    python3 \
    python3-pip \
    python3-venv \
    sshpass \
    ca-certificates \
    sshpass \
    git \
    jq \
    tar \
    gzip \
    sudo \
    openssh-client \
    libxml2-dev \
    libxslt1-dev \
    genisoimage \
    ipxe-qemu \
    qemu-system-common \ 
    qemu-system-data \
    xorriso \
    libnbd-bin \ 
    nbdkit \
    guestfish \
    curl \
    python3-dev  python3-setuptools gcc g++  build-essential software-properties-common gosu

# Install ansible-core + ansible-runner
RUN pip3 install --break-system-packages --no-cache-dir \
    ansible-core \
    ansible-runner

# Install Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --break-system-packages --no-cache-dir -r /tmp/requirements.txt
RUN rm -f /tmp/requirements.txt

# Grant the `runner` user passwordless sudo access
RUN echo 'runner ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/runner && \
    chmod 0440 /etc/sudoers.d/runner
RUN mkdir -p /home/runner && chown root:root /home/runner

ENV ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections
ENV ANSIBLE_ROLES_PATH=/usr/share/ansible/roles
ENV ANSIBLE_LIBRARY=/usr/share/ansible/collections
# Required for libguestfs inside containers
ENV LIBGUESTFS_BACKEND=direct

COPY . /tmp/build/
RUN cd /tmp/build && ansible-galaxy collection build -f .
RUN cd /tmp/build && ansible-galaxy collection install gocallag-template_builder*.tar.gz
RUN rm -rf /tmp/build
COPY proxmox.yml /home/runner/proxmox.yml

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
WORKDIR /home/runner
CMD ["/bin/bash"]

EXPOSE 5900-5910