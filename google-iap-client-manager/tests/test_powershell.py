import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')
HARNESS = r'''
param($Script, $Answers, $ConfigPath, [switch]$AddNew)
$ErrorActionPreference = 'Stop'
$global:AnswersQueue = [Collections.Generic.Queue[string]]::new()
foreach ($answer in (Get-Content -Raw -LiteralPath $Answers | ConvertFrom-Json)) {
    $global:AnswersQueue.Enqueue([string]$answer)
}
function global:Read-Host {
    param($Prompt)
    if (-not $global:AnswersQueue.Count) { throw 'Input cancelled' }
    return $global:AnswersQueue.Dequeue()
}
if ($AddNew) { & $Script new -Config $ConfigPath } else { & $Script -Config $ConfigPath }
if ($global:AnswersQueue.Count) { throw 'Unused answers' }
'''


@unittest.skipUnless(PWSH, 'PowerShell 7.2+ required')
class PowerShellTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='iap powershell ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.target = self.root / 'config/hosts'
        self.env = dict(os.environ, IAP_CONF=str(self.target),
                        XDG_CONFIG_HOME=str(self.root / 'xdg'))

    def run_ps(self, script, *args, ok=True):
        if Path(script).name == 'install.ps1':
            args = (*args, '-NoPath')
        result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-File', str(script),
                                 *map(str, args)], env=self.env, capture_output=True,
                                text=True, timeout=20)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def wizard(self, answers, ok=True, new=False):
        harness = self.root / 'harness.ps1'
        harness.write_text(HARNESS)
        inputs = self.root / 'answers.json'
        inputs.write_text(json.dumps(answers))
        script = ROOT / ('iap.ps1' if new else 'scripts/setup.ps1')
        extra = ['-AddNew'] if new else []
        return self.run_ps(harness, '-Script', script,
                           '-Answers', inputs, '-ConfigPath', self.target, *extra, ok=ok)

    def ssh_answers(self):
        return ['', '', 'app-vm', '', '', '', '', 'n', 'n']

    def test_setup_text_and_native_client(self):
        self.wizard(self.ssh_answers())
        self.assertEqual(self.run_ps(ROOT / 'iap.ps1', 'names').stdout.strip(), 'app-vm')
        self.assertFalse(self.target.read_bytes().startswith(b'\xef\xbb\xbf'))
        self.assertNotIn(b'\r', self.target.read_bytes())
        if os.name != 'nt':
            self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)

    def test_new_preserves_text_and_private_backup(self):
        self.target.parent.mkdir()
        original = b'# keep\r\nold ssh - - old\r\n  > literal endpoint'
        self.target.write_bytes(original)
        self.wizard(['new', 'old', 'new-ssh', 'ssh', '-', '-', 'user@vm', 'n'], new=True)
        self.assertTrue(self.target.read_bytes().startswith(original + b'\n'))
        backup, = self.target.parent.glob('hosts.backup-*')
        self.assertEqual(backup.read_bytes(), original)
        self.assertEqual(self.run_ps(ROOT / 'iap.ps1', 'names').stdout.splitlines(), ['old', 'new-ssh'])

    def test_new_structured_preserves_defaults_endpoints_and_metadata(self):
        for suffix in ('json','yaml','yml'):
            self.target = self.root / ('hosts.' + suffix)
            original = {'defaults': {'project': 'old-project'},
                        'hosts': {'old': {'endpoints': {'Web': 'url'}}}, 'metadata': ['keep']}
            self.target.write_text(json.dumps(original))
            self.wizard(['old','new-web','tunnel','','','vm','8080','18080',
                         'y','Web http://localhost:{port}','n'], new=True)
            actual = json.loads(self.target.read_text())
            self.assertEqual(actual['hosts']['old'], original['hosts']['old'])
            self.assertEqual(actual['defaults'], original['defaults'])
            self.assertEqual(actual['metadata'], ['keep'])
            self.assertEqual(actual['hosts']['new-web']['project'], '-')
            self.assertEqual(actual['hosts']['new-web']['local_port'], 18080)

    def test_new_cancellation_and_missing_config(self):
        self.wizard(['new-ssh','','','','','n'], new=True)
        before = self.target.read_bytes()
        self.wizard(['another','ssh'], new=True, ok=False)
        self.assertEqual(self.target.read_bytes(), before)
        self.assertFalse(list(self.target.parent.glob('hosts.backup-*')))

    def test_structured_formats_with_tunnel_literal_endpoints(self):
        endpoint = 'Web http://localhost:{port}/?q="hi"&path=\\data&x=$(throw "oops")'
        for suffix in ('json', 'yaml', 'yml'):
            self.target = self.root / ('hosts.' + suffix)
            self.env['IAP_CONF'] = str(self.target)
            self.wizard(['my-project', 'us-central1-a', 'web', 'tunnel', '', '', 'vm',
                         '0', '65536', '8080', '18080', 'y', endpoint, 'n', 'n'])
            host = json.loads(self.target.read_text())['hosts']['web']
            self.assertEqual(host['remote_port'], 8080)
            self.assertEqual(host['endpoints'], [endpoint])
            shown = self.run_ps(ROOT / 'iap.ps1', 'show', 'web').stdout
            self.assertIn(endpoint.replace('{port}', '18080'), shown)

    def test_defaults_yaml_and_endpoint_map(self):
        self.target = self.root / 'hosts.json'
        self.env['IAP_CONF'] = str(self.target)
        self.target.write_text(json.dumps({'defaults': {'project': 'my-project'},
            'hosts': {'web': {'type': 'tunnel', 'remote_port': 8080,
                              'endpoints': {'Web': 'http://localhost:{port}'}}}}))
        shown = self.run_ps(ROOT / 'iap.ps1', 'show', 'web').stdout
        self.assertIn('Web  http://localhost:8080', shown)
        self.assertIn('my-project', self.run_ps(ROOT / 'iap.ps1', 'ls').stdout)

    def test_cancel_backup_and_eof(self):
        self.target.parent.mkdir()
        self.target.write_text('original\n')
        self.wizard([''])
        self.assertEqual(self.target.read_text(), 'original\n')
        self.wizard(['y', '', ''], ok=False)
        self.assertEqual(self.target.read_text(), 'original\n')
        self.assertFalse(list(self.target.parent.glob('hosts.backup-*')))
        self.wizard(['y'] + self.ssh_answers())
        backup, = self.target.parent.glob('hosts.backup-*')
        self.assertEqual(backup.read_text(), 'original\n')
        if os.name != 'nt':
            self.assertEqual(backup.stat().st_mode & 0o777, 0o600)

    def test_install_wrapper_and_preserve_regular_file(self):
        bindir = self.root / "bin's directory"
        self.run_ps(ROOT / 'install.ps1', '-BinDir', bindir)
        self.run_ps(ROOT / 'install.ps1', '-BinDir', bindir)
        self.assertIn('0.4.1', self.run_ps(bindir / 'iap.ps1', 'version').stdout)
        self.run_ps(bindir / 'iap.ps1', 'setup', '-Help')
        (bindir / 'iap.ps1').write_text('original')
        self.run_ps(ROOT / 'install.ps1', '-BinDir', bindir, ok=False)
        self.assertEqual((bindir / 'iap.ps1').read_text(), 'original')

    def test_copied_install_survives_source_removal(self):
        source = self.root / 'source'
        shutil.copytree(ROOT, source)
        bindir = self.root / 'bin'
        self.run_ps(source / 'install.ps1', '-BinDir', bindir)
        installed = bindir / 'iap.ps1'
        self.assertFalse(installed.is_symlink())
        self.assertEqual(installed.read_bytes(), (source / 'iap.ps1').read_bytes())
        shutil.rmtree(source)
        self.run_ps(installed, 'setup', '-Help')
        self.wizard(self.ssh_answers())
        self.assertIn('app-vm', self.run_ps(installed, 'names').stdout)
        self.assertIn('安裝來源', self.run_ps(installed, 'update', ok=False).stderr)
        self.assertTrue((bindir / '.iap/completions/iap.ps1').is_file())

    def test_gcloud_arguments_and_failure_exit_code(self):
        self.wizard(self.ssh_answers())
        script = self.root / 'fake-gcloud.ps1'
        script.write_text(r'''
param($Client)
function global:gcloud { $args | ConvertTo-Json -Compress; $global:LASTEXITCODE = 0 }
& $Client app-vm -- -L '5432:localhost:5432'
''')
        output = self.run_ps(script, ROOT / 'iap.ps1').stdout.splitlines()[-1]
        self.assertEqual(json.loads(output), ['compute', 'ssh', 'app-vm',
            '--tunnel-through-iap', '-L', '5432:localhost:5432'])
        script.write_text(r'''
param($Client)
function global:gcloud { $global:LASTEXITCODE = 23 }
& $Client app-vm
exit $LASTEXITCODE
''')
        self.assertEqual(self.run_ps(script, ROOT / 'iap.ps1', ok=False).returncode, 23)

    def test_symlink_and_help(self):
        self.run_ps(ROOT / 'scripts/setup.ps1', '-Help')
        self.assertFalse(self.target.exists())
        if os.name == 'nt':
            return  # Symlink creation may require Windows Developer Mode.
        original = self.root / 'original'
        original.write_text('untouched')
        self.target.parent.mkdir()
        self.target.symlink_to(original)
        self.wizard([], ok=False)
        self.assertEqual(original.read_text(), 'untouched')

    @unittest.skipIf(os.name == 'nt', 'Unix executable stub')
    def test_native_gcloud_passthrough_and_tunnel_readiness(self):
        self.wizard(self.ssh_answers())
        bindir = self.root / 'fake-bin'
        bindir.mkdir()
        gcloud = bindir / 'gcloud'
        gcloud.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        gcloud.chmod(0o755)
        self.env['PATH'] = str(bindir) + os.pathsep + self.env['PATH']
        result = self.run_ps(ROOT / 'iap.ps1', 'app-vm', '--', '-L', '5432:localhost:5432')
        self.assertEqual(result.stdout.splitlines()[1:], ['compute', 'ssh', 'app-vm',
            '--tunnel-through-iap', '--', '-L', '5432:localhost:5432'])
        self.target.write_text('web tunnel my-project us-central1-a vm 8080 18080\n'
                               '  > Web http://localhost:{port}\n')
        gcloud.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\necho "Listening on port 18080" >&2\nexit 17\n')
        result = self.run_ps(ROOT / 'iap.ps1', 'web', ok=False)
        self.assertEqual(result.returncode, 17)
        self.assertIn('--local-host-port=localhost:18080', result.stdout)
        self.assertIn('http://localhost:18080', result.stdout)
        self.assertLess(result.stdout.index('http://localhost:18080'),
                        result.stdout.index('start-iap-tunnel'))

    def test_install_setup_and_client_config_dispatch(self):
        harness = self.root / 'install-harness.ps1'
        harness.write_text(r'''
param($Installer, $Client, $Target, $BinDir)
$global:Queue = [Collections.Generic.Queue[string]]::new()
function global:Read-Host {
    param($Prompt)
    if (-not $global:Queue.Count) { throw 'No input' }
    return $global:Queue.Dequeue()
}
foreach ($answer in @('','','app-vm','','','','','n','n')) { $global:Queue.Enqueue($answer) }
& $Installer -BinDir $BinDir -Setup -NoPath
foreach ($answer in @('','','new-vm','','','','','n','n')) { $global:Queue.Enqueue($answer) }
& $Client setup -Config $Target
''')
        alternate = self.root / 'alternate/hosts'
        self.run_ps(harness, ROOT / 'install.ps1', ROOT / 'iap.ps1',
                    alternate, self.root / 'bin')
        self.assertIn('app-vm', self.target.read_text())
        self.assertIn('new-vm', alternate.read_text())


if __name__ == '__main__':
    unittest.main()
