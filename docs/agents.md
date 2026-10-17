# What every agent can do (CHD-433)

Every agent chord can start, read for what it can do over ACP and how: the
25 in the ACP Registry, at the versions `src/registry.ts` pins (fetched
2026-10-17, refreshed by CHD-432), and the 11 CLIs in `src/clis.ts`, at
the release current when they were read. Section 1 is the summary, agents as
rows; section 2 is what chord itself uses of each capability and what it
leaves unused; section 3 has a part per agent with the details and sources;
section 4 is what this changes on the board, for the owner. Agents go by their
registry id or CLI name; chord itself calls `claude-acp` `claude` and
`codex-acp` `codex`.

It builds on the CHD-432 study at the same registry pins,
[`design/registry-2026-10-17.md`](design/registry-2026-10-17.md), and on
[`design/CHD-1.md`](design/CHD-1.md) for forms and permissions. Nothing was
run against a model. Packages, release notes, docs and public repositories
were read only, and a bundle whose licence forbids decoding was read as plain
text.

## 1. Summary

Each cell gives what holds and how it is known:

- `c`: read in the agent's code or bundle at the version read, cited in its
  part of section 3.
- `n`: from release notes, docs or binary strings only.
- `r`: taken from earlier work in this repository, named in the agent's part.

`✓` means supported, `◐` partly, `✗` no, and `?` unknown. A footnote in
the agent's part says how. The capability codes (A1, B14…) are the reading's
columns; section 3 uses them too.

### ACP (A1–A3)

| Agent | Protocol version | SDK | Surfaces |
| --- | --- | --- | --- |
| agoragentic-acp |  |  |  |
| auggie |  |  |  |
| autohand |  |  |  |
| bob |  |  |  |
| claude-acp |  |  |  |
| cline |  |  |  |
| codebuddy-code |  |  |  |
| codex-acp |  |  |  |
| deepagents |  |  |  |
| dimcode |  |  |  |
| dirac |  |  |  |
| factory-droid |  |  |  |
| fast-agent |  |  |  |
| gemini |  |  |  |
| github-copilot-cli |  |  |  |
| glm-acp-agent |  |  |  |
| grok-build |  |  |  |
| kilo |  |  |  |
| minimax-code |  |  |  |
| minion-code |  |  |  |
| nova |  |  |  |
| pi-acp |  |  |  |
| qoder |  |  |  |
| qwen-code |  |  |  |
| sigit |  |  |  |
| cursor |  |  |  |
| devin |  |  |  |
| fx |  |  |  |
| goose |  |  |  |
| junie |  |  |  |
| kimi |  |  |  |
| kiro |  |  |  |
| openclaw |  |  |  |
| opencode |  |  |  |
| poolside |  |  |  |
| zeroclaw |  |  |  |

### Sessions (B3–B8)

| Agent | New | Load | Resume | List | Fork | Delete · close |
| --- | --- | --- | --- | --- | --- | --- |
| agoragentic-acp |  |  |  |  |  |  |
| auggie |  |  |  |  |  |  |
| autohand |  |  |  |  |  |  |
| bob |  |  |  |  |  |  |
| claude-acp |  |  |  |  |  |  |
| cline |  |  |  |  |  |  |
| codebuddy-code |  |  |  |  |  |  |
| codex-acp |  |  |  |  |  |  |
| deepagents |  |  |  |  |  |  |
| dimcode |  |  |  |  |  |  |
| dirac |  |  |  |  |  |  |
| factory-droid |  |  |  |  |  |  |
| fast-agent |  |  |  |  |  |  |
| gemini |  |  |  |  |  |  |
| github-copilot-cli |  |  |  |  |  |  |
| glm-acp-agent |  |  |  |  |  |  |
| grok-build |  |  |  |  |  |  |
| kilo |  |  |  |  |  |  |
| minimax-code |  |  |  |  |  |  |
| minion-code |  |  |  |  |  |  |
| nova |  |  |  |  |  |  |
| pi-acp |  |  |  |  |  |  |
| qoder |  |  |  |  |  |  |
| qwen-code |  |  |  |  |  |  |
| sigit |  |  |  |  |  |  |
| cursor |  |  |  |  |  |  |
| devin |  |  |  |  |  |  |
| fx |  |  |  |  |  |  |
| goose |  |  |  |  |  |  |
| junie |  |  |  |  |  |  |
| kimi |  |  |  |  |  |  |
| kiro |  |  |  |  |  |  |
| openclaw |  |  |  |  |  |  |
| opencode |  |  |  |  |  |  |
| poolside |  |  |  |  |  |  |
| zeroclaw |  |  |  |  |  |  |

