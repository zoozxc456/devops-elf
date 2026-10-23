import json
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_CONFIG_HOME=str(self.home / "config"))
        self.env.pop("IAP_CONF", None)
        self.target = self.home / "config/iap/hosts"
        self.fake_bin = self.home / "fake-bin"
        self.fake_bin.mkdir()
        gcloud = self.fake_bin / "gcloud"
        gcloud.write_text('#!/bin/bash\nprintf "%s\\n" "$@"\n')
        gcloud.chmod(0o755)
        self.env["PATH"] = str(self.fake_bin) + os.pathsep + self.env["PATH"]

    def run_cli(self, script, *args, answers="", ok=True):
        if Path(script).name == 'install.sh':
            args = (*args, '--no-path')
        result = subprocess.run(
            ["/bin/bash", str(ROOT / script), *map(str, args)],
            input=answers, capture_output=True, text=True, env=self.env,
            cwd=self.home, timeout=10,
        )
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def ssh_answers(self, name="app-vm"):
        return f"\n\n{name}\n\n\n\n\nn\nn\n"

    def test_ssh_defaults_and_actual_command(self):
        self.run_cli("iap", "setup", answers=self.ssh_answers())
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertIn("app-vm", self.run_cli("iap", "ls").stdout)
        command = self.run_cli("iap", "app-vm", "--", "-L", "5432:localhost:5432")
        self.assertEqual(command.stdout.splitlines(), [
            "compute", "ssh", "app-vm", "--tunnel-through-iap",
            "--", "-L", "5432:localhost:5432"])

    def test_multiple_hosts_tunnel_and_literal_endpoints(self):
        marker = self.home / "must-not-exist"
        endpoint = f'Web http://localhost:{{port}}/$(touch {marker})'
        answers = ("my-project\nus-central1-a\napp-web\ntunnel\n\n\napp-vm\n"
                   f"8080\n18080\ny\n{endpoint}\nn\ny\n"
                   "app-ssh\nssh\nother-project\nus-central1-b\nuser@app-vm\nn\nn\n")
        self.run_cli("scripts/setup.sh", answers=answers)
        self.assertEqual(self.run_cli("iap", "names").stdout.splitlines(),
                         ["app-web", "app-ssh"])
        shown = self.run_cli("iap", "show", "app-web").stdout
        self.assertIn("http://localhost:18080/$(touch", shown)
        self.assertFalse(marker.exists())
        command = self.run_cli("iap", "app-ssh").stdout.splitlines()
        self.assertIn("other-project", command)
        self.assertIn("user@app-vm", command)

    def test_confirmed_replacement_has_private_backup(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_text("original\n")
        self.run_cli("iap", "setup", answers="y\n" + self.ssh_answers())
        backups = list(self.target.parent.glob("hosts.backup-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "original\n")
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)

    def test_replacement_defaults_to_no(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_text("original\n")
        self.run_cli("iap", "setup", answers="\n")
        self.assertEqual(self.target.read_text(), "original\n")
        self.assertEqual(list(self.target.parent.glob("*.backup-*")), [])

    def test_eof_does_not_change_existing_config(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_text("original\n")
        self.run_cli("iap", "setup", answers="y\n\n\napp-vm\n", ok=False)
        self.assertEqual(self.target.read_text(), "original\n")
        self.assertEqual(list(self.target.parent.glob("*.backup-*")), [])

    def test_validation_reserved_duplicate_and_ports(self):
        answers = ("\n\nsetup\nweb\ntunnel\n\n\nvm\n0\n65536\nabc\n8080\n"
                   "00080\n18080\nn\ny\nweb\nssh-vm\nssh\n\n\n\nn\nn\n")
        self.run_cli("iap", "setup", answers=answers)
        self.assertEqual(self.run_cli("iap", "names").stdout.splitlines(),
                         ["web", "ssh-vm"])
        self.assertIn("8080 18080", self.target.read_text())

    def test_structured_formats_and_existing_file_discovery(self):
        for extension in ("json", "yaml", "yml"):
            target = self.target.with_suffix("." + extension)
            self.run_cli("iap", "setup", "--config", target,
                         answers=self.ssh_answers())
            content = json.loads(target.read_text())
            self.assertEqual(content["hosts"]["app-vm"],
                             {"type": "ssh", "instance": "app-vm"})
            self.assertFalse(self.target.exists())
            if shutil.which("jq") and (extension == "json" or
                    importlib.util.find_spec("yaml") or shutil.which("yq")):
                self.assertIn("app-vm", self.run_cli("iap", "names").stdout)
            # The next setup discovers the structured file even without --config.
            self.run_cli("iap", "setup", answers="y\n" + self.ssh_answers("new-vm"))
            self.assertIn("new-vm", json.loads(target.read_text())["hosts"])
            target.unlink()

    def test_config_flag_takes_precedence_over_environment(self):
        self.env["IAP_CONF"] = str(self.home / "environment-hosts")
        target = self.home / "custom directory/hosts"
        self.run_cli("iap", "setup", "--config", target, answers=self.ssh_answers())
        self.assertTrue(target.exists())
        self.assertFalse(Path(self.env["IAP_CONF"]).exists())
        self.env["IAP_CONF"] = str(target)
        self.assertIn("app-vm", self.run_cli("iap", "ls").stdout)

    def test_home_config_fallback_and_tunnel_command(self):
        self.env.pop("XDG_CONFIG_HOME")
        answers = "\n\nweb\ntunnel\n\n\nvm\n8080\n\nn\nn\n"
        self.run_cli("iap", "setup", answers=answers)
        target = self.home / ".config/iap/hosts"
        self.assertTrue(target.exists())
        command = self.run_cli("iap", "web").stderr
        self.assertIn("start-iap-tunnel", command)
        self.assertIn("--local-host-port=localhost:8080", command)

    def test_tunnel_hints_appear_before_readiness(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_text('db tunnel - asia-east1-c vm 5431 5431\n'
                               '  > PostgreSQL localhost:{port}\n')
        result = self.run_cli('iap', 'db')
        self.assertIn('PostgreSQL  localhost:5431', result.stderr)
        self.assertLess(result.stderr.index('localhost:5431', result.stderr.index('PostgreSQL')),
                        result.stderr.index('start-iap-tunnel'))
        self.assertNotIn('已連線', result.stdout)

    def test_new_appends_ssh_preserving_existing_bytes_and_backup(self):
        self.target.parent.mkdir(parents=True)
        original = b'# keep comment\r\nold tunnel project zone vm 8080 18080\r\n  > URL http://localhost:{port}'
        self.target.write_bytes(original)
        self.run_cli('iap', 'new', answers='oneclick-ssh\nssh\nmy-project\nus-central1-a\nuser@vm\nn\n')
        self.assertTrue(self.target.read_bytes().startswith(original + b'\n'))
        self.assertIn('oneclick-ssh ssh my-project us-central1-a user@vm', self.target.read_text())
        backup, = self.target.parent.glob('hosts.backup-*')
        self.assertEqual(backup.read_bytes(), original)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)

    def test_new_rejects_duplicate_and_reserved_names_and_creates_missing_config(self):
        self.run_cli('iap', 'new', answers='new\nssh-vm\n\n\n\n\nn\n')
        self.run_cli('iap', 'new', answers='ssh-vm\nweb\ntunnel\n\n\nvm\n8080\n18080\ny\nWeb http://localhost:{port}\nn\n')
        self.assertEqual(self.run_cli('iap', 'names').stdout.splitlines(), ['ssh-vm', 'web'])
        self.assertIn('http://localhost:18080', self.run_cli('iap', 'show', 'web').stdout)

    def test_new_preserves_structured_defaults_and_extra_fields(self):
        for suffix in ('json', 'yaml', 'yml'):
            target = self.home / ('hosts.' + suffix)
            original = {'defaults': {'project': 'old-project', 'zone': 'old-zone'},
                        'hosts': {'old': {'instance': 'old-vm', 'endpoints': {'Web': 'url'}}},
                        'notes': {'keep': ['all', 'fields']}}
            target.write_text(json.dumps(original))
            self.run_cli('iap', 'new', '--config', target, answers='old\nssh-vm\n\n\n\n\nn\n')
            actual = json.loads(target.read_text())
            self.assertEqual(actual['defaults'], original['defaults'])
            self.assertEqual(actual['hosts']['old'], original['hosts']['old'])
            self.assertEqual(actual['notes'], original['notes'])
            self.assertEqual(actual['hosts']['ssh-vm']['project'], '-')
            self.assertEqual(actual['hosts']['ssh-vm']['zone'], '-')

    def test_new_cancellation_and_invalid_structured_config_leave_original(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_text('old ssh - - old\n')
        before = self.target.read_bytes()
        self.run_cli('iap', 'new', answers='new-host\nssh\n', ok=False)
        self.assertEqual(self.target.read_bytes(), before)
        self.assertFalse(list(self.target.parent.glob('*.backup-*')))
        target = self.home / 'broken.json'
        target.write_text('{broken')
        self.run_cli('iap', 'new', '--config', target, ok=False)
        self.assertEqual(target.read_text(), '{broken')

    def test_structured_tunnel_serialization_preserves_endpoints(self):
        target = self.home / "hosts.json"
        self.env["IAP_CONF"] = str(target)
        endpoint = '入口 http://localhost:{port}/?q="hello"&path=\\data'
        answers = ("my-project\nus-central1-a\nweb\ntunnel\n\n\nvm\n8080\n18080\n"
                   f"y\n{endpoint}\nn\nn\n")
        self.run_cli("iap", "setup", answers=answers)
        host = json.loads(target.read_text())["hosts"]["web"]
        self.assertEqual(host["remote_port"], 8080)
        self.assertEqual(host["local_port"], 18080)
        self.assertEqual(host["project"], "my-project")
        self.assertEqual(host["endpoints"], [endpoint])
        if shutil.which("jq"):
            self.assertIn(endpoint.split(" ", 1)[1].replace("{port}", "18080"),
                          self.run_cli("iap", "show", "web").stdout)

    def test_symlink_target_is_rejected(self):
        original = self.home / "original"
        original.write_text("untouched")
        self.target.parent.mkdir(parents=True)
        self.target.symlink_to(original)
        self.run_cli("iap", "setup", ok=False)
        self.assertEqual(original.read_text(), "untouched")

    def test_install_with_setup_and_repeat_install(self):
        bindir = self.home / "local bin"
        self.run_cli("install.sh", "--bin-dir", bindir, "--setup",
                     answers=self.ssh_answers())
        self.assertFalse((bindir / "iap").is_symlink())
        self.assertEqual((bindir / "iap").read_bytes(), (ROOT / "iap").read_bytes())
        self.run_cli("install.sh", "--bin-dir", bindir)
        result = subprocess.run(
            [str(bindir / "iap"), "setup", "--help"], env=self.env,
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--config", result.stdout)

    def test_copied_install_survives_source_removal_and_migrates_symlink(self):
        source = self.home / 'source'
        import shutil
        shutil.copytree(ROOT, source)
        bindir = self.home / 'bin'
        bindir.mkdir()
        (bindir / 'iap').symlink_to(source / 'iap')
        before = (source / 'iap').read_bytes()
        self.run_cli(source / 'install.sh', '--bin-dir', bindir)
        self.assertFalse((bindir / 'iap').is_symlink())
        self.assertEqual((source / 'iap').read_bytes(), before)
        shutil.rmtree(source)
        self.run_cli(bindir / 'iap', 'setup', answers=self.ssh_answers())
        self.assertIn('app-vm', self.run_cli(bindir / 'iap', 'ls').stdout)
        self.assertTrue((bindir / '.iap/completions/iap.bash').is_file())
        self.assertIn('安裝來源', self.run_cli(bindir / 'iap', 'update', ok=False).stderr)

    def test_install_preserves_existing_regular_file(self):
        bindir = self.home / "bin"
        bindir.mkdir()
        (bindir / "iap").write_text("original")
        self.run_cli("install.sh", "--bin-dir", bindir, ok=False)
        self.assertEqual((bindir / "iap").read_text(), "original")

    def test_help_and_invalid_arguments_have_no_config_side_effects(self):
        self.run_cli("iap", "setup", "--help")
        self.run_cli("iap", "setup", "--config", ok=False)
        self.run_cli("iap", "setup", "--unknown", ok=False)
        self.assertFalse(self.target.parent.exists())


if __name__ == "__main__":
    unittest.main()
