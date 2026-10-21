# CHD-492 — runtime draft

Runtime's answers to the brief's questions 1–5, protocol's two questions to
runtime, the module layout, the failure scenarios and the test plan. Read
against `drafts/protocol.md` (`--window w-<id>` create-or-reopen, an
optional `sessionId` per tab, no pid or live mark in the record) and
`drafts/interface.md` (the record derived by a pure `windowNow`, written
when its text changes; a held window refused before the screen).

## Summary of the picks

- **The record is kept current, not written at the end.** One writer per
  window, the *keeper*: it is handed the derived record after every change,
  drops one equal to the last written, has at most one write in flight and
  one waiting (latest wins), and no timer. Each write is today's
  `writeWindow` (whole file beside, renamed over).
- **The first write comes after the first tab is placed and before its
  agent is spawned**, so `tabs` keeps `min(1)` and the id exists on disk
  before anything can go wrong with the agent.
- **A quit or a signal writes nothing new.** It freezes the keeper (so the
  strip emptying under `closeAll` is never written) and waits for the write
  in flight. The record on disk is the window as it was at the last change,
  whatever the exit; SIGKILL leaves the last completed rename.
- **One holder per window id: a lock beside the record, taken before the
  screen and the agents, released after the last write.** Picked:
  `proper-lockfile` (tried below, runs under Bun and in a compiled binary).
  The better-fitting answer, `flock(2)` through `bun:ffi` in
  `src/platform/`, is our own code and goes to the owner as the alternative.
- **A second chord on a held id waits a bounded time, then refuses**
  (interface's 1d (i)). The wait covers a holder still in its leave.
- **Measured:** a closing tmux pane (SIGHUP) took chord and an idle fake
  agent down in 87 ms, session record flushed. The design does not depend
  on that: it needs no time after the signal at all.

## Protocol's two questions

**First write: after the first tab is placed.** Order at start, for
`--window w-<id>`:

1. Parse flags; resolve the id (protocol).
2. Take the lock (refuse or wait, question 2). Before `terminalSetup`, as
   the `--resume` refusals are.
3. Read the record if one exists (reopen) or start empty (create).
4. Clean this id's orphan `windows/w-<id>.json.*.tmp` (a SIGKILL between
   write and rename leaves one; `readWindows` already ignores them, so this
   is tidiness, under the lock so it cannot race a live writer).
5. The window mounts; `OpenSessions` places the first tab(s) synchronously
   from the plan (reopened tabs, or one fresh tab of `[agent]` in `-C`).
6. **First write**: the derived record, every tab with `agent` and `cwd`,
   `sessionId` where known. Before any `session/new` or `session/resume`
   answers.
7. Agents spawn and their sessions open; each change after is the keeper's.

Writing before step 5 would need `tabs: []`, a record that names nothing
and that protocol's own schema would only need for this. A SIGKILL between
2 and 6 (milliseconds, no agent spawned yet) leaves no record, or the
previous one on a reopen; the next `--window` creates or reopens as if the
start never happened. So `min(1)` stays. The strip can never be empty
afterwards either: closing the last tab is a quit, and a quit freezes the
keeper before the tab leaves (below).

**A record naming an agent chord no longer knows.** Options:

- (a) Refuse the whole start, as `main.tsx` does today. For a launcher the
  window then never reopens until a person edits settings or the record.
- (b) Open the rest; leave that tab out with a note in `missingNote`'s
  wording (`Not reopened: foo tab 1a2b3c4d, agent foo is not known`); the
  next write drops it from the record, as a tab whose session record is
  gone is dropped today.
- (c) As (b), but carry the unopened tab in the record unchanged, so a
  chord where the agent is known again reopens it.

**Pick (b).** One rule for runtime: *the record is the strip*. A tab that
cannot become a tab (no agent command, no session record) is not in the
strip and so not in the next write; a tab that is in the strip but whose
agent fails (start failed, `session/load` refused, exited, directory gone)
stays in it with its id, and so in the record, until the person closes it.
(c) needs a second list of tabs that are not on screen, with its own front
rule; not worth it for a removed agent. If none opens: interface's 1c, one
fresh tab of the default agent, for `--window` only. The change from (a)
also touches `--resume w-…`: **the owner's**.

## 1. What is written when

### Options weighed

| | When | Cost | SIGKILL leaves |
|---|---|---|---|
| A | Each change, at once, latest wins, no timer | one small write per change | the last change |
| B | Each change, debounced (e.g. 250 ms trailing) | fewer writes on a held key | up to 250 ms stale, and a timer to flush on every exit |
| C | Periodically (e.g. every 5 s) | a timer for the window's life | up to 5 s stale |
| D | Quit and signal only (alternative b) | none while running | nothing new: today's failure |

