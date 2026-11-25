# CTUI-35 runtime draft: chord's MCP server, children and messages

Runtime architect's answer to the brief's runtime questions 1-8: the
module layout, the event path, the concurrency and failure scenarios, the
test plan and my part of the unit split. Every behaviour named here is the
original's (`../chord` `src/server/`, `src/session/agents_host.ts`,
`open_agents.ts`, `tasks.ts`, `window_agents.ts`, `new_args.ts`,
`upstream.ts`, `upstream_commands.ts`, `src/acp/host_fold.ts`,
`src/acp_agent.ts`); nothing is added. Revised once after the critic's
findings (1, 2, 3, 6, 9, 10, 11 and the seams decision).

## 0. Where the port stands today

Reused, not rebuilt:

- `Conversation` steers the person's queued prompts (`steerQueued`,
  `_steer`, held for open calls and for an answer, `SelfStartedEntry` for
  a turn the agent started on its own after a missed steer). Messages from
  agents go through the same `_steer`, with a sender.
- `QueuedPrompt` carries `afterAnswer`, `afterCalls`, `steering`, `taken`;
  it has no sender yet.
- The record reads a prompt's `from` and `into`, `left_open` and `closed`
  lines, the header's `parent` and `task` (`record.dart`, `replay.dart`,
  `sessions.dart`).
- `SubagentEntry`/`Subagent` draw an adapter's own subagents; the original
  draws a task as the same block, marked by `_meta["chord/task"]`,
  `chord/spent`, `chord/stopped`. The port has no task meta yet.
- `serversFor` sorts the user's servers by transport; no `chord` argument,
  no `chord-2` naming.
- `acp/process.dart` stops an agent by stdin end, SIGTERM to its group,
  SIGKILL, 2 s each (`StopBounds`); `platform/process.dart` kills every
  group left at exit.
- `chord acp` advertises `session/state` and `session/steer`, answers
  `_chord/agents/*` with -32601, adds no command of its own, and has
  `asksIn` but no `nested` sessions, no `commandsSent`, no child routes
  (CTUI-56 decisions).
- `StartConnection` owns one `Conversation` and `ValueNotifier<AppState>
  app`, folding each event with `reduceApp`; the window also folds events
  it dispatches (`window.dart` around `reduceApp(before, event)`).

Missing: the MCP server, a window of many agents, tasks, messages between
agents and their records; `agent_name.dart` (`agentNameProblem`).

One port difference that this task must remove first: the port numbers
asks per session (`permission-${++_next}` in `session/permissions.dart`,
`elicitation-${++_next}` in `session/elicitations.dart`); the original
gives every ask a `crypto.randomUUID()` (`permissions.ts:119`,
`elicitations.ts:110`). With tasks relayed into a parent, numbered ids
collide (section 4.1). Nothing in `lib/` depends on the numbered form; one
test asserts `elicitation-1` and changes with it.

## 1. The MCP server (question 1)

### What the original does

`src/server/server.ts`: one server per window (one per `chord acp`
process), `127.0.0.1`, port 0, path `/mcp`, Streamable HTTP, stateful.
`src/platform/serve.ts` sets Bun's `idleTimeout: 0` (an MCP stream sits
idle while a tool waits on the person) and writes nothing to stdout or
stderr. Admission:

- `admit(caller)`: a random UUID token mapped to the `Caller`; answers the
  ACP `mcpServers` entry `{type: http, name: chord, url, headers:
  [Authorization: Bearer <token>]}`.
- Every request: no bearer or an unknown one, 401 `Unknown token`; a
  `mcp-session-id` not opened, 404 `Session not found`; opened with another
  token, 403 `Session opened with another token`; no session id and not an
  `initialize` POST, 400 `No session; initialize first`. JSON-RPC error,
  code -32000, `id: null`. A throwing handler, 500 `Internal error`.
- A fresh `McpServer` per `initialize` with the caller's tools registered,
  so `tools/list` differs per token.
- `revoke(token)` forgets the token and closes the MCP sessions it opened;
  `close()` closes every session and stops listening. A bind failure
  throws at startup; the port does the same.

Naming beside the user's servers (`serversFor`): chord's goes last, as
`chord`, or the first free `chord-2`, `chord-3`, … when a user server it
is given is named so; only to an agent whose `initialize` advertised
`mcpCapabilities.http`; otherwise held back with `own: true` in
`chord/held_back`.

### Package trial

The first trial (Dart 3.13.5, macOS arm64, scratch directory, deleted):
two tokens with different tool sets, tokens added and revoked at run
time, a 40 s call and an open GET stream across a revoke, a 200 s call,
JSON and SSE replies; each package built with `dart compile exe` and driven
with curl from the binary.

| Package | Version, publisher, last published | Streamable HTTP server | Own `HttpServer` in front | Per-token tools | Revoke closes in-flight | AOT |
| --- | --- | --- | --- | --- | --- | --- |
| `mcp_dart` | 2.4.4, leehack.com, 2026-11-16 | yes, `StreamableHTTPServerTransport`, the TypeScript SDK's shape | yes, `handleRequest(HttpRequest, parsedBody)` | yes, one `McpServer` per MCP session | yes, GET stream and the 40 s call ended within 2 s; handlers see `extra.signal` | 7.6 MB, every check ran |
| `dart_mcp` | 0.5.2, labs.dart.dev, 2026-06-29 | no HTTP transport; `MCPServer.fromStreamChannel` | only by writing the HTTP layer ourselves | yes | yes, with our glue | 6.6 MB, ran |
| `mcp_server` | 3.1.1, makemind.dev, 2026-11-02 | yes, but it owns the listener; handler private | no | no: global registry, both tokens listed every tool | no: the in-flight call hung until the client timed out | 6.9 MB, ran |

