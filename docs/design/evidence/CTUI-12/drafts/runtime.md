# CTUI-12 runtime proposal: processes, streams, failure modes, tests

Runtime architect's draft for the brief's R1 to R5, revised once after the
critic (the lead's items 1 to 7). The reference is
`../chord/src/acp/process.ts`, `../chord/src/platform/process.ts`,
`../chord/src/acp/connection.ts`, `traffic.ts`, `src/main.tsx` and
`src/session/leaving.ts`. Numbers and wording are theirs unless marked as a
proposal. O1 is (a): no fs or terminal capability, and such requests are
answered method-not-found.

Rulings adopted from the lead: framing follows the SDK (a line over 32 MiB
fails the connection with `MessageTooLargeError`, bad JSON is answered
-32700, an array or non-object -32600, and none of these reach the tap); the
way out kills every agent group on SIGTERM, SIGINT and SIGHUP and on a crash,
as `main.tsx` and `leaving.ts`; exit against stdout's end is the original's
policy; a request withdrawn by `$/cancel_request` is answered with the
handler's fallback as a result, as `connection.ts`; `cancel()`'s future means
*queued*. Q1 and Q6 are with the owner.

## Summary

- R1: Dart cannot put a child in a group of its own. Proposed: a re-exec
  launcher. chord starts itself with a hidden first argument; that copy
  calls `setsid()`, resets SIGPIPE, says so on fd 2 in a frame carrying a
  random nonce, then `execv()`s the agent in place. The agent keeps the pid,
  leads its own group and session, and `Process` keeps its pipes and exit
  code. Signals go to `-pid` once the group exists and to `pid` before it
  does. This was tried under `dart run`, `dart test` (from the package root
  and from another directory) and `dart compile exe` (run from `/`, with no
  source in reach). `butcher_process` 0.1.0 does not fit; that is owner
  question Q1.
- Hazards that were measured, each with a rule below:
  - an unguarded `stdin.done` ends chord when an agent closes its stdin;
  - Dart's children inherit SIGPIPE ignored;
  - `IOSink.flush()` binds the sink, so `add` and `close` throw while it is
    pending;
  - `close()` never completes against an agent that does not read;
  - Dart's `stderr.write` in the launcher would be lost to `exec`.
- Packages: `cancellation_token` 2.0.1 fits the cancellation primitive.
  Neither `io` 1.1.0's `shellSplit` nor `shlex` 2.0.2 matches the
  original's shell-quote 1.12.0; that is owner question Q7.
- From a git worktree `../chord` does not exist. The fake-agent finder
  resolves it through the main checkout.
- No request timeout is invented. Only the stop ladder, the stderr settle,
  the stdout drain and the writer's outstanding bytes are bounded.

## Module layout

Port files, named after the original's (`example/chord/lib/`), each with a
test of the same path under `example/chord/test/`:

| File | Holds | Tested by |
| --- | --- | --- |
| `platform/process.dart` | `spawnGroup` and `GroupProcess`: pid, stdio with the handshake stripped, `started`, `exit`, `signal`, `alive`. `Exit` keeps the code as a shell's `$?` and the signal's name. `ProcessGroups` is the registry of groups still holding a process, with `killAll()`. `Launcher` is the argv prefix, injectable. The ffi bindings `kill` (with errno) and `getpgid`. | real `sh` children |
| `platform/group_exec.dart` | The launcher: `groupExecFlag`, `Never groupExec(List<String> args)`, and a `main` for the JIT path. | real children; a `compile`-tagged test of the binary |
| `acp/process.dart` | `commandArgv`, `spawnAgent`, `AgentProcess`, `StopBounds`, `AgentExitError`, `settledWithin`, `STDERR_TAIL` (4096), `STDERR_LINES` (6), `STDERR_LINE_MAX` (1024), `STDERR_SETTLE_MS` (500). `StderrTail`, a pure class fed chunks. The stop ladder, over `GroupProcess`'s interface. | `StderrTail` and the ladder as units; `spawnAgent` with real children |
| `acp/writer.dart` | The connection's single writer: queue, admission bound, seal, end (R2). Pure over a byte sink interface. | unit, with a sink that never drains |
| `acp/traffic.dart` | `Traffic` (from agent, from chord, stderr) and the tap. | unit |
| `acp/connection.dart` | `openAgent`; `connectAgent(AgentProcess, options)`, kept apart as in the original; `clientCapabilities`; `AgentGone`; `Waiting` (session id to the tokens of agent requests waiting on the person), pure; `ask`; `close`. | in-memory `AgentProcess`; the fake agent (CTUI-13) |

The framing follows the SDK, as the lead ruled. It is the framework
architect's to build (F1). It must work over any pair of byte streams and in
both directions, because M2's `chord acp` serves ACP on chord's own stdio.

## R1. The process group

### What the original does

`spawnGroup` passes `detached: true` to `node:child_process`, which calls
`setsid()` in the child before `exec`. The pid is the group id. `signal` is
`process.kill(-pid, name)`. `alive` sends signal 0, and on macOS an EPERM
for a group of unreaped zombies counts as alive. node reports a failed exec
as a `spawn` error, so `started` rejects.

### What was tried

Scratch packages outside the repository, Dart 3.13.5, macOS arm64:

| Way | Result |
| --- | --- |
| Plain `Process.start` | The child is in chord's group. There is no `setsid`/`setpgid` option. |
| `setpgid` from the parent through ffi | Impossible. `Process.start` returns after the child exec'd, and POSIX then refuses (EACCES). |
| `ProcessStartMode.detachedWithStdio` | Dart double-forks under `setsid()`. The child's pgid is a dead intermediate's, not the pid given, and `exitCode` throws `StateError`. Rejected. |
| `setsid(1)` | Absent on macOS. |
| perl `setpgrp` shim | Works, 12 to 25 ms. Needs perl on the host. |
| `butcher_process` 0.1.0 | A setsid-then-perl shim. No environment parameter, SIGKILL only, and without a shim it kills the process alone. Does not fit (Q1). |
| **Re-exec launcher** | Works in every mode (below). |

Recorded trade-off, not pursued: `posix_spawn` with `POSIX_SPAWN_SETSID`
through ffi gives a group without a second program. It would mean our own
pipes turned into streams and our own reaping beside the VM's child
handling, which is far more code and risk than the launcher.

### The launcher's argv, frozen

```text
AOT:  <chord binary> --chord-group-exec <nonce> <path> -- <argv0> <args…>
JIT:  <dart> --packages=<package_config.json> <…/lib/platform/group_exec.dart>
          --chord-group-exec <nonce> <path> -- <argv0> <args…>
```

- `<chord binary>` and `<dart>` are both `Platform.resolvedExecutable`.
  Measured: under `dart run` and `dart test` it is the SDK's `dart`, and in
  AOT it is the binary itself.
- `--packages` is the absolute `Isolate.packageConfigSync`. The script is
  `Isolate.resolvePackageUriSync('package:chord/platform/group_exec.dart')`,
  also absolute. Neither depends on the current directory. Measured from the
  package root and from its parent, under `dart run` and `dart test`.
- `<nonce>`: 32 random bits in hex from `Random.secure()`, fresh per spawn.
- `<path>`: the program resolved before the launch, absolute. A name with a
  `/` is resolved against the agent's cwd. A bare name is looked up on the
  agent's `PATH`, which is chord's env with the agent's laid over, using
  `process_run`'s lookup, which the port already uses. A missing or
  non-executable program rejects the start with `cannot start <program>:
  <reason>`, as the original's does, and no process is started.
- `--` ends the launcher's own words. Everything after it is the agent's
  argv, passed to `execv(path, argv)` untouched. `argv0` is the program as
  written, so `ps` and the agent see what the person wrote; a program word
  like `-x` is just a word. An empty program never reaches here, because
  `commandArgv` refuses it.
- Who consumes the flag: in AOT, the first statement of `bin/chord.dart`'s
  `main` is `if (args.isNotEmpty && args.first == groupExecFlag)
  groupExec(args);`. That runs before argument parsing, settings or the
  terminal, so nothing of chord runs in the launcher. In JIT,
  `group_exec.dart`'s own `main`. `groupExec` checks the shape (flag, a hex
  nonce, an absolute path, `--`, at least `argv0`). A malformed call
  (someone typing the flag) prints one line and exits 126.
