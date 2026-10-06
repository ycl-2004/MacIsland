import subprocess,sys,time,os,signal,json,tempfile
from pathlib import Path
work = tempfile.TemporaryDirectory(prefix='atoll-guardian-test-')
helper = str(Path(work.name)/'guardian')
root = Path(__file__).resolve().parents[1]
subprocess.run(['xcrun','clang','-std=c11','-Os','-Wall','-Wextra','-Werror','-DATOLL_GUARDIAN_TEST', str(root/'Tools/OSDRecoveryGuardian.c'), '-o',helper],check=True)

def state(pid):
    return subprocess.check_output(['/bin/ps','-o','state=','-p',str(pid)],text=True).strip()
def wait_state(pid,stopped):
    end=time.monotonic()+3
    while time.monotonic()<end:
        if state(pid).startswith('T')==stopped: return True
        time.sleep(.02)
    return False
results=[]
for mode in ('normal','parent_sigkill','guardian_sigterm','already_stopped'):
    target=subprocess.Popen(['/bin/sleep','30'])
    proxy=None
    try:
        if mode == 'already_stopped': os.kill(target.pid,signal.SIGSTOP)
        code="import subprocess,sys,time; p=subprocess.Popen([sys.argv[1]],stdin=subprocess.PIPE); p.stdin.write(('S '+sys.argv[2]+'\\n').encode()); p.stdin.flush(); print(p.pid,flush=True); sys.stdin.read(); p.stdin.close(); p.wait(timeout=2)"
        proxy=subprocess.Popen([sys.executable,'-c',code,helper,str(target.pid)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        guardian_pid=int(proxy.stdout.readline())
        assert wait_state(target.pid,True),'guardian did not stop owned fixture'
        if mode == 'parent_sigkill': proxy.kill()
        else:
            if mode == 'guardian_sigterm': os.kill(guardian_pid,signal.SIGTERM)
            proxy.stdin.close()
        proxy.wait(timeout=3)
        assert wait_state(target.pid,mode == 'already_stopped'),'guardian did not preserve the expected ownership state'
        results.append({'mode':mode,'passed':True})
    finally:
        if proxy and proxy.poll() is None: proxy.kill(); proxy.wait()
        os.kill(target.pid,signal.SIGCONT); target.terminate(); target.wait(timeout=2)
print(json.dumps(results))

work.cleanup()
