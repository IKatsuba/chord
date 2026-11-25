# CTUI-56 framework draft: the serving peer, the modules, the session host

Author: framework (architects). Answers the brief's questions 1-3, with what
else in this field the others may miss. Owner decision already received and
applied here: `_chord/session/state` and `_chord/session/steer` are in
(main sessions only); `agents` and `monitors` wait for M4; `/team` and
`/new` are out, so no chord command of its own is intercepted, only a seam
is left for M4.

## 0. The framework (`lib/`) is not touched

`chord acp` draws nothing. No widget, render object, text layout, key or
renderer work is needed, and none is proposed. Two things at the boundary
do matter:

- **The acp path must not touch the terminal.** `bin/chord.dart` builds
  `StdioTerminal` lazily (`terminalForRun`); the acp branch must return
  before anything takes the terminal, sets raw mode or registers the
  window's `dieBySignal(leaving)`, which gives the terminal back. The acp
  path installs its own signal handling (section 4).
- **stdout is the protocol.** Any `print` reached from the acp path (a
  stray debug line, a package that prints) corrupts the stream. The acp
  run goes inside a zone whose `print` writes to stderr. The original has
  no such guard because Bun's `console.log` is not used there; this is a
  Dart-side precaution, not a behaviour difference.

## 1. The serving JSON-RPC peer and stdio framing (question 1)

### What the SDK does for the original

`connectAgentApp` (`src/acp/agent_app.ts`) registers a handler per method
on the SDK's `agent()` app. The SDK then: frames ndjson both ways
(`ndJsonStream`, 32 MiB `DEFAULT_MAX_MESSAGE_BYTES`), zod-parses each
method's params (-32602 on failure), answers unknown methods -32601, hands
each handler `{params, requestId, signal}` where `signal` aborts on the
client's `$/cancel_request` naming that id or on the connection's end,
turns a thrown `RequestError` into the error answer, and gives
`connection.client.request(method, params, {cancellationSignal})` /
`notify(...)` for chord's own calls to the client. `seeingWrites`
(`src/acp/stdio.ts`) wraps the stream so the shutdown can wait for named
answers to be written (`expect(id)`, `drained()`, `failed()`).

### `json_rpc_2` does not fit the serving side

| Need | `json_rpc_2` `Server`/`Peer` |
| --- | --- |
| The request id in the handler (`step(bind, requestId)`, `wire.expect(opening.requestId)`, `answers` keyed by id) | Not exposed: a handler gets `Parameters` only |
| `$/cancel_request` aborting one running handler | No per-request cancellation; the notification would be just another method |
| An answer settled from outside the handler (a turn's `result` answers `session/prompt` later; the shutdown answers `cancelled`) | Possible only by returning a Future, without the id there is no table to settle it from |
| Knowing an answer has reached the pipe (drain on the way out) | No hook; its sink is fire and forget |
| No batches (ACP refuses arrays with -32600) | Serves batches |
| The SDK's error shapes (-32601 `"Method not found": <m>` with `data.method`, -32602 `Invalid params` with data) | Its own wording (`Unknown method "x".`) |
| Strict write order between notifications and answers | Answers go out when the handler's Future completes, a microtask after the code that settled it |

`rpc.dart` already records the first point for the client side, and
`ChordRequests` already uses `json_rpc_2`'s `Client` for the half where it
fits. **Recommendation: the same split, mirrored.**

- **Serving (client to chord): a dispatcher of ours**, in `rpc.dart`
  beside `AgentRequests`, which already does the same job for the agent's
  requests (method table, -32600/-32601/-32602 shapes, `$/cancel_request`
  by id with JSON-RPC id equality, one answer per request). Generalise
  rather than copy: one `Incoming` core (id check, envelope check,
  `_running` tokens by id, `cancelRequest`, `_resultMessage` /
  `_errorMessage`, `OnCancel`) used by both `AgentRequests` (existing,
  refactored onto it, behaviour unchanged, its tests are the guard) and
  the new `ClientRequests` (serving). If ship prefers not to touch
  `AgentRequests` in this task, the core is extracted and only the new
  class uses it; the refactor follows later.
- **chord's calls to the client** (`session/request_permission`,
  `elicitation/create` if relayed, notifications): `ChordRequests` as it
  is, over the stdout writer. One addition: when its `token` is cancelled
  (an ask withdrawn because the agent settled it, the turn ended, or the
  session closed), it must also send `$/cancel_request {requestId}` to the
  client, as the SDK does for an aborted `cancellationSignal`. Today
  `ChordRequests.request` only drops the late answer. *Ship must confirm in
  the SDK source that it sends `$/cancel_request` on abort before building
  this; if it does not, the addition is dropped.*

