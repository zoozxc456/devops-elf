import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')


class InstallPathTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='iap PATH ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bindir = self.root / "bin's $cash `literal` [x]"
        self.env = dict(os.environ, HOME=str(self.root), SHELL='/bin/zsh')
        self.env.pop('ZDOTDIR', None)

    def install_bash(self, *args):
        result = subprocess.run(['/bin/bash', str(ROOT / 'install.sh'), '--bin-dir',
                                 str(self.bindir), *args], env=self.env,
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_zsh_persistence_backup_and_literal_paths(self):
        profile = self.root / '.zshrc'
        profile.write_text('# existing profile\n')
        self.install_bash()
        self.install_bash()
        text = profile.read_text()
        self.assertTrue(text.startswith('# existing profile\n'))
        self.assertEqual(text.count('# iap PATH:'), 1)
        backup, = self.root.glob('.zshrc.backup-*')
        self.assertEqual(backup.read_text(), '# existing profile\n')
        result = subprocess.run(['/bin/bash', '-c', '. "$1"; . "$1"; printf "%s" "$PATH"',
                                 'test', str(profile)], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(os.pathsep).count(str(self.bindir)), 1)
        zsh = shutil.which('zsh')
        if zsh:
            result = subprocess.run([zsh, '-f', '-c', '. "$1"; . "$1"; print -r -- "$PATH"',
                                     'test', str(profile)], env=self.env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip().split(os.pathsep).count(str(self.bindir)), 1)

    def test_bash_interactive_and_existing_login_profile(self):
        profile = self.root / '.profile'
        profile.write_text('# keep login\n')
        self.install_bash('--shell', 'bash')
        self.assertIn('# iap PATH:', profile.read_text())
        self.assertTrue((self.root / '.bashrc').exists())
        self.assertFalse((self.root / '.bash_profile').exists())

    def test_no_path_and_custom_zdotdir(self):
        self.install_bash('--no-path')
        self.assertFalse((self.root / '.zshrc').exists())
        self.env['ZDOTDIR'] = str(self.root / 'zsh config')
        self.install_bash()
        self.assertTrue((self.root / 'zsh config/.zshrc').exists())
        self.assertFalse((self.root / '.zshrc').exists())

    @unittest.skipUnless(PWSH, 'PowerShell 7.2+ required')
    def test_powershell_persistence_and_session_path_without_duplicates(self):
        profile = self.root / 'pwsh/profile.ps1'
        profile.parent.mkdir()
        profile.write_text('# keep PowerShell profile\n')
        harness = self.root / 'install-harness.ps1'
        harness.write_text(r'''
param($Installer, $BinDir, $ProfilePath)
$ErrorActionPreference='Stop'
& $Installer -BinDir $BinDir -ProfilePath $ProfilePath
& $Installer -BinDir $BinDir -ProfilePath $ProfilePath
. $ProfilePath
. $ProfilePath
@($env:PATH -split [regex]::Escape([string][IO.Path]::PathSeparator)) | ConvertTo-Json -Compress
''')
        result = subprocess.run([PWSH, '-NoProfile', '-File', str(harness), str(ROOT / 'install.ps1'),
                                 str(self.bindir), str(profile)], env=self.env,
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        paths = json.loads(result.stdout.splitlines()[-1])
        self.assertEqual(paths.count(str(self.bindir)), 1)
        self.assertEqual(profile.read_text().count('# iap PATH:'), 1)
        self.assertTrue(profile.read_text().startswith('# keep PowerShell profile\n'))
        backup, = profile.parent.glob('profile.ps1.backup-*')
        self.assertEqual(backup.read_text(), '# keep PowerShell profile\n')


if __name__ == '__main__':
    unittest.main()
