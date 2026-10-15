"""Only launches and signals this test's own supervisor, proxy and sleep fixture."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def wait_for(path):
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if path.exists() and path.read_text().strip():
            return int(path.read_text())
        time.sleep(0.01)
    raise AssertionError('fixture did not start')


def running(pid):
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'state='], capture_output=True, text=True, timeout=2)
    return result.returncode == 0 and not result.stdout.strip().startswith('Z')


with tempfile.TemporaryDirectory(prefix='atoll-supervisor-') as temporary:
    directory = Path(temporary)
    supervisor = directory / 'supervisor'
    subprocess.run(['xcrun', 'clang', '-std=c11', '-Os', '-Wall', '-Wextra', '-Werror',
                    str(ROOT / 'Tools/AtollProcessSupervisor.c'), '-o', str(supervisor)], check=True, timeout=30)
    results = []
    for mode in ['parent_sigkill', 'supervisor_sigterm', 'child_exit']:
        pidfile = directory / (mode + '.pid')
        proxy_code = 'import subprocess,sys; p=subprocess.Popen(sys.argv[1:]); print(p.pid,flush=True); sys.stdin.read(); p.wait(timeout=3)'
        child_code = 'import os,sys,time; open(sys.argv[1],"w").write(str(os.getpid())); time.sleep(float(sys.argv[2]))'
        proxy = subprocess.Popen([sys.executable, '-c', proxy_code, str(supervisor), sys.executable, '-c',
                                  child_code, str(pidfile), '0.2' if mode == 'child_exit' else '30'],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        child = None
        try:
            helper = int(proxy.stdout.readline())
            child = wait_for(pidfile)
            if mode == 'parent_sigkill':
                proxy.kill()
            elif mode == 'supervisor_sigterm':
                os.kill(helper, signal.SIGTERM)
            if proxy.stdin:
                proxy.stdin.close()
            proxy.wait(timeout=4)
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline and (running(child) or running(helper)):
                time.sleep(0.02)
            assert not running(child), f'{mode}: child leaked'
            assert not running(helper), f'{mode}: helper leaked'
            results.append({'mode': mode, 'passed': True})
        finally:
            if proxy.poll() is None:
                proxy.kill()
                proxy.wait(timeout=2)
            if child and running(child):
                os.kill(child, signal.SIGKILL)
    print(json.dumps(results))
