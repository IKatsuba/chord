# CTUI-56 brief: `chord acp`, a multi-session ACP server on stdio

Lead: architects. Task: `board show CTUI-56`. Split from CTUI-28 (see
"CTUI-28: headless one-shot here, `chord acp` as CTUI-56" in
`docs/decisions.md`).

## The problem

The original's `chord acp [agent]` serves ACP v1 on its own stdin and
stdout, without a window: an editor or another ACP client starts chord as
its agent, and chord starts the real agent (one process per session) and
stands between them, adding its records, settings, queue, titles and its
own extensions. The port has the client half (`example/chord/lib/acp/`),
sessions and records (`lib/session/`), settings (CTUI-29) and headless
helpers (CTUI-28), but nothing that serves ACP. This task designs that
server, as the original does it, for the part of it that does not need
children, teams or monitors.

## The specification

Read, in `../chord` (never edit):

- `docs/guide.md`, section "`chord acp`" (from "## `chord acp`" up to
  "## Settings"): the contract a client sees. It is the primary source.
- `docs/FEATURES.md`, the `chord acp` row and the rows it references.
- `src/acp_agent.ts` (`runAcp`, `AcpOptions`, `AcpRun`, `byHandNote`).
- `src/session/upstream.ts` and `src/session/upstream_commands.ts`.
- What they import that this scope needs: `src/acp/agent_app.ts`,
  `src/acp/stdio.ts`, `src/acp/host_fold.ts`, `src/acp/upstream_turns.ts`,
  `src/session/auth_status.ts`, `src/session/elicitations.ts`,
  `src/session/new_args.ts`, `src/session/place.ts`, the parts of
  `src/session/agents_host.ts` main sessions use, and `src/cli.ts`'s `acp`
  parsing.
- Tests: `tests/acp_agent_test.ts`, `tests/acp_extensions_test.ts`,
  `tests/session/upstream_test.ts`, `upstream_commands_test.ts`,
  `upstream_conversation_test.ts`; `tests/acp_agent_children_test.ts` only
  to see where children plug in.

And in this tree: `example/chord/lib/acp/` (client, `rpc.dart` dispatcher,
`schema.dart`, `process.dart` process groups), `lib/session/` (`session.dart`,
`conversation.dart`, `sessions.dart`, `record*.dart`, `replay.dart`,
`oneshot.dart`, `sign_in.dart`), `lib/headless.dart`, `lib/settings.dart`,
`lib/cli.dart`, `lib/platform/`, and the CTUI-26, CTUI-28 and CTUI-29
entries in `docs/decisions.md`.

## What a client sees (in scope)

A client starts `chord acp codex` (or `--agent-command`, `--model`/`-m`,
`--effort`, `--permission-mode`), keeps both pipes open, and gets:

- `initialize`: ACP v1, agent identity and capabilities, no auth methods;
  starts no agent. Advertises `title`, `auth.status`,
  `promptCapabilities.image` and `embeddedContext`.
- `session/new` (one agent process per session, the `cwd`'s settings and
  `.mcp.json`, client `mcpServers` override by name, `configOptions`
  passed through), `session/list` (chord's records of this agent, optional
  `cwd` filter, no paging), `session/load` (replay, then answer),
  `session/resume` (no replay), `session/close` (stop, keep record).
- `session/prompt` answering when its turn ends; further prompts queue;
  `session/cancel` interrupts and withdraws queued client prompts;
  `$/cancel_request` cancels only the named request (removes a queued
  prompt).
- `session/set_config_option`, `session/set_mode`, `session/set_title`
  (fold whitespace, -32602 empty, -32002 unknown, live vs listed record,
  pending rename sent on next load/resume), `auth/status` and
  `auth/status_update` (oldest live main session).
- `session/request_permission` relayed for permissions and plan approvals;
  `elicitation/create` and `elicitation/complete` relayed (see open
  questions); filesystem and terminal requests not relayed.
- Capability-gated `session/update` (the table in the guide: `plan`,
  `session.compaction`, `session.notices`, `subagents`; kinds outside the
  v1 schema never sent), live and in replay alike; dropped updates stay in
  the record.
- Duplicate live ids get upstream-only aliases (`s1~2`).
- Errors: -32601 unsupported, -32602 malformed / unsupported blocks /
  already open, -32002 unknown or closed session, -32603 shutting down.
