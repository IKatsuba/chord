# CTUI-35: chord's MCP server, children and messages between agents

The original's M4 row "chord's MCP server, children, messages": every
session the window opens gets an MCP server of chord's own, through whose
tools its agent lists runtimes and sessions, starts task agents and
long-lived children on any runtime chord knows, messages them, closes and
clears them; the person sees every child in a list under the prompt, picks
one to talk to it, and answers its permissions; resume draws the past of
children without reopening them. `chord acp` serves the same children to
its client through the `agents` extension and `/new`.

The specification is `../chord`: `docs/FEATURES.md` (M4), `docs/guide.md`
("chord's own server" and the agents list, about lines 1322-1480;
`chord acp`'s "Children, teams and commands" and "Extensions"),
`src/server/{server,tools,runtimes}.ts`,
`src/session/{agents_host,open_agents,tasks,window_agents,new_args,
upstream,upstream_commands}.ts`, `src/acp/host_fold.ts`,
`src/acp_agent.ts`, `src/ui/agents/`, `src/ui/app/state.ts`,
`src/ui/transcript/{message.ts,tools/chord.ts}`, and their tests.

The design was drafted by the framework, interface and runtime architects
and reviewed by the critic; the drafts, revised once after the review, are
the record, under `docs/design/evidence/CTUI-35/drafts/`. Where this
document and a draft disagree, this document holds. The drafts carry the
verbatim tables this document does not repeat: interface sections 3 and 4
(screens and every word), runtime section 5 (every tool answer and
refusal), runtime section 10 (failure scenarios). The package trial is
`docs/design/evidence/CTUI-35/mcp_trial/`.

## 1. Scope

In:

- chord's MCP server, one per window and one per `chord acp` process, on
  the loopback over Streamable HTTP, a token per session launch.
- Its tools `list_agents`, `list_sessions`, `spawn_task`, `open_agent`,
  `send_message`, `close_agent`, `clear_agent`, per role (section 4).
- Long-lived children: open, start failure, exit and failed-turn notes,
  close (by `x` and by `close_agent`), the eight-child limit, `/clear` on a
  picked child and `clear_agent`, closing on quit.
- Task agents nested in the parent's turn, their asks in the parent's view,
  their report as a message, Esc stopping them.
- Messages between agents: a turn of the recipient's, steered into its
  running turn where `_session/steering` is advertised, held after the
  person's answer, queued otherwise; `←` and `→` rows; `← from chord`
  notes.
- The agents list under the status line, picking an agent, the window's
  chat and prompt following the picked agent, drafts set aside, `x`,
  ctrl+x a.
- The live `@@` roster (from CTUI-24).
- `/new [agent] [--name <name>]` in the window and in `chord acp`, one
  parser (owner).
- Records and resume of children and messages.
- `chord acp`: `_chord/agents/send` and `_chord/agents/close`, child
  routes, child state, the subagent refusals, `/new` in the command list,
  `agents: 1` in `initialize` (from CTUI-56).

Out, each with the task that takes it:

- CTUI-36: `monitor`, `stop_monitor`, `list_monitors`, `_chord/monitors`,
  the background summary row and view, `logStep`/`FOLLOWING`.
- CTUI-74: `/fork` and forks in the list, fork refusals on chord's tools.
- CTUI-37: teams, `list_teams`, `run_team`, `propose_team`, `get_budgets`
  (owner), leads and members in the list, `/team` in `chord acp`'s list.
- CTUI-79: chord's `settings` tool (owner).

Nothing beyond the original is added.

## 2. The server

`example/chord/lib/server/server.dart`, over `mcp_dart` 2.4.4, pinned
(section 11 for the trial). As the original's `server.ts`:

- `HttpServer.bind(InternetAddress.loopbackIPv4, 0)`, path `/mcp`,
  `idleTimeout = null` (a stream stays open while a tool waits minutes on
  the person, as Bun's `idleTimeout: 0`); nothing written to stdout or
  stderr. A bind failure throws at startup.
- Our own admission layer before the package, as the original's before the
  TypeScript SDK: no bearer or an unknown one, 401 `Unknown token`; a
  session id not opened, 404 `Session not found`; opened with another
  token, 403 `Session opened with another token`; no session id and not an
  `initialize` POST, 400 `No session; initialize first`; JSON-RPC -32000
  with `id: null`; a throwing handler, 500 `Internal error`.
- One `McpServer` per `initialize`, its tools registered from the caller's
  role, so `tools/list` differs per token. `mcp_dart` has no
  `onsessionclosed` and `connect()` replaces `transport.onclose`: our layer
  chains its own hook after `connect()` so a closed session leaves the
  admission map.
- `ChordServer` is an interface (`url`, `admit(caller) → Admitted{token,
  server}`, `revoke(token)`, `close()`), so the host runs with a fake
  server in tests.
- Owner (G2): `initialize` declares `tools: {listChanged: true}` and every
  `inputSchema` carries `"$schema":
  "http://json-schema.org/draft-07/schema#"`, set through the package's
  configuration (declared capabilities, the literal in our schema maps),
  proven by a test. The other differences are accepted (section 11).

`serversFor` (`lib/session/servers.dart`) adds chord's server last, named
`chord` or the first free `chord-2`, `chord-3`, … where a passed user
server has that name, only to an agent whose `initialize` advertised
`mcpCapabilities.http` and that is not set to take none; otherwise held
back with `own: true` in `chord/held_back`.

## 3. Hosting many sessions

The port's window drives one session today. It becomes a host of many,
in the original's shape (runtime draft sections 2 and 3):

| Original | Port | Kind |
| --- | --- | --- |
| `agent_name.ts` | `lib/agent_name.dart` | pure |
| `session/window_agents.ts` | `lib/session/window_agents.dart` | pure roster: `WindowAgents<C>`, `ChildInfo`, `openChild`, `closeChild`, `forgetClosed`, `pick`, `movePick`, `attend`, `attentionOrder`, `hear`, `messageRecipients`, `childName`, `takenNames`, `childEnded`, `maxChildren = 8` |
| `session/open_agents.ts` | `lib/session/open_agents.dart` | effect shell; `closeAll` joins every close, one aggregate error |
| `session/tasks.ts` | `lib/session/tasks.dart` | pure `TaskAgent` state machine, `fromLine`, `senderName`, `wrapMessage` |
| `session/new_args.ts` | `lib/session/new_args.dart` | pure |
| `session/agents_host.ts` | `lib/session/agents_host.dart` | effects over mutable maps (`early`, `clearing`, tasks by id), admission per launch, `WindowView` for the tools |
| `session/upstream.ts`, `upstream_commands.ts` | existing files, extended | pure |
| `acp/host_fold.ts` | `lib/acp/host_fold.dart` | pure |
| `server/tools.ts` | `lib/server/tools.dart` | pure answers, schemas, `toolsOf`, `serve` |
| `server/runtimes.ts` | `lib/server/runtimes.dart` | effect with an injected `Probe` |

The host stays a class over mutable maps, as `createAgentsHost` is: its
race fixes (CHD-476, CHD-373) are written against those maps. What is pure
is lifted out and tested directly.

**One ordered event path.** `StartConnection` stops owning a
`Conversation`: it keeps what is per process (the start page's state, the
forced exit, the opener with command, env, MCP servers and resume, the
record drain) and becomes the opener the host calls for main and, with the
child's runtime and admission, for each child. The host owns every
`Conversation`. One `WindowFold` (in `lib/ui/app/`) implements the host's
port: `heard(key, event)`, `closingHeard(key, event)` and
`replayed(key, …)` fold synchronously, in delivery order, into the state
of `key`, shown or not; the window's own dispatches fold into the picked
key through the same fold; `stateOf(key)` reads it.

**Per session:** its `Conversation`, process and process group, token,
record, `!` command, queue, timers, kept drafts and retained
`ScrollController`. **Window-wide:** the server, `Runtimes`, the terminal,
clipboard, notifications, theme, pickers, the shortcuts panel, the sent
prompts history (the history walk is per agent).

**Results that land later** (editor text, model, effort and config
answers, completion matches, an awaited `@`/`@@` pick, image reads,
settings refusals, a resume list) carry `(key, launch)` taken when they
began; `launch` is the agent's generation, bumped on `cleared` and
`closing`. A result whose key is gone or whose launch moved is dropped,
never applied to whoever is picked. Window intents (send, clear, cancel,
steer, mode, model, effort, config, rename, answers, shell context) take
`conversationOf(front)` at the press. This replaces today's
`widget.connection.conversation` at every call site (interface draft
section 1).

**Processes.** A child is a `Conversation` over its own `Session` from the
same `SessionOpener`: its own process group, stopped with `StopBounds`;
the exit kill takes leftovers. Admission is per launch: the token is made
when a launch opens and revoked when it is let go, fails to open, or its
process exits; a call already in a handler after that answers `Your
session was cleared or closed; nothing more goes from it`.

**Cancellation, as the original.** `open_agent` and `spawn_task` do not
forward the MCP request's signal: a cancelled request neither refuses nor
stops a starting child. Launch invalidation is separate and required: a
caller whose launch was let go (`/clear`, `clear_agent`, close), or whose
session changed while the offer was read, is answered `STALE` before
anything starts.

## 4. Tools

| Tool | main (`person`) | long-lived child | task |
| --- | --- | --- | --- |
| `list_agents {agent?}` | yes | yes | no |
| `list_sessions` | yes | no | no |
| `spawn_task {agent, model?, effort?, prompt, name?}` | yes | yes | no |
| `open_agent {agent, model?, effort?, prompt, name?}` | yes | no | no |
| `send_message` | `{to, text}`, to a child it opened | `{text}`, to its parent | `{text}`, to its parent |
| `close_agent {to}` | its child or its task | its own tasks only (own description) | no |
| `clear_agent {to}` | yes | no | no |

`toolsOf(caller)` registers exactly these; `/mcp` lists main's seven, a
child's four. Descriptions, schemas, answers and refusals are the
original's text, field for field, listed in runtime draft section 5:
`serve` tells the caller's session the call (`served` with `task`,
`queued`), an `{error}` becomes `isError: true` with its text, close and
clear answer words plus `structuredContent`.

`list_agents` reads offers through `Runtimes`: kept per runtime for the
window, heard from an open session of that runtime, else probed by
opening a session with no MCP servers and closing it, one read per runtime
at a time, bounded by 60 s; a failed read is not cached; a refused runtime
(CHD-466) is never started.

## 5. Children, tasks and messages

As the original, worded as in runtime draft sections 2, 4 and 6:

- **Open.** Name rules from `agent_name` (`"` and control characters
  refused, naming the character; `main`, `chord` and taken names refused);
  model required, effort optional and reported; the ninth child refused
  before anything starts (`This session has 8 agents open; close_agent one
  first`). Messages to a child still starting wait in `early`: on
  `connected` the first is its first turn and the rest go into it.
- **Start failure, exit, failed turn.** `✗ failed to start` and main told
  `<name> (<runtime>) did not start: …`; `✗ exited` and `<name>'s agent
  exited: <stderr end>. open_agent opens it again.`; a failed turn leaves
  it open and idle, `<name>'s turn failed: <error>. It is still open;
  send_message reaches it.` All as `← from chord`, a turn of main's.
- **Close.** A busy turn interrupted, its command stopped, spend kept under
  its key until the close settles; on the person's `x`, main told `The
  person closed <name> (…, id <id>). It takes no more messages; open_agent
  starts another.`; nothing on main's own `close_agent`.
- **Clear.** `/clear` on a picked child and `clear_agent` keep its name,
  id, colour and position; held messages wait until the fresh session is
  up; the person's queued prompts return to that agent's draft with their
  images; other senders' queued messages are dropped and counted (`2
  queued messages from main and parser were not delivered.`); only a clear
  by the person tells main.
- **Tasks.** Drawn in the parent's turn as a subagent block,
  `Agent(<name>) · <runtime> · <model>`, ended `Done (5 tool uses · 2.0k
  tokens · $0.0125 · 13s)`; the report of its first turn, or what it sends
  with `send_message`, reaches the parent as a `←` message; Esc stops the
  turn's tasks with no report; `close_agent` stops one by id or by a name
  unique among the caller's tasks.
- **Task asks.** A task's permission, form or question is shown and
  answered in the parent's view. Ask ids become UUIDs at their source, as
  the original's `crypto.randomUUID()`, replacing the port's per-session
  `permission-n` and `elicitation-n`, which collide once two tasks relay
  into one parent. The parent keeps `foreign: id → task`, set when the ask
  is relayed, removed on its settlement and when the task ends; a late
  answer to an unknown id is ignored. A task's plan approval is not
  relayed, as the original's `TaskAgent.heard` has no case for it. With an
  ask open when a task's agent exits, ship checks the original's order
  against its fake and follows it; a stale box left open there is a small
  slip, fixed with a test and logged.
- **Messages.** `deliver` is a turn of the recipient's, wrapped `<message
  from="name · runtime[ · report|failed]">`; `tell` steers into a running
  turn of an agent advertising `_session/steering`, held for open calls
  where its steer cuts them and for the person's answer while the turn
  waits on one, else queued as the next turn with the sender's `→` row
  served again as `queued`. A turn the agent starts on its own from a
  steer is cancelled and the message goes next. A message is one
  `QueuedPrompt` with `from`, moved never copied, recorded once.

## 6. The window

### The agents list

Under the status line while a session has children: `main`, then
children in opening order. Ported as `example/chord/lib/ui/agents/`
(`glyphs.dart`, `agents.dart` pure, `agents_view.dart` widgets) on the
framework's `cellWidth` and `TextLayout.wrapAnsi`; nothing new in `lib/`
(`ListView` and `Picker` do not fit a list of wrapped rows counted against
a line budget, and a generic one would be chord's alone). The rows are
furniture, not selectable, as the original's `selectable: false`.

Prompt holding the keys, a child asking, 120x40, captured from the
original (`bun dev chord --fake --qa agents`):

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ● docs needs your permission · ctrl+x a to go · ? for shortcuts        Fake Large with a 1M context window · 1% used
    main    fake · Fake Large with a 1M context window · medium  ◦ idle 5s
    parser  fake · Fake Small · medium                           ◦ idle 7s        ✓ new reply
    docs    fake · Fake Large with a 1M context window · medium  ● permission 8s  ← new message
```

80x24, the same moment (model and effort give way on every row):

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ● docs needs your permission · ctrl+x a  Fake Large with a 1M con… · 1% used
    main    fake  ◦ idle 5s
    parser  fake  ◦ idle 7s        ✓ new reply
    docs    fake  ● permission 8s  ← new message
```

`docs` picked, 80x24: its marks clear on opening, the prompt box takes its
name and colour, the status line its model:

```
╭─ docs ───────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ↑ ↓ pick · enter write · x close · esc back    Fake Large with a 1M context…
    main    fake · Fake Large with a 1M context window  ◦ idle 13s
    parser  fake · Fake Small                           ◦ idle 15s
  ❯ docs    fake · Fake Large with a 1M context window  ● permission 16s
```

States: `● permission 17s`, `● input 17s`, `✻ working 41s`, `◦ idle 3m`,
`✗ exited`, `✗ failed to start`; unseen news `✗ turn failed`, `✓ new
reply`, `← new message`, cleared on opening. As room narrows effort, model
and the mark's words give way in that order; names wrap inside a third of
the width; a tall picked row is read by line; past the limit `… +N more`.
One one-second clock is shared by the list and the child line, running
only while a row is timed. Every other screen (narrow and tall rows, the
child line, `←`/`→` rows, held messages, task blocks, resume, the close
note) is in interface draft section 3 with its styles; the port's captures
beside these come from unit 34.

### Keys

| Key | Id / context | What it does |
| --- | --- | --- |
| ↓ | `history:next` / Chat | walk newer; from a non-empty draft not walking, set it aside; from an empty one with children, enter the list |
| ↑ | `history:previous` / Chat | newest kept draft, then older, then sent prompts |
| j / k | vim normal mode | as ↓ / ↑ at the last and first lines |
| ↑ ↓ j k | list keys | move `❯`, which picks at once; ↑ from the first row returns the keys |
| Enter / Esc | list keys | return the keys to the picked agent |
| x | `agents:close` / Agents | close the picked child; a second press while it works, waits, has queued prompts or tasks |
| ctrl+x a | `session:attention` / Global | pick the agent waiting longest, asking before unseen news; none: `Nothing waits on you` |

All go through `Actions` with descriptions; the list keys that are not
rebindable are bindings with descriptions so the panel lists them. A box
holding the keys hands ↓ from its last active row to the list and gets its
place back. Owner: until CTUI-36, the panel says `↑ ↓ for prompts, agents`
and `x to close an agent`; CTUI-36 restores `, background` and `, stop
background`. Hint while the list has the keys: `↑ ↓ to pick · enter to
write to it · x to close · esc to go back`, short form `↑ ↓ pick · enter
write · x close · esc back`.

### The chat follows the picked agent

One `Transcript`, keyed by the session, built for the picked agent with
that session's retained `ScrollController`. Hidden sessions cost no
layout; a switch costs a first frame, as a resumed session's (CTUI-1:
about 110 ms AOT at 10 000 entries). Selection and a picked code block end
on a switch. The prompt's `TextAreaController` is one, loaded from the
picked agent's draft and cursor; completion is reset on every front or
launch change, even when the recipients are the same names (two children
both offer `[main]`).

**Scroll has one authority**, the retained controller. In `lib/`
(unit 1), the anchor (item and rows into it) moves from
`RenderListViewport` into `ScrollController` (`@internal`), its value type
`ListAnchor` into `lib/src/foundation/scroll_state.dart`, so a controller
attached again after a resize or ctrl+o comes back on the same entry, as
the original's per-session anchors do. A detached step that moves the view
drops the anchor so the rows asked for win; one that does not keep it; an
empty or zero-width layout behaves as today; a cleared session gets a new
controller; swapping controllers keeps each one's own anchor. No public
API changes.

### The room

Computed before layout, in lines, by a pure `agentsRoom` in
`example/chord/lib/ui/app/agents_room.dart` (framework draft section 3):
the transcript gives way first, to no rows; then the agents list, from
`max(2, rows ~/ 6)` lines down to its floor (one agent row and `… +N
more`); then a request's shrinkable part. Each box's height arithmetic is
lifted into a pure `*Natural` function used by both the box and the
window. Forms, questions and links shrink only while held. When even the
fixed parts do not fit, the transcript is 0, the list at its floor, the
bodies at their minimum, and the window clips at its bottom, as the
original.

The permission body gives way after the list (CHD-464's `givesWay`). The
plan box has no such gate in the original: Yoga shrinks the plan's Note
and the list together, each by its natural height (flexShrink 1 on both),
and the list folds to its floor only when its share brings it there. The
port computes that proportional share, rounded as Yoga rounds to cells,
and tests it against a capture of the original, taken in unit 20, of a
plan with three children at 80x24. The framework draft proposed a stricter order; it is not taken,
being a departure from the original.

### The named top

`╭─ docs ───…╮`: `╭─` in the edge style, the name bold in the agent's
colour, then `─` to `╮`. The original draws it as a row of its own because
its framework's border title takes no colour. `Box.title` draws `╭ docs
─…` in the border's style, so the port draws the row with a `Stack` over
the prompt's `Box`; no framework change.

### `@@`

The roster is `messageRecipients(agents, front)`: from main its open
long-lived children; from a child `main`; never tasks or unopened
runtimes. `CompletionController.resetSession(names)` runs on every front
or launch change; equal names skip the reset only within one `(front,
launch)`.

### Tasks before CTUI-36

Owner: a task that outlives its parent's turn shows in the status line
(`2 agents still running`) and in its own block; no summary row is drawn
under the list, nothing names the background, until CTUI-36.

### `/new`

`/new [agent] [--name <name>]` opens an idle child of main, on main's
runtime or the named one, and picks it; `/new ` completes agent names,
not `--name`. Words and refusals as interface draft I10, from the one
`new_args.dart` shared with `chord acp`.

## 7. Records and resume

Each child has its own record; its header holds `parent`, `name`, and
`task` (a task's id) or `id` (a long-lived child's). A message is the
recipient's `prompt` line with `from` (and `into` when steered) and the
sender's `served` line; a close while the session goes on is a `closed`
line. Resume reads records whose `parent` is the session's id: task pasts
are spliced after the line that started each block, messages draw from
`from`, long-lived children are named in a `left_open` note (`parser
(codex) was open when this session was left and is not reopened · /resume
lists it`) and never reopened; `/resume` names a child's session before
its title and marks one open now. The splice is pure; the scan runs on an
isolated `XDG_STATE_HOME` in tests.

## 8. `chord acp`

As the original (runtime draft section 8):

- `host_fold.dart` folds each event before the host or server reads it; a
  test fails when an event type is neither folded nor listed as no action.
- `subagents` is read from the client's capabilities; without it a child's
  or task's permission is rejected, a form cancelled and a plan answered
  `cancelled`, each with `chord: refused a subagent's …: the client takes
  no subagents` on stderr.
- A child's route (`<parent>/<child id>`) is made on first need, holds
  events until `connected` and flushes them in order, is reset by
  `cleared` and deleted on close after a last `subagent_update` with
  `closed: true`. Child state (`requires_action`, `running`, `idle`) is
  sent when it changes.
- `_chord/agents/send {sessionId, prompt}` and `_chord/agents/close
  {sessionId}`, `session/cancel` on a child, with the original's errors.
- `new` goes into the command list ahead of the agent's, and once on
  `connected` to an agent that sends none (`commandsIfNone`). `team` joins
  with CTUI-37.
- `agents: 1` is advertised last, once all of the above work; until then
  `_chord/agents/*` stay -32601.

## 9. Seams

Carried now because records hold them: `ChildInfo.team`, `lead`,
`forkedFrom`, and `Caller.role`. Nothing unreachable ships: no fork
refusal, no team rows or branches, no monitor registry, no summary stop.

- CTUI-36 adds the monitor tools to `toolsOf` for main and long-lived
  children, `monitor`/`stopMonitor`/`monitors` to `WindowView` keyed by the
  caller, stopping an owner's monitors in close, clear and main's close, a
  `monitor` sender on `MessageFrom`, `monitors: 1` and `_chord/monitors/*`,
  a trailing stop in `moveListFocus` and the summary row in the room's
  fixed part, and the full panel wording.
- CTUI-74 adds `Caller.fork`, the refusals of `open_agent`, `close_agent`
  and `clear_agent`, `parentOf` with no parent for a fork, forks in
  `list_sessions` and after children in the list (the sort reads
  `forkedFrom` already), and the `fork ·` detail.
- CTUI-37 adds the lead and member branches of `toolsOf` and
  `messageRecipients`, `Caller.team`, team rows and folding, team clauses
  in the left-open note, `team` in `chord acp`'s commands, `get_budgets`.

## 10. Tests

- **Never a real agent.** One test catalog, `test/fixtures/runtimes.dart`,
  maps every runtime a test admits to the original's fake (bun) or a
  scripted opener; any other name throws before a process starts. It runs
  with `HOME`, `XDG_*` and settings in a temporary directory, and
  `CHORD_FAKE_CHILD_RUNTIME=fake` always set (the fake's child runtime
  defaults to `codex`). A test asks for `codex` and checks nothing ran.
  The fake's `agentmentions` calls `run_team` and is not used.
- **Through the fake**, whose MCP client is the TypeScript SDK's, proving
  the wire: `agents`, `agentsquiet`, `agentsheld[gated]`, `agenttask`,
  `agentcost`, `agentlong`, `agentexit`, `agentfail`, `agentlate`,
  `agentcall[gated|twice]`, `agentother`, `scenarios/tasks.ts`,
  `scenarios/efforts.ts`. No new scenario.
- Pure modules directly; the host with scripted sessions and a fake
  `ChordServer`; the server over loopback HTTP and from an AOT binary; the
  window through `package:chorded_tui/testing.dart`; records on an
  isolated `XDG_STATE_HOME`. Each unit below names the tests that fail
  without it.

## 11. The MCP package and its differences

`mcp_dart` 2.4.4 (published 2026-11-16) is the only package tried that
serves Streamable HTTP behind our own listener with a tool list per
session and revoke that ends calls in flight; it builds and serves under
`dart compile exe` with the same answers as under `dart run`. `dart_mcp`
0.5.2 has no HTTP transport; `mcp_server` 3.1.1 owns the listener, lists
every tool to every caller, ties no session to a token and leaves calls
hanging on revoke.

The trial compares `mcp_dart` against the original's
`@modelcontextprotocol/sdk` 1.32.2 on 46 requests
(`mcp_trial/results/diff.md`). Admission, sessions, revoke and every
valid tool answer agree. Owner's choices on the rest:

- **G1, accepted.** A tool outside the caller's role or unknown is a
  JSON-RPC error `{"code": -32602, "message": "Tool 'close_agent' not
  found"}` where the original answers `isError: true`, `MCP error -32602:
  Tool close_agent not found`. A missing argument reads `Invalid arguments
  for tool 'send_message': JsonSchemaValidationException: Required
  property is missing: text (at )` where the original reads `MCP error
  -32602: Input validation error: Invalid arguments for tool send_message:
  Invalid input: expected string, received undefined at text`; a wrong
  type likewise. No upstream filing without the owner.
- **G2, configured.** `tools.listChanged` and the schemas' `$schema`, as
  section 2.
- **G3, accepted.** Batches refused with 400 (the original serves them);
  other codes and words for a bad protocol-version header, invalid
  JSON-RPC and parse errors; a request's `id` where the original sends
  `null`; `charset` in content types; JSON member order.

## 12. Differences from the original

1. The MCP package's answers, section 11 (owner).
2. Panel wording trimmed until CTUI-36 (owner).
3. Tasks after their turn in the status line and their block only until
   CTUI-36 (owner).
4. The window's agent state is read without the original's lag until the
   next draw: the port's window already folds synchronously, as the
   original's `chord acp` does; nothing seen changes (lead).
5. `chord acp` lists `new` now and `team` with CTUI-37, as CTUI-56 split
   them (lead).

## 13. Units for ship, in order

Each unit is one reviewable change with the tests that fail without it.
Draft references name where each is spelled out.

**A. Foundations**

1. **`lib/`: the scroll controller owns its anchor** (framework F1).
   `test/widgets/scroll_controller_test.dart`: reattached across a width
   change on the same item; an offset inside an item kept and clamped;
   scrolled `Follow.bottom` with news while detached; a detached `jumpTo`
   and `toBottom` win over the old anchor; empty and zero-width interludes
   as today; swapped controllers each on their own item; a following
   controller at the bottom.
2. **Ask ids as UUIDs** (runtime 1). Conversation tests: two sources'
   first asks have distinct ids; the elicitation test that asserted
   `elicitation-1` updated.
3. **`agent_name`, `new_args`, `window_agents`, `open_agents`** (runtime
   2, interface I4's roster cases). Pure tests: name refusals naming the
   character; `new_args` cases of I10; open, close, pick, attend,
   `attentionOrder` (asking before unseen, oldest first, ties to main then
   opening order), `messageRecipients` from main and from a child, a
   `forkedFrom` child sorted after children, the ninth child refused;
   `closeAll` joins earlier closes and aggregates failures.
4. **Runtime offers** (runtime 3). `runtimes_test` with a stub probe and
   fake_async: the 60 s bound, one shared read, retry after failure, close
   mid-read, a refused runtime never started.
5. **Tool contracts** (runtime 4). `tools_test` against a fake
   `WindowView`: the role matrix, every schema, answer and refusal of
   runtime section 5, `structuredContent`, `served` metadata.
6. **The server** (runtime 5). `server_test` over loopback: the four
   refusals, per-token `tools/list`, revoke ending sessions and calls in
   flight, `close`, a closed session leaving the map, `listChanged` and
   `$schema` present; a compile-tagged test serving from an AOT binary.
7. **`serversFor` with chord's server** (runtime 6). `servers_test`:
   `chord-2`, held back without `http` and with `mcpServers: false`.
8. **Test runtime catalog** (runtime 7). The test that a real runtime name
   never starts a process.

**B. The window holds many sessions**

9. **Window state split** (interface I1). `state_test`: an event for k2
   changes only k2; `SessionShown` brings back k2's draft, cursor, queue
   and controller; window-wide fields survive a switch; existing window
   tests pass through `frontState`.
10. **One event path** (runtime 8). Hidden-child updates fold and draw
    when picked; a late `closingHeard` spend counts.
11. **Front routing and targeted results** (interface I2). `/rename` on a
    picked child; editor, model and refusal results across a switch land
    on the asking agent; typed keys split by a switch; `clear_agent` on a
    hidden child; a result after its agent's `/clear` dropped.
12. **Messages in `Conversation`** (runtime 9). On a scripted session:
    deliver, tell, held after calls and after an answer, refused and
    ended-on-the-way steers re-queued as `queued`, the self-started turn
    cancelled, `from` and `into` recorded once.

**C. The host**

13. **Open and start failure** (runtime 10). Scripted sessions and the
    fake `agents`: admission per launch, early messages in order, the
    `did not start` note.
14. **Exit and failed-turn notes** (runtime 11). Fake `agentexit`,
    `agentfail`; `childEnded` cases.
15. **Close and the eight-child limit** (runtime 12). The person's `x`
    note, nothing on main's own close, the ninth refused, token revoked.
16. **Clear and `clear_agent`** (runtime 13). Held messages after the
    fresh session, the person's prompts back in the draft, dropped
    messages counted, close while clearing, a second clear refused.
17. **Closing spend** (runtime 14). Spend kept under the closing key and
    counted after `session_closed`.

**D. The list on screen**

18. **`agents.dart` and `glyphs.dart`, pure** (framework U1 with
    interface I4's layout cases). The non-team cases of
    `../chord/tests/ui/agents/agents_test.ts` one by one; layouts at 120
    and 80 equal the captures; widths 0 and 1; a name wider than the list.
19. **`AgentsList` and `ChildLine`** (framework U2, interface I5). Tester
    at 120x40 and 80x24: the captured screens cell for cell with styles; no
    list without a child; a drag across the list copies nothing; the clock
    ticks while timed, stops when all rows are exited, one timer shared.
20. **The room** (framework U3, with section 6's plan rule). Pure cases
    at 40 and 24 rows, `avail` 0 and 1, saturation, wrapped rows as lines;
    window tests per request kind with three children; the plan box and
    the list sharing as a capture of the original at 80x24 shows; the list back
    at its limit after the answer.
21. **The chat switch and the named top** (framework U4). Same top entry
    after a round trip and after a resize while hidden; news on a hidden
    child; selection gone; a closed child's controller disposed; the named
    top cell for cell at 120 and 80, cut when narrow, nothing at 0 and 1.
22. **Kept drafts and the per-agent walk** (interface I3). The I3 cases.
23. **List keys and attention** (interface I6). ↓ ↓ into the list with the
    draft kept; ↑ ↓ j k pick; Enter, Esc, ↑ at the top return; `x` once
    and twice; nothing on `main`; rebinding `agents:close`; ctrl+x a order
    and `Nothing waits on you`; a box handing ↓ to the list; the panel's
    trimmed lines.
24. **Messages and chord's tool rows** (interface I7). Each verb's row,
    `· queued`, held rows' headers, `← from chord`, a failed report's
    arrow.

**E. Tasks**

25. **Tasks** (runtime 15). `tasks_test`; two tasks and the parent with
    asks pending at once, one answered, one closed, a late answer ignored;
    Esc with no report and the aside; fake `agenttask`, `tasks.ts`,
    `efforts.ts`; a task's ask open at its exit as the original's fake
    shows.
26. **Task blocks** (interface I8). The captured `task` and `tasktwo`
    blocks; unreported parts left out; a refused effort; a task after its
    turn in the status line and no row under the list.

**F. The rest**

27. **`@@` live roster** (interface I9). A pending pick dropped from child
    A to child B and across clear and reopen; equal names kept within one
    front; a closed child gone; no task offered.
28. **Window `/new`** (interface I10). Opens an idle child and picks it;
    refusals shown where typed.
29. **Records and resume of children** (runtime 16). Splice tests on
    fixture records; resume on an isolated state directory.
30. **Resume screens** (interface I11). Left-open wording, singular and
    plural; `open now` picks instead of resuming.
31. **`chord acp`: host fold, routes, capabilities, refusals, child
    state** (runtime 17). Wire tests of section 8, with and without
    `subagents`, duplicate request ids across sessions.
32. **`chord acp`: `_chord/agents/*`, cancel, `/new`, then `agents: 1`**
    (runtime 18). Wire tests; `/new` with and without the agent's
    commands; -32601 gone only here.
33. **Benchmark: the switch frame** (framework U5). AOT numbers beside
    CTUI-1's in `docs/decisions.md`; per-session extents outside the
    viewport are the fallback only if they are slow, and that is the
    owner's.
34. **Fixture and captures** (interface I12). `tool/children.dart` and
    its AGENTS.md lines; the port's captures at 120x40 and 80x24 beside
    the original's under `docs/design/evidence/CTUI-35/`; each fixture
    flag renders in the tester.

Within A the order is free; B needs A, C needs B, D needs 9 and 13, E
needs C, and F needs E. Unit 33 only measures and can follow 21.
