# Image Builder

An Ansible collection and container-based harness for building images.

## Getting started

Build the container image:

```bash
docker build -t imagebuilder .
```

Create the host configuration directory and add your Image Builder configuration:

```bash
mkdir -p ~/.template_builder/plugins ~/build
# Create ~/.template_builder/config.yml with your build configuration.
```

From the repository root, build an image and follow task progress:

```bash
./ib build samples/win2022 --follow
```

The harness mounts `~/.template_builder/config.yml`, `~/.template_builder/plugins`,
`~/build`, and the repository's `samples` directory into the container. The image
playbook is selected by appending `.yml` to the image argument.

## Commands

```text
ib build <image> [--follow] [--verbose]
ib phase <phase> <image> [--follow] [--patch-from base|latest]
ib validate <image>
ib inspect <image>

ib ps
ib status <jobid>
ib follow <jobid>
ib stop <jobid>
ib clean <jobid>
ib rm <jobid>
```

Examples:

```bash
# Build an image
./ib build samples/win2022

# Build and display task progress as it runs
./ib build samples/win2022 --follow

# Run an individual phase
./ib phase base samples/alma-8
./ib phase patch samples/alma-8 --follow
./ib phase patch samples/alma-8 --patch-from base

# Check and follow a detached job
./ib ps
./ib status 8c37028431d7
./ib follow 8c37028431d7

# Stop or remove a job
./ib stop 8c37028431d7
./ib clean 8c37028431d7
```

`ib follow` displays each task's start time, result, and elapsed time. Successful
tasks have a green check, failed or unreachable tasks have a red cross, and
skipped tasks have a dash. The complete JSON event stream, including event types
not shown in the task display, is retained in `~/build/jobs/<jobid>.ndjson`.
Job metadata is stored in `~/build/jobs/<jobid>.meta`. `ib clean` and `ib rm`
remove the job's container and both files.

`ib validate <image>` runs an Ansible syntax check for the image playbook.
`ib inspect <image>` prints the playbook path.

`ib phase base` creates a new immutable base artifact. `ib phase patch` creates
a new patched generation from the latest patched artifact by default; use
`--patch-from base` to start from the latest base artifact instead. Each patched
generation records its parent artifact.

`ib build` is the end-to-end flow: it uses the latest patched artifact, or
creates a base and patches it if only a base (or no artifact) is available,
then runs the configured target plugins. Targets perform their own platform
uplift, generic hardening, template cleanup, and publication. Target processing
uses a working copy and does not modify the source artifact in the library.

## Configuration

The harness reads `~/.template_builder/config.yml` on the host and mounts it at
`/root/.template_builder/config.yml` in the container. Add any callback or other
Ansible plugins used by the build to `~/.template_builder/plugins`; that
directory is mounted at `/plugins`.

RHEL 8, 9, and 10 patching and target uplift require Red Hat Subscription
Management credentials in the configuration:

```yaml
credentials:
  rhsm:
    username: your-rhsm-username
    password: your-rhsm-password
```

The build files are available under `~/build` on the host and at `/tmp/build` in
the container. Job metadata and the raw JSON event streams are stored in
`~/build/jobs`.

## Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `IMAGEBUILDER_IMAGE` | `imagebuilder:latest` | Container image used to execute builds. |
| `CONTAINER_RUNTIME` | `docker` | Container runtime (`docker` or `podman`). |
| `IB_VNC_PORT_START` | `5900` | First host port considered for VNC. |
| `IB_VNC_PORT_END` | `5999` | Last host port considered for VNC. |

The `ib` script uses the current directory's `samples` folder and expects you
to run it from the repository root.
