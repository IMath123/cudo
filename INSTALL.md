# Cudo Installation Guide

## Quick Installation

### Installation Steps

```bash
# Clone the repository
git clone https://github.com/IMath123/cudo.git
cd cudo

# Run the installation script (requires sudo)
./install.sh

# Test the installation
cudo --help
```

## File Structure After Installation

After installation, the file structure should look like this:

```
/usr/local/bin/cudo                  # Main executable
/usr/local/share/cudo/               # Support files directory
└── cuda-env-list-simple.py         # Python helper script
/var/lib/cudo-global/                # Global configuration directory (multi-user support)
└── *.conf                          # Project metadata files
```

## Troubleshooting

### Python Script Not Found Error

If you see an error like "Python list script not found", check:

1. **File locations**:
   ```bash
   # Check if files are in the right place
   ls -la /usr/local/bin/cudo
   ls -la /usr/local/share/cudo/cuda-env-list-simple.py
   ```

2. **Reinstall**:
   ```bash
   # Remove and reinstall
   sudo rm -f /usr/local/bin/cudo
   sudo rm -rf /usr/local/share/cudo
   sudo rm -rf /var/lib/cudo-global
   ./install.sh
   ```

### PATH Issues

If `cudo` command is not found:

```bash
# Check if /usr/local/bin is in PATH
echo $PATH | grep -q "/usr/local/bin" && echo "PATH is correct" || echo "PATH needs update"

# Add to PATH temporarily
export PATH="/usr/local/bin:$PATH"
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

```bash
sudo rm -f /usr/local/bin/cudo
sudo rm -rf /usr/local/share/cudo
sudo rm -rf /var/lib/cudo-global
```

## Support

If you encounter any issues during installation, please:

1. Check the troubleshooting section above
2. Create an issue on GitHub: https://github.com/IMath123/cudo/issues
3. Check the project documentation in README.md