# CTUI-12: the port's ACP client

The design the ship team builds. The record of how it was reached is in
`docs/design/evidence/CTUI-12/drafts/` (the brief, the framework, interface
and runtime drafts; runtime's was revised once after the critic). Where this
file and a draft disagree, this file wins. The decisions are logged in
`docs/decisions.md`.

## What it is for

chord's own ACP layer (`../chord/src/acp/`, on `@agentclientprotocol/sdk`
2.6.0, its `unstable` entry) in Dart, kept to what M0 and M1 need: start an
agent in a process group of its own, talk JSON-RPC 2.0 to it over its stdio,
`initialize`, `session/new`, `session/prompt`, `session/cancel`, the
`session/update`s M1 draws, `session/request_permission`, and the agent
exiting, closing its stdout, or hanging. Every later milestone stands on it.

It is the port's, under `example/chord/lib/acp/` and
`example/chord/lib/platform/`, with tests at the same paths under
`example/chord/test/`. `lib/` (the framework) knows nothing of it. It draws
nothing: the screens that read it (the session layer, CTUI-15; the
transcript, permission prompt and errors, M1) are their own tasks, and the
contract they need is below.

Out of this task, and where each lands: `session/load`, `resume`, `list`,
`fork`, `set_title`, `auth/status`, `set_mode`, `set_model`,
`set_config_option`, `_session/steering` (M2); elicitation UI, cursor's and
grok's plan UI, id-addressed plans, compaction, notices, subagents (M3);
`chord acp`, `agent_app.ts`, `stdio.ts`, `upstream_turns.ts`, `host_fold.ts`
and relays (M2 headless, M4); the session record's format (its own task).
Each is a new request method, handler, view or capability on the shape
below, not a change to it.

## Files

| File | Holds |
| --- | --- |
| `lib/platform/process.dart` | `spawnGroup`, `GroupProcess` (pid, stdio, `started`, `exit`, `signal`, `alive`), `Exit`, `ProcessGroups` with `killAll()` |
| `lib/platform/group_exec.dart` | the launcher: `groupExecFlag`, `Never groupExec(List<String> args)`, and a `main` for the JIT path |
| `lib/acp/process.dart` | `commandArgv`, `spawnAgent`, `AgentProcess`, `StopBounds`, `AgentExitError`, `settledWithin`, `StderrTail`, the original's constants |
| `lib/acp/wire.dart` | framing: bytes to messages and back, the SDK's errors |
| `lib/acp/rpc.dart` | chord's requests through `json_rpc_2`'s `Client`; the dispatcher for the agent's requests |
| `lib/acp/traffic.dart` | `Traffic` and the tap |
| `lib/acp/schema.dart` | the extension-type views over ACP's messages |
| `lib/acp/connection.dart` | `openAgent`, `connectAgent`, `Agent`, `clientCapabilities`, `AgentGone`, `Waiting`, the writer |
| `bin/chord.dart` | gains one first statement: the launcher's flag |

`pubspec.yaml` gains `json_rpc_2`, `stream_channel` and
`cancellation_token`; `fake_async` under dev dependencies.

## The call site

What the session layer (CTUI-15) writes. `SessionInbox` and
`PermissionBridge` are the session layer's, specified by the original's
`session/session.ts` and `session/permissions.ts`; they are shown to fix
the contract, not built here.

```dart
final permissions = PermissionBridge();
final inbox = SessionInbox(); // early updates, exact-id routing
final opening = CancellationToken();
final agent = await openAgent(
  command: start.command,       // String (split as below) or List<String>
  env: start.env,               // laid over chord's environment
  cwd: directory,
  capabilities: clientCapabilities(), // empty in M0/M1
  onTraffic: (traffic) {        // the one ingress; must not throw
    record.add(traffic);
    inbox.hear(traffic);
  },
  onPermission: permissions.handle, // (request, token) -> Future<response>
  cancellationToken: opening,
);
try {
  final opened = await agent.newSession(
    NewSessionRequest(cwd: directory, mcpServers: const []),
  );
  inbox.open(opened.sessionId, opened); // the answer first, then the buffer
  final unsubscribe = inbox.subscribe(conversation.fold);
  final result = await agent.prompt(PromptRequest(
    sessionId: opened.sessionId,
    prompt: [ContentBlock.text(draft)],
  ));
  conversation.finish(result.stopReason);
  // the interrupt action, meanwhile: agent.cancel(opened.sessionId)
  unsubscribe();
} finally {
  await agent.close();
}
```

