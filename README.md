# Ansible Collection - gocallag.templates

## BETA Testing, don't use at the moment.

Documentation for the collection.

The easiest way to use this collection is as follows:

1. Build the container
```
docker build -t imagebuilder . 
```
2. Run the container
```
docker run -it --privileged --device=/dev/kvm --rm -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) -v /home/gocallag/.template_builder/env.sh:/home/runner/.template_builder/env.sh -v /home/gocallag/build:/tmp/build -v ./samples:/home/runner/samples -p 5900:5900  imagebuilder:latest /bin/bash
```

Note: The env.sh file has a bunch of configuration settings, some examples below

```
IMAGEBUILDER_ENV_QEMU_IP=localhost
IMAGEBUILDER_ENV_BUILD_PATH=/tmp/build
IMAGEBUILDER_ENV_BUILD_MEMORY=8192
IMAGEBUILDER_ENV_BUILD_CPU=4
IMAGEBUILDER_ENV_ANSIBLE_USER=<user to use as part of the build process for ansible>
IMAGEBUILDER_ENV_ANSIBLE_PASSWORD=<password to be set in template for ansible>
IMAGEBUILDER_ENV_LINUX_ADMIN_USER=root
IMAGEBUILDER_ENV_LINUX_ADMIN_PASSWORD=<password for linux admin in the new image>
IMAGEBUILDER_ENV_WIN_ADMIN_USER=Administrator
IMAGEBUILDER_ENV_WIN_ADMIN_PASSWORD=<password for the Administrator account in windows systems>
IMAGEBUILDER_ENV_ANSIBLE_KEY="ssh-ed25519 <ssh pub key >"
```