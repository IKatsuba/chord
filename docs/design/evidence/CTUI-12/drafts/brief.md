# CTUI-12 brief: the port's ACP client in Dart

## The problem

The port (`example/chord/`, package `chord`) has its CLI and an interim
window (CTUI-11) but cannot talk to an agent. Every later milestone stands on
an ACP client: M1's session and transcript reducer, the permission prompt,
the status line; M2's modes, models, resume and `chord acp`; M4's children.
The original's layer is `../chord/src/acp/` (`process.ts`, `connection.ts`,
`traffic.ts`, `stdio.ts`, `plans.ts`, `host_fold.ts`, `upstream_turns.ts`,
`agent_app.ts`) on `@agentclientprotocol/sdk` ^2.6 (its `unstable` entry),
used by `../chord/src/acp_agent.ts` and `../chord/src/session/`.

This task designs the Dart counterpart, kept to what M0 and M1 need, and says
what later milestones add on top without reshaping it.

## In scope (M0 and M1)

- Start the agent from `agentStart`'s command (string split as a shell
  would, without expansion, or an argv) in a process group of its own, with
  env laid over chord's and a cwd; keep a bounded tail of its stderr (the
  original's `STDERR_TAIL`, `STDERR_LINES`, `STDERR_LINE_MAX`, `lastWords`).
- Stop it the original's way: stdin ended, then SIGTERM to the group, then
  SIGKILL, each bounded (2 s each); SIGKILL to the group after the exit;
  `AgentExitError` when even that is not seen; idempotent.
- JSON-RPC 2.0 over its stdio as newline-delimited JSON, both directions:
  chord's requests and notifications, and the agent's requests to chord.
- `initialize` (protocol version, client capabilities, client info),
  `session/new`, `session/prompt`, `session/cancel`.
