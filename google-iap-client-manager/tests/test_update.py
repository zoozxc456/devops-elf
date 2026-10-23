import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='iap update ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        shutil.copytree(ROOT, self.source, ignore=shutil.ignore_patterns('__pycache__'))
        self.config = self.root / 'hosts'
        self.config.write_text('keep ssh - - existing\n')
        self.env = dict(os.environ, IAP_CONF=str(self.config))
        self.modes = ['bash'] + (['powershell'] if PWSH else [])

    def command(self, mode, script, *args, ok=True):
        prefix = ['/bin/bash'] if mode == 'bash' else [PWSH, '-NoProfile', '-File']
        result = subprocess.run(prefix + [str(script), *map(str, args)],
                                capture_output=True, text=True, env=self.env, timeout=20)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def install(self, mode):
        bindir = self.root / (mode + ' bin')
        if mode == 'bash':
            result = self.command(mode, self.source / 'install.sh', '--bin-dir', bindir, '--no-path')
        else:
            result = self.command(mode, self.source / 'install.ps1', '-BinDir', bindir, '-NoPath')
        self.assertIn('安裝版本：iap 0.4.1', result.stdout)
        return bindir / ('iap' if mode == 'bash' else 'iap.ps1')

    def git(self, directory, *args):
        return subprocess.run(['git', '-C', str(directory), *args], check=True,
                              capture_output=True, text=True, timeout=20)

    def commit(self, directory):
        self.git(directory, 'add', '.')
        self.git(directory, '-c', 'user.name=IAP Test', '-c', 'user.email=iap@example.invalid',
                 'commit', '-m', 'test update')

    def test_update_syncs_local_source_and_companions_without_touching_config(self):
        installed = [(mode, self.install(mode)) for mode in self.modes]
        for filename in ('iap', 'iap.ps1'):
            path = self.source / filename
            path.write_text(path.read_text().replace('0.4.1', '0.4.2'))
        for filename in ('iap.bash', 'iap.ps1'):
            with (self.source / 'completions' / filename).open('a') as stream:
                stream.write('\n# completion update marker\n')
        for mode, executable in installed:
            with self.subTest(mode=mode):
                result = self.command(mode, executable, 'update')
                self.assertIn('安裝版本：iap 0.4.2', result.stdout)
                self.assertRegex(result.stdout, r'更新完成：iap 0\.4\.1.*→ iap 0\.4\.2')
                self.assertIn('0.4.2', self.command(mode, executable, 'version').stdout)
                completion = 'iap.bash' if mode == 'bash' else 'iap.ps1'
                self.assertIn('completion update marker',
                              (executable.parent / '.iap/completions' / completion).read_text())
                self.assertFalse(executable.is_symlink())
        self.assertEqual(self.config.read_text(), 'keep ssh - - existing\n')

    @unittest.skipUnless(shutil.which('git'), 'Git required')
    def test_update_pulls_local_git_remote_and_reinstalls(self):
        self.git(self.source, 'init', '--initial-branch=main')
        self.commit(self.source)
        remote = self.root / 'remote.git'
        subprocess.run(['git', 'clone', '--bare', str(self.source), str(remote)],
                       check=True, capture_output=True, timeout=20)
        self.git(self.source, 'remote', 'add', 'origin', str(remote))
        self.git(self.source, 'fetch', 'origin')
        self.git(self.source, 'branch', '--set-upstream-to=origin/main', 'main')
        installed = [(mode, self.install(mode)) for mode in self.modes]
        checkout = self.root / 'developer'
        subprocess.run(['git', 'clone', str(remote), str(checkout)],
                       check=True, capture_output=True, timeout=20)
        for filename in ('iap', 'iap.ps1'):
            path = checkout / filename
            path.write_text(path.read_text().replace('0.4.1', '0.4.2'))
        self.commit(checkout)
        self.git(checkout, 'push')
        for mode, executable in installed:
            with self.subTest(mode=mode):
                result = self.command(mode, executable, 'update')
                self.assertRegex(result.stdout, r'更新完成：iap 0\.4\.1.*→ iap 0\.4\.2')
                self.assertIn('0.4.2', self.command(mode, executable, 'version').stdout)
        # A dirty source must fail before changing either installed client.
        with (self.source / 'iap').open('a') as stream:
            stream.write('\n# local uncommitted change\n')
        for mode, executable in installed:
            before = executable.read_bytes()
            self.command(mode, executable, 'update', ok=False)
            self.assertEqual(executable.read_bytes(), before)
        self.assertEqual(self.config.read_text(), 'keep ssh - - existing\n')


if __name__ == '__main__':
    unittest.main()
