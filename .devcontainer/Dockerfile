# -------------------------
# Stage 1: builder
# Uses a public Ansible-ready image to prepare vendored collections and roles
# -------------------------
FROM python:3.11-slim AS builder
WORKDIR /tmp/ee

# Ensure basic OS utilities required by vendor.sh (curl/tar) are available
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates tar gzip unzip git; \
    rm -rf /var/lib/apt/lists/*;

# Copy the EE directory from the build context into the builder stage.
# When building from the repository root: docker build -f ee/Dockerfile .
COPY . /tmp/ee/
RUN mkdir -p /tmp/ansible_roles

# Ensure ansible-galaxy is available; some runner images include it, but install ansible-core if missing
RUN set -eux; \
        pip3 install --no-cache-dir ansible-core

# Run vendor script (if present) then install roles from requirements.yml only
RUN set -eux; \
    [ -f /tmp/ee/vendor.sh ] && chmod +x /tmp/ee/vendor.sh && /bin/bash /tmp/ee/vendor.sh || true; \
    if [ -f /tmp/ee/requirements.yml ]; then \
      ansible-galaxy role install -r /tmp/ee/requirements.yml --roles-path /tmp/ansible_roles; \
    fi

# -------------------------
# Stage 2: runtime image (based on existing Ubuntu layout)
# -------------------------
FROM ubuntu:24.04
LABEL maintainer=geoffocallaghan@gmail.com
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

# Install system deps
COPY bindep.txt /tmp/bindep.txt
RUN apt-get update && \
    apt-get install -y locales && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 && \
    apt-get install -y --no-install-recommends \
        $(grep -vE '^\s*#' /tmp/bindep.txt | tr '\n' ' ') \
        curl sudo python3 python3-dev python3-pip python3-setuptools gcc g++ ca-certificates build-essential software-properties-common
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*


 # ------------------------------------------------------------
# 2. Install ansible-core + ansible-runner
# ------------------------------------------------------------
RUN pip3 install --break-system-packages --no-cache-dir \
    ansible-core \
    ansible-runner

# ------------------------------------------------------------
# 3. Install Python dependencies
# ------------------------------------------------------------
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --break-system-packages --no-cache-dir -r /tmp/requirements.txt

# ------------------------------------------------------------
# Install the Ansible Language Server (Node-based)
# ------------------------------------------------------------
RUN npm install -g @ansible/ansible-language-server

# ------------------------------------------------------------
# 4. Install vendored Ansible collections (from builder)
# ------------------------------------------------------------
# Copy collections prepared by the builder's vendor.sh into the runtime image
COPY --from=builder /tmp/ee/collections/ansible_collections/ /usr/share/ansible/collections/ansible_collections/
RUN chmod -R 755 /usr/share/ansible/collections || true

# Copy roles installed by the builder stage
COPY --from=builder /tmp/ansible_roles/ /usr/share/ansible/roles/
RUN chown -R 1001:0 /usr/share/ansible/roles || true && chmod -R 755 /usr/share/ansible/roles || true

# ------------------------------------------------------------
# 5. Create roles directory (AWX expects it)
# ------------------------------------------------------------
RUN mkdir -p /usr/share/ansible/roles && \
    chown -R 1000:0 /usr/share/ansible/roles && \
    chmod -R 755 /usr/share/ansible/roles

# ------------------------------------------------------------
# 6. Environment variables for AWX
# ------------------------------------------------------------
ENV ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections
ENV ANSIBLE_ROLES_PATH=/usr/share/ansible/roles
ENV ANSIBLE_LIBRARY=/usr/share/ansible/collections

# ------------------------------------------------------------
# 7. Ensure /runner exists and is writable by the AWX execution user
# ------------------------------------------------------------
RUN mkdir -p /runner && \
    chown -R 1001:0 /runner && \
    chmod -R 755 /runner 


# ------------------------------------------------------------
# 8. Create a passwd entry for UID 1000
#    Required for SSH-based local connections and the ability to run sudo
# ------------------------------------------------------------
RUN echo "runner:x:1001:0:Ansible Runner:/runner:/usr/sbin/nologin" >> /etc/passwd

# Grant the `runner` user passwordless sudo access
RUN echo 'runner ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/runner && \
    chmod 0440 /etc/sudoers.d/runner
RUN usermod -p '!' runner || true
RUN usermod -aG 994 runner || true

COPY ansible.cfg /etc/ansible/ansible.cfg

USER 1001

