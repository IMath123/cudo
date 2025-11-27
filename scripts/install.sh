#!/bin/bash

# Cudo - CUDA Development Environment Manager Installation Script
# This script installs cudo system-wide

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

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_error "Please do not run this script as root"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

log_info "Installing Cudo - CUDA Development Environment Manager..."

# Check dependencies
check_dependencies() {
    local missing=()
    
    if ! command -v docker &> /dev/null; then
        missing+=("docker")
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        missing+=("docker-compose")
    fi
    
    if ! command -v python3 &> /dev/null; then
        missing+=("python3")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo "Please install the following software:"
        for dep in "${missing[@]}"; do
            case $dep in
                "docker")
                    echo "  Docker: https://docs.docker.com/get-docker/"
                    ;;
                "docker-compose")
                    echo "  Docker Compose: https://docs.docker.com/compose/install/"
                    ;;
                "python3")
                    echo "  Python 3:"
                    echo "    Ubuntu/Debian: sudo apt-get install python3"
                    echo "    CentOS/RHEL: sudo yum install python3"
                    ;;
            esac
        done
        return 1
    fi
    return 0
}

# Install system-wide
install_system_wide() {
    local install_dir="/usr/local/bin"
    local script_name="cudo"
    
    log_info "Installing to $install_dir..."
    
    # Copy main script
    sudo cp "$PROJECT_ROOT/cudo" "$install_dir/$script_name"
    sudo chmod +x "$install_dir/$script_name"
    
    # Create scripts directory
    local scripts_dir="/usr/local/share/cudo"
    sudo mkdir -p "$scripts_dir"
    sudo cp "$PROJECT_ROOT/scripts/cuda-env-list-simple.py" "$scripts_dir/"
    
    # Update script path in main script
    sudo sed -i "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$scripts_dir\"|" "$install_dir/$script_name"
    
    log_success "Installed $script_name to $install_dir"
    log_success "Support files installed to $scripts_dir"
}

# Install locally
install_local() {
    local install_dir="$HOME/.local/bin"
    
    log_info "Installing to $install_dir..."
    
    # Create directory if it doesn't exist
    mkdir -p "$install_dir"
    
    # Copy main script
    cp "$PROJECT_ROOT/cudo" "$install_dir/cudo"
    chmod +x "$install_dir/cudo"
    
    # Create scripts directory
    local scripts_dir="$HOME/.local/share/cudo"
    mkdir -p "$scripts_dir"
    cp "$PROJECT_ROOT/scripts/cuda-env-list-simple.py" "$scripts_dir/"
    
    # Update script path in main script
    sed -i "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$scripts_dir\"|" "$install_dir/cudo"
    
    log_success "Installed cudo to $install_dir"
    log_success "Support files installed to $scripts_dir"
    
    # Check if PATH includes ~/.local/bin
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
        log_warning "Please add $install_dir to your PATH"
        echo "Add this line to your ~/.bashrc or ~/.zshrc:"
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# Main installation
main() {
    local install_type=${1:-local}
    
    log_info "Cudo - Docker-based CUDA Development Environment Manager Installation"
    echo "========================================"
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    case $install_type in
        "system")
            install_system_wide
            ;;
        "local")
            install_local
            ;;
        *)
            log_error "Invalid installation type: $install_type"
            echo "Usage: $0 [system|local]"
            echo "  system: Install system-wide (requires sudo)"
            echo "  local:  Install to user directory (default)"
            exit 1
            ;;
    esac
    
    echo
    log_success "Installation completed successfully!"
    echo
    echo "Usage examples:"
    echo "  cudo --help"
    echo "  cudo build -c 11.8.0 -p 3.10"
    echo "  cudo list"
    echo
    echo "For more information, see:"
    echo "  https://github.com/yourusername/cudo"
}

# Run main function
main "$@"
