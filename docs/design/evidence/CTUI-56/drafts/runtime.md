# CTUI-56 runtime draft: `chord acp`

Author: runtime (architects). Answers the brief's questions 9 to 13, plus
what the run time of a server adds that the other drafts may miss. The
original is `../chord`; every reference to it is by its own file names.

Scope, as the lead relayed the owner's decision: `_chord/session/state` and
`_chord/session/steer` are in; `_chord/agents/*`, `_chord/monitors/*`,
`/team` and `/new` are out, and chord adds no commands of its own. Children,
teams, tasks and monitors get seams only.

## 0. What the original's run time is, in one page

`runAcp` (`src/acp_agent.ts`) is one client connection with any number of
`Entry`s, each a `Conversation` over its own agent process. Its run time
rests on five pieces, and the port needs a Dart counterpart of each:

1. **The wire** (`src/acp/stdio.ts`, the SDK's `ndJsonStream`): one JSON
   message per line, 32 MiB cap on a read line, one write queue to stdout,
   and `seeingWrites`, which tells when the answer to a given request id
   has actually been written (`expect(id)`, `drained()`, `failed()`).
2. **The dispatcher** (`src/acp/agent_app.ts` over the SDK's `agent()`):
   one handler per method, an `AbortSignal` per incoming request that
   `$/cancel_request` aborts, -32601 for the rest.
3. **The turn table** (`src/acp/upstream_turns.ts`): a pure reducer that
   binds each `session/prompt` request id to a turn id *before* the turn is
   sent, and turns `Conversation` events into answers (`answer`,
   `cancelled`, `session_gone`, `message`) and into the session state.
4. **The entry's gate** (`live`, `held`, `past`, `replaying`): nothing of a
   session reaches the client before the client has that session's id;
   a load's past goes ahead of its answer.
5. **The way out** (`src/session/leaving.ts`, `createLeaving`): one
   shutdown whatever started it, a 15 s deadline armed first, a 500 ms
   drain, every step started in parallel in one tick, process groups
   killed last, the exit code or the signal.

## 1. Module layout (runtime view)

Names follow the original's files, as AGENTS.md asks. The framework
architect owns the final layout; this is what the run time needs to be
separable and reachable by tests. Nothing goes into `lib/` of the
framework.

| Port file (`example/chord/lib/`) | From `../chord/src/` | Runtime content | Test (`example/chord/test/`) |
| --- | --- | --- | --- |
| `acp/stdio.dart` | `acp/stdio.ts` + `ndJsonStream` | `ServerWire`: reads lines through the existing `acp/wire.dart` `LineDecoder` (32 MiB cap, framing replies), one FIFO writer with per-id written futures (`expect`, `drained`, `failed`) | `acp/stdio_test.dart` |
| `acp/agent_app.dart` | `acp/agent_app.ts` | `AgentApp`: the serving dispatcher, a `CancellationToken` per incoming request, `$/cancel_request`, -32600/-32601/-32602 shapes, params parsing | `acp/agent_app_test.dart` |
| `acp/upstream_turns.dart` | `acp/upstream_turns.ts` | the turn table, pure | `acp/upstream_turns_test.dart` |
| `acp/host_fold.dart` | `acp/host_fold.ts` | main's open asks for `requires_action`, pure (children's fold later) | `acp/host_fold_test.dart` |
| `session/leaving.dart` (extended) | `session/leaving.ts` | `createLeaving`: reasons, steps, deadline, drain, exit mapping; the existing `Owned`/`leave` stay for the window | `session/leaving_test.dart` |
| `platform/signals.dart` (moved) | `main.tsx` signal wiring | `dieBySignal`, `raiseSignal`, moved out of `ui/app/renderer.dart` so the server imports no UI | `platform/signals_test.dart` |
| `session/upstream.dart` | `session/upstream.ts` | pure mapping (gating, aliases, config, prompt blocks); interface/framework own its content | `session/upstream_test.dart` |
| `acp_agent.dart` | `acp_agent.ts` | `runAcp`: entries, gate, asks, account source, the handlers, the way out | `acp_agent_test.dart`, `acp_agent_fake_test.dart` |
| `bin/chord.dart` / `cli.dart` | `main.tsx` `serveAcp`, `cli.ts` | parsing, `byHandNote`, real stdin/stdout/stderr, signals, zone for crashes, exit | `cli_acp_test.dart`, `cli_acp_compile_test.dart` |

Existing port modules reused unchanged: `acp/wire.dart` (`LineDecoder`,
`MessageTooLargeError`), `acp/process.dart` (`settledWithin`, stop ladder),
`platform/process.dart` (`ProcessGroups.killAll`), `session/sessions.dart`
(`readRecords`, `earlierSessions`, `sessionById`), `settings.dart`.

Seams the run time needs in existing port modules (detail in section 9):

- `Conversation.send(..., {String? turnId, links, resources, attachments})`:
  a caller-chosen turn id. `send` today mints `turn-n` itself, and the
  idle path reaches `_play` synchronously, so the server cannot bind a
  request to a turn id it learns only after `send` returns.
- `Conversation.steerQueued([String? turnId])`: steer *its own* entry, not
  the oldest eligible one (the original's `steerQueued(turnId)`; tests
  "it takes its own entry into the running turn, not the prompt queued
  ahead" and the U1 queue-ownership tests).
- `Conversation.rename(title)` and the pending-rename send on resume
  (`conversation.ts` near line 3431), and `recordPendingRename`.
- Account state on `Session` (CHD-629's `AccountState`) and an event for it.
- An ACP past for `session/load`: the record's raw `prompt` (with `from`),
  `update` and `renamed` events, which `replay.dart` folds into transcript
  actions and partly drops today (it skips `renamed` and omits `from`
  prompts).

## 2. The wire (question 1's run-time half, owned with framework)

### Reading

- `stdin` is a single-subscription byte stream. Chunks go through
  `LineDecoder` (already the SDK's framing, tested against the agent side).
  Each decoded message is dispatched synchronously, in order, before the
  next line is decoded, so `$/cancel_request` can never overtake the
  request it names, and a request's synchronous part (binding a prompt to
  its turn, claiming a reopened id) runs before any later line.
- A line that is not a message gets the framing reply (-32700 / -32600) the
  SDK sends; reading goes on (test: "a line that is not JSON, or a batch,
  leaves the next prompt answered").
- A line past 32 MiB: `MessageTooLargeError`, nothing of the line kept,
  the connection is broken, the way out starts with `broken` (exit 1) and a
  stderr line `chord: the connection closed: ...`.
- `onDone` (EOF, including a half-close): the way out with `eof`.

### Writing

Dart's `stdout` is an `IOSink`: `add` buffers without bound, `flush` must
not overlap another `add` (a `StateError` "StreamSink is bound to a
stream"). So the server has exactly one writer:

- A FIFO of encoded lines and a loop: take everything queued, `add` it,
  `await flush()`, settle the written futures of those lines, repeat.
  Batching by flush keeps a flood from costing one flush per update.
- `expect(id)`: a future that settles once the answer line for that id has
  been flushed, or once nothing can be written any more. `connected`'s
  release (section 3.2) and the drain both hang on it.
- `drained()`: settles when every expected answer is written or the writer
  failed.
- A write error (EPIPE: Dart ignores SIGPIPE, so a closed pipe is an error
  on `flush` / `stdout.done`) marks `failed`, settles every expectation,
  and starts the way out with `broken`.
- Writes are fire-and-forget for their callers; a notification to a gone
  connection is dropped silently, as the original's `.catch(() => {})`.

The writer takes an injected `Sink`-like port (`add` + `flush` + `done`),
so tests run it on a controllable in-memory sink (pause, fail, measure),
and `bin/` gives it the real `stdout`.

### Back-pressure and the client that stops reading

As in the original's "Limits": the queue is unbounded and there is no
blocked-write timeout. A client that stops reading while connected holds
output in memory and keeps agents running until chord is signalled. Same
outcome; same wording goes in the port's guide.

**Difference D1, the malformed-line stall.** The original's SDK awaits the
write of a parse error before reading on, so a malformed line while stdout
is full stops input reading (its guide documents this as a limit). The
port's reader never awaits a write: the parse error is queued like any
other line and reading goes on. Options: (a) reproduce the stall by pausing
`stdin` until that reply is flushed; (b) do not, and say so in the port's
guide. Recommendation: (b); the stall is an artefact of the SDK, not a
behaviour any client relies on, and reproducing it adds a pause/resume path
that exists only to be worse. Owner decision, since the guide lists it.

## 3. Concurrency model (question 9)

Dart runs the whole server on one isolate's event loop. "Concurrent"
means interleaved at `await`s; every rule below is about what must happen
before the first `await` of a handler, and about the order of lines in the
one write queue.

### 3.1 Per-session state

Per entry (one per `session/new`, `load`, `resume`):

- `conversation`, `upstream` (the client's id and the agent's id, alias
  included), `live`, `held` (closures run once live), `past` (load only),
  `replaying`, `opening` (the pending new/load/resume completer and its
  request id), `turns` (the turn table), `stateSent`, `gone`, `closed`,
  `closing` (the close future), `account`, the open asks this entry has
  out with the client (see 3.6).

Server-wide: `sessions` (client id → entry, live only), `reopening`
(ids claimed by an in-flight load/resume), `entries` (every entry not
closed, starting and gone included, in start order: the account source is
the first qualifying one), `answers` (prompt request id → completer),
`asks` (ask id → withdrawal token), `capabilities` (set once by
`initialize`).

### 3.2 Ordering invariants

1. **No line names a session id before the client has it.** Events heard
   before the `session/new` answer is *written* are pushed to `held`;
   `connected` answers, and `expect(requestId)` releases `held` after the
   answer's flush. Asks (`permission_requested`) go through the same gate.
2. **A load's past goes ahead of its answer.** On `connected` with a past,
   the past is relayed (prompts as `user_message_chunk` via
   `messageChunk`, updates through the gating `mapUpdate`, renames as
   `session_info_update`), then the answer, then `held`.
3. **The command list after the answer.** `commandsIfNone` goes after the
   answer is written, and after a load's past. (No chord commands in this
   scope, see 9.3.)
4. **A turn's updates before its answer.** The answer is enqueued when the
   turn's `ResultAction` is heard, which `Conversation` emits after the
   turn's updates; same queue, so same order on the wire. Updates that come
   after the result go at once (the original's "Updates after a prompt's
   answer go immediately"): no holding for silence.
5. **State after what caused it.** `_chord/session/state` is computed after
   each event's handling (`tellState` at the end of `heard`) and sent only
   on change; never after `closed`, never before `live`.
6. **Bind before send.** `session/prompt` binds `requestId → turnId` in the
   turn table, with no `await` between the request's arrival and
   `conversation.send(turnId: ...)`. Needs the caller-chosen turn id seam.
7. **Claim before await.** `load`/`resume` add the id to `reopening`
   before their first `await` (reading records), so a second load of the
   same id is -32602 "already open here" even while the first is reading.
   A new session's id is aliased against `sessions ∪ reopening`.

### 3.3 The prompt queue

The queue is `Conversation`'s own (the window's), not a second one in the
server. A `session/prompt` while a turn runs is queued by
`Conversation.send`; its request stays unanswered until its own
`ResultAction`. Turns nobody prompted (an agent cycle, CTUI-58; a
self-started turn) run with `origin: agent` and answer nothing; a
client prompt that takes over a cycle gets the cycle's place, as in
`reduceTurns`' `prompt` case.

### 3.4 Cancellation matrix

| Input | Target state | Outcome |
| --- | --- | --- |
| `session/cancel` | turn running, prompts queued | `Conversation.interrupt()`: `QueueWithdrawn` answers every queued bound prompt `{stopReason: cancelled}`; the running turn's own result (normally `cancelled`) answers its request. Each request answered once. |
| `session/cancel` | idle, agent cycle running | `interrupt` cancels the cycle; no request to answer. |
| `session/cancel` | ask open with the client | the conversation settles the permission as cancelled; `permission_settled` withdraws the client ask (`$/cancel_request` to the client); a late client answer finds nothing. |
| `session/cancel` | unknown id | ignored (notification, no answer). Children's routing is the seam (`cancelledIn`). |
| `$/cancel_request` | queued prompt | `cancelPrompt(turnId)` → `QueueWithdrawn([that])` → that request alone answers `cancelled`. Others stay queued. |
| `$/cancel_request` | running prompt | `cancelPrompt(turnId)` cancels the running turn as `interrupt` does, queue untouched; its result answers it. |
| `$/cancel_request` | prompt that arrived already cancelled | the original answers `cancelled` at once. In the port the cancel cannot precede its request's dispatch (in-order dispatch), so this case reduces to the two rows above; kept as a guard. |
| `$/cancel_request` | answered request | nothing ("a cancel of a request already answered changes nothing"). |
| `$/cancel_request` | `session/new`/`load`/`resume` in flight | if still reading place/records: nothing starts, -32800; if starting: the entry is closed (its group stopped) then -32800, and a reopen's id is given back. |
| `$/cancel_request` | `set_config_option`, `set_mode`, `set_title`, `list`, `close` | ignored; answered normally (the SDK only aborts the handler's signal, which these handlers do not read). |
| `$/cancel_request` | steer | nothing to cancel: `steer` answers synchronously. |
| connection end (EOF/broken) | any | not a client cancel: tokens fire with the connection, and the prompt handler must not call `cancelPrompt` for it (the original checks `connection.signal.aborted`); the way out's session close tells the agent `cancelled`. |

**An agent that ignores cancel.** No timer, as the original: the prompt
stays pending (test "an agent that ignores a cancel: open, no timer, until
session/close"). `session/close` answers it `cancelled` through the turn
table's `closing` step, then closes the conversation, whose stop ladder
(stdin end, SIGTERM, SIGKILL; 2 s each, `StopBounds`) ends the agent.

### 3.5 Steer and state (owner: in scope)

`_chord/session/steer {sessionId, prompt}`:

1. Parse blocks (`promptOf`): -32602 on refusal; -32002 unknown/closed;
   -32603 while leaving.
2. `step(steered, turnId)` *before* `send`, then
   `conversation.send(..., turnId: turnId)`; a refused send is `unbind`
   and -32002.
3. `conversation.steerQueued(turnId)` (the seam): `sent` → `{delivery:
   sent}`; anything else → `{delivery: queued}`. A queued steer later runs
   as its own turn, `origin: client`, no request bound, no echo (the
   steered set in the turn table suppresses the `message` send). A steer
   refused by the agent goes back to its place in the queue (`Queued`
   with `refused`), and is never answered twice (U4 test "a steer refused
   after cancellation runs as its own client turn and answers only once").
4. A steer held by an ask between turns waits for that answer (U4 "a held
   ask delays its named steer until the permission is answered"); this is
   `Conversation`'s existing `afterAnswer` rule.

`_chord/session/state`: from `sessionStateOf(turns, asking)` where
`asking` is main's open-ask count > 0 (`host_fold`). Rules from the guide
and the U3 tests: idle has no origin; `requires_action` keeps the origin;
an exiting main reports idle without waiting for close; nothing after a
close; a load says nothing (its replay runs nothing).

### 3.6 Asks

- One table of asks out with the client, keyed by the conversation's ask
  id, each with a withdrawal token. A client answer settles once; an error
  answer is a refusal (permissions: reject; forms: cancel) with a stderr
  line; a late answer after withdrawal finds nothing.
- **Difference D2, how a close withdraws asks.** The original's host keeps
  telling a closing main's events (`closingHeard`) so `permission_settled`
  withdraws the client's ask. The port's `Conversation.close` delivers
  nothing after `Closing`. The server therefore withdraws every ask of an
  entry itself when it closes it (and the agent side is answered
  `cancelled` by `AgentRequests`' closing token, as today). Same wire as
  the original; no owner question unless a test shows a difference.
- Asks between turns can hold the queue until `session/cancel`; chord
  neither times them out nor answers for the client (guide "Limits").
  Ordinary permissions have no timeout; `_meta["chord/permission"].deadlineAt`
  is only relayed.
- Plan approvals: see D3 in section 9.

### 3.7 Account source

`auth/status` reads the first entry in `entries` that is not gone, not
closing and has a session. `tellAccount` runs on every account event, on
`disconnected`, and when a close finishes, and sends
`auth/status_update` only when the value changed by deep equality
(key-order independent: compare canonical JSON with sorted keys). A retired
or exited session's late account event never replaces the live source
(CHD-629 tester tests). Children are never a source (seam: entries hold
mains only).

### 3.8 Settings and requests that change a live session

`set_config_option`, `set_mode` and `set_title` go through
`Conversation`'s own change chain (`_change`), so two concurrent sets on
one session are applied in arrival order, and the answer reads the state
after its own change. A set for an option the agent refuses returns the
agent's error unchanged (`refusal`). Mode/model `failed` events whose turn
id starts with `mode-`/`model-` are that request's error, not a `notice`.

## 4. Shutdown and exit codes (question 10)

### 4.1 Triggers

| Trigger | Detected by | Reason | Answers first? | Exit |
| --- | --- | --- | --- | --- |
| stdin EOF / half-close | reader `onDone` | `eof` | no (client gone) | 0 if every step clean, else 1 |
| stdout write fails | writer `failed` | `broken` | no | 1 |
| line over 32 MiB | `MessageTooLargeError` | `broken` | no | 1 |
| uncaught error | `runZonedGuarded` in `bin/` | `crash` | yes | 1 |
| SIGINT, SIGTERM, SIGHUP | `ProcessSignal.watch` | `signal` | yes | dies by that signal |
| second trigger | `leaving.started()` | joins the first | - | the first's |

stderr is written with errors swallowed (a stderr gone does not stop
anything), as the original's `say`.

### 4.2 Sequence (`createLeaving`, as `leaving.ts`)

1. `started()` holds from the first call: every request after it is -32603
   `chord is closing` (test "a request while closing is -32603").
2. Arm the deadline first (15 s, `leaveMs`).
3. On `signal`/`crash` only, `answer()`: withdraw every client ask;
   for each entry `expect` its bound prompt ids and step `closing` (each
   answered `cancelled`), reject a pending opening with -32603 after
   `expect`ing it.
4. Start, in the same tick, the connection step (wait `drained()` at most
   500 ms, `drainMs`; then close the wire: stop reading, close stdout) and
   one step per entry (`closeEntry`: `Conversation.close()`, which runs the
   stop ladder and flushes the record). A failing or hung step holds up
   none of the others; each failure is a stderr line `chord: <name>: ...`.
5. All settled: `ProcessGroups.killAll()` (groups left by an agent's
   children), then exit by the reason.
6. Deadline first: `chord: not settled at the deadline: <names>`, kill all
   groups with a line `chord: killed process group <pid>` each, exit as
   unclean (EOF → 1; a signal still dies by its signal).

Why 15 s: one agent stops within 6 s (2+2+2); the original budgets a hung
task and a hung main as 12 s. In this scope there are no tasks, so 6 s
plus record flush is the expected worst case; keep 15 s as the original.

### 4.3 Dart specifics

- `exit(code)` does not flush `stdout`. The connection step's drain is the
  only flush; after it (or its 500 ms) the writer is closed, and `exit`
  follows. Lines still queued after 500 ms are lost, as the guide says.
- Dying by a signal: cancel the watch subscriptions (Dart then restores the
  default disposition) and `Process.killPid(pid, signal)`; the existing
  `raiseSignal` falls back to `exit(128 + n)` after 500 ms. Reuse it, moved
  to `platform/signals.dart`.
- SIGPIPE is ignored by the Dart VM: a closed stdout is an `EPIPE` error on
  flush, which is `broken`. No signal handling needed for it.
- A synchronous loop (a huge JSON decode, a catastrophic regex) delays
  every trigger including the deadline timer; that is the guide's "event
  loop blocking synchronously" non-guarantee, same as the original.
- What holds, as the original: on every way out that runs, each process
  group chord spawned has stopped or been sent SIGKILL. Not: chord itself
  SIGKILLed, a process leaving its group, pid reuse.

### 4.4 How each is tested

- `createLeaving` alone, under `fake_async`: each reason's exit; the
  deadline with a hung step names it and kills groups (an injected
  `ProcessGroups`); drain bounded at 500 ms with a never-flushing sink;
  `answer()` only for signal/crash; a second `leave` joins; a failing step
  makes EOF exit 1.
- `runAcp` in memory: EOF idle exit 0; EOF with an ask open (no answer,
  the agent hears cancelled); a signal with an ask open (withdrawn, then
  the prompt `cancelled`); a signal in a turn (`cancelled` first, then the
  exit); a request while closing -32603; a 32 MiB + 1 line → exit 1, the
  stderr line; a sink that fails → exit 1.
- Compiled binary (tag `compile`): SIGINT, SIGTERM and SIGHUP each end
  `chord acp` by that signal with no process group of its agents left
  (the fake through bun, group pids read from the fake's own output and
  probed with `kill -0`); EOF exit 0; closing the read end of stdout →
  exit 1; `chord acp --nope` exit 2, empty stdout, the stderr line.

## 5. Load and resume (question 11)

1. `refuseIfClosing`; id in `sessions` or `reopening` → -32602
   `Session <id> is already open here.` (its running turn still answers).
2. Claim the id in `reopening` (before any `await`).
3. `readRecords(stateDir)` (already off the main isolate through the
   record worker) → `sessionById(..., agent, cwd)`; `ResumeError` → -32602;
   a different `cwd` → -32602 `Session <id> is in <cwd>.`
4. `placed(params)`: refuse an `acp` MCP transport (-32602), read the
   `cwd`'s settings and `.mcp.json` (startup agent fixed; settings'
   `refused` → -32603), merge client servers over settings by name;
   cancelled meanwhile → -32800, nothing started.
5. Open the entry with `resume: {from, replays}`. On `connected`: load
   relays its past then answers; resume answers with nothing replayed. A
   pending rename in the record (`renamed` with `pending: true`, written by
   `set_title` on an unloaded session) is sent to the agent on this open
   where the agent takes titles; a hung rename leaves load and prompts
   usable (CHD-629 tester test).
6. Release the claim in `finally`, whether it opened, failed or was
   cancelled ("a reopen cancelled / that fails gives its id back").

**Records from two processes.** Two `chord acp` (or a window and a server)
can open and append to the same record; the guide says so and there is no
lock. Each batch is one `FileMode.append` write; on a local file system
with `O_APPEND` each write lands whole at the end, so lines may interleave
between processes but not tear. Same as the original's `appendFile`. No
new record version (CTUI-26).

**Unwritable record.** A record that cannot be written: stderr and a
`notice` (to a client declaring `session.notices`), and the session goes
on (original test "a record that cannot be written").

**Settings per `cwd`.** Read per `session/new`/`load`/`resume`, not cached
(a client may edit them between sessions); a problem in the user's file is
said once per process, as `serveAcp`'s `problems` list.

## 6. Failure scenarios and expected outcomes

| Scenario | Expected |
| --- | --- |
| Agent command missing | `session/new` -32603 with `failureLines` in `data.lines`; chord lives; no group left. |
| Agent needs sign-in | -32000, ways in in `data` (`signInLines`). |
| Start hangs | `session/new` stays open; `$/cancel_request` closes the entry, -32800, no group left. |
| Agent exits in a turn | that prompt -32603 with its last words; the entry closes once the lost turn's result is in. |
| Agent exits with prompts queued | queued ones -32002 (`session_gone`, taken out of the queue), the running one its error. |
| Agent exits between turns | next prompt -32002; `session/resume` reopens the record. |
| Agent floods updates | each relayed, in order, one queue; memory grows with a slow client (documented limit); other sessions' answers interleave by arrival, no starvation of the loop beyond one chunk's dispatch. |
| Agent sends an ask under an unannounced session id | refused, stderr line, never shown. |
| Duplicate agent id across sessions | upstream-only alias `s1~2`; both route; not listed, not reloadable. |
| Two loads of one id at once | the second -32602 while the first reads. |
| Client answers an ask with an error | refusal (permission) / cancel (form), stderr line. |
| Client never answers an ask | the turn waits; `session/cancel` or close withdraws it. |
| Client stops reading | unbounded queue, agents keep running until a signal (documented). |
| stdout closed | `broken`, exit 1. |
| stdin closed mid-turn | `eof`: no answer to the running prompt; sessions closed; exit 0 if clean. |
| Crash in a handler | async errors inside a handler become that request's -32603; an error escaping to the zone is `crash`: prompts `cancelled`, asks withdrawn, exit 1, stack on stderr. |
| Record worker isolate fails | the record write fails as today: stderr + notice, the session goes on. |

## 7. Performance and memory

- **Memory per session.** The port's `Conversation` does not keep the
  window's transcript; the server keeps no transcript either, only the turn
  table, the open-ask set and the `upstream` mapping state (announced
  subagent ids, last config sent). The original's guide says its per-session
  fold is unmeasured; the port's is smaller by construction. The benchmark
  measures it.
- **One event loop.** JSON decode of a large line (an embedded resource,
  up to 32 MiB) and encode of a large replay run on the main isolate and
  delay every session for that time. Recommendation: no isolate at first
  (it would need an order-preserving decode queue, as a later small line
  must not overtake a big one); the benchmark measures a 32 MiB prompt
  line and a load of a large record, and an isolate is added only if the
  stall shows up (a decision then, logged).
- **Writer batching.** One flush per batch, not per line.
- **Benchmark** `example/chord/benchmark/acp_server.dart`, no terminal:
  (a) N in-memory sessions × M updates each to a counting sink: lines/s,
  peak RSS, time to the last answer; (b) one 32 MiB prompt line: dispatch
  latency of a ping on another session; (c) load of a 10k-update record:
  time to answer. Report numbers in the handover; no thresholds in tests.

## 8. Tests (question 12)

Three layers, as AGENTS.md: pure modules directly, the server through
in-memory processes and the original's fake, the binary in a pty only for
what needs a real process.

**Pure (no IO, fast):**

- `acp/upstream_turns_test.dart`: the original's reducer tests plus the
  U2 steered-turn tests (`acp_extensions_test.ts`).
- `acp/host_fold_test.dart`: open asks → `requires_action`.
- `acp/stdio_test.dart`: framing replies, 32 MiB cap (exact boundary),
  FIFO order, `expect`/`drained`/`failed` on an in-memory sink that can
  hold or fail a flush, batching.
- `acp/agent_app_test.dart`: -32600/-32601/-32602 shapes, a token per
  request, `$/cancel_request` by id (`1` vs `"1"`), notifications have no
  answer, unknown extension method -32601.
- `session/leaving_test.dart` under `fake_async` (section 4.4).
- `session/upstream_test.dart`: gating table, alias, config, prompt blocks
  (owned with interface).

**`runAcp` in memory** (`acp_agent_test.dart`): stdin/stdout as
`StreamController`s, the client as a small JSON-RPC driver, the agent as
`MemoryAgentProcess` with scripted ACP (the port's `test/acp` style), so
ordering is deterministic: initialize starts no agent; the gate (no line
with a session id before its answer; past before the load answer); bind
before send; the cancel matrix rows; steer `sent`/`queued`, own entry, no
echo, refused-once; state transitions; account source and dedup; alias;
already-open; reopen claims; asks withdrawn on close; every way-out row
of 4.4.

**Through the original's fake** (`acp_agent_fake_test.dart`, run by
default, skipped with a reason without bun or the checkout, via
`test/fixtures/fake.dart`): a whole turn; tool calls whole; cancel with a
queue; `$/cancel_request` on a queued prompt; ignored cancel until close;
permissions (`permissions`, `review_permissions` scenarios); config and
modes (`modes`); titles and pending renames (`titles`); accounts
(`accounts`); notices (`notices`); resources (`resources`, `links`);
agent dying in a turn / with a queue (`misbehaving`); failed start and
sign-in (the port's `fake_agent_auth_required` fixture); a hanging start
(`gatedCommand`); records: a session recorded as the window records it,
listed, loaded with its past, resumed without, by a window record too.
Records live under an isolated `XDG_STATE_HOME`. No new fake scenario is
needed for this scope as far as I can see; the original's tests use only
existing ones.

**Compiled, in a pty or with pipes** (`cli_acp_compile_test.dart`, tag
`compile`, run explicitly): the signal rows, EOF, broken stdout, `--nope`,
`byHandNote` shown only with a terminal on stdin (pty) and absent with a
pipe, and no stdout byte that is not a JSON line (OpenTUI-like terminal
queries must not leak: the server path must not construct a terminal).

**Not tested anywhere:** a real model, agent or terminal.

## 9. Differences from the original and seams

### 9.1 Differences (each needs the owner, with a recommendation)

- **D1 malformed-line stall** (section 2): recommend not reproducing it.
- **D2 close withdraws asks from the server** (section 3.6): no wire
  difference intended; a lead decision, not the owner's, unless a test
  shows a visible difference.
- **D3 plan approvals.** The original relays chord's plan asks
  (`askPlan`, `plan_requested`) as `session/request_permission`. The port
  has no plan-approval flow: `AgentRequests` answers `cursor/create_plan`
  and `x.ai/exit_plan_mode` `cancelled`, and the window shows none.
  Options: (a) keep the port's `cancelled` in `chord acp` too, and relay
  plans when the window gains them; (b) build the plan-approval flow in
  `Conversation` within this task. Recommendation: (a), since the port's
  two interfaces then agree and the flow is a window feature first; the
  guide row "calls `session/request_permission` for ... plan approvals"
  becomes a known gap in FEATURES.md.
- **D4 elicitation** (interface's question 7): runtime note only. If
  relayed, it is one more kind in the ask table with the same withdrawal
  and error rules, and `elicitation/complete` is a plain notification
  through the writer; if not relayed, the agent side keeps answering
  `cancel` as today. Either way no new run-time machinery.
- **D5 account status.** The port's `Session` reads no account state. The
  guide's `auth/status` / `auth/status_update` need it. Options: (a) build
  `AccountState` on `Session` in this task (a unit, U6 below); (b) answer
  `unknown` always and advertise `auth.status`, deferring the reading.
  Recommendation: (a); it is part of the spec and small, and the fake has an
  `accounts` scenario to test it.

### 9.2 Seams for M4/M5 (children, teams, monitors)

- `Entry` holds main's conversation and a `routes` map left empty; the
  `heard` dispatch has a `childHeard` branch point.
- `session/cancel` falls through to `cancelledIn(entry, id)`, returning
  false in this scope.
- `askPermission`/`askElicitation` take an `Asker` (conversation +
  upstream) so a child's asks plug in; the `subagents` refusal path exists
  already for a main's nested subagent asks.
- `closeEntry` closes a host's sessions in parallel; in this scope the host
  is main alone; `closeRuntimes`/`tellClosed` come with children.
- The way out's `steps` list takes more steps (chord's MCP server, resource
  readers) without changing `createLeaving`.
- Command interception (`commandOf`) is a hook that returns "not a
  command" for everything in this scope.

### 9.3 Other notes

- `--no-mcp-servers` and `mcpServers: false` hold back settings servers,
  chord's own included; with no chord MCP server in the port yet, nothing
  more to hold back.
- `dimcode` notice (`tellDimcode`): whatever the window does in the port
  today, the server mirrors; interface to confirm.

## 10. Build units for ship, in order (question 13)

Each unit is one branch-sized commit set with its tests; later units
depend on earlier ones.

1. **U1 Way-out core.** `createLeaving` in `session/leaving.dart`;
   `dieBySignal`/`raiseSignal` moved to `platform/signals.dart` (window
   imports updated, its tests unchanged). Tests: `leaving_test.dart`
   (fake_async), `signals_test.dart`.
2. **U2 Server wire and dispatcher.** `acp/stdio.dart` (`ServerWire`),
   `acp/agent_app.dart` with initialize, -32601 for the rest. Tests:
   `stdio_test.dart`, `agent_app_test.dart`.
3. **U3 Turn table and fold.** `acp/upstream_turns.dart`,
   `acp/host_fold.dart`. Tests: pure, including the U2 steered tests.
4. **U4 Conversation seams.** Caller-chosen `turnId` on `send`, links,
   resources and attachments on `send`, `steerQueued(turnId)`,
   `rename(title)` and the pending-rename send on resume; the ACP past
   reader for load (raw prompt/update/renamed). Tests in
   `test/session/conversation*_test.dart`, `replay_test.dart`; the window's
   tests stay green.
5. **U5 `upstream.dart` mapping.** Gating, aliases, config answer/change,
   prompt blocks, permission/elicitation answers. Pure tests (contract from
   interface).
6. **U6 Account state.** `AccountState` on `Session` and its event. Tests
   against the fake's `accounts` scenario. (Skip if the owner picks D5 (b).)
7. **U7 `runAcp`: sessions and turns.** new/list/prompt/cancel/close,
   the gate, held, aliases, asks, state, steer, config/mode/title,
   auth/status, failed starts, an agent that dies, way out wired to the
   entries. Tests: `acp_agent_test.dart` in memory; `acp_agent_fake_test.dart`.
8. **U8 Load and resume.** Reopen claims, past before answer, pending
   renames, already-open, records shared with the window. Tests in memory
   and through the fake with isolated state.
9. **U9 CLI and binary.** `chord acp` parsing, `byHandNote`, real stdio,
   signals, crash zone, exit; `--nope` exit 2. Tests: `cli_acp_test.dart`,
   `cli_acp_compile_test.dart` (tag `compile`); AGENTS.md command list and
   the port's guide/FEATURES rows.
10. **U10 Benchmark.** `benchmark/acp_server.dart`, numbers in the
    handover; an isolate decision only if numbers call for it.

U1 to U3 and U5 are independent of each other and can go in parallel; U4
before U7; U6 before U7's `auth/status` tests (or U7 answers `unknown`
until U6 lands).

## 11. Owner decisions

1. D1: reproduce the original's malformed-line stall, or not (recommend
   not, documented).
2. D3: plan approvals in `chord acp`: `cancelled` as the port's window
   does today (recommend), or build plan approval in this task.
3. D5: build account status now (recommend) or answer `unknown`.
4. (Interface's) D4 elicitation relay.

## 12. Open questions for the other architects

- framework: whether the serving dispatcher shares code with `rpc.dart`'s
  `AgentRequests` (same envelope checks and error shapes) or is its own
  class; the run time needs only "a token per incoming id, in-order
  synchronous dispatch, one writer".
- framework: the ACP past reader for load: a new function in `replay.dart`
  or `record.dart` (raw events, no transcript fold).
- interface: confirm the server answers `$/cancel_request` on non-prompt
  methods normally (SDK behaviour: only the handler's signal is aborted).
- interface: `dimcode` notice in the port.
