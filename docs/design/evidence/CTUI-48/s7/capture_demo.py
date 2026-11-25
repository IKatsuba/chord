"""Public demo only; source inspection callbacks, never clipboard."""
from pathlib import Path
import json,subprocess,time
P=Path('docs/design/evidence/CTUI-48/s7');B=['tmux','-L','ctui48-designer'];out=[]
def tm(*a):return subprocess.check_output(B+list(a)).decode()
def key(t,k):tm('send-keys','-t',t,k);time.sleep(.12)
def cap(t,n):
 for ext,flag in [('txt',[]),('ansi',['-e'])]:P.joinpath(n+'.'+ext).write_text(tm('capture-pane','-p',*flag,'-t',t))
def mouse(t,s):tm('send-keys','-t',t,'-l',s);time.sleep(.12)
for w,h in [(120,40),(80,24)]:
 t='demo'+str(w);tm('new-session','-d','-s',t,'-x',str(w),'-y',str(h),'env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dart run example/selection.dart');tm('set-option','-t',t,'remain-on-exit','on')
 for _ in range(160):
  if 'Selection area' in tm('capture-pane','-p','-t',t):break
  time.sleep(.1)
 for theme in ['dark','light','plain']:
  n=f'demo-{theme}-{w}x{h}';cap(t,n+'-initial')
  mouse(t,'\x1b[<0;1;1M');mouse(t,'\x1b[<32;9;1M');cap(t,n+'-held');key(t,'F2');cap(t,n+'-append-held');mouse(t,'\x1b[<0;9;1m');key(t,'C-s');cap(t,n+'-snapshot')
  assert 'finalized: Selection' in tm('capture-pane','-p','-t',t)
  key(t,'C-o');cap(t,n+'-overlay');key(t,'C-u');key(t,'C-s');cap(t,n+'-unknown');assert 'Snapshot unresolved' in tm('capture-pane','-p','-t',t)
  key(t,'C-u');key(t,'C-o');key(t,'C-l');key(t,'C-b');cap(t,n+'-code');key(t,'C-r');cap(t,n+'-reveal');key(t,'C-t')
 key(t,'C-q')
 for _ in range(40):
  dead=tm('display-message','-p','-t',t,'#{pane_dead},#{pane_dead_status}').strip()
  if dead.startswith('1,'):break
  time.sleep(.1)
 assert dead=='1,0';out.append({'size':f'{w}x{h}','exit':dead});tm('kill-session','-t',t)
P.joinpath('demo-results.json').write_text(json.dumps(out,indent=2)+'\n');print(out)
