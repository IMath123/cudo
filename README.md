# Cudo - Docker-based CUDA Development Environment Manager

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

A powerful command-line tool for managing CUDA development environments using Docker containers. Simplify your CUDA project setup and management with a single command.

## 🚀 Features

- **Docker-based Environments**: Isolated CUDA development environments using Docker containers
- **One-Click Setup**: Build CUDA environments with a single command
- **Global Management**: Track and monitor all your CUDA projects
- **Quick Container Entry**: Enter any named Cudo environment from any directory
- **Resource Monitoring**: Real-time CPU, memory, and GPU usage tracking
- **Conflict Resolution**: Smart handling of projects with identical names
- **Multi-Project Support**: Manage multiple CUDA projects simultaneously
- **Docker Integration**: Seamless integration with Docker and Docker Compose
- **Runtime SSH Access**: Password-authenticated SSH with no default listening port
- **GPU Selection**: Select all, no, or specific GPUs when starting an environment
- **Diagnostics and CI**: Built-in health checks plus automated fast tests

## 💡 Why Cudo?

Stop wrestling with complex Docker commands. Cudo simplifies your workflow significantly.

| Feature | Manual Docker Command | Cudo |
|---------|----------------------|------|
| **Build Environment** | `docker build -t my-env .` | `cudo build` |
| **Run Container** | `docker run --gpus all -it -v $(pwd):/workspace my-env` | `cudo run` |
| **GPU Setup** | Requires manual flag configuration | **Automatic** |
| **Volume Mounting** | Manual `-v` flag for every run | **Automatic** |
| **Project Tracking** | Manual bookkeeping | **Built-in Registry** |

### See the difference:

**Without Cudo:**
```bash
# Build (hope you have the right Dockerfile)
docker build -t my-cuda-project .

# Run (don't forget the flags!)
docker run --gpus all -it \
  --shm-size=8g \
  -v $(pwd):/workspace \
  -w /workspace \
  --name my-cuda-container \
  my-cuda-project
```

**With Cudo:**
```bash
# Build & Run
cudo build
cudo run
```


## 📋 Requirements

- **Docker** - Container runtime for environment isolation
- **Docker Compose** - Multi-container application management
- **NVIDIA Docker Runtime** - GPU access in containers
- **Python 3.6+** - For resource monitoring scripts
- **gettext (`envsubst`)** - Configuration template rendering
- **OpenSSL** - SHA-512 SSH password hashing


## 🛠️ Installation

For detailed installation instructions, please see the [INSTALL.md](INSTALL.md) file.

### One-Line Installation
```bash
# Install with a single command
curl -fsSL https://raw.githubusercontent.com/IMath123/cudo/master/get-cudo.sh | bash

# Test the installation
cudo --help
```

## 🎯 Quick Start

### 1. Create a new CUDA project
```bash
mkdir my-cuda-project
cd my-cuda-project
```

### 2. Build your CUDA environment
```bash
cudo build -c 11.8.0 -p 3.10
```

### 3. Run and enter the container
```bash
cudo run
```

### 4. View all your CUDA environments
```bash
cudo list
```

### 5. Enter the environment from anywhere
```bash
cudo enter my-cuda-project
```

## 📖 Usage

### Build Command
```bash
# Basic build with default settings
cudo build

# Custom CUDA and Python versions
cudo build -c 11.8.0 -p 3.8

# With CUDA Toolkit
cudo build -t

# Custom image name
cudo build -i my-custom-image

# Custom environment name for cudo enter
cudo build --name train
```

### Container Commands
```bash
# Start and enter container
cudo run

# Enter a named Cudo environment from any directory
cudo enter train

# Select an environment interactively
cudo enter

# Run a command inside a named environment
cudo enter train -- nvidia-smi

# Rename a Cudo environment
cudo rename train training

# Check container status
cudo status

# Start container
cudo start

# Start with selected GPUs; the selection is saved for later starts
cudo start --gpus 0,1

# Hide every GPU from the container
cudo start --gpus none

# Stop container
cudo stop

# Restart container
cudo restart

# Restore container to the last committed image state
cudo restore

# View logs
cudo logs

# Remove everything in current project (container, image, config)
cudo remove
```

`--gpus` accepts `all`, `none`, or comma-separated numeric device IDs such as `0,1`. It is supported by `run`, `start`, and `enter`. Changing it for a running environment recreates the container with the new visibility setting while preserving the project volume.

### SSH Commands

Every image built by Cudo contains the SSH server packages, but SSH is disabled until both a port and password are explicitly configured. There is no default SSH port.

```bash
# Enable SSH for the current project; the password is prompted without echo
cudo ssh enable --port 2222

# Show saved settings and whether sshd is currently listening
cudo ssh status

# Rotate the password using a hidden interactive prompt
cudo ssh passwd

# Disable SSH, stop sshd, and remove the saved password hash and port
cudo ssh disable

# Connect from another machine
ssh -p 2222 "$USER"@HOST
```

The existing runtime options remain available for `run`, `start`, and `enter`:

```bash
# Configure SSH while starting the current project
cudo start --ssh-port 2222

# Change the port of a named environment and enter it
cudo enter train --ssh-port 2223

# Read a password from standard input for automation
printf '%s\n' "$CUDO_SSH_PASSWORD" | \
  cudo run --ssh-port 2222 --ssh-password-stdin

# Read only the first line of a password file
cudo start --ssh-port 2222 --ssh-password-file /run/secrets/cudo-ssh
```

If no password has been saved, an interactive command prompts for one. Non-interactive commands must use `--ssh-password-stdin` or `--ssh-password-file`. The legacy `--ssh-password VALUE` option remains compatible, but it exposes the secret in shell history and process arguments and should not be used in new scripts.