### Modes, models and options (B9–B12)

| Agent | Modes | Models | Config options | Effort |
| --- | --- | --- | --- | --- |
| agoragentic-acp |  |  |  |  |
| auggie |  |  |  |  |
| autohand |  |  |  |  |
| bob |  |  |  |  |
| claude-acp |  |  |  |  |
| cline |  |  |  |  |
| codebuddy-code |  |  |  |  |
| codex-acp |  |  |  |  |
| deepagents |  |  |  |  |
| dimcode |  |  |  |  |
| dirac |  |  |  |  |
| factory-droid |  |  |  |  |
| fast-agent |  |  |  |  |
| gemini |  |  |  |  |
| github-copilot-cli |  |  |  |  |
| glm-acp-agent |  |  |  |  |
| grok-build |  |  |  |  |
| kilo |  |  |  |  |
| minimax-code |  |  |  |  |
| minion-code |  |  |  |  |
| nova |  |  |  |  |
| pi-acp |  |  |  |  |
| qoder |  |  |  |  |
| qwen-code |  |  |  |  |
| sigit |  |  |  |  |
| cursor |  |  |  |  |
| devin |  |  |  |  |
| fx |  |  |  |  |
| goose |  |  |  |  |
| junie |  |  |  |  |
| kimi |  |  |  |  |
| kiro |  |  |  |  |
| openclaw |  |  |  |  |
| opencode |  |  |  |  |
| poolside |  |  |  |  |
| zeroclaw |  |  |  |  |

### Prompt content (B13)

| Agent | Text | Image | Audio | Resource | Resource link |
| --- | --- | --- | --- | --- | --- |
| agoragentic-acp |  |  |  |  |  |
| auggie |  |  |  |  |  |
| autohand |  |  |  |  |  |
| bob |  |  |  |  |  |
| claude-acp |  |  |  |  |  |
| cline |  |  |  |  |  |
| codebuddy-code |  |  |  |  |  |
| codex-acp |  |  |  |  |  |
| deepagents |  |  |  |  |  |
| dimcode |  |  |  |  |  |
| dirac |  |  |  |  |  |
| factory-droid |  |  |  |  |  |
| fast-agent |  |  |  |  |  |
| gemini |  |  |  |  |  |
| github-copilot-cli |  |  |  |  |  |
| glm-acp-agent |  |  |  |  |  |
| grok-build |  |  |  |  |  |
| kilo |  |  |  |  |  |
| minimax-code |  |  |  |  |  |
| minion-code |  |  |  |  |  |
| nova |  |  |  |  |  |
| pi-acp |  |  |  |  |  |
| qoder |  |  |  |  |  |
| qwen-code |  |  |  |  |  |
| sigit |  |  |  |  |  |
| cursor |  |  |  |  |  |
| devin |  |  |  |  |  |
| fx |  |  |  |  |  |
| goose |  |  |  |  |  |
| junie |  |  |  |  |  |
| kimi |  |  |  |  |  |
| kiro |  |  |  |  |  |
| openclaw |  |  |  |  |  |
| opencode |  |  |  |  |  |
| poolside |  |  |  |  |  |
| zeroclaw |  |  |  |  |  |

### Tool calls (B14)

| Agent | Kinds | `rawInput` | `rawOutput` | Content: text · diff · terminal | Locations | Status lifecycle |
| --- | --- | --- | --- | --- | --- | --- |
| agoragentic-acp |  |  |  |  |  |  |
| auggie |  |  |  |  |  |  |
| autohand |  |  |  |  |  |  |
| bob |  |  |  |  |  |  |
| claude-acp |  |  |  |  |  |  |
| cline |  |  |  |  |  |  |
| codebuddy-code |  |  |  |  |  |  |
| codex-acp |  |  |  |  |  |  |
| deepagents |  |  |  |  |  |  |
| dimcode |  |  |  |  |  |  |
| dirac |  |  |  |  |  |  |
| factory-droid |  |  |  |  |  |  |
| fast-agent |  |  |  |  |  |  |
| gemini |  |  |  |  |  |  |
| github-copilot-cli |  |  |  |  |  |  |
| glm-acp-agent |  |  |  |  |  |  |
| grok-build |  |  |  |  |  |  |
| kilo |  |  |  |  |  |  |
| minimax-code |  |  |  |  |  |  |
| minion-code |  |  |  |  |  |  |
| nova |  |  |  |  |  |  |
| pi-acp |  |  |  |  |  |  |
| qoder |  |  |  |  |  |  |
| qwen-code |  |  |  |  |  |  |
| sigit |  |  |  |  |  |  |
| cursor |  |  |  |  |  |  |
| devin |  |  |  |  |  |  |
| fx |  |  |  |  |  |  |
| goose |  |  |  |  |  |  |
| junie |  |  |  |  |  |  |
| kimi |  |  |  |  |  |  |
| kiro |  |  |  |  |  |  |
| openclaw |  |  |  |  |  |  |
| opencode |  |  |  |  |  |  |
| poolside |  |  |  |  |  |  |
| zeroclaw |  |  |  |  |  |  |

