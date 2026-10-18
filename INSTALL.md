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
`~/.local/share/cudo`, and the project registry in `~/.local/share/cudo-global` (0700).
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
~/.local/share/cudo-global/         # Per invoking user, never shared writable
└── *.conf                          # Private metadata (new files: 0600)
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
# Private user registries are retained; do not delete the legacy registry blindly.
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

## Multi-user security and migration

System installation shares **code**, not a writable registry. Both installed
executables and a source checkout use the invoking user's
`~/.local/share/cudo-global`. Root uses the home from the UID 0 passwd entry,
not an inherited `HOME`. `CUDO_GLOBAL_CONFIG_DIR` remains supported only for an
absolute, caller-owned, private directory. Missing directories are created only
when needed, with mode 0700; new metadata files use 0600. `list` and `doctor`
do not create a registry. List's Python helper uses the same resolved path.

Existing directories with permissions other than private access are rejected,
as are symlink components, linked/nonregular/foreign-owned registry entries,
and untrusted writable ancestors. This deliberately excludes shared group
registries. A root-owned sticky ancestor such as `/tmp` is allowed, but the
registry itself must be private. Symlinked home paths require choosing a real
canonical private path via `CUDO_GLOBAL_CONFIG_DIR`. ACLs, NFS ownership and
root-squash need administrator verification on the deployment filesystem.

Before upgrading, stop old cudo processes and back up metadata. Disable old
system executables and remove old `CUDO_GLOBAL_CONFIG_DIR=/var/lib/cudo-global`
exports. An administrator should inspect the legacy directory with `lstat`
(no symlink traversal), verify it is the intended root-owned directory, then
make the legacy directory root-only (0700). Do not recursively chmod/chown or
blindly import its records: they may already have been replaced by another user.
The installer intentionally leaves this legacy state untouched.

For an existing **user-owned** registry, inspect ownership and symlinks first,
then set its directory to 0700 and regular metadata files to 0600. Audit any
exposed SSH credentials; rotate passwords whose hashes or legacy Base64
passwords may have been readable. Rebuild/re-register only trusted projects
as their owner. Audit existing `.cudo/config` permissions too; the new umask
does not retroactively protect old files. Avoid running project commands with
sudo, including inside another user's project. Root installation must use a
trusted checkout and environment.

Per-user names can now be identical; `list`, `enter`, `rename`, and `cleanup`
operate only on that user's registry. They no longer offer a server-wide
project directory. If that is required, add a separate administrator-managed
read-only inventory containing only public fields (owner UID, display name,
CUDA version). Do not expose password hashes, mount definitions, or actionable
project paths as trusted command input. A future publishing service must derive
ownership from peer credentials, not user-supplied OWNER fields.

This change is **not container isolation**. Users with a shared rootful Docker
socket have root-equivalent access and can manipulate other containers directly.
Container names still use the existing project hash; copying a project across
users can retain that hash. Use trusted cooperative users with this backend;
for mutually untrusted users, use an administrator-controlled scheduler/runtime
or separately isolated daemons and verify NVIDIA support. Shared GPU allocation,
SSH ports, existing container migration and same-user concurrent operations
are not serialized by the registry permissions patch. New registry saves use
atomic replacement, but multi-file operations are not transactions.

Regression checks:

```bash
python3 tests/test_permissions.py
# Ordinary Linux host: exercise distinct actual UIDs and both installer branches
sudo env CUDO_REQUIRE_MULTIUSER_TESTS=1 /usr/bin/python3 tests/test_permissions.py
./tests/run_all_tests.sh
```

Root installation tests use a temporary prefix and a fake systemctl. They do
not install Docker/NVIDIA packages or start a real service. The UID tests are
skipped on restricted hosts unless CUDO_REQUIRE_MULTIUSER_TESTS=1 is set; CI
sets it so missing multi-user coverage fails visibly.
