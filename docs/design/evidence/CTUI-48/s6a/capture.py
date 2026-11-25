"""Framework-only recording fixture, synthetic SGR routing, no clipboard.
Run from repository root. Every requested theme has explicit environment.
"""
import json,subprocess,time
from pathlib import Path
E=Path('docs/design/evidence/CTUI-48/s6a');B=['tmux','-L','ctui48-designer']
def tm(*a):return subprocess.check_output(B+list(a)).decode()
def send(t,s):tm('send-keys','-t',t,'-l',s)
def key(t,k):tm('send-keys','-t',t,k);time.sleep(.1)
def cap(t,k):
 for ext,flags in [('txt',[]),('ansi',['-e'])]:E.joinpath(k+'.'+ext).write_text(tm('capture-pane','-p',*flags,'-t',t))
def screen(t):return tm('capture-pane','-p','-t',t)
def mouse(t,x,y,kind):send(t,f'\x1b[<{32 if kind=="move" else 0};{x};{y}{"m" if kind=="up" else "M"}');time.sleep(.06)
def click(t,x,y):mouse(t,x,y,'down');mouse(t,x,y,'up')
results=[]
for w,h in [(120,40),(80,24)]:
 for theme in ['dark','light','plain']:
  t='s6a'+str(w)+theme;stem=f'{theme}-{w}x{h}'
  flags='' if theme=='dark' else ' --'+theme
  tm('new-session','-d','-s',t,'-x',str(w),'-y',str(h),'env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dart run test/fixtures/markdown_controls.dart'+flags)
  tm('set-option','-t',t,'remain-on-exit','on')
  for _ in range(150):
   if 'Copies 0:' in screen(t):break
   time.sleep(.1)
  assert screen(t).count('[copy]')==1
  cap(t,stem+'-initial')
  click(t,10,4);cap(t,stem+'-clicked')
  assert r'Copies 1: \tcopy body\n\ntail' in screen(t)
  key(t,'C-b');key(t,'C-b');cap(t,stem+'-quote-emphasized')
  key(t,'C-y');cap(t,stem+'-quote-recorded');assert 'Copies 2: quoted body' in screen(t)
  key(t,'F2');cap(t,stem+'-closed');assert screen(t).count('[copy]')==2
  key(t,'C-b');key(t,'C-b');key(t,'C-b');cap(t,stem+'-last-emphasized')
  key(t,'F3');click(t,10,4);cap(t,stem+'-covered-no-copy');assert 'Copies 2:' in screen(t)
  key(t,'F3')
  mouse(t,7,5,'down');mouse(t,10,5,'move');mouse(t,10,5,'up');key(t,'C-s');cap(t,stem+'-selected');assert 'Range: copy' in screen(t)
  mouse(t,10,4,'down');mouse(t,11,4,'move');mouse(t,11,4,'up');key(t,'C-s');cap(t,stem+'-moved-no-copy');assert 'Copies 2:' in screen(t) and 'Range: copy' not in screen(t)
  mouse(t,10,4,'down');key(t,'F2');mouse(t,10,4,'up');cap(t,stem+'-revision-no-copy');assert 'Copies 2:' in screen(t)
  # A fresh wheel report is never button activation.
  send(t,'\x1b[<65;10;4M');time.sleep(.1);cap(t,stem+'-wheel-no-copy');assert 'Copies 2:' in screen(t)
  for width in [15,14]:
   tm('resize-window','-t',t,'-x',str(width),'-y',str(h));time.sleep(.15);cap(t,stem+f'-narrow{width}')
  tm('resize-window','-t',t,'-x',str(w),'-y',str(h));time.sleep(.15)
  key(t,'C-q')
  for _ in range(30):
   dead=tm('display-message','-p','-t',t,'#{pane_dead},#{pane_dead_status}').strip()
   if dead.startswith('1,'):break
   time.sleep(.1)
  results.append({'case':stem,'exit':dead,'copied_payloads':[r'\tcopy body\n\ntail','quoted body']})
  tm('kill-session','-t',t)
E.joinpath('runtime-results.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