## The surface

```dart
/// A running agent and its ACP connection, initialised, until [close].
abstract interface class Agent {
  int get pid;
  /// The agent's whole answer to `initialize`, `_meta` included.
  InitializeResponse get init;
  /// Settles once the exit is seen and its last stderr has come, or 500 ms passed.
  Future<Exit> get exited;
  /// Null while connected; once stdout has ended, the end of its stderr, possibly empty.
  String? gone();
  Future<NewSessionResponse> newSession(NewSessionRequest request,
      {CancellationToken? cancellationToken});
  Future<PromptResponse> prompt(PromptRequest request,
      {CancellationToken? cancellationToken});
  /// Answers this session's waiting requests `cancelled`, then queues `session/cancel`.
  Future<void> cancel(String sessionId);
  /// Idempotent; throws [AgentExitError] when even SIGKILL's exit is not seen.
  Future<void> close();
}

Future<Agent> openAgent({
  required Object command,                 // String or List<String>
  Map<String, String>? env,
  required String cwd,
  required void Function(Traffic) onTraffic,
  required Future<RequestPermissionResponse> Function(
      RequestPermissionRequest, CancellationToken) onPermission,
  ClientCapabilities? capabilities,         // clientCapabilities() by default
  CancellationToken? cancellationToken,     // gives up on a start
  StopBounds stop = const StopBounds(),
  Relay? relay,                             // amended by CTUI-15: the enricher chain
});
```

`openAgent` rejects, with the agent stopped, when it cannot start, will not
initialise, or the token is cancelled first. `connectAgent(AgentProcess,
…)` is the same over a process already started, so tests drive the pipes
in any order, as the original's.

### One ingress for updates

> Amended by CTUI-15 (`docs/design/CTUI-15.md`, "Enrichers on the
> transport"): `openAgent` and `connectAgent` take an optional `relay`, run
> on each decoded message from the agent before the tap and routing, and on
> each of chord's before the tap and the writer, failing open per message.
> With no relay everything below holds unchanged; with one, `onTraffic`,
> the router and `onPermission` see the relay's output.

There is no `updates` stream. Every message either way, and stderr text,
reaches `onTraffic` as `Traffic.agent(map)`, `Traffic.chord(map)` or
`Traffic.stderr(text)`, in wire order, before routing: an update sent
before a reply reaches `onTraffic` before the reply's future completes.
Agents send updates before `session/new` answers and after a prompt
answers, so a stream attached after `openAgent` returns would lose them,
and a stream beside the tap would fold them twice. The session layer
(CTUI-15) owns the buffer before the session id is known, routing by exact
session id, seeding the `session/new` answer before buffered updates, and
holding updates until its first subscriber, as `session/session.ts` does.

`onTraffic` must not throw. The connection calls it inside a `try`; a throw
is caught and dropped and the message is still routed, so a reducer bug
cannot kill the pipe's listener; a test holds that. The session layer catches per
update in its reducer, so one malformed update draws nothing and the next
still draws.

### Permissions

`onPermission(request, token)` returns the answer. The connection owns the
request's id and exactly one answer on the wire; the bridge owns what the
screen shows.

- The handler gets a token merged from the request's own (the agent's
  `$/cancel_request`), its session's turn (`cancel(sessionId)`) and the
  connection's closing. It checks `isCancelled` before publishing, since the
  token may already be cancelled.
- The first of three wins: the handler's answer, its failure (answered with
  the fallback), or the token's cancellation (the fallback, enqueued
  synchronously in the token's `onCancel`). A late result is dropped. The
  fallback is `{"outcome": {"outcome": "cancelled"}}`, sent as a result,
  as the original's `answer()` does.
