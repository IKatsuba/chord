"""Matched actual original and Dart port sessions against the same original fake.
Only copier factories/bootstrap recording adapters and approved App.home input
are capture setup. No original files, product flags or HOME are changed.
"""
import json,subprocess,time,shlex,itertools
from pathlib import Path
P=Path('docs/design/evidence/CTUI-48/s7');B=['tmux','-L','ctui48-designer'];results=[]
SOURCE=Path('../../chord').resolve();BUN=subprocess.check_output(['which','bun']).decode().strip();COMMAND=shlex.join([BUN,str(SOURCE/'tests/fixtures/fake_agent/main.ts'),'--step-ms','10'])
def tm(*a):return subprocess.check_output(B+list(a)).decode()
def text(t):return tm('capture-pane','-p','-t',t)
def send(t,s):tm('send-keys','-t',t,'-l',s);time.sleep(.07)
def key(t,k):tm('send-keys','-t',t,k);time.sleep(.09)
def until(t,needle,seconds=15):
 for _ in range(int(seconds*10)):
  if needle in text(t):return
  time.sleep(.1)
 raise RuntimeError('missing '+needle+' in '+t+'\n'+text(t))
def cap(t,n):
 for ext,flags in [('txt',[]),('ansi',['-e'])]:P.joinpath(n+'.'+ext).write_text(tm('capture-pane','-p',*flags,'-t',t))
 P.joinpath(n+'-cursor.txt').write_text(tm('display-message','-p','-t',t,'#{cursor_x},#{cursor_y},#{cursor_flag}'))
def scene(ts,k,state):
 for role,t in ts.items():cap(t,f'{role}-{k}-{state}')
def action(ts,s,enter=False):
 for t in ts.values():send(t,s)
 if enter:
  for t in ts.values():key(t,'Enter')
def keys(ts,k):
 for t in ts.values():key(t,k)
def select(t,needle,reverse=False,where=None,release=True):
 lines=text(t).splitlines();row=next(i+1 for i,l in enumerate(lines) if needle in l and (where is None or where(l)))
 x=lines[row-1].index(needle)+1;end=x+len(needle)-1
 if reverse:x,end=end,x
 send(t,f'\x1b[<0;{x};{row}M');send(t,f'\x1b[<32;{end};{row}M')
 if release:send(t,f'\x1b[<0;{end};{row}m')
 return end,row

def locate(t,needle,where=None):
 key(t,'End')
 for _ in range(10):
  if any(needle in l and (where is None or where(l)) for l in text(t).splitlines()):return
  key(t,'PageUp')
 raise RuntimeError('target not exposed '+needle+'\n'+text(t))
def done(ts,k):
 for role,t in ts.items():
  key(t,'C-d')
  for _ in range(50):
   dead=tm('display-message','-p','-t',t,'#{pane_dead},#{pane_dead_status}').strip()
   if dead.startswith('1,'):break
   time.sleep(.1)
  assert dead=='1,0',(t,dead,text(t))
  results.append({'case':k,'role':role,'exit':dead});tm('kill-session','-t',t)

