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
| agoragentic-acp | echoes the client's, 1 c [ag1] | none, own JSON-RPC c [ag2] | `initialize` only c [ag3] |
| auggie |  |  |  |
| autohand |  |  |  |
| bob | ? [bo1] | ? [bo2] | v1 + private `_bob/*` n [bo3] |
| claude-acp |  |  |  |
| cline | 1, whatever is asked c [ci1] | SDK 0.16.1 c [ci2] | v1 + `set_model` c [ci3] |
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
| cursor | 1 c (bundle) | SDK 0.14.1 c (bundle) [cu1] | v1 + unstable c (bundle) [cu2] |
| devin | ? | ? (Rust, crate unknown) n [dv1] | v1, rest ? n [dv2] |
| fx |  |  |  |
| goose |  |  |  |
| junie | ? n [ju1] | ? (JVM app) n [ju2] | ◐ "ACP V1" · "ACP V2" n [ju3] |
| kimi | 1 c [km1] | SDK ^1.3.0 c [km2] | v1 + fork, set_model c [km3] |
| kiro | 1 n [kr1] | ? · V3 Node @kiro/agent n [kr2] | v1 · V3 adds list, fork n [kr3] |
| openclaw | 1 c [oc1] | SDK 1.5.0 c [oc2] | v1 + list, resume, close c [oc1] |
| opencode | 1 c [op1] | v1 SDK 0.21.0 · v2 SDK 1.6.0 c [op2] | v1 + unstable · v2 + more c [op3] |
| poolside | ? | ? | v1 + close, delete, message ids n [po1] |
| zeroclaw | 1, whatever is asked c [zc1] | none, own JSON-RPC c [zc2] | v1 + resume, close c [zc3] |

### Sessions (B3–B8)

| Agent | New | Load | Resume | List | Fork | Delete · close |
| --- | --- | --- | --- | --- | --- | --- |
| agoragentic-acp | ✗ Method not found c [ag4] | ✗ c | ✗ c | ✗ c | ✗ c | ✗ · ✗ c |
| auggie |  |  |  |  |  |  |
| autohand |  |  |  |  |  |  |
| bob | ✓ needs login n [bo4] | ✓ full replay n [bo5] | ✓ no replay n [bo5] | ✓ paged n [bo6] | ✗ c (bundle) [bo6] | ✓ · ✓ n, c (bundle) [bo6] |
| claude-acp |  |  |  |  |  |  |
| cline | ✓ needs a login c [ci4] | ✓ model back to default c [ci5] | ✗ c [ci6] | ✗ c [ci6] | ✗ c [ci6] | ✗ · ✗ c [ci6] |
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
| cursor | ✓ c (bundle) [cu3] | ✓ c (bundle) [cu4] | ✗ c (bundle) | ✓ unstable c (bundle) [cu5] | ✗ c (bundle) | ✗ · ✗ c (bundle) |
| devin | ✓ n [dv3] | ✓ n [dv4] | ? n [dv5] | ✓ n [dv6] | ? n [dv7] | ? · ? |
| fx |  |  |  |  |  |  |
| goose |  |  |  |  |  |  |
| junie | ✓ n [ju4] | ? n [ju5] | ? | ? | ? n [ju5] | ? · ? |
| kimi | ✓ c [km4] | ✓ c [km5] | ✓ c | ✓ c [km6] | ✓ unstable c [km7] | ✓ · ✓ c [km8] |
| kiro | ✓ n | ◐ n [kr4] | ✗ n [kr5] | ✗ · V3 ✓ n [kr5] | ✗ · V3 ✓ n [kr5] | ✗ · ✗ n [kr5] |
| openclaw | ✓ c [oc3] | ✓ c [oc4] | ◐ c [oc5] | ✓ Gateway keys c [oc6] | ✗ c | ✗ · ✓ c |
| opencode | ✓ c [op4] | ✓ with replay c [op4] | ✓ no replay c [op4] | ✓ 100 per page c [op4] | ✓ c [op4] | v1 ✗ · ✓; v2 ✓ · ✓ c [op4] |
| poolside | ✓ n [po2] | ✓ n [po2] | ? [po2] | ✓ n [po2] | ? [po2] | ✓ · ✓ n [po1] |
| zeroclaw | ✓ needs an agent alias c [zc4] | ✓ full replay c [zc5] | ✓ plan only c [zc5] | ✗ c | ✗ c | ✗ · ✓ c [zc5] |

### Modes, models and options (B9–B12)

| Agent | Modes | Models | Config options | Effort |
| --- | --- | --- | --- | --- |
| agoragentic-acp | ✗ c | ✗ c | ✗ c | ✗ c |
| auggie |  |  |  |  |
| autohand |  |  |  |  |
| bob | ✓ `set_mode` n, c (bundle) [bo7] | ✗ n [bo8] | ? [bo8] | ✗ c (bundle) [bo8] |
| claude-acp |  |  |  |  |
| cline | ✓ plan · act c [ci7] | ◐ `provider` select first c [ci8] | ✓ five, one boolean c [ci8] | ✗ `--thinking` flag only c [ci9] |
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
| cursor | agent · plan · ask c (bundle) [cu6] | ✓ c (bundle) [cu7] | mode · model c (bundle) [cu7] | ◐ opt-in `_meta` c (bundle) [cu7] |
| devin | ✓ six, shape ? n [dv8] | ✓ config option n [dv9] | model · effort · speed · dirs n [dv10] | ✓ option, category ? n [dv11] |
| fx |  |  |  |  |
| goose |  |  |  |  |
| junie | ◐ /plan, /goal as text n [ju6] | ✓ config option n [ju7] | ◐ model · brave_mode n [ju8] | ? n [ju9] |
| kimi | default · plan · auto · yolo c [km9] | ◐ option only c [km10] | model · thinking · mode c [km11] | ✓ `thinking` c [km11] |
| kiro | ✓ agent configs n [kr6] | ✓ · V3 option only n [kr7] | ? · V3 ✓ n [kr8] | flag only · V3 ◐ n [kr8] |
| openclaw | ◐ thought levels c [oc7] | ✗ `/model` only c [oc7] | 7, `thought_level` too c [oc8] | ✓ `thought_level` c [oc8] |
| opencode | ◐ option `mode` only c [op5] | ◐ option `model`; v1 + set_model c [op5] | ✓ model, effort, mode c [op5] | ✓ `thought_level` c [op5] |
| poolside | ◐ Build · Plan n [po3] | ◐ config option n [po3] | ✓ approval, mode, model, effort n [po3] | ◐ thought level n [po3] |
| zeroclaw | ✗ c [zc6] | ✗ fixed in its config c [zc6] | ✗ c [zc6] | ✗ c [zc6] |

### Prompt content (B13)

| Agent | Text | Image | Audio | Resource | Resource link |
| --- | --- | --- | --- | --- | --- |
| agoragentic-acp | ✗ no `session/prompt` c [ag4] | ✗ c | ✗ c | ✗ c | ✗ c |
| auggie |  |  |  |  |  |
| autohand |  |  |  |  |  |
| bob | ✓ n | ✓ n [bo9] | ? [bo9] | ✓ c (bundle) [bo9] | ? [bo9] |
| claude-acp |  |  |  |  |  |
| cline | ✓ c [ci10] | ✗ though advertised c [ci10] | ✗ c [ci10] | ✗ c [ci10] | ✗ c [ci10] |
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
| cursor | ✓ c (bundle) | ✓ c (bundle) | ✗ c (bundle) | ✓ inlined c (bundle) [cu8] | ✓ inlined c (bundle) [cu8] |
| devin | ✓ n | ? | ? | ? | ◐ inferred n [dv12] |
| fx |  |  |  |  |  |
| goose |  |  |  |  |  |
| junie | ✓ n [ju10] | ? | ? | ? | ? |
| kimi | ✓ c | ✓ c | ✗ c | ✓ text only c [km12] | ◐ as a path c [km12] |
| kiro | ✓ n | ✓ n [kr1] | ? | ? | ? |
| openclaw | ✓ c | ✓ c | ✗ c | ✓ as text c [oc9] | ◐ as text c [oc9] |
| opencode | ✓ c [op6] | ✓ c [op6] | ✗ c [op6] | ✓ c [op6] | ✓ `file://` c [op6] |
| poolside | ✓ n | ? [po4] | ? | ? | ? |
| zeroclaw | ✓ c [zc7] | ✗ c [zc7] | ✗ c [zc7] | ✓ inlined c [zc7] | ✗ dropped silently c [zc7] |

### Tool calls (B14)

| Agent | Kinds | `rawInput` | `rawOutput` | Content: text · diff · terminal | Locations | Status lifecycle |
| --- | --- | --- | --- | --- | --- | --- |
| agoragentic-acp | ✗ no updates sent c [ag5] | ✗ c | ✗ c | ✗ · ✗ · ✗ c | ✗ c | ✗ c |
| auggie |  |  |  |  |  |  |
| autohand |  |  |  |  |  |  |
| bob | ? [bo10] | ✓ c (bundle) [bo10] | ✓ `{result}` c (bundle) [bo10] | ◐ · ✓ · ✗ n, c (bundle) [bo10] | ◐ edits n [bo10] | ◐ can stick `pending` c (bundle) [bo11] |
| claude-acp |  |  |  |  |  |  |
| cline | all but `switch_mode` c [ci11] | ✓ c [ci11] | ✓ only at the end c [ci11] | ✗ · ✗ · ✗ c [ci11] | ✗ c [ci11] | `in_progress` only if asked c [ci12] |
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
| cursor | 9, `switch_mode` too c (bundle) [cu9] | ✓ trimmed c (bundle) [cu9] | ✓ per tool c (bundle) [cu9] | ◐ · ✓ · ✗ c (bundle) [cu9] | ✓ c (bundle) | pending → completed c (bundle) [cu10] |
| devin | ? | ? | ? | ? · ? · ◐ n [dv13] | ? | ◐ n [dv14] |
| fx |  |  |  |  |  |  |
| goose |  |  |  |  |  |  |
| junie | ? | ? | ? | ? · ? · ? | ? | ✓ pending first n [ju11] |
| kimi | 6, by tool name c [km13] | ✓ c | ✓ c | ✓ · ✓ · ◐ c [km14] | ✓ absolute c | full, `pending` lazy c [km13] |
| kiro | ? | ? n [kr9] | ? n [kr9] | ? · ? · ? | ? | ? · V3 failureReason n [kr9] |
| openclaw | 8, by tool name c [oc10] | ✓ c | ✓ c | ✓ · ? · ✗ c [oc10] | ✓ c | in_progress → end c [oc10] |
| opencode | execute, edit, read, search… c [op7] | ✓ c [op7] | ✓ `{metadata}` c [op7] | ✓ · ✓ · ✗ c [op7] | ✓ c [op7] | v1 live · v2 no live output c [op8] |
| poolside | ? | ? | ? | ? · ? · ? | ? | ? |
| zeroclaw | execute edit delete think other c [zc8] | ✓ c [zc8] | ✓ whole output, at end c [zc8] | ✓ · ✓ · ✗ c [zc8] | ✗ c [zc8] | pending → completed c [zc8] |

### Asking the person (B15–B17)

| Agent | Permission options | On cancel or timeout | Elicitation: form · URL | Plan |
| --- | --- | --- | --- | --- |
| agoragentic-acp | ✗ no requests sent c [ag5] | ✗ c | ✗ · ✗ c | ✗ c |
| auggie |  |  |  |  |
| autohand |  |  |  |  |
| bob | once · always · reject n [bo12] | cancelled c (bundle) [bo12] | ✓ · ? c (bundle) [bo13] | ✓ n [bo14] |
| claude-acp |  |  |  |  |
| cline | once · always · reject c [ci13] | reject · no timeout c [ci13] | ✗ · ✗ c [ci14] | ✗ c [ci15] |
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
| cursor | once · always · reject c (bundle) [cu11] | rejected; no timeout c (bundle) [cu11] | ✗ · ✗ c (bundle) [cu12] | ◐ CreatePlan only c (bundle) [cu13] |
| devin | once · session · 2 always n [dv15] | ? | ✓ · ? n [dv16] | ? |
| fx |  |  |  |  |
| goose |  |  |  |  |
| junie | once · always n [ju12] | ? | ◐ · ? n [ju13] | ? |
| kimi | once · always · reject c [km15] | cancelled; no timeout c [km15] | ✓ · ✗ c [km16] | ✓ todo list c [km17] |
| kiro | own _meta · V3 all four n [kr10] | ? n [kr10] | ? · ? n [kr11] | ? n [kr11] |
| openclaw | exec only: 3 kinds c [oc11] | deny c [oc11] | ✗ · ✗ c [oc12] | ✗ c |
| opencode | once · always · reject c [op9] | reject c [op9] | v1 ✗ · ✗; v2 ✓ · ✗ c [op10] | ✗ c [op11] |
| poolside | ◐ accept edits for session n [po5] | ? | ? · ? [po6] | ? [po7] |
| zeroclaw | once · always · reject + edit c [zc9] | deny · waits 1 h c [zc9] | ✓ · ✗ c [zc10] | ✓ whole list c [zc11] |

