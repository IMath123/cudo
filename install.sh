#!/bin/bash

# Cudo - CUDA Development Environment Manager Installation Script
# Installs system-wide as root, or for the current user otherwise.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}$1${NC}"; }
log_success() { echo -e "${GREEN} $1${NC}"; }
log_warning() { echo -e "${YELLOW}$1${NC}"; }
log_error() { echo -e "${RED}$1${NC}"; }

# Check OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    log_error "Error: macOS is not supported."
    log_error "Cudo is designed for Linux environments with NVIDIA GPUs and Docker."
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

log_info "Installing Cudo - CUDA Development Environment Manager..."

# Install Docker
install_docker() {
    log_info "Docker is not installed. Installing Docker..."
    echo "This will run: curl -fsSL https://get.docker.com | sh"
    read -p "Do you want to continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Installation aborted by user."
        return 1
    fi

    if curl -fsSL https://get.docker.com | sh; then
        log_success "Docker installed successfully."
        # Add current user to docker group if sudo is available
        if [ -n "$SUDO_USER" ]; then
            usermod -aG docker "$SUDO_USER"
            log_info "Added user $SUDO_USER to docker group."
        fi
        systemctl start docker
        systemctl enable docker
        return 0
    else
        log_error "Failed to install Docker."
        return 1
    fi
}

# Install NVIDIA Docker
install_nvidia_docker() {
    log_info "NVIDIA Docker is not installed. Installing NVIDIA Docker..."
    read -p "Do you want to continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Installation aborted by user."
        return 1
    fi

    # Detect distribution
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        distribution=$ID$VERSION_ID
    else
        log_error "Could not detect OS distribution."
        return 1
    fi

    log_info "Detected distribution: $distribution"
    
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
    
    apt-get update
    if apt-get install -y nvidia-docker2; then
        systemctl restart docker
        log_success "NVIDIA Docker installed successfully."
        return 0
    else
        log_error "Failed to install NVIDIA Docker."
        return 1
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    if ! command -v docker &> /dev/null; then
        if [ "$EUID" -ne 0 ]; then
            log_warning "Docker is missing; ask your administrator to install it before using cudo."
        elif ! install_docker; then
            log_error "Docker is required but could not be installed."
            return 1
        fi
    fi
    
    # Check for docker-compose (v1 or v2)
    if ! command -v docker-compose &> /dev/null && ! (command -v docker &> /dev/null && docker compose version &> /dev/null); then
        # Docker Compose V2 is usually included in modern Docker installation
        # If still missing, we could try to install it, but let's stick to core Docker for now
        # or assume 'docker compose' works if docker is installed via get-docker.com
        if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
             log_warning "Docker Compose not found. It might be available as 'docker compose'."
        fi
    fi
    
    # Check for NVIDIA Docker (nvidia-smi check inside container or check for runtime)
    # Simple check: look for nvidia-container-runtime or try to run a test container?
    # Better: check if /etc/docker/daemon.json contains nvidia runtime or check packages
    if ! dpkg -l | grep -q nvidia-docker2 && ! dpkg -l | grep -q nvidia-container-toolkit; then
         if [ "$EUID" -ne 0 ]; then
            log_warning "NVIDIA Container Toolkit is missing; ask your administrator to install it for GPU support."
         elif ! install_nvidia_docker; then
            log_error "NVIDIA Docker is required for GPU support but could not be installed."
            return 1
         fi
    fi

    if ! command -v python3 &> /dev/null; then
        missing+=("python3")
    fi
    if ! command -v nvidia-smi &> /dev/null; then
        missing+=("nvidia-smi")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo "Please install the following software:"
        for dep in "${missing[@]}"; do
            case $dep in
                "python3")
                    echo "  Python 3:"
                    echo "    Ubuntu/Debian: sudo apt-get install python3"
                    echo "    CentOS/RHEL: sudo yum install python3"
                    ;;
                "nvidia-smi")
                    echo "  NVIDIA driver tools: install a compatible NVIDIA driver on the host"
                    ;;
            esac
        done
        return 1
    fi
    return 0
}

