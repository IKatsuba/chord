# CTUI-56 interface draft: the wire contract of `chord acp`

Author: interface. Answers brief questions 4 to 8, with the owner's
decisions on Q5 and Q6 already applied (see "Owner decisions taken"). Sources:
`../chord/docs/guide.md` ("`chord acp`"), `src/acp_agent.ts`,
`src/acp/agent_app.ts`, `src/acp/upstream_turns.ts`, `src/session/upstream.ts`,
`src/main.tsx` (`serveAcp`), `tests/acp_agent_test.ts`,
`tests/acp_process_test.ts`; in this tree `example/chord/lib/acp/`,
`lib/session/`, `lib/cli.dart`, and the CTUI-12, CTUI-28 and CTUI-29 entries
of `docs/decisions.md`.

There is no screen. `chord acp` draws nothing; its only "screen" is stderr,
whose lines are listed in section 7. The 120x40 / 80x24 checks of AGENTS.md do
not apply; nothing here has a key, and the shortcuts panel gains nothing.

## 0. Owner decisions taken (from the lead, applied throughout)

- **Q6.** `_chord/session/state` and `_chord/session/steer` are in CTUI-56.
  `initialize` advertises only those two under
  `_meta["chord/acp"].extensions` until M4 adds `agents` and `monitors`.
- **Q5.** `/team` and `/new` follow the M4/M5 split: chord adds no commands of
  its own in this scope, and every slash command goes to the agent as typed.

## 1. The surface, one table

What the client may call, and what chord answers in CTUI-56. "Original" is
what `../chord` does; a difference is marked **D-n** and argued in section 8.

| Method | Kind | CTUI-56 | Differs |
| --- | --- | --- | --- |
| `initialize` | request | served | D-1 (extensions) |
| `session/new` | request | served | D-4 (settings MCP servers) |
| `session/list` | request | served | none |
| `session/load` | request | served | none |
| `session/resume` | request | served | none |
| `session/close` | request | served | none |
| `session/prompt` | request | served | D-2 (no chord commands) |
| `session/cancel` | notification | served, main only | children part waits for M4 |
| `$/cancel_request` | notification | served | none |
| `session/set_config_option` | request | served | none |
| `session/set_mode` | request | served | none |
| `session/set_title` | request | served | none (needs port seams, section 9) |
| `auth/status` | request | served | none (needs port seams, section 9) |
| `_chord/session/steer` | request | served | none |
| `_chord/agents/send`, `_chord/agents/close`, `_chord/monitors/stop` | request | -32601 | D-1, M4 |
| `authenticate`, `session/fork`, `session/delete`, `session/set_model`, `_session/steering`, `session/options`, anything else | request | -32601 | none |

What chord sends the client:

| Method | Kind | CTUI-56 | Differs |
| --- | --- | --- | --- |
| `session/update` | notification | served, gated (section 4) | D-3 (what upstream declares) |
| `_chord/session/state` | notification | served | none |
| `auth/status_update` | notification | served | none |
| `session/request_permission` | request | permissions; plan approvals per D-6 | D-6 |
| `elicitation/create`, `elicitation/complete` | request / notification | per D-5 | D-5 |
| `$/cancel_request` | notification | withdrawing an ask | none |
| `_chord/monitors/changed` | notification | never (no monitors) | M4 |
| `fs/*`, `terminal/*` | | never relayed | none |

## 2. Method by method (brief Q4)

Error words below are the SDK's, which the client may read: `-32601`
`"Method not found": <method>` with `data.method`; `-32602` `Invalid params:
<words>`; `-32002` `Resource not found` with `data.sessionId`; `-32800`
`Request cancelled`; `-32603 chord is closing`. The port's `rpc.dart` already
writes `-32601` in this exact form; the others must be matched literally,
since tests in `../chord` compare codes and some words.

### `initialize`