Not tried: `mcp` 0.0.1 (unlisted), `fastmcp` 0.1.14 (last published
2025-11), `agentic_mcp` 0.3.1, `mcp_models` (models only), `dart_mcp_server`
(an application).

`mcp_dart` fits in the original's own pattern: the original puts its own
handler (bearer, session map, 401/403/404/400) before the SDK's
per-session transport and builds one `McpServer` per `initialize` from the
caller's role; with `mcp_dart` the same layer is about a hundred lines in
`lib/server/server.dart` over `HttpServer.bind(loopbackIPv4, 0)` with
`idleTimeout = null`. Its high-level `StreamableMcpServer` is not used
(its factory never sees the request). `dart_mcp` would make us own all of
Streamable HTTP and returns stack traces with source paths in a thrown
handler's result; `mcp_server` cannot carry per-caller tools, binds no
session to a token and hangs in-flight calls on revoke.

### Reproducible comparison with the original's SDK

`docs/design/evidence/CTUI-35/mcp_trial/` holds a small trial anyone can
rerun (README with commands and versions): the same admission layer and
the same three tools (`send_message` in both schemas, `close_agent`,
`clear_agent`) served once with `mcp_dart` 2.4.4 (JIT and AOT) and once
with the original's `@modelcontextprotocol/sdk` 1.32.2 and zod under bun,
driven by one Deno script with the same requests, valid and malformed;
`results/` holds both sides' normalised answers and the differences.

Same on both sides, from real runs (`results/ts.json`, `results/dart.json`,
`results/dart_exe.json`; the AOT binary answers exactly as `dart run`):
the four admission refusals (code, words, `id: null`); all five tool
answers including `structuredContent`; an unknown extra argument accepted
(neither schema sets `additionalProperties`); `required` order
`["to","text"]`; `execution: {"taskSupport": "forbidden"}` on every tool;
negotiated `protocolVersion` 2025-11-25 and `serverInfo`; revoke closing
the token's sessions, 401 after, the other token unaffected.

Every difference (`mcp_dart` | original SDK), grouped by what an agent
could see:

- **Tool calls an agent makes**
  - A tool not in the caller's set (a task calling `close_agent`) or
    unknown: JSON-RPC error `{"code": -32602, "message": "Tool
    'close_agent' not found"}` | tool result `isError: true`, text `MCP
    error -32602: Tool close_agent not found`.
  - Missing argument: both `isError: true`; `Invalid arguments for tool
    'send_message': JsonSchemaValidationException: Required property is
    missing: text (at )` | `MCP error -32602: Input validation error:
    Invalid arguments for tool send_message: Invalid input: expected
    string, received undefined at text`.
  - Wrong type (`to: 5`): `… JsonSchemaValidationException: Value does not
    match schema type string (at to)` | `… Invalid input: expected string,
    received number at to`.
- **What the agent reads at start**
  - `initialize` capabilities: `"tools": {}` | `"tools": {"listChanged":
    true}`.
  - `tools/list` `inputSchema`: no `$schema`, property members
    `description` then `type` | `"$schema":
    "http://json-schema.org/draft-07/schema#"` first, `type` then
    `description`.
- **Transport edges, no agent's call**
  - Batch `[ping, tools/list]`: 400 -32600 `Invalid Request: Batch
    JSON-RPC payloads are not supported` | 200 with both answers
    (`mcp_dart`'s `rejectBatchJsonRpcPayloads` defaults on).
  - Unsupported `MCP-Protocol-Version`: 400 -32022 `Unsupported protocol
    version` with `data` | 400 -32000 `Bad Request: Unsupported protocol
    version: 1999-01-01 (supported versions: …)`.
  - Malformed JSON: -32700 `Parse error` with a `FormatException` in
    `data`, no `id` | -32700 `Parse error: Invalid JSON`, `id: null`; no
    `jsonrpc`: -32600 `Invalid Request` | -32700 `Parse error: Invalid
    JSON-RPC message`.
  - 406, 415, 405 and re-initialize: same codes and words; the request's
    `id` or no `id` member | `id: null`.
  - Unknown method: `Method not found: no/such_method` | `Method not
    found`.
  - `content-type` carries `; charset=utf-8` (also on empty 202/200
    bodies) | none on the SDK's; JSON member order differs.

Found while building it: `mcp_dart` has no `onsessionclosed`, and
`McpServer.connect()` replaces `transport.onclose`; the trial chains its
own hook after `connect()` so a DELETEd session leaves the admission map
(without it a request after DELETE reached the closed transport). This is
our layer's own bookkeeping, as the original's `onsessionclosed` is, and
the design keeps it. `mcp_dart` defaults DNS-rebinding protection and
strict protocol-version checks on; loopback requests are admitted. The
trial's Dart package excludes itself from the repository's `dart analyze`
(its dependencies are fetched only when it runs).

None of these is settled here: the choices are the owner's (open
question 1).

## 2. Session hosting (question 2)

### Mapping

