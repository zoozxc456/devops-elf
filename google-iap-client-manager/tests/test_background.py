import faulthandler
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')
# Binds the --local-host-port like the real gcloud; readiness is detected by the port.
LISTENING = r'''#!/bin/sh
echo "args: $*"
for a; do case $a in --local-host-port=*) port=${a##*:} ;; esac; done
exec python3 -c 'import socket, sys, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(); time.sleep(30)' "$port"
'''
FAILING = '#!/bin/sh\necho "ERROR: not authorized" >&2\nexit 1\n'


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


@unittest.skipIf(os.name == 'nt', 'Unix executable stub')
class BackgroundTunnelBase:
    def setUp(self):
        # A hung test dumps every thread's stack and exits instead of stalling CI until the job timeout
        faulthandler.dump_traceback_later(120, exit=True)
        self.addCleanup(faulthandler.cancel_dump_traceback_later)
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
        logs = self.run_cli('logs', 'web')
        self.assertIn(f'--local-host-port=localhost:{self.web}', logs)
        # gcloud's startup check hangs when output is not a terminal
        self.assertIn('--iap-tunnel-disable-connection-check', logs)
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

    def test_ctrl_c_while_waiting_cancels_without_leftovers(self):
        self.gcloud.write_text('#!/bin/sh\nexec sleep 30\n')  # never listens
        proc = subprocess.Popen([*self.command, 'up', 'web'], env=self.env, cwd=self.home,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                start_new_session=True)
        deadline = time.time() + 10
        while not (self.state / 'web.pid').exists() and time.time() < deadline:
            time.sleep(0.1)
        pid = self.pid('web')
        time.sleep(0.5)
        os.killpg(proc.pid, signal.SIGINT)  # what the terminal sends on Ctrl-C
        out = proc.communicate(timeout=10)[0].decode()
        self.assertNotEqual(proc.returncode, 0, out)
        self.assertFalse((self.state / 'web.pid').exists())
        for _ in range(50):
            if not self.alive(pid):
                break
            time.sleep(0.1)
        self.assertFalse(self.alive(pid))

    def test_foreground_tunnel_reports_ready_from_port(self):
        self.gcloud.write_text(LISTENING.replace('time.sleep(30)', 'time.sleep(1)'))
        out = self.run_cli('web')
        self.assertIn('--iap-tunnel-disable-connection-check', out)
        self.assertIn('已連線', out)
        with socket.socket() as s:
            s.bind(('127.0.0.1', self.web))
            s.listen()
            self.assertIn('已被佔用', self.run_cli('web', ok=False))

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