**Pick A.** The changes are person-paced (interface's table: a tab opened
or closed, the front moved, a session id known, a first prompt, `/clear`);
none comes from an agent's stream, so a flooding agent cannot drive writes.
The fastest source is a held `ctrl+x n` moving the front, at key-repeat
rate (~30/s); with one write in flight and one slot waiting, that is at
most one write per write's duration, each a few hundred bytes. B adds a
timer that every exit path then has to flush, for a saving nobody would
measure; C and D lose what the brief asks for.

### The keeper

```
WindowKeeper(write: (record) => Promise<void>, report: (error) => void)
  offer(record)   // after each change; equal text (sans `at`) is dropped
  freeze()        // synchronous: later offers are ignored
  settle()        // freeze, then wait for the write in flight and the slot;
                  // never rejects; bounded by the write itself
```

- **Dedup** compares `windowText` without `at` to the last one *written*
  (interface's rule), so a re-render that changes nothing writes nothing,
  and a failed write is retried by the next offer even if equal.
- **Latest wins:** an offer during a write replaces the waiting one; when
  the write ends the waiting one goes. This is the session record's
  "one write at a time, what comes during a write goes in the next".
- **Where offers come from:** an effect in `src/ui/app/sessions.ts` that
  gathers the tabs as `quit` does today (that gathering moved into one
  function both call), calls `windowNow` and offers it. It runs on every
  commit; `windowNow` over ≤ 9 tabs and one `JSON.stringify` are
  microseconds. No event list is kept by hand, so a future reorder is
  covered.
- **`at`** is set at write time, "last written" (protocol's 2).
- **Cost:** `mkdir -p` once per keeper (not per write), then `writeFile`
  of the temporary and `rename`: well under a millisecond on a local disk,
  off the render path (async).
- **No `fsync`,** as `saveSetting` and the session record do: rename is
  atomic against process death, which is the brief's threat; a power cut
  can lose the last changes on some file systems. Said, not designed for.

### At quit (ctrl+d, `/exit`, last tab closed)

`quit` in `sessions.ts` calls `keeper.freeze()` first, before `dispatch
({ type: 'closing' })` and `closeAll`, which take the tabs out. Then, in
`main.tsx` after `waitUntilExit`, `await keeper.settle()` replaces today's
`windowOnQuit` + `writeWindow` for a kept window; then the lock is
released; then the quit message is printed (interface's 2). A window
without `--window` keeps today's path (protocol: windows started by hand
keep both written decisions).

Whether the quit should first offer once more: no. Every change already
offered; the strip at the press of ctrl+d is what was last offered.

### On a signal or a crash

`leave` (renderer.tsx) runs every `closeOnForcedExit` entry in one
synchronous `map` before its first `await`. The keeper registers
`closeOnForcedExit(() => keeper.settle())`. Because `settle` freezes
synchronously, before its own first `await`, and the strip's emptying under
`closeAll` can only reach the keeper through a React commit (which cannot
happen inside that synchronous `map`), the freeze always precedes any
offer of the emptied strip, whichever entry was registered first. That
order is what a test pins (test plan, U4); it does not rest on Set order.

The settle then runs beside `closeAll` and the renderer's give-back under
`Promise.allSettled`: a hung agent (up to 2+2+2 s of `STOP_BOUNDS`) does
not hold the write, and the write does not hold the agents. After the
leave, the lock is released (by `proper-lockfile`'s own exit hook when
chord dies by the raised signal; checked below), then `raise`.

The same holds for a crash: `giveBackOnEveryExit` goes through `leave`.

### On SIGKILL

Nothing runs. On disk: the record as of the last completed rename, which
is the last change unless the kill landed during that change's write, in
which case the change before it; never half of one. A `w-<id>.json.<uuid>
.tmp` may remain (cleaned at the next start of that id, step 4). Session
records: up to their last line, as today; a first prompt sent in the same
milliseconds may be named by the window but have no record line yet, which
`windowTabs` already leaves out with its note (protocol's 4).

## 2. Two chords on one id

### What is needed

- Two starts at once on a new id: exactly one creates.
- A start while another chord holds it: refused, after a short wait.
- A start right after the holder got SIGHUP and is still in its leave
  (≤ ~7 s: agents' stop bounds plus the renderer's second): wait, then
  open. This is the launcher's common case (close pane, reopen).
- A start after the holder was SIGKILLed or crashed hard: not refused for
  ever.
- The holder's last write lands before the newcomer reads.

### Options

| | Mechanism | Stale after SIGKILL | Library |
|---|---|---|---|
| L1 | `proper-lockfile`: `mkdir` lock dir, mtime refreshed by a timer, stale after `stale` ms | after `stale` (≥ 2 s; default 10 s) | yes |
| L2 | `flock(2)` on `windows/w-<id>.lock` through `bun:ffi` | at once: the kernel drops it with the process | no: our own, in `src/platform/` |
| L3 | pid file by `open(…, 'wx')`, liveness by `process.kill(pid, 0)`, takeover by rename-aside then `link` | at once if the pid is dead; a reused pid reads as held | no: our own |
| L4 | `fs-ext` / `os-lock` (native `flock` addons) | at once | yes, native `.node`; not tried — a native addon in `bun build --compile` per target is what OpenTUI's own library already costs us, for one call |
| L5 | `lockfile` (npm, `O_EXCL`, stale by mtime with no refresh) | after `stale`, but a long-lived holder also goes stale | yes; last release 2022, built for short locks |
| L6 | No lock; last writer wins | — | — |

### Libraries tried

In a scratch directory outside the repository, Bun 1.4.3, darwin arm64,
each run from source and as a `bun build --compile` binary:

- **`proper-lockfile` 4.1.2** (last release 2022; depends on `graceful-fs`,
  `retry`, `signal-exit` 3). `lock(file, { stale: 3000, update: 1000,
  realpath: false })`: a second process is refused (`Lock file is already
  being held`); after the holder's SIGKILL a newcomer is refused for the
  `stale` window and takes it after; same from the compiled binary. With a
  chord-like SIGHUP handler that waits, then removes itself and re-raises
  (as `dieBySignal` does): the lock is **still held during the handler's
  wait** and gone after the raised signal kills the process. That is
  because `signal-exit` only acts when it is the last listener: it is,
  once `dieBySignal` takes its handlers off and raises, and it then removes
  the lock synchronously and re-raises itself. So chord still dies by the
  signal, and the lock outlives the leave, which is the order wanted.
  Costs: a timer refreshing the lock's mtime every `update` ms for the
  window's life; `onCompromised`'s default **throws from a timer** (an
  event loop stalled past `stale`, e.g. a laptop asleep), which must be
  replaced by a handler that notes it; and `signal-exit` adds its own
  listeners on every signal chord already handles, an interaction a test
  must hold (T3).
- **`flock` through `bun:ffi`** (`dlopen` of libc, `flock(fd, LOCK_EX |
  LOCK_NB)`): held, refused for a second process, free the moment the
  holder is SIGKILLed; works compiled. Costs: our own code, `bun:ffi` is
  marked experimental by Bun, and libc's name differs by target (glibc,
  musl, darwin), each of chord's four targets needing its own check.
- `lockfile` 1.0.4: installed, not pursued (L5's long-holder problem).

### Pick

**L1, `proper-lockfile`**, per the one rule: it runs under Bun and in the
binary, and does what is needed with options rather than workarounds:
`stale: 5000, update: 2500` (the newcomer after a SIGKILL waits ≤ 5 s),
`retries` sized to wait out a holder's leave (~ 10 s total), `realpath:
false` (the record may not exist yet at step 2; the lock is on the record's
path), and an `onCompromised` that reports once and goes on writing. The
holder's pid, which interface's refusal names, is not something
`proper-lockfile` stores: the refusal says `open in another chord` without
a pid, or chord writes a pid file inside the lock directory — which is
writing beside the library, so **left out unless the owner wants the pid**.

**The owner's:** L1 against L2. L2 is the better fit (no timer, no
staleness window, no `signal-exit`, a pid can sit in the locked file) but
is our own code on an experimental Bun API; per the one rule that needs the
owner's yes, and its trial above is not that yes. L6 is not offered:
two writers rewriting one record each with their own strip is exactly the
corruption the launcher would see as "the window came back wrong".

### What the second chord does

- Lock taken: proceed.
- Held: say on stderr, before the screen, `Waiting for window w-… (open in
  another chord)…`, retry for up to ~10 s (a holder in its leave lets go
  within that), then refuse: `error: Window w-… is open in another chord.`,
  exit 1, nothing drawn (interface's 1d). Not a Cliffy `ValidationError`,
  so no help is printed (interface).
- Stale (holder SIGKILLed): taken after `stale`, inside the same wait.
- `/resume` in a running chord, Enter on a window that another chord holds:
  opens its tabs beside as today (reading needs no lock) but does not adopt
  its id; the two chords then share sessions, as two chords resuming one
  session id share it today. Not made worse by this design; listed as open.

## 3. Failure cases

| Case | Expected outcome |
|---|---|
| State directory unwritable at start (`EACCES`, read-only FS) | Lock fails with the same error: start without the lock, status note once (interface's 1e (ii)), keeper keeps offering; each failed write is silent after the first note; at quit today's stderr line and the per-session commands. Refusing instead is the owner's (interface's 1e). |
| Disk full mid-run (`ENOSPC`) | `writeWindow` removes its temporary; the record on disk stays whole at the previous change; note once; the next offer retries; a success clears the standing note. |
| A write slower than the changes (network home, slow disk) | Latest wins: one in flight, one waiting, intermediate states skipped. Nothing queues. |
| Half-written record | Not possible from chord: write-beside-and-rename. A record damaged otherwise (hand edit, other tool): `--window` treats an unreadable record as **refused, not overwritten** (overwriting would destroy what a person may want back); `--resume` already refuses. The owner's if `--window` should rather start over. |
| Orphan `.tmp` files | Ignored by readers; removed for this id at start under the lock. |
| Record names a session record that is gone | Today's: left out with the note, the rest open; the next write drops it. All gone: interface's 1c (one fresh tab). |
| Agent can neither resume nor load | The tab opens, its start fails as `--resume <id>` fails today; the tab stays in the strip and the record with its id until closed. |
| Agent hangs on `session/load` / `session/resume` | The tab waits as today; the record already has it; a quit or signal stops the agent within `STOP_BOUNDS` and the record is unaffected. |
| Directory gone | The spawn (or the agent's `cwd` check) fails; the tab shows the failure and stays, as the row above. chord does not pre-check: the agent's own error is the truth, and a pre-check races the directory anyway. |
| Agent unknown | Protocol's question above: left out with a note. |
| Agent exits or crashes mid-session | No change to the strip, no write; the tab keeps its id. |
| Agent floods updates | No writes: the keeper is fed tab-level facts only, and dedup drops equal records. |
| Lock compromised (event loop stalled past `stale`) | Note once; keep writing. Another chord may have taken the id meanwhile: the case is a stalled process, rare, and the alternative (stop writing) loses the window for sure. |
| Lock's own directory removed by hand | Same as compromised. |
| A second signal during the leave | Held by `dieBySignal` as today; the keeper's settle is already in the leave. |

## 4. SIGHUP on a closing pane

**Measured** (fake agent, tmux session of its own, temporary
`XDG_STATE_HOME`, one run, killed after): `tmux kill-session` (SIGHUP to
the pane's process group) to chord *and* its agent gone: **87 ms**; the
session record (one prompt) was on disk whole. An idle agent exits on
stdin's end, the first and gentlest step of its stop.

That is tmux. A terminal app may follow SIGHUP with SIGKILL after a grace
of its own, or the system may be shutting down; Chorded's own behaviour on
pane close is CHRD-412's to say.

**The design must not depend on:**

- any time after the signal: the record is already current; the leave only
  waits for a write already started;
- stdout or the terminal: after a hangup writes to the tty fail; the
  resume line is not printed to anyone, and nothing relies on it (the
  launcher holds the id);
- the agent exiting in time: the window write is not ordered after it;
- the lock's release: a holder killed before releasing is stale within
  `stale` (L1) or at once (L2), and a newcomer waits that long.

## 5. Tests

### Module layout (tests mirror `src/`)

| Module | What | Test |
|---|---|---|
| `src/session/windows.ts` | `windowNow` (interface), schema (protocol), `windowText` | `tests/session/windows_test.ts` |
| `src/session/window_keeper.ts` (new) | `WindowKeeper`: dedup, latest wins, freeze, settle, failure reported once | `tests/session/window_keeper_test.ts` |
| `src/session/window_lock.ts` (new) | take / wait / release over `proper-lockfile`, its options, the refusal text | `tests/session/window_lock_test.ts` |
| `src/ui/app/sessions.ts` | the effect that offers; `quit` freezes; the `closeOnForcedExit` entry | window tests below |
| `src/main.tsx` | lock before the terminal; settle, release, message after `waitUntilExit` | `tests/cli_test.ts` (refusals), selftest |
| `src/platform/` | only under L2: `flock.ts` | `tests/platform/flock_test.ts` |

### Pure and module tests

- **K1** equal records (differing only in `at`) write once.
- **K2** three offers during one slow write: two writes, the second the
  last offer.
- **K3** `freeze` then `offer`: nothing written; `settle` resolves after the
  write in flight and the waiting one.
- **K4** a write that rejects: reported once; the next offer retries even if
  equal; a second rejection is not reported again; a success after it
  clears.
- **K5** `settle` never rejects and resolves at once with nothing pending.
- **W1** `windowNow` cases (interface's list) and both-ways readability
  (protocol's table), with a copy of today's schema as the "older chord".
- **L1–L4** in a temporary directory: take; a second take from a child
  process (`process.execPath`, a fixture script that takes the lock and
  idles) is refused within its retries; the child SIGKILLed, a take
  succeeds after `stale`; the child exiting normally releases at once.
- **T3** (renderer_test) with `proper-lockfile` loaded: `dieBySignal` with
  an injected `raise` still holds every close and the lock until the leave
  settles. Plus one child-process test that really raises: a fixture
  script with chord's `dieBySignal` and a lock dies by SIGHUP (exit by
  signal, not code) and leaves no lock directory.

### Window tests (harness, fake agent, temporary state directory)

Through `ui/app/render.tsx`'s `withWindow`, the window given a window id
and a state directory:

- **U1** mounted with a new id: the record exists with one tab (`agent`,
  `cwd`, no `sessionId`) before the fake agent's `session/new` answers
  (a fake flag that holds `session/new` until told, or the existing
  `--stop-gate` style gate).
- **U2** a prompt: the tab gains its `sessionId`; a second tab opened, the
  front moved, `/clear` (the tab loses then regains an id after a prompt),
  a tab closed: after each, the file matches `windowNow` of the strip.
- **U3** quit: `freeze` happened before `closeAll`; the file is the strip at
  the press, not empty.
- **U4** forced exit: `leave(renderer)` with two tabs open: the file is the
  pre-leave strip, never the emptied one; with `claudeslowstop` (an agent
  slow to stop) the write is on disk before the agents are gone.
- **U5** reopen: a record with a gone session record, an unknown agent, an
  agent that cannot reopen (new fake flag below), a removed directory: the
  window opens, notes as interface says, and the next write is the strip.
- **U6** unwritable state directory (`chmod 0500` on the temporary
  `windows/`): one note, the window works, no write after the first
  failure reported again.

### Real signals and the binary: `bun dev selftest`

`bun test` has no terminal to give a whole window, so real signals against
a whole chord run where a terminal already is: the selftest's tmux, on the
fake agent, on temporary state. New steps:

1. `chord fake --agent-command <fake> --window w-selftest01`: the record
   exists before the first prompt (one fresh tab).
2. A prompt, a second tab, the front moved back: the record names two tabs
   and the front.
3. `tmux kill-pane` (SIGHUP): the record is unchanged from 2, the lock gone
   within the leave bound, no agent left (`pgrep` on the fake's path).
4. `--window w-selftest01` again: both tabs, the front, `Hello, world.`
   drawn from the record.
5. `kill -TERM` the chord pid: as 3.
6. A change, then `kill -KILL`: the record is the change; the lock stale;
   `--window` again waits, then opens (within `stale` + retries).
7. Two `--window w-selftest02` at once in two panes: one opens, the other
   says it is waiting, then refuses after the bound.

A crash is covered by U4 (same `leave`) rather than by a binary that
crashes on purpose.

### Fake agent

- A flag `--no-reopen` (`CHORD_FAKE_NO_REOPEN`): advertises neither
  `loadSession` nor `sessionCapabilities.resume`, beside `--resume-only`.
- A gate on `session/new` (`--new-gate`), as `--stop-gate` gates a stop,
  for U1's "written before the agent answered".
- No new scenario: the existing `text` turn is enough; this feature is in
  what chord does around sessions, not in a turn.

## Open questions

For the owner (through the lead):

1. Lock: `proper-lockfile` (picked, a library, ≤ 5 s stale window, a
   timer, `signal-exit`) or `flock(2)` through `bun:ffi` in `src/platform/`
   (our own code, exact, experimental API).
2. The held-window refusal: with or without the holder's pid (the pid
   needs a file of ours beside the library's lock).
3. An agent in the record chord no longer knows: open the rest with a note
   (picked) or refuse as today — for `--resume w-…` too.
4. `--window` on an unreadable record: refuse (picked) or start over.

For the team and CHRD-412:

5. What Chorded does on pane close after SIGHUP (a SIGKILL after a grace?
   how long?) and whether it relaunches at once: sizes the wait (~10 s).
6. `/resume` of a window another chord holds: opens beside without the id
   (unchanged), or refuses.
7. Critic: whether the effect-per-commit offer is better replaced by
   explicit calls at the six change points; picked the derived form so no
   change point can be missed.
