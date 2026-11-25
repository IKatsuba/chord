"""Exact a6c5733 repair look; retain d061366 captures unchanged."""
import json,subprocess,time,shlex,itertools
from pathlib import Path
P=Path('docs/design/evidence/CTUI-48/s7');D=P/'repairs';D.mkdir(exist_ok=True);B=['tmux','-L','ctui48-designer'];results=[]
SOURCE=Path('../../chord').resolve();COMMAND=shlex.join([subprocess.check_output(['which','bun']).decode().strip(),str(SOURCE/'tests/fixtures/fake_agent/main.ts'),'--step-ms','10'])
def tm(*a):return subprocess.check_output(B+list(a)).decode()
def text(t):return tm('capture-pane','-p','-t',t)
def send(t,s):tm('send-keys','-t',t,'-l',s);time.sleep(.08)
def key(t,k):tm('send-keys','-t',t,k);time.sleep(.1)
def until(t,needle):
 for _ in range(160):
  if needle in text(t):return
  time.sleep(.1)
 raise RuntimeError('missing '+needle+'\n'+text(t))
def cap(ts,k,state):
 for role,t in ts.items():
  for ext,flags in [('txt',[]),('ansi',['-e'])]:D.joinpath(f'{role}-{k}-{state}.{ext}').write_text(tm('capture-pane','-p',*flags,'-t',t))
  D.joinpath(f'{role}-{k}-{state}-cursor.txt').write_text(tm('display-message','-p','-t',t,'#{cursor_x},#{cursor_y},#{cursor_flag}'))
def keyall(ts,k):
 for t in ts.values():key(t,k)
def sendall(ts,s):
 for t in ts.values():send(t,s)
for w,h in [(120,40),(80,24)]:
 for theme in ['dark','light','plain']:
  k=f'{theme}-{w}x{h}';ts={'original':'ro'+str(w)+theme,'port':'rp'+str(w)+theme}
  for role,t in ts.items():
   if role=='original':cmd='env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor CHORD_FAKE_STEP_MS=10 CHORD_SOURCE='+shlex.quote(str(SOURCE))+' bun --define \'process.env.NODE_ENV:"production"\' docs/design/evidence/CTUI-48/s7/original_recording.ts auto '+theme
   else:cmd='env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dart --packages=example/chord/.dart_tool/package_config.json docs/design/evidence/CTUI-48/s7/port_recording.dart.txt '+shlex.join([COMMAND,'auto',theme])
   tm('new-session','-d','-s',t,'-x',str(w),'-y',str(h),cmd);tm('set-option','-t',t,'remain-on-exit','on');until(t,'Fake Large')
  cap(ts,k,'empty');sendall(ts,'\x18b');cap(ts,k,'empty-catalog')
  for t in ts.values():assert 'No code block to pick' in text(t)
  time.sleep(3.1);cap(ts,k,'empty-notice-expired')
  for t in ts.values():
   lines=text(t).splitlines();row=next(i+1 for i,l in enumerate(lines) if 'chord' in l);x=lines[row-1].index('chord')+1
   for s in [f'\x1b[<0;{x};{row}M',f'\x1b[<32;{x+4};{row}M',f'\x1b[<0;{x+4};{row}m']:send(t,s)
  keyall(ts,'C-c');cap(ts,k,'stale-five-char-note');sendall(ts,'markdowncode');keyall(ts,'Enter')
  for t in ts.values():until(t,'bun dev check')
  sendall(ts,'\x18b');cap(ts,k,'picked-before-resize')
  for t in ts.values():tm('resize-window','-t',t,'-x','20','-y','24')
  time.sleep(.2);cap(ts,k,'narrow-picked')
  for t in ts.values():assert '↑ ↓ block' in text(t),(t,text(t))
  sendall(ts,'c');cap(ts,k,'narrow-copied')
  for t in ts.values():tm('resize-window','-t',t,'-x',str(w),'-y',str(h))
  time.sleep(.2);cap(ts,k,'restored-after-copy');sendall(ts,'\x18b\x1b[A\x1b[A')
  for t in ts.values():tm('resize-window','-t',t,'-x','20','-y','24')
  time.sleep(.2);keyall(ts,'Up');cap(ts,k,'narrow-first-control')
  target=next(l for l in text(ts['port']).splitlines() if 'typescript' in l and '┌' in l);assert '[copy]' not in target
  sendall(ts,'c');cap(ts,k,'narrow-first-copy')
  for t in ts.values():tm('resize-window','-t',t,'-x',str(w),'-y',str(h))
  time.sleep(.15)
  a=Path(f'build/ctui48-s7-original-auto-{theme}/record.jsonl');b=Path('build/ctui48-s7-port-record.jsonl')
  aa=[r for r in map(json.loads,a.read_text().splitlines()) if r['event'] in ['attempt','write']];bb=list(map(json.loads,b.read_text().splitlines()));assert aa==bb
  assert [r['text'] for r in aa if r['event']=='write']==['chord','chord','bun dev check','x']
  D.joinpath('original-'+k+'-record.jsonl').write_bytes(a.read_bytes());D.joinpath('port-'+k+'-record.jsonl').write_bytes(b.read_bytes())
  assert [r['text'] for r in aa if r['event']=='write']==['chord','chord','bun dev check','x'],aa
  D.joinpath(f'original-{k}-record.jsonl').write_bytes(a.read_bytes());D.joinpath(f'port-{k}-record.jsonl').write_bytes(b.read_bytes())
  for role,t in ts.items():
   key(t,'C-d')
   for _ in range(50):
    dead=tm('display-message','-p','-t',t,'#{pane_dead},#{pane_dead_status}').strip()
    if dead.startswith('1,'):break
    time.sleep(.1)
   assert dead=='1,0';results.append({'role':role,'case':k,'exit':dead});tm('kill-session','-t',t)
D.joinpath('runtime-results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results,indent=2))