| Original | Port | Kind | Tested |
| --- | --- | --- | --- |
| `agent_name.ts` | `lib/agent_name.dart` | pure | directly |
| `session/window_agents.ts` | `lib/session/window_agents.dart` | pure: `WindowAgents<C>` and its functions (`openMain`, `openChild`, `closeChild`, `forgetClosed`, `pick`, `movePick`, `attend`, `hear`, `ownedBy`, `ownChildren`, `messageRecipients`, `childName`, `takenNames`, `childEnded`, `maxChildren = 8`) | directly |
| `session/open_agents.ts` | `lib/session/open_agents.dart` | effect shell over `WindowAgents<C extends Driven>`: start on open, close on close, `closeAll` joins every close (earlier ones too), one aggregate error | stub `Driven` |
| `session/tasks.ts` | `lib/session/tasks.dart` | pure state machine `TaskAgent` over `TaskParent`/`TaskSession`; `taskUpdate`, `taskSpent`, `reportOf`, `taskName`, `wrapMessage`, `unwrapMessage`, `fromLine`, `senderName` | directly, stub session |
| `session/new_args.ts` | `lib/session/new_args.dart` | pure | directly |
| `session/agents_host.ts` | `lib/session/agents_host.dart` | effects: `OpenAgents`, the `early`/`clearing`/`parts` maps, tasks by id, `Runtimes`, the `WindowView` the server reads, admission per launch | scripted sessions, fake `ChordServer`; the fake |
| `session/upstream.ts` (`CHORD_COMMANDS`, `commandOf`, `commandsIfNone`, `childSession`, `agentStateOf`, `agentUpdate`) | `lib/session/upstream.dart` | pure | directly |
| `session/upstream_commands.ts` | `lib/session/upstream_commands.dart` | pure text | directly |
| `acp/host_fold.ts` | `lib/acp/host_fold.dart` | pure | directly |
| `server/tools.ts` | `lib/server/tools.dart` | pure answers, schemas, `toolsOf`, `toolNames`, `serve` | directly, fake `WindowView` |
| `server/runtimes.ts` | `lib/server/runtimes.dart` | effect, injected `Probe` | stub probe, fake_async |
| `server/server.ts` | `lib/server/server.dart` | effect: HTTP, admission, MCP sessions | loopback HTTP client; AOT test |

`ChordServer` is an interface (`url`, `admit`, `revoke`, `close`) so the
host runs with a fake server or none, as the original's tests do.

The host keeps the original's shape: a class over mutable maps reacting
to conversation events, as `createAgentsHost` is. Its races (a clear while
a child starts, a close while an effort waits, a stale caller after
`/clear`) are written against those maps (CHD-476, CHD-373); what is pure
is lifted out and tested directly: `window_agents`, `tasks`, tool answers,
`childEnded`, the `noChild` words, `startRefusal`'s checks as a function of
offer and args, the dropped-messages sentence.

### Children's processes

- Every child is its own `Conversation` over its own `Session`, opened by
  the same `SessionOpener` the window uses: its own process, its own
  process group, stopped with `StopBounds`. Nothing new in the platform
  layer.
- Admission per launch: the token is made in the conversation's open
  callback (a `/clear` or `clear_agent` launches again) and revoked when
  that launch is let go (`cleared` or `closing`), when its open fails, and
  when its session's exit completes. A cleared child's old calls get 401;
  a call already in a handler sees `caller.launch.valid() == false` and
  answers `Your session was cleared or closed; nothing more goes from it`.
- Start failure: `connect_failed` refuses an effort-waiting `open_agent`,
  and main is told, from `chord`, `<name> (<runtime>) did not start:
  <step words><failure note><sign-in note> It takes no messages;
  open_agent starts another.`; the row stays `✗ failed to start`.
- Exit and failed turn (`childEnded`): `disconnected` tells main
  `<name>'s agent exited[: <last words>]. open_agent opens it again.`; a
  failed turn with the agent alive, `<name>'s turn failed: <error>. It is
  still open; send_message reaches it.`
- Eight children: `fullRefusal` counts `ownChildren`, refusing `This
  session has 8 agents open; close_agent one first` before anything starts.
