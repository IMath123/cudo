# Cudo - Docker-based CUDA Development Environment Manager

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

A powerful command-line tool for managing CUDA development environments using Docker containers. Simplify your CUDA project setup and management with a single command.

## 🚀 Features

- **Docker-based Environments**: Isolated CUDA development environments using Docker containers
- **One-Click Setup**: Build CUDA environments with a single command
- **Global Management**: Track and monitor all your CUDA projects
- **Resource Monitoring**: Real-time CPU, memory, and GPU usage tracking
- **Conflict Resolution**: Smart handling of projects with identical names
- **Multi-Project Support**: Manage multiple CUDA projects simultaneously
- **Docker Integration**: Seamless integration with Docker and Docker Compose
- **Customizable**: Flexible configuration for CUDA versions, Python versions, and more


## 📋 Requirements

- **Docker** - Container runtime for environment isolation
- **Docker Compose** - Multi-container application management
- **NVIDIA Docker Runtime** - GPU access in containers
- **Python 3.6+** - For resource monitoring scripts


## 🛠️ Installation

For detailed installation instructions, please see the [INSTALL.md](INSTALL.md) file.

### Quick Start (Recommended)
```bash
# Clone the repository
git clone https://github.com/IMath123/cudo.git
cd cudo

# Install locally (recommended for single user)
./install.sh local

# Test the installation
cudo --help
```

### System-wide Installation
```bash
# Clone the repository
git clone https://github.com/IMath123/cudo.git
cd cudo

# Install system-wide (requires sudo)
./install.sh system

# Test the installation
cudo --help
```

### Manual Installation
If you prefer manual installation, see [INSTALL.md](INSTALL.md) for step-by-step instructions.

## 🎯 Quick Start

### 1. Create a new CUDA project
```bash
mkdir my-cuda-project
cd my-cuda-project
```

### 2. Build your CUDA environment
```bash
./cudo build -c 11.8.0 -p 3.10
```

### 3. Run and enter the container
```bash
./cudo run
```

### 4. View all your CUDA environments
```bash
./cudo list
```

## 📖 Usage

### Build Command
```bash
# Basic build with default settings
cudo build

# Custom CUDA and Python versions
cudo build -c 11.8.0 -p 3.8

# With CUDA Toolkit
cudo build -t true

# Custom image name
cudo build -i my-custom-image
```

### Run Command
```bash
# Start and enter container
cudo run

# Check container status
cudo status

# Start container
cudo start

# Stop container
cudo stop

# View logs
cudo logs

# Remove everything in current dir
cudo remove
```

### List Command
```bash
# Basic list
cudo list

# Detailed view with resource usage
cudo list --details

# GPU memory information
cudo list --gpu
```

## 🔧 Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `-c, --cuda-version` | CUDA version | 12.4.0 |
| `-u, --ubuntu-version` | Ubuntu version | 20.04 |
| `-t, --with-toolkit` | Include CUDA Toolkit | false |
| `-p, --python-version` | Python version | 3.10 |
| `-i, --image-name` | Custom image name | auto-generated |

## 📊 Example Output

### List Command Output
```
CUDA Environment List
PROJECT     CUDA    UBUNTU  PYTHON  STATUS     PATH
my-project  11.8.0  20.04   3.10    Running    /home/user/projects/my-project
test-env    12.4.0  20.04   3.10    Stopped    /home/user/projects/test-env

Statistics:
  Total environments: 2
  Running: 1
  System memory: 503Gi
```

## 🏗️ Project Structure

```
.cuda-docker-config/          # Docker configuration for project
├── Dockerfile               # Generated Dockerfile with CUDA support
├── docker-compose.yml       # Docker Compose configuration
└── config                   # Project settings

~/.cudo-global/              # Global configuration
└── *.conf                  # Project metadata files
```

## 🔍 How It Works

1. **Docker Image Building**: Generates optimized Dockerfile with CUDA support
2. **Container Orchestration**: Uses Docker Compose for lifecycle management
3. **Volume Mounting**: Maps project directories into containers
4. **GPU Access**: Configures NVIDIA runtime for GPU acceleration
5. **Global Tracking**: Stores project metadata in `~/.cudo-global/`
6. **Resource Monitoring**: Integrates with Docker stats and NVIDIA tools

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

- **Issues**: [GitHub Issues](https://github.com/yourusername/cudo/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/cudo/discussions)
- **Email**: imatphy@gmail.com

---

**Made with ❤️ for the CUDA development community using Docker containers**