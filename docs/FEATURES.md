# Features

Everything Claude Code's terminal interface does, what in ACP carries it, and
when chord gets it. The rule for the order: a milestone is done when someone can
use chord instead of the agent's own interface for the work that milestone
names, not when its rows are ticked.

"ACP" means the protocol carries it and chord's own ACP layer (`src/acp/`, on
the SDK) hands it on as the agent sent it; "enricher" means chord's layer fills
in what an agent left out of the message before anything records or draws it
(see "chord's own ACP layer" in `docs/decisions.md`). "client" means it is
chord's own and the agent never hears of it. "agent" means it lives inside the
agent and chord passes it through untouched.

## M0 — skeleton (done)

| Feature                        | Carried by | Notes                                   |
| ------------------------------ | ---------- | --------------------------------------- |
| Full-screen window             | client     | OpenTUI (React), alternate screen, fixed layout |
| `chord <agent>`, `chord agents` | client     | the ACP Registry's npx and uvx agents, frozen in `src/registry.ts`; agents' own CLIs in `src/clis.ts`, marked by whether PATH has them; names the settings files alone define |
| Standalone binary, npm shim    | client     | `bun build --compile`, `bun dev npm` |

## M1 — talk to an agent (the MVP)

Done when a person can do a real coding task with Claude Code through chord from
first prompt to commit without opening `claude`.

