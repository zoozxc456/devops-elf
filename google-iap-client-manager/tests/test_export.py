import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='iap export ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'hosts'
        self.env = dict(os.environ, IAP_CONF=str(self.config),
                        XDG_CONFIG_HOME=str(self.root / 'config'))
        self.modes = ['bash'] + (['powershell'] if PWSH else [])

    def run_export(self, mode, *args, answers='', ok=True):
        if mode == 'bash':
            command = ['/bin/bash', str(ROOT / 'iap'), 'export', *map(str, args)]
        else:
            harness = self.root / 'export-harness.ps1'
            harness.write_text(r'''
param($Client)
$ErrorActionPreference='Stop'
function global:Read-Host { param($Prompt); return [Console]::ReadLine() }
& $Client export @args
''')
            command = [PWSH, '-NoProfile', '-File', str(harness), str(ROOT / 'iap.ps1'), *map(str, args)]
        result = subprocess.run(command, input=answers, capture_output=True,
                                text=True, env=self.env, timeout=15)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def test_export_original_formats_and_private_file(self):
        for mode in self.modes:
            for suffix in ('', '.json', '.yaml'):
                with self.subTest(mode=mode, suffix=suffix):
                    self.config = self.root / ('hosts' + suffix)
                    self.env['IAP_CONF'] = str(self.config)
                    original = b'# literal comments\r\ninvalid-as-json preserved $value\r\n'
                    self.config.write_bytes(original)
                    output = self.root / mode / ('backup' + suffix)
                    self.run_export(mode, '--output', output)
                    self.assertEqual(output.read_bytes(), original)
                    self.assertEqual(self.config.read_bytes(), original)
                    if os.name != 'nt':
                        self.assertEqual(output.stat().st_mode & 0o777, 0o600)

    def test_stdout_has_only_config(self):
        self.config.write_text('vm ssh - - vm\n')
        for mode in self.modes:
            result = self.run_export(mode)
            self.assertEqual(result.stdout.strip(), 'vm ssh - - vm')
            self.assertEqual(result.stderr, '')

    def test_existing_output_confirmation_and_backup(self):
        self.config.write_text('vm ssh - - vm\n')
        for mode in self.modes:
            output = self.root / (mode + '.backup')
            output.write_bytes(b'original\r\n')
            self.run_export(mode, output, answers='\n')
            self.assertEqual(output.read_bytes(), b'original\r\n')
            self.run_export(mode, output, answers='y\n')
            self.assertEqual(output.read_bytes(), self.config.read_bytes())
            backup, = self.root.glob(output.name + '.backup-*')
            self.assertEqual(backup.read_bytes(), b'original\r\n')

    def test_self_symlink_directory_and_missing_source_are_rejected(self):
        self.config.write_text('vm ssh - - vm\n')
        for mode in self.modes:
            self.run_export(mode, self.config, ok=False)
            self.run_export(mode, self.root, ok=False)
            if os.name != 'nt':
                link = self.root / (mode + '.link')
                link.symlink_to(self.config)
                self.run_export(mode, link, ok=False)
            self.assertEqual(self.config.read_text(), 'vm ssh - - vm\n')
        self.config.unlink()
        for mode in self.modes:
            output = self.root / (mode + '.missing')
            self.run_export(mode, output, ok=False)
            self.assertFalse(output.exists())
            self.assertFalse(self.config.exists())

    def test_default_discovery_and_help(self):
        self.env.pop('IAP_CONF')
        directory = self.root / 'config/iap'
        directory.mkdir(parents=True)
        (directory / 'hosts').write_text('lower priority')
        (directory / 'hosts.yaml').write_text('# preferred YAML\nhosts: {}\n')
        for mode in self.modes:
            output = self.root / (mode + '.yaml')
            self.run_export(mode, output)
            self.assertEqual(output.read_bytes(), (directory / 'hosts.yaml').read_bytes())
            self.assertIn('export', self.run_export(mode, '--help').stdout)


if __name__ == '__main__':
    unittest.main()