- Before sending a `selected` answer the connection checks its `optionId`
  is one of the request's options; one that is not is answered with the
  fallback, so a wrong handler cannot put a bad answer on the
  wire.
- Two requests at once, for one tool call too, stay distinct; the screen
  shows the oldest first (interface draft, I1).

### The agent's requests, and what each is answered

| Method | Answer in M0/M1 |
| --- | --- |
| `session/request_permission` | `onPermission`; fallback `{"outcome": {"outcome": "cancelled"}}` |
| `elicitation/create` | `{"action": "cancel"}` at once (elicitation is not declared; the original cancels a mode it does not draw) |
| `cursor/create_plan`, `x.ai/exit_plan_mode` | `{"outcome": "cancelled"}` at once, never -32601, which cursor reads as accepted (`plans.ts`) |
| `fs/*`, `terminal/*` | -32601, neither is declared (O1, decided) |
| anything else | -32601 |
| a request after closing began | its fallback if it has one, else -32601, if the sink is still open |

A request from the agent is checked at the edge for the fields the port
reads (`sessionId`, `toolCall.toolCallId`, `options[].optionId`, `name`,
`kind`); one that fails is answered -32602, as the SDK's schema check does.

## The wire

### Framing, as the SDK's `ndJsonStream`

- In: bytes split on `0x0A`, a trailing `\r` trimmed, empty lines skipped, a
  final line without a newline taken at EOF; UTF-8 decoded with malformed
  bytes as U+FFFD; `jsonDecode`.
- A line over 32 MiB (`DEFAULT_MAX_MESSAGE_BYTES`) fails the connection
  with `MessageTooLargeError`, as the SDK does; nothing of it is kept.
- Bad JSON is answered -32700 with `id: null`; a JSON array -32600 "JSON-RPC
  batches are not supported"; any other non-object -32600. None of these,
  nor their replies, reaches the tap, as in the original.
- Out: one `jsonEncode(message) + '\n'` per message through the writer.

### JSON-RPC: `json_rpc_2` for chord's requests, our dispatcher for the agent's

The owner chose this (Q1, option B). `json_rpc_2` 4.1.0's `Peer` never
gives a handler its request's id, so `$/cancel_request` could not withdraw a
permission through it.

- **chord's requests**: `json_rpc_2`'s `Client.withoutJson` over a
  `StreamChannel` the router feeds responses to. It keeps ids, the pending
  map, error decoding, and fails every pending request when the channel
  closes. A caller's token races the future, as the original's `ask()`
  does; chord never sends `$/cancel_request` itself. A late answer is
  tapped and dropped. A request whose token is already cancelled is never
  sent.
- **The router**, below both, on each decoded message from the agent after
  the tap: `id` and `result`/`error` → the client; `id` and `method` → the
  dispatcher; a notification → `$/cancel_request` to the dispatcher, all
  others (updates included) to the traffic alone.
- **The dispatcher** (ours, about a hundred lines): a handler per method
  from the table above; -32601, -32602 and -32600 as the SDK answers them;
  each running request kept under the agent's id with its token.
  - The agent's ids and chord's are separate maps; an id is matched by
    value and JSON type, so `1` and `"1"` are different requests, as in
    JSON-RPC.
  - `$/cancel_request {requestId}` cancels that request's token; an
    unknown id or one already answered is ignored.
  - One settlement gate per request: the first of answer, failure, cancel
    or close writes, the rest do nothing.

### The types: views over the decoded maps

None of the Dart ACP packages fits (see decisions), and the schema did not
generate under the one generator that reads it. The wire stays
`Map<String, Object?>`; `schema.dart` holds hand-written Dart 3 extension
types over those maps for the about thirty types M0/M1 read or write
(framework draft, F2, lists them).

```dart
/// One `session/update`'s `update`, any kind.
extension type const SessionUpdate._(Map<String, Object?> _json) {
  String get kind => _json['sessionUpdate'] as String;
}
```