- `session/update` notifications: the kinds M1 draws (agent message and
  thought chunks, user message chunks, tool calls and their updates with
  content, diffs and locations, plan, available commands, current mode,
  usage if M1's status line needs it), with unknown kinds kept, not dropped.
- `session/request_permission`, answered by the session layer, with
  `cancelled` answered by the client when the turn is cancelled, the agent
  withdraws it, or the agent is closing.
- fs and terminal requests: see open question O1.
- The agent exiting (before initialize, mid-turn, after), its stdout
  closing, its writes failing, malformed lines, and the agent hanging (no
  answer to initialize or to a request; ignoring cancel; ignoring stdin's
  end).
- A traffic tap: every message either way and stderr, in wire order, for
  the session record and logs later (the original's `onTraffic`).

## What an author of the port writes

Roughly, the session layer (CTUI-15 and M1) writes:

```dart
final agent = await openAgent(
  command: start.command, env: start.env, cwd: dir,
  onPermission: (request, cancelled) => ...,   // a Future<answer>
  onTraffic: record.add,
);
final session = await agent.newSession(NewSessionRequest(cwd: dir, mcpServers: []));
agent.updates.listen(reducer.fold);            // or a callback
final answer = await agent.prompt(PromptRequest(...));
await agent.cancel(session.sessionId);
await agent.close();
```

The exact shape is the interface architect's to propose; the original's
`Agent` interface is the reference.

## Constraints

- AGENTS.md is binding: a maintained package before our own code for what
  is not the terminal (JSON-RPC, schema types); what was tried goes into
  the design and `docs/decisions.md`; a package that does not fit as it is
  goes to the owner with options, not a workaround on our own call.
- It is the port's (`example/chord/lib/acp/`, named file for file after
  `src/acp/`), not the framework's: `lib/` knows nothing of ACP.
- Logic where a test reaches it: framing, routing, the stop ladder and the
  cancel bookkeeping are testable without a real process; the process layer
  is testable against a real child.
- Builds under `dart compile exe`; POSIX only ("Windows is out").
- The port's tests never reach a real agent: the original's fake agent
  (`../chord/tests/fixtures/fake_agent/main.ts`) run with bun, skipped with a
  message when bun or `../chord` is missing (decisions.md). Wiring it is
  CTUI-13, right after this; the design says how the client is tested
  against it and what CTUI-13 must provide.
- Nothing under `../chord` is edited.

## Non-goals (say where they land)

`session/load`, `resume`, `list`, `fork`, `set_title`, `auth/status`,
`session/set_mode`, `set_model`, `set_config_option` (M2); `_session/steering`
(M2); elicitation, plans of cursor and grok, subagents, compaction, notices
(M3); `chord acp`, `agent_app.ts`, `stdio.ts`, `upstream_turns.ts`,
`host_fold.ts`, relays (M2 headless and M4); the session record format
(its own task). The design names each as a later addition and shows that the
M0/M1 shape takes it without a rewrite.

## Open questions

O1 (owner, via main; decided: (a), main chose it on the owner's behalf and called the task's wording wrong). The task asks for "fs and terminal requests", but the
original's `clientCapabilities()` declares neither `fs` nor `terminal`, on
purpose, "so agents use their own tools for those" (connection.ts). Options:
(a) follow the original: declare neither, answer any such request with
method-not-found, and draw command output from `terminal_output` `_meta` as
the original does; (b) implement them anyway, undeclared, as a dormant
handler; (c) implement and declare them, differing from the original. Lead's
recommendation: (a). The architects design for (a) and say briefly what (c)
would add.

O2 (owner, via main, after the drafts). Which client capabilities M0/M1
declare. The original declares elicitation, plan, session compaction and
notices, subagents and `_meta.terminal_output_delta`, and declaring each
changes what agents send (a plan as reply text when not declared, notices as
reply text). Declaring what M1 does not draw yet would hide things; not
declaring them makes M1 differ from the original until M3. interface and
runtime: list per capability what an agent sends either way.

Framework architect (owns the protocol side here):
- F1. JSON-RPC: try `json_rpc_2` (and anything else on pub.dev: a Dart ACP
  package, `acp_dart` or similar). Does it frame newline-delimited JSON over
  a process's stdio, take requests from the other side, cancel a wait, fail
  every pending request when the stream ends, and keep wire order for a tap?
  Own code only with the finding.
- F2. Types: is there a Dart ACP SDK; can the ACP JSON schema
  (`schema.json` in the agent-client-protocol repository, and the version
  the original's SDK 2.6 pins) generate Dart types under `dart compile exe`
  (quicktype, `json_serializable`, a generator of our own)? What about the
  unstable parts and `_meta`? Hand-written, generated, or untyped maps at the
  edges?
- F3. Unknown fields and unknown update kinds: kept, round-tripped, ignored?
- F4. Protocol version negotiation and what happens on a mismatch.

Interface architect (what the session layer and screens need):
- I1. The client's Dart surface (the `Agent` counterpart): futures, streams
  or callbacks for updates and for the agent's requests; how a permission
  request is handed to the screen and withdrawn.
- I2. What M1's reducer and screens read from each update kind, and from
  `initialize`'s answer (agent info, capabilities, auth methods).
- I3. The errors a person sees (the agent would not start, went away,
  stopped answering) and the original's wording for each
  (`start_failure.ts`, `AgentGone`).
- I4. O2 above, from the screens' side.

Runtime architect (processes, streams, failure modes, tests):
- R1. The process group in Dart: `Process.start` has no `setsid`/`setpgid`;
  how the original's `spawnGroup` (`src/platform/process.ts`) is matched
  (a `setsid` wrapper, `dart:ffi` `posix_spawn`, a package), and how a
  signal reaches the group.
- R2. The stop ladder, exit vs stdout end vs stderr end ordering, writes to
  an agent that stopped reading (backpressure), a hung agent.
- R3. Cancel: what is answered `cancelled` and when, prompt settling after
  cancel, a cancel the agent ignores.
- R4. Tests: unit (framing, routing, stop) without processes; against a tiny
  Dart or shell child for the process group; against the original's fake
  agent with bun (CTUI-13): which scenarios cover M0/M1, how the test finds
  bun and `../chord`, and the skip.
- R5. Performance: a thousand updates a second reaching the reducer without
  a frame each (the framework batches per frame).