- Close (`dropChild`): a busy turn is interrupted first, a running `!`
  command stopped, the spend kept under the child's key until its close
  settles (`spend_closing`/`spend_closed`), the conversation closed,
  `session_closed` told, and `agents_unfocused` with the last child. Main
  hears nothing of its own `close_agent`; on the person's `x`: `The person
  closed <name> (<runtime · model>, id <id>). It takes no more messages;
  open_agent starts another.`
- `/clear` on a picked child and `clear_agent` (`clearChild`): what
  arrives is held in `early` while the fresh session starts; the person's
  own queued prompts go back into that child's box (`queueBack`); its
  command stops; the old launch's spend is kept under a retired key; it
  settles on `connected` (held messages go in then), `connect_failed` or
  `closing` (dropped and counted: `N queued message(s) from a and b
  was/were not delivered.`). The person's clear tells main `The person
  cleared <name>'s context (<runtime · model>, id <id>). It is open with a
  fresh session and knows nothing of earlier turns; your next message is
  its first.[ dropped]`. A second clear while one runs: `it is being
  cleared already`.
- Window close: `closeAll` closes main and every child at once and waits
  for all, earlier ones included, within the window's quit bound; the exit
  kill takes any group left. Tasks close with their parent conversation
  (`TaskAgent.close`: `cancelled`, no report).

### Held starts and cancellation (finding 10)

What the original does, followed as it is:

- `open_agent` and `spawn_task` pass the `Caller` to the host **without**
  the MCP request's `extra.signal` (only `get_budgets`, `run_team`,
  `propose_team`, `settings` and a lead's member open forward it,
  `tools.ts` lines ~1124, 1559, 1612, 1667, 1725). `openAgent` calls
  `startChild` with no `launch`, so a cancelled MCP request neither
  refuses nor stops the child: it keeps starting, takes its first prompt,
  and the cancelled request's answer goes nowhere.
- Launch invalidation is required and separate: `stale(caller)` (the
  caller's own launch let go by `/clear`, `clear_agent` or close) answers
  `STALE` before any start; `spawn` and `openAgent` also answer `STALE`
  when the caller's session changed while `startRefusal` awaited the offer
  (`parent?.session !== session`). After a child has started it belongs to
  main's agents: main's `/clear`, `/resume` or quit close it with main.
- `captureLaunch` with the request signal is `run_team`'s (CTUI-37).

## 3. One ordered event path (finding 2)

Today `StartConnection` owns main's `Conversation` and folds its events
into `app` synchronously in `_heard`, and the window folds what it
dispatches. With many agents the original has one path: `OpenAgents`
hears every conversation's event, folds it into that agent's wait state
(`hear`), then calls the host port `heard(key, event, wait)` at once and in
order; the window turns it into the action it dispatches. A closing
session's late events go through `closingHeard(key, event)`; a replay runs
inside `replayed(key, replay)` so the driver folds it as one batch; the
host reads back through `stateOf(key)`.

The port's shape:

- `StartConnection` keeps what is per process: the forced-exit owner
  (`closeOnForcedExit`), the start page's `StartState`, the opener
  (`SessionOpener`, command, env, `Starting`, MCP servers, resume), the
  record drain. It stops owning a `Conversation`: it becomes the opener
  the host's `conversation(agent, emit, key)` callback calls for main, and
  the same opener is used for each child with that child's runtime,
  `Starting` and `Caller` admission.
- The host owns every `Conversation`. Its port is implemented by one
  `WindowFold` (the window's, in `lib/ui/app/`) that holds
  `ValueNotifier` state for every key. `heard`, `closingHeard` and
  `replayed` fold synchronously in the order delivered, into the agent of
  `key`, whether it is shown or not; a dispatch from a key goes into the
  same fold under the picked key. `stateOf(key)` reads that fold. In the
  original the window's fold lags its dispatches until it next draws
  (`AgentsPort.stateOf`'s comment), while `chord acp`'s `host_fold` does
  not lag. The port's window already folds synchronously in `_heard`, so
  its `stateOf` does not lag either; this differs from the original's
  window only in being fresher, and is listed in open questions.
  Interface's draft writes the state projection (what is per agent, what is
  window-wide); this section fixes only the path.
- Per session effects: the record (one `FileRecording` each), the
  process, the token, timers in its `Conversation`, its `!` command
  (`stopCommand(key)`), its queue. Window-wide: the server, `Runtimes`,
  the terminal, the clipboard, notifications.
- Async results that land later (a model or effort picked, the editor's
  text, a completion or file search, an image paste, a resume list) carry
  `(key, launch)` taken when they started; `launch` is the agent's
  generation, bumped on `cleared` and `closing`. A result whose key is
  closed or whose launch has moved is dropped. The window's current
  single-session guards (`_publicationGeneration`, `mounted`, `closing`)
  generalise to this pair.

Tests (scripted sessions, through the tester): updates of a hidden child
fold and draw when picked; a switch while an editor result or model pick is
out drops it from the wrong agent; `/clear` of a hidden child keeps its
spend and drops its async results; a late `closingHeard` spend after
`session_closed` still counts in the total.

## 4. Messages and asks (question 3, finding 1)

### 4.1 Asks of tasks: identity and the route back

The original's rule: a task's permission, form or question is shown in
the parent's session and answered there; the parent keeps
`#foreign: Map<askId, TaskAgent>`; `choose`, `reject` and `answer` look
the id up there first and forward to the task's own conversation, else
settle their own. This is safe only because ids are UUIDs, unique across
every session. The port follows it:

- Identity: every permission and elicitation (forms, links and the
  questions that ride on forms) gets a UUID v4 at its source, as the
  original; plan asks already do (`plan_asks.dart`). The id the parent
  sees is the task's own id, unchanged; the ask carries
  `subagentId: <task id>` (permission: `permission.subagentId ?? task id`;
  elicitation: the task id), which draws it in the task's block and lets
  ACP name the child.
- Route back: parent `Conversation._foreign[id] = task`, set when the
  relayed `permission_requested`/`elicitation_requested` passes through
  `_relay`, deleted on the relayed `*_settled`. An ask relayed with no
  parent turn running holds the parent's queue (`_foreignBetween`) as its
  own would, released on settlement.
- Settlement and withdrawal: the task's own conversation settles its asks
  (answered, or withdrawn by its turn's end, an interrupt or its close),
  and `TaskAgent.heard` relays `*_settled` to the parent while it runs.
  When the task ends, `TaskParent.ended` → `_forget(task)` deletes every
  `_foreign` entry of that task and releases any queue it held. A stop
  interrupts the task's turn, whose `_withdrawAsks` settles its asks before
  the turn's result ends the task, so the parent's box closes. On an exit
  the order of the task's withdrawal and its `disconnected` is not shown in
  the original's code (`TaskAgent.heard` ignores everything after its end);
  the port checks it against the original's fake (`agentexit` shape with an
  ask open) and follows what the original does; if the box stays open
  there, that is a question for the owner, not a fix of ours.
- Late answers: an answer for an id no longer in `_foreign` and not the
  parent's own is ignored (`_settle` finds nothing), as the original.
- Plans: the original's `TaskAgent.heard` relays no plan ask (no case for
  it), and `TaskSession` has no plan answer, so a task's plan approval is
  not shown in the parent. The port follows; listed in open questions.
- `chord acp`: the ask goes to the client under the composite id of the
  child (`asksIn`, `upstreamIdOf`); see section 8.

Tests: two tasks and the parent each raise an ask whose source-local
counter would have been the same (scripted sessions that make the
asks); all three pending in the parent; answering one task's leaves the
other two pending and reaches only that task; closing the other task
withdraws its ask and leaves the parent's pending; a late answer to the
closed task's id changes nothing. The same in `chord acp` (two child
asks and main's, answered over the wire out of order).

### 4.2 Messages

`Conversation` gains the original's entries:

- `deliver(from, text, [part])`: a turn of its own, wrapped
  `<message from="name · runtime[ · report|failed]">…</message>`, queued
  behind a running turn as a prompt is. A child's first prompt, chord's
  notes (`from: chord`), a task's report.
- `tell(from, text, [queued])`: while a turn of chord's runs on an agent
  that steers (`_session/steering`), into that turn through the same
  `_steer` the person's steers use: held for the calls open as it came on
  an agent whose steer cuts calls (`afterCalls`), held for the person's
  answer while the turn waits on a permission, form or link
  (`afterAnswer`, released into the turn after the answer); refused, or
  the turn ended on the way, it goes as the next turn and calls `queued`
  so the sender's `→` row is served again as queued (`servedLater`). Not
  steerable: `deliver`. Answer `sent` or `queued`; null before the session
  is up or once closing, which the host words `<name> is closing; nothing
  reaches it`.
- A steer the agent answers by starting a turn of its own: that turn is
  cancelled and the message goes as the next turn. The port does this for
  the person's steers already; messages take the same path with their
  sender kept on the re-queued prompt.
- `QueuedPrompt` gains `from` (`MessageFrom`: name, runtime, reachable,
  note), so held messages draw `← from @main · after the running calls: …`
  and Esc never takes another's message into the box. A message from
  another is kept in `_incoming` until it goes out, so a clear counts it
  dropped.
- Delivery once: a message is one `QueuedPrompt`, moved, never copied,
  between held, steering and queued; the record writes it once, as the
  `prompt` line with `from` (and `into` when steered) when the agent took
  it. A child still starting holds messages in the host's `early`; on
  `connected` the first is `deliver`ed (its first turn) and the rest
  `tell` into that turn, after `connected` is drawn (a microtask).
- The sender's `→` row is the `served` call, recorded as a `served` line.

## 5. Tools: one matrix and every answer (finding 11)

### Who has which tool (this task)

| Tool | main (role `person`) | long-lived child (`child`, `agent` set) | task (`child`, `task` set) |
| --- | --- | --- | --- |
| `list_agents` | yes | yes | no |
| `list_sessions` | yes | no | no |
| `spawn_task` | yes | yes | no |
| `open_agent` | yes | no | no |
| `send_message` | `{to, text}`: to a child it opened | `{text}`: to its parent | `{text}`: to its parent |
| `close_agent` | `{to}`: its child or its task | `{to}`: only its own tasks (own description and schema) | no |
| `clear_agent` | yes | no | no |

`toolsOf(caller)` registers exactly these; `toolNames(role)` gives
`/mcp`'s list (main's seven; a child's four, as only long-lived children
are picked). The original's other tools (`get_budgets`, `list_teams`,
`run_team`, `propose_team`, `settings`, monitors) and its lead/member
branches are added by their tasks (section 9).

### Answers and refusals, as the original words them

- Every answer goes through `serve`: the caller's session is told the
  call (`served`: `{tool, input, answer | error, task?, asked?, queued?}`;
  `task` for a `spawn_task` answer with an id; `queued: true` for a
  `send_message` answered `queued`); an `{error}` becomes `isError: true`
  with the text; otherwise the value as two-space JSON text, or, with
  `said`, the words plus `structuredContent` (close and clear).
