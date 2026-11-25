# CTUI-35 brief: chord's MCP server, children and messages between agents

The original's M4 row "chord's MCP server, children, messages" (`../chord`
`docs/FEATURES.md` M4, `docs/guide.md` lines ~1322-1480 and `chord acp`'s
"Children, teams and commands" and "Extensions"), ported to the window and
to `chord acp`. Board comments add: the live `@@` roster (from CTUI-24) and
`chord acp`'s `_chord/agents/send|close`, `/new` and the advertised
`agents` extension (from CTUI-56). The `_chord/monitors` extension is
CTUI-36's.

## The problem

Today the port's window drives one ACP session. M4 makes it a host of many:
main, long-lived children opened by main's agent, task agents nested in a
turn, each on any runtime chord knows. The agent reaches them through an MCP
server chord serves itself, on the loopback over Streamable HTTP, one per
window, with a token per session that says who calls and so which tools it
has.

## What a person sees and presses

- The agents list under the status line while a session has children:
  `main`, then children in opening order; colour per child; runtime, model,
  effort, state (`● permission 17s`, `✻ working 41s`, `◦ idle 3m`,
  `✗ exited`, `✗ failed to start`) and an unseen-news column (`✗ turn
  failed`, `✓ new reply`, `← new message`); giving way as room narrows;
  folding to one row and `… +N more` in short windows.
- ↓ on an empty prompt enters the list; ↑ ↓ / j k pick; Enter, Esc or ↑ from
  the top returns. The picked agent's chat fills the window, the box takes
  its colour and name, the status line its model; typed prompts go to it.
  Drafts set aside per agent with ↓ and brought back with ↑.
- `x` closes the picked child (twice while it works or waits); ctrl+x a
  picks a child that waits on the person; its permission opens there.
- Task agents draw in the parent's turn as subagent blocks
  (`Agent(<name>) · codex · <model>`, `Done (… · 13s)`), groups
  `Running 2 agents…`.
- Messages: `←` rows where they arrive, `→` rows where sent, held messages
  above the prompt (`← from @main · after the running calls: …`), steering
  into a running turn where `_session/steering` is advertised, queueing
  otherwise; `← from chord` notes on exit or failed turn.
- `/clear` on a picked child clears only it; parent's `clear_agent`.
- Resume: task blocks and messages as they were; long-lived children named,
  not reopened.
- `@@` completion offers the live recipients of the picked session.

## What an agent calls

`list_agents`, `list_sessions`, `spawn_task`, `open_agent`,
`send_message`, `close_agent`, `clear_agent`, with the original's
descriptions, inputs, answers, refusals and per-role tool sets (main, child,
task; fork restrictions are CTUI-74's but the role split must carry them).

## Constraints

- AGENTS.md binds. The port follows `../chord` (`src/server/`,
  `src/session/agents_host.ts`, `open_agents.ts`, `tasks.ts`,
  `window_agents.ts`, `new_args.ts`, `upstream_commands.ts`,
  `src/ui/agents/`, `src/acp_agent.ts`), files named after the original's.
- MCP and HTTP serving are not about the terminal: a maintained pub.dev
  package before our own code (try `dart_mcp`, `mcp_dart`, `shelf`,
  `dart:io HttpServer`); must work under `dart compile exe`. If none fits
  as it is, that is the owner's question, not ours.
- Logic in plain Dart reachable by tests; widgets draw and dispatch. Every
  action has a key bound through `Actions` and listed in the shortcuts
  panel (`agents:close` is already read, bound to nothing: CTUI-31).
- Generic needs go to `lib/` with their own tests only if the port truly
  needs a general widget; prefer what the framework already has.
- Tests: in memory, scripted children or the original's fake
  (`../chord/tests/fixtures/fake_agent/`); never a real agent. Records in
  isolated `XDG_STATE_HOME`.
- Features first; no extras beyond the original.

## Non-goals (seams only)

- CTUI-36: `monitor`, `stop_monitor`, `list_monitors`, the background view
  and its summary line under the agents list, `logStep`/`FOLLOWING`,
  `_chord/monitors`. Leave the summary row's slot, the ↓ path into it, and
  the per-owner monitor registry closed with the session.
- CTUI-74: `/fork`, forks beside main in the list, fork tool refusals.
  Leave a top-level-agent kind in the roster and the role in `Caller`.
- CTUI-37: teams, `list_teams`, `run_team`, `propose_team`, `get_budgets`,
  team leads and members in the list. Leave lead/member in the roster
  model, but build none of it.
- The `settings` tool on chord's server: not in the task; see the open
  question below.

## Open questions

Framework architect:
1. Does the agents list need anything new from `lib/` (a list that wraps
   rows and counts lines toward a limit, folding to `… +N more`), or does
   `Column`/`ListView`/`TextLayout` already carry it?
2. Switching the whole window's chat between sessions: one transcript view
   rebuilt per picked session, or one retained per session? Cost for long
   transcripts and selection.
3. Room arithmetic: transcript gives way first, then the list; how is this
   expressed in layout without a second pass?

Interface architect:
1. The window state with many sessions: what moves from today's single
   session state into a per-agent state, what stays window-wide (picked
   agent, drafts set aside, list focus)?
2. Keys: ↓/↑ into and out of the list, j/k, Enter, Esc, `x` twice,
   ctrl+x a, draft set-aside rules, vim j/k; binding ids and contexts, and
   their conflict with history walking and open lists.
3. Captures to compare: the list at 120x40 and 80x24 in each state, task
   blocks, `←`/`→` rows, held messages; which `../chord` fixtures/tools
   produce the original's captures.
4. `@@` roster wiring from CTUI-24's injected snapshot.

Runtime architect:
1. The MCP server: package trial (`dart_mcp`, `mcp_dart`, others) for
   Streamable HTTP on loopback with bearer tokens, admit/revoke per
   session, under AOT. The name `chord`/`chord-2` beside user servers;
   only for agents that take MCP over HTTP.
2. Session hosting: the original's `agents_host.ts` as a pure reducer plus
   effects; children's ACP processes, start failure, exit, eight-child
   limit, close and process-group ends, `/clear` and `clear_agent`.
3. Messages: queue, steering through `_session/steering`, held after an
   answer, the "agent started this on its own" cancel, delivery once.
4. `spawn_task`: nesting in the parent's turn, report on first turn end,
   Esc stops tasks, cost and tokens in the block, effort/model refusal.
5. `list_agents` probing runtimes (60 s bound, cache per window).
6. Records and resume: what is written per child and per message, and how
   resume draws them without reopening.
7. `chord acp`: `_chord/agents/send|close`, `/new`, the `agents`
   extension advertisement and `subagents` traffic toward the client.
8. Seams for CTUI-36 (monitor registry per owner, events as messages) and
   CTUI-74 (fork as a top-level agent).

All three: an ordered unit split for ship, each unit with the tests that
would fail without it.