### Asking the person (B15–B17)

| Agent | Permission options | On cancel or timeout | Elicitation: form · URL | Plan |
| --- | --- | --- | --- | --- |
| agoragentic-acp |  |  |  |  |
| auggie |  |  |  |  |
| autohand |  |  |  |  |
| bob |  |  |  |  |
| claude-acp |  |  |  |  |
| cline |  |  |  |  |
| codebuddy-code |  |  |  |  |
| codex-acp |  |  |  |  |
| deepagents |  |  |  |  |
| dimcode |  |  |  |  |
| dirac |  |  |  |  |
| factory-droid |  |  |  |  |
| fast-agent |  |  |  |  |
| gemini |  |  |  |  |
| github-copilot-cli |  |  |  |  |
| glm-acp-agent |  |  |  |  |
| grok-build |  |  |  |  |
| kilo |  |  |  |  |
| minimax-code |  |  |  |  |
| minion-code |  |  |  |  |
| nova |  |  |  |  |
| pi-acp |  |  |  |  |
| qoder |  |  |  |  |
| qwen-code |  |  |  |  |
| sigit |  |  |  |  |
| cursor |  |  |  |  |
| devin |  |  |  |  |
| fx |  |  |  |  |
| goose |  |  |  |  |
| junie |  |  |  |  |
| kimi |  |  |  |  |
| kiro |  |  |  |  |
| openclaw |  |  |  |  |
| opencode |  |  |  |  |
| poolside |  |  |  |  |
| zeroclaw |  |  |  |  |

### The turn (B18–B21)

| Agent | Cancel stops | Steering | Subagents | Usage: meter · answer · cost |
| --- | --- | --- | --- | --- |
| agoragentic-acp |  |  |  |  |
| auggie |  |  |  |  |
| autohand |  |  |  |  |
| bob |  |  |  |  |
| claude-acp |  |  |  |  |
| cline |  |  |  |  |
| codebuddy-code |  |  |  |  |
| codex-acp |  |  |  |  |
| deepagents |  |  |  |  |
| dimcode |  |  |  |  |
| dirac |  |  |  |  |
| factory-droid |  |  |  |  |
| fast-agent |  |  |  |  |
| gemini |  |  |  |  |
| github-copilot-cli |  |  |  |  |
| glm-acp-agent |  |  |  |  |
| grok-build |  |  |  |  |
| kilo |  |  |  |  |
| minimax-code |  |  |  |  |
| minion-code |  |  |  |  |
| nova |  |  |  |  |
| pi-acp |  |  |  |  |
| qoder |  |  |  |  |
| qwen-code |  |  |  |  |
| sigit |  |  |  |  |
| cursor |  |  |  |  |
| devin |  |  |  |  |
| fx |  |  |  |  |
| goose |  |  |  |  |
| junie |  |  |  |  |
| kimi |  |  |  |  |
| kiro |  |  |  |  |
| openclaw |  |  |  |  |
| opencode |  |  |  |  |
| poolside |  |  |  |  |
| zeroclaw |  |  |  |  |

### Commands, titles, login and calls back (B22–B26)