- The discriminator is `const bool.fromEnvironment('dart.vm.product')`. It
  is true exactly in product-mode AOT code, which is what `dart compile exe`
  makes, and false under `dart run` and `dart test`. The alternatives depend
  on names: `Platform.script` is a `.dart` file under `dart run` but a
  kernel or data URI under `dart test`, and the executable's basename
  changes when the binary is renamed. A kernel or JIT snapshot is not a
  shipped form; it would take the JIT path and need the source.
- Measured cost, launch to handshake: 12 ms AOT, 164 to 210 ms JIT.

### What the launcher does, in order

1. `signal(SIGPIPE, SIG_DFL)`. Measured: Dart's children inherit SIGPIPE
   ignored (`yes | head -n1` printed `Broken pipe` under a plain
   `Process.start`), and node resets it. With the reset the message is gone.
2. `setsid()`. On failure, the frame `chord-exec <nonce> fail setsid
   <errno>` and `_exit(126)`.
3. The frame `chord-exec <nonce> ok` and a newline.
4. `execv(path, argv)`. On failure, the frame `chord-exec <nonce> fail exec
   <errno>` and `_exit(127)` for ENOENT, `_exit(126)` otherwise.

Frames are written with libc `write(2, …)`, not Dart's `stderr`: Dart's
stdio sinks write asynchronously, and `exec` would drop what is still
buffered. Nothing else goes to fd 0, 1 or 2 before `exec`.

