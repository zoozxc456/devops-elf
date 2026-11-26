import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')
LISTENING = '#!/bin/sh\necho "Listening on port [$5]." >&2\nexec sleep 30\n'
FAILING = '#!/bin/sh\necho "ERROR: not authorized" >&2\nexit 1\n'


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


@unittest.skipIf(os.name == 'nt', 'Unix executable stub')
class BackgroundTunnelBase:
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='iap bg ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / 'fake-bin'
        self.bin.mkdir()
        self.gcloud = self.bin / 'gcloud'
        self.gcloud.write_text(LISTENING)
        self.gcloud.chmod(0o755)
        self.web, self.db = free_port(), free_port()
        conf = self.home / 'hosts'
        conf.write_text(f'web tunnel p z vm 8080 {self.web}\n  > Web http://localhost:{{port}}\n'
                        f'db tunnel - - vm 5432 {self.db}\nbox ssh - - vm\n')
        self.state = self.home / 'state/iap'
        self.env = dict(os.environ, HOME=str(self.home), IAP_CONF=str(conf),
                        XDG_STATE_HOME=str(self.home / 'state'), IAP_UP_TIMEOUT='10',
                        PATH=str(self.bin) + os.pathsep + os.environ['PATH'])
        self.addCleanup(self.run_cli, 'down', '--all', ok=None)

    def run_cli(self, *args, ok=True):
        result = subprocess.run([*self.command, *map(str, args)], env=self.env, cwd=self.home,
                                capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        if ok is True:
            self.assertEqual(result.returncode, 0, output)
        elif ok is False:
            self.assertNotEqual(result.returncode, 0, output)
        return output

    def pid(self, name):
        return int((self.state / f'{name}.pid').read_text().split()[0])

    def alive(self, pid):
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False

    def test_up_ps_logs_down(self):
        out = self.run_cli('up', 'web', 'db')
        self.assertIn(f'http://localhost:{self.web}', out)
        web, db = self.pid('web'), self.pid('db')
        self.assertTrue(self.alive(web) and self.alive(db))
        self.assertIn(str(web), self.run_cli('up', 'web'))  # already running, no second process
        self.assertEqual(self.pid('web'), web)
        listing = self.run_cli('ps')
        self.assertIn(f'localhost:{self.db}', listing)
        self.assertIn('vm:8080', listing)
        self.assertIn('Listening on port', self.run_cli('logs', 'web'))
        self.run_cli('down', 'web')
        self.assertFalse((self.state / 'web.pid').exists())
        self.assertNotIn('web', self.run_cli('ps'))
        self.run_cli('down', 'web', ok=False)
        self.run_cli('down', '--all')
        self.assertNotIn('db', self.run_cli('ps'))

    def test_rejects_ssh_busy_port_and_failed_start(self):
        self.run_cli('up', 'box', ok=False)
        self.run_cli('up', 'missing', ok=False)
        with socket.socket() as s:
            s.bind(('127.0.0.1', self.web))
            s.listen()
            self.assertIn('已被佔用', self.run_cli('up', 'web', ok=False))
        self.gcloud.write_text(FAILING)
        self.assertIn('not authorized', self.run_cli('up', 'db', ok=False))
        self.assertFalse((self.state / 'db.pid').exists())

    def test_path_like_names_are_rejected(self):
        outside = self.home / 'state/victim.pid'
        outside.parent.mkdir(parents=True)
        outside.write_text('1 1 1 x')
        self.run_cli('down', '../victim', ok=False)
        self.run_cli('logs', '../victim', ok=False)
        self.assertTrue(outside.exists())


class BashBackgroundTests(BackgroundTunnelBase, unittest.TestCase):
    command = ['/bin/bash', str(ROOT / 'iap')]


@unittest.skipUnless(PWSH, 'PowerShell 7.2+ required')
class PowerShellBackgroundTests(BackgroundTunnelBase, unittest.TestCase):
    command = [PWSH or 'pwsh', '-NoLogo', '-NoProfile', '-File', str(ROOT / 'iap.ps1')]


if __name__ == '__main__':
    unittest.main()