- Shutdown: EOF, broken output, a line over 32 MiB, crash, SIGINT, SIGTERM,
  SIGHUP; 15 s deadline, 500 ms write wait, parallel session close, process
  groups killed; exit codes as the guide says.
- `chord acp --nope` exits 2 with empty stdout and the unknown-agent line.

## Not in scope (non-goals)

- Children, teams, tasks, monitors: `_chord/agents/*`, `_chord/monitors/*`,
  `/team`, `/new`, `chord/agent` meta, composite ids, `chord/left_open`
  beyond what a record already holds. They wait for M4/M5 (CTUI-35/36).
  Design the seams where they plug in (session host, update mapping,
  command interception, cancel routing, shutdown), not the features.
- Elicitation forms in the window: CTUI-33.
- Any change to the framework (`lib/`): this is port-only. If an
  architect finds a framework need, say so and why.
- No code is written by this team.

## Constraints

- AGENTS.md is binding: the port follows the original; a difference is
  the owner's to approve. Logic where a test reaches it: the server's
  state and the mapping of updates are plain Dart, testable with
  in-memory processes and the original's fake agent
  (`../chord/tests/fixtures/fake_agent/main.ts`), never a real agent.
- Packages: `json_rpc_2` is already used; say whether its `Server`/`Peer`
  fits the serving side (it does not expose request ids to handlers, which
  `$/cancel_request` needs; see `rpc.dart`), or whether our dispatcher
  extends to it. A package that does not fit as it is goes to the owner.
- Records are the window's records (CTUI-26): either interface reopens
  them; no new record version without the owner.
- Runs under `dart compile exe`; POSIX process groups as `lib/platform/`.

## Open questions, by owner

**framework** (internals of the port's ACP layer, since nothing in `lib/`
is expected):
1. The serving JSON-RPC peer: reuse `rpc.dart`'s dispatcher, `json_rpc_2`
   `Peer`, or both; framing over stdio (newline-delimited, the 32 MiB
   line limit, stdout back-pressure, a malformed line).
2. Module layout under `example/chord/lib/` named after the original's
   files (`acp_agent.dart`, `session/upstream.dart`, `acp/agent_app.dart`,
   `acp/stdio.dart`, ...), and which existing port modules are reused
   unchanged vs. need seams (e.g. `Session`, `Conversation`, `oneshot`).
3. The session host: what object owns live sessions, ids, aliases, the
   prompt queue, titles and auth status; where M4's children attach.

**interface** (the contract a client sees, line by line against the
original):
4. Every method, its params, answers and errors as the original sends
   them, including `_meta["chord/acp"]` on new/load/resume and
   `initialize`; the capability-gating table and the tool-call `session`
   reference stripping.
5. Which commands (`chord/command` replies) exist without `/team` and
   `/new`; what `available_commands_update` carries in this scope.
6. Whether `_chord/session/state` and `_chord/session/steer` (main-only,
   not children/teams/monitors) are in this task, and what `initialize`'s
   `_meta["chord/acp"].extensions` advertises if only some extensions
   exist. This is likely an owner question; give options and a
   recommendation.
7. The elicitation relay until CTUI-33: the port's client declares no
   elicitation and cancels `elicitation/create` itself (CTUI-28 entry).
   What does `chord acp` do, and does serving it need the capability
   declared toward the agent? Options and a recommendation.
8. CLI: `chord acp` parsing, `byHandNote` (a terminal on stdin), exit
   codes, stderr wording.

**runtime** (processes, streams, failure, performance, testability):
9. Concurrency model: per-session queue, ordering of updates vs. answers,
   cancellation (`session/cancel`, `$/cancel_request` on queued vs.
   running), asks between turns, a prompt pending forever when the agent
   ignores cancel.
10. Shutdown and exit codes: each trigger, the 15 s deadline, 500 ms
    write wait, process-group kill, signals, and how each is tested.
11. Load/resume: replay before answer, already-open refusal, pending
    renames, record writes from two processes, settings per `cwd`.
12. Tests: what runs through in-memory processes, what through the
    original's fake agent, what needs a compiled binary in a pty (tag
    `compile`); a benchmark if any (many sessions, update flood).
13. The proposed split into build units for ship, in order, each with
    its tests.

Each architect: answer your questions, flag every difference from the
original with options and a recommendation, and list anything that is
the owner's decision. Write only your own draft:
`docs/design/evidence/CTUI-56/drafts/<framework|interface|runtime>.md`.
