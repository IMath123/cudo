# Cudo Installation Guide

## Quick Installation

### Method 1: Clone and Install (Recommended)

```bash
# Clone the repository
git clone https://github.com/IMath123/cudo.git
cd cudo

# Run the installation script
./scripts/install.sh local

# Test the installation
cudo --help
```

### Method 2: Manual Installation

If you want to install manually, follow these steps:

```bash
# Create directories
mkdir -p ~/.local/bin
mkdir -p ~/.local/share/cudo

# Copy the main script
cp cudo ~/.local/bin/cudo
chmod +x ~/.local/bin/cudo

# Copy the Python helper script
cp scripts/cuda-env-list-simple.py ~/.local/share/cudo/

# Update the script path in cudo
sed -i "s|PYTHON_SCRIPT_DIR=.*|PYTHON_SCRIPT_DIR=\"$HOME/.local/share/cudo\"|" ~/.local/bin/cudo

# Add to PATH (if not already)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Test the installation
cudo --help
```

### Method 3: System-wide Installation

```bash
# Clone the repository
git clone https://github.com/IMath123/cudo.git
cd cudo

# Install system-wide (requires sudo)
./scripts/install.sh system

# Test the installation
cudo --help
```

## File Structure After Installation

After installation, the file structure should look like this:

### For Local Installation:
```
~/.local/bin/cudo                    # Main executable
~/.local/share/cudo/                 # Support files directory
└── cuda-env-list-simple.py         # Python helper script
```

### For System-wide Installation:
```
/usr/local/bin/cudo                  # Main executable
/usr/local/share/cudo/               # Support files directory
└── cuda-env-list-simple.py         # Python helper script
```

## Troubleshooting

### Python Script Not Found Error

If you see an error like "Python list script not found", check:

1. **File locations**:
   ```bash
   # Check if files are in the right place
   ls -la ~/.local/bin/cudo
   ls -la ~/.local/share/cudo/cuda-env-list-simple.py
   ```

2. **Update script paths**:
   ```bash
   # Update the Python script path in cudo
   sed -i "s|PYTHON_SCRIPT_DIR=.*|PYTHON_SCRIPT_DIR=\"$HOME/.local/share/cudo\"|" ~/.local/bin/cudo
   ```

3. **Reinstall**:
   ```bash
   # Remove and reinstall
   rm -f ~/.local/bin/cudo
   rm -rf ~/.local/share/cudo
   ./scripts/install.sh local
   ```

### PATH Issues

If `cudo` command is not found:

```bash
# Check if ~/.local/bin is in PATH
echo $PATH | grep -q ".local/bin" && echo "PATH is correct" || echo "PATH needs update"

# Add to PATH temporarily
export PATH="$HOME/.local/bin:$PATH"

# Add to PATH permanently
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Verification

After installation, verify everything works:

```bash
# Check if cudo is accessible
which cudo

# Check version and help
cudo --help

# Test list command (should show empty list or existing environments)
cudo list
```

## Dependencies

Make sure you have the following dependencies installed:

- **Docker**: Container runtime
- **Docker Compose**: Container orchestration
- **Python 3**: For the list command
- **Git**: For cloning the repository

## Uninstallation

### Local Installation:
```bash
rm -f ~/.local/bin/cudo
rm -rf ~/.local/share/cudo
```

### System-wide Installation:
```bash
sudo rm -f /usr/local/bin/cudo
sudo rm -rf /usr/local/share/cudo
```

## Support

If you encounter any issues during installation, please:

1. Check the troubleshooting section above
2. Create an issue on GitHub: https://github.com/IMath123/cudo/issues
3. Check the project documentation in README.md