The first call's `clientCapabilities` are kept for the connection
(`capabilities ??=`): a second `initialize` is answered the same and does not
change them. It starts no agent. Answer, exactly (test "answers what the
design says, starting no agent"), with D-1 applied:

```json
{
  "protocolVersion": 1,
  "agentInfo": { "name": "chord", "version": "<chord's version>" },
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
      "agent": { "name": "<startup agent's name>" }
    }
  }
}
```

`agentInfo.version` is the port's `version.dart` value. `agent.name` is the
resolved startup agent (with `--agent-command`, the name it was given or the
default). `promptCapabilities` are chord's, not the agent's: the real ones
come per session in `_meta["chord/acp"]` of new/load/resume.

### `session/new`

Params: `cwd` (required), `mcpServers` (array, may be null), `configOptions`
(optional initial entries). Order of checks, as the original:

1. Shutting down: `-32603 chord is closing`.
2. Any client server with an `acp` transport: `-32602` with
   `MCP server <name> has an acp transport, which chord does not take from a client.`
3. The `cwd`'s place is read (settings layers for that directory; problems
   go to stderr once each). A startup refusal of the agent there (for
   example a refused `agents.<name>.command`): `-32603` with the refusal line.
4. A cancel (`$/cancel_request` on this request) that arrived while the place
   was read: `-32800`, and no agent starts.
5. Servers: settings' servers, then the client's, the client's winning by
   name (D-4 for what the port has of settings' servers).
6. One agent process is started; the answer waits until it is up.
   A `$/cancel_request` while it starts closes it (no group left) and
   answers `-32800`.

Failure to start: `-32603` with the step's words and `data.lines` (the
failure lines); a sign-in failure is `-32000` with the same shape, its lines
including what to run (`signInLines`). chord itself keeps serving.

Answer:

```json
{
  "sessionId": "<agent's id, or an alias like s1~2>",
  "configOptions": [ ...the one shape of section 5... ],
  "_meta": {
    "chord/acp": { "image": <agent takes images>, "embeddedContext": <agent takes resources> },
    "chord/held_back": [ ... ]      // only when a server was held back
  }
}
```

No `modes` and no `models` field: modes, models and efforts go only in
`configOptions` (test "the answer holds one configOptions; modes never go").
`chord/left_open` never appears on a new session.

Ids: the agent's id, unless it is live here or being reopened, then
`<id>~2`, `~3`, ... (`aliasFor`). Aliases are upstream-only: not recorded,
not listed, not reloadable.

Initial `configOptions`: passed unchanged to an agent that advertises
`options`; read back by id; values not current are then set; a refused
entry fails `session/new` (and the session is closed). An agent without
`options` gets them set after it opens. Ids the session does not list are
dropped silently.

Order on the wire: the answer first, then what the session said while
starting (held), then `config_option_update` if it moved since the answer,
then `_chord/session/state` if not idle, then the agent's
`available_commands_update` when it sends one (D-2: chord sends none of its
own).

### `session/list`

Params: optional `cwd` (a non-string is ignored, meaning all), optional
`cursor` ignored. Answer, one page, no `nextCursor`:

```json
{ "sessions": [ { "sessionId": "...", "cwd": "...", "title": "...", "updatedAt": "<ISO time>" } ] }
```

Only records of the startup agent. `title` is the stored title, falling back
to the first prompt with a leading chord aside omitted (`earlierSessions`'s
`prompt`, the same text `-r` shows). Sessions that are live here are listed
too, as records. Port: `sessions.dart` already computes this for `-r`; the
server only shapes it.

### `session/load` and `session/resume`

Params: `sessionId`, `cwd`, `mcpServers`. Checks, in order:

1. Shutting down: `-32603`.
2. The id is live here, or another load/resume of it is in flight:
   `-32602 Invalid params: Session <id> is already open here.`