### When `started` means the group exists

`spawnGroup`'s stderr reader takes the first line before anything reaches
`StderrTail` or the tap:

| First line, or what comes instead | Meaning |
| --- | --- |
| `chord-exec <nonce> ok` | `setsid` is done, so `started` resolves and the group exists. If the next line is `chord-exec <nonce> fail exec <errno>`, exec failed: `started`'s successor `execFailed` rejects, and the connection turns it into `cannot start <program>: <strerror>`. Anything else is the agent's own stderr and passes through. |
| `chord-exec <nonce> fail setsid <errno>` | `started` rejects: `cannot start <program>: setsid: <strerror>`. |
| stderr ends, or the process exits, before the `ok` frame | `started` rejects. If the launcher was stopped, the reason is that cancellation. |

The agent cannot forge a frame. The nonce is in the launcher's argv only, and
`execv` replaces that argv; it is never in the env. Only the first line, and
a fail frame right after it, are read as frames. No exit code is read as a
start failure on its own, since an agent may exit 126 or 127 itself.

There is no timer on the handshake. A launcher that never says `ok` is
handled like any start: by the open's cancellation or by `close()`.

### Signals before and after the group exists

`signal(name)`: `kill(-pid, name)`; on ESRCH, `kill(pid, name)`.

- Before `setsid` there is no group with id `pid` (the pid is fresh), so the
  first call fails with ESRCH and the second reaches the launcher itself,
  which has started nothing. Measured with a gated launcher: `kill(-pid)`
  gave errno 3, `kill(pid)` ended it, and the exit came as -15.
- After `setsid`, the first call reaches the whole group.
- A `setsid` that falls between the two calls means the second reaches the
  agent alone. Anything it started in that instant is still in group `pid`,
  and the ladder's sweep SIGKILL to `-pid` after the exit catches it. The
  group id lives while any member does.

A stop or cancel before `started` runs the same ladder through this
`signal`. Ending stdin works on the launcher's pipe as on the agent's.

### `Exit`, `alive`, the registry

`Exit` is built from Dart's exit code: a negative `-n` means signal `n`, kept
as code `128 + n` with the signal's name, as the original's `exitOf`.
`alive()` is `kill(-pid, 0)` through ffi, with EPERM on macOS read as alive,
as the original's. `ProcessGroups` is an object with a default instance, so
tests get their own.

### The way out (ruled: as the original)

An agent in its own session gets none of the terminal's signals. chord
watches SIGTERM, SIGINT and SIGHUP (`ProcessSignal.watch`) and closes every
agent within the ladder's bounds, then re-raises the signal to itself, as
`main.tsx` does. On an uncaught error, and as the last thing before
`exit`, it calls `ProcessGroups.killAll()`, which sends SIGKILL to every
group still holding a process without waiting, as `leaving.ts` does. A chord
killed with SIGKILL leaves agents to end at their stdin's EOF.

## R2. Stop ladder, close ordering, ordering, backpressure, hung agents

### The stop ladder (as `process.ts`)

`stop(bounds)` is `stopping ??= _stop(bounds)`. Each wait is "the exit is
seen within the bound", on timers the ladder cancels:

1. `writer.end()`, which never awaits (see the writer below).
2. Not seen within `exitMs` (2 s): `signal(SIGTERM)`, then wait `termMs`
   (2 s).
3. Not seen: `signal(SIGKILL)`, then wait `killMs` (2 s).
4. Not seen: throw `AgentExitError([pid])`.
5. Seen at any step: SIGKILL to `-pid` anyway, as a sweep.

### `close()`, a synchronous barrier

`close()` is `closed ??= _close()`:

```text
synchronously, in one turn of the event loop:
  closing.cancel()        every waiting request's onCancel runs now and
                          enqueues its fallback answer on the writer, also now
  writer.seal()           from here no new application message is admitted
                          (requests fail with AgentGone; notifications and
                          late handler answers are dropped)
  writer.end()            stdin is ended once the queue ahead of it is out
then:
  try   await process.stop(bounds)        the ladder; never waits on the writer
  finally
        await settledWithin(stdoutDone, DRAIN_MS = 1 s)
        connection.close(): routing stops, every pending chord request fails
        with AgentGone, tokens are released
  rethrow AgentExitError if the ladder threw it
```

What makes it synchronous: `cancellation_token`'s `cancel()` calls every
attached `Cancellable.onCancel` inside the call (measured), and the writer's
`enqueue` is synchronous. The claim is therefore exact: the fallback answers
sit in the writer's queue ahead of stdin's end. An agent that reads its
stdin reads them before EOF. An agent that does not read never sees either,
and the ladder ends it on its timers. The `finally` runs even when the
ladder throws, as the original's.

### The writer, and an agent that stopped reading

Measured: while `IOSink.flush()` is pending, `add` and `close` throw
`StateError: StreamSink is bound to a stream`. `close()` never completes
while data the agent has not read is buffered; 4 MiB added to a non-reader
was still pending after 200 ms, and SIGKILL settled it within 10 ms.
Unflushed adds grow chord's memory without bound.

So the connection has one writer of its own:

- `enqueue(message)` is synchronous. It encodes the line, hands it to the
  tap (so the tap's order is the wire's), and appends it to the writer's
  queue.
- A pump moves everything queued into the sink with `add`, then awaits one
  `flush()`. While that flush is pending, new messages wait in the writer's
  queue, never in the sink, so the sink is never touched while bound.
- **Admission bound** (proposal): outstanding bytes, meaning queued plus in
  flight since the last flush completed, are capped at 4 MiB. ACP's own
  messages from chord are prompts, answers and notifications. A prompt with
  images can be a few MiB, so the cap is above one large prompt and well
  below a memory problem. An `enqueue` that would pass the cap puts the
  writer in **stalled**: the message is refused; every pending chord request
  fails with `AgentGone` built from what the agent left on stderr, with
  `stalled` set; `gone()` turns non-null; and the session layer closes the
  agent, as for any gone agent. A stalled writer refuses everything after.
- `seal()` stops admission. `end()` closes the sink once the in-flight flush
  completes, without being awaited by anyone. Against a non-reader that
  flush never completes and stdin never ends; the ladder's SIGTERM and
  SIGKILL bypass it, and the sink settles with an error that is caught.
- `stdin.done` gets an error handler the moment the process starts.
  Measured: without one, an agent that closes its stdin ends chord with an
  unhandled `SocketException: Write failed (Broken pipe)` (exit 255). A
  sink error puts the writer in **failed**, which refuses and fails pending
  requests as stalled does.
- A request whose token is already cancelled is never enqueued.

### Exit, stdout's end and stderr's end (as the original)

Dart gives three independent futures (`exitCode`, stdout's done and
stderr's done) with no order between them.

- **The connection ends when stdout ends** (or errors), never at the exit.
  The original's `ask` gives up on `connection.signal` (stdout's end) or the
  caller's signal, and nothing else.
- **`gone()`** turns non-null at once when the connection ends. It returns
  `lastWords ?? stderrTail().trim()`, so possibly empty or incomplete at
  first.
- **Every pending request** fails with `AgentGone`, built once the last
  words have come: stderr's end or 500 ms, whichever first. The exit is
  attached if it is seen within another 500 ms. Messages read before
  stdout's end reach the tap and the routing first, and a final line without
  a newline is handled as the SDK handles it.
- **`exited`** settles at the exit plus the last words. It fails nothing.
- **An exit before `initialize`'s answer** rejects the open only through
  stdout's end. Normally the exit closes stdout at once, so the open rejects
  with `AgentGone`, or with the start failure from the handshake. When a
  descendant still holds stdout, the open stays pending, as in the original,
  until the caller cancels it or the window closes; `close()` then kills the
  group, stdout ends, and the open fails. The earlier draft's line "an exit
  before `initialize` rejects the open" was wrong for that case.

### What the agent writes, and floods

- stdout is always listened to and never paused. Each read is decoded and
  routed synchronously in wire order: tap, then route. An update sent
  before a reply reaches the subscriber before the reply's future completes.
- Notifications reach the subscriber through the tap only and are not
  validated, so an unknown update kind or notification passes raw.