- `list_agents {agent?}`: without `agent`, every runtime with what is
  known, probing nothing; unknown runtime: note `chord knows no runtime
  named X; list_agents without an agent names every one`; not read:
  `models and modes not read yet; list_agents with agent "X" reads them`;
  failed: `models and modes could not be read: <error>` (`it did not open a
  session within 60 s`, `it offers no models or modes`, a refused
  command's words).
- `list_sessions`: `{sessions: [{id|null, runtime, model|null, you?,
  agents?: [{id, name, runtime, model|null}]}]}`; `you` on main's for a
  person caller.
- `spawn_task {agent, model?, effort?, prompt, name?}`: `{id, name, agent,
  model?, effort?, note?}`; refusals from `startRefusal`: `This session is
  closing; no task can start from it`, `No agent named X; chord knows a,
  b`, a refused command's words, `X offers no model M; it offers a, b`;
  `This session has closed`; `STALE`.
- `open_agent {agent, model?, effort?, prompt, name?}`: `{id (8 hex),
  name, agent, model?, effort?, note?}`; refusals: `An agent name must not
  contain …`, the `startRefusal` ones with `agent`, `This session has 8
  agents open; close_agent one first`, `This session has closed`, `STALE`.
- `send_message` (main): `{delivered: sent|queued, to}`; `No agent X is
  open in this session; list_sessions names them`, `X is closed;
  open_agent starts another`, `X was closed when this session was left;
  open_agent starts another`, `X is closing; nothing reaches it`.
  `send_message` (child or task): `{delivered}`; `The session that opened
  you has closed`, `You are closed; nothing more reaches your parent`,
  `Your task has ended; nothing more reaches its parent`, `The session
  that started you has closed`.
- `close_agent`: `{closed: name}` (JSON text, `structuredContent`);
  `{ended: name}` → `X has already ended` with `structuredContent`; `N of
  your tasks are named X; close_agent one by its id: a, b and c`; a child
  caller with no such task: `No task X of yours; spawn_task's answer names
  them`; main: the `noChild` words.
- `clear_agent`: `X (id I) has a fresh session; it knows nothing of
  earlier turns.[ dropped]` with `structuredContent {cleared, id,
  dropped?}`; `Could not clear X: <why>[. dropped]`; the `noChild` words.
- Descriptions and input schemas are the original's text, field for
  field; the trial (section 1) compares the generated schemas.

## 6. `spawn_task` (question 4)

- `TaskAgent` relays its conversation's events into the parent's stream
  under the task id: a `subagent_update` with `chord/task` (name, runtime,
  model, effort) on start and when its effort is known, its updates and
  served calls with `subagentId`, its asks as in 4.1, its `warned` and
  pre-send `failed` named `<task>: …`.
- Ends on its first turn: `completed` (report: the last agent message of
  that turn, `(no report)` if empty), `failed`, `cancelled`;
  `disconnected` (`<runtime> exited`); `connect_failed` → `failed`. The end
  update carries `chord/spent` (tokens from the turn's answer, cost from
  its last `usage_update`, `estimated` when chord worked it out) and
  `chord/stopped`. The report goes to the parent as `deliver({name,
  runtime, note: report|failed}, text)`; the task closes. A stopped task
  sends no report; a stop by the person adds the aside `The person
  stopped this task before it reported.` ahead of the next prompt.
- Esc on the parent cancels its tasks; `close_agent` on a task cancels it
  naming the caller (`chord/stopped` says who).
- Model required (start fails without it), effort never required: the
  answer waits on the start and says the effort it is on and the refusal
  note.

## 7. `list_agents` and runtimes (question 5)

`Runtimes` (injected `Probe`): an offer kept per runtime for the window;
`heard` from main's open session of that runtime; a read probes by opening
a session with no MCP servers and closing it, one read per runtime at a
time, bounded by `probeMs = 60000`; a failed read is not cached; `close()`
aborts every read, which closes their sessions; a refused runtime
(CHD-466) is never started. Tests: stub `Probe`, `fake_async` for the
bound, a shared read, a retry after failure, close mid-read.

## 8. `chord acp` (question 7, finding 3)

`agents: 1` is advertised in `initialize` only when everything below is
built and tested; until then `_chord/agents/*` stay -32601.

- **Host fold** (`lib/acp/host_fold.dart`, the original's
  `acp/host_fold.ts`): `foldEvent(fold, event)` folds each event into a
  `FoldedSession {transcript, queue}` synchronously, before the host or the
  server reads it (`stateOf` returns `entry.folds[key]`); `cleared` resets
  it to `noFold`; events that are no transcript action leave it as it is.
  A list of non-action event types is kept beside it, checked by a test
  that fails when a new event type is neither (the original makes `bun
  check` fail).
- **Upstream capabilities from the client**: `subagents` read from the
  client's `initialize` `clientCapabilities`; a child's or task's
  permission, form or plan for a client without them is refused: `chord:
  refused a subagent's permission|form|plan: the client takes no
  subagents` on stderr, the permission rejected, the form cancelled, the
  plan answered `cancelled` (original `acp_agent.ts` ~552, ~604, ~622).
- **Alias and route lifecycle**: a child's route is made on first need
  (`routeOf`): `parent` (main's upstream id), `upstreamId =
  <parent>/<child id>`, `held` events. Its `UpstreamSession` is
  `childSession(agentId, upstreamId)` with `nested: true`, set on
  `connected`; events before it are held and flushed in order; `cleared`
  drops the session, stop reason, gone, failed and held; `connect_failed`
  sets `failed`, `disconnected` sets `gone`; close tells a last
  `subagent_update` with `closed: true` and deletes the route. A task's
  and an adapter's subagent ids map by `children` in the upstream session,
  looked up exactly (`childOf`), never parsed.
- **Child state**: each child's `subagent_update` (via `agentUpdate`)
  carries `title`, `state` from `agentStateOf(fold, stopReason)`
  (`requires_action` when a plan ask is open or it waits on a permission or
  input; `running` while busy; `idle` with the stop reason), runtime,
  model, effort, mode, gone, failed; sent only when its JSON changed.
  Main's `_chord/session/state` takes `requires_action` from its own fold.
- **`_chord/agents/send {sessionId, prompt}`**: the open, not-gone child;
  failed start → session not found; clearing or starting → -32603 `<name>
  is being cleared|starting; send once its subagent_update says idle`;
  the prompt checked as a prompt (`promptOf` refusals → invalid params);
  `{delivery: sent|queued}` by whether its fold was idle.
- **`_chord/agents/close {sessionId}`**: a task named by its composite id
  cancelled (`{closed: [name]}`) or ended (`{closed: [], ended: [name]}`);
  a long-lived child closed as the person's `x` (`{closed: [name]}`).
- **`session/cancel` on a child**: a long-lived one's turn stops and it
  stays open; a task of chord's ends (`x`); an adapter's subagent is
  stopped by its agent.
- **`/new` in the command list**: `chordCommands` holds `new` (`Open a new
  agent beside main`, hint `[agent] [--name <name>]`); `team` is CTUI-37's.
  Main's `available_commands_update` is rewritten with chord's first and
  the agent's after, a name both have being chord's; a child's list is its
  own. An agent that sends none gets chord's once (`commandsIfNone`, on
  `connected`), as the original. This replaces CTUI-56's "no commands of
  our own until M4".
- **`/new [agent] --name <name>`** as a prompt alone: `newTyped`; refused
  with text alone (`notAloneRefusal`); refusals as a `failed` command
  chunk; otherwise the opened text; main gets the aside `The person opened
  @<name> (<agent>) with /new; it has no prompt yet. It reports to you, and
  send_message reaches it.` and a `ran` call (`open_agent`, `typed:
  '/new'`).

Wire tests (`chord acp` through the in-memory client, and through the
fake): each bullet above; a client with and without `subagents`; a child
route held before `connected` then flushed in order; clear resets the
route; `requires_action` on a child's and main's state; `/new` injected
both when the agent sends commands and when it sends none; two requests
from the client with the same id on two sessions (served and answered per
session, as CTUI-56's keyed asks); `_chord/agents/*` -32601 until the
advertisement.

## 9. Seams (question 8, the lead's decision)

Carried now, because records already hold them: `ChildInfo.team`, `lead`,
`forkedFrom`, and `Caller.role`. Nothing else: no `FORK_REFUSED`, no
lead/member branches in `toolsOf`, no monitor registry.

- CTUI-36 plugs in at `toolsOf` (adds `monitor`, `stop_monitor`,
  `list_monitors` to main and long-lived children), at `WindowView`
  (`monitor`, `stopMonitor`, `monitors` keyed by the caller's `key` and
  `agent`), at `dropChild`/`clearChild`/main's close (stop the owner's
  monitors), at `MessageFrom` (a `monitor` sender), and at `initialize`
  (`monitors: 1`, `_chord/monitors/*`).
- CTUI-74 plugs in at `Caller` (adds `fork`), at the three tools that
  refuse a fork (`open_agent`, `close_agent`, `clear_agent`), at
  `parentOf` (a fork has none), and at `view.sessions()` (forks beside
  main), using the `forkedFrom` field carried now.
- CTUI-37 plugs in at `toolsOf` (lead and member branches), at `Caller`
  (`team`), at `teamTell`, `openMember`, `runTeam`, `chordCommands`
  (`team`), and at the roster's lead/member rows, using `team`/`lead`.

## 10. Concurrency and failure scenarios

| Scenario | Expected outcome | Where tested |
| --- | --- | --- |
| 1000 child updates between two frames | each folds into its own agent's state in order; the window draws once per frame | host, scripted children; benchmark |
| Two children stream while main works | independent folds; picked agent drawn; unseen news on the others | host + tester |
| `open_agent` with effort; child hangs in start; MCP request cancelled | the child keeps starting (original passes no request signal); the late answer goes nowhere | host, scripted child that never answers `session/new` |
| Main `/clear` while a child's `open_agent` awaits the offer | `STALE`; nothing starts; the old token 401 | host |
| Message to a child still starting | held in `early`; first as its turn, the rest into it, after `connected` | host |
| Message to a child whose start failed | `<name> is closing; nothing reaches it` | host |
| Message while the recipient waits on permission | held `afterAnswer`, into the turn after the answer | conversation, scripted session |
| Steer refused / turn ended on the way | next turn; sender's row served again as queued | conversation |
| Agent starts its own turn on a steer | that turn cancelled; message goes next | conversation |
| Two tasks and the parent ask at once | three pending asks, distinct ids; each answer reaches its asker only | conversation, scripted sessions; ACP |
| Task ends with an ask open | its asks forgotten in the parent, queue released | conversation |
| Child exits mid-turn | `✗ exited`; main told; token revoked | host; fake `agentexit` |
| Child turn fails | main told; child stays open | host; fake `agentfail` |
| Child floods | its own inbox; no cross-child blocking | scripted child |
| Ninth child | refused before start | host |
| `clear_agent` with messages queued | dropped and counted in the answer | host |
| Close while clearing | clear settles `it was closed`, held counted | host |
| Esc during tasks | cancelled, no report, aside before the next prompt | tasks + host |
| Revoked token mid-handler | new requests 401; the running handler answers `STALE` | server + host |
| Tool waits minutes on the person | stream kept (`idleTimeout = null`); a 200 s call completed in the trial | server test |
| Handler throws | 500 `Internal error` or the package's `isError`; nothing on stdout/stderr | server test |
| Window quit with children working | turns interrupted, groups stopped within `StopBounds`, aggregate error on failures, exit kill of leftovers | open_agents unit; compile pty test |
| Hidden child cleared while an async result is out | result dropped by `(key, launch)` | tester |
| `list_agents` probe never answers | `did not open a session within 60 s`; not cached | runtimes, fake_async |

## 11. Test plan

- **Never a real agent (finding 6).** One test catalog,
  `test/fixtures/runtimes.dart`: every runtime name a test admits maps to
  the fake (bun, `../chord/tests/fixtures/fake_agent/main.ts`) or to a
  scripted opener; any other name throws in the opener before a process
  starts. The catalog runs in an isolated environment: `HOME`,
  `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME` and the settings
  files in a temporary directory; `CHORD_FAKE_CHILD_RUNTIME=fake` always
  set (the fake's `CHILD_RUNTIME` defaults to `codex`, which `agentother`
  opens). `fakeSessionOpener` takes its command only from the catalog. A
  test opens a child named after a real catalog runtime (`codex`) and
  asserts the opener refused it and no process started. The fake's
  `agentmentions` (it calls `run_team`) is not used; the `@@` roster is
  tested with a scripted roster.
- **Pure, direct:** `agent_name_test`, `window_agents_test`, `tasks_test`,
  `new_args_test`, `tools_test` (the matrix, each answer and refusal,
  `structuredContent`, `served` metadata), `upstream_test` (commands,
  child sessions, `agentStateOf`), `upstream_commands_test`,
  `host_fold_test`, `servers_test` (`chord-2`, held back without `http`),
  record splice tests on fixture records.
- **Effects with stand-ins:** `open_agents_test` (stub `Driven`),
  `runtimes_test` (stub `Probe`, fake_async), `agents_host_test`
  (scripted sessions, fake `ChordServer` recording admit/revoke),
  conversation tests for messages and foreign asks.
- **The server:** `server_test` over loopback: the four refusal codes,
  per-token tool lists, revoke closing sessions and in-flight calls,
  `close`; a compile-tagged test serving from an AOT binary.
- **End to end through the fake**: its MCP client is the TypeScript SDK's
  `StreamableHTTPClientTransport`, so these prove wire compatibility.
  Scenarios: `agents`, `agentsquiet`, `agentsheld[gated]`, `agenttask`,
  `agentcost`, `agentlong`, `agentexit`, `agentfail`, `agentlate`,
  `agentcall[gated|twice]`, `agentother` (child runtime set to `fake`),
  `scenarios/tasks.ts`, `scenarios/efforts.ts`. No new scenario.
- **The window** through `package:chorded_tui/testing.dart` with the host
  on scripted sessions; the event-path tests of section 3.
- **`chord acp`**: the wire tests of section 8.
- Records in isolated `XDG_STATE_HOME` always.

## 12. Records and resume (question 6)

Per child: its own record, header with `parent` (the parent's agent
session id), `name`, and `task` (a task's id) or `id` (a long-lived
child's), plus `team` (CTUI-37). Per message: the recipient's `prompt`
line with `from` and, when steered, `into`; the sender's `served` line.
Per close while the session goes on: `closed` with the child's id. Left
open at quit, `/clear` or `/resume`: no line; the resumed transcript's
`left_open` names them and `noChild` says `<name> was closed when this
session was left; open_agent starts another`; they are never reopened.

Resume of a parent: `childPasts` reads the records whose header's `parent`
is the parent's id; task pasts are spliced after the line that started
each task's block (the parent keeps only start and end); a task whose
record has gone keeps the bare block. Messages draw from `prompt` lines'
`from`. The splice is pure (fixture records); the scan is an effect on an
isolated `XDG_STATE_HOME`, run in the record worker's isolate when it is
large.

## 13. Unit split (my part, ordered)

Each unit names the test that fails without it.

1. **Ask ids as UUIDs** (permissions, elicitations). `conversation`:
   two sources' first asks have distinct ids; `elicitation_tester_test`
   updated.
2. **`agent_name`, `new_args`, `window_agents`, `open_agents`** (pure
   state, `closeAll`). Their unit tests.
3. **Runtime offers** (`runtimes.dart`, `agentsAnswer`). `runtimes_test`:
   bound, shared read, retry, close.
4. **Tool contracts** (`tools.dart`: matrix, schemas, answers, refusals,
   `serve`, `structuredContent`, `served` metadata) against a fake
   `WindowView`. `tools_test`.
5. **Server** (`server.dart` over `mcp_dart`, admission, revoke, close).
   `server_test`; AOT serve test.
6. **`serversFor` with chord's server**. `servers_test` `chord-2`,
   held-back cases.
7. **Test runtime catalog** (finding 6). The "real runtime never runs"
   test.
8. **One event path** (`StartConnection` as opener, `WindowFold`,
   `(key, launch)` guards). Hidden-child fold, switch during async work.
9. **Messages in `Conversation`** (`deliver`, `tell`, `from`, held,
   steer, queued, record `from`/`into`). Conversation tests on a scripted
   session.
10. **Host: open and start failure** (admission per launch, early
    messages, the `did not start` note). `agents_host_test` start
    cases; fake `agents`.
11. **Host: exit and failed-turn notes**. Fake `agentexit`,
    `agentfail`; `childEnded` unit.
12. **Host: close and the eight-child limit** (`dropChild`, person's
    `x` note, `agents_unfocused`). Ninth-child refusal; close note.
13. **Host: clear and `clear_agent`** with held-message counting.
    Dropped-count cases; close while clearing.
14. **Host: closing spend** (`spend_closing`/`spend_closed`, retired
    keys). Late `closingHeard` spend counts.
15. **Tasks** (`tasks.dart`, task meta, `spawn_task`, foreign asks, Esc,
    report, spend). `tasks_test`; the two-tasks-and-parent ask test; fake
    `agenttask`, `tasks.ts`, `efforts.ts`.
16. **Records and resume of children**. Splice tests; resume on
    isolated state.
17. **`chord acp`: host fold, routes, capabilities, refusals, child
    state**. Section 8 wire tests.
18. **`chord acp`: `_chord/agents/send|close`, cancel, `/new` and the
    command list, then the `agents` advertisement**. Their wire tests;
    -32601 gone only here.

## 14. Open questions

1. **For the owner: `mcp_dart` 2.4.4 and its differences from the
   original's SDK** (section 1, with examples). Take the package, pinned
   exactly, behind our own listener (recommended over writing Streamable
   HTTP ourselves or our own MCP server). For the differences, by group:
   - Tool calls (tool not in the role answered as a JSON-RPC error rather
     than `isError`; validation words): (a) accept the package's answers
     and record them; (b) answer these in our own words before the
     package sees them (a check of the tool name against the role and our
     own argument validation in each handler), which is code around the
     package; (c) ask upstream for SDK-compatible answers and accept (a)
     until then.
   - Start (`listChanged`, `$schema` and member order): (a) accept; (b)
     where the package takes it as configuration (declared capabilities,
     a literal `$schema` in our schema maps), set it to the original's,
     checked by the trial before it is used; (c) leave both.
   - Transport edges (batch, protocol-version error, parse errors, `id`
     member, charset): (a) accept; (b) `rejectBatchJsonRpcPayloads:
     false` to serve batches as the SDK does, the rest accepted.
2. Plans of tasks: the original does not relay a task's plan approval to
   the parent (`TaskAgent.heard` has no case), so a task that asks for one
   waits unseen until it is stopped. Follow (designed so), or show it?
3. A task's ask open when its agent exits: the parent's box may stay open
   if the original's order is so (section 4.1); checked against the fake,
   and asked if it does.
4. The window's `stateOf` is fresher than the original's (no lag until
   the next draw). Accept, as it changes no wording or order the person
   sees, or reproduce the lag?
5. `chord acp`'s command list gets `new` now and `team` with CTUI-37,
   while the original lists both together; a client sees one entry, then
   two. Accept the split, as CTUI-56 already split them?