3. No record of that id for this agent: `-32602` with `ResumeError`'s words.
   (A session never recorded can still be loaded by id if the agent knows
   it: test "a session chord never recorded is unlisted, but load by id
   reaches the agent". The runtime draft owns how.)
4. The record is in another directory: `-32602 Invalid params: Session <id> is in <cwd>.`
5. Then as `session/new` steps 2 to 6.

`load`: every recorded `prompt`, `update` and `renamed` event is relayed
before the answer, through the same gate as live updates:
a prompt as `user_message_chunk` (text, leading aside omitted, `chord/from`
when it was a message), an update as recorded, a rename as
`session_info_update { title }`. Then the answer. `resume`: no replay.

The answer is the `session/new` answer without `sessionId`, plus
`_meta["chord/left_open"]` when the record holds children left open (it may,
from a window session; chord does not restart them, as the original).
A pending rename recorded by `set_title` is sent to the agent on this open
where it supports titles. The reopened session keeps the id it was asked
for: no alias.

No `_chord/session/state` is sent for the replay (test "a load says nothing").

### `session/close`

Params: `sessionId`. Unknown or already closed: `-32002`. Shutting down:
`-32603`. Otherwise: the id leaves the table at once (a prompt to it is now
`-32002`), every bound `session/prompt` of it answers
`{ stopReason: "cancelled" }`, its asks are withdrawn with `$/cancel_request`,
the agent's process group is stopped, the record is kept. Answer `{}` after
the close. No `_chord/session/state` after it.

### `session/prompt`

Params: `sessionId`, `prompt` (content blocks). In order:

1. Shutting down: `-32603`.
2. Already cancelled by a `$/cancel_request` that came right behind it:
   `{ stopReason: "cancelled" }`.
3. Unknown or closed: `-32002`.
4. Blocks (`promptOf`), in order: `text` joined by `\n`; `image` needs the
   agent's `image`, else `-32602 Invalid params: <agent> does not take images`;
   `resource` needs `embeddedContext`, else `-32602 Invalid params: <agent>
   does not take embedded resources` and nothing is sent; `resource_link`
   always; any other kind, audio included,
   `-32602 Invalid params: A prompt cannot carry a <type> block.`
   Sent to the agent as text, then images, then resources, then links.
5. Queued behind the running turn if any; answered when its own turn ends:
   `{ stopReason, usage? }` (the agent's usage as given). A turn that failed
   is `-32603` with its message. The agent gone while it ran: the running
   one answers with its result when it comes, queued ones `-32002`.

Every slash command, `/team` and `/new` included, goes to the agent as typed
(D-2). The record keeps resources as `uri` and `mimeType` only (the port's
`SubmittedContent` already does).

`session/update`s of a turn go before its answer. Updates after the answer
go at once; the client must not assume an answer is the last word.

### `session/cancel`

Params: `sessionId`. A live main id: interrupts the running turn, withdraws
every queued client prompt (each answers `{ stopReason: "cancelled" }`),
withdraws open asks. Unknown ids are ignored (it is a notification). In M4
the same handler routes to a child; the seam is "not a main id: ask each
session's children" (`cancelledIn`), which in CTUI-56 finds nothing.

### `$/cancel_request`

Params: `requestId`. On a queued `session/prompt`: that prompt alone leaves
the queue and answers `{ stopReason: "cancelled" }`; the others stay. On the
running prompt: cancels that turn (as `session/cancel` does, but only that
request's turn). On a `session/new`/`load`/`resume` still starting: the start
is given up, `-32800`. On a request already answered: nothing. This needs the
request id in the handler, which `json_rpc_2`'s `Server` does not expose:
framework draft's call.

### `session/set_config_option`

Params: `sessionId`, `configId`, `value`. `-32603` when closing, `-32002` for
an unknown session. `-32602 Invalid params: No option <configId> takes that
value.` when the id is not in chord's list, the value is not a string, or
`type` is `boolean`. The mode option goes to the mode setter, the model
option to the model setter, others to the option setter. An agent refusal is
the error it gave (its code and words kept; a non-RPC error is `-32603` with
its message). Answer: `{ configOptions: [...] }`, the whole list, and the
client's copy is updated (no echoing `config_option_update` follows for the
same list).

### `session/set_mode`

Params: `sessionId`, `modeId`. As above for errors; answer `{}`; the change
reaches the client as `config_option_update` (never `current_mode_update`).

### `session/set_title`

Params: `sessionId`, `title`. Whitespace runs fold to one space, trimmed.
Empty: `-32602 Invalid params: The title is empty.` A live session: renamed
as the window renames (`renamed` recorded, the agent told where it supports
titles); the agent's answer wins (`{ title: <the agent's> }`); an agent
refusal is returned unchanged. A listed, not-open record of this agent:
a pending rename is recorded and `{ title }` returned. Otherwise `-32002`.

### `auth/status` and `auth/status_update`

`auth/status` (no params): the account of the oldest live main session that
heard one, else `{ state: "unknown" }`. Unknown state words read `unknown`.
`auth/status_update` with the same shape goes once per change of value
(compared deeply, key order ignored), including when the source session
closes or exits and the next one becomes the source. Nothing of it is
recorded.

### `_chord/session/steer` (in scope, Q6)

Params: `{ sessionId, prompt }`; a missing or ill-typed field, or a prompt
block whose known kind is malformed (for example a `resource` without
`uri`), is `-32602`. Unknown main id `-32002`; closing `-32603`. Blocks as
`session/prompt`. Answer `{ delivery: "sent" }` only when it went into a
running turn; otherwise `{ delivery: "queued" }`, and it runs as its own
turn with `origin: "client"`, no request waiting for it and no echo of its
words. It steers its own entry even with prompts queued ahead. An agent
without steering keeps it queued. The port's `Conversation.steerQueued`
already returns `sent`/`unsteerable`/`none` per entry, so this maps directly.

### `_chord/session/state` (in scope, Q6)

`{ sessionId, state, origin? }`: `running` with `origin` `client` (a client
prompt or a queued steer), `message` (a message starts a turn; no source of
one exists in CTUI-56 unless the port's inbox emits one, runtime to say), or
`agent` (the agent's own cycle, CTUI-59's cycles); `requires_action` while
main has a permission or form ask open (with the running turn's origin if
any); `idle` with no origin. Only changes go. None before the session's id
is answered, none during a load's replay, none after a close. Sent whatever
the client declared.

## 3. `_meta` keys a client sees in this scope

| Key | Where | CTUI-56 |
| --- | --- | --- |
| `chord/acp` | `initialize` answer; new/load/resume answers | yes |
| `chord/held_back` | new/load/resume answers | per D-4 |
| `chord/left_open` | load/resume answers | when a record holds it |
| `chord/from` | `user_message_chunk` of a turn no client began | only on load replay of window records and if the inbox has a source; runtime to say |
| `chord/filled` | `config_option_update` (`["configOptions"]`) | yes |
| `chord/permission` | relayed `session/request_permission`, as the agent sent | yes, passed whole |
| `chord/agent`, `chord/command` | | no (M4; D-2) |

## 4. The capability gate and reference stripping (brief Q4)

The gate is a pure function of the client's declared capabilities and the
update kind, applied identically live and on load (`reaches`):

| Update kind | Needs |
| --- | --- |
| `user_message_chunk`, `agent_message_chunk`, `agent_thought_chunk`, `tool_call`, `tool_call_update`, `plan`, `available_commands_update`, `config_option_update`, `session_info_update`, `usage_update` | nothing |
| `subagent_update`, `session_message`, `session_message_chunk` | `subagents` |
| `plan_update`, `plan_removed` | `plan` |
| `compaction_update`, `compaction_summary_chunk` | `session.compaction` |
| `notice` | `session.notices` |
| any other kind, `current_mode_update` included | never sent |

`config_option_update` and `current_mode_update` from the agent are never
relayed as sent: chord sends its own one shape (section 5) when the list
changes. Dropped updates stay in the record; there is no text fallback.

Tool calls: `content` items of `type: "session"` are rewritten to the alias
announced for that subagent (`<main>/<agentId>`) when the client declared
`subagents` and the subagent was announced on this session by a
`subagent_update`; every other `session` item is removed; other content and
the status stay. Subagent ids in `subagent_update` and in `session_message`'s
sender/recipient are rewritten the same way. In CTUI-56 this is an adapter's
own subagents only (Claude's tasks), and only if the agent was told
`subagents` (D-3). The function is the original's `mapUpdate`, pure, ported
whole so M4 plugs chord's children into the same `children` map.

## 5. Configuration, one shape

`configOptions` (answers and `config_option_update`): the mode option (id
from the agent's mode config option, else `mode`, `category: "mode"`), the
model option (id from the agent's, else `model`, `category: "model"`), then
the agent's other select options; all `type: "select"` with `currentValue`
and `options: [{ value, name }]`. Booleans never appear. An agent with only
legacy `modes`/`models` fields gets the same shape. A
`config_option_update` carries `_meta: { "chord/filled": ["configOptions"] }`
and goes only when the list differs (JSON-equal) from what the client last
had, whatever made it change.

## 6. Commands (brief Q5, decided)

- chord intercepts no prompt: `commandOf` is not ported in CTUI-56.
- `available_commands_update` is the agent's, relayed unchanged (gate:
  none). chord does not add `team` or `new`.
- An agent that sends no list: chord sends nothing. The original's
  `commandsIfNone` exists only to show chord's own two; with none, an empty
  `available_commands_update` would tell the client "no commands", which is
  not what the agent said. **Recommendation: send nothing** (owner to
  confirm, Q-O4).
- Seam for M4/M5: the prompt handler takes an optional interceptor
  (`ChordCommands? commands`) that, given a prompt's blocks, either returns
  nothing (goes to the agent) or a command's reply; and the update mapper
  takes the list of chord's own commands to merge (empty now). M4 fills both
  without touching the handler, and adds `chord/command` replies there.

## 7. CLI and stderr (brief Q8)

### Parsing

`chord acp [agent] [--agent-command <command>] [-m|--model <id>]
[--effort <id>] [--permission-mode <id>] [--no-mcp-servers] [-h|--help]`.
`acp` comes first; flags after it. `chord --agent-command ... acp` is the
window with an agent named `acp` (as the original says: it opens the
window). Help text, from the original's Cliffy command:

- command: `Serve ACP on stdin and stdout, for a client that starts chord as its agent; draws nothing.`
- `--agent-command`: `Start this ACP agent command instead of chord's own; [agent] only names it.`
- `-m, --model`: `Start each of [agent]'s sessions on this model, by its id for it.`
- `--effort`: `Start each of [agent]'s sessions on this effort, by its id for it.`
- `--permission-mode`: `Start each of [agent]'s sessions in this mode, by its id for it.`
- `--no-mcp-servers`: `Start each of [agent]'s sessions with no MCP servers, chord's own included.`

The port's `chordParser` gains an `acp` sub-parser beside `agents`, and the
top-level help's command list gains its line.

### Exit codes and what goes where

**stdout carries nothing but protocol, ever.** This is the one rule the
port's current `refuse()` breaks: it writes the help to stdout. For `acp`,
every usage error writes only to stderr (the original calls `throwErrors()`
for this reason). Pinned by `acp_process_test.ts`:

| Case | Exit | stdout | stderr |
| --- | --- | --- | --- |
| `chord acp no-such-agent` | 2 | empty | contains `Unknown agent "no-such-agent"` (port: `Unknown agent "no-such-agent". \`chord agents\` lists them.`) |
| `chord acp --nope` | 2 | empty | contains `"--nope"`: an unknown flag is read as `[agent]`, so it is the unknown-agent line naming `--nope` |
| `chord acp --nope --agent-command x` | serves | | `--nope` silently names the agent |
| `chord acp --agent-command` (no value) | 2 | empty | starts with `chord: ` |
| refused startup command in the launch directory | 1 | empty | `chord: <refusalLine>` |
| EOF after clean cleanup | 0 | | |
| EOF unclean, broken stdout, line over 32 MiB, crash | 1 | | |
| SIGINT / SIGTERM / SIGHUP | by the signal | | |

`--nope` read as an agent is Cliffy's behaviour, not a design; the port's
`args` package rejects an unknown option instead. To keep the pinned
contract (exit 2, empty stdout, stderr naming `"--nope"`), the port can
either (a) refuse an unknown option with the unknown-agent line naming it,
or (b) refuse it with `args`' own wording (`Could not find an option named
"--nope".`), which also contains `"--nope"`. Both satisfy the test; (b) is
the more truthful line. **Recommendation: (b)**, owner to confirm (Q-O5),
since the guide's sentence says "naming `--nope` as an unknown agent" and
"with `--agent-command`, it silently becomes the agent's name", which (b)
changes: with (b) `chord acp --nope --agent-command x` is also refused.

Other stderr lines (all prefixed `chord: `, one line each, never on stdout):

- the by-hand note, only when stdin is a terminal, before serving:
  `chord: acp serves ACP on stdin and stdout, for a client that starts it.`
  and `chord: nothing to press here. Ctrl-D or Ctrl-C leaves; \`chord\` opens a window.`
- settings problems (`problemLine`), once each per process.
- `chord: the client answered <method> with an error: <message>`
- `chord: refused a permission for a session it does not know`
- `chord: refused a subagent's permission: the client takes no subagents`
  (and `form`, `plan` variants), when D-3 makes subagent asks possible.
- `chord: <message>` for each warning a session carries on past (a record
  that cannot be written, a failed set), mirrored as a `notice` to clients
  declaring `session.notices`.
- `chord: the connection closed: <reason>` on broken output or an oversized
  line.
- the shutdown's own lines (deadline passed, what did not close): runtime's
  draft names them from `leaving.ts`.

`stderr` must never throw: a stderr gone is no reason to stop serving.

## 8. Differences from the original, with options

**D-1. Extensions advertised.** Decided by the owner: `{ "session/state": 1,
"session/steer": 1 }` only. Consequence for clients: `_chord/agents/*` and
`_chord/monitors/stop` are `-32601` (unknown extension method), as the guide
says of unknown extensions. A client that declares all four still works.

**D-2. No chord commands.** Decided by the owner. The guide's sentence
"chord adds `/team` and `/new` to the command list even if the agent sends
none" does not hold until M4/M5.

**D-3. What chord declares toward the agent.** The original declares its
full client capabilities toward each agent (elicitation form and url, `plan`,
`session.compaction`, `subagents`, `_meta.terminal_output_delta`), and
`session.notices` only when the client did. The port declares none
(CTUI-12, staged until each is drawn in the window). This changes what the
client receives far more than the gate does: with nothing declared, Codex
sends its plan as reply text, nothing sends compaction or subagent traffic,
and no form ever comes. Options:

- (a) Declare nothing in `chord acp` either. Cheapest; consistent with the
  window; the gate is ported and tested with synthetic updates but rarely
  fires. A client sees the window's fallbacks.
- (b) Declare the original's set for `chord acp` sessions only, through
  `openAgent`'s existing `capabilities` parameter. `chord acp` draws
  nothing, so CTUI-12's reason (the window cannot draw them) does not apply;
  the client draws. Cost: records written by `chord acp` then hold kinds the
  window does not draw yet; the window's replay must skip them (runtime to
  confirm it does).