- The representation is library-private (`_json`), so outside `schema.dart`
  a view is read-only; `Traffic` carries the same decoded map, and nobody
  mutates it.
- A kind is dispatched on its string, `switch (update.kind)`, never by a
  runtime type test, since extension types are erased.
- Enum values are strings with named constants (`StopReason.endTurn`), so an
  unknown value is still a value; unknown kinds and fields are kept by
  construction and reach the traffic.
- A getter casts; a field of the wrong type throws `TypeError` at the read.
  Requests from the agent are checked at the edge (above); updates are not
  checked on arrival, as in the original, and the reducer's per-update catch
  is the boundary.
- Tests: each view against the JSON of the original's fixtures and fake
  agent, and a semantic round trip (every field, unknown ones and `_meta`
  included, survives decode and encode); not a byte-exact one, since
  whitespace, escapes and number spelling do not survive `jsonDecode`.

### `initialize` and the protocol version

`initialize` sends `protocolVersion: 1`, `clientCapabilities()` and
`clientInfo: {name: "chord", version: <the port's version>}`. The version
the agent answers is kept in `init` and not acted on, as in the original;
an agent refusing with -32022 fails the start with its message.

### Client capabilities in M0/M1: none

The owner chose to declare nothing until each capability's drawing exists
(Q3, option a). `clientCapabilities()` returns `{}` in M0/M1 and grows
with the task that draws each:

| Capability | What agents send while it is not declared | Declared by |
| --- | --- | --- |
| `plan: {}` | Codex sends its plan as reply text; other agents send the base `plan` update (entries), which needs no capability | the task that draws id-addressed plans (`plan_update`, `plan_removed`), M3 |
| `session.notices: {}` | Claude and Codex send notices as reply text, Claude's `info` ones included | the notices task, M3 (header, splash, notifications) |
| `session.compaction: {}` | a tool call without the summary | the compaction task, M3 |
| `subagents: {}` | Claude stamps children's work into the parent under its `_meta`; Codex sends none of it | the subagents task, M3 |
| `elicitation: {form: {}, url: {}}` | no forms or links; one that comes is cancelled | the elicitation forms task, M3 |
| `_meta.terminal_output_delta: true` | Claude, droid, autohand: command output as text; Codex and pi: output only under `_meta`, folded anyway (amended by CTUI-15) | the live command output task, M3 |
| `fs`, `terminal` | (never declared, O1) | none |

M1's plan checklist is the base `plan` update and does not depend on the
`plan` capability; Claude's adapter and the fake's `todos` send it
undeclared. What M1 loses is Codex's plan as a checklist: it arrives as
reply text until `plan: {}` is declared. That is part of the staged
difference the owner accepted.

## The process

### Its own group: the re-exec launcher

The owner chose this (Q2, option a). Dart cannot set a child's group:
`Process.start` has no `setsid`, `setpgid` from the parent is refused after
exec, and `detachedWithStdio` loses the exit code. chord starts itself as a
launcher that calls `setsid` and `execv` through `dart:ffi`, so the agent
keeps the pid `Process.start` returned, leads its own group and session,
and `Process` keeps its pipes and exit code.

```text
AOT:  <chord binary> --chord-group-exec <nonce> <path> -- <argv0> <args…>
JIT:  <dart> --packages=<package_config.json> <…/lib/platform/group_exec.dart>
          --chord-group-exec <nonce> <path> -- <argv0> <args…>
```

- `<chord binary>` and `<dart>` are `Platform.resolvedExecutable`; the
  path is chosen by `const bool.fromEnvironment('dart.vm.product')`, true
  exactly in `dart compile exe`'s code. `--packages` and the script are
  absolute (`Isolate.packageConfigSync`, `Isolate.resolvePackageUriSync`),
  so the current directory does not matter.
- `<path>` is the program resolved before the launch, against the agent's
  cwd if it has a `/`, else on the agent's `PATH` (chord's env with the
  agent's over it) with `process_run`'s lookup. A missing or non-executable
  program rejects with `cannot start <program>: <reason>` and nothing is
  started. `argv0` is the program as written; everything after `--` is
  passed to `execv` untouched.
