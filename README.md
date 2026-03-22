# Ansible Collection - gocallag.templates

## BETA Testing, don't use at the moment.

Documentation for the collection.

## Development Setup with Devcontainer

This project includes a devcontainer configuration for a consistent development environment using Docker and VS Code.

### Prerequisites

Before getting started, ensure you have the following installed:

- **Docker**: Install from [docker.com](https://docs.docker.com/get-docker/)
- **VS Code**: Install from [code.visualstudio.com](https://code.visualstudio.com/)
- **Remote Containers Extension**: Install the "Dev Containers" extension by Microsoft in VS Code (ms-azuretools.vscode-containers)

### Quick Start

1. **Open the project in a devcontainer**:
   - Open the workspace folder in VS Code
   - Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on macOS) to open the command palette
   - Type and select **"Dev Containers: Reopen in Container"**
   - VS Code will build and start the devcontainer (this may take a few minutes on first run)

2. **Verify the environment**:
   - Once the container starts, open an integrated terminal in VS Code
   - Verify Ansible is available: `ansible --version`
   - Verify Python is available: `python --version`

### Devcontainer Configuration

The devcontainer includes:

- **Python 3.11**: Base runtime environment
- **Ansible Core**: Pre-installed and ready to use
- **Required Dependencies**: All Python packages from `requirements.txt`
- **Ansible Roles**: Automatically installed from `requirements.yml`
- **Docker Access**: Mounted `/var/run/docker.sock` for Docker-in-Docker capability
- **Execution Environment**: This Dockerfile creates a container that can be used as an Execution Environment in AWX/AAP
- **Vendored scripts**: This Dockerfile uses vendored versions of ansible modules rather than ansible galaxy directly due to issues with ansible-galaxy.

### Environment Configuration

If your development requires credentials or environment variables (e.g., cloud credentials, API tokens), create a credentials file:

1. Create the credentials directory in your home directory:
   ```bash
   mkdir -p ~/.template_builder
   ```

2. Create a `credentials.sh` file with your environment variables:
   ```bash
   # ~/.template_builder/credentials.sh
   CLOUD_API_KEY="your-api-key"
   VAULT_ADDR="https://vault.example.com"
   # Add other required environment variables
   ```

3. Make it readable (the devcontainer will source this automatically):
   ```bash
   chmod 600 ~/.template_builder/credentials.sh
   ```

The credentials file is automatically mounted and sourced in the container startup.

### Working in the Devcontainer

- **Terminal**: Use the integrated terminal in VS Code to run Ansible commands
- **File Editing**: All files are editable directly from VS Code (changes sync with the container)
- **Extension Support**: The devcontainer is configured with recommended VS Code extensions
- **Debugging**: Debug Ansible playbooks and Python scripts using VS Code's debugging features
- **Supports remote execution**: This devcontainer can be used via remote ssh connection with the appropriate vscode extension installed

### Rebuilding the Devcontainer

If you make changes to the `Dockerfile` or dependency files:

1. Press `Ctrl+Shift+P` and select **"Dev Containers: Rebuild Container"**
2. Or remove the container and reopen: **"Dev Containers: Reopen in Container"**

### Exiting the Devcontainer

To return to working on your local machine:

- Press `Ctrl+Shift+P` and select **"Dev Containers: Reopen Folder Locally"**

### Troubleshooting

- **Docker not running**: Ensure Docker is running before opening the devcontainer
- **Port conflicts**: If the container fails to start, check for port conflicts or resource constraints
- **Extension installation**: Some extensions may need to be reinstalled in the container—VS Code will prompt you
- **Credential file not found**: Verify the `~/.template_builder/credentials.sh` file exists and is readable. This file is passed as env-vars to the devcontainer runtime.
