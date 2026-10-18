"""Private registry and trusted installation path checks (Linux/POSIX).

Different UIDs are the boundary; processes sharing a UID are trusted.
No symlinked path components are supported. A root-owned sticky ancestor
(e.g. /tmp) is allowed, but the final directory must belong to the caller.
"""
import argparse
import os
from pathlib import Path
import pwd
import stat
import sys


def default_registry():
    # Never let sudo's inherited HOME select another user's registry.
    home = pwd.getpwuid(0).pw_dir if os.geteuid() == 0 else os.environ['HOME']
    return str(Path(home) / '.local/share/cudo-global')


def check_directory(path, create=False, private=True):
    path = Path(path)
    if not path.is_absolute() or '..' in path.parts:
        raise ValueError('directory must be absolute and contain no .. components')
    uid = os.geteuid()
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for index, part in enumerate(path.parts[1:]):
            final = index == len(path.parts) - 2
            try:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    return False
                try:
                    os.mkdir(part, 0o700 if private else 0o755, dir_fd=fd)
                except FileExistsError:
                    pass
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
            info = os.fstat(fd)
            sticky_root = info.st_uid == 0 and bool(info.st_mode & stat.S_ISVTX)
            if info.st_uid not in (0, uid) or (info.st_mode & 0o022 and not sticky_root):
                raise ValueError(f'untrusted directory component: {part}')
            if final:
                if info.st_uid != uid or info.st_mode & (0o077 if private else 0o022):
                    raise ValueError(f'{path}: requires caller ownership and mode {"0700" if private else "0755"}')
                for name in os.listdir(fd):
                    entry = os.stat(name, dir_fd=fd, follow_symlinks=False)
                    # Installation directories can contain unrelated subdirectories.
                    if not private:
                        continue
                    if (not stat.S_ISREG(entry.st_mode) or entry.st_uid != uid
                            or entry.st_nlink != 1 or entry.st_mode & 0o022):
                        raise ValueError(f'unsafe registry entry: {name}')
        if path == Path('/'):
            raise ValueError('the filesystem root cannot be used as a registry/install directory')
        return True
    finally:
        os.close(fd)


def check_target(path):
    path = Path(path)
    check_directory(path.parent, create=True, private=False)
    try:
        info = path.lstat()
    except FileNotFoundError:
        return
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid()
            or info.st_nlink != 1 or info.st_mode & 0o022):
        raise ValueError(f'unsafe installation target: {path}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('path', nargs='?')
    parser.add_argument('--create', action='store_true')
    parser.add_argument('--install-target', action='store_true')
    args = parser.parse_args()
    try:
        if args.install_target:
            check_target(args.path)
        else:
            path = args.path or os.environ.get('CUDO_GLOBAL_CONFIG_DIR') or default_registry()
            check_directory(path, create=args.create)
            print(path)
    except (OSError, ValueError, KeyError) as exc:
        print(f'Unsafe cudo path: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
