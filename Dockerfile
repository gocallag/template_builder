# Single-stage image with build and runtime tools using an isolated venv
FROM fedora:40
LABEL maintainer="geoffocallaghan@gmail.com"

ENV DEBIAN_FRONTEND=noninteractive
ENV LIBGUESTFS_BACKEND=direct
ENV LANG=C.UTF-8
ENV VENV_PATH=/opt/venv
ENV PATH="${VENV_PATH}/bin:${PATH}"

# Install system packages including QEMU, libguestfs, build tools and utilities
RUN dnf -y update && \
    dnf install -y \
      dnf-plugins-core \
      libguestfs-tools-c \
      libguestfs-tools \
      libguestfs-appliance \
      supermin \
      qemu-kvm \
      qemu-system-x86 \
      qemu-img \
      dracut \
      python3 \
      python3-virtualenv \
      python3-devel \
      gcc gcc-c++ make \
      git \
      jq \
      tar gzip \
      sudo \
      curl \
      xorriso \
      nbdkit \
      genisoimage \
      ipxe-bootimgs \
      vim \
      libxml2-devel \
      libxslt-devel \
      sshpass \
    && dnf clean all

# Create an isolated venv for Python tooling and put it on PATH
RUN python3 -m venv ${VENV_PATH} && \
    ${VENV_PATH}/bin/pip install --upgrade pip setuptools wheel

# Install build-time Python requirements into the venv (if provided)
COPY requirements.txt /tmp/requirements.txt
RUN if [ -f /tmp/requirements.txt ]; then \
      ${VENV_PATH}/bin/pip install --no-cache-dir -r /tmp/requirements.txt && rm -f /tmp/requirements.txt; \
    fi

# Install ansible tooling into the venv and verify
RUN ${VENV_PATH}/bin/pip install --no-cache-dir --upgrade ansible-core ansible-runner && \
    ${VENV_PATH}/bin/ansible-galaxy --version && ${VENV_PATH}/bin/ansible-runner --version

# Install gosu for privilege drop at runtime
RUN curl -fsSL https://github.com/tianon/gosu/releases/download/1.17/gosu-amd64 -o /usr/local/bin/gosu && \
    chmod +x /usr/local/bin/gosu && /usr/local/bin/gosu --version || true

# Install govc CLI for vSphere automation
RUN set -eux; \
    curl -fsSL -o /tmp/govc.tar.gz \
      https://github.com/vmware/govmomi/releases/latest/download/govc_Linux_x86_64.tar.gz && \
    tar -C /usr/local/bin -xzf /tmp/govc.tar.gz govc && \
    chmod +x /usr/local/bin/govc && \
    rm -f /tmp/govc.tar.gz && \
    govc version

# Copy repository and build the collection tarball using the venv ansible-galaxy
COPY . /tmp/build/
WORKDIR /tmp/build
RUN ${VENV_PATH}/bin/ansible-galaxy collection build -f . && \
    mv gocallag-template_builder-*.tar.gz /tmp/gocallag-collection.tar.gz || true

# Install the built collection into the venv-managed ansible environment
RUN if [ -f /tmp/gocallag-collection.tar.gz ]; then \
      ${VENV_PATH}/bin/ansible-galaxy collection install /tmp/gocallag-collection.tar.gz || true; \
    fi

# Validate libguestfs appliances early, best-effort
RUN if command -v libguestfs-test-tool >/dev/null 2>&1; then \
      libguestfs-test-tool --version || (echo "libguestfs-test-tool failed; appliances may be missing" && false); \
    else \
      echo "libguestfs-test-tool not found; skipping appliance self-test"; \
    fi

# Copy entrypoint and make executable (ensure entrypoint uses PATH or explicit venv binaries)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create a default runner user at build time to reduce runtime surprises
RUN groupadd -g 1001 runner || true && \
    useradd -m -u 1001 -g 1001 -s /bin/bash runner || true

RUN mv /usr/bin/passt /usr/bin/passt.disabled

# Working directory and default entrypoint
WORKDIR /root
# ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash","-il"]

EXPOSE 5900-5910
