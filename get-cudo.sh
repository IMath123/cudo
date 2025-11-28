#!/bin/bash

# Cudo One-Line Installer
# Downloads and installs Cudo from the master branch

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}$1${NC}"; }
log_success() { echo -e "${GREEN}$1${NC}"; }
log_error() { echo -e "${RED}$1${NC}"; }

# Check OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    log_error "Error: macOS is not supported."
    log_error "Cudo is designed for Linux environments with NVIDIA GPUs and Docker."
    exit 1
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
log_info "Created temporary directory: $TEMP_DIR"

# Cleanup on exit
cleanup() {
    rm -rf "$TEMP_DIR"
    log_info "Cleaned up temporary directory"
}
trap cleanup EXIT

# Download files
REPO_URL="https://raw.githubusercontent.com/IMath123/cudo/master"
log_info "Downloading Cudo..."

cd "$TEMP_DIR"

# Download cudo script
if ! curl -fsSL "$REPO_URL/cudo" -o cudo; then
    log_error "Failed to download cudo script"
    exit 1
fi
chmod +x cudo

# Download install script
if ! curl -fsSL "$REPO_URL/install.sh" -o install.sh; then
    log_error "Failed to download install.sh"
    exit 1
fi
chmod +x install.sh

# Download helper scripts
mkdir -p scripts
if ! curl -fsSL "$REPO_URL/scripts/cuda-env-list-simple.py" -o scripts/cuda-env-list-simple.py; then
    log_error "Failed to download helper scripts"
    exit 1
fi

# Run install script
log_info "Running installation script..."
# install.sh expects to be in the project root and uses relative paths
bash ./install.sh

log_success "Cudo installed successfully!"
