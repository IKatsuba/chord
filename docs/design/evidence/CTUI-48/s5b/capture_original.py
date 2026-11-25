"""Original production UI with recording factory; run from task root.
No original file is edited. All agent traffic is scripted fake traffic.
"""
import json,subprocess,time
from pathlib import Path
E=Path('docs/design/evidence/CTUI-48/s5b');B=['tmux','-L','ctui48-designer']
def tm(*a):return subprocess.check_output(B+list(a)).decode()
def send(t,s):tm('send-keys','-t',t,'-l',s)
def cap(t,k):
 for ext,flags in [('txt',[]),('ansi',['-e'])]:E.joinpath(k+'.'+ext).write_text(tm('capture-pane','-p',*flags,'-t',t))
def until(t,needle):
 for _ in range(200):
  text=tm('capture-pane','-p','-t',t)
  if needle in text:return text
  time.sleep(.1)
 raise RuntimeError('original missing '+needle)
def drag(t):
 text=tm('capture-pane','-p','-t',t);lines=text.splitlines()
 row=next(i+1 for i,l in enumerate(lines) if 'Next eligible request' in l);x=lines[row-1].index('Next')+1
 for s in [f'\x1b[<0;{x};{row}M',f'\x1b[<32;{x+3};{row}M',f'\x1b[<0;{x+3};{row}m']:send(t,s)
 time.sleep(.16)
results=[]
for mode,theme in [('auto','dark'),('auto','light'),('auto','plain'),('manual','dark'),('failure','dark'),('timeout','dark')]:
 t='o-'+mode+'-'+theme
 command='env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor CHORD_FAKE_STEP_MS=1 CHORD_SOURCE="$(cd ../../chord && pwd)" bun --define \'process.env.NODE_ENV:"production"\' docs/design/evidence/CTUI-48/s5b/original-recording.ts '+mode+' '+theme
 tm('new-session','-d','-s',t,'-x','120','-y','40',command);tm('set-option','-t',t,'remain-on-exit','on')
 until(t,'? for shortcuts');time.sleep(.2)
 send(t,'long');tm('send-keys','-t',t,'Enter');until(t,'200. Line 200');time.sleep(.4)
 send(t,'Next eligible request');tm('send-keys','-t',t,'Enter');until(t,'Hello, world. This reply');time.sleep(.3)
 for w,h in [(120,40),(80,24)]:
  tm('resize-window','-t',t,'-x',str(w),'-y',str(h));time.sleep(.2)
  k=f'original-{mode}-{theme}-{w}x{h}';cap(t,k+'-before');drag(t);cap(t,k+'-released')
  if mode=='auto':
   time.sleep(3.1);cap(t,k+'-expired');tm('send-keys','-t',t,'C-c');time.sleep(.15);cap(t,k+'-explicit')
  elif mode=='manual':
   tm('send-keys','-t',t,'C-c');time.sleep(.15);cap(t,k+'-explicit')
  elif mode=='failure':
   time.sleep(3.1);cap(t,k+'-persistent');tm('send-keys','-t',t,'C-c');time.sleep(.15);cap(t,k+'-retry')
  else:
   time.sleep(1.3);cap(t,k+'-bounded');tm('send-keys','-t',t,'C-c');time.sleep(.1);cap(t,k+'-retry-pending')
  E.joinpath(k+'-record.jsonl').write_bytes(Path(f'build/ctui48-original-{mode}-{theme}/record.jsonl').read_bytes())
  # Ordinary text cancels a surviving selection/copy before clearing draft.
  send(t,'x');time.sleep(.1);tm('send-keys','-t',t,'C-c');time.sleep(.1)
 tm('send-keys','-t',t,'C-d')
 for _ in range(50):
  dead=tm('display-message','-p','-t',t,'#{pane_dead},#{pane_dead_status}').strip()
  if dead.startswith('1,'):break
  time.sleep(.1)
 results.append({'case':mode+'-'+theme,'exit':dead})
 tm('kill-session','-t',t)
E.joinpath('original-runtime-results.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