- `bin/chord.dart`'s first statement consumes the flag, before arguments,
  settings or the terminal. A malformed launcher call prints one line and
  exits 126.
- The launcher, in order: `signal(SIGPIPE, SIG_DFL)` (Dart's children inherit
  it ignored, node's do not); `setsid()`; the frame `chord-exec <nonce> ok`
  on fd 2 with libc `write`; `execv`. A failure writes `chord-exec <nonce>
  fail setsid|exec <errno>` and exits 126, or 127 for ENOENT.
- `started` resolves on the `ok` frame: the group exists. A `fail` frame, or
  stderr or the process ending before `ok`, rejects. The nonce is fresh per
  spawn and only in the launcher's argv, which `execv` replaces, so the
  agent cannot forge a frame; only the first line and a `fail exec` right
  after it are read as frames. No exit code is read as a start failure.
- `signal(name)` is `kill(-pid)`, then `kill(pid)` on ESRCH, so a stop before
  `setsid` reaches the launcher, and the sweep after the exit catches what a
  race left in the group.
- Measured: 12 ms launch to handshake compiled, about 170 ms under `dart run`
  and `dart test`.

### The way out, as the original

An agent in its own session gets none of the terminal's signals. chord
watches SIGTERM, SIGINT and SIGHUP, closes every agent within the ladder's
bounds and re-raises the signal, as `main.tsx`; on an uncaught error and
before `exit`, `ProcessGroups.killAll()` sends SIGKILL to every group still
holding a process, as `leaving.ts`.

### Stopping, and `close()`

The ladder is `process.ts`'s: end stdin; 2 s; SIGTERM to the group; 2 s;
SIGKILL; 2 s; `AgentExitError`; and once the exit is seen, SIGKILL to the
group anyway. Idempotent.

`close()` is a synchronous barrier, then the ladder:

```text
in one synchronous turn:
  closing.cancel()   every waiting request's onCancel enqueues its fallback now
  writer.seal()      no new message is admitted; requests fail with AgentGone
  writer.end()       stdin ends once the queue ahead of it is out
then:
  try     await process.stop(bounds)
  finally await settledWithin(stdoutDone, 1 s); fail every pending request
          with AgentGone; stop routing
```

`cancellation_token`'s `cancel()` runs `onCancel` inside the call and the
writer's `enqueue` is synchronous, so the fallbacks sit ahead of stdin's
end. An agent that does not read gets neither, and the ladder ends it.

### The writer

One per connection. `enqueue` is synchronous: encode, tap, append to the
writer's queue. A pump `add`s everything queued and awaits one `flush()`;
while a flush is pending, messages wait in the writer's queue, never in the
sink (an `add` or `close` on a sink being flushed throws). `end()` is never
awaited. `stdin.done` has an error handler from the start (without one, an
agent closing its stdin ends chord with exit 255); a sink error puts the
writer in `failed`, which fails pending requests as the agent gone.

The writer's queue is not bounded, as the original's is not: an agent that
stops reading is a hung agent, and the person closes it, which bypasses the
stuck flush. The benchmark reports how memory grows against a non-reading
agent.

### Exit, stdout's end and stderr's end, as the original

- The connection ends when stdout ends or errors, never at the exit alone
  (a descendant may hold stdout). Messages already read are tapped and
  routed first.
- `gone()` turns non-null at that moment: the stderr tail so far, possibly
  empty.
- Every pending request then fails with `AgentGone`, built once stderr has
  ended or 500 ms passed, with the exit attached if seen within another
  500 ms. Its message is `The agent exited.` or `The agent exited: <tail>`.
- `exited` settles at the exit plus the last words; it fails nothing.
- An open rejects through stdout's end too. With a descendant holding
  stdout, the open stays pending until its token is cancelled or the window
  closes, as in the original.
- stderr is kept in `StderrTail`: the last 4096 characters, the last six
  non-empty lines of at most 1024 characters each (cut with `…`) and how
  many came before, as `process.ts`.

### Cancel and hangs

- `cancel(sessionId)` cancels the session's waiting tokens (their fallbacks
  are enqueued), then enqueues `session/cancel`. Its future completes when
  the notification is queued, not when the agent obeys; it fails with
  `AgentGone` if the writer is sealed or failed.