| Agent | Available commands | Session title | Login (`authenticate`) | Client `fs` · `terminal` | MCP: stdio · http · sse |
| --- | --- | --- | --- | --- | --- |
| agoragentic-acp |  |  |  |  |  |
| auggie |  |  |  |  |  |
| autohand |  |  |  |  |  |
| bob |  |  |  |  |  |
| claude-acp |  |  |  |  |  |
| cline |  |  |  |  |  |
| codebuddy-code |  |  |  |  |  |
| codex-acp |  |  |  |  |  |
| deepagents |  |  |  |  |  |
| dimcode |  |  |  |  |  |
| dirac |  |  |  |  |  |
| factory-droid |  |  |  |  |  |
| fast-agent |  |  |  |  |  |
| gemini |  |  |  |  |  |
| github-copilot-cli |  |  |  |  |  |
| glm-acp-agent |  |  |  |  |  |
| grok-build |  |  |  |  |  |
| kilo |  |  |  |  |  |
| minimax-code |  |  |  |  |  |
| minion-code |  |  |  |  |  |
| nova |  |  |  |  |  |
| pi-acp |  |  |  |  |  |
| qoder |  |  |  |  |  |
| qwen-code |  |  |  |  |  |
| sigit |  |  |  |  |  |
| cursor |  |  |  |  |  |
| devin |  |  |  |  |  |
| fx |  |  |  |  |  |
| goose |  |  |  |  |  |
| junie |  |  |  |  |  |
| kimi |  |  |  |  |  |
| kiro |  |  |  |  |  |
| openclaw |  |  |  |  |  |
| opencode |  |  |  |  |  |
| poolside |  |  |  |  |  |
| zeroclaw |  |  |  |  |  |

### Capabilities (B1–B2)

| Agent | Agent capabilities advertised | Client capabilities read |
| --- | --- | --- |
| agoragentic-acp |  |  |
| auggie |  |  |
| autohand |  |  |
| bob |  |  |
| claude-acp |  |  |
| cline |  |  |
| codebuddy-code |  |  |
| codex-acp |  |  |
| deepagents |  |  |
| dimcode |  |  |
| dirac |  |  |
| factory-droid |  |  |
| fast-agent |  |  |
| gemini |  |  |
| github-copilot-cli |  |  |
| glm-acp-agent |  |  |
| grok-build |  |  |
| kilo |  |  |
| minimax-code |  |  |
| minion-code |  |  |
| nova |  |  |
| pi-acp |  |  |
| qoder |  |  |
| qwen-code |  |  |
| sigit |  |  |
| cursor |  |  |
| devin |  |  |
| fx |  |  |
| goose |  |  |
| junie |  |  |
| kimi |  |  |
| kiro |  |  |
| openclaw |  |  |
| opencode |  |  |
| poolside |  |  |
| zeroclaw |  |  |

### Custom extensions (C)

One entry per extension: what it gives, what a client has to do to get it,
and what it costs. The cell names the extensions; the agent's part has the
rest.

| Agent | Extensions | Opt-in needed | chord uses |
| --- | --- | --- | --- |
| agoragentic-acp |  |  |  |
| auggie |  |  |  |
| autohand |  |  |  |
| bob |  |  |  |
| claude-acp |  |  |  |
| cline |  |  |  |
| codebuddy-code |  |  |  |
| codex-acp |  |  |  |
| deepagents |  |  |  |
| dimcode |  |  |  |
| dirac |  |  |  |
| factory-droid |  |  |  |
| fast-agent |  |  |  |
| gemini |  |  |  |
| github-copilot-cli |  |  |  |
| glm-acp-agent |  |  |  |
| grok-build |  |  |  |
| kilo |  |  |  |
| minimax-code |  |  |  |
| minion-code |  |  |  |
| nova |  |  |  |
| pi-acp |  |  |  |
| qoder |  |  |  |
| qwen-code |  |  |  |
| sigit |  |  |  |
| cursor |  |  |  |
| devin |  |  |  |
| fx |  |  |  |
| goose |  |  |  |
| junie |  |  |  |
| kimi |  |  |  |
| kiro |  |  |  |
| openclaw |  |  |  |
| opencode |  |  |  |
| poolside |  |  |  |
| zeroclaw |  |  |  |

## 2. What chord uses today and leaves unused

Read in chord's own client at HEAD 287fedc3: `src/acp/`, `src/session/`,
`src/headless.ts` and the launch in `src/agents.ts` and `src/clis.ts`, on
`@agentclientprotocol/sdk` 1.8.0. Each entry says what chord uses and what it
leaves unused, in the summary's codes.

Four things are not as earlier notes had them: chord never calls
`session/list`; a cost of 0 from an agent counts as a cost and stops chord's
estimate (CHD-380 is still open); a subagent is never cancelled on its own
session id; and steering carries only messages from other agents, never the
person's own prompts.