`ClientRequests` API (plain Dart, no IO):

```dart
/// A request from the client, as a handler sees it.
final class Served<P> {
  final Object? id;           // the JSON-RPC id, by value and type
  final P params;             // checked and typed
  final CancellationToken token; // $/cancel_request on this id, or close
}

/// The client's requests to chord: a typed handler per method, answered
/// exactly once, in the order answers are settled.
class ClientRequests {
  ClientRequests({required Send send, required CancellationToken closing});

  void onRequest<P>(String method, P Function(Object? params) check,
      FutureOr<Map<String, Object?>> Function(Served<P> request) handle);
  void onNotification<P>(String method, P Function(Object? params) check,
      void Function(P params) handle);

  void request(Map<String, Object?> message);       // id and method
  void notification(Map<String, Object?> message);  // method, no id
  void cancelRequest(Map<String, Object?> message); // $/cancel_request
  int get running;
}
```

`check` throws `InvalidParams(message, data)`; a handler throws
`RpcError(code, message, data)` (the SDK's `RequestError`); anything else
thrown is -32603 with its message, as the SDK answers. `route` in
`rpc.dart` grows a twin for the serving side: id+method to
`ClientRequests.request`, id alone to `ChordRequests.response`,
`$/cancel_request` to `ClientRequests.cancelRequest`, other notifications
(`session/cancel`) to `notification`.

**Write order.** The original relies on order in three places: a new
session's answer before anything held for it (`wire.expect(...).then
(release)`), a load's replayed updates before its answer, and a prompt's
`session/update`s before its answer. Dart's `Future.then` puts the answer
one microtask behind whatever the settling code enqueues after
`complete()`. So the dispatcher writes an answer synchronously at the
moment the handler's Future completes (it listens with a synchronous
completer it owns, `Completer.sync`), and the host never enqueues after
settling in the same task unless that order is intended. For a new
session the host still waits for the answer's write (`expect`, below)
before releasing what it held, as the original does; that is a property
of the pipe, not of microtasks, and stays.

**Params checking.** The SDK checks params with zod and answers -32602
with zod's issue list as `data`. CTUI-29 settled that settings are
checked by our own code "in zod's words". Recommendation: the same for
ACP params: a checker per method in `acp/agent_app.dart` (or beside the
types in `schema.dart`) producing the message and `data` the SDK would,
for the fields chord reads; `interface` lists the exact texts. If exact
zod `data` arrays prove too costly, the fallback is the same code and
message with a shorter `data`: **owner decision** (D1).

### Framing over stdio

- **Input.** `stdin` as `Stream<List<int>>` through `wire.dart`'s
  `LineDecoder`, which is already the SDK's `ndJsonStream` read side
  (`\n`, one `\r` dropped, blanks skipped, last unterminated line taken at
  EOF, malformed UTF-8 as U+FFFD, -32700 for a bad line, -32600 for an
  array or a non-object). It is reused unchanged; the default cap is the
  same 32 MiB. `FramingReply` goes to stdout. `MessageTooLargeError` ends
  the connection: the leave starts with `broken` and stderr says
  `chord: the connection closed: Incoming ACP data exceeds the configured
  33554432 byte limit` (the `toString` already matches the SDK). Stdin's
  `done` is `eof`; an error on stdin is `broken`.
- **Output.** An `Output` in `acp/stdio.dart`: the original's
  `outputStream` + `seeingWrites` in one. It is `Writer`'s pump
  (`connection.dart`) over an `IOSink` (stdout) instead of an
  `AgentInput`: `enqueue` is synchronous (encode, queue), one `add` of
  everything queued and one `flush` in flight, the next pump on its
  completion. Then:
  - `Future<void> expect(Object? id)`: settles when the line answering
    `id` has been flushed, or when the output fails or is closed;
  - `Future<void> drained()`: every expected answer flushed, or none can
    be;
  - `bool get failed`: a flush or add failed (the client is gone):
    `broken`.
  Flush granularity is coarser than the SDK's per-message write callback
  (a flush covers every line added before it); an answer counts as
  written when the flush that carried it completes. That is the same
  observable behaviour for `expect` and `drained`.
- **Back-pressure.** A client that stops reading must not stop chord: the
  pump never blocks the isolate (Dart's `IOSink.flush` is asynchronous),
  and the queue grows in memory as Node's would. No cap is added; the
  original has none. On the way out the drain wait is bounded by
  `DRAIN_MS` (500 ms) as in `leaving.ts`.
- **SIGPIPE.** Writing to a pipe the client closed must fail the flush,
  not kill chord, so the leave can still close the agents. Ship verifies
  under `dart compile exe` in the `compile` tag (a client that closes
  stdout and keeps stdin open): the expected stderr line is the
  `connection closed` one and the agents' groups are gone afterwards.
- **Tap.** `traffic.dart`'s `TrafficTap` is the agent side's record of
  traffic. The upstream side needs none in this scope; `enqueue` takes no
  tap. (Should a client-side traffic log be wanted later, the hook is
  the same as `Writer`'s.)

## 2. Module layout (question 2)

Files are named after the original's, per AGENTS.md.

| Original | Port | Status |
| --- | --- | --- |
| `src/acp_agent.ts` (`runAcp`, `AcpOptions`, `AcpRun`, `byHandNote`) | `lib/acp_agent.dart` | New. `runAcp` wires stdio, `ClientRequests`, `ChordRequests`, the host and the leave; `byHandNote(bool)` pure |
| `src/acp/agent_app.ts` (method table, `BLOCKS`, `STEER`) | `lib/acp/agent_app.dart` | New. Registers the methods in scope on `ClientRequests`, with their params checkers; the `_chord/agents/*` and `_chord/monitors/*` entries are absent (-32601) until M4 |
| `src/acp/stdio.ts` | `lib/acp/stdio.dart` | New: `Output` (section 1) |
| SDK `agent()` connection | `lib/acp/rpc.dart` | Extended: `ClientRequests`, shared `Incoming` core, a serving `route` |
| `src/acp/upstream_turns.ts` | `lib/acp/upstream_turns.dart` | New, pure: `Turns`, `TurnInput`, `TurnSend`, `reduceTurns`, `turnOf`, `sessionStateOf` |
| `src/acp/host_fold.ts` | `lib/acp/host_fold.dart` | Deferred to M4 (see 3.4); main's `requires_action` read from the conversation instead |
| `src/session/upstream.ts` | `lib/session/upstream.dart` | New, pure: `UpstreamSession`, `aliasFor`, `mapUpdate` (gating), `configChange`, `answeredConfig`, `configSetter`, `configOptionsOf`, `messageChunk`, `permissionAnswerOf`, `planPermission`/`planAnswerOf`, `promptOf`, `commandOf` (seam), `commandsIfNone`. `agentStateOf`/`agentUpdate`/`childSession` wait for M4 |
| `src/session/upstream_commands.ts` | none | Only `/team` and `/new` text; out of scope |
| `src/session/new_args.ts` | none | `/new`; out |
| `src/session/auth_status.ts` | `lib/session/auth_status.dart` | New, pure: `AccountState`, `AccountEvent`, `foldAccount` (needs the client-side seam S5) |
| `src/session/elicitations.ts` | `lib/session/elicitations.dart` | Depends on the interface/owner answer to question 7 |
| `src/session/place.ts` | `lib/session/place.dart` | New: per-`cwd` settings (`loadSettings` + `resolveStartup` of `settings.dart`), `.mcp.json` servers, `startupOf(agent).refused` |
| `src/session/leaving.ts` (`createLeaving`) | `lib/session/leaving.dart` | Extended: `Leaving`, `LeaveReason`, `LeaveExit`, `LeaveStep`, `leaveMs`/`drainMs`, beside the window's `leave()`, which stays |
| `src/session/agents_host.ts` | none now | Not ported for main alone; see 3.4 |
| `src/cli.ts` `acp` parsing | `lib/cli.dart` | Extended: the `acp` word, its flags, the unknown-agent refusal |
| `bin` entry | `bin/chord.dart` | Extended: the acp branch before any terminal |

Tests mirror them: `test/acp_agent_test.dart`,
`test/acp_extensions_test.dart` (state and steer only),
`test/acp/upstream_turns_test.dart`, `test/acp/stdio_test.dart`,
`test/acp/rpc_test.dart` (grown), `test/session/upstream_test.dart`,
`test/session/upstream_conversation_test.dart`,
`test/session/auth_status_test.dart`, `test/session/place_test.dart`,
`test/session/leaving_test.dart`. `runtime` owns which run in memory,
through the fake, or in a pty.

### Existing port modules: reused unchanged

`wire.dart` (`LineDecoder`, `encodeLine`), `ChordRequests`, `process.dart`
(process groups, `stopLadder`, `MemoryAgentProcess` for tests),
`connection.dart` (one `Agent` per session), `sessions.dart`
(`readRecords`, `earlierSessions`, `sessionById`, `ResumeError`),
`record.dart`/`record_worker.dart` (records as the window writes them),
`replay.dart`, `settings.dart`, `platform/`.

### Existing port modules: seams needed

The port's `Conversation` and `Session` were cut to the window's person
(`conversation.dart`'s header says so). The original's `acp_agent.ts` uses
more of them. Each item below is a prerequisite, in the session layer, not
the server; I list them so `runtime` can order the build units and the
lead can see the real size of the task.

| # | Seam | Original | Port today |
| --- | --- | --- | --- |
| S1 | `send` with a caller-given `turnId` | `send(text, prompt, attachments, mentions, {turnId, links, resources})`; the request binds its turn *before* `send`, which emits before returning | `send(text, [prompt, mentions])` mints `turn-N` itself and may emit `PromptAction` before it returns, so the server cannot bind first. Add an optional `turnId` |
| S2 | Prompt content beyond text: images, embedded resources, resource links | `promptOf` turns blocks into text + attachments + links + resources; `Session.takesImages()`/`takesEmbeddedContext()` | Text and mention paths only; no image or resource blocks reach `session/prompt`; no `takesImages` |
| S3 | `steerQueued(turnId)` | steers that request's own entry | `steerQueued()` takes the oldest |
| S4 | `rename(title)` on a live session, and `recordPendingRename` for a listed one, with the pending rename sent on next load/resume | `conversation.rename`, `record.ts` | `renamed` is read from records (`sessions.dart`, `replay.dart`), never written; no `rename` |
| S5 | Account: the agent's `auth/status` and `auth/status_update`, as events | `account` events, `AccountState` | Nothing in `connection.dart` |
| S6 | Client MCP servers and `.mcp.json` in `session/new`/`load`/`resume` | `mainServers`, `place.mcpServers` | `mcpServers: const []` hard-wired in `session.dart`; `.mcp.json` not read anywhere |
| S7 | Initial `configOptions` from `session/new` | `mainEntries` | `initial_options.dart` exists; check it takes ACP's `InitialSessionConfigOption` shape |
| S8 | `notices` capability toward the agent, and the client's `elicitation/complete` notify | `open({notices, onElicitationComplete})` | Not declared; elicitation cancelled in `rpc.dart` (CTUI-28) |
| S9 | `heldBack` and `left_open` in the new/load answer's `_meta` | `session.heldBack`, `left_open` replay event | Check `replay.dart`; `left_open` is records-only in scope |
| S10 | Events the turn table hears, by name | `prompt`, `result`, `queue_withdrawn{turnIds}`, `cycle_started`, `self_started`, `disconnected` | `Transcribed(PromptAction)`, `Transcribed(ResultAction)`, `QueueWithdrawn(prompts)`, `Transcribed(CycleStartedAction)`, `Transcribed(SelfStartedAction)`, `Gone`. A pure `turnInputOf(ConversationEvent)` maps them; check that `QueueWithdrawn` carries turn ids and `PromptAction` carries `into` |
| S11 | The replay hook | `replayed(key, replay)` sets `replaying` while the past plays | One `HistoryReplayed` batch before live updates: simpler, the server takes the batch as `past` |

S1, S3 and S10 are small. S2, S4, S5 and S6 are features of their own
(the window would gain from S2, S4 and S6 too). Whether they are built in
CTUI-56 or as tasks before it is the **lead's/owner's call** (D2); the
server cannot answer the guide's contract without them, so the honest
options are: (a) CTUI-56 builds them first, as units 1..n; (b) split them
out as tasks CTUI-56 depends on; (c) CTUI-56 ships without them and
refuses (image blocks -32602 as "unsupported", `set_title` -32601,
`auth/status` `unknown` forever, no MCP servers), each a recorded
difference. Recommendation: (a) for S1, S3, S10, S11 (they are the
server's own needs); (b) for S2, S4, S5, S6 (they change the window too
and deserve their own tests and owner look); never (c) silently.

## 3. The session host (question 3)

### 3.1 Shape

Flutter has no analogue worth borrowing here; this is a reducer-and-ports
design like the rest of the port. Logic sits where a test reaches it:

- **Pure:** `reduceTurns` (which request a turn answers), `mapUpdate` /
  `configChange` (what goes up, gated), `aliasFor`, `foldAccount`,
  `sessionStateOf`, `promptOf`, params checkers.
- **One stateful object, `AcpHost`** (in `acp_agent.dart`), holding the
  tables and calling the pure functions; it touches IO only through ports
  it is given (`send`/`notify`/`request` toward the client, `open` for a
  `Conversation`, `place(cwd)`, `readRecords`, the clock). Tests drive it
  with in-memory processes and a recorded `Output`.

```dart
/// What `chord acp` holds: every session the client can name, until the
/// way out.
final class AcpHost {
  AcpHost(AcpPorts ports, {required String agent, required String version});

  // The tables, as the original's closure holds them:
  final Map<String, AcpEntry> sessions;      // by the client's id
  final Set<String> reopening;               // ids a load/resume claims
  final LinkedHashSet<AcpEntry> entries;     // every not-closed entry, in
                                             // start order: the oldest live
                                             // main is the account source
  final Map<String, CancellationToken> asks; // chord's asks to the client
  final Map<Object?, Completer<Map<String, Object?>>> answers; // prompts
  ClientCapabilities? capabilities;          // first initialize wins
  AuthStatus toldAccount;                    // last auth/status_update
  final Leaving leaving;

  // One method per served method, each taking a Served<P>:
  Map<String, Object?> initialize(Served<InitializeRequest> r);
  Future<Map<String, Object?>> newSession(Served<NewSessionRequest> r);
  Future<Map<String, Object?>> listSessions(Served<ListSessionsRequest> r);
  Future<Map<String, Object?>> loadSession(Served<LoadSessionRequest> r);
  Future<Map<String, Object?>> resumeSession(Served<ResumeSessionRequest> r);
  Future<Map<String, Object?>> prompt(Served<PromptRequest> r);
  void cancel(CancelNotification n);
  Future<Map<String, Object?>> setConfigOption(Served<...> r);
  Future<Map<String, Object?>> setMode(Served<...> r);
  Future<Map<String, Object?>> setTitle(Served<...> r);
  Future<Map<String, Object?>> close(Served<CloseSessionRequest> r);
  Map<String, Object?> authStatus(Served<void> r);
  Map<String, Object?> steer(Served<SteerRequest> r);   // owner: in
}

/// One session, from its start until its agent is gone.
final class AcpEntry {
  final Conversation conversation;
  final String name;                 // "session n", for stderr
  UpstreamSession? upstream;         // none until connected
  bool live = false;                 // the client has its id
  final List<void Function()> held;  // what waits for `live`
  List<ConversationEvent>? past;     // set on load: replayed before answer
  String? reopens;                   // the id load/resume claimed
  Turns turns = noTurns;
  String stateSent = idle;           // last _chord/session/state, encoded
  bool closed = false, gone = false;
  Opening? opening;                  // the pending new/load/resume answer
  AccountState account = noAccount;
  Future<void>? closing;
  void Function()? unlisten;         // the conversation listener
}
```

### 3.2 Who owns what

| Concern | Owner | How |
| --- | --- | --- |
| Live ids | `AcpHost.sessions` | Set on `Connected`; removed on `close`, `Gone` |
| Aliases (`s1~2`) | `aliasFor(sessions.keys ∪ reopening, agentId)` at `Connected` | A reopened session keeps its claimed id. `UpstreamSession` holds `upstreamId` (client's) and `agentId` (agent's); every update, ask and set translates through it |
| Prompt queue | `Conversation` (its own queue), plus `AcpEntry.turns` binding request id to turn id | `session/prompt` binds (S1) then sends; the turn's `result` answers; `QueueWithdrawn` answers `cancelled`; `$/cancel_request` on a queued prompt is the request's token, which calls `conversation.cancelPrompt(turnOf(turns, id))` |
| `session/cancel` | `conversation.interrupt()` | Withdraws the client's queued prompts (they answer `cancelled` via `QueueWithdrawn`); for an unknown id, the children seam (3.4) |
| Titles | `conversation.rename` (S4) for a live entry; `recordPendingRename` for a listed one | Whitespace folded, empty -32602, unknown -32002 |
| Auth status | `AcpHost.entries` order + each entry's `account` | `accountSource` = first entry not gone, not closing, with a session; `tellAccount` sends `auth/status_update` on a deep change; a source's close or exit re-reads it |
| Session state | `sessionStateOf(entry.turns, asking)` | `asking` = the conversation has an open permission (or plan/elicitation ask) for main; sent on change only, never after `closed` |
| Steer | `step(steered, turnId)` then `conversation.send(turnId)` (S1) then `steerQueued(turnId)` (S3) | Answer `{delivery: sent|queued}`; its turn, if it runs as one, is the client's and its words are not told back |
| Asks to the client | `AcpHost.asks` by chord's ask id | Permission and plan relayed through `ChordRequests.request` with a token; the agent's settle cancels the token (S8's `$/cancel_request`); a client error is no answer, stderr line, settled as none |
| Held updates | `AcpEntry.held` | Until `live`: on `session/new`, after the answer's line is flushed (`output.expect(id)`); on load, past first, then the answer, then held |
| Records | `Conversation`'s recording, as the window's | No new record version |
| The way out | `Leaving` (section 4) | Steps: each entry's close, in parallel |

### 3.3 The event path, per update

`Conversation.listen` → `AcpHost.heard(entry, event)`:

1. If `entry.past != null` and replay is under way: append, return (S11:
   in the port the past arrives as one `HistoryReplayed` batch, so this
   is one append, not a flag around a callback).
2. `turnInputOf(event)` (S10) → `reduceTurns` → each `TurnSend` settles
   an `answers` completer, or relays a `messageChunk`.
3. `Transcribed(UpdateAction)` → `relay`: `mapUpdate(upstream,
   capabilities, update)` → `send` or drop; then `configChange`.
4. `AgentStateChanged` → `configChange` (modes, models, options as one
   `config_option_update`).
5. Permission asked/settled → `once(entry, askPermission)` / withdraw.
6. `Connected`/`ConnectFailed`/`Gone` → as `acp_agent.ts`.
7. `tellState(entry)` at the end of every event, as the original does.

All synchronous; nothing awaits between hearing and writing, so the
order on stdout is the order of events.

### 3.4 Where M4's children attach

The original routes even a lone main session through `createAgentsHost`
(children, teams, monitors, tasks). Porting that host for main alone
would carry `agents_host.ts`'s 3,000 lines of machinery the brief
excludes. Recommendation: **`AcpEntry` holds the main `Conversation`
directly now**, and the places a child plugs in are explicit, each with
a test that pins the main-only behaviour:

1. **Session host.** `AcpEntry.conversation` becomes `host.main` when M4
   ports `agents_host`; `AcpEntry` gains `routes` and `folds` then. The
   `heard` dispatch already takes `(entry, event)`; M4 adds
   `childHeard(entry, key, event)` beside it.
2. **Update mapping.** `UpstreamSession.children` exists now: the
   agent's own `subagent_update` (in scope, capability-gated) needs it to
   name `parent/child` ids. `mapUpdate`'s `subagentId` argument exists
   and is always null from main in this scope.
3. **Command interception.** `session/prompt` calls `commandOf(prompt)`
   first; in this scope it returns null for every prompt (no chord
   command exists), so the prompt goes to the agent as typed, including
   a literal `/team`. M4 fills `commandOf` and the `commanding` table.
   This is the original's behaviour minus its commands, which the owner
   decided.
4. **Cancel routing.** `cancel(sessionId)`: a live main is interrupted;
   otherwise `cancelledInChildren(entry, id)` over every entry, which
   now handles only the agent's own subagents (`childOf(upstream, id)` →
   `conversation.stopSubagent`) if the port's `Conversation` can stop one,
   and returns false otherwise.
5. **Shutdown.** `Leaving.steps` is a getter over `entries`; M4 adds the
   server and resource-reader steps.
6. **Extensions.** `initialize`'s `_meta["chord/acp"].extensions` is
   built from one const map, `{'session/state': 1, 'session/steer': 1}`
   now; M4 adds `agents` and `monitors` with their methods.
7. **The host fold** (`host_fold.ts`) exists for the host's `stateOf`
   (children asking). Main's `requires_action` needs only "an ask is
   open", which the entry knows from the asks it relayed. M4 ports the
   fold with the host.

## 4. The way out, as it touches this layer

`runtime` owns triggers, timings and exit codes. What the layer needs:

- `Leaving` in `session/leaving.dart`, the original's `createLeaving`:
  `started`, `leave(reason)` once, deadline armed first (`leaveMs` 15 s),
  `answer()` (the turn table's `closing` sends; pending opens rejected
  -32603 `chord is closing`; each answer `expect`ed), `drained()` bounded
  by `drainMs` 500 ms, `closeConnection()`, steps in parallel, failures
  and unsettled steps named on stderr, groups killed at the deadline
  (`ProcessGroups.instance.killAll()` exists), `exit(how)`.
- Signals: SIGINT, SIGTERM, SIGHUP through `ProcessSignal.watch` on the
  acp path, each a `leave(signal)`; exit by the signal (re-raise after
  the leave) as `dieBySignal` already does for the window. Ship checks
  that `dieBySignal`'s re-raise is reusable without its terminal giveback.
- Crash: `runZonedGuarded`'s handler is `leave(crash)`.

## 5. Costs

There are no frames. Per client message: one line decode, one params
check, one handler. Per agent update: one `mapUpdate` (a map lookup and,
for a new subagent, a copy of the `children` map, as the original), one
`jsonEncode`, one queue append; the pump batches all lines queued while a
flush is in flight into one `add` + `flush`, so a flood costs one
syscall-ish flush per batch, not per update. `tellState` encodes the
state per event (as the original's `JSON.stringify`); it is a few fields.
`tellAccount` compares two small maps. `sessions` lookups are O(1);
`turnOf` is O(bound prompts) per cancel, which is the queue's length.
Memory: one `Conversation` per session, as the window; held updates only
until the answer's flush. `runtime` owns the benchmark (many sessions,
update flood through `Output` to a slow reader).

## 6. Differences from the original

| # | Difference | Options | Recommendation |
| --- | --- | --- | --- |
| F1 | Our own serving dispatcher instead of the SDK | (a) ours in `rpc.dart`, (b) `json_rpc_2` `Peer` with workarounds | (a); `json_rpc_2` does not fit (table in 1). No behaviour difference intended; recorded in `docs/decisions.md` as the package finding |
| F2 | Params errors' `data` (zod issues) | (a) reproduce zod's issue shapes for read fields, (b) same code/message, our own `data` | (a), per the CTUI-29 precedent; (b) only with the owner's yes (D1) |
| F3 | No `agents_host` behind main | (a) entry holds the conversation, (b) port the host now | (a); M4 ports it |
| F4 | Answer written-ness by flush, not per write callback | none needed | Same observable behaviour |
| F5 | Replay arrives as one batch (`HistoryReplayed`) rather than events under a `replaying` flag | none | Same wire result: past updates, then the answer |
| F6 | `print` redirected to stderr on the acp path | none | Precaution, no visible difference |
| F7 | Missing session features S2, S4, S5, S6 | (a) build in CTUI-56, (b) prerequisite tasks, (c) refuse and record | (a) or (b), never (c) silently (D2) |
| F8 | `ChordRequests` sends `$/cancel_request` on a withdrawn ask | only if the SDK does | Verify in the SDK, then match it |

## 7. Owner decisions

- **D1.** -32602 `data`: zod's issue lists exactly, or our own shorter
  data (F2).
- **D2.** The session-layer prerequisites S2 (images and embedded
  resources in prompts), S4 (renames, pending renames), S5 (agent
  account / `auth/status`), S6 (client MCP servers and `.mcp.json`):
  built inside CTUI-56, or split as tasks it waits on.
- **D3.** Whether `AgentRequests` is refactored onto the shared core in
  this task, or the core is extracted for the serving side alone
  (behaviour is the same either way; it is a scope question for ship).

## 8. Open questions for the others

- **interface:** the exact text of each -32602/-32002/-32603 (they
  feed the checkers); whether `available_commands_update` without
  chord's commands still sends `commandsIfNone` (an empty list, or
  nothing); question 7 decides whether `elicitation/create` goes through
  `ChordRequests` and S8 is in scope.
- **runtime:** the ordering of the load answer against updates the agent
  sends while chord is replaying (held until after the answer, as
  section 3.2 proposes); whether a new session's held updates wait for
  the answer's *flush* (`expect`) or only its enqueue (the original waits
  for the write); the SIGPIPE check under `dart compile exe`.