| Feature                                   | Claude Code                         | Carried by                                   |
| ----------------------------------------- | ----------------------------------- | -------------------------------------------- |
| Start a session in a directory            | `claude`                            | ACP `session/new`                            |
| Send a prompt, stream the reply           | Enter                               | ACP `session/prompt`, `agent_message_chunk`  |
| Markdown in replies                       | rendered                            | client (marked + a terminal renderer)        |
| Thinking, collapsed                       | `∴ Thinking…`, ctrl+o expands       | ACP `agent_thought_chunk`                    |
| Tool calls with status                    | `⏺ Read(file)` … `⎿`                | ACP `tool_call`, `tool_call_update`          |
| Edits as diffs                            | coloured diff under the call        | ACP `tool_call.content` (`type: "diff"`)     |
| Permission prompt                         | inline choice, 1/2/3, Esc rejects; a request with no content shows its arguments | ACP `session/request_permission`             |
| Interrupt the turn                        | Esc                                 | ACP `session/cancel`                         |
| Multiline input                           | `\`+Enter, shift+Enter, paste        | client                                       |
| Prompt history                            | ↑ / ↓                               | client                                       |
| Plan / todo list                          | `☐ ☒` list above the prompt         | ACP `plan`, and `plan_update`'s entries      |
| Status line                               | model, effort, mode, context used   | ACP `usage_update`, `current_mode_update`, `config_option_update` |
| Spinner with elapsed time while working   | `✻ Working… (12s · esc to interrupt)` | client                                     |
| Errors shown, not swallowed               | red line in the transcript          | ACP error answer to `session/prompt`         |
| Quit                                      | ctrl+c twice, ctrl+d (ctrl+c on a draft clears it) | client                        |
| Keyboard shortcuts                        | `?` on an empty prompt lists every key | client                                    |

## M2 — daily driver

Done when chord is the interface its authors open by default.

| Feature                                   | Claude Code                         | Carried by                                   |
| ----------------------------------------- | ----------------------------------- | -------------------------------------------- |
| Permission modes, cycled                  | shift+tab: default → accept edits → plan | ACP `session/set_config_option` on the agent's `mode` config option, else `session/set_mode` |
| Model picker                              | `/model`                            | ACP `model` config option, else `session/set_model` |
| Agent slash commands with completion      | `/` opens the list                  | ACP `available_commands_update`              |
| Client slash commands                     | `/clear` `/resume` `/help` `/exit` `/status` `/cost` `/new` | client               |
| `@` file mentions with fuzzy finder       | `@` opens files                     | client (the path in the prompt text), ACP `resource_link` beside it |
| Bash mode                                 | `!` prefix runs a command           | client, output sent as context               |
| Resume a session                          | `--continue`, `--resume`, `/resume` | chord's own session records, ACP `session/load` / `session/resume` |
| Resume a whole window                     | — (not in Claude Code)              | chord's own window records: `--resume w-…`, `/resume`, `--resume` with no id |
| Queue a prompt while a turn runs          | type and Enter during a turn; Esc puts it back | client, sent once the turn ahead ends |
| Transcript / verbose view                 | ctrl+o                              | client                                       |
| Reverse history search                    | ctrl+r                              | client                                       |
| Headless one-shot                         | `-p "prompt"`, `--output-format json`, `--effort`, `--permission-mode`, `--dangerously-skip-permissions` | ACP, one session, `session/set_config_option` |
| Syntax highlighting in code and diffs     | yes                                 | client                                       |
| Session config options (effort, etc.)     | `/config`, effort                   | ACP `session/set_config_option`              |
| Usage and cost                            | `/cost`, `/context`                 | ACP `session/prompt`'s `usage`, `usage_update`; enricher: a cost from the tokens and a window from the model, marked as chord's estimate |
| Settings files                            | `~/.claude/settings.json`, project  | client: `~/.config/chord/`, `.chord/`        |

## M3 — the rest

| Feature                                   | Claude Code                         | Carried by                                   |
| ----------------------------------------- | ----------------------------------- | -------------------------------------------- |
| Image paste                               | ctrl+v an image                     | ACP `image` content blocks                   |
| Open the prompt in `$EDITOR`              | ctrl+g                              | client                                       |
| Vim mode for the prompt                   | `/vim`                              | client                                       |
| Themes, light and dark                    | `/theme`                            | client                                       |
| Startup header with the logo              | the logo, version, model, directory | client (Chorded's mark as pixel art)         |
| Startup splash                            | the mark drifting while the agent starts | client (the mark at 8 rows, dim)        |
| Notify when the agent waits               | terminal bell, OS notification      | client (BEL, OSC 9 / OSC 777)                |
| Status in the terminal's tab            | OSC 7501, cleared on exit           | client: one root record folding every agent, through OpenTUI's `setProgramStatus` (OSC 7501) |
| Live terminal output of a running command | streaming under the call            | the tool call's `_meta` (`terminal_output_delta`, `terminal_exit`), as Codex's and Claude's adapters send it |
| Subagents shown nested                    | indented task blocks                | ACP `subagent_update` (unstable), each subagent's work under its own session id; enricher: the adapters' `subagent_spawned` and `subagent_state_update` read as it |
| Elicitation forms                         | MCP elicitation                     | ACP `elicitation/create`                     |
| Compaction shown                          | `/compact`, auto-compact notice     | ACP `compaction_update`, `compaction_summary_chunk` (unstable); `/compact` is the agent's own command |
| Rewind to an earlier prompt               | Esc Esc                             | ACP `session/fork` where the agent has it — open |
| MCP servers for the session               | `/mcp`, `.mcp.json`                 | ACP `mcpServers` in `session/new`            |
| Custom keybindings                        | `~/.claude/keybindings.json`        | client                                       |
| Several sessions in one window            | — (not in Claude Code)              | client, one agent per session                |
| Session list across directories           | `/resume` picker, ctrl+a            | client, chord's own session records          |

"open" marks a row acpx's runtime kept out of reach, since it handed chord no
raw messages and had no fork; on chord's own transport each is open to build.

## M4 — agents that start agents

Done when a session can start an agent on another runtime, on the model it
picks, give it a job or a conversation, and hear back, while the person sees
every child and answers its permissions. ACP's own subagents run inside the
agent's runtime; these run on any runtime chord knows, so chord starts them
itself. chord serves an MCP server of its own to every session it opens, beside
the user's servers; its tools are what an agent calls, and chord opens the
sessions, sets the models and carries the messages on its own ACP layer.

| Feature                                   | Claude Code                         | Carried by                                   |
| ----------------------------------------- | ----------------------------------- | -------------------------------------------- |
| chord's MCP server in every session       | —                                   | client: an MCP server in chord, passed in ACP `mcpServers` |
| Runtimes, their models and modes, the open sessions | —                         | client: `list_agents`, `list_sessions`       |
| Task agents, nested in the turn           | Task tool's blocks                  | client: `spawn_task`; its report back as a message; drawn as subagents are |
| Long-lived agents in the parent's session | background agents under the prompt | client: `open_agent`, `send_message`, `close_agent`; a list under the prompt, the picked one's chat and prompt |
| Messages between agents                   | —                                   | client: a new turn for the recipient, `<message from="…">`, or into its running turn through `_session/steering` where it advertises that, after the person's answer to an open question; queued behind a turn otherwise; drawn `←` where it went, and one sent `→` |
| Children on resume                        | —                                   | client, chord's own session records: task blocks and messages as they were, long-lived children named and not reopened |
| Monitors                                  | Monitor tool                        | client: `monitor`, `stop_monitor`, `list_monitors`; output batches and the end reach the owner as messages; monitors and `spawn_task` tasks share a wrapped summary line under the agents list; ↓ selects it, Enter opens the background view (at most half the screen), then a monitor's details, `x` stops an item; every ended item leaves the list at once, only an open monitor detail stays until left, and its end is shown in the transcript; monitors stop with the session; on resume the agent is told which were stopped and not restarted |

A child gets `send_message`, to its own parent, and a long-lived one also
`spawn_task` and `list_agents`, for task agents of its own drawn in its own
turn and closed with it, and the monitor tools for monitors of its own; a
task starts no agent, and a child opens no long-lived one. A long-lived
child whose agent exits or whose turn fails is told to its parent as a
`← chord` message. A child's permission requests go to the person, never to
the parent agent.

## M5 — teams

Done when a person can describe in words how a piece of work should be done,
keep that as a team, and later hand a job to the team and watch it get done
without driving each agent: the lead opens its members, passes them the work
and reports to the person's session, while the person can look in on any of
them and answers their permissions. No daemon and no task board: a team lives
while the window is open, and `--resume` brings it back as M4 brings children
back. Starting agents, messages and the agent list are M4's, reused.
`docs/design/M5-teams.md` is the design.

| Feature                                   | Claude Code                         | Carried by                                   |
| ----------------------------------------- | ----------------------------------- | -------------------------------------------- |
| Team files                                | —                                   | client: `.chord/teams/<name>.md` in the project, the same under `~/.config/chord/` for every project; checked by zod |
| `/team`: describe, save, list, show, run, stop | —                                   | client: a chord slash command; the session's agent proposes the team, or a change to one asked in plain words, and the person's ok saves it |
| Hand a job to a team                      | —                                   | client: a long-lived lead opened with the team's instructions, by `/team` or a tool on chord's MCP server |
| A lead starts its members                 | —                                   | client: one level deeper than M4 — a team's lead opens the file's members; members open no long-lived agents; `spawn_task` is every agent's |
| Each member's runtime, model, effort, start mode | —                                   | client: as `/new` and the settings files set them per agent |
| The team in the agent list                | —                                   | client: the lead and its members nested under it in M4's list, each team folded to its lead's row where the list does not fit |
| The lead reports to main                  | —                                   | client: M4's messages, drawn `← @lead …` |
| Teams on resume                           | —                                   | client, chord's own session and window records: the past drawn, each run named with its agents and not reopened, `/team run` the way back |

Every member works in the session's directory; who edits which files when is
the team's own instructions' business, agreed among the agents, not chord's
code. Members message their lead and each other; a team may run several
times in one window (`bugfix`, `bugfix 2`). A member's permission requests
go to the person, as a child's do.

## Agent-side: passed through, never reimplemented

Hooks, `CLAUDE.md` / `AGENTS.md` memory, skills, subagent definitions, output
styles, the agent's own tool set and its sandbox belong to the agent. chord
shows what they produce and does not interpret them. A feature that would need
chord to understand one agent's private format is out of scope unless ACP
carries it.