### What chord asks for and declares

- **A1–A3, ACP.** chord asks for protocol version 1, the SDK's
  `PROTOCOL_VERSION`, as `clientInfo {name: 'chord', version}`
  (`src/acp/connection.ts:356-360`). It also calls `session/set_model`, which version 1 has not made stable
  (`src/acp/connection.ts:60`). Unused: anything of a later protocol version.
- **B1, agent capabilities.** Read: `loadSession`,
  `sessionCapabilities.resume`, `promptCapabilities.image`,
  `mcpCapabilities.http` and `_meta.steering.supported`. Unused: `authMethods`,
  `promptCapabilities.audio` and `embeddedContext`, `mcpCapabilities.sse`, and
  `sessionCapabilities` list, fork, close and delete.
- **B2, client capabilities.** Declared: `elicitation` (form and URL), `plan`,
  `session.compaction`, `subagents`, and `_meta.terminal_output_delta`
  (`src/acp/connection.ts:184-190`). Not declared: `fs` and `terminal`. chord
  answers only `session/request_permission` and `elicitation/create`; every
  other request from an agent, `fs/*`, `terminal/*` and extension methods
  included, gets the SDK's method-not-found. Notifications other than
  `session/update` are dropped without a trace, `elicitation/complete` and
  extension notifications included (`src/acp/traffic.ts`,
  `src/session/session.ts`).

### Sessions (B3–B8)

- **B3, new.** `{cwd, mcpServers}`, with no `_meta`
  (`src/session/session.ts:415`). Unused: `_meta` on `session/new`, such as
  instructions, or Claude's `promptSuggestions: false` (CHD-432 C10, C17).
- **B4–B5, load and resume.** Resume when the agent offers it and chord has
  its own record of the session, or the agent has no `loadSession`; load
  otherwise, with the same MCP servers (`src/session/session.ts:713-727`).
- **B6, list.** The SDK call is wrapped (`src/acp/connection.ts:404`) but
  never made. `/resume` and the other pickers read chord's own records
  (`src/session/sessions.ts`).
- **B7–B8, fork, delete, close.** Never called.

### Modes, models and options (B9–B12)

- **B9, modes.** Through the agent's mode config option if it has one, else
  `session/set_mode`; `current_mode_update` is read. An enricher fills in the
  mode Codex leaves out after `set_mode` (`src/session/enrichers.ts`).
- **B10, models.** Through the `model` config option if there is one, else
  `session/set_model`; the list comes from the `session/new` answer
  (`src/session/session.ts:622-647`, `src/session/agent_state.ts`).
- **B11, config options.** `session/set_config_option` and
  `config_option_update`.
- **B12, effort.** Only a select option of category `thought_level`, never by
  its id; chord keeps no effort list of its own per agent
  (`src/session/efforts.ts`).

### Prompt content (B13)

- **Used:** text, base64 images when `promptCapabilities.image` is set, and
  one `resource_link` per `@` mention (`src/session/session.ts:538-556`).
- **Unused:** audio and embedded `resource` blocks are never sent. Images and
  resources inside an agent's message and thought chunks are dropped
  (`src/session/transcript/messages.ts`); only a replayed history shows them.

### Tool calls (B14)

- **Used:** title, kind, status (only forward), locations, content, rawInput
  and rawOutput are kept (`src/session/transcript/tools.ts`). Text content and
  diffs are drawn; other content shows as its type. Without the `terminal`
  capability a `terminal` content block names only an id, so a command's
  output comes from the tool call's `_meta` (`terminal_info`,
  `terminal_output_delta`, `terminal_output`, `terminal_exit`). Claude's
  `_meta.claudeCode.nonExecutionKind` marks an interrupted call.
- **Unused:** rawOutput is kept but never drawn, and locations show only in
  the permission box.

### Asking the person (B15–B17)

- **B15, permissions.** All four option kinds are offered. Esc answers
  `reject_once`, else `reject_always`, else `cancelled`; a withdrawn request
  or a closed session also answers `cancelled`
  (`src/session/permissions.ts`). A request with no turn running is rejected
  without being shown (CHD-158). Under `-p` a request is refused unless
  `--dangerously-skip-permissions` allows it, with `allow_once` before
  `allow_always`.
