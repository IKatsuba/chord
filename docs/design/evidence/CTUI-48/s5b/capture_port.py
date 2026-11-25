"""Owned tmux recording-only screen checks, run from repository root.
Synthetic SGR bytes prove protocol routing, never physical pointer delivery.
"""
import json, subprocess, time
from pathlib import Path
E = Path('docs/design/evidence/CTUI-48/s5b')
J = Path('build/ctui48_selection_record.jsonl')
BASE = ['tmux', '-L', 'ctui48-designer']
def tm(*a): return subprocess.check_output(BASE + list(a)).decode()
def send(t,s): tm('send-keys','-t',t,'-l',s)
def cap(t,k):
    for ext,flags in [('txt',[]),('ansi',['-e'])]:
        E.joinpath(k+'.'+ext).write_text(tm('capture-pane','-p',*flags,'-t',t))
def wait(t):
    for _ in range(150):
        text=tm('capture-pane','-p','-t',t)
        if 'Next eligible request' in text: return text
        time.sleep(.1)
    raise RuntimeError('fixture did not become ready')
results=[]
for w,h in [(120,40),(80,24)]:
    for mode,theme in [('auto','dark'),('auto','light'),('auto','plain'),('manual','dark'),('failure','dark'),('timeout','dark')]:
        t=f'p{w}-{mode}-{theme}'
        flags=('' if mode=='auto' else ' --'+mode)+('' if theme=='dark' else ' --'+theme)
        tm('new-session','-d','-s',t,'-x',str(w),'-y',str(h),'env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dart run example/chord/tool/selection.dart'+flags)
        tm('set-option','-t',t,'remain-on-exit','on')
        text=wait(t); key=f'port-{mode}-{theme}-{w}x{h}'
        cap(t,key+'-before')
        row=next(i+1 for i,l in enumerate(text.splitlines()) if 'Next eligible request' in l)
        x=text.splitlines()[row-1].index('Next')+1
        for event in [f'\x1b[<0;{x};{row}M',f'\x1b[<32;{x+3};{row}M',f'\x1b[<0;{x+3};{row}m']:
            send(t,event)
        time.sleep(.13);cap(t,key+'-released')
        if mode=='manual':
            assert not J.read_text(), 'manual copied on release'
            tm('send-keys','-t',t,'C-c');time.sleep(.13);cap(t,key+'-explicit')
        elif mode=='auto':
            time.sleep(3.1);cap(t,key+'-expired')
            send(t,'x');time.sleep(.12);cap(t,key+'-typed-clear')
            tm('send-keys','-t',t,'C-c');time.sleep(.1)
        elif mode=='failure':
            time.sleep(3.1);cap(t,key+'-persistent')
            tm('send-keys','-t',t,'C-c');time.sleep(.12);cap(t,key+'-retry')
        else:
            time.sleep(1.3);cap(t,key+'-bounded')
            tm('send-keys','-t',t,'C-c');time.sleep(.1);cap(t,key+'-retry-pending')
        E.joinpath(key+'-record.jsonl').write_bytes(J.read_bytes())
        tm('send-keys','-t',t,'C-d')
        for _ in range(50):
            dead=tm('display-message','-p','-t',t,'#{pane_dead},#{pane_dead_status}').strip()
            if dead.startswith('1,'):break
            time.sleep(.1)
        results.append({'case':key,'exit':dead,'events':J.read_text().splitlines()})
        tm('kill-session','-t',t)
E.joinpath('port-runtime-results.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