- Framing errors follow the SDK (ruled): over 32 MiB on one line,
  `MessageTooLargeError` and the connection fails; bad JSON, -32700; an
  array or non-object, -32600. None reach the tap.
- A flood (the fake's `flood`, 64 MiB as fast as it is taken): each pipe read
  is one event of at most one pipe buffer, so timers, frames included, run
  between reads. That chord stays responsive and how much memory it takes
  are measured by the benchmark (R5), not claimed. Memory is mostly the
  subscriber's (the transcript), which the client does not bound.

### A hung agent

No timeout on `initialize` or any request, as in the original. The person
cancels, closes or quits; the open takes a cancellation token while it
starts. Only the stop is bounded. With `--hang`, the fake ignores SIGTERM
and outlives stdin's end, so only the ladder's SIGKILL ends it.

### Several agents in one window

Each agent has its own group, connection and writer; only `ProcessGroups`
is shared. Closing the window closes all of them concurrently: one ladder
of 6 s plus 1 s, not one per agent.

## R3. Cancel

The cancellation primitive is `cancellation_token` 2.0.1 (pub.dev, verified
publisher, 160 points, last release July 2023), tried:

- `cancel()` runs attached `Cancellable.onCancel` synchronously inside the
  call, which close's barrier needs.
- `MergedCancellationToken([a, b])` is the "any" of several.
- The first reason is kept (`exception`); later cancels are ignored.
- A `Cancellable` attached to a token already cancelled gets no callback,
  so a handler checks `isCancelled` first. That is the interface's rule
  "check before publishing a pending permission".
- `CancellableCompleter` gives a future that fails on cancel.

`package:async`'s `CancelableOperation` cancels one operation and has no
merge, so it does not fit. Our own `CancellationSignal` is not needed; the
interface draft's `CancellationSignal` becomes `CancellationToken`.

Bookkeeping, as `connection.ts`:

- Every request from the agent to chord (M1: `session/request_permission`)
  runs through `answer(sessionId, requestToken, fallback, handler)`:
  - a token is registered under its session id in `Waiting`;
  - the handler gets `MergedCancellationToken([own, request's, closing])`;
  - the first of three wins: the handler's answer, its failure (answered
    with the fallback), or the token's `onCancel` (the fallback, enqueued
    synchronously);
  - exactly one answer goes on the wire, and a late result is ignored;
  - the entry leaves `Waiting` when the answer is settled.
- The permission fallback is `{outcome: {outcome: "cancelled"}}`.
- `cancel(sessionId)`: synchronously cancel that session's tokens, so their
  answers are enqueued, then enqueue `session/cancel`. **Its future completes
  when the notification is queued** (ruled), and fails with `AgentGone` if
  the writer is sealed, stalled or failed.
- `$/cancel_request` for a request of the agent's cancels that request's
  token. The answer is the fallback, as a result (ruled).
- `close()`: see the barrier in R2.
- fs, terminal and any other method chord does not handle get -32601. The
  cursor and grok plan methods get `cancelled`, never -32601, which cursor
  reads as accepted (`plans.ts`).

Prompt settling:

- `prompt()` settles with the agent's own answer, `stopReason: "cancelled"`
  after a cancel the agent obeys. The client never invents a stop reason.
- If the prompt's own token is cancelled, `cancel(sessionId)` is sent and the
  local wait ends at once with the token's exception. The agent's answer,
  when it comes, is tapped and otherwise dropped.
- If the agent ignores the cancel (`ignorescancel`, `--hang turn`), the
  prompt stays pending until the person closes. It then fails with
  `AgentGone` within the ladder.
- A cancel with no turn running sends one notification (the fake's
  `cancels`).

## Splitting a command line (`commandArgv`)

The original uses shell-quote 1.12.0's `parse` with `$NAME` left as written,
and refuses any non-string token (operator, glob, comment). Tried against it
on 16 command lines (a scratch harness ran shell-quote under bun):

| Case | shell-quote 1.12.0 | `io` 1.1.0 `shellSplit` | `shlex` 2.0.2 `split` |
| --- | --- | --- | --- |
| `"a b" 'c d'`, `"" ''`, `a\ b`, `"q\"x"`, `'it'\''s'`, `--flag=val "x y"z` | as a shell | same | same |
| `$HOME`, `'$Y'` | kept literal | same | same |
| `"${X}y"` | `$Xy` | `${X}y` | `${X}y` |
| `a\|b`, `&& x`, `> f`, `; x`, `$(id)` | operators, so chord refuses | literal words | literal words |
| `*.ts` | glob, refused | literal word | literal word |
| `# comment` | comment, refused | dropped | the words `#`, `comment` |
| `"unclosed` | accepted, `unclosed` | throws | throws |