- **B16, elicitation.** Forms: string fields (text, or a choice by `enum` or
  `oneOf`), number, integer, boolean, and a multiple choice by `enum` or
  `anyOf`; any other field stays unset (`src/ui/dialogs/form.ts`). Esc
  cancels, Decline declines. The question shapes of Claude, Codex, droid,
  OpenCode and DimCode are read into one question box
  (`src/session/enrichers.ts`, `src/session/questions.ts`). URL: Open or
  Decline. Unused: `elicitation/complete`. A form with no turn running is
  cancelled (CHD-158); `-p` declines forms and cancels URLs.
- **B17, plans.** `plan` replaces the live list; `plan_update` keeps its items
  as the live list and draws a markdown plan as reply text; `plan_removed`
  takes it away (`src/session/transcript/plans.ts`).

### The turn (B18–B21)

- **B18, cancel.** `session/cancel` on the root session only. Pending
  permissions and forms of the parent and of every known subagent are
  answered `cancelled` at once (`src/acp/connection.ts:426-434`); running
  subagents are marked cancelled when the turn settles
  (`src/session/transcript/turn.ts`). Tool calls are not marked; they move
  only on the agent's updates. Unused: `session/cancel` on one subagent's
  session id (CHD-432 C15).
- **B19, steering.** `_session/steering` when the agent answers
  `_meta.steering.supported: true`, sent with
  `_meta.steering.idleBehavior: 'promptRequired'`, for messages from other
  agents only (`send_message`, task reports). A prompt the person sends
  mid-turn is always queued until the turn ends
  (`src/session/conversation.ts`).
- **B20, subagents.** The RFD's `subagent_update`, and Codex's draft
  `subagent_spawned` reshaped into it by an enricher. `running` and
  `requires_action` read running, `idle` completed whatever its stopReason,
  and `unknown` keeps the previous state
  (`src/session/transcript/subagents.ts`). A child's traffic is routed by its
  session id; its usage, modes and commands are not folded into the
  session's. Unused: `session_message` (a subagent's full task), the
  stopReason of `idle`, and a stop per subagent.
- **B21, usage and cost.** `usage_update` (used, size, cost) and
  `PromptResponse.usage`; with no cost from the agent, chord estimates one
  from the tokens through `@pydantic/genai-prices` (`src/session/prices.ts`,
  `src/session/enrichers.ts`). Any cost the agent sends, 0 included, stops
  the estimate for the rest of the session (`src/session/enrich.ts:304-325`).
  Unused: usage or cost an agent sends in its own `_meta` or methods.

### Commands, titles, login and calls back (B22–B26)

- **B22, available commands.** `available_commands_update` is kept as the
  agent's slash commands (`src/session/agent_state.ts`).
- **B23, session title.** `session_info_update` is dropped.
- **B24, login.** chord never calls `authenticate` and does not read
  `authMethods`. An `authRequired` error shows as a failed start or a failed
  turn, with its message.
- **B25, `fs` and `terminal`.** Not declared, so never called back; requests
  get method-not-found.
- **B26, MCP servers.** The person's servers from settings and `.mcp.json`
  (stdio, http, sse) are passed as they are, never checked against the
  agent's `mcpCapabilities`. chord's own server goes in, over http, only when
  `mcpCapabilities.http` is true, and never under `-p`.

### Other updates

- **Used:** `compaction_update` and summary chunks are drawn
  (`src/session/transcript/compactions.ts`); chord never starts a compaction
  itself. A user's own message chunks are read only when a history is
  replayed.
- **Dropped:** `session_info_update`, `notice`, `session_message`,
  `session_message_chunk`, a live `user_message_chunk`, and any kind chord
  does not know.

### Custom (C)

- **Read:** `_meta.steering.supported`; `_meta.claudeCode.nonExecutionKind`;
  the `terminal_*` keys of a tool call's `_meta`; Codex's
  `_meta.is_mcp_tool_call` and `_meta.codex` (`autoResolutionMs`, a
  `user_note` role, `isSecret`); `_claude/askUserQuestionOption` previews;
  DimCode's `_meta.lody.elicitation.customAnswerFor`.
- **Sent:** `_meta.terminal_output_delta` in the client capabilities,
  `_meta.steering.idleBehavior` on a steer, and
  `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` in Claude's environment
  (`src/session/session.ts:99-105`).
- **Unused:** every other extension, listed per agent in section 1's custom
  table, among them Claude's `asyncTasks` and prompt suggestions, which its
  adapter gives only to JetBrains AIR,
  qwen's `_qwencode` turns, DimCode's `_lody` notifications and codebuddy's
  terminal output.

