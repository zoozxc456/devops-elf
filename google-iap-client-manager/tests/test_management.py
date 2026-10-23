import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import unittest

import test_setup as bash_tests
import test_powershell as ps_tests

ROOT = bash_tests.ROOT


class BashManagementTests(unittest.TestCase):
    setUp = bash_tests.SetupTests.setUp
    run_cli = bash_tests.SetupTests.run_cli

    def seed(self, structured=False):
        self.target.parent.mkdir(parents=True, exist_ok=True)
        if structured:
            self.target = self.target.with_suffix('.json')
            self.target.write_text(json.dumps({'defaults': {'project': 'keep'},
                'hosts': {'db': {'type': 'tunnel', 'remote_port': 5431, 'local_port': 5431},
                          'other': {'instance': 'other-vm'}}, 'extra': ['keep']}))
        else:
            self.target.write_text('# keep\ndb tunnel - zone vm 5431 5431\n'
                                   '  > DB localhost:{port}\n# next comment\nother ssh - - other-vm\n')
        self.env['IAP_CONF'] = str(self.target)
        return self.target.read_bytes()

    def test_remove_confirmation_backup_and_other_entries(self):
        for structured in (False, True):
            before = self.seed(structured)
            self.run_cli('iap', 'remove', 'db', answers='\n')
            self.assertEqual(self.target.read_bytes(), before)
            self.run_cli('iap', 'remove', 'missing', answers='y\n', ok=False)
            self.run_cli('iap', 'remove', 'db', answers='y\n')
            self.assertEqual(self.run_cli('iap', 'names').stdout.strip(), 'other')
            backups = list(self.target.parent.glob(self.target.name + '.backup-*'))
            self.assertTrue(any(path.read_bytes() == before for path in backups))
            if structured:
                self.assertEqual(json.loads(self.target.read_text())['extra'], ['keep'])
            else:
                self.assertIn('# next comment', self.target.read_text())

    def test_reset_defaults_to_no_and_preserves_structured_defaults(self):
        before = self.seed(True)
        self.run_cli('iap', 'reset', answers='\n')
        self.assertEqual(self.target.read_bytes(), before)
        self.run_cli('iap', 'reset', answers='y\n')
        data = json.loads(self.target.read_text())
        self.assertEqual(data['hosts'], {})
        self.assertEqual(data['defaults'], {'project': 'keep'})

    def editor(self, replacement='6543', code=0):
        script = self.home / 'fake editor.py'
        script.write_text('from pathlib import Path\nimport sys\np=Path(sys.argv[1])\n'
                          f'p.write_text(p.read_text().replace("5431", {replacement!r}))\n'
                          f'sys.exit({code})\n')
        self.env['EDITOR'] = shlex.quote(sys.executable) + ' ' + shlex.quote(str(script))

    def test_edit_only_selected_connection_and_validate_ports(self):
        for structured in (False, True):
            self.seed(structured)
            self.editor()
            self.run_cli('iap', 'edit', 'db', answers='y\n')
            self.assertIn('6543', self.target.read_text())
            self.assertIn('other-vm', self.target.read_text())
            before = self.target.read_bytes()
            self.editor('99999')
            self.run_cli('iap', 'edit', 'db', answers='y\n')  # unchanged 5431 is absent
            self.assertEqual(self.target.read_bytes(), before)
            self.seed(structured)
            before = self.target.read_bytes()
            self.run_cli('iap', 'edit', 'db', answers='y\n', ok=False)
            self.assertEqual(self.target.read_bytes(), before)

    def test_edit_cancel_and_editor_failure_preserve_config(self):
        before = self.seed()
        self.editor()
        self.run_cli('iap', 'edit', 'db', answers='\n')
        self.assertEqual(self.target.read_bytes(), before)
        self.editor(code=1)
        self.run_cli('iap', 'edit', 'db', ok=False)
        self.assertEqual(self.target.read_bytes(), before)

    def test_uninstall_only_installed_bash_and_preserves_settings(self):
        before = self.seed()
        self.run_cli('iap', 'uninstall', answers='y\n', ok=False)
        bindir = self.home / 'bin'
        self.run_cli('install.sh', '--bin-dir', bindir)
        (bindir / 'iap.ps1').write_text('keep PowerShell')
        (bindir / '.iap/scripts/common.ps1').write_text('keep shared')
        self.run_cli(bindir / 'iap', 'uninstall', answers='\n')
        self.assertTrue((bindir / 'iap').exists())
        self.run_cli(bindir / 'iap', 'uninstall', answers='y\n')
        self.assertFalse((bindir / 'iap').exists())
        self.assertTrue((bindir / 'iap.ps1').exists())
        self.assertTrue((bindir / '.iap/scripts/common.ps1').exists())
        self.assertEqual(self.target.read_bytes(), before)


