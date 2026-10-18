#!/usr/bin/env python3
"""No Docker/GPU required. Root additionally exercises real distinct UIDs."""
import importlib.util
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('paths', ROOT / 'scripts/cudo_paths.py')
paths = importlib.util.module_from_spec(spec)
spec.loader.exec_module(paths)


class Permissions(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cudo-permissions-')
        self.base = Path(self.temp.name)
        self.registry = self.base / 'registry'

    def tearDown(self):
        self.temp.cleanup()

    def test_read_only_check_does_not_create(self):
        self.assertFalse(paths.check_directory(self.registry))
        self.assertFalse(self.registry.exists())

    def test_private_creation_even_with_permissive_umask(self):
        old = os.umask(0)
        try:
            paths.check_directory(self.registry, create=True)
        finally:
            os.umask(old)
        self.assertEqual(stat.S_IMODE(self.registry.stat().st_mode), 0o700)

    def test_shared_and_sticky_registries_rejected(self):
        self.registry.mkdir()
        for mode in (0o755, 0o777, 0o1777, 0o2770):
            self.registry.chmod(mode)
            with self.subTest(mode=oct(mode)), self.assertRaises(ValueError):
                paths.check_directory(self.registry)

    def test_symlink_components_and_entries_rejected(self):
        paths.check_directory(self.registry, create=True)
        link = self.base / 'link'
        link.symlink_to(self.registry)
        with self.assertRaises(OSError):
            paths.check_directory(link)
        victim = self.base / 'victim'
        victim.write_text('unchanged')
        (self.registry / 'evil.conf').symlink_to(victim)
        with self.assertRaises(ValueError):
            paths.check_directory(self.registry)
        self.assertEqual(victim.read_text(), 'unchanged')

    def test_hardlinks_and_writable_ancestors_rejected(self):
        paths.check_directory(self.registry, create=True)
        victim = self.base / 'victim'
        victim.write_text('unchanged')
        os.link(victim, self.registry / 'evil.conf')
        with self.assertRaises(ValueError):
            paths.check_directory(self.registry)
        (self.registry / 'evil.conf').unlink()
        self.base.chmod(0o777)
        with self.assertRaises(ValueError):
            paths.check_directory(self.registry)

    def test_install_target_rejects_symlink_and_hardlink(self):
        victim = self.base / 'victim'
        victim.write_text('unchanged')
        target = self.base / 'cudo'
        target.symlink_to(victim)
        with self.assertRaises(ValueError):
            paths.check_target(target)
        target.unlink()
        os.link(victim, target)
        with self.assertRaises(ValueError):
            paths.check_target(target)
        self.assertEqual(victim.read_text(), 'unchanged')

    def test_cli_rejects_shared_registry_before_cleanup(self):
        self.registry.mkdir(mode=0o777)
        self.registry.chmod(0o777)
        record = self.registry / 'alice.conf'
        record.write_text('STATUS=deleted\n')
        result = subprocess.run([str(ROOT / 'cudo'), 'cleanup'], cwd=self.base,
                                env={**os.environ, 'CUDO_GLOBAL_CONFIG_DIR': str(self.registry)},
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(record.exists())

    def test_root_default_ignores_home(self):
        if os.geteuid() != 0:
            self.skipTest('requires root')
        old = os.environ.get('HOME')
        try:
            os.environ['HOME'] = '/home/untrusted-user'
            self.assertNotIn('untrusted-user', paths.default_registry())
        finally:
            if old is None:
                os.environ.pop('HOME', None)
            else:
                os.environ['HOME'] = old

    def require_uid_mapping(self, uid):
        probe = self.base / 'uid-probe'
        probe.touch()
        try:
            os.chown(probe, uid, uid)
        except OSError as exc:
            if os.environ.get('CUDO_REQUIRE_MULTIUSER_TESTS') == '1':
                raise
            self.skipTest(f'host cannot map test UID {uid}: {exc}')
        finally:
            probe.unlink()

    def fake_docker(self, directory):
        directory.mkdir(exist_ok=True)
        docker = directory / 'docker'
        docker.write_text('#!/bin/sh\nexit 1\n')
        docker.chmod(0o755)

    def test_distinct_uids_cannot_read_write_delete_or_redirect(self):
        if os.geteuid() != 0:
            self.skipTest('requires root; CI runs this suite with sudo too')
        self.require_uid_mapping(61001)
        self.require_uid_mapping(61002)
        self.base.chmod(0o755)
        a = self.base / 'alice'
        b = self.base / 'bob'
        for directory, uid in ((a, 61001), (b, 61002)):
            directory.mkdir(mode=0o700)
            os.chown(directory, uid, uid)
        record = a / 'project.conf'
        record.write_text('STATUS=active\n')
        os.chown(record, 61001, 61001)
        code = '''
import os, sys
from pathlib import Path
record = Path(sys.argv[1])
for operation in (lambda: record.read_text(), lambda: record.write_text('bad'),
                  lambda: record.unlink(), lambda: (record.parent / 'evil').symlink_to('/etc/passwd')):
    try: operation()
    except PermissionError: pass
    else: raise AssertionError('cross-user operation succeeded')
'''
        def bob():
            os.setgroups([])
            os.setgid(61002)
            os.setuid(61002)
        result = subprocess.run(['/usr/bin/python3', '-c', code, str(record)],
                                preexec_fn=bob, cwd='/tmp', capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(record.read_text(), 'STATUS=active\n')

    def test_staged_system_install_and_installed_list(self):
        if os.geteuid() != 0:
            self.skipTest('root branch; CI runs with sudo')
        stage = self.base / 'stage'
        source = self.base / 'source'
        shutil.copytree(ROOT / 'scripts', source / 'scripts')
        shutil.copy2(ROOT / 'cudo', source / 'cudo')
        # Run the actual root installation function in a disposable prefix.
        # Dependency installation and systemd are deliberately not exercised.
        script = (ROOT / 'install.sh').read_text().replace('/usr/local', str(stage / 'usr/local'))
        script = script.replace('/etc/systemd/system', str(stage / 'etc/systemd/system'))
        (source / 'install.sh').write_text(script)
        fake = self.base / 'bin'
        self.fake_docker(fake)
        systemctl = fake / 'systemctl'
        systemctl.write_text('#!/bin/sh\nexit 0\n')
        systemctl.chmod(0o755)
        result = subprocess.run(['bash', '-c', 'source "$1"; install_cudo', '_', str(source / 'install.sh')],
                                env={**os.environ, 'PATH': f'{fake}:' + os.environ['PATH']},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        executable = stage / 'usr/local/bin/cudo'
        self.assertEqual(stat.S_IMODE(executable.stat().st_mode), 0o755)
        paths.check_directory(self.registry, create=True)
        (self.registry / 'demo.conf').write_text('PROJECT_NAME=private-demo\nPROJECT_PATH=/missing\nUNIQUE_HASH=12345678\n')
        result = subprocess.run([str(executable), 'list'], cwd=self.base,
                                env={**os.environ, 'CUDO_GLOBAL_CONFIG_DIR': str(self.registry), 'PATH': f'{fake}:' + os.environ['PATH']},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('private-demo', result.stdout)
        self.assertFalse((stage / 'var/lib/cudo-global').exists())

    def test_user_install_with_quoted_home_and_default_list(self):
        if os.geteuid() != 0:
            uid = os.geteuid()
            demote = None
        else:
            uid = 61003
            self.require_uid_mapping(uid)
            def demote():
                os.setgroups([])
                os.setgid(uid)
                os.setuid(uid)
        self.base.chmod(0o755)
        home = self.base / "user's home"
        home.mkdir(mode=0o700)
        source = home / 'source'
        shutil.copytree(ROOT / 'scripts', source / 'scripts')
        shutil.copy2(ROOT / 'cudo', source / 'cudo')
        shutil.copy2(ROOT / 'install.sh', source / 'install.sh')
        registry = home / '.local/share/cudo-global'
        registry.mkdir(parents=True, mode=0o700)
        (registry / 'demo.conf').write_text('PROJECT_NAME=user-demo\nPROJECT_PATH=/missing\nUNIQUE_HASH=12345678\n')
        if os.geteuid() == 0:
            for item in [home, *home.rglob('*')]:
                os.chown(item, uid, uid)
        fake = home / 'fake-bin'
        self.fake_docker(fake)
        if os.geteuid() == 0:
            os.chown(fake, uid, uid)
            os.chown(fake / 'docker', uid, uid)
        env = {**os.environ, 'HOME': str(home), 'PATH': f'{fake}:' + os.environ['PATH']}
        env.pop('CUDO_GLOBAL_CONFIG_DIR', None)
        result = subprocess.run(['/bin/bash', '-c', 'source "$1"; install_cudo', '_', str(source / 'install.sh')],
                                preexec_fn=demote, cwd='/tmp', env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run([str(home / '.local/bin/cudo'), 'list'], preexec_fn=demote,
                                cwd='/tmp', env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('user-demo', result.stdout)


if __name__ == '__main__':
    unittest.main()