## 3. The agents

Each part gives the version read and where from, then A, B and C in the
summary's codes with a footnote per cell, what chord does with it today, and
the sources.

### In the ACP Registry

#### agoragentic-acp

- Name: Agoragentic
- Pinned: `agoragentic-mcp` 1.3.0
- Run as: `npx -y agoragentic-mcp@1.3.0 --acp`
- Source: <https://github.com/rhein1/agoragentic-integrations>

Not yet filled.

#### auggie

- Name: Auggie CLI
- Pinned: `@augmentcode/auggie` 0.36.0
- Run as: `npx -y @augmentcode/auggie@0.36.0 --acp`
- Source: <https://github.com/augmentcode/auggie>

Not yet filled.

#### autohand

- Name: Autohand Code
- Pinned: `@autohandai/autohand-acp` 0.2.1
- Run as: `npx -y @autohandai/autohand-acp@0.2.1`
- Source: <https://github.com/autohandai/autohand-acp>

Not yet filled.

#### bob

- Name: Bob
- Pinned: `@ibm/bob` 2.0.8
- Run as: `npx -y @ibm/bob@2.0.8 acp`
- Source: <https://bob.ibm.com>

Not yet filled.

#### claude-acp

- Name: Claude Agent
- Pinned: `@agentclientprotocol/claude-agent-acp` 0.93.0
- Run as: `npx -y @agentclientprotocol/claude-agent-acp@0.93.0`
- Source: <https://github.com/agentclientprotocol/claude-agent-acp>

Not yet filled.

#### cline

- Name: Cline
- Pinned: `cline` 3.0.73
- Run as: `npx -y cline@3.0.73 --acp`
- Source: <https://github.com/cline/cline>

Not yet filled.

#### codebuddy-code

- Name: Codebuddy Code
- Pinned: `@tencent-ai/codebuddy-code` 2.168.2
- Run as: `npx -y @tencent-ai/codebuddy-code@2.168.2 --acp`
- Source: <https://www.codebuddy.cn/cli/>

Not yet filled.

#### codex-acp

- Name: Codex
- Pinned: `@agentclientprotocol/codex-acp` 2.2.2
- Run as: `npx -y @agentclientprotocol/codex-acp@2.2.2`
- Source: <https://github.com/agentclientprotocol/codex-acp>

Not yet filled.

#### deepagents

- Name: DeepAgents
- Pinned: `deepagents-acp` 0.1.7
- Run as: `npx -y deepagents-acp@0.1.7`
- Source: <https://github.com/langchain-ai/deepagentsjs>

Not yet filled.

#### dimcode

- Name: DimCode
- Pinned: `dimcode` 0.5.19
- Run as: `npx -y dimcode@0.5.19 acp`
- Source: <https://dimcode.dev/docs/acp.html>

Not yet filled.

#### dirac

- Name: Dirac
- Pinned: `dirac-cli` 0.5.21
- Run as: `npx -y dirac-cli@0.5.21 --acp`
- Source: <https://github.com/dirac-run/dirac>

Not yet filled.

#### factory-droid

- Name: Factory Droid
- Pinned: `droid` 0.244.0
- Run as: `npx -y droid@0.244.0 exec --output-format acp-daemon`
- Source: <https://factory.ai/product/cli>

Not yet filled.

#### fast-agent

- Name: fast-agent
- Pinned: `fast-agent-acp` 0.10.1
- Run as: `uvx fast-agent-acp@0.10.1 -x`
- Source: <https://github.com/evalstate/fast-agent>

Not yet filled.

#### gemini

- Name: Gemini CLI
- Pinned: `@google/gemini-cli` 0.64.0
- Run as: `npx -y @google/gemini-cli@0.64.0 --acp`
- Source: <https://github.com/google-gemini/gemini-cli>

Not yet filled.

#### github-copilot-cli

- Name: Copilot
- Pinned: `@github/copilot` 1.0.98
- Run as: `npx -y @github/copilot@1.0.98 --acp`
- Source: <https://github.com/github/copilot-cli>

Not yet filled.

#### glm-acp-agent

- Name: GLM Agent
- Pinned: `glm-acp-agent` 1.15.0
- Run as: `npx -y glm-acp-agent@1.15.0`
- Source: <https://github.com/stefandevo/glm-acp-agent>