Passwords are stored only as salted SHA-512 crypt hashes. Existing `SSH_PASSWORD_B64` configurations are migrated when SSH is next configured. Cudo validates the requested host port before startup; if it is occupied in an interactive terminal, Cudo asks for another. Startup and SSH configuration failures restore the previous SSH and GPU settings.

SSH uses the current host username inside the container. Password authentication is enabled only for that non-root user; root login, empty passwords, and public-key authentication are disabled by the generated Cudo SSH configuration.

### List Command
```bash
# Basic list
cudo list

# Detailed view with resource usage
cudo list --details

# GPU memory information
cudo list --gpu
```

### Cleanup Command
```bash
# Clean up deleted/moved project configurations
cudo cleanup
```

This command removes project configurations that are marked as deleted in the global registry, helping keep your environment list clean.

### Doctor Command
```bash
# Diagnose dependencies and the current project configuration
cudo doctor

# Check every registered environment
cudo doctor --all

# Machine-readable output for automation
cudo doctor --all --json
```

This command only reports `PASS`, `WARN`, and `FAIL` checks. It does not modify your environment.

`doctor` checks Docker, Compose, the NVIDIA runtime, required host tools, global configuration access, the current image and container, SSH configuration, SSH runtime state, and GPU selection. `--all` also checks every environment in the global registry. `--json` returns an object with `failures`, `warnings`, and `checks`; the command exits non-zero when any `FAIL` check is present.

## 🔧 Command Options

### Build Options

| Option | Description | Default |
|---|---|---|
| `-c, --cuda-version` | CUDA version | 12.4.0 |
| `-u, --ubuntu-version` | Ubuntu version | 20.04 |
| `-t, --with-toolkit` | Include CUDA Toolkit | false |
| `-p, --python-version` | Python version | 3.10 |
| `-i, --image-name` | Custom image name | auto-generated |
| `-n, --name` | Environment name for `cudo enter` | project directory name |

### Runtime Options

These options apply to `run`, `start`, and `enter`.

| Option | Description | Default |
|---|---|---|
| `--ssh-port` | Runtime SSH port for `run`, `start`, or `enter` | unset |
| `--ssh-password-stdin` | Read the SSH password from standard input | unset |
| `--ssh-password-file FILE` | Read the first line of a password file | unset |
| `--ssh-password VALUE` | Deprecated plaintext argument | unset |
| `--gpus` | Visible GPUs: `all`, `none`, or device IDs such as `0,1` | all |

### SSH Subcommands

| Command | Effect |
|---|---|
| `cudo ssh enable --port PORT` | Save SSH settings and start the container |
| `cudo ssh status` | Show configuration and runtime listening state |
| `cudo ssh passwd` | Replace the saved password hash |
| `cudo ssh disable` | Stop sshd and remove SSH runtime settings |

## 📊 Example Output

### List Command Output
```
CUDA Environment List
NAME        CUDA    UBUNTU  PYTHON  STATUS     SSH   PATH
my-project  11.8.0  20.04   3.10    Running    2222  /home/user/projects/my-project
test-env    12.4.0  20.04   3.10    Stopped    -     /home/user/projects/test-env

Statistics:
  Total environments: 2
  Running: 1
```

## 🏗️ Project Structure

```
.cudo/                       # Docker configuration for project
├── Dockerfile               # Generated Dockerfile with CUDA support
├── docker-compose.yml       # Docker Compose configuration
├── cudo-entrypoint.sh       # Container startup and SSH configuration
└── config                   # Project settings

/var/lib/cudo-global/        # Global configuration (multi-user support)
└── *.conf                  # Project metadata files
```

## 🔍 How It Works

1. **Docker Image Building**: Generates optimized Dockerfile with CUDA support
2. **Container Orchestration**: Uses Docker Compose for lifecycle management
3. **Volume Mounting**: Maps project directories into containers
4. **GPU Access**: Persists GPU visibility and configures the NVIDIA runtime
5. **Global Tracking**: Stores project metadata in `/var/lib/cudo-global/`
6. **Resource Monitoring**: Integrates with Docker stats and NVIDIA tools
7. **Runtime SSH Access**: Starts `sshd` only after an explicit port and password are configured
8. **Safe Configuration Loading**: Parses and validates known fields without executing the config as shell code

## 🐛 Troubleshooting

### Common Issues

**Docker not found**
```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

**NVIDIA Docker not working**
```bash
# Install NVIDIA Docker
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt-get update && sudo apt-get install -y nvidia-docker2
sudo systemctl restart docker
```

**Permission denied**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Log out and log back in
```

**Environment is broken (image missing)**
```bash
# This happens when the Docker image was deleted but the project still exists
# Simply rebuild the environment:
cudo build
```

**SSH does not start**
```bash
# Check the saved port, hash format, entrypoint, and running sshd process
cudo doctor
cudo ssh status

# Reconfigure SSH interactively
cudo ssh disable
cudo ssh enable --port 2222
```

**SSH port is already occupied**
```bash
# Pick an available port; interactive commands will also prompt for another
cudo start --ssh-port 2223
```

**Use only selected GPUs**
```bash
cudo start --gpus 0,1

# Confirm the saved selection and NVIDIA runtime
cudo doctor
```

**Too many deleted projects in list**
```bash
# Clean up deleted/moved project configurations
cudo cleanup
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- NVIDIA for CUDA and Docker images
- Docker community for excellent container tools
- All contributors who help improve this tool

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/IMath123/cudo/issues)
- **Discussions**: [GitHub Discussions](https://github.com/IMath123/cudo/discussions)
- **Email**: imatphy@gmail.com

---

**Made with ❤️ for the CUDA development community using Docker containers**
