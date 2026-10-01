# Cudo Installation Guide

## Quick Installation

### Installation Steps

```bash
# Clone the repository
git clone https://github.com/IMath123/cudo.git
cd cudo

# Install for the current user (no sudo)
bash ./install.sh
export PATH="$HOME/.local/bin:$PATH"

# Or install system-wide, including the GPU process agent
sudo bash ./install.sh

# Test the installation
cudo --help
cudo doctor
```

## File Structure After Installation

A user installation stores the executable in `~/.local/bin`, support files in
`~/.local/share/cudo`, and the project registry in `~/.local/share/cudo-global`.
Add `~/.local/bin` to your shell configuration if it is not already on `PATH`.
User installation does not install system dependencies or the GPU agent service;
an administrator must provide those. The GPU process view requires that service.

After a system-wide installation, the file structure should look like this:

```
/usr/local/bin/cudo                  # Main executable
/usr/local/share/cudo/               # Support files directory
├── cuda-env-list-simple.py         # Environment list helper
└── cudo-smi.py                     # Container GPU process client
/usr/local/libexec/cudo-gpu-agent   # Host GPU process agent
/etc/systemd/system/cudo-gpu-agent.service
/run/cudo/gpu-agent.sock            # Runtime Unix socket
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
   sudo bash ./install.sh
   ```

### PATH Issues

If `cudo` command is not found:

```bash
# Check if /usr/local/bin is in PATH
echo $PATH | grep -q "/usr/local/bin" && echo "PATH is correct" || echo "PATH needs update"

# Add the appropriate directory to PATH temporarily
export PATH="$HOME/.local/bin:$PATH"  # User installation
export PATH="/usr/local/bin:$PATH"    # System-wide installation
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

# Diagnose Docker, NVIDIA runtime, Compose, and required host tools
cudo doctor

# Verify the filtered GPU process agent
systemctl status cudo-gpu-agent
test -S /run/cudo/gpu-agent.sock
```

## Dependencies

Make sure you have the following dependencies installed:

- **Docker**: Container runtime
- **Docker Compose v2 or v1**: Container orchestration
- **NVIDIA Container Runtime**: GPU access from Docker containers
- **Python 3**: For the list command
- **gettext (`envsubst`)**: Configuration template rendering
- **OpenSSL with `passwd -6`**: SSH password hashing
- **Git**: For cloning the repository

On Ubuntu or Debian, the host-side utility dependencies can be installed with:

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin python3 gettext openssl git
```

Install and configure the NVIDIA Container Toolkit separately using NVIDIA's instructions, then restart Docker. Verify that Docker exposes the runtime before building an environment:

```bash
docker info --format '{{json .Runtimes}}'
cudo doctor
```

`cudo doctor` returns a non-zero exit code when a required check fails. Warnings, such as an environment that has not created its container yet, do not make the command fail.

## Uninstallation

For a user installation:

```bash
rm -f "$HOME/.local/bin/cudo"
rm -rf "$HOME/.local/share/cudo"
# Remove the project registry only if you no longer need its metadata
rm -rf "$HOME/.local/share/cudo-global"
```

For a system-wide installation:

```bash
sudo rm -f /usr/local/bin/cudo
sudo rm -rf /usr/local/share/cudo
sudo rm -rf /var/lib/cudo-global
sudo systemctl disable --now cudo-gpu-agent.service
sudo rm -f /etc/systemd/system/cudo-gpu-agent.service
sudo rm -f /usr/local/libexec/cudo-gpu-agent
sudo systemctl daemon-reload
```

## Support

If you encounter any issues during installation, please:

1. Check the troubleshooting section above
2. Create an issue on GitHub: https://github.com/IMath123/cudo/issues
3. Check the project documentation in README.md