- `prompt()` settles with the agent's own answer; the client never invents
  a stop reason. Cancelling a prompt's own token sends `cancel` and ends the
  local wait with the token's exception; the answer is tapped and dropped.
- No timeout on `initialize` or any request, as in the original: the
  person cancels, closes or quits. An agent that ignores cancel keeps its
  prompt pending until `close()`, which fails it with `AgentGone`. Only the
  stop is bounded.

### `commandArgv`

The owner chose a port of the original's parse (Q7, option a): a small
tokenizer of our own with shell-quote 1.12.0's results on the 16 cases of
the runtime draft as its tests: quotes and escapes as a shell, `$NAME` and
`${X}` kept as written, an unclosed quote accepted as shell-quote accepts
it, and operators, globs and comments refused with `The agent command
"<command>" holds shell syntax; give a plain command line.` An empty
command is refused with `The agent command is empty.`

## What a person sees

The client draws nothing. The words the screens use come from the
original, and the client hands them the facts:

- start failures: `⏺ <agent> did not start: <words>` with the end of the
  stderr below, the words from `start_failure.ts` per fact (closed before
  answering `<step>`, exited with code `<n>`, stopped by `<signal>`,
  refused, -32601 "does not serve ACP sessions", -32000 with the sign-in
  hint). The interface draft (I3) has the table and the 120x40 and 80x24
  layout for the M1 task that draws them.
- a turn whose agent went: `The agent exited.` or `The agent exited: <tail>`.
- a silent agent: no error and no timer; `Interrupting…` until it answers,
  goes, or the person quits.

The keys that act on the client (Esc to interrupt, the permission prompt's
numbers, arrows, Enter and Esc) belong to the screens and are bound there
through `Actions`; the client binds none.

## Tests

No test reaches a real model, agent or terminal.

- **Unit, no process**, on an in-memory `AgentProcess` and `fake_async`:
  `StderrTail`; the handshake parser (ok, fail frames, wrong nonce, split
  across chunks); `signal`'s ESRCH fallback; the ladder at every step and
  its idempotence; the close barrier (permission and close in one turn,
  cancel then close, a sink that never drains, the ladder failing still
  fails pending requests); the writer (tap order equals byte order, nothing
  touches a sink being flushed, a sink error, a cancelled token never
  sends); exit, stdout and stderr in every order; framing (blank lines,
  CRLF, EOF without newline, malformed UTF-8, non-object JSON, a batch, an
  oversized line in pieces, framing replies untapped); routing (an update
  before a reply and before `session/new`'s answer, a late reply dropped,
  unknown kinds raw, a throwing `onTraffic`); the dispatcher (every row of
  the table above, `$/cancel_request` for a running, an unknown and an
  answered id, numeric vs string ids, a handler answering late, two
  requests for one tool call, a bad `optionId`); `commandArgv`'s 16 cases;
  the views.
- **In-memory only**, because no fake scenario plays them (Q4, owner chose
  unit tests): a permission withdrawn by `$/cancel_request`; an update
  before `session/new` answers; stdout closed without an exit; a sink that
  never drains.
- **A real child**, `sh -c` scripts with the original's test bounds (exit
  100 ms, term 300 ms, kill 2000 ms): own group and a grandchild in it;
  SIGTERM reaching it; a TERM trap ended by SIGKILL; nothing left after;
  cancel in the same turn `Process.start` returns; a launcher gated by an
  injected `sh` wrapper, stopped before and after the gate opens; missing,
  non-executable and vanished programs; a grandchild holding stderr; env,
  an unrelated cwd, argv with a `-dash` `argv0`; SIGPIPE default; an agent
  closing stdin while chord writes. Run from the repository root and from
  `example/chord`.
