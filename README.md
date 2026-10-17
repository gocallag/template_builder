# Image Builder

An Ansible collection and container-based harness for building images.

> **Beta:** This project is under active testing.

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
ib phase <phase> <image> [--follow]
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
./ib phase cleanup samples/alma-8
./ib phase uplift samples/alma-8
./ib phase patch samples/alma-8 --follow

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

## Configuration

The harness reads `~/.template_builder/config.yml` on the host and mounts it at
`/root/.template_builder/config.yml` in the container. Add any callback or other
Ansible plugins used by the build to `~/.template_builder/plugins`; that
directory is mounted at `/plugins`.

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