@unittest.skipUnless(ps_tests.PWSH, 'PowerShell 7.2+ required')
class PowerShellManagementTests(unittest.TestCase):
    setUp = ps_tests.PowerShellTests.setUp
    run_ps = ps_tests.PowerShellTests.run_ps

    def seed(self, structured=False):
        self.target.parent.mkdir(parents=True, exist_ok=True)
        if structured:
            self.target = self.target.with_suffix('.json')
            self.target.write_text(json.dumps({'defaults': {'project': 'keep'},
                'hosts': {'db': {'type': 'tunnel', 'remote_port': 5431, 'local_port': 5431},
                          'other': {'instance': 'other-vm'}}, 'extra': ['keep']}))
        else:
            self.target.write_text('# keep\ndb tunnel - zone vm 5431 5431\n'
                                   '  > DB localhost:{port}\n# next comment\nother ssh - - other-vm\n')
        self.env['IAP_CONF'] = str(self.target)
        return self.target.read_bytes()

    def action(self, action, name=None, answers=('',), ok=True, client=None):
        inputs = self.root / 'answers.json'
        inputs.write_text(json.dumps(list(answers)))
        harness = self.root / 'manage-harness.ps1'
        harness.write_text(r'''
param($Client, $Action, $Name, $Inputs)
$ErrorActionPreference='Stop'
$global:Queue=[Collections.Generic.Queue[string]]::new()
foreach ($value in (Get-Content -LiteralPath $Inputs -Raw | ConvertFrom-Json)) { $global:Queue.Enqueue([string]$value) }
function global:Read-Host {
    param($Prompt)
    if (-not $global:Queue.Count) { throw 'Input cancelled' }
    return $global:Queue.Dequeue()
}
if ($Name) { & $Client $Action $Name } else { & $Client $Action }
''')
        return self.run_ps(harness, '-Client', client or ROOT / 'iap.ps1', '-Action', action,
                           '-Name', name or '', '-Inputs', inputs, ok=ok)

    def editor(self, replacement='6543', code=0):
        editor = self.root / 'editor.ps1'
        editor.write_text('param($Target)\n$text=[IO.File]::ReadAllText($Target)\n'
                          f"[IO.File]::WriteAllText($Target, $text.Replace('5431','{replacement}'))\nexit {code}\n")
        self.env['EDITOR'] = str(editor)

    def test_remove_and_reset_preserve_other_data(self):
        for structured in (False, True):
            before = self.seed(structured)
            self.action('remove', 'db')
            self.assertEqual(self.target.read_bytes(), before)
            self.action('remove', 'db', ['y'])
            self.assertIn('other-vm', self.target.read_text())
            self.assertNotIn('localhost:{port}', self.target.read_text())
            self.action('reset', answers=['y'])
            if structured:
                data = json.loads(self.target.read_text())
                self.assertEqual(data['hosts'], {})
                self.assertEqual(data['defaults'], {'project': 'keep'})
                self.assertEqual(data['extra'], ['keep'])
            else:
                self.assertEqual(self.run_ps(ROOT / 'iap.ps1', 'names').stdout, '')

    def test_targeted_edit_and_invalid_port(self):
        for structured in (False, True):
            self.seed(structured)
            self.editor()
            self.action('edit', 'db', ['y'])
            self.assertIn('6543', self.target.read_text())
            self.assertIn('other-vm', self.target.read_text())
            before = self.seed(structured)
            self.editor('99999')
            self.action('edit', 'db', ['y'], ok=False)
            self.assertEqual(self.target.read_bytes(), before)

    def test_edit_cancel_and_editor_failure(self):
        before = self.seed()
        self.editor()
        self.action('edit', 'db')
        self.assertEqual(self.target.read_bytes(), before)
        self.editor(code=1)
        self.action('edit', 'db', ok=False)
        self.assertEqual(self.target.read_bytes(), before)

    def test_uninstall_preserves_bash_and_config(self):
        before = self.seed()
        self.action('uninstall', answers=['y'], ok=False)
        bindir = self.root / 'bin'
        self.run_ps(ROOT / 'install.ps1', '-BinDir', bindir)
        (bindir / 'iap').write_text('keep Bash')
        (bindir / '.iap/scripts/setup.sh').write_text('keep Bash setup')
        self.action('uninstall', client=bindir / 'iap.ps1')
        self.assertTrue((bindir / 'iap.ps1').exists())
        self.action('uninstall', answers=['y'], client=bindir / 'iap.ps1')
        self.assertFalse((bindir / 'iap.ps1').exists())
        self.assertTrue((bindir / 'iap').exists())
        self.assertTrue((bindir / '.iap/scripts/setup.sh').exists())
        self.assertEqual(self.target.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
