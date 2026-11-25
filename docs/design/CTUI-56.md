# CTUI-56: `chord acp`, a multi-session ACP server on stdio

`chord acp [agent]` serves ACP v1 on its own stdin and stdout, without a
window: an ACP client starts chord as its agent, and chord starts the real
agent, one process per session, adding its records, settings, queue, titles
and the `_chord/session/*` extensions. The specification is `../chord`:
`docs/guide.md` ("`chord acp`"), `src/acp_agent.ts`,
`src/acp/{agent_app,stdio,upstream_turns}.ts`,
`src/session/{upstream,auth_status,servers,place,initial_options}.ts` and
their tests (`tests/acp_agent_test.ts`, `tests/acp_extensions_test.ts`,
`tests/acp_process_test.ts`, `tests/session/upstream*_test.ts`).

The design was drafted by the framework, interface and runtime architects
and reviewed by the critic; the drafts are the record, under
`docs/design/evidence/CTUI-56/drafts/`. Where this document and a draft
disagree, this document holds. The interface draft (sections 2 to 7) is the
method-by-method contract with every error word; this document does not
repeat it line for line, and amends it where section 11 says so.

Nothing in the framework (`lib/`) changes. Everything is port code under
`example/chord/`.

## 1. Scope

In:

- `initialize`, `session/new`, `session/list`, `session/load`,
  `session/resume`, `session/close`, `session/prompt` and its queue,
  `session/cancel`, `$/cancel_request`, `session/set_config_option`,
  `session/set_mode`, `session/set_title`, `auth/status` with
  `auth/status_update`.
- `_chord/session/state` and `_chord/session/steer`, for main sessions;
  `initialize` advertises only these two extensions (owner).
- Relayed permissions; the elicitation relay (`elicitation/create`,
  `elicitation/complete`) for `chord acp` sessions (owner, O3).
- Capability-gated `session/update`, live and replayed; tool-call `session`
  references stripped or aliased; duplicate live ids aliased (`s1~2`).
- The session-layer pieces the contract needs and the port lacks: image and
  embedded-resource prompts, renames, the agent's account, client MCP
  servers filtered by what the agent takes, generic initial config options,
  downstream capabilities per open, and a raw ACP past for load (owner, O1).
- The CLI (`chord acp`, its flags, the by-hand note), the way out (EOF,
  broken output, an oversized line, a crash, SIGINT/SIGTERM/SIGHUP) and
  exit codes.

Out, each with where it goes:

- Children, teams, tasks, monitors; `_chord/agents/*`,
  `_chord/monitors/*`; `/team` and `/new`, so chord adds no commands of its
  own and every slash command goes to the agent as typed: M4/M5 (CTUI-35,
  CTUI-37). Seams in section 10.
