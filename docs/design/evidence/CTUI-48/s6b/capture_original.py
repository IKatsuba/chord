"""Original production UI/fake agent with recording copier factory only.
Run from task root. Original repository files remain unchanged.
"""
import json,subprocess,time
from pathlib import Path
E=Path('docs/design/evidence/CTUI-48/s6b');B=['tmux','-L','ctui48-designer'];results=[]
def tm(*a):return subprocess.check_output(B+list(a)).decode()
def screen(t):return tm('capture-pane','-p','-t',t)
def send(t,s):tm('send-keys','-t',t,'-l',s);time.sleep(.12)
def key(t,k):tm('send-keys','-t',t,k);time.sleep(.12)
def cap(t,k):
 for ext,flags in [('txt',[]),('ansi',['-e'])]:E.joinpath(k+'.'+ext).write_text(tm('capture-pane','-p',*flags,'-t',t))
 E.joinpath(k+'-cursor.txt').write_text(tm('display-message','-p','-t',t,'#{cursor_x},#{cursor_y}'))
def until(t,needle):
 for _ in range(180):
  if needle in screen(t):return
  time.sleep(.1)
 raise RuntimeError('missing '+needle+'\n'+screen(t))
for theme in ['dark','light','plain']:
 t='s6bo'+theme;cmd='env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor CHORD_FAKE_STEP_MS=1 CHORD_SOURCE="$(cd ../../chord && pwd)" bun --define \'process.env.NODE_ENV:"production"\' docs/design/evidence/CTUI-48/s6b/original-recording.ts manual '+theme
 tm('new-session','-d','-s',t,'-x','120','-y','40',cmd);tm('set-option','-t',t,'remain-on-exit','on');until(t,'? for shortcuts');time.sleep(.3)
 send(t,'markdown');key(t,'Enter');until(t,'built');time.sleep(.5)
 for w,h in [(120,40),(80,24)]:
  tm('resize-window','-t',t,'-x',str(w),'-y',str(h));time.sleep(.25);k=f'original-{theme}-{w}x{h}';cap(t,k+'-initial')
  send(t,'\x18');cap(t,k+'-pending');send(t,'b');cap(t,k+'-picked');key(t,'Escape')
  send(t,'\x18b');cap(t,k+'-samebatch-picked');assert 'another block' in screen(t)
  key(t,'Up');cap(t,k+'-previous-picked');send(t,'c');cap(t,k+'-copied')
  send(t,'/sta');cap(t,k+'-sta');key(t,'Tab');cap(t,k+'-status-completed');assert '/status' in screen(t);key(t,'C-c')
  # Chord/prompt guards do not need a real clipboard or run action.
  E.joinpath(k+'-record.jsonl').write_bytes(Path(f'build/ctui48-s6b-original-manual-{theme}/record.jsonl').read_bytes())
 key(t,'C-d')
 for _ in range(40):
  dead=tm('display-message','-p','-t',t,'#{pane_dead},#{pane_dead_status}').strip()
  if dead.startswith('1,'):break
  time.sleep(.1)
 assert dead=='1,0',(t,dead)
 results.append({'case':theme,'exit':dead});tm('kill-session','-t',t)
E.joinpath('original-runtime-results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results,indent=2))
