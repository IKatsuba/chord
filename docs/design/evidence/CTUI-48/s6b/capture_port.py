"""Serial real port fixtures; recording journal never shared concurrently.
Run from task root. Synthetic SGR is protocol evidence, not physical input.
"""
import json,subprocess,time
from pathlib import Path
E=Path('docs/design/evidence/CTUI-48/s6b');B=['tmux','-L','ctui48-designer'];J=Path('build/ctui48_selection_record.jsonl');results=[]
def tm(*a):return subprocess.check_output(B+list(a)).decode()
def screen(t):return tm('capture-pane','-p','-t',t)
def send(t,s):tm('send-keys','-t',t,'-l',s);time.sleep(.12)
def key(t,k):tm('send-keys','-t',t,k);time.sleep(.12)
def cap(t,k):
 for ext,flags in [('txt',[]),('ansi',['-e'])]:E.joinpath(k+'.'+ext).write_text(tm('capture-pane','-p',*flags,'-t',t))
 E.joinpath(k+'-cursor.txt').write_text(tm('display-message','-p','-t',t,'#{cursor_x},#{cursor_y}'))
def start(t,w,h,cmd,ready):
 tm('new-session','-d','-s',t,'-x',str(w),'-y',str(h),'env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor '+cmd);tm('set-option','-t',t,'remain-on-exit','on')
 for _ in range(160):
  if ready in screen(t):return
  time.sleep(.1)
 raise RuntimeError('not ready '+t+'\n'+screen(t))
def end(t,k,quit='C-d'):
 key(t,quit)
 for _ in range(40):
  dead=tm('display-message','-p','-t',t,'#{pane_dead},#{pane_dead_status}').strip()
  if dead.startswith('1,'):break
  time.sleep(.1)
 assert dead=='1,0',(t,dead,screen(t))
 results.append({'case':k,'exit':dead});tm('kill-session','-t',t)
def pick(t):send(t,'\x18b');assert '↑ ↓ another block · c copy · esc done' in screen(t)
def mouse(t,x,y,kind):send(t,f'\x1b[<{32 if kind=="move" else 0};{x};{y}{"m" if kind=="up" else "M"}')
for w,h in [(120,40),(80,24)]:
 for theme in ['dark','light','plain']:
  t=f'p{w}{theme}';k=f'port-{theme}-{w}x{h}';flag='' if theme=='dark' else ' --'+theme
  start(t,w,h,'dart run example/chord/tool/selection.dart --pick --manual'+flag,'Next eligible request');cap(t,k+'-initial')
  send(t,'\x18');cap(t,k+'-pending');send(t,'b');cap(t,k+'-picked-quote');key(t,'Escape')
  pick(t);cap(t,k+'-samebatch-picked');key(t,'Up');cap(t,k+'-picked-ordinary');send(t,'c');cap(t,k+'-ordinary-copied')
  pick(t);send(t,'c');cap(t,k+'-quote-copied')
  lines=screen(t).splitlines();row=next(i+1 for i,l in enumerate(lines) if '[copy]' in l);x=lines[row-1].index('[copy]')+1
  mouse(t,x,row,'down');mouse(t,x,row,'up');cap(t,k+'-button-copied')
  lines=screen(t).splitlines();row=next(i+1 for i,l in enumerate(lines) if 'Select these reply words.' in l);x=lines[row-1].index('Select')+1
  mouse(t,x,row,'down');mouse(t,x+5,row,'move');mouse(t,x+5,row,'up');cap(t,k+'-selection');pick(t);cap(t,k+'-selection-then-pick');key(t,'Escape')
  send(t,'x');cap(t,k+'-typed');key(t,'C-c')
  send(t,'/sta');cap(t,k+'-sta');key(t,'Tab');cap(t,k+'-status-completed');assert '/status' in screen(t);key(t,'C-c')
  data=[json.loads(l) for l in J.read_text().splitlines()]
  assert [e['text'] for e in data if e['event']=='write']==['\tcopy body\n\ntail','quoted body','\tcopy body\n\ntail'],data
  E.joinpath(k+'-record.jsonl').write_bytes(J.read_bytes());end(t,k)
 for mode in ['many','failure','timeout']:
  t=f'p{w}{mode}';k=f'port-{mode}-{w}x{h}';flags=' --many' if mode=='many' else ' --'+mode
  start(t,w,h,'dart run example/chord/tool/selection.dart --pick --manual'+flags,'Next eligible request');cap(t,k+'-initial')
  if mode=='many':assert 'quoted body' not in screen(t)
  pick(t);cap(t,k+'-picked');send(t,'c');cap(t,k+'-copy')
  if mode=='many':
   pick(t);key(t,'Up');cap(t,k+'-ordinary-revealed');send(t,'c');cap(t,k+'-ordinary-copy')
  elif mode=='failure':time.sleep(3.1);cap(t,k+'-expired')
  else:
   time.sleep(1.3);cap(t,k+'-bounded');pick(t);send(t,'c');cap(t,k+'-retry-pending')
  E.joinpath(k+'-record.jsonl').write_bytes(J.read_bytes());end(t,k)
 # Existing tall-help fixture: normal, then closing, at actual catalog size.
 for closing in [False,True]:
  t=f'h{w}{closing}';k=f'help-{w}x{h}'+('-closing' if closing else '')
  cmd='dart run example/chord/tool/wheel.dart --help --tall-draft'+(' --closing' if closing else '')
  start(t,w,h,cmd,'draft line 7');time.sleep(.4);cap(t,k+'-initial')
  # Panel wheel over the first visible help action, never draft input.
  lines=screen(t).splitlines();matches=[i+1 for i,l in enumerate(lines) if 'ctrl' in l and i<h-10]
  row=matches[0] if matches else 2
  send(t,f'\x1b[<65;10;{row}M');cap(t,k+'-wheel')
  end(t,k,'C-q')
 # Same mounted public window across all seeded start phases.
 t=f'phase{w}';k=f'phase-{w}x{h}'
 start(t,w,h,'dart --packages=example/chord/.dart_tool/package_config.json docs/design/evidence/CTUI-48/s6b/status_phases.dart.txt','Starting')
 for i,phase in enumerate(['starting','failed','idle','connected','gone','closing']):
  if i:key(t,'F2')
  cap(t,k+'-'+phase)
 end(t,k,'F12')
E.joinpath('port-runtime-results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results,indent=2))