- Settings' and `.mcp.json` MCP servers, for the window, `-p` and `chord
  acp` alike: CTUI-34.
- Plan approvals (`cursor/create_plan`, `x.ai/exit_plan_mode` as
  `session/request_permission`): CTUI-63. Until then they stay `cancelled`,
  as the window does.
- Elicitation forms in the window and `-p`'s declines: CTUI-33. The window
  keeps cancelling forms.
- Filesystem and terminal requests: never relayed, as the original.

## 2. What a client sees

There is no screen: the 120x40 and 80x24 checks do not apply, no key is
bound, and the shortcuts panel gains nothing. stdout carries protocol and
nothing else; every diagnostic is a `chord: ` line on stderr.

### 2.1 `initialize`

The first call's `clientCapabilities` are kept for the connection. It starts
no agent.

```json
{
  "protocolVersion": 1,
  "agentInfo": { "name": "chord", "version": "<version.dart>" },
  "authMethods": [],
  "agentCapabilities": {
    "loadSession": true,
    "promptCapabilities": { "image": true, "audio": false, "embeddedContext": true },
    "mcpCapabilities": { "http": true, "sse": true },
    "auth": { "status": {} },
    "sessionCapabilities": { "list": {}, "resume": {}, "close": {}, "title": {} }
  },
  "_meta": {
    "chord/acp": {
      "version": 1,
      "extensions": { "session/state": 1, "session/steer": 1 },
      "agent": { "name": "<startup agent>" }
    }
  }
}
```

The original's answer is the same with `agents` and `monitors` in
`extensions`; those methods are -32601 until M4.

### 2.2 Methods, in brief

| Method | Does | Errors |
| --- | --- | --- |
| `session/new` | one agent process in `cwd`; answers when it is up, with `configOptions` and `_meta["chord/acp"]` (`image`, `embeddedContext` of that agent) and `_meta["chord/held_back"]` when a server was held back | -32603 closing or a refused start; -32602 an `acp` transport; -32000 sign-in; -32800 cancelled |
| `session/list` | this agent's records, optional `cwd`, one page | |
| `session/load` | reopen, replay the past, then answer | -32602 already open here, wrong `cwd`, record of another agent |
| `session/resume` | reopen, no replay | as load |
| `session/close` | stop the agent, keep the record, answer bound prompts `cancelled` | -32002 |
| `session/prompt` | queue, answer when its own turn ends | -32002, -32602 blocks, -32603 |
| `session/cancel` | interrupt, withdraw queued client prompts and open asks | none (notification) |
| `$/cancel_request` | cancel the named request only | none |
| `session/set_config_option` | set a select option, answer every `configOptions` | -32602, agent's own refusal |
| `session/set_mode` | set the mode; the change goes as `config_option_update` | as above |
| `session/set_title` | live: rename, the agent's answer wins; listed: pending rename | -32602 empty, -32002 unknown |
| `auth/status` | the oldest live main session's account, else `unknown` | |
| `_chord/session/steer` | `{delivery: sent}` into a running turn, else `queued` | -32602, -32002, -32603 |
| anything else | | -32601 |

Notifications chord sends: `session/update` (gated, 2.3),
`_chord/session/state` (on change; `running` with `origin`
`client`/`message`/`agent`, `requires_action`, `idle`), `auth/status_update`
(on a deep change), `elicitation/complete`, `$/cancel_request` (an ask
withdrawn). Requests: `session/request_permission`, `elicitation/create`.

`auth/status` reads the oldest live main session first and answers
`unknown` when that one has heard no account, even if a newer one has
(amends interface section 2, critic 9).

### 2.3 The gate

A pure function of the client's declared capabilities and the update kind,
the same live and on load (`reaches`):

| Update | Client must declare |
| --- | --- |
| text, thoughts, tool calls, `plan`, commands, `config_option_update`, `session_info_update`, `usage_update` | nothing |
| `subagent_update`, `session_message`, `session_message_chunk` | `subagents` |
| `plan_update`, `plan_removed` | `plan` |
| `compaction_update`, `compaction_summary_chunk` | `session.compaction` |
| `notice` | `session.notices` |
| anything outside the v1 schema, `current_mode_update` included | never |

Dropped updates stay in the record. Tool-call `session` references are
rewritten to announced aliases with `subagents`, removed otherwise.

### 2.4 What chord declares toward the agent (owner, O2 and O3)

For `chord acp` sessions only, through the session's open options: `plan`,
`session.compaction`, `elicitation: { form: {}, url: {} }`, and
`session.notices` when the client declared it. Not `subagents` and not
`_meta.terminal_output_delta` (M4). The window and `-p` keep declaring
nothing (CTUI-12) and keep cancelling forms.

Records written by `chord acp` may hold kinds the window does not draw yet;
the window's replay already omits unsupported updates (CTUI-26), and a test
pins that.

### 2.5 CLI

`chord acp [agent] [--agent-command <command>] [-m|--model <id>]
[--effort <id>] [--permission-mode <id>] [--no-mcp-servers] [-h|--help]`,
with the original's help words (interface draft section 7).

| Case | Exit | stdout | stderr |
| --- | --- | --- | --- |
| unknown agent | 2 | empty | the unknown-agent line |
| unknown option, `--nope` | 2 | empty | `Could not find an option named "--nope".` (owner, O5) |
| `--agent-command` without a value | 2 | empty | `chord: ...` |
| refused startup command in the launch directory | 1 | empty | `chord: <refusal>` |
| EOF after clean cleanup | 0 | | |
| EOF unclean, broken stdout, line over 32 MiB, crash | 1 | | |
| SIGINT / SIGTERM / SIGHUP | by that signal | | |

The port's `refuse()` writes help to stdout; the `acp` path never does. The
by-hand note goes to stderr only when stdin is a terminal.

## 3. Modules

Named after the original's files.

| Port (`example/chord/lib/`) | Original | Content |
| --- | --- | --- |
| `acp_agent.dart` | `src/acp_agent.ts` | `runAcp`, `AcpHost`, `AcpEntry`, `byHandNote` |
| `acp/agent_app.dart` | `src/acp/agent_app.ts` | the method table and params checkers on `ClientRequests` |
| `acp/stdio.dart` | `src/acp/stdio.ts` | `Output`: the stdout writer with `expect`, `drained`, `failed` |
| `acp/rpc.dart` (extended) | the SDK's connection | the shared `Incoming` core, `AgentRequests` on it, `ClientRequests`, a serving `route`; `ChordRequests` sends `$/cancel_request` on withdrawal |
| `acp/upstream_turns.dart` | `src/acp/upstream_turns.ts` | pure: `Turns`, `reduceTurns`, `turnOf`, `sessionStateOf` |
| `session/upstream.dart` | `src/session/upstream.ts` | pure: `UpstreamSession`, `reaches`, `aliasFor`, `mapUpdate`, `configOptionsOf`, `configSetter`, `configChange`, `answeredConfig`, `messageChunk`, `permissionAnswerOf`, `elicitationReplyOf`, `promptOf` |
| `session/auth_status.dart` | `src/session/auth_status.ts` | pure: `AccountState`, `foldAccount` |
| `session/servers.dart` | `src/session/servers.ts` | pure: `HeldBack`, `serversFor` |
| `session/place.dart` | `src/session/place.ts` | per-`cwd` settings, the launch directory's read once |
| `session/leaving.dart` (extended) | `src/session/leaving.ts` | `Leaving` (`createLeaving`) beside the window's `leave()` |
| `platform/signals.dart` (moved) | `main.tsx` | `dieBySignal`, `raiseSignal`, out of `ui/app/renderer.dart` |
| `cli.dart`, `bin/chord.dart` (extended) | `src/cli.ts`, `main.tsx` | the `acp` word, its flags, the branch before any terminal |

Not ported in this task: `host_fold.ts`, `agents_host.ts`,
`upstream_commands.ts`, `new_args.ts`, `team_command.ts` (M4/M5);
`plans.ts`/`plan_asks.ts` (CTUI-63).

Reused unchanged: `acp/wire.dart` (`LineDecoder`, 32 MiB cap,
`MessageTooLargeError`), `acp/process.dart` (stop ladder, process groups,
`MemoryAgentProcess`), `acp/connection.dart`, `session/sessions.dart`,
`record.dart`/`record_worker.dart`, `settings.dart`, `platform/process.dart`.

## 4. The wire

### 4.1 Reading

stdin's bytes go through `LineDecoder`. Each decoded message is dispatched
synchronously and in order before the next line is decoded, so a
`$/cancel_request` never overtakes the request it names, and a handler's
synchronous part runs before any later line. A framing error is answered
(-32700, -32600) and reading goes on; the reader never waits for that answer
to be written (owner, O6: the original's stall behind a full stdout is not
reproduced, and the port's guide says so). A line over 32 MiB is `broken`;
stdin's end is `eof`.

### 4.2 The dispatcher (owner, O8)

`json_rpc_2`'s `Peer`/`Server` does not fit the serving side: a handler never
sees its request id, there is no per-request cancellation, no hook for an
answer having been written, it serves batches, and its error words are not
the SDK's. The serving side is ours, in `rpc.dart`: one `Incoming` core
(envelope and id checks, a `CancellationToken` per running id, `$/cancel_request`
by JSON-RPC id equality, one answer per id) under both the existing
`AgentRequests` (refactored onto it in the same unit, its tests the guard)
and the new `ClientRequests`. chord's requests to the client keep
`json_rpc_2`'s `Client` through `ChordRequests`, which gains one thing: when
an ask's token is cancelled it sends `$/cancel_request` to the client, as the
original's SDK does on an aborted outbound request.

Params are checked by our own code, answering -32602 with zod's issue list
in zod's words for the fields chord reads (owner, O7; as CTUI-29 did for
settings).

### 4.3 Answer order (critic 7)

Correctness does not rest on when a Future completes. `ClientRequests` has
two kinds of handler:

- **Immediate**: returns the result (or throws) synchronously or as a
  Future; the dispatcher enqueues the answer when it has it. Used where no
  notification depends on the answer's position (`list`, `set_*`, `close`,
  `auth/status`, `steer`, `initialize`).
- **Deferred**: the handler returns nothing and the host answers later
  through `respond(id, result)` / `fail(id, error)`, which enqueue the
  answer line on `Output` synchronously, in the same call stack. `session/prompt`,
  `session/new`, `load` and `resume` are deferred.

So a turn's `ResultAction`, heard after the turn's updates, enqueues the
prompt's answer at once through the turn table, and an update heard after
it goes after it on the wire. A new session's held updates wait for the
answer's line to be flushed (`Output.expect(id)`), as the original waits for
the write; a load's past is enqueued before its answer.

### 4.4 Writing

`Output` is one FIFO and one pump: take everything queued, one `add`, one
`flush`, settle the written futures of those lines, repeat. `expect(id)`
settles once the line answering `id` is flushed or nothing more can be
written; `drained()` once every expected answer is; `failed` on a flush
error (EPIPE: Dart ignores SIGPIPE), which starts the way out as `broken`.
The queue is unbounded, as the original's: a client that stops reading holds
output in memory. The sink is injected, so tests hold, fail and count it.

## 5. The host

`AcpHost` (in `acp_agent.dart`) holds the tables and touches IO only through
ports it is given (`Output`, `ChordRequests`, `open` for a session, `place`,
`readRecords`, the clock). Its shape is framework draft section 3.1, with
these changes:

- **Asks are keyed per entry (critic 1).** The port's permission ids are
  per bridge (`permission-1` in every session); the original's are UUIDs.
  Each `AcpEntry` holds its own `asks` map by the conversation's local ask
  id; the JSON-RPC id of the request to the client is allocated by
  `ChordRequests`, separately. Settle, withdraw and a late answer all go
  through `(entry, localId)`.
- **One ask set for state.** Main's `requires_action` is "the entry has an
  open ask" (permission or form); `host_fold` comes with M4's children. No
  second counter.
- **Prompt answers** are the turn table's: `session/prompt` binds its
  request id to a caller-chosen turn id before `Conversation.send` (which
  can emit before it returns), and the table's sends call `respond`/`fail`.

Per entry: the conversation, `UpstreamSession` (client id, agent id, alias,
announced subagents, last config sent), `live`, `held`, `past`, the claimed
reopen id, `turns`, last state sent, its asks, its account, `closing`.
Server-wide: `sessions` (client id to entry), `reopening`, `entries` in
start order (the account source is the first not gone, not closing, with a
session), `capabilities`, the last account told, `Leaving`.

The event path: every `ConversationEvent` goes through `heard(entry,
event)`, synchronously: a pure `turnInputOf(event)` into `reduceTurns`, an
update through `mapUpdate` to `Output` or dropped, a config change through
`configChange`, asks raised or withdrawn, connection events, then
`tellState` and, on account events, `tellAccount`.

## 6. Concurrency and cancellation

One isolate. Ordering invariants (runtime draft 3.2): nothing names a
session id before the client has it; a load's past before its answer; a
turn's updates before its answer, later updates at once; state after what
caused it, only on change, never before `live` or after close; bind before
send; claim before await.

The prompt queue is `Conversation`'s own. Turns nobody prompted run with
`origin: agent` and answer nothing.

The cancellation matrix is runtime draft 3.4, unchanged: `session/cancel`
interrupts and answers every queued bound prompt `cancelled`;
`$/cancel_request` on a queued prompt removes it alone, on the running one
cancels that turn; on a new/load/resume still reading, nothing starts and
-32800; still starting, the entry is closed, then -32800; on other methods
it is ignored. A connection's end is not a client cancel. An agent that
ignores a cancel leaves the prompt pending with no timer, until
`session/close`.

**Admission (critic 4).** `session/new`, `load` and `resume` check
`leaving.started` at the start and again after every `await` (records read,
place read) before a process is started; once leaving has started nothing is
admitted (-32603 `chord is closing`). An opening admitted before the way out
is an entry in `entries` from the moment its process starts, so the way out's
close steps own it.

**Steer.** Bind, send with the turn id, then `steerQueued(turnId)` steers
that request's own entry: `sent` answers `{delivery: sent}`, anything else
`queued`; a queued steer runs as its own client turn with no echo. A steer
refused by the agent returns to its place and is answered once.

**Asks.** A client error answer is a refusal (permission: reject; form:
cancel) with a stderr line. A late answer after withdrawal finds nothing.
The port's `Conversation.close` emits nothing after `Closing`, so the host
withdraws an entry's asks itself when it closes it; the wire matches the
original's.

**Elicitation (owner, O3).** For `chord acp` sessions, `rpc.dart`'s
`elicitation/create` branch becomes a handler like permissions, routed
through the session to the host: a session-scoped form or URL request goes
to the client raw (no scheme check, as the original), a request-scoped one
or one naming an unannounced session is cancelled, an error or unknown
action answer is `cancel`, `session/cancel` and close withdraw it, and the
agent's `elicitation/complete` is forwarded. Forms count for
`requires_action`. The window's sessions keep the `cancel` answer.

## 7. Load, resume and the past

1. -32603 when closing; id live or claimed: -32602 `Session <id> is
   already open here.`
2. Claim the id in `reopening` before any `await`; release it in `finally`.
3. Read records; a record of another agent or a `ResumeError`: -32602; a
   different `cwd`: -32602 `Session <id> is in <cwd>.` An id with no record
   goes to the agent unchanged (the original loads unrecorded ids by id).
4. Re-check admission; read the place; open with `resume`.
5. Load: relay the past through the gate, then answer, then what was held.
   Resume: answer with nothing replayed. A pending rename is sent to the
   agent on this open where it takes titles; a hung rename leaves the
   session usable. No `_chord/session/state` for the replay.

**The raw past (critic 3).** `HistoryReplayed` carries transcript actions,
which merge user chunks and drop links and unsupported updates, so it cannot
feed `mapUpdate`. `Session` gains a raw ACP past alongside the window's
projection, from whichever source the open uses, never both: the record's
`prompt` (with `from`), `update`, `renamed` and `left_open` events, or, for
an id chord never recorded, the updates the agent sends during its own
`session/load`. The window's projection stays as it is.

**Settings per `cwd` (critic 10).** As `place.ts`: the launch directory's
settings are loaded once at start; any other `cwd` is read on each call.

**Records from two processes (critic 11).** Two processes may open and
append to one record, as the original allows. No guarantee is made that
their lines never interleave or tear.

## 8. Opening a session: servers, config, capabilities

**Client MCP servers (critic 5, owner O1).** The pure policy of
`servers.ts` is ported: after the agent's `initialize`, each client server
goes or is held back by its transport (stdio always; `http`, `sse` as the
agent advertises), and `--no-mcp-servers` holds back all. `chord/held_back`
entries have the original's shape: `{ server, agent, transport, takes,
from?, own? }`. With no settings' servers and no chord server in the port,
the client's servers are the only ones (difference, CTUI-34).

**Initial config options (critic 2).** `initial_options.dart` today takes
only model, effort and mode and drops everything for an unknown adapter.
As `initial_options.ts`: a client's `configOptions` entries go unchanged to
an agent that advertises `options`, merged by `configId` over chord's
starting values (the client's win); chord reads them back by id and sets the
values not current; a refusal, or a read-back still reporting another value,
fails `session/new` and stops its process group. An agent without `options`
gets them set after it opens.

**Downstream capabilities and asks (critic 8).** The session's open options
gain `capabilities` (2.4), `notices` (tied to the client's declaration) and
an elicitation handler; `openSession` passes them to `openAgent` and to the
request dispatcher. The window passes none, so nothing changes for it.

## 9. The way out

As `leaving.ts`, runtime draft section 4: one way out whatever starts it;
`started` holds from the first trigger and every request after it is -32603;
the 15 s deadline armed first; on a signal or crash only, prompts answered
`cancelled`, asks withdrawn and pending opens rejected; then, in one tick,
the connection step (drain at most 500 ms, close the wire) and one close
step per entry, in parallel; then `ProcessGroups.killAll()` and the exit.
At the deadline the unsettled steps are named on stderr and every group is
killed. Exit: EOF 0 if clean else 1; broken, oversized, crash 1; a signal
dies by that signal (`raiseSignal`, moved to `platform/signals.dart`).
`exit()` does not flush stdout, so the drain is the only flush. What holds:
every process group chord spawned has stopped or been sent SIGKILL on every
way out that runs.

## 10. Where M4 plugs in

1. `AcpEntry.conversation` becomes the host's main when `agents_host` is
   ported; `heard` gains `childHeard` beside it.
2. `UpstreamSession.children` and `mapUpdate`'s subagent argument exist now
   for the agent's own subagents.
3. `session/prompt` calls a `commandOf` hook that returns null in this
   scope; M4 and M5 fill it with `/new` and `/team` and the `chord/command`
   replies, and `commandsIfNone` merges chord's commands into the list.
4. `session/cancel` on a non-main id falls to `cancelledIn`, false now.
5. Asks take an asker (conversation and upstream view), so a child's ask
   plugs in; the `subagents` refusal path exists for main's nested asks.
6. `Leaving` takes more steps (chord's MCP server, resource readers).
7. The extensions map is one const; M4 adds `agents` and `monitors` and
   their methods, and `host_fold`.

## 11. Differences from the original

| Difference | Why | Decided by |
| --- | --- | --- |
| Extensions: only `session/state`, `session/steer` | children and monitors are M4 | owner |
| No `/team`, `/new`; no `commandsIfNone` list; an agent with no command list gets none from chord | M4/M5 | owner, lead |
| No settings' or `.mcp.json` MCP servers | the port has none anywhere yet; CTUI-34 | owner (O1) |
| Downstream capabilities: no `subagents`, no terminal deltas | M4 | owner (O2) |
| Plan approvals answered `cancelled` | CTUI-63 | owner (O4) |
| `chord acp --nope` refused with `args`' words; `--nope --agent-command x` refused too | a Cliffy quirk is not copied; the port's guide states the port's line | owner (O5) |
| No malformed-line stall behind a full stdout | an SDK artefact; the port's guide says so | owner (O6) |
| Our own serving dispatcher | `json_rpc_2` shown not to fit | owner (O8) |
| Answers count as written per flush, not per write callback | same observable `expect`/`drained` | lead |
| The host withdraws asks on close itself | `Conversation.close` emits nothing after `Closing`; same wire | lead |

Amendments to the drafts: interface section 2 `auth/status` (2.2 above),
load step 3 (a record of another agent, not "no record"); framework S11/F5
(section 7), the `Completer.sync` ordering (4.3), the global asks map (5),
`host_fold` (deferred); runtime 3.6 asks keying (5), section 5 settings per
`cwd` and record-write guarantee (7), and its unit split (12).

## 12. Build units, in order

Each unit is one branch's commits with its tests; tests never reach a real
agent. "Fake" means the original's fake agent through
`test/fixtures/fake.dart`, skipped with a reason without bun or the
checkout; records under an isolated `XDG_STATE_HOME`.

Foundations (independent of each other):

1. **U1 Way out.** `Leaving` in `session/leaving.dart`; `dieBySignal` and
   `raiseSignal` moved to `platform/signals.dart`, the window's imports
   updated. Tests: `leaving_test.dart` under `fake_async` (each reason's
   exit, the deadline names a hung step and kills groups through an injected
   `ProcessGroups`, the 500 ms drain against a never-flushing sink, answers
   only on signal or crash, a second trigger joins); the window's tests stay
   green.
2. **U2 Dispatcher and output.** The `Incoming` core, `AgentRequests` on it,
   `ClientRequests` with immediate and deferred handlers, the serving
   `route`, `ChordRequests` sending `$/cancel_request` on withdrawal,
   `acp/stdio.dart`'s `Output`. Tests: the existing `rpc` tests unchanged;
   -32600/-32601/-32602 shapes, `$/cancel_request` by id (`1` vs `"1"`),
   notifications unanswered, a deferred `respond` followed in the same stack
   by a notification lands first on the wire; `expect`/`drained`/`failed` on
   a held and a failing sink; batching.
3. **U3 Pure upstream.** `upstream_turns.dart`, `session/upstream.dart`, the
   params checkers in zod's words. Tests: the original's reducer and
   upstream tests ported, including the steered-turn ones; the gate table;
   aliases; config shapes; prompt blocks and their refusals.

Session layer (before the server; each keeps the window's tests green):

4. **U4 Turn seams.** `Conversation.send` with a caller-chosen `turnId`;
   `steerQueued(turnId)`; `turnInputOf(ConversationEvent)`. Tests: a turn id
   bound before an idle send's synchronous emit; a steer takes its own entry,
   not the one queued ahead.
5. **U5 Prompt content.** Images, embedded resources and resource links
   through `send`, in the original's order; `takesImages`,
   `takesEmbeddedContext`; records keep `uri` and `mimeType` only. Tests in
   memory and with the fake's `resources` and `links` scenarios.
6. **U6 Titles.** `Conversation.rename`, the `renamed` record event written,
   `recordPendingRename`, the pending rename sent on reopen. Tests with the
   fake's `titles` scenario; a hung rename leaves the session usable.
7. **U7 Account.** `auth_status.dart`, the agent's `auth/status` and its
   pushes folded per session. Tests with the fake's `accounts` scenario.
8. **U8 Open options.** `servers.dart`'s `serversFor` and `HeldBack`; client
   servers and `--no-mcp-servers` through `openSession`; generic initial
   config entries, merge, read-back and failure; downstream `capabilities`,
   `notices` and an elicitation handler passed to `openAgent` and the
   dispatcher. Tests: a stdio-only and an HTTP/SSE agent against client
   servers, held-back shape; an unknown adapter with `options` gets client
   entries unchanged, one without gets post-open sets, client over startup,
   a refused or mismatched entry fails the open and stops its group; the
   downstream `initialize` inspected with and without the options; the
   window's open declares nothing.
9. **U9 Raw past.** The raw ACP past from records and from an agent's own
   load replay, one source per open. Tests: a record with a gated update
   the window omits, links, `from` and renames comes out whole; an
   unrecorded id loaded through the agent; resume yields none.

Server (in order):

10. **U10 Sessions.** `runAcp`/`AcpHost` with `initialize`, `session/new`,
    `list`, `close`, the held gate, aliases, place (launch directory read
    once), admission re-checked after each await, failed starts and
    sign-in, -32603 while closing, the way out wired to the entries. Tests
    in memory (no line names an id before its answer; two duplicate ids
    alias; a signal while place is held admits nothing and leaves no
    process) and through the fake.
11. **U11 Turns and asks.** `session/prompt`, the queue, `session/cancel`,
    `$/cancel_request`, permission relay, elicitation relay,
    `_chord/session/state`, `_chord/session/steer`. Tests: every row of
    the cancellation matrix; two sessions both asking their first
    permission, one answered and the other closed, late answers touching
    neither; a form relayed, a request-scoped one cancelled, withdrawn on
    cancel, a late `elicitation/complete`; state transitions; steer sent,
    queued, own entry, answered once; through the fake's `permissions`,
    `review_permissions` and `misbehaving` scenarios.
12. **U12 Config, titles, account.** `set_config_option`, `set_mode`,
    `set_title` (live and listed), `auth/status` and `auth/status_update`.
    Tests: an agent refusal returned unchanged; two sessions where the
    oldest has no account and the newer has one: `unknown` until the oldest
    closes; through the fake's `modes`, `titles` and `accounts`.
13. **U13 Load and resume.** Claims, past before answer through the gate,
    pending renames, already open, wrong `cwd`, a window record reopened by
    `chord acp` and back. Tests in memory and through the fake.
14. **U14 CLI and binary.** `chord acp` parsing, help, the by-hand note,
    real stdio, signals, the crash zone, exits; the port's README
    (`chord acp` section with the port's `--nope` line and the stall
    difference), `docs/FEATURES.md`'s row, AGENTS.md's commands. Tests:
    `cli_acp_test.dart`; tag `compile`: each signal ends the binary by that
    signal with no agent group left, EOF 0, a closed stdout 1, `--nope` 2
    with empty stdout, the note only with a terminal, no stdout byte that is
    not a JSON line.
15. **U15 Benchmark.** `benchmark/acp_server.dart`, no terminal: N sessions
    by M updates to a counting sink, a 32 MiB prompt line against a ping on
    another session, a load of a 10k-update record. Numbers in the handover;
    an isolate for decoding only if they call for it.

U1 to U3 can go in parallel, and U4 to U9 in parallel after them where
files allow; U10 to U14 in order; U15 last.

## 13. Note, 2026-11-18: `session/cancel` between turns (main)

This amends 2.2 and §6; the text above stands as written. Main decided that
`session/cancel` follows the original: it is `conversation.interrupt()` and
nothing more. An agent's permission or form is withdrawn only through a
turn's or a cycle's cancel, so one asked between turns stays pending after a
`session/cancel`; the ACP client answers its own pending requests.

2.2's `session/cancel` row, "interrupt, withdraw queued client prompts and
open asks", and §6's "`session/cancel` and close withdraw it" hold only while
a turn or a cycle runs. Close and the way out (§9) still withdraw every open
ask, between turns too.

The window agrees: Esc on a request held between turns, before ctrl+x a has
taken the keys, leaves it waiting, as the original's does (captures
`evidence/CTUI-56/u11b-*`).