### The turn (B18–B21)

| Agent | Cancel stops | Steering | Subagents | Usage: meter · answer · cost |
| --- | --- | --- | --- | --- |
| agoragentic-acp | ✗ error line with no id c [ag6] | ✗ c | ✗ c | ✗ · ✗ · ✗ c |
| auggie |  |  |  |  |
| autohand |  |  |  |  |
| bob | ◐ turn, pending ask c (bundle) [bo12] | ✗ refused c (bundle) [bo15] | as one call c (bundle) [bo16] | ✗ · ✗ · ✗ c (bundle) [bo17] |
| claude-acp |  |  |  |  |
| cline | ◐ lost after a 2nd prompt c [ci16] | ✗ queued c [ci16] | flat in parent c [ci17] | ✗ · ✗ · ✗ c [ci18] |
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
| cursor | turn and subagents c (bundle) [cu14] | ✗; a prompt cancels c (bundle) [cu15] | draft shape c (bundle) [cu16] | ✗ · ✗ · ✗ c (bundle) |
| devin | ◐ parks subagents n [dv17] | ? (CLI steers) n [dv18] | fore- and background, shape ? n [dv19] | ? · ? · ? n [dv20] |
| fx |  |  |  |  |
| goose |  |  |  |  |
| junie | ? n [ju14] | ? (CLI steers) n [ju15] | ? (CLI has them) n [ju16] | ? · ◐ · ? n [ju17] |
| kimi | main turn only c [km18] | ✗; refused -32600 c [km19] | as one call c [km20] | ◐ · ✗ · ✗ c [km21] |
| kiro | ✓ turn n [kr12] | own _session/steer n [kr13] | own _session/spawn n [kr14] | ✗ · ✗ · ✗ n [kr15] |
| openclaw | prompt, approval, run c [oc13] | ✗; a prompt aborts c [oc13] | never reach ACP c [oc14] | ◐ · ✗ · ✗ c [oc15] |
| opencode | v1 all · v2 not children c [op12] | ✗ c [op13] | v1 as one call · v2 flat c [op14] | ✓ · ✓ · ✓ at turn end c [op15] |
| poolside | ? | ◐ own `poolside/session_steer` n [po8] | ◐ shape unknown n [po9] | ? · ? · ? [po10] |
| zeroclaw | ✓ + `turn-cancelled` row c [zc12] | ✗ `SESSION_BUSY` c [zc13] | as one call c [zc14] | ✗ · ✗ · ✗ c [zc15] |

### Commands, titles, login and calls back (B22–B26)

| Agent | Available commands | Session title | Login (`authenticate`) | Client `fs` · `terminal` | MCP: stdio · http · sse |
| --- | --- | --- | --- | --- | --- |
| agoragentic-acp | ✗ c [ag5] | ✗ c | ✗ malformed method c [ag7] | ✗ · ✗ c [ag5] | ✗ · ✗ · ✗ c |
| auggie |  |  |  |  |  |
| autohand |  |  |  |  |  |
| bob | ✓ c (bundle) [bo18] | ✓ after a turn n [bo19] | ◐ `sso`, browser n [bo20] | ? · ✗ n [bo21] | ✓ · ✓ · ✗ n [bo22] |
| claude-acp |  |  |  |  |  |
| cline | ✗ c [ci19] | ◐ `updatedAt`, no title c [ci20] | 3 agent-run OAuth c [ci21] | ✗ · ✗ c [ci22] | ✗ · ✗ · ✗ ignored c [ci23] |
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
| cursor | ✓ c (bundle) | ✓ c (bundle) | **needed** c (bundle) [cu17] | ✗ · ✗ c (bundle) | ✓ · ✓ · ✓ c (bundle) |
| devin | ✓ n [dv21] | ? n [dv22] | ✓ n [dv23] | ? · ? | ✓ · ✓ · ✓ n [dv24] |
| fx |  |  |  |  |  |
| goose |  |  |  |  |  |
| junie | ✓ n [ju18] | ? n [ju19] | ? n [ju20] | ◐ · ? n [ju21] | ? · ? · ? n [ju22] |
| kimi | ✓ c [km22] | ✓ c | **needed** c [km23] | ✓ · ✓ if declared c [km24] | ✓ · ✓ · ✓ c |
| kiro | ✗ own · V3 ✓ n [kr16] | ✗ · V3 ◐ n [kr17] | CLI login · V3 optional n [kr18] | ? · ? (V3 terminal ✓) n [kr19] | ? · ? · ? n [kr20] |
| openclaw | ✓ Gateway commands c [oc16] | ✓ c [oc17] | not needed c [oc18] | ✗ · ✗ c | ✗ · ✗ · ✗ refused c [oc3] |
| opencode | ✓ c [op16] | v1 ✗ · v2 ◐ `_meta` only c [op17] | `opencode-login`, no-op c [op18] | v1 ◐ · ✗; v2 ✗ · ✗ c [op19] | v1 ✓ · ✓ · ✓; v2 ✓ · ✓ · ✗ c [op20] |
| poolside | ✓ n [po11] | ? [po12] | outside ACP n [po13] | ? · ? | ? · ? · ? [po14] |
| zeroclaw | ✗ c | ✗ c | ✗ own config c [zc16] | ✗ · ✗ c [zc17] | ✗ · ✗ · ✗ c [zc18] |

### Capabilities (B1–B2)

| Agent | Agent capabilities advertised | Client capabilities read |
| --- | --- | --- |
| agoragentic-acp | `loadSession: false` only c [ag8] | none c [ag9] |
| auggie |  |  |
| autohand |  |  |
| bob | ◐ `bob/extensions` n, c (bundle) [bo23] | elicitation only c (bundle) [bo24] |
| claude-acp |  |  |
| cline | load, image c [ci1] | none c [ci1] |
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
| cursor | load, list, image c (bundle) [cu18] | `subagents`, `_meta` c (bundle) [cu18] |
| devin | ? n [dv25] | elicitation, rest ? n [dv26] |
| fx |  |  |
| goose |  |  |
| junie | ? | fs, form n [ju23] |
| kimi | load, all session caps c [km25] | fs, terminal, form c [km25] |
| kiro | loadSession, image n [kr1] | ? · V3 terminal, _meta.kiro n [kr19] |
| openclaw | load, list, resume, close c [oc1] | none c [oc1] |
| opencode | load, image, http, list… c [op21] | v1 terminal-auth · v2 + form c [op22] |
| poolside | ? [po8] | ? |
| zeroclaw | load, resume, close, context c [zc19] | `elicitation` only c [zc10] |

### Custom extensions (C)

One entry per extension: what it gives, what a client has to do to get it,
and what it costs. The cell names the extensions; the agent's part has the
rest.