for w,h in [(120,40),(80,24)]:
 for theme in ['dark','light','plain']:
  for mode in ['auto','manual','failure','timeout']:
   k=f'{mode}-{theme}-{w}x{h}';ts={r:r[0]+str(w)+theme+mode for r in ['original','port']}
   for role,t in ts.items():
    if role=='original':cmd='env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor CHORD_FAKE_STEP_MS=10 CHORD_SOURCE='+shlex.quote(str(SOURCE))+' bun --define \'process.env.NODE_ENV:"production"\' docs/design/evidence/CTUI-48/s7/original_recording.ts '+mode+' '+theme
    else:cmd='env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dart --packages=example/chord/.dart_tool/package_config.json docs/design/evidence/CTUI-48/s7/port_recording.dart.txt '+shlex.join([COMMAND,mode,theme])
    tm('new-session','-d','-s',t,'-x',str(w),'-y',str(h),cmd);tm('set-option','-t',t,'remain-on-exit','on');until(t,'Fake Large')
   scene(ts,k,'empty-header')
   for t in ts.values():select(t,'chord')
   time.sleep(.15);scene(ts,k,'header-released')
   if mode=='manual':
    keys(ts,'C-c');scene(ts,k,'explicit-cleared')
   elif mode=='failure':
    time.sleep(3.1);scene(ts,k,'failure-persistent');keys(ts,'C-c');scene(ts,k,'failure-retry')
   elif mode=='timeout':
    time.sleep(1.3);scene(ts,k,'timeout-bounded');keys(ts,'C-c');scene(ts,k,'timeout-retry-pending')
   else:
    time.sleep(3.1);scene(ts,k,'auto-expired');keys(ts,'C-c');scene(ts,k,'explicit-cleared')
    action(ts,'drafttarget');scene(ts,k,'draft')
    for t in ts.values():select(t,'draft',where=lambda l:l.startswith('│'))
    scene(ts,k,'draft-forward');keys(ts,'C-c')
    for t in ts.values():select(t,'draft',reverse=True,where=lambda l:l.startswith('│'))
    scene(ts,k,'draft-reverse');keys(ts,'C-c');keys(ts,'C-c')
    action(ts,'markdowncode',True)
    for t in ts.values():until(t,'bun dev check')
    time.sleep(.25);scene(ts,k,'markdowncode')
    for state,strokes in [('picked-newest','\x18b'),('nested-copy','c'),('wrapped-copy','\x18b\x1b[Ac'),('first-copy','\x18b\x1b[A\x1b[Ac')]:
     action(ts,strokes);scene(ts,k,state)
    for t in ts.values():key(t,'Home');until(t,'A paragraph before the code.')
    for t in ts.values():select(t,'A paragraph before the code.')
    scene(ts,k,'prose-forward');keys(ts,'C-c')
    for t in ts.values():select(t,'A paragraph before the code.',reverse=True)
    scene(ts,k,'prose-reverse');keys(ts,'C-c');keys(ts,'End')
    action(ts,'markdown',True)
    for t in ts.values():until(t,'const session = await openSession',seconds=15)
    scene(ts,k,'stream-open')
    held={t:select(t,'const',release=False,where=lambda l:'openSession' in l) for t in ts.values()}
    scene(ts,k,'stream-held-open');time.sleep(3.5);scene(ts,k,'stream-held-mutated')
    for t,(x,y) in held.items():send(t,f'\x1b[<0;{x};{y}m')
    scene(ts,k,'stream-release');keys(ts,'C-c');keys(ts,'End')
    for t in ts.values():until(t,'built',seconds=15)
    time.sleep(.2);scene(ts,k,'stream-closed');action(ts,'\x18bc');scene(ts,k,'last-code-copy')
    for t in ts.values():locate(t,'closed agent')
    for t in ts.values():select(t,'closed agent')
    scene(ts,k,'quote-selection');keys(ts,'C-c')
    for t in ts.values():locate(t,'session.ts',where=lambda l:l.count('│')>=3)
    for t in ts.values():select(t,'session.ts',where=lambda l:l.count('│')>=3)
    scene(ts,k,'table-selection');keys(ts,'C-c');keys(ts,'End')
    action(ts,'permission',True)
    for t in ts.values():until(t,'1. Allow')
    scene(ts,k,'permission')
    for t in ts.values():select(t,'notes',where=lambda l:'notes.txt' not in l and '│' in l)
    scene(ts,k,'permission-diff-selection');keys(ts,'C-c');scene(ts,k,'permission-explicit-copy');keys(ts,'Escape');time.sleep(.3)
    keys(ts,'End');action(ts,'\x18b');scene(ts,k,'pick-before-narrow')
    for t in ts.values():tm('resize-window','-t',t,'-x','20','-y','24')
    time.sleep(.2);scene(ts,k,'narrow20')
    for t in ts.values():tm('resize-window','-t',t,'-x',str(w),'-y',str(h))
    time.sleep(.2);keys(ts,'Escape')
   # Header-mode cases leave the draft empty; timeout quits while retry pending.
   pj=Path('build/ctui48-s7-port-record.jsonl');oj=Path(f'build/ctui48-original-{mode}-{theme}/record.jsonl')
   # Original launcher below uses S7 prefix, never another unit's state.
   oj=Path(f'build/ctui48-s7-original-{mode}-{theme}/record.jsonl')
   P.joinpath('port-'+k+'-record.jsonl').write_bytes(pj.read_bytes());P.joinpath('original-'+k+'-record.jsonl').write_bytes(oj.read_bytes())
   done(ts,k)
P.joinpath('matched-results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results,indent=2))
