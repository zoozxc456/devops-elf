"""Run native PowerShell wizard logic with queued Read-Host answers in temporary trees."""
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')
PASSWORD = r'literal-$value\with#hash'
HARNESS = r'''
param([string]$Wizard, [string]$AnswersPath, [string]$OutputRoot, [string]$WizardMode)
$ErrorActionPreference='Stop'
$global:WizardAnswers=[Collections.Generic.Queue[string]]::new()
foreach ($answer in (Get-Content -LiteralPath $AnswersPath -Raw -Encoding utf8 | ConvertFrom-Json)) {
    $global:WizardAnswers.Enqueue([string]$answer)
}
function global:Read-Host {
    param([string]$Prompt, [switch]$AsSecureString)
    if ($global:WizardAnswers.Count -eq 0) { throw 'No queued input remaining' }
    $value=$global:WizardAnswers.Dequeue()
    if ($AsSecureString) { return (ConvertTo-SecureString -String $value -AsPlainText -Force) }
    return $value
}
& $Wizard -Mode $WizardMode -OutputDir $OutputRoot
if ($global:WizardAnswers.Count -ne 0) { throw 'Unused queued answers' }
'''


@unittest.skipUnless(PWSH, 'PowerShell 7.2+ required')
class PowerShellSetupTests(unittest.TestCase):
    def run_wizard(self, root, mode, answers, env=None):
        harness = root / 'harness.ps1'
        harness.write_text(HARNESS)
        inputs = root / 'answers.json'
        inputs.write_text(json.dumps(answers))
        inputs.chmod(0o600)
        return subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-File', str(harness),
                               '-Wizard', str(ROOT / 'scripts/setup.ps1'), '-AnswersPath', str(inputs),
                               '-OutputRoot', str(root), '-WizardMode', mode],
                              capture_output=True, text=True, timeout=40, env=env)

    def test_agent_retries_invalid_ip_and_defaults_to_core(self):
        with tempfile.TemporaryDirectory(prefix='lookout config ') as temporary:
            root = Path(temporary)
            result = self.run_wizard(root, 'agent', [''] * 5 + ['999.1.1.1', '127.0.0.1', '10.2.0.10', '', ''])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            settings = root / 'agent/.env'
            self.assertIn('http://10.2.0.10:3100', settings.read_text())
            self.assertFalse(settings.read_bytes().startswith(b'\xef\xbb\xbf'))
            self.assertNotIn(b'\r', settings.read_bytes())
            self.assertEqual(json.loads((root / 'agent/generated/.lookout-generated').read_text())['plugins'], [])
            if os.name != 'nt':
                self.assertEqual(stat.S_IMODE(settings.stat().st_mode), 0o600)

    def test_server_password_and_plugins(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = self.run_wizard(root, 'server', [''] * 9 + ['y', 'y', 'mismatch-one', 'mismatch-two', PASSWORD, PASSWORD])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn(PASSWORD, result.stdout + result.stderr)
            self.assertIn("GRAFANA_ADMIN_PASSWORD='" + PASSWORD + "'", (root / 'server/.env').read_text())
            self.assertIn("LOOKOUT_DATA_DIR='/opt/lookout/server/data'", (root / 'server/.env').read_text())
            self.assertTrue((root / 'server/generated/dashboards/nginx.json').is_file())
            self.assertTrue((root / 'server/generated/dashboards/odoo-logs.json').is_file())

    def test_existing_env_is_preserved_or_privately_backed_up(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'agent').mkdir()
            target = root / 'agent/.env'
            target.write_text('KEEP=existing\n')
            result = self.run_wizard(root, 'agent', [''])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(target.read_text(), 'KEEP=existing\n')
            self.assertFalse((root / 'agent/generated').exists())
            result = self.run_wizard(root, 'agent', ['y'] + [''] * 8)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            backups = list((root / 'agent').glob('.env.backup-*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), 'KEEP=existing\n')
            if os.name != 'nt':
                self.assertEqual(stat.S_IMODE(backups[0].stat().st_mode), 0o600)

    @unittest.skipIf(os.name == 'nt', 'Native Unix vault path; Windows WSL bridge requires a Windows runner')
    @unittest.skipUnless(shutil.which('ansible-vault') and shutil.which('ansible-inventory'), 'Ansible required')
    def test_ansible_real_vault_and_host_inventory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            password_file = root / 'vault-password'
            password_file.write_text('test-vault-password\n')
            password_file.chmod(0o600)
            env = dict(os.environ, ANSIBLE_VAULT_PASSWORD_FILE=str(password_file), ANSIBLE_HOME=str(root / 'ansible-home'))
            answers = [''] * 13 + ['y', 'y', '', '', '1', 'app-one', '10.0.0.21', 'staging', 'myapp_default', 'staging|dev']
            result = self.run_wizard(root, 'ansible', answers + [PASSWORD, PASSWORD], env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn(PASSWORD, result.stdout + result.stderr)
            vault = root / 'deploy/group_vars/all/vault.yml'
            cipher = vault.read_bytes()
            self.assertTrue(cipher.startswith(b'$ANSIBLE_VAULT;'))
            self.assertNotIn(PASSWORD.encode(), cipher)
            shutil.copy(ROOT / 'deploy/group_vars/all/main.yml', root / 'deploy/group_vars/all/main.yml')
            inventory = root / 'deploy/inventory.local.yml'
            parsed = subprocess.run(['ansible-inventory', '-i', str(inventory), '--list'], env=env, capture_output=True, text=True)
            self.assertEqual(parsed.returncode, 0, parsed.stderr)
            data = json.loads(parsed.stdout)
            host = data['_meta']['hostvars']['app-one']
            self.assertEqual(host['app_network'], 'myapp_default')
            self.assertEqual(host['lookout_server_ip'], '10.0.0.10')
            self.assertEqual(host['lookout_plugins'], ['odoo', 'nginx'])
            value = host['vault_grafana_admin_password']
            if isinstance(value, dict): value = value['__ansible_unsafe']
            self.assertEqual(value, PASSWORD)
            result = self.run_wizard(root, 'ansible', ['y'] + [''] * 15 + ['n', '0'], env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(vault.read_bytes(), cipher)
            parsed = subprocess.run(['ansible-inventory', '-i', str(inventory), '--list'], env=env, capture_output=True, text=True)
            self.assertEqual(parsed.returncode, 0, parsed.stderr)
            self.assertNotIn('lookout_agent', json.loads(parsed.stdout))


if __name__ == '__main__':
    unittest.main()