Not yet filled.

#### grok-build

- Name: Grok Build
- Pinned: `@xai-official/grok` 1.0.63
- Run as: `npx -y @xai-official/grok@1.0.63 agent stdio`
- Source: <https://x.ai/cli>

Not yet filled.

#### kilo

- Name: Kilo
- Pinned: `@kilocode/cli` 7.8.12
- Run as: `npx -y @kilocode/cli@7.8.12 acp`
- Source: <https://github.com/Kilo-Org/kilocode>

Not yet filled.

#### minimax-code

- Name: MiniMax Code
- Pinned: `@minimax-ai/code` 0.2.7
- Run as: `npx -y @minimax-ai/code@0.2.7 acp`
- Source: <https://agent.minimax.io>

Not yet filled.

#### minion-code

- Name: Minion Code
- Pinned: `minion-code` 0.1.44
- Run as: `uvx minion-code@0.1.44 acp`
- Source: <https://github.com/femto/minion-code>

Not yet filled.

#### nova

- Name: Nova
- Pinned: `@compass-ai/nova` 1.1.55
- Run as: `npx -y @compass-ai/nova@1.1.55 acp`
- Source: <https://github.com/Compass-Agentic-Platform/nova>

Not yet filled.

#### pi-acp

- Name: pi ACP
- Pinned: `pi-acp` 0.0.34
- Run as: `npx -y pi-acp@0.0.34`
- Source: <https://github.com/svkozak/pi-acp>

Not yet filled.

#### qoder

- Name: Qoder CLI
- Pinned: `@qoder-ai/qodercli` 0.2.14
- Run as: `npx -y @qoder-ai/qodercli@0.2.14 --acp`
- Source: <https://qoder.com>

Not yet filled.

#### qwen-code

- Name: Qwen Code
- Pinned: `@qwen-code/qwen-code` 0.25.2
- Run as: `npx -y @qwen-code/qwen-code@0.25.2 --acp --experimental-skills`
- Source: <https://github.com/QwenLM/qwen-code>

Not yet filled.

#### sigit

- Name: siGit Code
- Pinned: `@smbcloud/sigit` 1.7.0
- Run as: `npx -y @smbcloud/sigit@1.7.0`
- Source: <https://github.com/getsigit/sigit>

Not yet filled.

### Own CLIs (`src/clis.ts`)

#### cursor

- Name: Cursor
- Run as: `agent acp`, from PATH
- Install: <https://cursor.com/docs/cli/installation>

Not yet filled.

#### devin

- Name: Devin
- Run as: `devin acp`, from PATH
- Install: <https://docs.devin.ai/cli>

Not yet filled.

#### fx

- Name: fx
- Run as: `fx acp`, from PATH
- Install: <https://github.com/vercel-labs/fx>

Not yet filled.

#### goose

- Name: goose
- Run as: `goose acp`, from PATH
- Install: <https://goose-docs.ai/docs/getting-started/installation>

Not yet filled.

#### junie

- Name: Junie
- Run as: `junie --acp true`, from PATH
- Install: <https://junie.jetbrains.com/docs/junie-cli.html>

Not yet filled.

#### kimi

- Name: Kimi Code
- Run as: `kimi acp`, from PATH
- Install: <https://www.kimi.com/code/docs/en/kimi-code-cli/guides/getting-started.html>

Not yet filled.

#### kiro

- Name: Kiro
- Run as: `kiro-cli acp`, from PATH
- Install: <https://kiro.dev/docs/getting-started/installation/>

Not yet filled.

#### openclaw

- Name: OpenClaw
- Run as: `openclaw acp`, from PATH
- Install: <https://docs.openclaw.ai/install>

Not yet filled.

#### opencode

- Name: OpenCode
- Run as: `opencode acp`, from PATH
- Install: <https://opencode.ai/docs/>

Not yet filled.

#### poolside

- Name: Poolside
- Run as: `pool acp`, from PATH
- Install: <https://github.com/poolsideai/pool>

Not yet filled.

#### zeroclaw

- Name: ZeroClaw
- Run as: `zeroclaw acp`, from PATH
- Install: <https://github.com/zeroclaw-labs/zeroclaw>

Not yet filled.

## 4. What this changes on the board

Not yet filled: the open tasks and questions this closes or changes, and the
new tasks it suggests, as a list for the owner. Nothing is filed or decided
here.

## Sources

Not yet filled.
