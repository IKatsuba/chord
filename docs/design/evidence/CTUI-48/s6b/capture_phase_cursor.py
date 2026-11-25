"""Auxiliary virtual cursor flags; readiness and exit are bounded polls."""
import json,subprocess,time
from pathlib import Path
P=Path('docs/design/evidence/CTUI-48/s6b');B=['tmux','-L','ctui48-designer'];records=[]
def tm(*a):return subprocess.check_output(B+list(a)).decode()
for w,h in [(120,40),(80,24)]:
 t='phaseflags'+str(w)
 tm('new-session','-d','-s',t,'-x',str(w),'-y',str(h),'env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dart --packages=example/chord/.dart_tool/package_config.json docs/design/evidence/CTUI-48/s6b/status_phases.dart.txt');tm('set-option','-t',t,'remain-on-exit','on')
 for _ in range(150):
  if 'Starting fixture' in tm('capture-pane','-p','-t',t):break
  time.sleep(.1)
 for i,phase in enumerate(['starting','failed','idle','connected','gone','closing']):
  if i:tm('send-keys','-t',t,'F2');time.sleep(.2)
  records.append({'size':f'{w}x{h}','phase':phase,'x_y_visible':tm('display-message','-p','-t',t,'#{cursor_x},#{cursor_y},#{cursor_flag}').strip()})
 tm('send-keys','-t',t,'F12')
 for _ in range(40):
  dead=tm('display-message','-p','-t',t,'#{pane_dead},#{pane_dead_status}').strip()
  if dead.startswith('1,'):break
  time.sleep(.1)
 assert dead=='1,0'
 tm('kill-session','-t',t)
P.joinpath('phase-cursor-visibility.json').write_text(json.dumps(records,indent=2)+'\n');print(json.dumps(records,indent=2))