# Install using the privileges of the current process; never invoke sudo.
install_cudo() {
    local install_dir scripts_dir global_config_dir
    if [ "$EUID" -eq 0 ]; then
        install_dir="/usr/local/bin"
        scripts_dir="/usr/local/share/cudo"
        global_config_dir="/var/lib/cudo-global"
    else
        install_dir="$HOME/.local/bin"
        scripts_dir="$HOME/.local/share/cudo"
        global_config_dir="$HOME/.local/share/cudo-global"
    fi

    log_info "Installing to $install_dir..."
    mkdir -p "$install_dir" "$scripts_dir" "$global_config_dir"
    cp "$PROJECT_ROOT/cudo" "$install_dir/cudo"
    chmod 755 "$install_dir/cudo"
    cp "$PROJECT_ROOT/scripts/cuda-env-list-simple.py" "$scripts_dir/"
    cp "$PROJECT_ROOT/scripts/cudo-smi.py" "$scripts_dir/"
    cp "$PROJECT_ROOT/scripts/nvidia-smi" "$scripts_dir/"
    chmod 755 "$scripts_dir/cudo-smi.py" "$scripts_dir/nvidia-smi"

    # Quote paths as shell literals, including homes containing spaces or quotes.
    python3 - "$install_dir/cudo" "$scripts_dir" "$global_config_dir" <<'PYTHON'
import pathlib
import shlex
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
lines = text.splitlines(keepends=True)
for index, line in enumerate(lines):
    if line.startswith('SCRIPT_DIR='):
        lines[index] = 'SCRIPT_DIR=' + shlex.quote(sys.argv[2]) + '\n'
    elif line.startswith('GLOBAL_CONFIG_DIR='):
        lines[index] = ('GLOBAL_CONFIG_DIR=${CUDO_GLOBAL_CONFIG_DIR:-'
                        + shlex.quote(sys.argv[3]) + '}\n')
path.write_text(''.join(lines))
PYTHON

    if [ "$EUID" -eq 0 ]; then
        chmod 777 "$global_config_dir"
        mkdir -p /usr/local/libexec
        cp "$PROJECT_ROOT/scripts/cudo-gpu-agent.py" /usr/local/libexec/cudo-gpu-agent
        chmod 755 /usr/local/libexec/cudo-gpu-agent
        if command -v systemctl >/dev/null 2>&1; then
            cp "$PROJECT_ROOT/scripts/cudo-gpu-agent.service" /etc/systemd/system/cudo-gpu-agent.service
            systemctl daemon-reload
            systemctl enable --now cudo-gpu-agent.service
        else
            log_warning "systemd was not found; start /usr/local/libexec/cudo-gpu-agent manually"
        fi
        log_success "GPU process agent installed"
    else
        log_warning "The system GPU process agent requires an administrator to install it with sudo bash ./install.sh."
        case ":$PATH:" in
            *":$install_dir:"*) ;;
            *) log_warning 'Add ~/.local/bin to PATH in your shell configuration: export PATH="$HOME/.local/bin:$PATH"' ;;
        esac
    fi

    log_success "Installed cudo to $install_dir"
    log_success "Support files installed to $scripts_dir"
    log_success "Project registry directory created: $global_config_dir"
}

# Main installation
main() {
    log_info "Cudo - Docker-based CUDA Development Environment Manager Installation"
    echo "========================================"
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    install_cudo
    
    echo
    log_success "Installation completed successfully!"
    echo
    echo "Usage examples:"
    echo "  cudo build -c 11.8.0 -p 3.10"
    echo "  cudo run"
    echo "  cudo enter <environment-name>"
    echo "  cudo enter <environment-name> -- nvidia-smi"
    echo "  cudo enter <environment-name> -- cudo-smi"
    echo "  cudo list"
    echo "  cudo rename <old-name> <new-name>"
    echo
    echo "For more information, see:"
    echo "  cudo --help"
    echo "  https://github.com/IMath123/cudo"
}

# Run main function
main "$@"
