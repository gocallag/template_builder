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
        curl sudo python3 python3-dev python3-pip python3-setuptools gcc g++ ca-certificates build-essential software-properties-common gosu
RUN rm -f /tmp/bindep.txt

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

COPY . /tmp/build/
RUN cd /tmp/build && ansible-galaxy collection build -f .
RUN cd /tmp/build && ansible-galaxy collection install gocallag-template_builder*.tar.gz
RUN rm -rf /tmp/build

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
WORKDIR /home/runner
CMD ["/bin/bash"]