- (c) As (b) minus `subagents` and `terminal_output_delta`: `plan`,
  `session.compaction`, `session.notices` when the client declares it, and
  elicitation per D-5. `subagents` is left to M4, where children and adapter
  subagents share one routing; terminal deltas reach a client as agent
  `_meta` it may not expect.

**Recommendation: (c)**, owner to confirm (Q-O1). It is the original's
contract for everything that is a pure relay, and holds back the two that
pull in child routing or agent-specific `_meta`.

**D-4. Settings' MCP servers.** The port has no `mcpServers` settings or
`.mcp.json` reading (CTUI-29 kept only the `mcpServers: false` switch; the
window and `-p` send `mcpServers: []`). The original merges settings'
servers with the client's, client winning by name, and reports
`chord/held_back`. Options: (a) pass the client's servers through, honour
`mcpServers: false` / `--no-mcp-servers` by holding them back (reported in
`chord/held_back`), and add settings' servers when the task that reads them
lands; (b) bring `.mcp.json` and settings' servers into CTUI-56.
**Recommendation: (a)** (Q-O2): it is the contract a client sees for its
own servers, and the window does not have settings' servers either.
`chord/held_back` entries take the original's `HeldBack` shape (name and
reason) when the runtime draft defines it.

**D-5. Elicitation relay (brief Q7).** The original relays
`elicitation/create` raw to the client (session-scoped; regardless of the
client's declared elicitation), cancels request-scoped ones and ones naming
an unannounced session, treats an error answer or an unknown action as
`cancel`, withdraws open forms on `session/cancel`/close with
`$/cancel_request`, and forwards the agent's `elicitation/complete`. The
port declares no elicitation and its `rpc.dart` answers `cancel` itself
(CTUI-28). Options:

- (a) Keep it: `chord acp` declares no elicitation, the agent sends none,
  any that comes is cancelled by `rpc.dart` as now. Contract difference:
  a client never sees `elicitation/create`.
- (b) Relay in `chord acp` only: declare `elicitation: { form: {}, url: {} }`
  toward the agent for `chord acp` sessions, and route `elicitation/create`
  to the server instead of the fixed `cancel`. It needs no drawing (the
  client draws), so CTUI-28's reason, "advertised without honouring it",
  does not apply: the client honours it. CTUI-33 later brings the window's
  forms and `-p`'s declines on the same routing.
- (c) Wait for CTUI-33 and do (b) there.

**Recommendation: (b)** (Q-O3). It is small (a request passed through, the
answer mapped by `elicitationReplyOf`), it is the original's contract, and
the port's `rpc.dart` only needs its `elicitation/create` branch made a
handler like permissions. `requires_action` in `_chord/session/state` then
covers forms as the original's does.

**D-6. Plan approvals.** The original turns cursor's `cursor/create_plan`
and grok's `x.ai/exit_plan_mode` into `session/request_permission` with
options `accepted` ("Yes, accept the plan", `allow_once`), `kept` ("No, keep
planning", `reject_once`) and, for grok, `left` ("No, and leave plan mode",
`reject_once`), title the plan's name or `Plan`, content the plan as
Markdown; a cancel, error or unknown id is `cancelled`, never a yes. The
port answers both `cancelled` at once (CTUI-12) and has no plan ask in
`Conversation`. Options: (a) keep `cancelled` in `chord acp`: cursor's and
grok's plan mode then never proceeds for a client; (b) bring plan asks into
CTUI-56 for `chord acp` only (a pure `planPermission`/`planAnswerOf` plus a
handler in `rpc.dart`); (c) leave it for the task that brings plan asks to
the window. **Recommendation: (c)** with (a) meanwhile, since plan asks need
`Conversation` state the window will share, and only two agents send them;
owner to confirm (Q-O6). This leaves the guide's "calls
`session/request_permission` for ... plan approvals" untrue for now.

**D-7. `chord acp --nope`.** See section 7 (Q-O5).

No other difference is proposed. In particular the wording of every error
and stderr line, the ordering of answers and updates, aliases, the 32 MiB
limit, and the exit codes follow the original.

## 9. What the server needs from the port's session layer

Not interface decisions, but contract items that do not exist in the port
yet; the framework and runtime drafts own how:

- `Conversation.rename(title)` returning the stored title, with the agent
  told where it supports `session/set_title` (the window's `/rename` is in
  the command catalog but has no `Conversation` method), and
  `recordPendingRename(record, title, at)` plus its delivery on the next
  load/resume.
- The agent's account: `auth/status` toward the agent and its
  `auth/status_update` pushes folded (`auth_status.ts`'s `foldAccount`),
  exposed per session; nothing in the port does this.
- Prompts carrying images and embedded resources to the agent (the port
  records them through `SubmittedContent`; whether `Conversation.send` sends
  them is to be checked) and `takesImages`/`takesEmbeddedContext` per
  session for `_meta["chord/acp"]`.
- `Conversation.cancelPrompt(turnId)` and `steerQueued` exist; `interrupt`
  exists.
- Session events the turn table reads (`prompt` with `turnId`, `result`,
  `queue_withdrawn` with turn ids, `cycle_started`, `disconnected`): the
  port's `ConversationEvent` names differ (`Queued`, `QueueWithdrawn`,
  `Gone`, ...); the mapping is the runtime draft's.

## 10. State: what lives where

All of it is plain Dart without a widget, tested without a process:

- Pure, ported file for file: `lib/session/upstream.dart` (`reaches`,
  `aliasFor`, `mapUpdate`, `configOptionsOf`, `configSetter`,
  `configChange`, `answeredConfig`, `messageChunk`, `permissionAnswerOf`,
  `elicitationReplyOf`, `promptOf`; `planPermission`/`planAnswerOf` per
  D-6; `CHORD_COMMANDS`/`commandOf`/`commandsIfNone` per D-2 not ported) and
  `lib/acp/upstream_turns.dart` (`reduceTurns`, `sessionStateOf`, `turnOf`).
- Per connection: the declared client capabilities; the session table by
  client id; reopening ids; open asks by id; unanswered prompts by request
  id; the account last told.
- Per session: its upstream view (`UpstreamSession`: agent id, client id,
  announced subagents, last config sent), its turn table, last state sent,
  held updates until its id is answered, past events for a load.

## 11. Owner questions

- **Q-O1** (D-3): which client capabilities `chord acp` declares toward the
  agent. Recommended: `plan`, `session.compaction`, `session.notices` when
  the client declares it, elicitation per Q-O3; not `subagents` or terminal
  deltas until M4.
- **Q-O2** (D-4): client `mcpServers` passed through with `--no-mcp-servers`
  / `mcpServers: false` honoured, settings' and `.mcp.json` servers left to
  the task that reads them. Recommended: yes.
- **Q-O3** (D-5): relay `elicitation/create` and `elicitation/complete` in
  `chord acp`, declaring elicitation toward the agent for its sessions
  only. Recommended: yes, now, ahead of CTUI-33.
- **Q-O4** (section 6): an agent that sends no command list gets no
  `available_commands_update` from chord. Recommended: send nothing.
- **Q-O5** (D-7): `chord acp --nope` refused with `args`' own unknown-option
  line, exit 2, stdout empty; `--nope --agent-command x` refused too.
  Recommended: yes; the alternative copies Cliffy's quirk.
- **Q-O6** (D-6): plan approvals stay `cancelled` until plan asks reach the
  window. Recommended: yes.