Neither package refuses shell syntax, which is the original's behaviour a
person sees ("holds shell syntax; give a plain command line"). Using one
anyway means a check of our own around it, which AGENTS.md sends to the
owner. That is Q7.

## R4. Tests

No test reaches a real model, agent or terminal.

### Unit, no process

These use an in-memory `AgentProcess` (stream controllers for stdout and
stderr, a sink whose flush completes only when the test says so, a completer
for the exit, a recording `signal`) and `fake_async` for every bound.

- **`StderrTail`**: the original's `process_test.ts` cases fed as chunks:
  - the last six non-empty lines, and the count before them;
  - an unfinished last line;
  - a line past 1024, cut and marked `…`;
  - CRLF and blank lines across chunk boundaries;
  - the 4096 tail.
- **The handshake parser**:
  - `ok`, then agent stderr, which passes through;
  - `ok`, then `fail exec`, which gives `execFailed`;
  - `fail setsid`;
  - stderr ending before `ok`;
  - a frame with the wrong nonce, which is agent stderr;
  - a frame after the agent's first line, which is agent stderr;
  - a frame split across chunks.
- **`signal`**: ESRCH from `-pid` falls back to `pid`.
- **The ladder**:
  - an exit at each step;
  - each signal only after its bound;
  - the sweep after an exit;
  - `AgentExitError` when no exit comes;
  - idempotence: two calls run one ladder.
- **The close barrier**:
  - a permission request arrives and `close()` is called in the same
    synchronous turn: exactly one `cancelled` answer is in the sink's bytes
    before stdin's end;
  - `cancel()` then `close()`: one answer and one `session/cancel` before
    the end;
  - a blocked sink (flush never completes): `close()` finishes within the
    ladder's bounds, no `StateError`, the sink's late error caught;
  - the ladder fails: `AgentExitError` is thrown, *and* pending requests have
    failed, *and* routing has stopped.
- **The writer**:
  - the tap's order equals the bytes' order;
  - nothing touches the sink while a flush is pending;
  - the 4 MiB bound gives stalled, with pending requests failed and `gone()`
    non-null;
  - a sink error gives failed, with no unhandled error;
  - a cancelled token never enqueues;
  - `cancel()`'s future completes when queued.
- **Exit, stdout and stderr, every order**:
  - exit, stdout's end, stderr's end;
  - stdout's end, stderr's end, exit later than 500 ms (the exit is not
    attached);
  - stderr's end, exit, stdout held open (nothing fails; `close()` kills,
    stdout ends, pending requests fail);
  - stdout's end with the process alive;
  - stderr that never ends (the 500 ms settle);
  - each checks that `gone()` turns non-null at stdout's end and not before,
    and what `AgentGone` carries.
- **Routing**:
  - an update before a reply reaches the tap first;
  - an update before `session/new`'s answer is routed (the interface's
    buffer);
  - a reply after the caller's cancellation is tapped and dropped;
  - an unknown notification and update kind pass raw.
- **`Waiting` and permissions**:
  - handler answers; handler throws;
  - turn cancel; `$/cancel_request`; close;
  - a late answer is ignored;
  - two requests at once for one session stay distinct;
  - one answer on the wire in every case.
- **Unhandled methods**: fs and terminal get -32601; cursor and grok plans get
  `cancelled`.
- **`commandArgv`**: the 16 cases above, with the original's results, once
  Q7 is decided.

Marked in-memory only, because no fake scenario plays them:

- an update before `session/new` answers;
- stdout closed without an exit;
- a permission withdrawn by `$/cancel_request` (Q6);
- a sink that never drains.

### Against a real child (`test/platform/`, `test/acp/process_test.dart`)

These use `sh -c` scripts with the original's test bounds (exit 100 ms,
term 300 ms, kill 2000 ms):

- **Group**:
  - the agent leads its own group (`ps -o pgid=`);
  - a background child is in it;
  - SIGTERM reaches the grandchild;
  - a script trapping TERM ends by SIGKILL within bounds;
  - nothing is left afterwards (`alive()` false).
- **Cancel right after launch**: the open's token is cancelled in the same
  turn `Process.start` returns. The stop runs before the handshake; the
  launcher is gone (`kill(pid, 0)` ESRCH); no group is left.