| Agent | Extensions | Opt-in needed | chord uses |
| --- | --- | --- | --- |
| agoragentic-acp | MCP `tools/*` and 3 more c [ag10] | MCP calls on the ACP pipe | none |
| auggie |  |  |  |
| autohand |  |  |  |
| bob | `bob/extensions`, `_bob/task/*`, `bob/mode` | `_meta`, flag, form | none |
| claude-acp |  |  |  |
| cline | `--thinking`, `provider` +2 c [ci24] | flag; config options | `provider`, read as the model |
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
| cursor | `cursor/*` methods, picker `_meta` | answer methods, `_meta` | none |
| devin | tool _meta, timestamps n [dv27] | ? | none |
| fx |  |  |  |
| goose |  |  |  |
| junie | brave_mode, late chunks n [ju24] | config option | none |
| kimi | `session/set_model`, `terminal-auth` | none | none |
| kiro | _kiro.dev/* · V3 _kiro/* n [kr21] | none · V3 flag, capability | none |
| openclaw | routing `_meta`, lineage `_meta` | `_meta`, flags | none |
| opencode | child updates, retry, terminal-auth | capability, `_meta` | none |
| poolside | session_steer, Auto mode, hooks | capability, config option | none |
| zeroclaw | `reject_with_edit` and 5 more c [zc20] | a non-standard kind; `agentAlias` | none |

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

`agoragentic-mcp` 1.3.0, the registry pin, read from the npm package (MIT,
one plain JavaScript file, no limits on reading). Paths are relative to the
package root. At the pin it is not an ACP agent: `--acp` gives an ACP-shaped
`initialize` answer and then only MCP's `tools/list` and `tools/call`, so
every per-session cell is `✗` because the session never opens, not because
it was not looked at. The npm latest, 1.3.6 (2026-07-23), was read too, as
an esbuild bundle (`dist/mcp-server.cjs`): it adds `session/new`,
`session/prompt` and `session/cancel`, but answers every prompt with one
canned refusal ("a tool bridge, not a code-editing chat agent") and reads
the prompt from `params.content` rather than ACP's `params.prompt`
(`dist/mcp-server.cjs:37811-37817`, `:37869-37907`). The cells are 1.3.0's.

**Footnotes.**

- **ag1.** `mcp-server.js:688`: `protocolVersion: params?.protocolVersion ||
  1`. It echoes what the client asks; chord asks 1 and gets 1.
- **ag2.** `readline` on stdin and one JSON line per answer on stdout
  (`mcp-server.js:664-683`). The only dependency is
  `@modelcontextprotocol/sdk`, unused in ACP mode.
- **ag3.** The method switch (`mcp-server.js:724-758`) knows `initialize`,
  `initialized`, `tools/list`, `tools/call` and `shutdown`; anything else is
  `-32601 Method not found`.
- **ag4.** `session/new` and `session/prompt` fall to that `-32601` branch.
- **ag5.** `send` (`mcp-server.js:674`) is called only from `sendResult`
  and `sendError` (`:677-683`): no `session/update` and no request to the
  client (`session/request_permission`, `elicitation/create`, `fs/*`,
  `terminal/*`).
- **ag6.** `session/cancel` is a notification; the default branch
  (`mcp-server.js:756-757`) still writes an error, with no `id`.
- **ag7.** With `AGORAGENTIC_API_KEY` set, `authMethods: []`; without it,
  one `{type: "terminal", description}` entry with no `id` or `name`, not a
  valid v1 method (`mcp-server.js:698-706`). No `authenticate`.
- **ag8.** `{loadSession: false, promptCapabilities: {image: false, audio:
  false}}` verbatim (`mcp-server.js:689-692`); no `sessionCapabilities`,
  `mcpCapabilities` or `_meta`.
- **ag9.** `handleInitialize` (`mcp-server.js:686-708`) reads only
  `protocolVersion`.
- **ag10.** Four, each a bullet under Custom below.

**Custom.**

- MCP `tools/list` and `tools/call` on the ACP connection
  (`mcp-server.js:731-748`): the marketplace's tools, called by the client
  rather than a model. A client must speak MCP on the ACP pipe, which no ACP
  client does. `agoragentic_invoke` spends USDC from the account behind the
  key, with no permission step (`:108`); a payment demand comes back as
  error `-32042` (`:760-762`).
- `initialized` and `shutdown` (`mcp-server.js:728-730`, `:750-753`):
  MCP-style lifecycle methods; nothing for an ACP client.
- `agentInfo.version` is `"2.0.0"` and the stderr banner says "ACP Agent
  v2.0" while the package is 1.3.0 (`mcp-server.js:693-697`, `:771`).
- A `postinstall` banner (`scripts/postinstall.js`) goes to npm's output,
  not to the agent's stdout.

**In chord.** `initialize` succeeds: chord does not read `authMethods`, so
the malformed entry passes. `session/new` then gets `Method not found:
session/new`, which chord shows as the start failure, and the agent is
stopped. The person reads a JSON-RPC method name with no hint that this is
an MCP tool server. A prompt typed afterwards sits in the box with no word
(CHD-55). `chord agents` lists it like any agent. At 1.3.6 the start
would succeed instead, and every prompt would get the same canned refusal
and `end_turn`, so the person would see a session that refuses everything.
chord uses nothing of it;
the same package without `--acp` could be added as an MCP server for
another agent, which is the person's choice.

**Sources.**

- `agoragentic-mcp` 1.3.0 and 1.3.6 on npm,
  <https://www.npmjs.com/package/agoragentic-mcp>.
- Repository <https://github.com/rhein1/agoragentic-integrations>.
- CHD-432's notes in
  [`design/registry-2026-10-17.md`](design/registry-2026-10-17.md) (ag1).

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

`@ibm/bob` 2.0.8, the registry pin (release date 2026-10-14), read from its
npm package. The package ships `ACP.md`, `README.md`, a single bundle
`dist/bob.js` and the licence under `dist/ibm-licence/`. That licence is the
IBM International License Agreement for Non-Warranted Programs (ILAN), which
forbids "reverse assembling, reverse compiling, translating, or reverse
engineering the Program" (`dist/ibm-licence/license.txt:61`), and the
question whether its bundle may be read is with the owner. For this part the
bundle was not read: cells marked `n` come from IBM's own `ACP.md` and
`README.md`. CHD-432 did read `dist/bob.js`
([`design/registry-2026-10-17.md`](design/registry-2026-10-17.md), its bob
notes at lines 696-747), so every cell resting on what it took from the
bundle is marked `c (bundle)`, and so should its bob rows in that study's
section 2 tables be read. A cell that would need the bundle again says `?`.

**Footnotes.**

- **bo1.** Not documented, and CHD-432 recorded none. chord's request of
  version 1 is answered, as far as CHD-432's reading shows, but nothing
  states the number.
- **bo2.** The bundled notices list no ACP library
  (`dist/ibm-licence/notices.txt:45-66`, `:250-275`), and they say they are
  not complete (`:15-16`). Unknown.
- **bo3.** `ACP.md:60-62` (list, delete, resume, load), `:91` (`set_mode`),
  `:72` (no `set_model`), `:93-129` (`_bob/task/*`). No fork.
- **bo4.** `ACP.md:25`: the first `session/new` fails `auth_required`
  without a login or key. `ACP.md:44`, `:49`: without form support and before
  `--accept-license`, or in a folder marked untrusted, it is refused.
- **bo5.** `ACP.md:62`: resume "without replaying already-visible messages";
  load replays history, tool calls, diffs and the last plan.
- **bo6.** `ACP.md:60`: list, page through and delete sessions "from the
  shared Bob store", so a delete reaches bob's own UI too. Close and no fork
  are CHD-432's (registry-2026-10-17.md:181, :703-705).
- **bo7.** `ACP.md:77-91`: `session/set_mode`, default from
  `session.defaultMode`. `current_mode_update` is CHD-432's (:714).
- **bo8.** `ACP.md:72`: "Model selection (`session/set_model`) is not
  supported". No effort per CHD-432 (:84). Config options are documented
  nowhere and CHD-432 recorded none.
- **bo9.** `ACP.md:65`: pasted images go to the model. Embedded context per
  CHD-432 (:181). Audio and `resource_link` were not established.
- **bo10.** CHD-432 (:710-711, :740-742): `pending` with rawInput, then
  `in_progress`, then `rawOutput {result}`; command output as text chunks that
  replace each other. `ACP.md:63`: edits stream as diffs with locations.
  `ACP.md:73`: no client terminals. The `kind` values are recorded nowhere.
- **bo11.** CHD-432 (:742): a cancelled permission leaves its call `pending`
  for good; otherwise `completed` or `failed`.
- **bo12.** `ACP.md:53-56`: Allow once and Reject, plus Always allow when the
  command or tool is eligible for a task-scoped approval. The option kinds,
  and a cancel answering a pending ask `cancelled`, are CHD-432's (:712-713).
  Timeouts and what a cancel does to running tools were not established.
- **bo13.** CHD-432 (:114, :713-714): questions as a form with
  `properties.answer` and an optional `properties.other`. URL mode not read.
- **bo14.** `ACP.md:64`: the todo list streams as ACP plan updates.
- **bo15.** CHD-432 (:744-746): a concurrent `session/prompt` is refused
  ("already running"); no steering.
- **bo16.** CHD-432 (:84, :743): subtask events are dropped, so a subagent is
  its parent's tool call. `ACP.md:36`: `--disable-subagents`.
- **bo17.** CHD-432 (:84, :707): no usage or cost at all.
- **bo18.** CHD-432 (:723). The command list was not read.
- **bo19.** `ACP.md:61`: title and last-activity updates after successful
  turns; that they are `session_info_update` is CHD-432's (:150, :747).
- **bo20.** `ACP.md:24-26`, `README.md:30-38`: SSO in a browser, or
  `BOB_API_KEY`. The method id `sso` is CHD-432's (:705). Other methods and
  their `type`s were not established.
- **bo21.** `ACP.md:73`: "ACP client terminals are not used". Whether bob
  calls `fs/*` was not established.
- **bo22.** `ACP.md:66`: stdio and Streamable HTTP; `:71`: "Legacy
  two-endpoint HTTP+SSE MCP servers supplied by an ACP client are rejected".
  Whether that fails `session/new` or drops one server is not stated.
- **bo23.** `ACP.md:95` quotes `_meta["bob/extensions"] = {version: 1}`.
  `loadSession`, list, delete, resume, close, embedded context, image and
  MCP http are CHD-432's (:703-705), not quoted verbatim.
- **bo24.** CHD-432 (:706): it reads only `clientCapabilities.elicitation`,
  which decides how the licence is asked (`ACP.md:43-44`).

**Custom.**

- **`_bob/task/export` and `_bob/task/import`** under
  `_meta["bob/extensions"]` (`ACP.md:93-129`): move a stored task between
  machines or clients. A client sends the private requests, then loads or
  resumes a returned id. Child tasks, workspace files and credentials do not
  travel; importing twice makes two copies.
- **`_meta["bob/mode"]` on `session/new`** (`ACP.md:75-91`): start in a given
  mode. An unknown id is -32602 and no session is made.
- **The licence form** (`ACP.md:43-44`): a client declaring forms is asked to
  accept IBM's licence on the first prompt, inside the turn. A client without
  forms needs `--accept-license`, which accepts it on the person's behalf.
- **Launch flags** (`ACP.md:30-37`): `--trust` saves every opened folder as
  trusted, for bob's own UI too; `--auto-approve` approves what bob's safety
  rules allow; `--disable-mcp` and `--disable-subagents`; `--log-level`.

**In chord.**

- chord never calls `authenticate`, and the registry passes no key, so
  without an SSO login from a terminal `session/new` fails and chord shows a
  bare start failure.
- chord passes only `acp`: no `--trust`, so a folder marked untrusted is
  refused. The licence form goes through chord's form path; `-p` declines it,
  and bob asks again on every run.
- chord resumes when it has its own record, else loads; both fit. It never
  calls `session/list`, fork, delete or close, and sends no `bob/mode`.
- chord's own http MCP server reaches bob. A person's sse server goes out
  unfiltered, and bob rejects it.
- Titles are dropped. A running command shows only its latest chunk; a call
  whose permission was cancelled stays `pending`; a subagent is one tool call;
  there is no usage, so no meter and no estimate. A mid-turn prompt is queued,
  which fits bob's refusal of a concurrent one.

**Sources.**

- `@ibm/bob` 2.0.8 on npm: `ACP.md`, `README.md`,
  `dist/ibm-licence/license.txt` and `notices.txt`.
- CHD-432, `docs/design/registry-2026-10-17.md`, bob 2.0.8.

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

Cline 3.0.73, the registry pin, read at tag `cli-v3.0.73` (c718573) of
<https://github.com/cline/cline> (Apache-2.0, no limits on reading). Paths
are relative to the repository root; `acp/` stands for `apps/cli/src/acp/`,
and the runtime behind it is `sdk/packages/core/` (`@cline/core` 0.0.95).
The image cell corrects CHD-432's: cline advertises images but drops them.

**Footnotes.**

- **ci1.** `acp/acpAgent.ts:130-152`: `initialize(_params)` never reads the
  request and answers `PROTOCOL_VERSION`, `loadSession: true`,
  `promptCapabilities {image: true, audio: false, embeddedContext: false}`,
  no `sessionCapabilities` or `mcpCapabilities`.
- **ci2.** `apps/cli/package.json:71`, `bun.lock:859`; transport
  `acp/index.ts:12-31`.
- **ci3.** `unstable_setSessionModel` at `acp/acpAgent.ts:438`; no
  `extMethod`, `extNotification` or `_meta` in `acp/`.
- **ci4.** `session/new` and `session/load` throw `auth_required` without
  `CLINE_API_KEY` or a stored login (`acp/acpAgent.ts:154-168`, `:639-650`).
- **ci5.** `session/load` replays the stored conversation
  (`acp/acpAgent.ts:249-326`); provider and model come back as defaults
  (`:262-286`).
- **ci6.** The agent's methods (`acp/acpAgent.ts:130-594`) have no resume,
  list, fork, close or delete.
- **ci7.** `plan` and `act` as `modes` and as a `mode` option, with
  `current_mode_update` (`acp/acpAgent.ts:170-184`, `:421-436`).
- **ci8.** The options are `provider` (select, category `model`, first),
  `model` (select, category `model`), `mode`, auto-approve (`boolean`) and
  organization (category `account`, Cline accounts only)
  (`acp/acpAgent.ts:865-941`, `acp/auto-approve.ts:9`,
  `acp/organizations.ts:92-97`). `models` is in the answer too.
  `config_option_update` follows each set (`acp/acpAgent.ts:572`).
- **ci9.** `--thinking <none|low|medium|high|xhigh>`
  (`apps/cli/src/commands/program.ts:40-41`, `apps/cli/src/main.ts:804-815`);
  the registry passes only `--acp`.
- **ci10.** `extractTextFromContentBlocks` keeps text only
  (`acp/acpAgent.ts:943-948`); a prompt with no text answers `end_turn` at
  once (`:333-336`).
- **ci11.** Kinds in `acp/tool-utils.ts:4-25`. `tool_call` with `rawInput`
  (`acp/session-updates.ts:66-80`); the end carries `rawOutput` only
  (`:137-147`). No `content` or `locations` is ever set.
- **ci12.** `pending`, then `in_progress` only after the person approves
  (`acp/permissions.ts:105-130`), then `completed` or `failed`.
- **ci13.** `acp/permissions.ts:15-31`; `allow_always` acts as once,
  `cancelled` and a failed request reject (`:57-90`, `:114-118`). No timeout.
- **ci14.** Core's `ask_question` tool needs an executor the ACP layer never
  passes (`sdk/packages/core/src/extensions/tools/definitions.ts:970-972`).
- **ci15.** No `plan` update (`acp/session-updates.ts:26-152`).
- **ci16.** A second `session/prompt` is queued and answered `end_turn` at
  once, then runs with no prompt open; it also clears the abort controller,
  so a later cancel stops nothing (`acp/acpAgent.ts:339-402`,
  `sdk/packages/core/src/runtime/host/local-runtime-host.ts:1142-1190`).
- **ci17.** `spawn_agent` is a `think` call; the child's events land in the
  parent session unmarked
  (`sdk/packages/core/src/runtime/host/local/spawn-tool.ts:50`).
- **ci18.** Usage events are dropped (`acp/session-updates.ts:36-39`); the
  answer is `{stopReason}` only (`acp/acpAgent.ts:402`).
- **ci19.** No `available_commands_update` in `apps/cli/src/`.
- **ci20.** `session_info_update` after every turn with `updatedAt` only
  (`acp/acpAgent.ts:387-389`).
- **ci21.** `cline`, `cline-pass`, `openai-codex` (`acp/auth.ts:12-16`);
  `authenticate` opens a browser from the agent process (`:32-106`).
- **ci22.** The only request to the client is `session/request_permission`
  (`acp/permissions.ts:115`).
- **ci23.** `mcpServers` is stored, never read (`acp/acpAgent.ts:81`,
  `:211`, `:276`); the CLI's own MCP settings file applies.
- **ci24.** Four, each a bullet under Custom below.

**Custom.**

- `--thinking <level>`: effort for every session of the process. A client
  adds the flag to the command; a change needs a restart.
- `provider` select with category `model`: switches between Cline,
  ClinePass, a ChatGPT subscription and others. A client must tell it from
  the model; two selects share the category.
- Auto-approve, a `boolean` option: skips every permission request. A
  client must draw a boolean option.
- Organization select, category `account`: personal or an organization for
  Cline billing.

**In chord.** `/model` lists providers: chord takes the first select of
category `model` and prefers it over the `models` field
(`src/session/models.ts:73-82`), so it shows and sets `provider`, and the
status line names the provider. The real `model` option is left out of
`/config`, which drops category `model` (`src/session/config.ts:28-40`,
`:60-62`). So the model cannot be chosen in chord. Pasted images vanish, and
an image-only prompt ends at once; @-mentions survive only as the path in
the text. Command output arrives only in `rawOutput`, which chord does not
draw. Without a login or `CLINE_API_KEY` the start fails with
`auth_required`, as chord never calls `authenticate`. chord's MCP server is
not offered, and `mcpServers` would be ignored. chord queues its own
mid-turn prompts, so the queued-prompt path is not reached. Ignored: the
auto-approve boolean and `session_info_update`.

**Sources.**

- Cline `cli-v3.0.73`, <https://github.com/cline/cline/tree/cli-v3.0.73>;
  `cline` 3.0.73 on npm.
- CHD-432's notes in
  [`design/registry-2026-10-17.md`](design/registry-2026-10-17.md)
  (ci1–ci7).

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

Read at 2026.10.16-e3cb207, the release `https://cursor.com/install` named on
2026-10-18 and the ACP Registry's pin, from the archive
`https://downloads.cursor.com/lab/2026.10.16-e3cb207/darwin/arm64/agent-cli-package.tar.gz`,
with 2026.08.11-e8db854 beside it for comparison. The CLI is a minified Node
webpack bundle; its ACP layer is the chunk `5300.index.js`, and the cites name
the webpack module inside it. It was read as plain text only, with grep and a
split at `;`: nothing beautified, renamed or decoded, no copy kept. Cursor's
Terms of Service §1.5(i) forbid any attempt to "reverse engineer,
disassemble, decompile, decode, or otherwise attempt to derive or gain access
to the source code" of the Service, and reading the shipped JS may fall under
it, as with qoder. Every cell here rests on the bundle and is marked
`c (bundle)`: the owner has to weigh whether these cells stay, and they are
kept for now. The registry's `cursor` is a proprietary binary archive; chord
takes only npx and uvx registry entries, so it starts the person's own
`agent`.

**Footnotes.**

- **cu1.** `@agentclientprotocol/sdk@0.14.1`, pre-1.0, from the pnpm store
  paths in the bundle.
- **cu2.** v1 plus `unstable_listSessions` and `unstable_setSessionModel`, the
  draft subagent shape (ACP PR #1992) on request, and `cursor/*` methods.
- **cu3.** `./src/acp/cursor-acp-agent.ts`: answers `modes`, `models` and
  `configOptions`; refuses with `authRequired` when not signed in (cu17).
- **cu4.** Replays chunks and tool calls, then past subagents
  (`./src/acp/subagent-history.ts`); one still running replays
  `disconnected`.
- **cu5.** The cwd filter must be absolute; a pagination `cursor` is refused
  with invalidParams.
- **cu6.** `mapAcpModeToCliMode` also takes `code`, `architect` and `chat`;
  each change sends `current_mode_update`. Also https://cursor.com/docs/cli/acp.
- **cu7.** Options `mode` and `model`; `unstable_setSessionModel` goes through
  `model`. Only with `clientCapabilities._meta.parameterizedModelPicker` does
  `buildModelParameterConfigOptions` add per-parameter options, among them
  `thought_level`; otherwise effort is baked into one long `model` list. No
  `config_option_update`.
- **cu8.** An embedded `resource` is inlined as text though `embeddedContext`
  is false. A `file:` link inside the project is read and inlined, cut at
  20 000 characters; any other link is named only.
- **cu9.** Kinds `execute`, `edit`, `delete`, `read`, `search`, `fetch`,
  `think`, `switch_mode`, `other` (`./src/acp/types.ts`). `rawOutput` per
  tool, shell `{exitCode, stdout, stderr}`. Content: a `diff` for edit and
  delete, text only for plan progress and `Watching:` calls, never `terminal`
  (`./src/acp/agent-session.ts`).
- **cu10.** `sendToolCall` sends `pending`, completion sends `completed`;
  nothing sends `failed`, so a failed command is `completed` with a non-zero
  `exitCode`. Only plan and `Watching:` calls send `in_progress`.
- **cu11.** Asked for write, shell, delete, read, MCP and web. `cancelled` or a
  failed request is rejected. `requestPermission` in
  `./src/acp/session-resources.ts` returns `{approved: true}` unasked when the
  request has no `toolCallId`; which operations do that is unread.
- **cu12.** No `elicitation/create`; questions go through
  `cursor/ask_question` (`./src/acp/interaction-handlers/ask-question-handler.ts`).
- **cu13.** A `plan` only when the model calls CreatePlan in plan mode
  (`./src/acp/interaction-handlers/create-plan-handler.ts`); todos go only to
  `cursor/update_todos`.
- **cu14.** With `subagents` declared it aborts the turn's subagents, waits
  up to a timeout and marks the rest `disconnected`; watched shells keep
  running (`./src/acp/background-completion-drain.ts`).
- **cu15.** `handlePrompt` calls `pendingPromptCancel` first, so a second
  `session/prompt` cancels the running one. No `_session/steering`.
- **cu16.** With `subagents` declared, since v2026.09.15: `subagent_spawned`,
  the child on its own session id, then `subagent_state_update` (`completed`,
  `failed`, `cancelled`, `disconnected`); `capabilities: {}`, so no stop.
  Without it, one `Task: …` call and a `cursor/task` request.
- **cu17.** `run.ts`: new, load and list throw `authRequired` unless a stored
  login, `CURSOR_API_KEY` or a token exists; `authenticate` (`cursor_login`)
  opens a browser login.
- **cu18.** Advertises `loadSession`, MCP http and sse, image, and
  `sessionCapabilities` list (plus `subagents` when the client declares it).
  Reads `subagents`, `_meta.subagents`, `_meta.parameterizedModelPicker` and
  `clientInfo`, never `fs`, `terminal`, `elicitation` or `plan`.

**Custom.**

- `cursor/ask_question`: questions a client must answer. On -32601 each
  single-select one becomes a permission request with a "Skip"
  (`reject_once`) option; multi-select ones are dropped.
- `cursor/create_plan`: plan approval a client must answer. On -32601 the
  plan counts as accepted.
- `cursor/update_todos`, `cursor/task`, `cursor/generate_image`: sent as
  requests whose errors are only logged; unanswered, the todos are lost.
- `cursor/list_available_models`, client to agent: models with parameters.
- `_meta.parameterizedModelPicker`: efforts as `thought_level` options, for
  a private key.
- Background subagents and watched shells hold the prompt open.
- Login and payment failures come as agent text ending `end_turn`.

**In chord.** chord declares `subagents`, so the draft shape arrives and its
enricher maps all four end states; nobody has seen it live. Questions come as
permission boxes, and `-p` with `--dangerously-skip-permissions` answers one
with its first option. chord answers `cursor/create_plan` with
method-not-found, so a plan counts as approved without the person. Shell
output is only in `rawOutput`, which chord never draws; a running call stays a
grey `Waiting…` and a failed one reads `completed`. No usage, so no meter and
no estimate. The effort picker is empty. Without `agent login` or
`CURSOR_API_KEY` the start fails `authRequired`. chord's queue keeps a
mid-turn prompt from cancelling the turn. chord reopens with `session/load`,
never calls `session/list` and drops titles.

**Sources.**

- Cursor CLI 2026.10.16-e3cb207 and 2026.08.11-e8db854, release archives.
- https://cursor.com/docs/cli/acp, https://cursor.com/docs/cli/changelog.md
- https://cursor.com/terms-of-service, §1.5.

#### devin

- Name: Devin
- Run as: `devin acp`, from PATH
- Install: <https://docs.devin.ai/cli>

Devin CLI v3000.11.92 (14 October 2026), still the latest on 2026-10-18. No
source is readable: the CLI is a native Rust binary under Cognition's
proprietary terms, the npm package `devin` is a download shim, and
github.com/CognitionAI/devin-cli holds only a README and publish scripts. The
binary was neither downloaded nor read, so every cell rests on Devin's docs and
stable changelog (`n`) or is unknown. The ACP Registry lists `devin` at the
same version as a binary archive; chord takes npx and uvx entries only, so it
starts the person's own `devin acp`.

**Footnotes.**

- **dv1.** The docs never name the ACP library. The protocol version is not
  documented either.
- **dv2.** The changelog names `session/new`, `session/load`, `session/list`,
  `authenticate`, elicitation, config options and slash commands. Nothing says
  whether it uses unstable or later surfaces.
- **dv3.** Changelog: ACP sessions take MCP servers on new and load.
- **dv4.** Changelog: "Persistence and resume restore titles, modes, and usage
  totals". Load is named beside new.
- **dv5.** "Resume" in that line does not name `session/resume`.
- **dv6.** The v3000.11.92 changelog fixes a "`session/list` failed" error, so
  the agent answers it. chord never calls it.
- **dv7.** `/fork` is a CLI command; `session/fork` is not named.
- **dv8.** Permissions reference: Normal (Code), Accept Edits, Smart, Bypass,
  Plan and Ask; `/normal` is an alias of `/code` over ACP. Whether they come
  as ACP modes or a mode config option is not said.
- **dv9.** Changelog: Devin models are chosen "through session configuration
  controls"; `--model` and `DEVIN_MODEL` set the default. `session/set_model`
  is not named.
- **dv10.** Changelog: config options for model, thinking effort and speed,
  and a workspace-directories option with replacement semantics.
- **dv11.** Thinking effort is a config option; its category is not said, and
  chord shows effort only for category `thought_level`.
- **dv12.** Changelog: links are rendered as `file://` URIs, which implies
  `resource_link` is taken. Inferred.
- **dv13.** Changelog: streamed shell output stays visible after the command
  ends, with its exit code. Whether it travels as `terminal` content, a client
  terminal or `_meta` is not said.
- **dv14.** Changelog: late terminal flushes can no longer reopen completed
  command cards, so tool calls do reach a final status. The rest of the
  lifecycle is not documented.
- **dv15.** Permissions reference: allow once, for the session, always for the
  project, always in all projects, plus "Edit command", "Describe change to
  command" and "Yes, switch to bypass mode"; "ACP clients get the same
  affordances". The ACP `kind`s and ids are not documented.
- **dv16.** Changelog: `ask_user_question` goes over "standard ACP
  elicitation" to clients that advertise it; free-text "Other" answers are
  recognised. URL elicitation and the form schema are not documented.
- **dv17.** Changelog: an interrupt parks running subagents for the next
  message instead of killing them; "ACP revert can cancel an active turn".
- **dv18.** The v3000.11.92 changelog adds steering to the CLI. No
  `_session/steering` or other ACP method is documented.
- **dv19.** Subagents docs: foreground subagents ask, background ones deny any
  tool not already granted without asking. Their ACP shape is not documented.
- **dv20.** `/usage`, `/session-stats` and `/context` are slash commands, and
  usage totals are restored on resume. `usage_update` is not named.
- **dv21.** Commands reference: the full set with descriptions, argument hints
  and categories, among them `/login`, `/plan`, `/compact`, `/context`,
  `/loop`, `/btw`, `/workspace`, `/mcp`, `/help`, `/status` and `/bug`.
- **dv22.** Titles are persisted and restored; `session_info_update` is not
  named.
- **dv23.** Commands reference: `authenticate` is accepted at runtime, with
  browser and manual sign-in. Method ids are not documented. Credentials also
  come from `WINDSURF_API_KEY` or `devin auth login`. An older changelog entry
  (v2026.4.9-0) says ACP sessions need host-provided credentials, which the
  current reference contradicts.
- **dv24.** Changelog: stdio, http and sse MCP servers are taken on new and
  load.
- **dv25.** `agentCapabilities` are not documented; dv3, dv6 and dv24 imply
  load, list and http and sse MCP.
- **dv26.** Changelog: elicitation is gated on the client advertising it. An
  unnamed host capability lets the host own the workspace roots (hiding
  `/workspace` and `/add-dir`), and a host-managed login hides `/login`.
  `fs`, `terminal`, `plan` and `subagents` are not mentioned.
- **dv27.** Changelog: a tool-name key in tool call metadata, timestamps on
  streamed agent messages, typed error causes and a retryable error when the
  channel closes. None of the field names are documented.

**Custom.**

- **Tool-name metadata and message timestamps.** They give the inference
  tool's name and when a message was streamed. A client reads them if it knows
  the keys, which are not documented.
- **Workspace roots.** A config option and a host-owned mode let the client
  set the directories. The host signal is not named.
- **Launch flags.** `--model`, `--agent-type`, `--refusal-fallback`, `--cloud`
  (insiders; relays ACP to Devin's cloud) and `DEVIN_SESSIONS_DIR`. A client
  must add them to argv; chord passes none.
- **Off-spec.** Choosing "switch to bypass mode" on one permission also
  approves the session's other open requests that offered it.

**In chord.** chord starts `devin acp` from PATH and uses new, load and
resume where offered, config options for model and mode, form elicitation and
the agent's slash commands. Effort shows only if its option has category
`thought_level`. chord never calls `authenticate`; if a stored
`devin auth login` does not count for an ACP client, the start fails with the
agent's message. Several of devin's commands share names with chord's own
(`/mcp`, `/context`, `/help`, `/status`); which one a person reaches is not
checked. A prompt sent mid-turn is queued, since devin documents no
`_session/steering`. If shell output travels as `terminal` content, chord,
which declares no `terminal`, shows only its id. Under
`--dangerously-skip-permissions` chord picks the first `allow_once`; which of
devin's options that is depends on undocumented kinds. Titles and any `_meta`
are ignored.

**Sources.**

- Devin CLI docs, <https://docs.devin.ai/cli>: ACP pages for Zed, JetBrains
  and Xcode, commands and permissions references, subagents, and the stable
  changelog through v3000.11.92 (read 2026-10-18).
- npm `devin` 3000.11.92 and <https://github.com/CognitionAI/devin-cli>.
- ACP Registry entry `devin` 3000.11.92.

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

Junie CLI stable 26.10.12, build 3659.7 (16 October 2026); nightly is at
3844.1. Junie is a closed native app of about 175 MB per platform under the
JetBrains AI Service terms, and npm `@jetbrains/junie` is a download shim. The
binary was neither downloaded nor read. Every cell rests on Junie's docs,
release notes and GitHub issues (`n`), or on `hermes-plugin/`, an ACP client
for Junie that JetBrains publishes in github.com/JetBrains/junie (commit
`6aa4138`). That client shows what JetBrains expects Junie to send, not
Junie's code; it is cited as `hermes-plugin/junie_hermes/client.py`. The ACP
Registry lists `junie` 3659.7.0 as a binary archive with `--acp=true`; chord
starts the person's own `junie --acp true`, a form the docs also give.

**Footnotes.**

- **ju1.** Not documented. The JetBrains client sends the Python SDK's version
  1 and works (`client.py:923, 1314`).
- **ju2.** "Handshake (JVM cold start) can be slow" (`client.py:110-111`); the
  client allows 90 s. Issue #53's log names a `SessionConfigController`. The
  ACP library is not known.
- **ju3.** The slash-commands page speaks of "ACP V1" and "ACP V2" clients
  with different command sets and does not say what selects one. Whether they
  are protocol versions or Junie's own adapter generations is unknown.
- **ju4.** The `session/new` answer carries `configOptions` with a `model`
  select (`client.py:804-863, 927-928`).
- **ju5.** The TUI resumes (`--session-id`, `--resume`, `/history`) and
  branches (`/branch`). Nothing says whether load or fork exist over ACP.
- **ju6.** ACP V2: bare `/plan` selects Plan for the next prompt and
  `/plan <prompt>` submits at once; `/goal` works the same way. Whether these
  are reported as ACP modes is not said. The TUI cycles default, Plan and
  Debug.
- **ju7.** The client sets the model with `set_config_option` id `model`
  (`client.py:1636-1645`). Issue #53 (build 1755.37) shows `session/set_model`
  too, refusing `custom:` ids.
- **ju8.** The client sets `brave_mode` with a boolean value
  (`client.py:1650-1660`), so it is likely a boolean config option. A sandbox
  session option is documented.
- **ju9.** The CLI has `/effort`, `--effort` and per-session effort since
  3659.4. Effort over ACP is not documented.
- **ju10.** Text is all the JetBrains client sends.
- **ju11.** The client expects `pending`, then `in_progress`, then `completed`
  or `failed`, and lines of up to 50 MB (`client.py:117-120, 130-136,
  1588-1592`). Kinds, raw fields and content are not shown.
- **ju12.** With Brave mode off Junie calls `session/request_permission`
  offering `allow_once` and `allow_always`; the client prefers once
  (`client.py:381-397, 1094-1109`). Reject kinds and cancel or timeout
  behaviour are not shown.
- **ju13.** ACP V2 offers `/goal` "only to clients with form support", and
  Goal "requests setup before dispatch", so Junie sends forms. The schema and
  URL elicitation are unknown (CHD-392).
- **ju14.** "Turn completion and cancellation do not reset Plan" implies
  `session/cancel` is handled. What it stops is not said.
- **ju15.** Mid-run steering came to the CLI in 3579.5. No ACP method is
  named.
- **ju16.** The CLI runs subagents as subtasks and tells the person which
  started. Their ACP shape is unknown.
- **ju17.** The client "prefers Junie's own token counts
  (PromptResponse.usage)" and says "ACP historically reported no counts"
  (`client.py:1481-1500`), so newer builds likely send `usage`. No
  `usage_update` is mentioned. Cost shows only as `/stats` text.
- **ju18.** ACP V2 sends `available_commands_update` at session start and on
  change: `/plan`, `/skills`, `/commands`, `/review`, `/title`, `/compress`,
  `/goal`, `/stats`, `/logs`, `/sandbox on|off`, skills and custom commands.
- **ju19.** `/title` sets a title that persists across reloads; whether it is
  sent as `session_info_update` is unknown.
- **ju20.** Sign-in is a JetBrains account, `JUNIE_API_KEY`, `--auth` or BYOK
  keys. The client passes `--auth` and never calls `authenticate`
  (`client.py:223-233`). `authMethods` are not documented.
- **ju21.** The client declares `fs` read and write and no terminal, and
  serves Junie's file reads and writes (`client.py:182-187, 1111-1135`).
  Whether Junie writes on its own when `fs` is absent is not said.
- **ju22.** ACP V1's `/mcp` lists "session servers provided by the ACP client
  at session init". Transports are not documented.
- **ju23.** `fs` from ju21 and form elicitation from ju13.
- **ju24.** `brave_mode` from ju8. The client waits up to 20 s after the
  prompt's answer, because "the ACP completion response can precede a
  trailing agent_message_chunk" (`client.py:121-128, 1061-1070`), and drops
  updates for other sessions as stragglers (`client.py:1072-1077`).

**Custom.**

- **`brave_mode`.** Turns asking off or on for the session. A client sets a
  boolean config option. With it on, nothing asks.
- **Slash commands as the mode surface** (`/plan`, `/goal`, `/sandbox`). A
  client sends them as prompt text. It cannot read the resulting mode unless
  Junie reports one, which is unknown.
- **Launch flags.** `--auth`, `--model`, `--effort`, `--sandbox`,
  `--agent-mode`, `--system-prompt` (an ACP session prompt is appended to it)
  and `--skip-update-check`. chord passes none.
- **Late chunks.** Text after the prompt's answer is off-spec; a client that
  ends the turn on the answer may miss the end of the reply.

**In chord.** chord declares no `fs`, so if Junie relies on client writes they
fail with method-not-found; unknown. chord ends the turn on the prompt's
answer, so late chunks land after it; how they draw was not checked. `/config`
lists only select options (`src/session/config.ts`), so `brave_mode` does not
show. Plan and Goal reach Junie as command text; whether chord shows the mode
depends on Junie reporting it. chord never calls `authenticate`, so the person
signs in through `junie` or sets `JUNIE_API_KEY`; issue #23 saw an ACP launch
exit with no message. Goal's form goes to chord's form dialog. If Junie sends
`PromptResponse.usage` with no cost, chord estimates a cost from it. A
mid-turn prompt is queued.

**Sources.**

- Junie CLI docs, <https://junie.jetbrains.com/docs/junie-cli-acp.html>,
  `slash-commands.html` and `junie-cli-subagents.html` (read 2026-10-18).
- Release notes and `hermes-plugin/` in <https://github.com/JetBrains/junie>,
  through 3659.7; issues #23, #53 and #113.
- npm `@jetbrains/junie` 3110.7.0; ACP Registry entry `junie` 3659.7.0.

#### kimi

- Name: Kimi Code
- Run as: `kimi acp`, from PATH
- Install: <https://www.kimi.com/code/docs/en/kimi-code-cli/guides/getting-started.html>

Read at Kimi Code 2.2.0, `@moonshot-ai/kimi-code` on npm, published
2026-10-14, from https://github.com/MoonshotAI/kimi-code at its 2.2.0 commit
`472192c`; `packages/acp-server/` is unchanged at main `4a82a07`
(2026-10-18). MIT, plain TypeScript, no limits on reading. chord's `kimi`
(`src/clis.ts`) is this Kimi Code 2.x. The ACP Registry's `kimi` entry is a
different program: the archived Python Kimi CLI 1.52.0, a binary archive,
which chord does not take, since it takes only npx and uvx registry entries.
Both packages install a `kimi` binary, so whichever is first on PATH decides
what `chord kimi` starts. Kimi CLI 1.52.0 prints a deprecation line on stdout
and exits without answering `initialize`
(`src/kimi_cli/__main__.py:12-45` in the Python package). The cells are Kimi
Code 2.x. Paths below are under `packages/acp-server/src/` unless they name
another root.

**Footnotes.**

- **km1.** It answers the highest version it has at or below the client's;
  1 is the only one (`version.ts:18-50`). Its comments still name ACP 0.23.
- **km2.** `packages/acp-server/package.json:22`; the SDK's `agent()` builder
  (`server.ts:700-721`).
- **km3.** SDK-unstable `session/fork` (`server.ts:211-215`), and
  `session/set_model`, which SDK 1.x dropped, registered by hand
  (`server.ts:662-687`).
- **km4.** Reads `cwd`, `additionalDirectories` and `mcpServers`; answers
  `configOptions` and `modes` (`server.ts:242-253`). Needs sign-in (km23).
- **km5.** Replays the main agent's history before it answers
  (`server.ts:296-310`, `replay.ts`); replayed tool ids use a fresh turn
  counter, not the live ids.
- **km6.** Every session, filtered by `cwd` when given; the request's
  `cursor` is ignored (`server.ts:323-330, 736-763`).
- **km7.** Ignores `cwd`, `additionalDirectories` and `mcpServers`
  (`server.ts:266-294`).
- **km8.** Close cancels the turn, best effort; delete of an unknown id is
  `invalid_params` (`server.ts:340-377`).
- **km9.** As `modes` and as a `mode` config option; `set_mode` sends
  `current_mode_update` and `config_option_update` (`modes.ts:22-87`).
- **km10.** No `models` field in any answer; the model is the `model` config
  option. `session/set_model` is accepted too, and a `<id>,thinking` suffix
  turns thinking on (`config-options.ts:31-48`, `session.ts:1048-1064`).
- **km11.** `model`, `thinking` (category `thought_level`, only for a model
  that can think: `off` plus its efforts, or `off`/`on`) and `mode`; every
  change sends `config_option_update` (`config-options.ts:59-137`).
- **km12.** A text resource becomes `<resource uri>…</resource>`, blobs are
  dropped; a `file://` link becomes the bare path, with `:L1-L2` from a line
  fragment (`convert.ts:33-71, 229-272`).
- **km13.** Kinds `read`, `edit`, `execute`, `fetch`, `think`, `other` by a
  tool-name table; `FetchURL` is not in it and reads `other`. `pending` from
  the first argument delta, `in_progress` on each delta, then `completed` or
  `failed` (`events-map.ts:106-391`).
- **km14.** While a call streams and runs, its content is the raw argument
  JSON, replaced by the result text or a `diff`. `terminal` content only with
  a client terminal; without one, Bash output arrives in the final update.
- **km15.** `allow_once`, `allow_always` (for the session) and `reject_once`.
  Leaving plan mode asks one `allow_once` per plan option plus
  `plan_revise` and `plan_reject_and_exit`. A `cancelled` outcome is
  cancelled; an unknown id or an RPC error is rejected (`approval.ts:65-188`).
- **km16.** AskUserQuestion as a form when `elicitation.form` is declared:
  fields `q0…qN` titled by header, `oneOf` or `anyOf` choices, all required,
  no "Other"; decline, cancel or an empty accept is "dismissed"
  (`question.ts:96-196`). Without a form it asks the first question as a
  permission with `q0_skip` "Skip" (`interaction-bridge.ts:196-231`).
- **km17.** A `todo_list` becomes `plan`, every entry `medium`
  (`events-map.ts:393-445`); the plan-mode document goes only as text in the
  exit permission.
- **km18.** Cancels the main agent's turn (`session.ts:980-1010`); background
  tasks and subagents stop only through the model's own `TaskStop`.
- **km19.** A concurrent prompt is refused with -32600 "another turn is
  already in progress" (`session.ts:621-648`). A turn the engine started by
  itself is not seen by that check; a prompt then answers `end_turn` at once
  and runs later, unseen (`session.ts:666-673, 728-740`).
- **km20.** The `Agent` tool runs a child in the same engine session; its
  events are not forwarded, but its approvals and questions are, under a
  tool call id that matches no card (`interaction-bridge.ts:61-93`).
- **km21.** `usage_update {used, size}` after each turn, sent after the
  prompt has answered, skipped for a model not in its catalog; no cost, no
  `PromptResponse.usage` (`session.ts:907-944`).
- **km22.** `/compact`, `/status`, `/usage`, `/mcp`, `/tasks`, `/help` and
  skills, answered locally as agent text (`builtin-commands.ts:17-42`).
- **km23.** One terminal method, `login` (`--login`), plus a legacy
  `_meta['terminal-auth']`; `authenticate` only re-checks. new, load, resume
  and fork answer `auth_required` with no data unless a model key or an OAuth
  login exists (`auth-methods.ts:28-61`, `server.ts:379-401, 625-646`).
- **km24.** `fs/*` and `terminal/*` only when declared
  (`acp-fs/acpConnection.ts:144-163`,
  `acp-terminal/acpTerminalRunner.ts:57-70`); otherwise all runs locally.
- **km25.** `loadSession`, image and embedded context, `sessionCapabilities`
  list, resume, close, delete, fork and `additionalDirectories`, MCP http and
  sse, `auth.logout` (`server.ts:192-240`). Reads only `fs`, `terminal` and
  `elicitation.form` (`server.ts:193-196, 572`).

**Custom.**

- `session/set_model`: the same switch as the `model` config option, called
  by name; nothing gained.
- `_meta['terminal-auth']` on the auth method: a command a client runs in a
  terminal of its own to sign in.
- Local slash commands, sent as prompt text: status, usage, tasks and
  compaction as one agent message with no turn; they skip the busy check.
- Compaction notices arrive as agent text outside any turn, not as ACP
  compaction.
- Launch: `kimi acp --login [--region …]`, and `KIMI_CODE_HOME`.
- A failed turn with a non-auth error answers `end_turn` with no message
  (`events-map.ts:61-76`).

**In chord.** chord starts, reopens with `session/resume`, and takes models,
modes and efforts from the config options, `thinking` as the effort. Usage
fills the meter; with no cost from kimi, chord's own estimate is the cost.
Questions arrive through chord's form, as no canonical shape: no enricher
reads them, and with a header the question text is only in the form's
message. chord never calls `authenticate`, so without a Kimi login or a model
key the start fails with a bare "Authentication required". A Python `kimi`
on PATH fails the start with no reason, and chord cannot tell the two apart.
Approvals and questions from a background subagent with no turn running are
refused (CHD-158). A turn kimi starts by itself is invisible, and a prompt
sent then reads as an empty reply. Tool cards show argument JSON while a
call runs. kimi's `/help`, `/mcp` and `/status` are hidden behind chord's own.
chord queues mid-turn prompts, which avoids kimi's -32600. chord never calls
`session/list`, drops titles, and leaves fork, delete, close and logout
unused.

**Sources.**

- `@moonshot-ai/kimi-code` 2.2.0, https://github.com/MoonshotAI/kimi-code
  (472192c and main 4a82a07), its CHANGELOG and `git log` of
  `packages/acp-server`.
- Python `kimi-cli` 1.52.0, the final release of the archived Kimi CLI.
- https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-acp.
- The ACP Registry's `registry.json`, fetched 2026-10-18.

#### kiro

- Name: Kiro
- Run as: `kiro-cli acp`, from PATH
- Install: <https://kiro.dev/docs/getting-started/installation/>

Kiro CLI 2.31.1 (14 October 2026), the newest CLI entry in the Kiro changelog
on 2026-10-18; issue #11995 cites a 2.32.0 with no changelog entry yet. Kiro
CLI is closed source and not in the ACP Registry. No code was read: every cell
rests on Kiro's docs, changelog and GitHub issues in kirodotdev/Kiro (`n`),
some of which quote its bundle. `kiro-cli acp`, which chord runs, starts the
CLI v2 server. The V3 engine, a Node bundle `@kiro/agent` behind a Rust
relay, needs `--agent-engine=v3` today; changelog 2.30 says V3 becomes the
default with CLI 3.0 at the end of October 2026, and whether a bare
`kiro-cli acp` then switches is not stated. Both answer protocol version 1.
Cells give v2 first, then V3 where it differs.

**Footnotes.**

- **kr1.** The v2 docs' `initialize` example answers `protocolVersion: 1`
  with `{loadSession: true, promptCapabilities: {image: true}}`. The V3
  migration guide: "both negotiate version 1".
- **kr2.** Issue #11956 names the relay `kas_acp_relay.rs` in `kiro-cli-chat`;
  #11819 and #11995 cite `@kiro/agent/dist/server/acp-server.js`. The ACP
  library inside either is unknown.
- **kr3.** V3 migration guide §2–3: `initialize`, `authenticate`, new, list,
  load, fork, prompt, cancel, `set_mode` and `set_config_option`, with
  `additionalDirectories` on new and load.
- **kr4.** v2: `session/load` with an id from an ended process hangs with no
  answer (#6753, 1.28.1, open). V3 replays with `_meta.kiro.replay: true` and
  needs MCP servers sent again.
- **kr5.** Neither the v2 docs nor the V3 method list name resume, delete or
  close; V3 adds list and fork "from an earlier point".
- **kr6.** v2 modes are agent configs. V3 modes per #11995: default, plan,
  autonomous, spec and custom-agent modes.
- **kr7.** v2 takes `session/set_model`. "CLI V3 does not implement
  session/set_model"; the model is a config option.
- **kr8.** v2 sets effort only by the `--effort` launch flag. V3 (#11873):
  options `mode`, `model`, `memoryReflection`, `autopilot` and
  `contentCollection`; `effortLevel` (`thought_level`) appears only after the
  model leaves `auto`, with no `config_option_update`.
- **kr9.** Tool call details are not documented for v2. V3: failed updates
  can carry `_meta.kiro.failureReason` (`cancelled`, `denied`, `error`).
  rawInput and rawOutput are not documented for either.
- **kr10.** v2 asks with its own `_meta.trustOptions`; whether standard
  options come too is not said. V3 offers `accept`, `always-accept`, `reject`
  and `always-reject`, "Always allow" only when it can be saved (2.19). What a
  `cancelled` answer does is not documented.
- **kr11.** Neither doc has elicitation or plan updates. The TUI has question
  prompts (2.21.4) and a todo tool (2.27); their wire is unknown (CHD-392).
- **kr12.** v2 cancels the turn. V3 also: with a client terminal, a running
  command lives on to its 120 s timeout (#11819).
- **kr13.** `_session/steer`, kept under that name in V3 (migration guide §7).
  chord's `_session/steering` is a different method.
- **kr14.** v2: `_session/spawn`, `_session/terminate` and
  `_kiro.dev/subagent/list_update`. V3 has no roster; subagents are background
  prompts on child sessions. Neither sends `subagent_update`.
- **kr15.** #9992 (open): the only per-turn usage is `_kiro.dev/metadata`
  with `meteringUsage` in credits; no `PromptResponse.usage`. V3 adds
  `context_usage` and `turn_completion` info kinds.
- **kr16.** v2 sends commands as `_kiro.dev/commands/available`. V3 sends
  `available_commands_update`.
- **kr17.** v2 sends none. V3 uses `session_info_update` to carry
  `_meta.kiro.kind`; titles exist (#11343) but their wire is not said.
- **kr18.** Since 2.29 `kiro-cli acp` uses the CLI's own login by default. V3
  calls `authenticate` only "when advertised"; `--auth-method=client` moves the
  token to an agent-to-client `_kiro/auth/getAccessToken`.
- **kr19.** v2: not documented. V3 runs commands in a client terminal when
  `terminal` is declared (#11819) and reads
  `clientCapabilities._meta.kiro.openExternalUrl`.
- **kr20.** Transports are not documented. #11717 (open): global `mcp.json` is
  ignored in ACP mode.
- **kr21.** v2's `_kiro.dev/*` methods (commands, MCP state, compaction,
  metadata, agent and subagent events, settings) and `_session/*`; V3's
  `_kiro/*` methods advertised in `agentCapabilities._meta.kiro`.

**Custom.**

- **v2 `_kiro.dev/*`.** Commands, MCP state, compaction, credits and a
  subagent roster. A client needs a v2-specific adapter. V3 retires them.
- **V3 `_kiro/*`.** Context, compaction, rename, usage, MCP status and reset,
  hooks and workflows. A client calls only advertised methods; deployments may
  differ.
- **`_kiro/auth/getAccessToken`.** A client-owned login under
  `--auth-method=client`. Unanswered, 2.25.0 retried it forever (#11669).
- **`_kiro/openExternalUrl`.** MCP OAuth URLs, behind a client `_meta`
  capability.
- **`session_info_update` with `_meta.kiro.kind`.** Context meter, turn
  summaries and steering states. A client that ignores `_meta` sees empty info
  updates.
- **Permission `_meta.kiro.consent`.** Workspace-scoped "always" rules, sent
  back with an `allow_always` answer.
- **Off-spec.** V3 exits when one stdin message takes over 2 s (#11956);
  sessions in one process run one at a time (#11995).

**In chord.** chord gets the v2 server: text, images, tool calls,
`set_mode`, `set_model`, load and cancel. Every `_kiro.dev/*` notification is
dropped, so Kiro's commands never reach completion. Effort cannot be set,
since chord passes no flags. A mid-turn prompt is queued, since Kiro's
steering is `_session/steer`. No usage comes, so chord can only estimate cost
if Kiro's model ids have prices. A load of a session v2 lost hangs; whether
chord's reopen times out is unchecked. chord never calls `session/list`, so
V3's list would not be used either. Under V3, chord's config-option path would
carry model and effort, and a slow stdin write would read as the agent
exiting. chord's `allow_always` carries no consent `_meta`; what V3 saves then
is unknown.

**Sources.**

- Kiro docs: <https://kiro.dev/docs/cli/acp/>,
  <https://kiro.dev/docs/cli/v3/acp-migration>, <https://kiro.dev/docs/acp/>
  and <https://kiro.dev/docs/cli/v3/> (read 2026-10-18).
- Kiro changelog, CLI 2.17 to 2.31.1, <https://kiro.dev/changelog/>.
- Issues in <https://github.com/kirodotdev/Kiro>: #6050, #6753, #9992,
  #10597, #11343, #11669, #11717, #11819, #11873, #11956, #11995.

#### openclaw

- Name: OpenClaw
- Run as: `openclaw acp`, from PATH
- Install: <https://docs.openclaw.ai/install>

Read at OpenClaw 2026.10.4, npm `latest`, published 2026-10-15 and current on
2026-10-18, from https://github.com/openclaw/openclaw at tag `v2026.10.4`
(commit `383c124c`). The betas 2026.10.10-beta.1 and beta.2 were not read.
MIT, plain TypeScript, no limits on reading. `openclaw acp` is a bridge, not
an agent: it speaks ACP on stdio and forwards to an OpenClaw Gateway over
WebSocket, where the model, tools, workspace and approvals live, possibly on
another host (`src/acp/server.ts:147-190`). It waits for the Gateway's hello
before it answers, and exits when the Gateway cannot be reached
(`server.ts:247-258`). Not in the ACP Registry. Paths below are under
`src/acp/` unless they name another root.

**Footnotes.**

- **oc1.** `translator.ts:135-158`: `initialize(_params)` reads nothing from
  the client and answers `loadSession`, image and embedded context,
  `mcpCapabilities {http: false, sse: false}`, `sessionCapabilities {list,
  resume, close}` and `authMethods: []`, with the SDK's `PROTOCOL_VERSION`.
- **oc2.** `@agentclientprotocol/sdk` 1.5.0 (`package.json:2247`).
- **oc3.** `assertSupportedSessionSetup`, called from new, load and resume,
  throws "ACP bridge mode does not support per-session MCP servers" for any
  non-empty `mcpServers` (`translator.session-lifecycle.ts:388-395`). The
  answer of new has `configOptions` and `modes`, no `models` (`:68-89`).
- **oc4.** Replays the bridge's ledger, else transcript text
  (`translator.session-lifecycle.ts:91-144`); a complete replay only for
  sessions the bridge created (`docs/cli/acp.md:34, 47`).
- **oc5.** Resume works for Gateway keys only. The session store is per
  process (`server.ts:269`), so the UUID `session/new` gave throws
  `Session <uuid> not found` after a restart
  (`translator.session-lifecycle.ts:203-233`,
  `translator.session-state.ts:66-70`). Bridge sessions are "synthetic and
  disposable" and pruned (`docs/cli/acp.md:269`).
- **oc6.** Lists every Gateway session, under Gateway keys, with a cwd filter
  and a cursor (`translator.session-lifecycle.ts:146-201`,
  `translator.session-state.ts:78-90`).
- **oc7.** The modes are the Gateway thinking levels, and `session/set_mode`
  patches `thinkingLevel` (`translator.presentation.ts:115-188`,
  `translator.session-lifecycle.ts:247-270`). The model is not exposed as an
  option (`docs/cli/acp.md:50`); only the `/model` command changes it.
- **oc8.** `thought_level` (off, minimal, low, medium, high, adaptive),
  `fast_mode`, `verbose_level`, `trace_level`, `reasoning_level`,
  `response_usage`, `elevated_level` (`translator.presentation.ts:115-188`).
- **oc9.** A resource is flattened to text; a link becomes the text
  `[Resource link (title)] <uri>` (`event-mapper.ts:220-265`).
- **oc10.** Kinds read, edit, delete, move, search, execute, fetch and other,
  guessed from the tool name (`event-mapper.ts:285-329`). Text content; diffs
  were not read. Status starts `in_progress`, never `pending`, and ends
  `completed` or `failed` (`translator.agent-events.ts:75-113`).
- **oc11.** Exec approvals only, `allow_once`, `allow_always` and
  `reject_once`, narrowed to what the Gateway allows; a cancelled, failed or
  late answer is `deny` (`permission-relay.ts:25-55`,
  `translator.agent-events.ts:238-266`).
- **oc12.** The bridge handles only Gateway `chat`, `exec.approval.requested`
  and `agent` events (`translator.prompt-stream.ts:165-177`). The Gateway's
  `ask_user` and `secrets` tools go through Gateway `question.*` and never
  reach ACP.
- **oc13.** Cancel answers `cancelled` at once, denies an open approval and
  sends Gateway `chat.abort` (`translator.prompt-stream.ts:375-428,
  451-462`). A concurrent `session/prompt` aborts the running turn and then
  runs (`:198-224`).
- **oc14.** Events pass only when the session key and run id match the
  pending prompt (`translator.prompt-stream.ts:667-690`); child sessions show
  only as lineage `_meta`. No `subagent_update`, no stop.
- **oc15.** `usage_update` with used and size, marked approximate, only when
  fresh; no cost; the answer is `{stopReason}` only
  (`translator.session-state.ts:122-131`).
- **oc16.** 25 Gateway slash commands, `help` to `compact`, sent as plain
  prompt text (`commands.ts:4-41`).
- **oc17.** Title from `derivedTitle`, `displayName`, `label` or the key,
  with `updatedAt` and lineage `_meta` (`translator.presentation.ts:193-213`).
- **oc18.** `authMethods: []`; the Gateway token or password is set outside
  ACP (`docs/cli/acp.md:304-311`).

**Custom.**

- Session routing `_meta` on new, load, resume and prompt (`sessionKey`,
  `sessionLabel`, `resetSession`, `requireExistingSession`, and on prompts
  `thinking`, `deliver`, `timeoutMs`), or `--session` and
  `--session-label`: attach to a named Gateway conversation. Private
  coupling; shared keys make routing best effort.
- Lineage `_meta` (`parentSessionId`, `spawnedBy`, `spawnDepth`,
  `subagentRole`) on list rows and titles: the subagent graph, read from
  `_meta`, without the children's activity.
- `[Working directory: <cwd>]` prefixed to every prompt unless
  `--no-prefix-cwd`; the Gateway works in its own workspace.
- `--provenance`: a receipt with hostname, cwd and session ids sent to the
  Gateway.
- Gateway credentials by `--url`, `--token`, `--password` (or files) and
  `OPENCLAW_GATEWAY_TOKEN`/`_PASSWORD`.
- A Gateway error ends the turn `end_turn` with no text
  (`translator.prompt-stream.ts:509-513`).

**In chord.** chord passes the person's MCP servers from settings and
`.mcp.json` as they are, so with any configured, every session open fails on
OpenClaw's refusal; chord's own server is withheld, since `mcpCapabilities`
has no http. The start needs a running Gateway and its credentials, set up
outside chord, else a bare start failure. chord resumes a session it has a
record of, and that resume fails in a new bridge process where load would
have worked. Mode and effort are one control, and there is no model picker.
Usage is approximate and sometimes missing; with no cost, chord's estimate
stands. Only exec approvals reach chord; an `ask_user` call stays
`in_progress`. A Gateway error reads as a normal end. @-mentions arrive as
bare URIs the Gateway may not read. chord queues mid-turn prompts, which
avoids the abort. chord never calls `session/list`, and drops titles and
lineage.

**Sources.**

- OpenClaw 2026.10.4, https://github.com/openclaw/openclaw at `v2026.10.4`,
  its `CHANGELOG/` and `src/acp` commit titles.
- https://docs.openclaw.ai/cli/acp (`docs/cli/acp.md` at the tag).

#### opencode

- Name: OpenCode
- Run as: `opencode acp`, from PATH
- Install: <https://opencode.ai/docs/>

Two products answer to `opencode acp`, and they cannot be installed side by
side: v1, `opencode-ai` 1.19.3 (2026-10-16, tag `v1.19.3`), and v2,
`@opencode/cli` 2.0.32 (2026-10-16). Both were read in
<https://github.com/anomalyco/opencode> (MIT, plain TypeScript): v1 at its
tag, under `packages/opencode/src/`; v2 at `dev` 8f7b012 (2026-10-17),
whose `packages/cli/package.json` says 2.0.32, under `packages/cli/src/`.
The v2 npm package ships a compiled binary, so that this tree is 2.0.32 rests
on the version field. Footnote paths are relative to those two folders, or
start at the repository root with `packages/`. A cell gives one value when
both agree, and `v1 … · v2 …` where they differ. No licence limit applies;
nothing rests on a licence-restricted bundle. The registry's binary archive of
1.19.3 is not what chord runs: chord starts the `opencode` on PATH.

**Footnotes.**

- **op1.** v1 `acp/service.ts:94-139`; v2 `acp/service.ts:106-131`, with
  `agentInfo {name: "OpenCode", version}` in both.
- **op2.** `packages/opencode/package.json:57`; `packages/cli/package.json:27`.
  v2 builds its agent with SDK 1.6.0's `agent()` (`acp/agent.ts:58-125`).
- **op3.** v1: `unstable_setSessionModel`, list, fork, resume and close. v2
  adds `additionalDirectories`, `session/delete`, compaction updates,
  `elicitation/create` with `toolCallId`, `$/cancel_request` and
  `auth.terminal`, and drops `set_model` (`acp/agent.ts:58-125`).
- **op4.** v1 `acp/service.ts:163-209` (new), `:211-247` (load), `:295-334`
  (resume), `:249-293` (list, root sessions only), `:362-407` (fork),
  `:347-355` (close), no delete. v2 `acp/service.ts:137-216`, replay in
  `acp/replay.ts:16-138`.
- **op5.** Only config options: `model`, `effort` (category `thought_level`,
  the model's variants plus `default`) and `mode`. v1
  `acp/config-option.ts:31-91`, `set_model` at `acp/service.ts:478-495`; v2
  `acp/config-option.ts:22-66`, sending `config_option_update` on any change
  (`acp/sessions.ts:52-94`). `set_mode` answers `{}` with no update in both.
- **op6.** v1 `acp/content.ts:41-188`; v2 `acp/prompt.ts:21-51`. Audio is
  dropped. v2 sends an embedded resource as synthetic text before the prompt
  (`acp/turn.ts:212-222`).
- **op7.** v1 `acp/tool.ts:65-69`, `:117`, `:124-236`; v2 `acp/tool.ts:16-151`,
  which adds image content and a `name` key.
- **op8.** Both go `pending`, `in_progress`, then `completed` or `failed`. v1
  sends the shell's whole output so far on each update (`acp/event.ts:341-377`).
  v2 sends `in_progress` with no content until the end
  (`acp/translate.ts:352-366`).
- **op9.** v1 `acp/permission.ts:20-24`, `:219-223`; v2
  `acp/permission.ts:39-74`. Any outcome but once or always answers reject.
  v2 queues asks per turn and answers them reject when the turn is cancelled
  (`acp/turn.ts:105-133`).
- **op10.** v1 has no question tool under ACP (`tool/registry.ts:207`, `:233`).
  v2 sends forms for its question tool and the websearch-provider choice only
  (`acp/elicitation.ts:48-176`): `q<i>` and `q<i>_custom`, the own-answer
  field titled `<header> (other)` (`:174`), message `Questions`, or
  `<child>: Questions` for a subagent (`:93`).
- **op11.** `todowrite` is a plain tool call (v1 `acp/tool.ts:68-69`).
- **op12.** v1 aborts the session and its background jobs
  (`session/run-state.ts:76-85`). v2 interrupts, waits up to 5 s, and marks
  open calls `failed` (`acp/turn.ts:261-279`); children keep running and only
  their asks reach the client (`:295-313`).
- **op13.** No `_meta.steering`. A second `session/prompt` joins the running
  loop in v1 (`session/prompt.ts:1343-1346`) and is refused in v2
  (`acp/turn.ts:375-393`).
- **op14.** v1 drops a child's events, so a subagent is one `task` call
  (`acp/event.ts:194-195`), and a child's permission ask is dropped
  unanswered (`acp/permission.ts:53-54`). v2 projects children into the
  parent with `_meta["opencode/child-session"]` (`acp/child.ts:39-67`).
- **op15.** One `usage_update` per turn, at its end, `cost` the session's USD
  total. `used` is input plus cache tokens in v1 (`acp/usage.ts:86-115`), and
  adds output and reasoning in v2 (`acp/turn.ts:328-350`). The answer's
  `usage` is the last message in v1, the whole turn in v2
  (`acp/translate.ts:150-168`). Free models send cost 0.
- **op16.** v1 `acp/service.ts:988-1008`; v2 `acp/sessions.ts:75-78`.
- **op17.** v1 sends no `session_info_update`. v2 sends one only to carry
  `_meta` retry and compaction markers (`acp/translate.ts:258-276`).
- **op18.** One method, `opencode-login`; `authenticate` answers `{}` (v1
  `acp/service.ts:96-146`, v2 `:106-136`).
- **op19.** v1 sends `fs/write_text_file` after an allowed edit without
  checking `fs` (`acp/permission.ts:84-115`). v2 calls nothing back.
- **op20.** v1 maps http and sse to remote servers (`acp/service.ts:1010-1072`).
  v2 refuses any server not stdio or http with an error
  (`acp/service.ts:243-253`).
- **op21.** v1 `{loadSession, mcpCapabilities {http, sse}, promptCapabilities
  {embeddedContext, image}, sessionCapabilities {close, fork, list,
  resume}}`. v2 has `sse: false`, adds `additionalDirectories` and `delete`,
  and `_meta {"opencode/child-session-updates": true}`.
- **op22.** v1 reads only `_meta["terminal-auth"]`. v2 also reads
  `elicitation.form`, `session.compaction`, `auth.terminal` and
  `_meta["opencode/child-session-updates"]` (`acp/capabilities.ts:7-15`).

**Custom.**

- **`opencode/session/child_update`** (v2, `acp/child.ts:3`): each child's
  status and updates as an extension notification. A client declares
  `clientCapabilities._meta["opencode/child-session-updates"]`. Costs a
  private coupling.
- **`_meta["opencode/child-session"]`** (v2): marks child traffic projected
  into the parent, with tool ids `<child>:<id>`. A client must read the key.
- **`_meta["opencode/retry"]`** (v2) on `session_info_update` and the prompt
  answer: provider retry state. Free to read; nothing to declare.
- **`terminal-auth`** (both): a login command on the auth method, behind
  `clientCapabilities._meta["terminal-auth"]`.
- **Off spec, v1:** `fs/write_text_file` undeclared; a prompt starting with
  an unknown `/…` is dropped with `end_turn` (`acp/service.ts:588-589`).

**In chord.**

- chord's opencode question enricher (`src/session/enrichers.ts:617-662`)
  matches no release. v1 sends no form; v2 titles the own-answer field
  `<header> (other)`, not `(other)`. A v2 question falls to the generic form,
  where answering still works. The `askopencode` scenario and its fixture play
  a shape no release sends.
- An Esc on a v2 question fails the tool and ends the step
  (`packages/core/src/session/runner/step.ts:206-224`, inferred, not run).
- v2 children land flat in the parent, titled `<child>: …`; after a cancel
  their asks arrive with no turn running, and chord refuses them unseen
  (CHD-158).
- Free models report cost 0, which chord takes as the price and stops its
  estimate; the meter overstates context on v2, as `used` includes output.
- chord reads the config options, resumes or loads, and never calls
  `session/list`, fork, delete or close. It adds its own http MCP server; it
  passes a person's sse server unfiltered, which v2 refuses.
- v1's `fs/write_text_file` gets method-not-found; the edit still lands.
  `authenticate` is never called; paid providers need `opencode auth login`.

**Sources.**

- `opencode-ai` 1.19.3, tag `v1.19.3` of
  <https://github.com/anomalyco/opencode>.
- `@opencode/cli` 2.0.32, `dev` 8f7b012 of the same repository.
- <https://opencode.ai/docs/>, fetched 2026-10-18.

#### poolside

- Name: Poolside
- Run as: `pool acp`, from PATH
- Install: <https://github.com/poolsideai/pool>

pool 1.0.16, released 2026-08-14 and still the latest release on 2026-10-18,
read from <https://github.com/poolsideai/pool> at `main` fcabc59
(2026-08-18), which holds only `README.md`, `CHANGELOG.md`, `LICENSE.md` and
third-party notices, and from <https://docs.poolside.ai>. The agent is a
closed native binary under the Poolside End User License Agreement, whose
§2.2(3) forbids reverse engineering or otherwise discovering its source. The
licence question is with the owner. Nothing was downloaded or inspected,
strings included, so no cell rests on the binary and none says
`c (bundle)`: every cell is `n` or `?`. The registry lists the same version
as a binary archive; chord runs the `pool` on PATH.

**Footnotes.**

- **po1.** README:147-153 ("ACP features"); CHANGELOG 1.0.2
  (`session/close`) and 1.0.6 (`session/delete`, message ids). The protocol
  version and SDK are not documented.
- **po2.** README:149: "Session persistence: `session/list` and
  `session/load`". `session/new` is the registry's and README's baseline.
  Resume and fork are not named; the TUI's `pool -r` is client-side.
- **po3.** README:151-152: "approval mode, agent mode, model, and thought
  level when supported", sent through `session/set_config_option`. Build and
  Plan are a separate selector since 1.0.15. Poolside-hosted thought levels
  are `max` and `none`. Whether modes also go through `session/set_mode` is
  not said.
- **po4.** The read tool takes images (CHANGELOG 1.0.13); prompt
  capabilities are not documented.
- **po5.** CHANGELOG 1.0.3 adds "Accept edits for this session" to the
  permission dialog. Option kinds, cancel and timeout are not documented.
  Auto mode (1.0.16) answers low- and medium-risk asks itself with a
  classifier; only high-risk ones reach the client.
- **po6.** `docs/design/CHD-1.md:47` in chord's repository: "probably an
  elicitation form (medium confidence)". CHANGELOG 1.0.5 names elicitations
  only for pool as a client. Nothing documents `pool acp` sending one.
- **po7.** CHANGELOG 1.0.16: returning from Plan to Build "always requires
  your review"; how it asks is not said.
- **po8.** README:150: "Mid-turn steering via the `poolside/session_steer`
  capability". The capability's shape, and the rest of `agentCapabilities`,
  are not documented.
- **po9.** README:115-117 and the docs' subagents page: a `general` subagent
  and named ones, in-process or another ACP server. "You review their
  approval requests in the parent session." The wire shape is not said.
- **po10.** `/usage` shows tokens, context and cost, per subagent too
  (README:117, CHANGELOG 1.0.6). `usage_update` is not documented.
- **po11.** README:153: "Slash commands advertised to the client": `/plan`,
  `/clear`, `/compact`, `/share`, `/rename`, `/mcp`, `/sandbox`,
  `/sandbox-apply-to-host`, `/usage`, `/skills` and skills.
- **po12.** `/rename` exists (CHANGELOG 1.0.5); titles on the wire are not
  said.
- **po13.** `pool login` or `POOLSIDE_API_KEY` with
  `POOLSIDE_STANDALONE_BASE_URL` (docs `get-started/log-in`). The
  troubleshooting page says bad credentials fail at the first
  `session/prompt`. `authenticate` is not documented.
- **po14.** `pool mcp add` takes stdio, http and sse servers into pool's own
  settings (docs `mcp-servers`); which transports `session/new` accepts is
  not said.

**Custom.**

- **`poolside/session_steer`** (1.0.16): folds a new prompt into a running
  turn. A client must negotiate a Poolside-private capability whose shape is
  undocumented. Costs a private coupling.
- **Auto approval mode** (1.0.16), a config option: a classifier model
  approves low- and medium-risk calls. Costs spend on the classifier, and the
  person sees only high-risk asks.
- **Hooks** (README:111, `settings.yaml`): may block or rewrite tool calls and
  prompts before the client sees them. Nothing to declare.
- **Launch flags** `--sandbox` and `--settings` (README:145). chord passes
  only `acp`.

**In chord.**

- By the docs, sessions (new, load, close), the config options and the slash
  commands work through chord's standard paths. chord never calls
  `session/list`.
- pool's `/clear` and `/mcp` share names with chord's own commands; which one
  a person reaches is unchecked.
- Steering is pool's own capability, so chord queues a mid-turn prompt.
- Sign-in is outside chord; a bad login shows only as a failed first prompt.
- Questions and the Plan-to-Build review have unknown shapes; they fall to
  chord's generic form or permission box.
- The fake agent has no pool scenario: without a known shape, any would be a
  guess.

**Sources.**

- pool 1.0.16: `README.md`, `CHANGELOG.md` and `LICENSE.md` of
  <https://github.com/poolsideai/pool>.
- <https://docs.poolside.ai>: log-in, troubleshooting, permissions,
  subagents and MCP pages.
- Poolside End User License Agreement, <https://poolside.ai/eula>.

#### zeroclaw

- Name: ZeroClaw
- Run as: `zeroclaw acp`, from PATH
- Install: <https://github.com/zeroclaw-labs/zeroclaw>

ZeroClaw v0.8.5, released 2026-09-05 and still the latest release on
2026-10-18, read at tag `v0.8.5` of
<https://github.com/zeroclaw-labs/zeroclaw> (MIT or Apache-2.0, plain Rust,
no limits on reading). It is not in the ACP Registry; chord starts it from
its own CLI table as `zeroclaw acp`. Paths are relative to the repository
root; the server is `crates/zeroclaw-channels/src/orchestrator/acp_server.rs`
(`acp_server.rs` below) and the back-channel to the client is
`crates/zeroclaw-channels/src/acp_channel.rs`. `master` at 3f2f028
(2026-10-17, unreleased) was diffed against the tag: the session-update
kinds, the extension methods and the dispatch table are unchanged.

**Footnotes.**

- **zc1.** `acp_server.rs:575-620` answers `protocolVersion: 1` whatever the
  client asks; `docs/book/src/channels/acp.md` says the same.
- **zc2.** Hand-rolled JSON-RPC over ndjson with serde_json; no ACP SDK in
  the workspace.
- **zc3.** Dispatch at `acp_server.rs:512-541`: v1 core plus
  `session/resume` and `session/close`; anything else is `-32601`.
- **zc4.** `session/new` answers `{sessionId, workspaceDir}`
  (`acp_server.rs:949-952`). With several `[agents.<alias>]`, no
  `[acp].default_agent` and no `agentAlias` param it fails `-32602`
  (`:697-721`); an agent that cannot be built fails `-32603` (`:813-851`).
- **zc5.** `loadSession` and `sessionCapabilities {resume, close}` only when
  the SQLite store opened (`acp_server.rs:589-605`). Load replays the whole
  history, tool calls as `completed` (`:955-1169`); resume replays only the
  stored plan (`:1172-1370`); close at `:1372`. A session idle past
  `sessionTimeoutSecs` (3600 s) is dropped from memory (`:354-390`).
- **zc6.** No `models`, `modes` or `configOptions` in the answer and no
  setter (dispatch `acp_server.rs:516-525`). The model is fixed per
  `[agents.<alias>]`.
- **zc7.** `promptCapabilities {image: false, audio: false, embeddedContext:
  true}` (`acp_server.rs:599-603`). Text and `resource.text` are joined,
  `resource.blob` is saved under `uploads/`; `resource_link` and `image` are
  dropped without error (`:1869-1963`).
- **zc8.** `map_tool_kind` (`acp_server.rs:2300-2349`) uses only `execute`,
  `edit`, `delete` and `other`; the synthetic cancel row is `think`. A call
  is one `tool_call` `pending` with `rawInput` and one `tool_call_update`
  `completed` or `failed` with the whole output as `rawOutput` and text
  content (`:2368-2447`); edits and writes carry a `diff` (`:2215-2228`). No
  `in_progress`, no `locations`, no terminal content.
- **zc9.** Options `allow_once`, `allow_always`, `reject_once`, and on
  `file_edit` and `file_write` also kind `reject_with_edit`
  (`acp_channel.rs:423-452`). `cancelled` is a deny (`:534-541`); the wait is
  `sessionTimeoutSecs` (`acp_server.rs:869`).
- **zc10.** Only `clientCapabilities.elicitation` is read
  (`acp_server.rs:568-572`), `{}` counting as form. A form has one `choice`
  field (`oneOf` const `choice-i`) or one `choices` array
  (`crates/zeroclaw-api/src/elicitation.rs:127-200`). URL mode is never sent
  (`acp_channel.rs:140-143`). Without form a single choice falls back to a
  permission request with `choice-i` ids (`:53-125`).
- **zc11.** A whole-list `plan` from TodoWrite (`acp_server.rs:2480-2495`),
  replayed on resume.
- **zc12.** `session/cancel` fires the turn's token (`acp_server.rs:2014-2044`).
  The answer is `cancelled` with the partial text in a non-standard
  `content` (`:1834-1842`), after a synthetic completed `turn-cancelled` call
  (`:1844-1866`).
- **zc13.** A second `session/prompt` during a turn gets `-32002
  SESSION_BUSY` (`acp_server.rs:1484-1489`). No steering.
- **zc14.** `spawn_subagent` and `delegate` are tools, one call each
  (`acp_server.rs:2368-2447`); no child session, no `subagent_update`.
- **zc15.** Usage is kept in ZeroClaw's own tracker and never sent: no
  `usage_update`, no `usage` in the answer (`acp_server.rs:1594-1622`,
  `:1826-1832`, `:2498`).
- **zc16.** `authMethods: []` and no `authenticate` (`acp_server.rs:615`);
  provider keys come from ZeroClaw's config.
- **zc17.** The only requests to the client are `session/request_permission`
  and `elicitation/create` (`acp_channel.rs:91`, `:146`, `:385`, `:491`).
- **zc18.** `mcpCapabilities {http: false, sse: false}`
  (`acp_server.rs:604-607`); `mcpServers` is never read. MCP comes from the
  agent's own config, `acp_enable_mcp` (`:805-812`).
- **zc19.** `acp_server.rs:589-620`: `loadSession`, `resume`, `close`,
  `embeddedContext`, `authMethods: []` and `_meta.zeroclaw`.
- **zc20.** Six extensions, each a bullet under Custom below; chord sends and
  reads none of them.

**Custom.**

- `reject_with_edit` option kind, with `proposedEdit` on the tool call and
  `replacementContent` in the answer (`acp_channel.rs:423-525`): "reject,
  but write this instead". A client must accept a kind outside ACP's four;
  an SDK-validating client refuses the whole request.
- `_zeroclaw/history_trimmed` `{droppedMessages, keptTurns, reason}`
  (`acp_server.rs:2464-2479`): history was cut to fit. A client reads the
  notification; nothing to send.
- Inbound `session/stop`, `session/event` and `session/update`
  (`acp_server.rs:1966-2100`): requests a client may send; free.
- `_meta.zeroclaw {maxSessions, sessionTimeoutSecs, defaultModel}` in
  `initialize`: informational.
- `agentAlias` (or `agent_alias`, `agent`) on `session/new` picks the agent;
  the client must send it. `master` adds `zeroclaw acp --agent <alias>`,
  unreleased.
- Launch flags `--max-sessions` and `--session-timeout` (`src/main.rs:690-699`).

**In chord.** Supervised edit approvals cannot be answered: the SDK's
schema in chord's `session/request_permission` handler allows only the four
standard kinds, so a request carrying `reject_with_edit` is answered
invalid-params before chord sees it, and the edit gets no approval. Other
tools' approvals work. `session/new` fails before any turn when ZeroClaw has
several agents and no default, because chord sends no `agentAlias`.
@-mentions are lost, since chord sends them as `resource_link`; images are
not offered. Questions come as forms and chord's generic form path reads the
one `choice` field; chord never meets the permission fallback. The model,
mode and effort pickers are empty, and the meter and estimate have no tokens.
A cancel leaves a completed row titled `turn-cancelled`. Tool rows jump from
pending to done. chord resumes when it has its own record (plan only), else
loads; a session idle over an hour answers `-32000 Session not found`.
Ignored: `_zeroclaw/history_trimmed`, `_meta.zeroclaw`, extra keys; chord's
MCP server is not offered (`http: false`).

**Sources.**

- ZeroClaw v0.8.5, <https://github.com/zeroclaw-labs/zeroclaw/tree/v0.8.5>,
  and `master` at 3f2f028.
- `docs/book/src/channels/acp.md` in that repository.
- `@agentclientprotocol/sdk` 1.8.0, `dist/schema/zod.gen.js:318-323`.

## 4. What this changes on the board

Not yet filled: the open tasks and questions this closes or changes, and the
new tasks it suggests, as a list for the owner. Nothing is filed or decided
here.

## Sources

Not yet filled.
