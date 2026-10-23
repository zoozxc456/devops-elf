"""Exercise the wizard through stdin; configuration files are written only under tmp."""
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/setup.sh'
PASSWORD = r'literal-$value\with#hash'


def run_wizard(output, mode, answers, env=None):
    return subprocess.run(
        ['bash', str(SCRIPT), mode, '--output-dir', str(output)],
        input='\n'.join(answers) + '\n', text=True, capture_output=True,
        env=env, timeout=30,
    )


class SetupTests(unittest.TestCase):
    def test_agent_retries_invalid_address_and_defaults_to_no_plugins(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = run_wizard(root, 'agent', ['', '', '', '', '', '999.1.1.1', '127.0.0.1', '10.2.0.10', '', ''])
            self.assertEqual(result.returncode, 0, result.stderr)
            settings = root / 'agent/.env'
            self.assertIn('http://10.2.0.10:3100', settings.read_text())
            self.assertEqual(stat.S_IMODE(settings.stat().st_mode), 0o600)
            marker = root / 'agent/generated/.lookout-generated'
            self.assertEqual(json.loads(marker.read_text())['plugins'], [])

    def test_server_keeps_password_literal_and_plugin_files_readable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = run_wizard(root, 'server', [''] * 9 + ['y', 'y', PASSWORD, PASSWORD])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(PASSWORD, result.stdout + result.stderr)
            settings = root / 'server/.env'
            self.assertIn("GRAFANA_ADMIN_PASSWORD='" + PASSWORD + "'", settings.read_text())
            self.assertEqual(stat.S_IMODE(settings.stat().st_mode), 0o600)
            dashboards = root / 'server/generated/dashboards'
            self.assertTrue((dashboards / 'odoo-logs.json').is_file())
            self.assertTrue((dashboards / 'nginx.json').is_file())
            self.assertEqual(stat.S_IMODE(dashboards.stat().st_mode), 0o755)
            if shutil.which('docker'):
                shutil.copy(ROOT / 'server/docker-compose.yml', root / 'server/docker-compose.yml')
                parsed = subprocess.run(['docker', 'compose', '--project-directory', str(root / 'server'), 'config', '--format', 'json'], capture_output=True, text=True)
                self.assertEqual(parsed.returncode, 0, parsed.stderr)
                # config escapes literal $ as $$ for a reusable Compose document.
                # --environment reports the actual .env value before that serialization.
                environment = subprocess.run(['docker', 'compose', '--project-directory', str(root / 'server'), 'config', '--environment'], capture_output=True, text=True)
                self.assertEqual(environment.returncode, 0, environment.stderr)
                values = dict(line.split('=', 1) for line in environment.stdout.splitlines() if '=' in line)
                self.assertEqual(values['GRAFANA_ADMIN_PASSWORD'], PASSWORD)

    def test_declining_replacement_leaves_files_untouched(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'agent').mkdir()
            settings = root / 'agent/.env'
            settings.write_text('KEEP=existing\n')
            result = run_wizard(root, 'agent', [''])
            self.assertEqual(result.returncode, 0)
            self.assertEqual(settings.read_text(), 'KEEP=existing\n')
            self.assertFalse((root / 'agent/generated').exists())
            self.assertEqual(list((root / 'agent').glob('.env.backup-*')), [])

    def test_confirmed_replacement_makes_private_backup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'agent').mkdir()
            settings = root / 'agent/.env'
            settings.write_text('PG_DSN_CUSTOM=existing\n')
            result = run_wizard(root, 'agent', ['y'] + [''] * 8)
            self.assertEqual(result.returncode, 0, result.stderr)
            backups = list((root / 'agent').glob('.env.backup-*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), 'PG_DSN_CUSTOM=existing\n')
            self.assertEqual(stat.S_IMODE(backups[0].stat().st_mode), 0o600)

    @unittest.skipUnless(shutil.which('ansible-vault') and shutil.which('ansible-inventory'), 'Ansible required for real Vault encryption test')
    def test_ansible_generates_readable_inventory_and_preserves_existing_vault(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            vault_password = root / 'vault-password'
            vault_password.write_text('test-vault-password\n')
            vault_password.chmod(0o600)
            env = dict(os.environ, ANSIBLE_VAULT_PASSWORD_FILE=str(vault_password), ANSIBLE_HOME=str(root / 'ansible-home'))
            answers = [''] * 13 + ['y', 'y', '', '', '1', 'app-one', '10.0.0.21', 'staging', 'myapp_default', 'staging|dev']
            result = run_wizard(root, 'ansible', answers + [PASSWORD, PASSWORD], env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(PASSWORD, result.stdout + result.stderr)
            vault = root / 'deploy/group_vars/all/vault.yml'
            self.assertTrue(vault.read_text().startswith('$ANSIBLE_VAULT;'))
            ciphertext = vault.read_bytes()
            self.assertNotIn(PASSWORD.encode(), ciphertext)
            # Include tracked group defaults to verify the wizard host vars take precedence.
            shutil.copy(ROOT / 'deploy/group_vars/all/main.yml', root / 'deploy/group_vars/all/main.yml')
            inventory = root / 'deploy/inventory.local.yml'
            parsed = subprocess.run(['ansible-inventory', '-i', str(inventory), '--list'], env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(parsed.returncode, 0, parsed.stderr)
            data = json.loads(parsed.stdout)
            hosts = data['_meta']['hostvars']
            self.assertEqual(hosts['app-one']['lookout_server_ip'], '10.0.0.10')
            self.assertEqual(hosts['app-one']['lookout_plugins'], ['odoo', 'nginx'])
            self.assertEqual(hosts['app-one']['app_network'], 'myapp_default')
            password_value = hosts['app-one']['vault_grafana_admin_password']
            if isinstance(password_value, dict):  # ansible-core 2.21's JSON representation
                password_value = password_value['__ansible_unsafe']
            self.assertEqual(password_value, PASSWORD)
            self.assertIn('monitoring', data['lookout_agent']['hosts'])
            self.assertEqual(stat.S_IMODE(inventory.stat().st_mode), 0o600)
            result = run_wizard(root, 'ansible', ['y'] + answers, env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(vault.read_bytes(), ciphertext)
            self.assertEqual(len(list(inventory.parent.glob('inventory.local.yml.backup-*'))), 1)
            # Server-only deployments must still produce a valid inventory.
            result = run_wizard(root, 'ansible', ['y'] + [''] * 15 + ['n', '0'], env)
            self.assertEqual(result.returncode, 0, result.stderr)
            parsed = subprocess.run(['ansible-inventory', '-i', str(inventory), '--list'], env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(parsed.returncode, 0, parsed.stderr)
            data = json.loads(parsed.stdout)
            self.assertNotIn('lookout_agent', data)
            self.assertEqual(vault.read_bytes(), ciphertext)


if __name__ == '__main__':
    unittest.main()