- **Gated launcher**: the injected `Launcher` wraps the real one in
  `sh -c 'while [ ! -e "$GATE" ]; do sleep 0.02; done; exec "$@"'`, so
  nothing of the launcher has run.
  - A stop while gated: SIGTERM reaches the pid alone, `started` rejects with
    the cancellation, and no orphan is left.
  - Releasing the gate before the stop: normal start.
  - No hook in the launcher itself.
- **Failures and stderr**:
  - a missing program and a non-executable one give `cannot start …` with no
    process started;
  - a program removed between resolution and exec gives the `fail exec`
    frame;
  - a grandchild holding stderr past the exit gives last words at 500 ms,
    with the stop still bounded.
- **What the agent gets**:
  - env laid over chord's;
  - an unrelated cwd (`/tmp`) honoured;
  - argv untouched, with `argv0` as written (measured: `-dash-name` arrived
    as `$0`);
  - SIGPIPE default (`yes | head -n1` silent);
  - an agent closing its stdin while chord writes: no crash.
- **Modes**: run with `(cd example/chord && dart test)`, and once more as a
  test that spawns `dart run` of a small fixture script with
  `workingDirectory` set to the repository root, then to `example/chord`.
  The JIT launcher is found the same way from both.
- **`compile`-tagged** (as the framework's `-t compile --run-skipped`):
  `dart compile exe example/chord/bin/chord.dart` into a temporary directory,
  run from `/` with `HOME` set to an empty temporary directory so no source
  is in reach. It checks the AOT self-exec: own group, exit code, missing
  program, malformed flag (exit 126).

### Against the original's fake agent (CTUI-13)

The agent's argv is `[<bun, absolute>, <chord>/tests/fixtures/fake_agent/main.ts
(absolute), --scenario <name>?, flags…]`. Every test closes its agent in
`tearDown` with the short bounds.

The finder (`test/fixtures/fake.dart`, CTUI-13) resolves, in order:

1. **The original's checkout.**
   - `CHORD_SOURCE`, if set, wins. It must hold
     `tests/fixtures/fake_agent/main.ts`, or the test is skipped saying
     `CHORD_SOURCE` is wrong, with no fallback.
   - Otherwise git: `git rev-parse --path-format=absolute --git-common-dir`,
     run with `workingDirectory` set to the port's package directory
     (`Isolate.resolvePackageUriSync('package:chord/…')`, never
     `Directory.current`). The result is absolute (a relative one, from an
     older git, is resolved against that same directory). Its parent is the
     main checkout, and `../chord` is beside it.
   - Without git (no binary, or not a repository, as in an unpacked
     tarball): `../chord` beside the repository root, which is the package
     directory's `../..`.
   - Measured: inside `../chorded-tui-worktrees/<key>`, `../chord`
     relative to the worktree does not exist.
2. **bun.** `CHORD_BUN` (absolute, executable) wins; else `bun` on `PATH`,
   resolved to an absolute path.
3. **The SDK the fake imports.**
   `<chord>/node_modules/@agentclientprotocol/sdk/package.json` exists. The
   skip names its version if it is present but differs from the original's
   own `package.json` range.

Each missing piece is a `skip:` reason saying which and how to fix it: "bun
not found; install bun or set CHORD_BUN", "../chord not found beside the
main checkout; check it out or set CHORD_SOURCE", "the ACP SDK is missing
in ../chord; run bun install there". Tests are tagged `fake_agent`. The
finder is unit-tested with injected env, a git runner and a file-existence
function, and once for real from the repository root and from
`example/chord` (the subprocess way above).

Scenarios for M0/M1 (all exist in the fake today):

| What | Scenario or flag |
| --- | --- |
| initialize, session/new, commands after it, usage per turn | default `text`; `--no-usage` |
| updates M1 draws | `text`, `thought`, `todos`, `tools`, `calls`, `edit`, `rewrite`, `markdown`, `long` |
| an update after the answer | `late` |
| unknown kinds and notifications pass raw | `unknown`, `authstatus` |
| permission, answered and cancelled | `permission`, `twins`, `overlapask`, `leftask`, `mainbetween` |
| cancel | `slow` or `long` then cancel; `permission` then cancel; `cancels` |
| cancel ignored | `ignorescancel`, `--hang turn` |
| prompt errors | `error`, `turnfailed` |
| exit mid-turn with last words | `crash` |
| start failures | `--start-fails traceback`, `stdout`, `notacp`, `alias` |
| no answer to initialize; SIGTERM ignored | `--hang start` (the full ladder against a real process) |
| flood | `flood` |

What CTUI-13 must provide:

- the finder and the skip reasons;
- `fakeAgentCommand(scenario, flags)` with absolute argv, and the original's
  `gatedCommand`;
- a harness that opens an agent on a scenario with a traffic recorder and
  always closes it with short bounds;
- a note that `bun install` in `../chord` is a precondition.

## R5. Performance

- From a stdout read to the reducer is synchronous: split, decode, tap,
  route. The framework's `scheduleFrame` coalesces every mark into at most
  one frame per 16 ms (`run_app.dart`), so the client schedules no frames.
- Decoding stays on the main isolate unless the benchmark shows one decode
  holding a frame.
- The benchmark, `example/chord/benchmark/acp_updates.dart`, has no terminal
  and measures, rather than assumes:
  - **heartbeat lateness**: a 16 ms periodic timer's worst and 99th
    percentile lateness while 10 000 updates arrive in one burst, while
    1 000 a second arrive for 10 s (in-memory), and while the fake's `flood`
    plays (a real pipe);
  - **frames drawn** by a headless host over the same runs;
  - **cancel latency**: from `cancel()` to `session/cancel`'s bytes in the
    sink, during the burst, and, against the fake's `flood`, to the prompt's
    answer;
  - **a non-reading child**: a real `sh -c 'sleep 30'` agent sent prompts
    until the writer stalls. The time and bytes to stalled, chord's RSS
    before and after, and that `close()` ends within the ladder.
  - **memory**: RSS before and after each run, as a number reported, not a
    claim.
- A framework test checks that a thousand updates between two pumps draw
  once.

## O2 from the runtime's side

| Capability | Declared | Not declared |
| --- | --- | --- |
| `_meta.terminal_output_delta` | Many small `tool_call_update`s while commands run (Claude), the highest rate an agent sends. | Output comes once, as text. |
| `subagents` | Updates and requests under several session ids on one connection. `Waiting` and routing already key on session id. | Claude stamps children into the parent with `_meta`; Codex sends none. |
| `elicitation` | More requests waiting on the person, through `answer` (session id optional). | One that comes anyway is cancelled. |
| `plan`, `session.compaction`, `session.notices` | Their own update kinds, routed like the rest. | Reply text or tool calls instead. |

None changes the runtime's shape, so the empty set the interface proposes
for M0/M1 can widen later at no cost.

## What later milestones add

- M2 load, resume, list, fork, set_title, auth/status, set_mode, set_model,
  set_config_option and steering: more `ask` calls behind capability checks.
- M2 `chord acp`: the same framing and writer over chord's own stdio.
- M3 elicitation and plans: handlers through `answer`.
- M4 children and relays: more connections under one `ProcessGroups`; a
  relay is a hook between framing and tap.

## Open questions

- **Q1 (owner): how the agent gets its own group.** `butcher_process` 0.1.0
  does not fit (no environment, SIGKILL only, perl on macOS, falls back to
  the process alone).
  - (a) The re-exec launcher above: our own `dart:ffi` code run by chord's
    binary. It needs nothing on the host and was tried in every mode.
    Recommended.
  - (b) A setsid-then-perl shim of our own: no ffi in the launcher, but perl
    is needed on macOS and minimal Linux, SIGPIPE stays ignored, and a failed
    exec is seen only through stderr text.
  - (c) `butcher_process`, after asking upstream for an environment
    parameter and a choice of signal.
- **Q6 (owner): permission withdrawn by `$/cancel_request`.** The original
  has no fake scenario that plays it. Unit tests only, or a scenario the
  owner arranges.
- **Q7 (owner, new): `commandArgv`.** Neither `io` 1.1.0 nor `shlex` 2.0.2
  refuses shell syntax as shell-quote does, and they differ on `${X}y`,
  comments and an unclosed quote (table above).
  - (a) Port shell-quote's `parse`, kept to what `commandArgv` reads: our
    own tokenizer with the original's cases as tests. Exact behaviour.
    Recommended, since a person sees the refusal.
  - (b) `io`'s `shellSplit` plus our own check for unquoted operator, glob
    and comment characters. The check needs a quoting-aware scan, nearly a
    tokenizer, and differs on `${X}y` and an unclosed quote.
  - (c) `io`'s `shellSplit` alone: operators become literal arguments, and
    the "holds shell syntax" refusal is gone. A difference from the
    original.
- Q8 (lead): the writer's admission bound of 4 MiB outstanding bytes, and
  "stalled" treated as the agent gone. The original has no bound.