- **`compile`-tagged**: `dart compile exe` into a temporary directory, run
  from `/` with no source in reach: own group, exit code, missing program,
  malformed flag.
- **The original's fake agent**, wired by CTUI-13 (next): argv `[<bun>,
  <chord>/tests/fixtures/fake_agent/main.ts, --scenario <name>, flags…]`,
  both absolute, every agent closed in `tearDown` with short bounds, tests
  tagged `fake_agent`. CTUI-13 provides:
  - the finder: `CHORD_SOURCE` if set (wrong means skip, no fallback); else
    `git rev-parse --path-format=absolute --git-common-dir` run in the
    port's package directory, whose parent is the main checkout with
    `../chord` beside it (from a worktree, `../chord` relative to the
    worktree does not exist); without git, `../chord` beside the
    repository root. Then `CHORD_BUN` or `bun` on `PATH`, made absolute;
    then `<chord>/node_modules/@agentclientprotocol/sdk/package.json`.
    Each missing piece skips with a reason that says which and how to fix
    it.
  - `fakeAgentCommand(scenario, flags)`, the original's `gatedCommand`, and
    a harness that opens an agent with a traffic recorder installed before
    the start and always closes it.
  - The scenarios for M0/M1, all in the fake today: `text` and
    `--no-usage`; `thought`, `todos`, `tools`, `calls`, `edit`, `rewrite`,
    `markdown`, `long`; `late`; `unknown`, `authstatus`; `permission`,
    `twins`, `overlapask`, `leftask`, `mainbetween`; `slow`/`long` then
    cancel, `permission` then cancel, `cancels`; `ignorescancel`,
    `--hang turn`; `error`, `turnfailed`; `crash`; `--start-fails
    traceback|stdout|notacp|alias`; `--hang start` (the full ladder);
    `flood`.
- **Benchmark**, `example/chord/benchmark/acp_updates.dart`, no terminal:
  a 16 ms heartbeat's lateness and frames drawn while 10 000 updates come
  in one burst, 1 000 a second for 10 s, and the fake's `flood`; cancel
  latency during them; memory against a non-reading agent. Reported, not
  assumed. Decoding stays on the main isolate unless it shows a decode
  holding a frame.

## The critic's findings, resolved

1. Permission withdrawal vs `json_rpc_2`'s `Peer`: taken to the owner, who
   chose option B; the dispatcher's id rules and settlement gate are above.
2. The launcher's race before `setsid`: accepted; the nonce handshake and
   `kill(-pid)`-then-`kill(pid)` above.
3. The launcher's argv and the JIT path: accepted; frozen above, measured
   from both package directories and under AOT with no source.
4. Close ordering: accepted; the synchronous barrier, `cancel()` meaning
   queued, and the `finally` above.
5. Two ingresses: accepted; one ingress, the session layer's buffer is
   CTUI-15's.
6. Framing: accepted; the SDK's framing and cap, untapped errors. Runtime's
   64 MiB bound and `malformed` traffic were dropped.
7. The agent's requests: accepted; the table above (elicitation and plans
   cancelled, fs and terminal -32601).
8. Exit vs stdout and `gone()`: accepted; as the original, `gone()`
   immediate at stdout's end.
9. Views: accepted in part. Library-private representation, string
   dispatch, edge checks, an `optionId` check, a caught `onTraffic`, a
   semantic round trip. Not taken: generated or validated types for
   updates, since the original validates none.
10. Packages for `commandArgv` and cancellation: accepted; `io` and `shlex`
    tried and taken to the owner (Q7, a port of the parse);
    `cancellation_token` 2.0.1 tried and taken.
11. Writer and flood: accepted in part. Unmeasured claims dropped and the
    benchmark measures them. Rejected: runtime's 4 MiB admission bound
    with a stalled agent treated as gone, since the original has none and
    a non-reading agent is a hung agent the person closes; a bound would
    be a difference from the original, for the owner to ask for.
12. The fake's finder: accepted; above.
