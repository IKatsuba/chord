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
were read only.

For an agent whose licence limits reverse-engineering (bob, cursor, nova,
auggie, factory-droid, poolside), the owner's rule of 2026-10-18, recorded on
CHD-433, holds: its bundle is read as plain text only for what crosses the
wire, the messages, fields and capabilities it sends and accepts. These pages
name none of its internals and quote none of its code, cite its docs and
release notes first where they state a fact, and nothing is deobfuscated.

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
| auggie | 1 c | SDK 0.14.1 c [au1] | v1 + unstable c [au2] |
| autohand | 1, the client's echoed c [ah1] | SDK 0.12.0 c [ah2] | v1 + unstable c [ah3] |
| bob | 1 c [bo1] | SDK 1.3.0 c [bo2] | v1 + private `_bob/*` n, c [bo3] |
| claude-acp | 1, fixed; 2 behind an env c [cl1] | SDK 1.9.0, pinned c [cl2] | v1 + unstable, RFDs, own c [cl3] |
| cline | 1, whatever is asked c [ci1] | SDK 0.16.1 c [ci2] | v1 + `set_model` c [ci3] |
| codebuddy-code | 1 c [cb1] | SDK 1.7.0 c [cb2] | v1 + `set_model`, `resume` c [cb3] |
| codex-acp | 1; v2 reverted in 2.1.0 c [cx1] | SDK 1.5.0 c [cx2] | v1 + unstable, drafts, own c [cx3] |
| deepagents | 1, the client's echoed c [da1] | SDK ^0.17.0 (0.17.1) c [da2] | v1 only c [da3] |
| dimcode | 1 c [dm1] | SDK 0.21.1 c [dm2] | v1 + unstable, `_lody/*` c [dm3] |
| dirac | 1, always c [di1] | SDK 1.3.0 c [di2] | v1 + unstable and drafts c [di3] |
| factory-droid | 1 c [dr1] | SDK 1.5 c [dr2] | v1 + `set_model` c [dr3] |
| fast-agent | 1, the client's echoed c [fa1] | Python acp 0.10.1 c [fa2] | v1 + `userMessageId` c [fa3] |
| gemini | 1 c [ge1] | SDK 0.16.1, exact pin c [ge2] | v1 + `set_model` c [ge3] |
| github-copilot-cli | ?; v1 methods n [co1] | ? native, not named n [co1] | v1 + `github.com/copilot/*` n [co2] |
| glm-acp-agent | 1 c [gl1] | SDK 0.20.0, pinned c [gl2] | v1 + unstable fork, set_model c [gl3] |
| grok-build | 1 c [gr1] | Rust crate 0.10.4 c [gr2] | v1 + unstable, 300+ `x.ai/*` c [gr3] |
| kilo | 1, whatever is asked c [ki1] | SDK 0.21.0 c [ki2] | v1 + fork, set_model c [ki3] |
| minimax-code | 1, whatever is asked c [mm1] | SDK 1.x (≤ 1.4.0), bundled c [mm2] | v1 + fork, `plan_update` c [mm3] |
| minion-code | min(asked, 1) c [mi1] | Python acp ≥ 0.7.0, unbounded c [mi2] | v1; unstable unreachable c [mi3] |
| nova | 1 to chord, 2 if asked c [no1] | none, own JSON-RPC c [no2] | v1, a v2 permission, own c [no3] |
| pi-acp | 1, whatever is asked c [pi1] | SDK 0.26.0 c [pi2] | v1 + terminal auth c [pi3] |
| qoder | 1, whatever is asked c [qo1] | own schema copy, version ? c [qo2] | v1 + `set_model` c [qo3] |
| qwen-code | 1 c [qw1] | SDK 0.14.1 c [qw2] | v1 + unstable, large own c [qw3] |
| sigit | 1 c [si1] | Rust crate 2.2.0 c [si2] | v1 + unstable fork c [si3] |
| cursor | 1 c | SDK 0.14.1 c [cu1] | v1 + unstable c [cu2] |
| devin | ? | ? (Rust, crate unknown) n [dv1] | v1, rest ? n [dv2] |
| fx | 1, whatever is asked c [fx1] | none, own Zig layer c [fx2] | v1 + list, resume, close, RFDs c [fx3] |
| goose | 1, even if 2 is offered c [go1] | Rust crate 2.2.0 c [go2] | v1 + list, delete, close c [go3] |
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
| auggie | ✓; `authRequired` c [au3] | ✓ no plans c [au4] | ✗ c | ✓ cwd filter c [au4] | ✗ c | ✗ · ✗ c |
| autohand | ✓; `authRequired` r [ah4] | ✓ text only r [ah5] | ◐ the CLI's ids only r [ah6] | ◐ lists turns c [ah6] | ◐ this process only r [ah6] | ✗ · ✗ c |
| bob | ✓ needs login n, c [bo4] | ✓ full replay n [bo5] | ✓ no replay n [bo5] | ✓ paged n, c [bo6] | ✗ c [bo6] | ✓ · ✓ n, c [bo6] |
| claude-acp | ✓ + `_meta`, no `models` c [cl4] | ✓ replays subagents c [cl5] | ✓ r [cl5] | ✓ paged, cwd filter n [cl6] | ✓; fork point by `_meta` c [cl7] | ✓ · ✓ n [cl8] |
| cline | ✓ needs a login c [ci4] | ✓ model back to default r [ci5] | ✗ r [ci5] | ✗ c [ci6] | ✗ c [ci6] | ✗ · ✗ c [ci6] |
| codebuddy-code | ✓ c [cb4] | ✓ full replay c [cb5] | ◐ served, not advertised c [cb6] | ✗ c [cb3] | ✗ c [cb3] | ✗ · ✗ c [cb3] |
| codex-acp | ✓; roots marked trusted c [cx4] | ✓ with child tree, tasks n [cx5] | ✓ survives a restart r [cx5] | ✓ the person's other threads c [cx6] | ✓; fork point by `_meta` c [cx7] | ◐ archives · ✓ c [cx8] |
| deepagents | ✓ c [da4] | ◐ memory only r [da5] | ✗ c | ✗ c | ✗ c | ✗ · ✗ c |
| dimcode | ✓ read-only preset c [dm4] | ✓ c [dm5] | ✓ no replay c [dm5] | ✓ paged c [dm6] | ✓ unstable, at a turn c [dm7] | ✗ · ✓ c [dm8] |
| dirac | ✓; worktree opt-in c [di4] | ✓ replays its journal c [di5] | ✗ advertised, -32601 c [di6] | ✗ not reachable c [di7] | ✗ c | ✓ · ✓ c [di8] |
| factory-droid | ✓ signed in only c [dr4] | ✓ full replay c [dr5] | ✓ no replay c [dr6] | ✓ 50 a page c [dr7] | ✗ c | ✗ · ✗ c |
| fast-agent | ✓ r | ✓ replays text r [fa4] | ◐ alias for load, replays r [fa4] | ✓ cwd filter, paged c [fa5] | ✗ slash command only r [fa6] | ✗ · ✗ slash only r [fa6] |
| gemini | ✓; signs in itself r [ge4] | ✓ replays history r [ge5] | ✗ c | ✗ c | ✗ c | ✗ · ✗ c |
| github-copilot-cli | ✓ n [co3] | ✓ since 0.0.410 n [co4] | ✓ n [co5] | ◐ named, not confirmed n [co6] | ? n [co6] | ? · ✓ since 1.0.78 n [co7] |
| glm-acp-agent | ✓ c [gl4] | ✓ text only c [gl5] | ✓ no replay c [gl5] | ✓ no paging c [gl6] | ◐ unstable, latest only c [gl7] | ✗ · ✓ c [gl8] |
| grok-build | ✓ no `modes` c [gr4] | ✓ replays history c [gr5] | ✓ unstable, no extra dirs c [gr5] | ✓ not in chat mode c [gr6] | ✗; own `x.ai/session/fork` c [gr6] | ✗ own method · ✓ c [gr6] |
| kilo | ✓ r [ki4] | ✓ with replay r [ki4] | ✓ no replay r [ki4] | ✓ 100 per page c [ki5] | ✓ last 20 replayed c [ki6] | ✗ · ✓ r [ki4] |
| minimax-code | ✓ needs a login c [mm4] | ✓ stored cwd only c [mm5] | ✓ stored cwd only c [mm5] | ✓ no subagent sessions c [mm6] | ✓ unstable, stored cwd c [mm5] | ✗ · ✓ c [mm7] |
| minion-code | ✓ needs a key or login c [mi4] | ✗ in memory only c [mi5] | ✗ unreachable c [mi3] | ✗ unreachable c [mi3] | ✗ unreachable c [mi3] | ✗ · ✗ c [mi5] |
| nova | ✓ + `systemPrompt` c [no4] | ✓ c [no4] | ✓ c [no4] | ✓ + own search c [no4] | ◐ advertised c [no4] | ✓ · ◐ c [no4] |
| pi-acp | ✓ absolute cwd c [pi4] | ✓ no thoughts c [pi5] | ✗ c [pi6] | ✓ by cwd, 50 a page c [pi6] | ✗ c [pi6] | ✓ · ✗ c [pi6] |
| qoder | ✓ needs a login c [qo4] | ✓ replay may trail answer c [qo5] | ✗ no handler c [qo3] | ✓ by cwd, with titles c [qo6] | ✗ no handler c [qo3] | ✗ · ✗ c [qo3] |
| qwen-code | ✓ c [qw4] | ✓ c [qw4] | ✓ unstable c [qw4] | ✓ unstable c [qw4] | ✗; own `fork_agent` c [qw4] | ✗ · ✗; own methods c [qw4] |
| sigit | ✓ c [si4] | ✓ full replay c [si5] | ✓ saved sessions only c [si6] | ✓ paged c [si7] | ✓ unstable, latest only c [si8] | ✓ · ✓ c [si9] |
| cursor | ✓ c [cu3] | ✓ c [cu4] | ✗ c | ✓ unstable c [cu5] | ✗ c | ✗ · ✗ c |
| devin | ✓ n [dv3] | ✓ n [dv4] | ? n [dv5] | ✓ n [dv6] | ? n [dv7] | ? · ? |
| fx | ✓ c [fx4] | ✓ full replay c [fx5] | ✓ c [fx5] | ✓ across workspaces c [fx6] | ✗ c | ✗ · ✓ c [fx7] |
| goose | ✓ needs a provider c [go4] | ✓ full replay c [go5] | ✗ c | ✓ c [go6] | ◐ not advertised c [go7] | ✓ · ✓ c [go8] |
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
| auggie | default · ask c [au5] | ✓ legacy, may be null c [au5] | ✗ c | ✗ over ACP c [au5] |
| autohand | ✓ six, legacy r [ah7] | ✓ legacy, next run r [ah7] | ✓ nine selects r [ah7] | ◐ no `thought_level` r [ah8] |
| bob | ✓ `set_mode` n, c [bo7] | ✗ n, c [bo8] | ✗ c [bo8] | ✗ c [bo8] |
| claude-acp | ✓ five, `auto` per model n [cl9] | ◐ option only, no set_model c [cl3] | ✓ five incl. effort, fast c [cl10] | ✓ `thought_level` c [cl10] |
| cline | ✓ plan · act r [ci7] | ◐ `provider` select first c [ci8] | ✓ five, one boolean c [ci8] | ✗ `--thinking` flag only c [ci9] |
| codebuddy-code | ✓ seven permission modes c [cb7] | ✓ c [cb7] | ✓ six selects and more c [cb7] | ✓ `thought_level` c [cb7] |
| codex-acp | ✓ four, `agent` default c [cx9] | ✓ + `set_model` c [cx10] | ✓ five incl. Plan, Fast c [cx11] | ✓ `thought_level` c [cx11] |
| deepagents | ◐ three, no effect r [da6] | ✗ fixed by `--model` r [da6] | ✗ r | ✗ r |
| dimcode | agent · goal c [dm9] | ✓ c [dm10] | mode, model, effort, permission c [dm11] | ✓ per model c [dm11] |
| dirac | plan · act c [di9] | ✗; `model` option c [di10] | mode, model, effort, booleans c [di11] | ◐ two `thought_level` c [di11] |
| factory-droid | 5, org-capped c [dr8] | ✓ c [dr9] | autonomy · model · effort c [dr8] | ✓ per model c [dr8] |
| fast-agent | ◐ one per agent r [fa7] | ✗ `/model` only r [fa7] | ✗ r | ✗ fixed by the env var r [fa7] |
| gemini | 4 by `set_mode`; text update c [ge6] | ✓ `models`, `auto` + ids r [ge7] | ✗ r | ✗ r |
| github-copilot-cli | agent · plan · autopilot n [co8] | ✓ option, with metadata n [co9] | model, effort, agent… n [co10] | ✓ option; `--effort` flag n [co11] |
| glm-acp-agent | default · accept_edits · bypass r [gl9] | ✓ r [gl10] | thought_level · mode · model c [gl11] | ✓ per model c [gl11] |
| grok-build | ◐ undeclared, `plan` works c [gr7] | ✓ unstable `models` c [gr8] | model · reasoning_effort c [gr9] | ✓ five levels c [gr9] |
| kilo | ✓ as option `mode` r [ki7] | ✓ as option `model` r [ki7] | ✓ model, effort, mode c [ki8] | ✓ `thought_level` r [ki7] |
| minimax-code | ◐ default · plan, next prompt c [mm8] | ✓ `model` option c [mm9] | ✓ three, one process-wide c [mm10] | ✓ `thinkingEffort` c [mm10] |
| minion-code | ✓ five, legacy c [mi6] | ◐ after login; `set_model` ✗ c [mi7] | ✗ c | ✗ c |
| nova | ◐ set_mode taken c [no5] | ◐ set_model taken c [no5] | ✗ r [no6] | ✗ r [no6] |
| pi-acp | ◐ thinking levels c [pi7] | ✓ `model` option c [pi8] | ✓ model · thought_level c [pi8] | ✓ `thought_level` c [pi8] |
| qoder | ✓ four, legacy c, n [qo7] | ✓ legacy + `set_model` c [qo8] | ◐ only in a set's answer c [qo9] | ✗ c [qo9] |
| qwen-code | ✓ `set_mode` and option c [qw5] | ✓; inside change private c [qw5] | mode, model, effort c [qw5] | ◐ `thought_level`, per model c [qw5] |
| sigit | Manual · Auto · Plan c [si10] | ◐ config option only c [si11] | model · inference · mode c [si12] | ✗ c |
| cursor | agent · plan · ask n, c [cu6] | ✓ c [cu7] | mode · model c [cu7] | ◐ opt-in `_meta` c [cu7] |
| devin | ✓ six, shape ? n [dv8] | ✓ config option n [dv9] | model · effort · speed · dirs n [dv10] | ✓ option, category ? n [dv11] |
| fx | auto · ask · full-access c [fx8] | ✗ set_model; config only c [fx9] | provider · model · mode · effort c [fx9] | ✓ `effort` c [fx10] |
| goose | auto · approve · smart · chat c [go9] | ✗ set_model; config only c [go10] | provider · mode · model · effort c [go10] | ✓ `thinking_effort` c [go11] |
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
| auggie | ✓ c [au6] | ✓ c [au6] | ✗ dropped c [au6] | ✗ dropped c [au6] | ◐ `file://` path only c [au6] |
| autohand | ✓ c | ◐ never reaches the model c [ah9] | ✗ placeholder text c [ah9] | ✓ inlined c [ah10] | ✓ read, inlined c [ah10] |
| bob | ✓ c [bo9] | ✓ n, c [bo9] | ◐ as `[audio]` c [bo9] | ✓ text inlined c [bo9] | ◐ as text, not fetched c [bo9] |
| claude-acp | ✓ c [cl11] | ✓ base64 · URL c [cl11] | ✗ dropped c [cl11] | ◐ text only c [cl11] | ◐ as a markdown link c [cl11] |
| cline | ✓ c [ci10] | ✗ though advertised c [ci10] | ✗ c [ci10] | ✗ c [ci10] | ✗ c [ci10] |
| codebuddy-code | ✓ c [cb8] | ✓ base64 or http c [cb8] | ✗ dropped silently c [cb8] | ◐ text only c [cb8] | ◐ as link text c [cb8] |
| codex-acp | ✓ c [cx12] | ✓ c [cx12] | ✗ dropped c [cx12] | ✓ text · blobs c [cx12] | ◐ text link only c [cx12] |
| deepagents | ✓ c | ◐ always `image/png` c [da7] | ✗ c | ✓ inlined c [da8] | ✗ `[object Object]` c [da8] |
| dimcode | ✓ c | ✓ c [dm12] | ✗ refused c [dm12] | ✓ inlined c [dm12] | ◐ name only c [dm12] |
| dirac | ✓ c | ✓ c | ✗ c | ◐ text dropped c [di12] | ✗ dropped c [di12] |
| factory-droid | ✓ c | ✓ c | ✗ dropped c [dr10] | ✓ as text c [dr10] | ✓ as text c [dr10] |
| fast-agent | ✓ c | ✓ c [fa8] | ✗ placeholder text c [fa8] | ✓ text inlined c [fa8] | ◐ path not decoded c [fa9] |
| gemini | ✓ c | ✓ c [ge8] | ✓ inline c [ge8] | ✓ joins the prompt c [ge8] | ◐ `file://` only; may ask c [ge8] |
| github-copilot-cli | ✓ n [co12] | ? | ? | ◐ `embeddedContext` named n [co12] | ? |
| glm-acp-agent | ✓ c | ✓ c [gl12] | ✗ a text note c [gl12] | ✓ text c [gl12] | ◐ name only c [gl12] |
| grok-build | ✓ c | ◐ taken, not advertised c [gr10] | ✗ invalid_params c [gr10] | ✓ c | ✓ also as `@path` c [gr10] |
| kilo | ✓ c [ki9] | ✓ c [ki9] | ✗ c [ki9] | ✓ c [ki9] | ✓ `file://`, `zed://` c [ki9] |
| minimax-code | ✓ c [mm11] | ✗ refused c [mm11] | ✗ refused c [mm11] | ✗ refused c [mm11] | ◐ as a text line c [mm11] |
| minion-code | ✓ joined by newlines c [mi8] | ✗ dropped c [mi8] | ✗ dropped c [mi8] | ✗ dropped c [mi8] | ✗ dropped c [mi8] |
| nova | ✓ c [no7] | ✓ c [no7] | ✗ c [no7] | ✓ c [no7] | ? [no7] |
| pi-acp | ✓ no separator c [pi9] | ✓ c [pi9] | ✗ marker text c [pi9] | ◐ inlined, opt-in c [pi9] | ◐ `[Context] <uri>` c [pi9] |
| qoder | ✓ c [qo10] | ✓ c, n [qo10] | ✓ as inline data c [qo10] | ◐ as an `@uri` mention c [qo10] | ✓ `file://` read, else text c [qo10] |
| qwen-code | ✓ c | ✓ c [qw6] | ✓ inline, clamped c [qw6] | ✓ embedded c [qw6] | ◐ `file://` as @-path c [qw6] |
| sigit | ✓ c | ✓ if the model takes it c [si13] | ✓ if the model takes it c [si13] | ✓ inlined c [si13] | ✓ `file:` read from disk c [si13] |
| cursor | ✓ c | ✓ c | ✗ c | ✓ inlined c [cu8] | ✓ inlined c [cu8] |
| devin | ✓ n | ? | ? | ? | ◐ inferred n [dv12] |
| fx | ✓ c | ✓ c | ✗ c | ✓ inlined c [fx11] | ✗ dropped silently c [fx11] |
| goose | ✓ c | ✓ c | ✗ dropped c [go12] | ◐ text only c [go12] | ✓ inlined if readable c [go12] |
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
| auggie | 7 standard kinds c [au7] | ✓ c [au7] | ✓ output only here c [au7] | ◐ · ✓ · ✗ c [au7] | ✓ read, edit c [au7] | pending → completed c [au8] |
| autohand | 8 from a name map c [ah11] | ✓ c [ah11] | ✓ result text c [ah11] | ✓ · ✗ · ◐ c [ah12] | ◐ path as given c [ah11] | pending → completed/failed c [ah13] |
| bob | 7 standard kinds c [bo10] | ✓ c [bo10] | ✓ `{result}` c [bo10] | ◐ · ✓ · ✗ n, c [bo10] | ✓ arguments, results n, c [bo10] | ◐ can stick `pending` c [bo11] |
| claude-acp | 8 incl. `switch_mode` n [cl12] | ✓ `{}` first, then partial n [cl12] | ✓ n [cl12] | ✓ · ✓ · ✗ for chord n [cl12] | ✓ n [cl12] | Bash `pending` to the end r [cl13] |
| cline | all but `switch_mode` c [ci11] | ✓ c [ci11] | ✓ only at the end c [ci11] | ✗ · ✗ · ✗ c [ci11] | ✗ c [ci11] | `in_progress` if approved c [ci12] |
| codebuddy-code | seven of ten c [cb9] | ✓ c [cb9] | ✓ Bash output only here c [cb10] | ✓ · ✓ · ◐ background only c [cb10] | ✓ path, line c [cb9] | ✓ Bash `in_progress` 1 s c [cb10] |
| codex-acp | 8 incl. `switch_mode` n [cx13] | ✓ n [cx13] | ✓ n [cx13] | ✓ · ✓ · id, no terminal n [cx13] | ✓ n [cx13] | `in_progress` while asking n [cx13] |
| deepagents | read, search, edit, execute… c [da9] | ✗ sent as `input` c [da9] | ✗ sent as `output` c [da9] | ◐ · ✗ · ✗ c [da9] | ✓ read, write, edit c [da9] | ends `error` or `cancelled` c [da10] |
| dimcode | 10, guessed from name c [dm13] | ✓ c [dm13] | ✓ whole result c [dm13] | ✓ · ✗ · ✓ if declared c [dm13] | ◐ permission only c [dm13] | in_progress → end c [dm13] |
| dirac | edit, read, search, execute… c [di13] | ✓ c [di13] | ✓ c [di13] | ✗ · ✓ · ✗ c [di13] | ✓ path and line c [di13] | full; cancel ends `failed` c [di13] |
| factory-droid | 6, by tool name c [dr11] | ✓ c | ◐ c [dr11] | ✓ · ✓ · opt-in `_meta` c [dr12] | ◐ edit and read c [dr11] | pending → completed c [dr13] |
| fast-agent | inferred from the name c [fa10] | ✓ c [fa10] | ✓ text or error c [fa10] | ✓ · ◐ · ✗ c [fa10] | ✗ c [fa10] | ◐ r [fa11] |
| gemini | 10 kinds; agent is `think` c [ge9] | ✗ c [ge9] | ✗ c [ge9] | ✓ · ✓ `_meta.kind` · ✗ c [ge9] | ✓ c [ge9] | asked: `pending` → end c [ge9] |
| github-copilot-cli | ? | ◐ named n [co13] | ◐ named n [co13] | ? · ✓ every edit · ? n [co13] | ◐ named n [co13] | ? |
| glm-acp-agent | read, edit, execute, fetch, other c [gl13] | ✓ elided c [gl13] | ✓ elided c [gl13] | ✓ · ✗ · ✗ c [gl13] | ✓ files, URLs c [gl13] | pending → in_progress → end c [gl13] |
| grok-build | 7, no delete or move c [gr11] | ✓ c [gr11] | ◐ some tools c [gr11] | ✓ · ✓ · ✗ c [gr12] | ✓ file tools c [gr11] | pending → in_progress → end c [gr11] |
| kilo | execute, edit, read, search… c [ki10] | ✓ + workdir c [ki10] | ✓ c [ki10] | ✓ · ✓ · ✗ c [ki10] | ✓ c [ki10] | pending → in_progress → end c [ki10] |
| minimax-code | all ten, from the name c [mm12] | ✓ c [mm12] | ✓ output only here c [mm12] | ◐ · ◐ excerpts · ✗ c [mm12] | ✓ c [mm12] | ✓; ids restart each turn c [mm13] |
| minion-code | six + `other` c [mi9] | ✓ c [mi9] | ✓ output only here c [mi9] | ◐ code calls · ✗ · ✗ c [mi9] | ✗ c [mi9] | in_progress → completed c [mi10] |
| nova | ? [no8] | ✓ c [no8] | ? [no8] | ? · ? · ✗ c [no8] | ✓ c [no8] | ? `pending` at an ask c [no8] |
| pi-acp | read · edit · execute · other c [pi10] | ✓ streamed c [pi10] | ✓ not on edits c [pi10] | ✓ · ✓ · ✓ c [pi10] | ✓ from path args c [pi10] | pending → completed c [pi10] |
| qoder | ACP kinds, one as `think` c [qo11] | ✓ c [qo11] | ✓ result as a string c [qo11] | ✓ · ◐ in asks · ? c [qo11] | ✓ from path args c [qo11] | late; live status ? c [qo12] |
| qwen-code | core's kinds, `switch_mode` c [qw7] | ✓ c [qw7] | ✓ when shown c [qw7] | ✓ · ✓ · ✗ c [qw7] | ✓ c [qw7] | full; extra `_meta` update c [qw7] |
| sigit | 8 kinds, status as `think` c [si14] | ✓ c [si14] | ✓ c [si14] | ✓ · ✓ · ✓ if declared c [si14] | ✓ file tools c [si14] | full, `failed` too c [si14] |
| cursor | 9, `switch_mode` too c [cu9] | ✓ trimmed c [cu9] | ✓ per tool c [cu9] | ◐ · ✓ · ✗ c [cu9] | ✓ c | pending → completed c [cu10] |
| devin | ? | ? | ? | ? · ? · ◐ n [dv13] | ? | ◐ n [dv14] |
| fx | 6 kinds, skills `other` c [fx12] | ✓ c | ✗ c [fx12] | ✓ · ✗ · ✗ c [fx13] | ✗ c | pending → in_progress → done c [fx14] |
| goose | none on its own calls c [go13] | ✓ c | ✓ c | ✓ · ✗ · ✗ c [go13] | ✓ c [go13] | pending → done c [go14] |
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
| auggie | once · reject c [au9] | error denies c [au9] | ✗ · ✗ c | ✓ task-list tools c [au10] |
| autohand | once · always · reject, opt-in r [ah14] | ?; chord's SDK refuses all r [ah14] | ✗ · ✗ r | ✓ todo and plan tools r [ah15] |
| bob | once · always · reject n, c [bo12] | cancelled; no timeout c [bo12] | ✓ · ✗ c [bo13] | ✓ n [bo14] |
| claude-acp | once · always · reject once n [cl14] | aborts tool · no timeout n [cl14] | ✓ · ✓ c [cl15] | ✓ + `plan_update` r [cl16] |
| cline | once · always · reject c [ci13] | reject · no timeout c [ci13] | ✗ · ✗ r [ci14] | ✗ r [ci15] |
| codebuddy-code | ◐ allow · reject r [cb11] | ? · timeout ends the turn c [cb12] | ✓ · ✗ c [cb13] | ✓ from `TodoWrite` c [cb14] |
| codex-acp | all four kinds n [cx14] | fails closed · no timeout n [cx14] | ✓ · ✓ c [cx15] | ✓ + `plan_update` n [cx16] |
| deepagents | never asks r [da11] | never asks r [da11] | ✗ · ✗ r | ✗ never sent r [da12] |
| dimcode | all four c [dm14] | rejected; no timeout c [dm14] | ✓ standard · ✗ c [dm15] | ✓ from TodoWrite c [dm16] |
| dirac | all four; always to a file c [di14] | rejected; no timeout c [di14] | ✓ · ✗ c [di15] | ◐ plan cards only c [di16] |
| factory-droid | once · always · reject c [dr14] | not withdrawn c [dr14] | ✓ · sign-in only c, r [dr15] | ✓ always sent c [dr16] |
| fast-agent | four kinds r [fa12] | ? | ✗ · ✗ r | ✗ r |
| gemini | once · always · reject_once c [ge10] | call fails; no timeout c [ge10] | ✗ · ✗ r [ge11] | ✗ r [ge11] |
| github-copilot-cli | once · always; reject ? n [co14] | ? | ? · ? n [co15] | ✓ live plan n [co16] |
| glm-acp-agent | once · reject r [gl14] | rejected; no timeout c [gl14] | ✗ · ✗ r [gl15] | ✗ todos as a tool call r [gl16] |
| grok-build | once · always · reject c [gr13] | cancelled; backstop timeout n [gr14] | ✗ · ✗; own `x.ai/mcp/elicit` c [gr15] | ✓ todo list c [gr16] |
| kilo | once · always · reject r [ki11] | reject r [ki11] | ✗ · ✗ r [ki12] | ✗ r [ki13] |
| minimax-code | once · always · reject c [mm14] | deny · no timeout c [mm14] | ✓ · ✗ c [mm15] | ◐ markdown `plan_update` c [mm16] |
| minion-code | once · always · reject c [mi11] | **allow** · no timeout c [mi11] | ✗ · ✗ c | ✗ `todo_write` is a call c [mi12] |
| nova | once · reject r [no9] | rejected; timeout ? c [no10] | ✗ · ✗; own method r [no11] | ◐ one entry r [no12] |
| pi-acp | none for tools c [pi11] | ? | ✗ · ✗ c [pi11] | ✗ c |
| qoder | once · always · Reject c [qo13] | rejects after 30 s c [qo13] | ✗ · ✗ c [qo14] | ✗ plan in a permission c [qo15] |
| qwen-code | once · always ×3 · reject c [qw8] | cancel; no timeout c [qw8] | ✗ · ✗; questions in `_meta` c [qw8] | ✓ from its todos c [qw9] |
| sigit | all four c [si15] | cancelled ends turn; no timeout c [si15] | ✗ · ◐ in authenticate c [si16] | ✓ c [si17] |
| cursor | once · always · reject n, c [cu11] | rejected; no timeout c [cu11] | ✗ · ✗ n, c [cu12] | ◐ plan mode only c [cu13] |
| devin | once · session · 2 always n [dv15] | ? | ✓ · ? n [dv16] | ? |
| fx | once · session · reject c [fx15] | deny; no timeout c [fx15] | ◐ · ◐ MCP servers only c [fx16] | ✗ c |
| goose | all four kinds c [go15] | tool cancelled; no timeout c [go15] | ✓ · ✗ cancelled inside c [go16] | ✗ c [go17] |
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
| auggie | the whole loop c [au11] | ✗; a prompt runs twice c [au11] | as one call c [au12] | ✗ · ✗ · ✗ c |
| autohand | kills the CLI run r [ah16] | ✗ queued r [ah16] | ✗ r | ✗ · ✗ · ✗ r [ah17] |
| bob | turn and task c [bo15] | ✗ refused c [bo16] | as one call c [bo17] | ✗ · ✗ · ✗ c [bo18] |
| claude-acp | ◐ foreground only n [cl17] | ✓ `_session/steering` c [cl18] | RFD subagent_update r [cl19] | ✓ · ✓ · at the end c [cl20] |
| cline | ◐ lost after a 2nd prompt r [ci16] | ✗ queued r [ci16] | flat in parent r [ci17] | ✗ · ✗ · ✗ r [ci18] |
| codebuddy-code | ◐ turn; background ? c [cb15] | ✗ queued c [cb16] | flat, `parentToolCallId` r c [cb17] | ✓ · ✗ · ✗ r c [cb18] |
| codex-acp | ◐ root turn only c [cx17] | ✓; ignores `promptRequired` c [cx18] | draft subagent_spawned n [cx19] | last call · whole turn · ✗ c [cx20] |
| deepagents | newest stream c [da13] | ✗; a prompt runs alongside r [da13] | as one call r [da14] | ✗ · ✗ · ✗ r |
| dimcode | ◐ run, permissions, terminals c [dm17] | own `_lody`; a prompt refused c [dm18] | as one call; `_lody` opt-in c [dm19] | ✓ · ✗ · ✓ 0 if unpriced c [dm20] |
| dirac | turn, asks, subagents c [di17] | own `whisper`; busy refused c [di18] | ◐ one call, flat c [di19] | ✓ · ◐ session total · ◐ c [di20] |
| factory-droid | turn c [dr17] | ✗ refused c [dr18] | as one call c [dr19] | ✗ · ✗ · ✗ c [dr20] |
| fast-agent | the newest turn task r [fa13] | ✗; a prompt runs alongside r [fa13] | ◐ flat, `parentToolCallId` r [fa14] | ✗ · ✗ · ✗; `_meta` line r [fa15] |
| gemini | prompt, tool, subagent c [ge12] | ✗; 2nd prompt aborts r [ge13] | as one `think` call r [ge14] | ✓ · ✓ no thinking · ✗ r [ge15] |
| github-copilot-cli | the turn; scope ? n [co17] | ? | ◐ subagent ids n [co18] | ✓ · ✓ · ? n [co19] |
| glm-acp-agent | turn, stream, permission c [gl17] | ✗; a prompt aborts the turn c [gl18] | ✗ r [gl19] | ✗ · ✓ turn sum · ✗ c [gl20] |
| grok-build | turn and subagents c [gr17] | queued; own `sendNow` c [gr18] | own notification c [gr19] | ✗ · ✗ · ✗; `_meta` only c [gr20] |
| kilo | ✓ aborts the run c [ki14] | ◐ supersedes at next step r [ki15] | as one call, asks dropped r [ki16] | ✓ · ✓ · ✓ at turn end r [ki17] |
| minimax-code | ◐ turn; subagents ? c [mm17] | ✗ refused; own `steer` c [mm18] | own extension, opt-in c [mm19] | ✓ · ✗ · ✓ c [mm20] |
| minion-code | ◐ between chunks only c [mi13] | ✗ 2nd prompt runs at once c [mi14] | as one call c [mi15] | ✗ · ✗ · ✗ c |
| nova | ✓ process tree n [no13] | ✗ not offered c | ? r [no14] | ✗ · ✗ · ✗ r [no15] |
| pi-acp | ✓ queue cleared, `abort` c [pi12] | ✗ queued in adapter c [pi13] | ✗ c | ✓ · ✗ · ✗ c [pi14] |
| qoder | ◐ may end `end_turn` c [qo16] | ✗ 2nd prompt aborts 1st c [qo17] | ? n [qo18] | ? · `_meta.quota` · ✗ c [qo19] |
| qwen-code | prompt and waiting ones c [qw10] | own `drainMidTurnQueue` c [qw11] | own `_meta`, flat r [qw12] | ✓ · ✗ · ✗; `_meta.usage` c [qw13] |
| sigit | turn, foreground command c [si18] | ✗; a prompt waits c [si19] | ◐ one call, mostly off c [si20] | ✓ · ✗ · ✗ c [si21] |
| cursor | turn and subagents n, c [cu14] | ✗; a prompt cancels c [cu15] | draft shape n, c [cu16] | ✗ · ✗ · ✗ c |
| devin | ◐ parks subagents n [dv17] | ? (CLI steers) n [dv18] | fore- and background, shape ? n [dv19] | ? · ? · ? n [dv20] |
| fx | turn, tools, subagents c [fx17] | own `_meta.fx.steer` c [fx18] | flat, on the parent id c [fx19] | ✓ · ✓ · ✗ since 0.0.14 c [fx20] |
| goose | turn and subagents c [go18] | own `_goose/unstable` c [go19] | as one call c [go20] | ✓ · ✓ · ◐ when known c [go21] |
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
| auggie | ✓ before a prompt c [au13] | ✗ c [au14] | **needed** c [au15] | ✗ · ✗ c [au15] | ✓ · ◐ · ◐ c [au16] |
| autohand | ✓ 24 by default c [ah18] | ✗ on purpose c [ah19] | **needed**, terminal-auth r [ah20] | ◐ · ◐ if declared c [ah21] | ✗ · ✗ · ✗ dropped c [ah22] |
| bob | ✓ c [bo19] | ✓ after a turn n, c [bo20] | ◐ `sso`, browser n, c [bo21] | ✗ · ✗ n, c [bo22] | ✓ · ✓ · ✗ n, c [bo23] |
| claude-acp | ✓ the CLI's + 2 own c [cl21] | ✓ a model call per session c [cl22] | ✗ none offered to chord c [cl23] | ✗ · ✗ c [cl24] | ✓ · ✓ · ✓ c [cl25] |
| cline | ✗ c [ci19] | ◐ `updatedAt`, no title c [ci20] | 3 agent-run OAuth c [ci21] | ✗ · ✗ c [ci22] | ✗ · ✗ · ✗ ignored c [ci23] |
| codebuddy-code | ✓ c [cb19] | ✓ c [cb20] | 4 agent-run, no `type` c [cb21] | ✓ · ✓ if declared c [cb22] | ✓ · ✓ · ✓ c [cb23] |
| codex-acp | ✓ 11 + `$skill` c [cx21] | ✓ a model call per session c [cx22] | 3 agent-run methods c [cx23] | ✗ · ✗ c [cx3] | ✓ · ✓ · ✗ fails new c [cx24] |
| deepagents | ✓ five + custom c [da15] | ✗ c | env key only, no-op r [da16] | ✗ · ✗ c [da17] | ✗ · ✗ · ✗ never read c [da18] |
| dimcode | ✓ `/help`, `/compact` c [dm21] | ✓ c [dm22] | terminal, opt-in c [dm23] | ✓ · ✓ if declared c [dm24] | ✗ dropped · ✓ · ✓ c [dm25] |
| dirac | ✓ before every prompt c [di21] | ✓ once c [di22] | only with no provider c [di23] | ✓ · ✓ if declared c [di24] | ✗ · ✗ · ✗ c [di25] |
| factory-droid | ✓ skills c [dr21] | ✗ c [dr22] | **needed** c [dr23] | ✗ · ✗ c | ✓ · ✓ · ✓ c [dr24] |
| fast-agent | ✓ after new c [fa16] | ◐ on load only c [fa17] | not called; Codex login c [fa18] | ✓ · ✓ if declared c [fa19] | ✓ · ✓ · ✓ c [fa20] |
| gemini | ✓ five, after new and load c [ge16] | ✗ c | 4 methods, `_meta` keys c [ge17] | ✓ if declared · ✗ c [ge18] | ✓ · ✓ · ✓ c [ge19] |
| github-copilot-cli | ✓ with hints and skills n [co20] | ✓ since 1.0.81 n [co21] | `copilot-login`, terminal n [co22] | ? · ? | ✓ · ✓ · ✓ n [co23] |
| glm-acp-agent | ✓ from `.claude/` c [gl21] | ✓ after each turn c [gl22] | not needed r [gl23] | ◐ fs if declared · ✗ c [gl24] | ✓ · ✓ · ✗ fails session c [gl25] |
| grok-build | ✓ c [gr21] | ✓ c [gr22] | 4 agent methods c [gr23] | ✓ · ✓ if declared c [gr24] | ✓ · ✓ · ✓ c [gr25] |
| kilo | ✓ no input hint c [ki18] | ✗ titles in list only c [ki19] | `kilo-login`, no-op c [ki20] | ◐ write, undeclared · ✗ r [ki21] | ✓ · ✓ · ✓ c [ki22] |
| minimax-code | ✓ ten, answered locally c [mm21] | ✓ also outside turns c [mm22] | 1 terminal, if declared c [mm23] | ✗ · ✗ c [mm24] | ✓ · ✓ · ✓ c [mm25] |
| minion-code | ✗ c | ✗ c | 1 agent-run OAuth c [mi16] | ✗ · ✗ c [mi17] | ✗ · ✗ · ✗ ignored c [mi18] |
| nova | ✓ likely c [no16] | ✗ c [no17] | terminal method c [no18] | ✗ · ✗; own `file/write` c [no19] | ✓ · ✓ · ✓ c [no20] |
| pi-acp | ✓ pi's + built-ins c [pi15] | ◐ after `/name` only c [pi16] | 1 terminal, a no-op c [pi17] | ✗ · ✗ c [pi18] | ✗ · ✗ · ✗ ignored c [pi19] |
| qoder | ✓ after new, load c, n [qo20] | ? [qo21] | agent-run · env_var c, n [qo22] | fs if declared · ? c [qo23] | ✓ · ✓ · ✓ c, n [qo24] |
| qwen-code | ✓ with skills c [qw14] | ✓ c [qw15] | terminal by `_meta` c [qw16] | ✓ if declared · ✗ c [qw17] | ✓ · ✓ · ✓ c [qw18] |
| sigit | ✓ c [si22] | ✓ c [si23] | optional, agent type c [si24] | ✓ · ✓ if declared c [si25] | ✓ · ✓ · ✗ ignored c [si26] |
| cursor | ✓ c | ✓ c | **needed** n, c [cu17] | ✗ · ✗ c | ✓ · ✓ · ✓ c |
| devin | ✓ n [dv21] | ? n [dv22] | ✓ n [dv23] | ? · ? | ✓ · ✓ · ✓ n [dv24] |
| fx | ◐ always `[]` c [fx21] | ✓ c [fx22] | ✗ `fx login` outside c [fx23] | ✗ · ✗ c [fx24] | ✓ · ✓ · ✓, + `acp` c [fx25] |
| goose | ✓ c | ✓ c [go22] | ◐ no-op `agent` method c [go23] | ✓ · ✓ when declared c [go24] | ✓ · ✓ · ✗ c [go25] |
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
| auggie | load, image, list c [au17] | `terminal-auth` only c [au15] |
| autohand | load, list, resume, fork, http… c [ah23] | fs, terminal, terminal-auth c [ah24] |
| bob | load, list, resume, http c [bo24] | `elicitation` only c [bo25] |
| claude-acp | load, image, sse, fork +13 c [cl26] | form, url, plan, AIR +10 c [cl27] |
| cline | load, image c [ci1] | none c [ci1] |
| codebuddy-code | load, image, embedded +5 c [cb24] | fs, terminal, form, `_meta` c [cb25] |
| codex-acp | load, image, http, fork +11 c [cx25] | form, url, plan, AIR +7 c [cx26] |
| deepagents | load, image, embedded c [da19] | fs, terminal (unused) c [da17] |
| dimcode | load, image, http, sse, list… c [dm26] | fs, terminal, form, `_meta.lody` c [dm27] |
| dirac | load, resume, close, delete… c [di26] | fs, terminal, form, auth c [di27] |
| factory-droid | load, list, resume, image c [dr25] | `elicitation`, `_meta` c [dr26] |
| fast-agent | load, image, embedded, http… c [fa21] | fs, terminal, `_meta` c [fa22] |
| gemini | load, prompt ×3, MCP ×2 c [ge20] | fs only c [ge18] |
| github-copilot-cli | ? load, prompt, MCP named n [co24] | ? n [co24] |
| glm-acp-agent | load, http, image, list, fork… c [gl26] | `fs` only c [gl27] |
| grok-build | load, list, resume, close c [gr26] | fs, terminal, own `_meta` c [gr27] |
| kilo | load, image, http, sse, list… c [ki1] | `_meta` terminal-auth only c [ki1] |
| minimax-code | load, http, sse, 4 session c [mm26] | auth, form, plan, `_meta` c [mm27] |
| minion-code | `streaming` only: defaults c [mi19] | none c [mi19] |
| nova | load, sse, list, fork… c [no21] | version, auth, delegation c [no22] |
| pi-acp | load, image, list, delete c [pi20] | `terminal-auth` only c [pi21] |
| qoder | load, list, prompt, MCP c [qo25] | `fs` c [qo26] |
| qwen-code | load, list, resume, prompt ×3 c [qw19] | fs, own `_meta` keys c [qw17] |
| sigit | load, audio, http, list, fork… c [si27] | fs, terminal, URL, boolean c [si28] |
| cursor | load, list, image c [cu18] | `subagents`, `_meta` c [cu18] |
| devin | ? n [dv25] | elicitation, rest ? n [dv26] |
| fx | load, list, resume, close c [fx26] | elicitation, notices, `_meta` c [fx27] |
| goose | load, list, delete, close c [go26] | fs, terminal, form, `_meta` c [go27] |
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
| auggie | history, terminal-auth, indexing | ext method, `_meta`, flag | none |
| autohand | terminal-auth, terminal `_meta` | `_meta`, env | none |
| bob | `bob/extensions`, `_bob/task/*`, `bob/mode` | `_meta`, flag, form | none |
| claude-acp | SDK options, AIR, usage +7 c [cl28] | `_meta`; AIR for most | steering, `nonExecutionKind` +2 |
| cline | `--thinking`, `provider` +2 c [ci24] | flag; config options | `provider`, read as the model |
| codebuddy-code | terminal, question +6 c [cb26] | `_meta` capability; C3 none | none |
| codex-acp | `/mcp`, `/status`, AIR +8 c [cx27] | none · `_meta` · AIR capability | steering, `_meta.codex`, MCP flag |
| deepagents | `input`/`output`, own statuses, flags | own keys, flags | none |
| dimcode | `_lody/*`, `_dimcode/*`, `_meta` | none, or `_meta.lody` capability | `_meta.lody.elicitation` |
| dirac | `dev.dirac/*`, providers, worktrees | call or `_meta` | none |
| factory-droid | `terminal_output`, `set_model`, … | `_meta`, `elicitation.url` | none |
| fast-agent | structuredOutput, metrics, parent id | `_meta`, flags | none |
| gemini | `_meta.quota`, `[MODE_UPDATE]`, auth | `_meta`; parse text | none |
| github-copilot-cli | `github.com/copilot/sessionEvent` | ?; launch flags | none |
| glm-acp-agent | none; off-spec behaviour only | none | none |
| grok-build | `x.ai/*`: questions, plan, 300+ more | none: questions on by default | none |
| kilo | terminal-auth, fs write +2 c [ki23] | `_meta`, env | none |
| minimax-code | `mcode/*`, `permissionMode` +3 c [mm28] | `_meta` capability; methods | `permissionMode` in `/config` |
| minion-code | `agent-auth`, skip flag, stubs c [mi20] | none; flag | none |
| nova | `_meta.compass`, peers, delegation… | `_meta`, version 2, methods | none |
| pi-acp | `terminal_*`, `piAcp` +4 c [pi22] | none; env, `_meta` | `terminal_output`, misread |
| qoder | `_meta.quota`, hidden opts +5 c [qo27] | none; `_meta`, env | none |
| qwen-code | `_qwencode/*` turns, `qwen/*` [qw20] | none for turns; call | none |
| sigit | `_meta.sigit`, out-of-band commands | none | none |
| cursor | `cursor/*` methods, picker `_meta` | answer methods, `_meta` | none |
| devin | tool _meta, timestamps n [dv27] | ? | none |
| fx | `_meta.fx.steer` and 11 more c [fx28] | `_meta`, flag, capability | none |
| goose | `_goose/unstable/*`, `_meta` c [go28] | methods, capability `_meta` | none |
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
  (`src/acp/connection.ts:356-360`). It also calls `session/set_model`,
  which version 1 has not made stable (`src/acp/connection.ts:60`). Unused:
  anything of a later protocol version.
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

Read at `@augmentcode/auggie` 0.36.0, the ACP Registry's pin, unchanged since
CHD-432. The package is one minified bundle with its own copy of the ACP
SDK. Its `LICENSE.md` is proprietary: §2 says "The CLI must not be
reverse-engineered, decompiled, or modified", and use is tied to an Augment
subscription. Under the owner's rule of 2026-10-18, recorded on CHD-433, the
bundle was read as plain text only for the ACP contract: the messages,
fields and capabilities auggie sends and accepts, and what it does on the
wire. Nothing was deobfuscated, nothing internal is named or cited, and no
copy is kept. Where Augment's docs or the changelog of
https://github.com/augmentcode/auggie state a fact, they are cited first; the
rest is from auggie 0.36.0. The registry sets `AUGMENT_DISABLE_AUTO_UPDATE=1`,
which stops self-update.

**Footnotes.**

- **au1.** auggie 0.36.0 carries `@agentclientprotocol/sdk` 0.14.1, a
  pre-1.0 release; its methods and schema match that release and no other
  published one.
- **au2.** v1 plus `session/set_model` and `session/list`, and two
  extension methods: `augment/session/history` ("ACP integrations can now
  access CLI session history", `CHANGELOG.md:181`) and IDE inline-completion
  methods. No v2.
- **au3.** When not signed in, `session/new` fails `authRequired` with
  "Auggie does not currently support authenticating over ACP. Please run
  `auggie login` from your terminal".
- **au4.** Load replays user and agent text, thought summaries and tool
  calls, not plans. `session/list` answers `title`, `cwd`, `updatedAt` and
  `_meta.messageCount`, filtered by cwd; paging was not established.
- **au5.** Legacy `models`, which may be null, and `session/set_model`.
  Legacy modes `default` and `ask`; `ask` answers read-only. No config
  options and no effort over ACP.
- **au6.** Only `text`, `image` and `resource_link` blocks are read; any
  other block adds nothing to the prompt, with no error. A leading `/name`
  runs a custom command. An image without data is dropped. A
  `resource_link` counts only as a local path from a `file://` URI: an image
  file is attached as an image, some documents as files, the rest becomes
  the text `@<path>`. The changelog names "file mentions and image support"
  for ACP (`CHANGELOG.md:638`).
- **au7.** Kinds `read`, `edit`, `delete`, `execute`, `search`, `fetch` and
  `other`, which covers subagents and unmapped tools. rawInput is the parsed
  tool input, none for a subagent. Shell, file-view and MCP results arrive
  only in `rawOutput.output`, with empty `content`; edits send diffs and some
  searches text. No terminal content. Read and edit tools carry `locations`
  (`path`, with `line` for a ranged read), on results too.
- **au8.** `tool_call` goes out with no status, so pending, then one
  `tool_call_update` with `completed` or `failed`; never `in_progress`.
- **au9.** A tool permission offers `allow_once` "Allow" and `reject_once`
  "Deny"; an error answer counts as denied. Right after `session/new`, with
  no turn running and no `tool_call`, it asks a workspace-indexing
  permission with four options: always or session, enable or disable. The
  first prompt waits on the answer. `--allow-indexing` skips it
  (`CHANGELOG.md:622`).
- **au10.** Its task list goes out as a whole `plan`: depth sets priority,
  cancelled tasks are dropped.
- **au11.** `session/cancel` interrupts the whole turn, subagents with it.
  A second `session/prompt` mid-turn runs a second loop over the same
  session at once; no `_meta.steering`.
- **au12.** A subagent is one `tool_call` titled with its name and task,
  closed with its final text; its own calls are not sent and it has no
  session id.
- **au13.** `available_commands_update` from `.augment/commands/`, sent
  before the first prompt.
- **au14.** No `session_info_update` is sent; titles appear only in
  `session/list`.
- **au15.** Terminal login for ACP is in the changelog (`CHANGELOG.md:610`).
  `authMethods` is empty unless the client sends
  `clientCapabilities._meta["terminal-auth"]: true`; then it lists
  `auggie-login` "Log in with Auggie", with no `type`, whose
  `_meta["terminal-auth"]` runs `auggie login`. `authenticate` does nothing.
  That key is the only client capability read; auggie makes no `fs/*` or
  `terminal/*` call.
- **au16.** No `mcpCapabilities` are advertised. stdio servers are passed on
  with command, args and env; http and sse servers are passed on too, with
  their `type`, url and headers, and not refused. Whether they connect is
  not visible on the wire. The changelog fixed "MCP server initialization
  timing in ACP mode" (`CHANGELOG.md:306`).
- **au17.** `{loadSession: true, promptCapabilities: {image: true},
  sessionCapabilities: {list: {}}}`, with `agentInfo` `{name: "auggie",
  title: "Auggie Agent"}`.

**Custom.**

- `_meta["terminal-auth"]`: gives an `auggie-login` method. A client must
  declare the key and run the command in a terminal; otherwise there is no
  method and `session/new` fails `authRequired`.
- Workspace-indexing permission: gives consent to upload the workspace to
  Augment's index. A client must answer a permission outside any turn,
  naming no known call; the first prompt waits until it does. A
  skip-permissions client agrees to indexing. `--allow-indexing` answers it
  at launch.
- `augment/session/history`: the history as plain text. A client must call
  the method; private coupling.
- IDE inline-completion methods: for editors only.
- `_meta.messageCount` in `session/list`: free to read.

**In chord.** chord asks for nothing auggie offers in `_meta`, so it gets no
login method; without `auggie login` beforehand every start fails
`authRequired`. The indexing permission comes before any turn, so chord
rejects it unseen with `reject_once`, which is the session-disable option:
the workspace is not indexed for that session, and the person is not told.
The first prompt does not hang. An `@` mention goes out as a
`resource_link`, which auggie reads only as a local `file://` path. Shell,
file-view and MCP results are only in `rawOutput`, which chord keeps but
never draws, and a running call is a grey `Waiting…` until it ends.
Subagents read as one call. No usage arrives, so chord estimates nothing.
No title arrives, so none is lost. chord reopens with `session/load`, as
auggie has no resume, and never calls `session/list`. chord's own MCP server
is left out, since auggie advertises no `mcpCapabilities.http`; the person's
stdio, http and sse servers all reach auggie. A mid-turn prompt is queued,
which keeps a second loop from starting.

**Sources.**

- `@augmentcode/auggie` 0.36.0, npm; its `LICENSE.md` and its ACP contract.
- https://docs.augmentcode.com/cli/acp and
  https://docs.augmentcode.com/cli/acp/clients.
- https://github.com/augmentcode/auggie, `CHANGELOG.md`.
- CHD-432, `docs/design/registry-2026-10-17.md`, auggie 0.36.0.

#### autohand

- Name: Autohand Code
- Pinned: `@autohandai/autohand-acp` 0.2.1
- Run as: `npx -y @autohandai/autohand-acp@0.2.1`
- Source: <https://github.com/autohandai/autohand-acp>

Read at `@autohandai/autohand-acp` 0.2.1, the ACP Registry's pin, unchanged
since CHD-432: the npm package, plain `tsc` output, Apache-2.0, with nothing
restricting reading. Paths are in that package; `dist/acp-agent.js` unless
named. It is an adapter: each `session/prompt` spawns the separate `autohand`
CLI (`autohand-cli`, not read), which must be installed globally beside the
npx package. The registry launches it with no arguments and no environment,
so it never asks permission (ah14) and its telemetry stays on (Custom).

**Footnotes.**

- **ah1.** `initialize` answers `params.protocolVersion ?? 1` (`:271`), so 1
  to chord; it echoes whatever a client asks for, on a v1 SDK.
- **ah2.** `@agentclientprotocol/sdk` 0.12.0, exact pin (`package.json`).
- **ah3.** v1 plus the SDK's unstable handlers `unstable_setSessionModel`
  (`:444`), `unstable_setSessionConfigOption` (`:455`),
  `unstable_forkSession` (`:481`), `unstable_resumeSession` (`:557`) and
  `unstable_listSessions` (`:1115`). No v2.
- **ah4.** `session/new` and prompts throw `authRequired` with "run
  `autohand login`" when the CLI is not signed in (CHD-432).
- **ah5.** Load replays user and assistant text only and answers `{}`
  (CHD-432).
- **ah6.** Each turn is a fresh CLI run. Resume needs an id in the CLI's
  index, which chord's ids are not; fork copies in-memory sessions of this
  process (CHD-432 ah3). `session/list` lists the CLI's per-turn sessions,
  titled `Session <8 chars>`, filtered by cwd, never paged (`:1115-1134`).
- **ah7.** Six legacy modes with `current_mode_update`; legacy `models`,
  where `set_model` stores the id for the next CLI run; nine select options
  (thinking level, auto-commit, history, auto-mode and its caps,
  temperature, streaming), answered but never sent as `config_option_update`
  (CHD-432).
- **ah8.** `thinking_level` carries no `thought_level` category (CHD-432 ah2).
- **ah9.** `promptToText` turns an image into the lines `[Image 1]`,
  `Type: …`, `Size: ~N KB`; the data never reaches the CLI (`:2325-2343`,
  "Future enhancement" at `:766-768`). Audio is advertised only under
  `AUTOHAND_SUPPORTS_AUDIO` and becomes placeholder text.
- **ah10.** An embedded resource is pasted as `[resource: <uri>]` and its
  text. A `file:` `resource_link` is read through `fs/read_text_file` when
  the client declares it, else from disk by the adapter, then inlined the
  same way (`:2078-2124`, `:2187`).
- **ah11.** Kinds `read`, `search`, `edit`, `move`, `delete`, `execute`,
  `think`, `other` from a tool-name map (`:121-159`). `rawInput` is the
  call's args, `rawOutput` its result text. Locations are
  `[{path: args.path}]` as given, possibly relative (`:2909-2918`).
- **ah12.** Content is text only, no diff. To a client with `terminal`,
  `run_command` gets `terminal` content with an id that was never created,
  and output as `_meta.terminal_output` (`:1916-2004`); to one without, each
  update resends the whole output as text (CHD-432 ah5).
- **ah13.** `pending`, then `in_progress` only when output streams, then
  `completed` or `failed`; `failed` is guessed by a regex (`:1909-2070`).
- **ah14.** Asks only under `AUTOHAND_PERMISSION_MODE=external`, through a
  localhost permission server (`dist/permission-server.js:76-170`); the
  registry does not set it. Every request lacks `toolCall`, so chord's SDK
  refuses it and the CLI hears "denied" (CHD-432 ah4).
- **ah15.** `plan` from `todo_write` and `plan` tools (CHD-432).
- **ah16.** Cancel kills the CLI child; a prompt sent meanwhile is queued and
  runs next (CHD-432).
- **ah17.** No usage; the CLI's token line is scraped into reply text
  (CHD-432 ah1).
- **ah18.** 24 default commands, or a JSON list from the environment, after
  `session/new` (via `setImmediate`) and after load; some run in the adapter,
  the rest go to the CLI as text (`:65-90`, `:404-411`, `:1239`).
- **ah19.** Titles are made from the first message but never sent, being
  "not a valid ACP notification type in Zed" (`:622`, `:750`).
- **ah20.** `_meta["terminal-auth"]` methods `autohand-install` and
  `autohand-login` (`:236-266`, `:290-313`).
- **ah21.** `fs/read_text_file` only for links (ah10) and `terminal/*` only
  when declared; `fs.writeTextFile` is read but its only user,
  `delegatedWriteFile`, is never called (`:824`, `:1420`, `:2094-2110`,
  `:2212`).
- **ah22.** `parseMcpServers` keeps name, type and URL (for stdio only the
  command, no args or env) on the session, and nothing ever reads them or
  passes them to the CLI (`:2702-2717`).
- **ah23.** `{promptCapabilities: {embeddedContext: true, image: true,
  audio: <env> | undefined}, loadSession: true, mcpCapabilities: {http:
  true, sse: true}, sessionCapabilities: {list: {}, resume: {}, fork: {}}}`,
  `agentInfo._meta.cliVersion`, and top-level `_meta.{warning, installUrl}`
  when the CLI is missing (`:216-286`).
- **ah24.** `fs.readTextFile`, `fs.writeTextFile`, `terminal`,
  `_meta["terminal-auth"]` (`:298`, `:326`), and `clientInfo`, passed to the
  CLI as environment. Elicitation, plan and subagents are not read.

**Custom.**

- `_meta["terminal-auth"]` methods: a login and an install run in a
  terminal. A client must declare the key, run the command, then call
  `authenticate`. Without it every start fails `authRequired`.
- `_meta.terminal_info` and `_meta.terminal_output` on tool calls: live
  command output under a terminal id that does not exist. A client must
  declare `terminal` and read the keys.
- `AUTOHAND_PERMISSION_MODE=external`: approvals, selects and confirms as
  permissions without `toolCall`; text inputs are always denied. A client
  must set the variable and accept the off-spec shape.
- Telemetry to `https://api.autohand.ai/v1/telemetry`, on by default
  (`dist/telemetry.js:10-22`, `:146-200`; `:403`, `:1077`, `:1248`): a device
  id kept in the home directory, session start and end, model and
  slash-command names, OS and Node versions, all labelled
  `clientType: "zed"` whatever the client. A client stops it only with
  `AUTOHAND_TELEMETRY=false` or `0` in the agent's environment.
- Unprompted text: a "Hey <name>!" welcome after `session/new`
  (`:412-421`) and a feedback request after turns 5 to 10.
- `agentInfo._meta.cliVersion` and `_meta.{warning, installUrl}`: the CLI's
  version and an install hint. Free to read.
- History: turns share no memory unless `include_history` is on, which
  pastes the last 6 turns, up to 8000 characters, as text.

**In chord.** chord sends each @-mention as a `resource_link`; chord
declares no `fs`, so the adapter reads the file from disk itself and pastes
it in. A pasted image goes out because `image` is advertised, but the model
gets only `[Image 1]` and a size, and the person is not told. autohand drops
every MCP server: chord adds its own over http because `mcpCapabilities.http`
is true, and the person's servers go too, and none reach the CLI. No
permission ever reaches the person under the registry launch, and with the
variable set chord's SDK would refuse each request. Effort is not found,
having no category. Command output arrives as whole-output resends. No usage
arrives, so chord estimates nothing. chord reopens a recorded session with
`session/resume`, which the CLI's index does not know; it never calls
`session/list`. Without `autohand-cli` on PATH, `initialize` offers only an
install method and the first `session/new` fails. The welcome and feedback
lines show as agent text. chord does not see the telemetry.

**Sources.**

- `@autohandai/autohand-acp` 0.2.1, npm, and
  https://github.com/autohandai/autohand-acp.
- `@agentclientprotocol/sdk` 0.12.0, npm.
- CHD-432's reading, `docs/design/registry-2026-10-17.md` (ah1-ah5).

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
engineering the Program" (`dist/ibm-licence/license.txt:61`). Under the
owner's rule of 2026-10-18, recorded on CHD-433, the bundle was read as plain
text only for the ACP contract: the messages, fields and capabilities bob
sends and accepts, and how it behaves. Nothing was deobfuscated, and no copy
is kept. Cells marked `n` come from IBM's own `ACP.md` and `README.md`, which
are cited first; cells marked `c` state that contract as read in `@ibm/bob`
2.0.8. The read confirms CHD-432's bob notes B1 to B7 as wire facts, with
one correction under B6 (bo16).

**Footnotes.**

- **bo1.** The `initialize` answer carries `protocolVersion` 1 and
  `agentInfo` `{name: "bob-shell", title: "Bob", version: "2.0.8"}`.
- **bo2.** The bundled notices list no ACP library
  (`dist/ibm-licence/notices.txt:45-66`). The package carries
  `@agentclientprotocol/sdk` 1.3.0: its methods, schema and error messages
  match that release and no other published one.
- **bo3.** `ACP.md:60-62` (list, delete, resume, load), `:91` (`set_mode`),
  `:72` (no `set_model`), `:93-129` (`_bob/task/*`). On the wire bob answers
  initialize, authenticate, session new, load, resume, list, delete, close,
  set_mode, prompt and cancel, and sends `session/update`,
  `session/request_permission`, `elicitation/create` and `$/cancel_request`.
  No fork, `set_model`, `set_config_option` or v2.
- **bo4.** `ACP.md:25`: the first `session/new` fails `auth_required`
  without a login or key. Set-up refuses, in this order, an unknown
  `bob/mode` (-32602), a folder marked untrusted (-32600, naming `--trust`),
  no login (`authRequired`), and, for a client without forms, a licence not
  yet accepted (`ACP.md:44`, `:49`). Load and resume run the same set-up.
- **bo5.** `ACP.md:62`: resume "without replaying already-visible messages";
  load replays history, tool calls, diffs and the last plan. Replayed calls
  come as one `tool_call` already `completed` or `failed`.
- **bo6.** `ACP.md:60`: list, page through and delete sessions "from the
  shared Bob store", so a delete reaches bob's own UI too. Close is
  advertised and answered; fork is neither.
- **bo7.** `ACP.md:77-91`: `session/set_mode`, default from
  `session.defaultMode` (`agent`); changes come as `current_mode_update`.
- **bo8.** `ACP.md:72`: "Model selection (`session/set_model`) is not
  supported". No `configOptions` or `models` are sent and
  `session/set_config_option` is not answered, so there is no effort either.
- **bo9.** `ACP.md:65`: pasted images go to the model. Text goes as it is;
  an image without data becomes `[image: <uri>]`; audio becomes `[audio]`;
  an embedded text resource is inlined and a blob one becomes
  `[resource: <uri>]`; a `resource_link` becomes its title and URI as text.
  A prompt with neither text nor images is refused -32602.
- **bo10.** Kinds `read`, `edit`, `delete`, `execute`, `search`, `fetch` and
  `other`. `tool_call` carries title, kind, rawInput and `locations` from
  path-like arguments; the result carries `rawOutput {result}`, diffs or
  text, and the changed files as `locations`. Each command output chunk is a
  `tool_call_update` whose `content` replaces the previous chunk. `ACP.md:63`:
  edits stream as diffs; `ACP.md:73`: no client terminals.
- **bo11.** `pending`, then `in_progress` once approved, then `completed` or
  `failed`; a rejected permission gives `failed`. A cancelled permission gets
  no update, so its call stays `pending` for good.
- **bo12.** `ACP.md:53-56`: Allow once and Reject, plus Always allow when
  the command or tool is eligible for a task-scoped approval. Option ids
  `allow`, `allow_always` and `reject`; the request carries rawInput, kind
  and an edit's pending diff. No timeout. On cancel bob withdraws the request
  with `$/cancel_request` and treats it as cancelled.
- **bo13.** Questions come as a form with `properties.answer` and an
  optional `properties.other`; the licence comes as a form too. URL mode is
  never sent.
- **bo14.** `ACP.md:64`: the todo list streams as ACP plan updates.
- **bo15.** `session/cancel` stops the prompt and the session's task,
  withdraws a pending permission, and the prompt answers
  `stopReason: "cancelled"`. What it does to a running subagent is not
  visible on the wire.
- **bo16.** A concurrent `session/prompt` is refused -32600 "Session is
  already running a prompt", and so are load and resume of that session.
  After `session/cancel`, the next prompt waits for the cancelled turn to end
  and is not refused. No steering.
- **bo17.** Events of tasks other than the session's own are not sent, so a
  subagent is only its parent's tool call. `ACP.md:36`:
  `--disable-subagents`.
- **bo18.** No usage, `usage_update` or cost is sent.
- **bo19.** `available_commands_update` is sent; the command list was not
  read.
- **bo20.** `ACP.md:61`: title and last-activity updates after successful
  turns, as `session_info_update` with `title` and `updatedAt`.
- **bo21.** `ACP.md:24-26`, `README.md:30-38`: SSO in a browser, or
  `BOB_API_KEY`. `authMethods` holds one method, `sso` "Log in with SSO",
  with no `type`, so the default agent type. No env-var or terminal method.
- **bo22.** `ACP.md:73`: "ACP client terminals are not used". bob makes no
  `fs/*` or `terminal/*` call.
- **bo23.** `ACP.md:66`: stdio and Streamable HTTP; `:71`: "Legacy
  two-endpoint HTTP+SSE MCP servers supplied by an ACP client are rejected".
  One sse entry, or one `acp`-transport entry, fails the whole
  `session/new`, load or resume; bob does not drop that server.
- **bo24.** `{_meta: {"bob/extensions": {version: 1}}, loadSession: true,
  sessionCapabilities: {list, delete, resume, close}, promptCapabilities:
  {embeddedContext: true, image: true}, mcpCapabilities: {http: true}}`, as
  `ACP.md:95` states for the `_meta` key.
- **bo25.** It reads only `clientCapabilities.elicitation`, which decides
  how the licence is asked (`ACP.md:43-44`).

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
  without an SSO login from a terminal `session/new` fails `authRequired` and
  chord shows a bare start failure.
- chord passes only `acp`: no `--trust`, so a folder marked untrusted is
  refused. The licence form goes through chord's form path; `-p` declines it,
  and bob asks again on every run.
- chord resumes when it has its own record, else loads; both fit. It never
  calls `session/list`, fork, delete or close, and sends no `bob/mode`.
- chord's own http MCP server reaches bob. The person's servers go out
  unfiltered, so one sse server in settings or `.mcp.json` stops bob from
  starting in chord.
- Titles are dropped. A running command shows only its latest chunk; a call
  whose permission was cancelled stays `pending`; a subagent is one tool call;
  there is no usage, so no meter and no estimate. A mid-turn prompt is queued
  until the turn ends, which fits bob's refusal of a concurrent one.

**Sources.**

- `@ibm/bob` 2.0.8 on npm: `ACP.md`, `README.md`,
  `dist/ibm-licence/license.txt` and `notices.txt`, and its ACP contract.
- CHD-432, `docs/design/registry-2026-10-17.md`, bob 2.0.8.

#### claude-acp

- Name: Claude Agent
- Pinned: `@agentclientprotocol/claude-agent-acp` 0.93.0
- Run as: `npx -y @agentclientprotocol/claude-agent-acp@0.93.0`
- Source: <https://github.com/agentclientprotocol/claude-agent-acp>

`@agentclientprotocol/claude-agent-acp` 0.93.0, the registry pin, read from
the npm package's `dist/` (plain `tsc` output) and the repository at tag
`v0.93.0` for `README.md` and `docs/`. Paths are relative to the package root
(`dist/…`) or the repository root (`docs/…`). The adapter is Apache-2.0, no
limits on reading. It drives `@anthropic-ai/claude-agent-sdk` 0.3.300 under
Anthropic's terms, which spawns the Claude Code CLI; neither was read, only
the adapter's calls into them. Several cells correct CHD-432
([`design/registry-2026-10-17.md`](design/registry-2026-10-17.md)): its own
usage and session titles reach every client, and its `/mcp` is hidden by
chord's.

**Footnotes.**

- **cl1.** `dist/acp-agent.js:1413` answers `protocolVersion: 1` whatever is
  asked. With `CLAUDE_AGENT_ACP_EXPERIMENTAL_V2=1` a router answers 2 to a
  client asking 2 or more (`dist/index.js:81-83`, `dist/serve.js:19-42`).
- **cl2.** `package.json:68` pins `@agentclientprotocol/sdk` 1.9.0; chord
  runs 1.8.0.
- **cl3.** The handler list `dist/acp-agent.js:10420-10447`: v1 methods plus
  `session/fork`, `providers/*`, `logout`, the subagents RFD, `notice`,
  `plan_update`, and own `_session/steering`, `_session/async_task/stop`,
  `_session/goal`, `_session/list/*`, `_session/rename·archive·unarchive`,
  `_auth/status_update`, `_claude/sdkMessage`. There is no
  `session/set_model`; models are only the `model` config option.
- **cl4.** `session/new` takes `additionalDirectories`, `systemPrompt` and
  many `_meta` keys (Custom), and answers modes and config options, no
  `models` (`dist/acp-agent.js:8290-8512`).
- **cl5.** Load replays the history, subagents under their live ids; resume
  is offered. From CHD-432 (C16).
- **cl6.** Pages of up to 1000 with `nextCursor` and a cwd filter
  (`docs/air-extensions.md:74-77`).
- **cl7.** The whole session, or up to one message given in
  `_meta.jetbrains.air.fork` (`dist/fork-session.js:6-24`), see Custom.
- **cl8.** For a client that is not AIR, delete is a real delete; close of an
  unloaded session answers `{}` (`docs/air-extensions.md:1468-1478`).
- **cl9.** `default`, `acceptEdits`, `plan`, `auto` when the model has it,
  `bypassPermissions` unless barred (`docs/air-extensions.md:688-697`).
- **cl10.** `mode`, `model`, `effort` (category `thought_level`), `fast`
  (category `model_config`, a select unless booleans are declared) and
  `agent` when the person has agents (`dist/acp-agent.js:9446-9582`,
  `dist/session-effort.js:91`).
- **cl11.** `dist/acp-agent.js:9680-9745`: audio is dropped; a resource keeps
  its text as a `<context ref>` block and drops a blob; a `resource_link`
  becomes the text `[@name](file://…)` for the model to read itself.
- **cl12.** `docs/air-extensions.md:297-331` (the column for clients that
  are not AIR). Kinds `execute`, `read`, `edit`, `search`, `fetch`, `think`,
  `switch_mode`, `other`. Terminal content goes only to a client declaring
  `_meta.terminal_output`; chord declares `terminal_output_delta` and gets a
  command's output once, at the end.
- **cl13.** A Bash call stays `pending` until done; an unfinished call ends
  `failed` with a reason line (CHD-432 C6, cl6).
- **cl14.** `allow_once`, `allow_always`, `reject_once`, never
  `reject_always`. A cancelled outcome or a signal abort stops the tool use;
  the request is raced against the tool's signal, with no timeout of its own
  (`docs/air-extensions.md:621-646,711-722`).
- **cl15.** AskUserQuestion, MCP form elicitation and the refusal-fallback
  dialog as forms; MCP URL elicitation and MCP OAuth as URLs
  (`dist/acp-agent.js:8358-8370,8487-8503,1063-1150`). Without `form`,
  AskUserQuestion is off.
- **cl16.** Entries from TodoWrite and Task*, and a markdown `plan_update` of
  an approved plan to a client declaring `plan` (CHD-432 cl5, C8).
- **cl17.** The turn and its foreground subagents stop; background subagents
  and commands keep running (`README.md`, "Subagent sessions").
- **cl18.** `dist/acp-agent.js:2600-2636`: answers `injected`,
  `startedNewTurn`, and `promptRequired` when idle and asked so. A
  concurrent `session/prompt` is queued (`promptQueueing`).
- **cl19.** RFD `subagent_update` and `session_message` to a client
  declaring `subagents`; a cancel on a child id stops that child (CHD-432
  C1, C15).
- **cl20.** `usage_update` used and size; cost (`total_cost_usd`) only at
  the turn's end (`dist/acp-agent.js:5003-5011`); `PromptResponse.usage`.
  Its own usage `_meta` comes too, see Custom.
- **cl21.** Claude Code's commands and skills minus `clear`, `cost`,
  `keybindings-help`, `login`, `logout`, `output-style:new`,
  `release-notes`, `todos`; MCP prompts as `mcp:<server>:<cmd>`; plus the
  adapter's `/mcp` and `/remote-control` (`dist/acp-agent.js:9604-9662`).
- **cl22.** A title generated once per session through the CLI's
  `generate_session_title`, a model call, else the stored custom title, as
  `session_info_update` to every client (`dist/session-titles.js:136-175`).
  CHD-432's "Session titles —" for claude is wrong.
- **cl23.** Terminal login methods only to a client declaring `auth.terminal`
  or `_meta["terminal-auth"]`, gateway only with `auth._meta.gateway`;
  chord declares none and gets `authMethods: []`
  (`dist/acp-agent.js:1305-1400`).
- **cl24.** `readTextFile` and `writeTextFile` have no caller in `dist/`;
  Claude Code's own tools touch the disk.
- **cl25.** All three kept with headers (`dist/acp-agent.js:8290-8312`); a
  server that needs OAuth gets a URL elicitation at startup.
- **cl26.** `dist/acp-agent.js:1396-1470`: `loadSession`, image and embedded
  context, MCP http and sse, `sessionCapabilities` list, resume, fork,
  close, delete, `additionalDirectories`, `systemPrompt`;
  `_meta.steering.supported`, `promptQueueing`, `authStatus`.
  `subagents` only to AIR.
- **cl27.** `elicitation` form and URL, `plan`, `session.compaction`,
  `session.notices`, boolean config options, `subagents`, `auth.terminal`,
  the gateway, and the `_meta` keys `terminal-auth`, `terminal_output`,
  `terminal_output_delta`, `subagent-transcript`, `jetbrains.air`. Not
  `fs` or `terminal`.
- **cl28.** Ten, each a bullet under Custom below.

**Custom.**

- `_meta.claudeCode.options` on `session/new` and again on load or resume:
  any Agent SDK option (`maxBudgetUsd`, `maxTurns`, `allowedTools`,
  `settings`, `promptSuggestions`…). Costs coupling to Anthropic's option
  names; a typo is ignored, and the adapter overrides `cwd`, `mcpServers`,
  `permissionMode`, `hooks` (`dist/acp-agent.js:8462-8512`).
- Prompt suggestions: one predicted next prompt per turn in
  `session_info_update._meta.promptSuggestions`, published only to an AIR
  client. They are requested for every client, so chord pays for one each
  turn it never sees. `_meta.claudeCode.options.promptSuggestions: false` on
  `session/new` turns them off (`dist/acp-agent.js:8462-8468,2500-2525`).
- `/remote-control [name|off]`: the session can also be driven from
  claude.ai or the mobile app. A plain prompt; chord passes it through.
- Instructions: the RFD field `systemPrompt`, `_meta.systemPrompt`, and
  `_meta.jetbrains.air.customInstructions`, read with no AIR declaration
  (`dist/acp-agent.js:8314-8337`).
- Usage and account `_meta`, to every client: `PromptResponse._meta.quota`
  per model, `usage_update._meta["_claude/model"]`, `_claude/origin`,
  `_claude/rateLimit` (the account's rate-limit window), and the
  `_auth/status_update` notification (`dist/acp-agent.js:9014-9020,
  2925-2937,5960-5972`). CHD-432's "Own usage or cost ✗" for claude is
  wrong.
- Its own `/mcp`: server status, reconnect, enable, disable, OAuth by URL
  (`dist/mcp-command.js:1-40`). Same name as chord's `/mcp`, so a chord
  user cannot reach it.
- `_session/steering`, announced by `_meta.steering.supported`; off-spec,
  shared with codex.
- Fork point: `session/fork` with `_meta.jetbrains.air.fork {version: 1,
  messageId}` forks up to that message, with no AIR declaration
  (`dist/fork-session.js:6-24`). The key sits in AIR's namespace.
- AIR (`_meta.jetbrains.air` declared): async tasks with their own stop,
  `_session/goal`, `diffPatch`, `planFile`, `sessionFailure`, the session
  index and more (`docs/air-extensions.md`). Declaring AIR at all switches
  subagents to the earlier draft `subagent_spawned` shape and drops Edit's
  `old_string`/`new_string` and Write's `content` from `rawInput`; the
  update kinds are not in ACP's schema.
- `_meta.claudeCode.emitRawSDKMessages`: every SDK message as
  `_claude/sdkMessage`, in Claude Code's private wire format.

**In chord.** chord sends `session/new` with no `_meta`, so it pays for a
prompt suggestion every turn and a title call every session, and shows
neither (`session_info_update` is dropped). It sets model and effort through
the config options and never needs `session/set_model`, which 0.93.0 lacks;
the comment at `src/acp/connection.ts:58-61` that the adapter answers it is
stale. Fast mode shows in `/config` as an on/off select. It reads the RFD
subagents but never cancels one on its own id, though claude would honour
it. `_meta.quota`, `_claude/rateLimit` and `_auth/status_update` are
ignored. Warnings arrive as `**Warning:**` reply text, as chord does not
declare `session.notices`. chord's `/mcp` hides claude's, a second agent for
U8 beside codex. With `authMethods: []` and no `authenticate` call, login
stays outside chord. Fork, delete, close and list are never called.

**Sources.**

- `@agentclientprotocol/claude-agent-acp` 0.93.0 on npm;
  <https://github.com/agentclientprotocol/claude-agent-acp/tree/v0.93.0>,
  `README.md` and `docs/air-extensions.md`.
- CHD-432's notes in
  [`design/registry-2026-10-17.md`](design/registry-2026-10-17.md)
  (cl1–cl8, C1–C16).

#### cline

- Name: Cline
- Pinned: `cline` 3.0.73
- Run as: `npx -y cline@3.0.73 --acp`
- Source: <https://github.com/cline/cline>

Cline 3.0.73, the registry pin, read at tag `cli-v3.0.73` (c718573) of
<https://github.com/cline/cline> (Apache-2.0, no limits on reading). Paths
are relative to the repository root; `acp/` stands for `apps/cli/src/acp/`,
and the runtime behind it is `sdk/packages/core/` (`@cline/core` 0.0.95).
Cells marked `r` are CHD-432's reading of the same tag. The image cell
corrects CHD-432's: cline advertises images but drops them, and resource
links with them.

**Footnotes.**

- **ci1.** `acp/acpAgent.ts:130-152`: `initialize(_params)` never reads the
  request and answers `PROTOCOL_VERSION`, `loadSession: true`,
  `promptCapabilities {image: true, audio: false, embeddedContext: false}`,
  no `sessionCapabilities` or `mcpCapabilities`, and `authMethods` as
  `{id, name}` only.
- **ci2.** `apps/cli/package.json:71` (`^0.16.1`), `bun.lock:859` resolves
  0.16.1; transport `acp/index.ts:12-31`.
- **ci3.** `unstable_setSessionModel` at `acp/acpAgent.ts:438`; mode,
  config-option and session-info updates at `acp/session-updates.ts:162-193`.
  No `extMethod`, `extNotification` or `_meta` in `acp/`.
- **ci4.** `session/new` and `session/load` throw `auth_required` without
  `CLINE_API_KEY` or a stored login (`acp/acpAgent.ts:154-168`, `:639-650`).
- **ci5.** CHD-432: `session/load` replays the stored conversation
  (`acp/acpAgent.ts:249-326`); provider and model come back as defaults
  (`:262-286`). No resume handler.
- **ci6.** The agent's methods (`acp/acpAgent.ts:130-594`) are `initialize`,
  `newSession`, `loadSession`, `prompt`, `cancel`, `setSessionMode`,
  `unstable_setSessionModel`, `setSessionConfigOption`, `authenticate` and
  `shutdown`: no list, fork, close or delete.
- **ci7.** CHD-432: `plan` and `act` as `modes` and as a `mode` option, with
  `current_mode_update` (`acp/acpAgent.ts:170-184`, `:421-436`).
- **ci8.** `buildAllConfigOptions` (`acp/acpAgent.ts:925-941`) puts
  `provider` first, a select of category `model` over the three login
  providers (`:862-881`); then `model`, also category `model` (`:883-899`),
  `mode`, auto-approve (`boolean`, `acp/auto-approve.ts:9`) and, for Cline
  accounts, organization (category `account`, `acp/organizations.ts:92-97`).
  `models` is in the `session/new` answer too (`acp/acpAgent.ts:226-247`).
  `config_option_update` follows each set (`:572`).
- **ci9.** `--thinking <none|low|medium|high|xhigh>`
  (`apps/cli/src/commands/program.ts:40-41`, `apps/cli/src/main.ts:804-815`);
  the registry passes only `--acp`.
- **ci10.** `extractTextFromContentBlocks` keeps `text` blocks only
  (`acp/acpAgent.ts:943-948`), so images and resource links are dropped
  though `image: true` is advertised; a prompt with no text answers
  `end_turn` at once (`:333-336`).
- **ci11.** Kinds `read search edit delete move execute fetch think other`
  (`acp/tool-utils.ts:4-25`). `tool_call` with `rawInput`
  (`acp/session-updates.ts:66-80`); the end carries `rawOutput` only
  (`:137-147`). No `content` or `locations` is ever set; generated images go
  out as message chunks (`:110-136`).
- **ci12.** `pending`, then `in_progress` only after the person approves
  (`acp/permissions.ts:105-130`), then `completed` or `failed`; a rejected
  call goes `failed`.
- **ci13.** `acp/permissions.ts:15-31`; `allow_always` acts as once,
  `cancelled` and a failed request reject (`:57-90`, `:114-118`). No timeout.
- **ci14.** CHD-432: core's `ask_question` tool needs an executor the ACP
  layer never passes
  (`sdk/packages/core/src/extensions/tools/definitions.ts:970-972`).
- **ci15.** CHD-432: no `plan` update (`acp/session-updates.ts:26-152`).
- **ci16.** CHD-432: a second `session/prompt` is queued and answered
  `end_turn` at once, then runs with no prompt open; it also clears the
  abort controller, so a later cancel stops nothing
  (`acp/acpAgent.ts:339-402`,
  `sdk/packages/core/src/runtime/host/local-runtime-host.ts:1142-1190`).
- **ci17.** CHD-432: `spawn_agent` is a `think` call; the child's events land
  in the parent session unmarked, with no id of their own
  (`sdk/packages/core/src/runtime/host/local/spawn-tool.ts:50`).
- **ci18.** CHD-432: usage events are dropped
  (`acp/session-updates.ts:36-39`); the answer is `{stopReason}` only
  (`acp/acpAgent.ts:402`).
- **ci19.** No `available_commands_update` in `apps/cli/src/`.
- **ci20.** `session_info_update` after every turn with `updatedAt` only
  (`acp/acpAgent.ts:387-389`); no caller passes a `title`.
- **ci21.** `cline`, `cline-pass`, `openai-codex`, with no `type`, so ACP's
  default `agent` (`acp/auth.ts:12-16`); `authenticate` opens a browser OAuth
  from the agent process (`acp/acpAgent.ts:576-592`, `acp/auth.ts:32-106`).
- **ci22.** The only request to the client is `session/request_permission`
  (`acp/permissions.ts:115`).
- **ci23.** `mcpServers` is stored, never read (`acp/acpAgent.ts:81`,
  `:211`, `:276`); the CLI's own `cline_mcp_settings.json` applies.
- **ci24.** Four, each a bullet under Custom below.

**Custom.**

- `--thinking <level>`: effort for every session of the process. A client
  adds the flag to the command; a change needs a restart.
- `provider` select with category `model`: switches between Cline,
  ClinePass, a ChatGPT subscription and others. A client must tell it from
  the model; two selects share the category.
- Auto-approve, a `boolean` option: skips every permission request. A
  client must draw a boolean option; once set, nothing is asked.
- Organization select, category `account`: personal or an organization for
  Cline billing.

**In chord.** `/model` lists providers: chord takes the first select of
category `model` or id `model` (`src/session/models.ts:72-82`) and prefers it
over the `models` field (`:24-36`), so it shows and sets `provider`, and the
status line names the provider. The real `model` option is left out of
`/config`, which drops category and id `model`
(`src/session/config.ts:28-40`, `:60-62`). So the model cannot be chosen in
chord. Pasted images vanish, and an image-only prompt ends at once with
nothing said; @-mentions survive only as the path in the text. Command
output arrives only in `rawOutput`, which chord does not draw. Without a
login or `CLINE_API_KEY` the start fails with `auth_required`, as chord never
calls `authenticate`. chord's MCP server is not offered, and `mcpServers`
would be ignored. chord queues its own mid-turn prompts, so the
queued-prompt path is reached only by a second client. Ignored: the
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

`@tencent-ai/codebuddy-code` 2.168.2, the registry pin, dated 2026-10-16 in
its `CHANGELOG.md:10`, read from the npm package. Under `--acp`,
`bin/codebuddy` loads `dist/codebuddy-headless.js` (`bin/codebuddy:186-189`),
a minified, not obfuscated bundle; `H39:28046` below means line 39, column
28046 of that file, and `types/` means `dist-server/types/node/acp/`, the
authors' own declarations. `LICENSE.txt` is MIT, so no reading limit
applies; nothing was decoded or run. The entry is the one agent here whose
successful shell output never leaves `rawOutput`, and it starts model turns
of its own when a background task ends.

**Footnotes.**

- **cb1.** `initialize` answers the bundled SDK's `PROTOCOL_VERSION`, 1
  (`H39:28046`, `H4585:53022`).
- **cb2.** `package.json` pins `@agentclientprotocol/sdk` 1.7.0 exactly;
  `CHANGELOG.md:196` (2.164.0). stdio by default, `--acp-transport
  streamable-http` the other choice (`H269:12563`).
- **cb3.** The agent has `session/resume` (unstable) and `session/set_model`
  (`H39:43746`, `H41:24535`); a search finds no list, fork, close or delete
  handler in the ACP agent. Fork exists only as a Mod-page extension.
- **cb4.** `session/new` returns `models`, `modes` and `configOptions`
  (`H39:44954`); `_meta["codebuddy.ai/continue"]` continues the last session.
- **cb5.** `loadSession: true`; history is replayed between
  `session_info_update` markers `_meta["codebuddy.ai/historyReplay"]`
  (`H39:44954`, `H52:58524`).
- **cb6.** `session/resume` is served (`H39:43746`), but the answer has no
  `sessionCapabilities`.
- **cb7.** `getConfigOptions` (`H39:19710`): modes `default`, `acceptEdits`,
  `plan`, `auto`, `dontAsk`, `bypassPermissions`, `fullAccess`; selects
  `mode`, `model`, `thought_level`, `context_window`, `sandbox`, `agent`;
  `session/set_mode` and `set_model` work too.
- **cb8.** `promptToUserMessage` (`H3226:10873`) has cases for text, image,
  `resource` with text (a blob is dropped) and `resource_link` (the model
  gets the link); no audio case.
- **cb9.** Kinds `read`, `edit`, `execute`, `fetch`, `search`, `think`,
  `other`, with `rawInput` and `locations` (`H3226:4650`).
- **cb10.** `H3224:34057`: a successful Bash or PowerShell result carries no
  `content`, only `rawOutput`; a failed one gets its output as a code block.
  While it runs, a 1 s timer sends `in_progress` updates with `rawOutput`
  only (`H2704:4910`, `H2667:589`). A backgrounded call ends with a
  `terminal` block, opt-in or not.
- **cb11.** CHD-432's note cb3: Code Mode approvals offer Allow and Reject.
- **cb12.** How a `cancelled` answer reads was not traced. A sandbox approval
  that times out ends the turn with cancel reason `sandbox_approval_timeout`
  (`H4028:4429`).
- **cb13.** Forms need `elicitation.form` (`H479:4502`): A2A approvals,
  WeixinPay cards, MCP-forwarded requests and `AskUserForStructuredInput`,
  which is off unless `CODEBUDDY_ENABLE_ASK_USER_FOR_STRUCTURED_INPUT` is
  set (`H2904:58247`). No URL mode.
- **cb14.** `TodoWrite` becomes a `plan` update (`H3224:33960`).
- **cb15.** `session/cancel` aborts the running turn and reads
  `_meta["codebuddy.ai/cancelReason"]` (`H41:24535`, `H46:47984`); whether
  it also stops background tasks was not traced.
- **cb16.** No `_session/steering`; prompts are queued (`H46:79285`).
- **cb17.** CHD-432's cb1; subagent calls stay in the parent session with
  `_meta["codebuddy.ai/parentToolCallId"]` (`H3224:33960`). No stop per
  subagent.
- **cb18.** `usage_update` with `_meta["codebuddy.ai/usageByCategory"]`,
  whose parts sum to `used` (`H52:64628`, `types/acp-protocol.d.ts:1005`);
  no usage in the answer and no cost, as CHD-432 found.
- **cb19.** Sent on new, load and resume, and when settings change
  (`H39:25718`, `H39:10483`).
- **cb20.** `session_info_update` with `title` after a turn and on replay
  (`H46:65616`).
- **cb21.** `iOA`, `external`, `internal`, `selfhosted`, none with a `type`,
  so the agent runs the login itself (`H39:27700-28046`).
- **cb22.** With `fs.*TextFile` declared its file tools go through `fs/*`;
  with `terminal` its Bash runs through `terminal/create` (`H44:27885`,
  `H44:30614`, `H44:31133`).
- **cb23.** `H3226:4650`: an entry without `type` is stdio; `http` and `sse`
  pass; an entry with an explicit `type: "stdio"` is skipped.
- **cb24.** `H39:28046`: `promptCapabilities {image, embeddedContext}`,
  `mcpCapabilities {http, sse}`, `loadSession`, and five keys outside the
  spec (`delegateToolsSupport`, `mainAgentSupport`, `multitaskSupport`,
  `metaPromptSupport`, `processDefaults`). No `sessionCapabilities`.
- **cb25.** `H39:27171-27700` and the checks cited under Custom: `fs`,
  `terminal`, `elicitation.form`, `clientInfo.name`, and nine keys under
  `_meta["codebuddy.ai"]`. `elicitation.url`, `plan`, `subagents` and
  `_meta.terminal_output_delta` are not read.
- **cb26.** Eight, each a bullet under Custom below.

**Custom.**

- Terminal output, `_meta["codebuddy.ai"].terminalOutput` and
  `.terminalOutputChunk`: `terminal_update` (command, cwd, exit, end reason)
  and `terminal_output_chunk` (base64, 250 ms frames, cut at 2 MiB) for
  background commands only, cast from the draft v2 RFD onto v1
  (`H38:37681`, `H52:31339`, `types/acp-terminal-types.d.ts`). The client
  declares both keys; the authors plan to drop the gate with SDK v2.
- `_codebuddy.ai/session/cancelBackgroundTask {sessionId, terminalId}`:
  stops one background task, answering `cancelled`, `already_exited`,
  `not_found` or `cancel_failed`, and starts no model call (`H38:53717`,
  `CHANGELOG.md:116`). The `terminalId` comes on the call's `terminal` block.
- Unsolicited turns: when a background task ends and the session is idle,
  the agent sends `session_info_update` with
  `_meta["codebuddy.ai/unsolicitedTurn"] {requestId, reason:
  "background_drain"}`, runs a model turn with no `session/prompt` open, and
  ends it with a non-standard `session_end` update (`H82:16892`,
  `H46:65981`, `H38:40648`). `/goal` and cron use the same path. No opt-in;
  it spends model tokens nobody asked for.
- `_codebuddy.ai/question`: a request with multiple-choice questions, sent
  only to a client declaring `_meta["codebuddy.ai"].question: true`.
  Without it the `AskUserQuestion` tool is disabled (`H44:34209`,
  `H2614:101494`), so the model cannot ask.
- `_meta` on standard messages: tool names and failures, PromptResponse
  cancel and finish reasons, prompt suggestions (opt-in
  `promptSuggestion`), usage by category.
- Notifications to every client: `_codebuddy.ai/checkpoint`, `command`,
  `authUrl`, `fileDirectoryApproval/committed`; the SDK drops them.
- About 80 client-to-agent methods for its WorkBuddy and Mod pages, among
  them the unprefixed `session/set_agent` and `session/set_multitask`.
- Launch flags beyond `--acp`: `--permission-mode`, `--model`, `--effort`,
  `--agent`, `--sandbox*` and others (`H269`).

**In chord.** chord loads sessions with a full replay, since resume is not
advertised. Text, images and `@` links reach the model, the links as link
text. Modes, models, `thought_level` effort, plans, permissions, commands
and usage work. chord's own MCP server goes in over http, and its stdio
entries carry no `type`, so none is skipped. A successful foreground Bash
shows no output, live or final: chord keeps `rawOutput` but never draws it,
and codebuddy does not read `terminal_output_delta`. A backgrounded command
ends with an empty terminal block that chord filters out, so the call reads
as done with nothing said, and its end never arrives. The unsolicited turn
that follows is folded under the last turn on screen with no working line,
as CHD-426 describes for Claude; `session_end` falls to the reducer's
default. A permission request or form in that turn comes with no turn
running, so chord refuses it unseen (CHD-158). chord does not declare
`question`, so the model has no `AskUserQuestion` tool. Subagents show flat.
Ignored: titles, the custom `_meta`, the notifications and the extra
capability keys.

**Sources.**

- `@tencent-ai/codebuddy-code` 2.168.2 on npm, its `CHANGELOG.md` and
  shipped declarations; <https://www.codebuddy.cn/cli/>.
- CHD-432's notes in
  [`design/registry-2026-10-17.md`](design/registry-2026-10-17.md)
  (cb1–cb4).

#### codex-acp

- Name: Codex
- Pinned: `@agentclientprotocol/codex-acp` 2.2.2
- Run as: `npx -y @agentclientprotocol/codex-acp@2.2.2`
- Source: <https://github.com/agentclientprotocol/codex-acp>

`@agentclientprotocol/codex-acp` 2.2.2 (2026-10-10), the registry pin, read
in the repository at tag `v2.2.2` (commit `202e66e`) and checked against the
npm package's `dist/index.js` (esbuild, not minified). Paths are relative to
the repository root (`src/…`, `docs/…`) or the package root (`dist/…`).
Apache-2.0, no limits on reading. It runs `@openai/codex` 0.160.1 as an
app-server over JSON-RPC; Codex itself was not read, only the adapter's
calls into it. Several cells correct CHD-432
([`design/registry-2026-10-17.md`](design/registry-2026-10-17.md)): the
answer's `usage` is now the whole turn, titles and its own usage reach every
client, and its `/status` is hidden by chord's as well as its `/mcp`.

**Footnotes.**

- **cx1.** `src/CodexAcpServer.ts:484`, bundled as `PROTOCOL_VERSION = 1`
  (`dist/index.js:4241`); no v2 router. `CHANGELOG.md` 2.1.0 adds ACP v2 and
  reverts it in the same release.
- **cx2.** `package.json` `^1.5.0`, locked and bundled at 1.5.0.
- **cx3.** Methods `src/CodexAcpServer.ts:453-4004`, `extMethod` switch
  `:557-688`: v1 plus `session/fork`, `session/set_model`, `providers/*`,
  `logout`, draft subagents, `compaction_update`, `notice`, `plan_update`,
  and own `_session/steering`, `_session/async_task/stop`, `_session/goal`,
  `_codex/hooks/list·trust`, `_session/rename·archive·unarchive·list/*`,
  `authentication/status·logout`. The only requests to the client are
  `session/request_permission`, `elicitation/create` and
  `elicitation/complete`; no `fs/*` or `terminal/*`.
- **cx4.** `session/new` answers `models`, `modes` and config options, and
  marks every session root `trust_level: "trusted"` in the Codex config it
  passes (`src/CodexAcpClient.ts:940-998`, `:958-962`).
- **cx5.** Load replays the history, the child tree and async tasks
  (`docs/subagent-sessions.md`); resume survives an app-server restart
  (CHD-432 X4).
- **cx6.** Cwd filter and cursor over Codex threads from `cli`, `vscode`,
  `exec`, `appServer` and `unknown`, so the person's Codex CLI and VS Code
  sessions too (`src/CodexAcpClient.ts:1272-1320`). chord never calls it.
- **cx7.** The whole thread, or up to the turn holding the message given in
  `_meta.jetbrains.air.fork` (`src/SessionFork.ts:74-125`), see Custom.
- **cx8.** For a client that is not AIR, `session/delete` archives the
  thread (`thread/archive`), it does not delete it
  (`src/CodexAcpServer.ts:1273-1345`, `docs/air-extensions.md:1137-1140`).
  Close interrupts the turn and clears async tasks.
- **cx9.** `read-only`, `workspace-write`, `agent` (the default: Codex's
  model reviewer approves) and `agent-full-access` (`src/AgentMode.ts:39-100`).
- **cx10.** `models` with ids `model[effort]`, legacy `session/set_model`,
  and the `model` config option (`src/CodexAcpServer.ts:1967-2010`).
- **cx11.** `mode`, `collaboration_mode` (Default or Plan), `model`,
  `reasoning_effort` (category `thought_level`, the model's efforts) and
  `fast-mode` (a select unless booleans are declared)
  (`src/CodexAcpServer.ts:2272-2300`, `src/ModelConfigOption.ts:72-95`).
- **cx12.** `src/CodexAcpClient.ts:1361-1391`: audio is dropped; a resource
  keeps its text as `<context ref>`, an image blob as an image, another blob
  as base64; a `resource_link` is a text link only.
- **cx13.** `docs/air-extensions.md:237-348` (the column for other
  clients). Kinds `execute`, `read`, `search`, `edit`, `fetch`, `think`,
  `switch_mode`, `other`. Every command carries `terminal` content with an
  id though no client terminal exists; output streams in
  `_meta.terminal_output_delta`. A call is `in_progress` also while it waits
  on an approval.
- **cx14.** `allow_once`, `allow_always`, `reject_once`, `reject_always`
  from Codex's decisions. Cancelled, an unknown option, a transport failure
  or a malformed answer fail closed; no timeout
  (`docs/air-extensions.md:538-632`).
- **cx15.** `request_user_input` with `_meta.codex` and MCP forms; MCP URL
  elicitation, MCP OAuth and the device-code login as URLs
  (`src/CodexElicitationHandler.ts:290-306,419-480`).
- **cx16.** Standard `plan` entries, and plan-mode markdown as `plan_update`
  to a client declaring `plan` (`docs/air-extensions.md:636-674`).
- **cx17.** `turn/interrupt` on the root thread only; a child id stops
  nothing, and background terminals keep running
  (`src/CodexAcpServer.ts:3994-4004`, `docs/subagent-sessions.md`).
- **cx18.** `src/CodexAcpServer.ts:2029-2147` answers `injected`,
  `startedNewTurn` or `failed`; there is no `idleBehavior` in `src/`, so a
  steer with no turn running starts one.
- **cx19.** Draft `subagent_spawned` and `subagent_state_update` to a client
  declaring `subagents`; no targeted cancel or close
  (`docs/subagent-sessions.md`).
- **cx20.** `usage_update.used` is the last request's tokens, `size` the
  context window; no cost. `PromptResponse.usage` is the whole turn: the
  thread's total at the end minus at the start, else the summed per-request
  counts (`src/TokenCount.ts:106-150`, `src/CodexAcpServer.ts:3926-3955`,
  shipped at `dist/index.js:45367-45384`). CHD-432 lists CHD-374 as
  unaffected; that is wrong.
- **cx21.** `/plan`, `/mcp`, `/skills`, `/status`, `/review`,
  `/review-branch`, `/review-commit`, `/compact`, `/goal`, `/rename`,
  `/logout`, and `$skill` commands (`src/CodexCommands.ts:138-210`).
- **cx22.** After the first turn the adapter asks a model for a title
  (`gpt-5.6-luna`, an ephemeral thread, the first message cut to 4000
  characters) and sends it as `session_info_update` to every client
  (`src/TitleGenerator.ts:4-148`). CHD-432's "Session titles —" for codex is
  wrong.
- **cx23.** `api-key`, `chat-gpt` (a browser), `chat-gpt-device-code` (with
  `elicitation.url`), `gateway` (with `auth._meta.gateway`); none of type
  `terminal`. chord would get the first three (`src/CodexAuthMethod.ts:1-90`).
- **cx24.** An SSE server fails `session/new` with "Codex doesn't support
  MCP SSE transport protocol"; a server whose name the person's Codex config
  already has is skipped as a failed startup call
  (`src/CodexAcpClient.ts:965-998,1043-1063`).
- **cx25.** `src/CodexAcpServer.ts:474-540`: `loadSession`, image and
  embedded context, MCP http (not sse), `sessionCapabilities` resume, list,
  close, delete, fork, `additionalDirectories`, `subagents`; `auth.logout`,
  `providers`, `_meta.authStatus`, `_meta.steering.supported`.
- **cx26.** `elicitation` form and URL, `plan`, `session.compaction`,
  `session.notices`, boolean config options, `subagents`,
  `auth._meta.gateway`, `_meta.terminal_output`,
  `_meta.terminal_output_delta`, `_meta.jetbrains.air`
  (`src/tool-calls/ClientCapabilities.ts:65-92`). Not `fs` or `terminal`.
- **cx27.** Eleven, each a bullet under Custom below.

**Custom.**

- Its own `/mcp` and `/mcp reconnect`: server status, and MCP OAuth by URL
  elicitation (`src/mcp/McpCommand.ts:18-80`). Hidden by chord's `/mcp`.
- Its own `/status`: token usage and the account's rate limits, which are
  never pushed (`src/CodexCommands.ts:464-540`). Hidden by chord's
  `/status`, so the rate limits are unreachable from chord.
- Usage and account `_meta`, to every client: `PromptResponse._meta.quota`
  per model, the `_auth/status_update` notification (kind, label, plan) and
  `session_info_update._meta.codex.threadStatus`
  (`src/CodexAcpServer.ts:3926-3940,1838`). CHD-432's "Own usage or cost ✗"
  for codex is wrong for usage; there is still no cost.
- Instructions and other `session/new` `_meta`:
  `_meta.jetbrains.air.customInstructions`, read with no AIR declaration,
  new sessions only (`src/AirExtension.ts:101-108`), and
  `_meta.mcpStartupAwaitTimeoutMs`, which waits for the passed MCP servers.
- `_session/steering`, announced by `_meta.steering.supported`; no
  `promptRequired`, so a late steer starts and spends a turn.
- `_session/goal` and `/goal`: a long-running objective that keeps spending
  between prompts. The method works for any client; its snapshots are
  AIR-only (`src/CodexAcpServer.ts:592-650`).
- `_codex/hooks/list` and `_codex/hooks/trust`: registered for every
  client; trusting writes into the person's `$CODEX_HOME/config.toml`.
- Fork point: `session/fork` with `_meta.jetbrains.air.fork {version: 1,
  messageId}` keeps whole turns up to that message, with no AIR declaration.
- AIR (`_meta.jetbrains.air` declared): async tasks for background shell
  commands with their own stop, the session index with real delete,
  `diffPatch`, `sessionFailure` and more (`docs/air-extensions.md`).
  Declaring it changes every update's shape: unchanged `_meta` keys
  dropped, `_meta.codex.*` removed, fewer fields on permission requests.
- `terminal` content with an id on every command, and `_meta.terminal_info`
  and `terminal_exit`, Zed's convention, with no client terminal.
- Plan review as a `session/request_permission` of kind `switch_mode` with
  options `implement_plan` and `revise_plan`.

**In chord.** chord sets model and effort through the config options and
mode with `set_mode`, and an enricher fills in the mode Codex leaves out
after it. Draft subagents are reshaped into the RFD shape by an enricher.
chord never cancels a child on its own id, which would stop nothing on codex
anyway. It reads `PromptResponse.usage`, which is now the whole turn, and
estimates the cost. It drops the generated title, though codex spends a
model call on it, and ignores `_meta.quota` and `_auth/status_update`. The
default `agent` mode sends approvals to Codex's model reviewer, more spend
chord does not show. chord's `/mcp` and `/status` hide codex's, so Codex's
MCP sign-in and rate limits cannot be reached. chord passes the person's MCP
servers as they are, never checked against `mcpCapabilities.sse: false`, so
an SSE server in the person's settings fails `session/new`. Steering carries
only messages from other agents; a late one starts a turn on codex. List,
fork, delete and close are never called.

**Sources.**

- `@agentclientprotocol/codex-acp` 2.2.2 on npm;
  <https://github.com/agentclientprotocol/codex-acp/tree/v2.2.2>, `README.md`,
  `CHANGELOG.md`, `docs/air-extensions.md`, `docs/subagent-sessions.md`.
- CHD-432's notes in
  [`design/registry-2026-10-17.md`](design/registry-2026-10-17.md)
  (cx1–cx7, X1–X4, U8).

#### deepagents

- Name: DeepAgents
- Pinned: `deepagents-acp` 0.1.7
- Run as: `npx -y deepagents-acp@0.1.7`
- Source: <https://github.com/langchain-ai/deepagentsjs>

Read at `deepagents-acp` 0.1.7, the ACP Registry's pin, unchanged since
CHD-432: the npm package, MIT, with nothing restricting reading. Its bin is
`dist/cli.js`, a readable tsdown bundle; line numbers below are in that file.
It wraps `deepagents` 1.8.8 on `@agentclientprotocol/sdk` `^0.17.0`, which
resolves to 0.17.1 today. The registry passes no flags, so the model
(`claude-sonnet-4-5-20250929` by default) and its provider key
(`ANTHROPIC_API_KEY`) are set outside chord.

**Footnotes.**

- **da1.** `initialize` echoes the client's version, a number or parsed,
  else 1 (`:662`), so 1 to chord.
- **da2.** `package.json`; `PROTOCOL_VERSION = 1` in the SDK.
- **da3.** Handlers for initialize, authenticate, new, load, prompt, cancel
  and set_mode only (`:632-642`). No unstable method, no v2.
- **da4.** `session/new` also reads the off-spec `params.mode` and
  `params.configOptions.agent` (`:696-712`).
- **da5.** Sessions live in memory; after a restart load answers "Session
  not found" (CHD-432 da3).
- **da6.** Three modes that change nothing; the model is fixed by `--model`
  (CHD-432 da2).
- **da7.** It reads `block.mediaType`, but ACP's field is `mimeType`, so
  every image goes to the model labelled `image/png` (`:275-276`). A JPEG so
  labelled may be refused by the provider; not run.
- **da8.** `acpContentToLangChain` handles text, image and resource; an
  embedded resource becomes `[Resource: <uri>]` and its text. Anything else
  becomes `String(block)` (`:261-296`), so a `resource_link` beside text is
  the literal text `[object Object]`. A replayed user message keeps only its
  first block (`:1160`).
- **da9.** Kinds `read`, `search`, `edit`, `execute`, `think`, `other`
  (`:348-366`). Arguments and results go under the non-ACP keys `input` and
  `output` (`:1190`, `:1206`), not `rawInput` or `rawOutput`. Content is one
  text block on `completed` only; no diff, no terminal. Locations for read,
  write and edit (`:392`).
- **da10.** `pending`, `in_progress`, then `completed`, or the non-ACP
  `"error"` on failure and `"cancelled"` on abort (`:864-869`, `:982`,
  `:1180-1215`).
- **da11.** Nothing calls its permission request: every tool, writes
  included, runs without asking (CHD-432 da4).
- **da12.** `write_todos` never reaches a `plan` update (CHD-432 da5).
- **da13.** Cancel aborts the newest turn's stream and marks its open calls
  `"cancelled"` (`:834-837`). A second prompt starts its own stream, and the
  first can then not be cancelled (CHD-432 da1).
- **da14.** A subagent is one `Delegating:` call (CHD-432).
- **da15.** `/plan`, `/agent`, `/ask`, `/clear`, `/status` plus an agent
  config's own commands, after new and load, before the answer
  (`:721-731`, `:754-763`).
- **da16.** Environment-variable methods; `authenticate` does nothing
  (CHD-432).
- **da17.** `fs.readTextFile`, `fs.writeTextFile` and `terminal` are
  recorded (`:652-659`), but the CLI always uses its own filesystem
  (`:1576`), and `executeWithTerminal` is never called; it has no shell at
  all (CHD-432 da6). The dead fs path would also call `readTextFile`
  without a `sessionId` (`:1295-1296`).
- **da18.** `mcpServers` is never read anywhere in the file.
- **da19.** `{loadSession: true, promptCapabilities: {image: true, audio:
  false, embeddedContext: true}, mcpCapabilities: {http: false, sse: false},
  sessionCapabilities: {modes: true, commands: true}}`; the last two are not
  ACP fields (`:667-683`).

**Custom.**

- `input` and `output` on tool calls: arguments and results under keys of
  its own. A client must read them; a standard one loses the arguments and
  sees results only on success.
- Statuses `"error"` and `"cancelled"`: nothing a client can rely on; a
  strict client shows the call unfinished.
- `session/new` params `mode` and `configOptions.agent`: a start mode and a
  named agent config. A client must send them; private coupling.
- Launch flags `--model`, `--workspace`, `--skills`, `--memory`, `--name`,
  `--description`, `--debug`, `--log-file` (`:1408-1465`): set in the launch;
  the registry passes none.

**In chord.** chord sends every @-mention as a `resource_link`, never
embedded, though deepagents advertises `embeddedContext`; deepagents turns
each link into `[object Object]`, and the path survives only because the
prompt's own text names it. Images go out with the right `mimeType`, and
reach the model labelled PNG. chord reads `rawInput` and `rawOutput`, so tool
rows show titles and the completed text only. A failed or cancelled call
keeps reading `Waiting…`, as chord knows neither status. Every tool runs
without asking, writes included. Modes show and do nothing; no model or
effort list. Load fails after the agent restarts. No usage arrives, so
chord estimates nothing. chord's own MCP server is left out, as `http` is
false, and the person's servers are passed and ignored. A mid-turn prompt
is queued, which keeps a second stream from starting. chord never calls
`session/list`.

**Sources.**

- `deepagents-acp` 0.1.7, npm, and https://github.com/langchain-ai/deepagentsjs.
- `@agentclientprotocol/sdk` 0.17.1, npm.
- CHD-432's reading, `docs/design/registry-2026-10-17.md` (da1-da7).

#### dimcode

- Name: DimCode
- Pinned: `dimcode` 0.5.19
- Run as: `npx -y dimcode@0.5.19 acp`
- Source: <https://dimcode.dev/docs/acp.html>

Read at 0.5.19, the registry's pin, from the npm wrapper `dimcode@0.5.19`
and its `dimcode-darwin-arm64@0.5.19`, a Bun-compiled binary whose bundled
JavaScript stands in it as plain text with `// <path>` module markers. Cites
name the module path from those markers (`../agent/…` as the marker has it),
with lines counted from the marker. The bundler's output is not obfuscated;
it was read as text, not decoded. The package names a LICENSE it does not
ship, and there is no public repository. Other platforms' binaries were not
read. Two findings correct the CHD-432 study: usage with cost comes as a
standard `usage_update` with no opt-in, and the question form is standard
`elicitation/create`, which `_lody` only adds extras to.

**Footnotes.**

- **dm1.** `src/acp/capabilities.ts:58-66`: invalidParams for a non-integer
  or a version below 1, and 1 for anything above.
- **dm2.** `@agentclientprotocol/sdk` 0.21.1 from the pnpm path in the
  bundle; `AgentSideConnection` on `ndJsonStream`
  (`src/acp/connection.ts:11-19`).
- **dm3.** `src/acp/server.ts:10-89`: stable v1 methods plus, unstable in
  0.21.1, `session/fork`, `session/set_model`, `elicitation/create`,
  `document/did*` as no-ops and `userMessageId`; `_lody/*` and `_dimcode/*`.
- **dm4.** `src/acp/session-bridge.ts:134-181`: a new session gets
  permission preset `read-only`, and answers `configOptions`, `modes` and
  `models`. Without provider credentials it fails `auth_required`.
- **dm5.** Load replays chunks and tool calls with `_meta.lody.turnId` after
  the answer (`session-bridge.ts:362-404`); resume has no replay (`:405-437`).
- **dm6.** `session-bridge.ts:183-206`: `cwd` filter, cursor, newest first;
  an `additionalDirectories` filter is refused.
- **dm7.** `session-bridge.ts:207-245`: same cwd only; with
  `_meta.lody.forkAtTurn {turnId}` it forks at that assistant message.
- **dm8.** No delete. `session/close` cancels the run, its permissions and
  terminals (`session-bridge.ts:438-445`).
- **dm9.** `src/acp/config-options.ts:8-11`: `agent` and `goal` (C7).
- **dm10.** `config-options.ts:69-75,186-205`: `provider/model` ids as
  `models` and as the `model` option.
- **dm11.** `config-options.ts:2-38,262-312`: `mode`, `model`,
  `thought_level` (alias `reasoning_effort`, levels from the model), and
  `permission`: `read-only`, `workspace-write`, `full-access`.
- **dm12.** `src/acp/prompt-bridge.ts:266-405`: images saved as
  attachments; audio refused with invalidParams; embedded text inlined as
  `<resource>`; a `resource_link` becomes the text `<resource name uri />`,
  never read for the model.
- **dm13.** `src/acp/event-bridge.ts`: kind guessed from the tool name
  (`:583-604`), title the bare name (`:245`), rawInput at start, rawOutput the
  whole result; content text, image, link, or `terminal` with a client
  terminal, never a `diff` (`:453-492`). Locations only on the permission's
  call (`src/acp/permission-bridge.ts:198-209`). Calls start `in_progress`
  and end `completed` or `failed`; one that asks goes `pending` first.
- **dm14.** `permission-bridge.ts:2-23,140-146`: four options, "always"
  kept for the session, `cancelled` a deny, no timeout. Under the default
  `read-only` preset writes, network and commands are denied without asking
  (`src/core/permission-policy.ts:19-27`); `workspace-write` asks for
  commands and network, `full-access` never asks.
- **dm15.** `src/acp/elicitation.ts:2-78`: with `elicitation.form` declared,
  its question tool becomes a standard form, `oneOf` or `anyOf` per question
  and a `__custom_<i>` field, tagged `_meta.lody.elicitation` whether or not
  the client opts in. No URL mode.
- **dm16.** `event-bridge.ts:252-265,544-579`: TodoWrite results as `plan`,
  the call hidden.
- **dm17.** `session-bridge.ts:692-714`: interrupts the run, aborts its
  permissions, kills its client terminals. Whether external subagents, run
  as background tasks, stop too was not traced.
- **dm18.** `prompt-bridge.ts:5-10`: a second `session/prompt` is refused
  with "ACP session already has an active prompt". No `_meta.steering`;
  steering only by `_lody/session/steer` (C3).
- **dm19.** `event-bridge.ts:37-67,330-358`: by default a `think` call
  `subagent:<childSessionId>` with output in rawOutput deltas and
  `_meta.lody.task`; with `_meta.lody.subagentEvents` declared, that call is
  replaced by `_lody/subagents/event`. No `subagent_update`.
- **dm20.** `event-bridge.ts:74-102,302-320`: standard `usage_update` with
  `used`, `size` and the session's total cost, sent with no opt-in. The cost
  is `COALESCE(SUM(cost), 0)`
  (`../agent/src/storage/sqlite-session-catalog.ts:192`),
  so an unpriced model sends 0. No `PromptResponse.usage`.
- **dm21.** `src/acp/slash-commands.ts:2-19`: `/help`, and `/compact` where
  that plugin loads; sent after new, load, resume, fork and each command.
- **dm22.** `event-bridge.ts:302-326`: `title` and `updatedAt` at start and
  on change; also `_meta.lody.goal` and MCP warnings in `_meta.lody.notice`.
- **dm23.** `src/acp/auth.ts:3-56`: a `terminal` method only to a client
  declaring `auth.terminal` or `_meta["terminal-auth"]`, else `[]`; without
  credentials session/new fails "Provider credentials are required".
- **dm24.** `src/acp/client-tool-backend.ts:23-330`: `fs/*` for read, write
  and edit, `terminal/*` for exec, only when declared.
- **dm25.** `src/acp/mcp-bridge.ts:17-50`: stdio servers dropped with a
  warning sent only as `_meta.lody.notice`; http and sse taken.
- **dm26.** `capabilities.ts:7-38`: `loadSession`, prompt `{image,
  embeddedContext}`, `mcpCapabilities {http, sse}`, session `{fork, list,
  resume, close}`, and `_meta.lody` and `_meta["dimcode.extensions"]`.
- **dm27.** `client-tool-backend.ts:23-26`, `prompt-bridge.ts:118-120`,
  `auth.ts:48-51`, `src/acp/lody.ts:33-45`: `fs`, `terminal`,
  `elicitation.form`, `auth.terminal`, three `_meta.lody` keys; never `plan`,
  `subagents` or `elicitation.url`.

**Custom.**

- `_meta.lody` on standard updates, always on: turn ids, tool names, task
  state, title source, goal and MCP warnings. Nothing to declare; a client
  that ignores it loses the warnings and the goal.
- `_lody/session/usage_update`: per-model and per-turn tokens and cost.
  Needs `_meta.lody.usage` or any `_lody` call; its `usage` is a delta or a
  total depending on the case.
- `_lody/session/steer` and `steer_applied`: a second steering protocol,
  answered without opt-in; calling it turns the private usage on.
- `_lody/subagents/list|cancel|output`: a stop and the output per subagent,
  by the `taskId` in `_meta.lody.task`.
- `_lody/subagents/event`: needs `_meta.lody.subagentEvents`, and then the
  standard subagent call is no longer sent.
- `_lody/rate_limits/get|update`: quota windows; queries the provider.
- Goal mode, by mode `goal` or `_meta.lody.goalControl` on a prompt: dimcode
  keeps working on its own, so more turns and more spend.
- `_lody/session/history/read`, and `_dimcode/*` file rewind and reapply,
  which change the person's files.
- External CLIs as subagents, on by default since 0.5.19
  (`../agent/src/agent-type/registry-meta.ts:2-24`, `drivers/`): each
  session probes PATH for 18 CLIs, claude, codex, cursor (`agent`), droid,
  pi-acp and others, and the model may start them with their approvals
  bypassed (claude with `bypassPermissions`, ACP CLIs answered
  `allow_always`), on the person's own accounts. It presents itself to devin
  as `windsurf`. No ACP switch turns it off; only dimcode's config or the
  `permission` option gates its `agent` tool.
- `PromptResponse._meta.dimcode.error` on a failed run, which otherwise
  reads as stopReason `refusal`.

**In chord.** chord opens, reopens by resume or load, cancels, and sets mode,
model, effort and the `permission` option as plain config options. The
standard `usage_update` brings the session's cost; for an unpriced model it
is 0, which stops chord's estimate and reads $0.00 (CHD-380). Questions
reach chord's form because chord declares `elicitation.form`, and
`dimcodeQuestions` reads `_meta.lody.elicitation.customAnswerFor`; a
question whose own id is `__custom_<n>` would miss that match. A fresh
session is `read-only`, so writes and commands are denied with no prompt
until the person changes the option. Tool rows read the bare tool name with
no diff, and a subagent is one `think` row. @ mentions reach the model as a
bare name and URI. Without credentials the start fails `auth_required`, and
chord has no hint to give. A mid-turn prompt is queued, so dimcode's refusal
of a second prompt never comes up. chord drops titles, `_meta.lody` and
`_meta.dimcode.error`, never calls `session/list`, fork or close, and calls
no `_lody` method.

**Sources.**

- npm `dimcode@0.5.19` and `dimcode-darwin-arm64@0.5.19`.
- `docs/design/registry-2026-10-17.md` (CHD-432), `docs/design/CHD-1.md`.

#### dirac

- Name: Dirac
- Pinned: `dirac-cli` 0.5.21
- Run as: `npx -y dirac-cli@0.5.21 --acp`
- Source: <https://github.com/dirac-run/dirac>

Read at `dirac-cli` 0.5.21, the ACP Registry's pin, from the repository
https://github.com/dirac-run/dirac at tag v0.5.21 (2026-10-14), checked
against the npm package's `dist/cli.mjs`; paths below are in the repository.
Apache-2.0, with nothing restricting reading. `@agentclientprotocol/sdk`
1.3.0 was read beside it to see how the SDK routes requests, which is what
shows resume unreachable (di6) and corrects CHD-432's "resume goes through
load" (`docs/design/registry-2026-10-17.md`).

**Footnotes.**

- **di1.** It answers the SDK's `PROTOCOL_VERSION`, 1, whatever the client
  asks (`cli/src/agent/DiracAgent.ts:1164-1165`).
- **di2.** Exact pin (`cli/package.json:96`, `package-lock.json:212-214`).
- **di3.** v1 `AgentSideConnection`, no v2. Unstable or draft: form
  elicitation, close, delete, `providers/*`, `logout`, boolean config
  options, `session_info_update`, `usage_update`, and auth types `env_var`
  and `terminal` (`cli/src/acp/AcpAgent.ts:120-130`, `:367-460`).
- **di4.** A random UUID id; `_meta["dev.dirac/worktree"]` makes a git
  worktree first. Answers `modes` and `configOptions`; commands and options
  follow by `setImmediate` (`DiracAgent.ts:1277-1337`, `:1472-1485`).
- **di5.** Replays its journal of sent updates, then `usage_update`. It
  refuses a session with no runtime record, one whose history is gone, and
  one whose worktree is gone (`DiracAgent.ts:1345-1452`, `:2134-2207`).
- **di6.** `sessionCapabilities.resume` is advertised, but only
  `unstable_resumeSession` is defined (`cli/src/acp/AcpAgent.ts:367-373`).
  SDK 1.3.0 registers `session/resume` only for `resumeSession`
  (`dist/acp.js:1024-1025`), and the bundle's router does the same, so the
  request gets method-not-found. Dirac's tests call the method directly
  (`AcpAgent.test.ts:256-264`). Not checked live.
- **di7.** `unstable_listSessions` exists (`AcpAgent.ts:375-378`), but the
  SDK registers `session/list` only for `listSessions`; not advertised.
- **di8.** `closeSession` frees resources; `deleteSession` also removes the
  history and worktree; both also as `dev.dirac/session.*`
  (`AcpAgent.ts:283-286`, `:408-426`).
- **di9.** `plan` and `act` by `set_mode` and the `mode` option, with
  `current_mode_update` and `config_option_update` (`DiracAgent.ts:1944-1997`).
- **di10.** No `set_model` and no `models`; `model` is a config option over
  the provider's catalogue (`cli/src/agent/sessionConfig.ts:218-226`).
- **di11.** `mode`, booleans `auto_approve` and `yolo` (category `mode`,
  sent without the client's `sessionConfigOptions.boolean`), `provider`
  (`_provider`), `model`, `inference_speed`, and two `thought_level`
  selects: `reasoning_effort`, always, and `thinking_budget`, except on
  deepseek (`sessionConfig.ts:150-250`).
- **di12.** Only an embedded resource's `uri` is kept; a `resource_link` is
  dropped silently (`cli/src/agent/promptContent.ts:9-24`).
- **di13.** Kinds `edit`, `read`, `search`, `delete`, `think`, `execute`,
  `other`. `rawInput` is the tool's input; `rawOutput` the same, or
  `{reason}` or `{error}` on failure. Content is `diff` only. Locations
  carry path and line. `pending`, `in_progress`, `completed` or `failed`;
  cancel closes open calls `failed` (`cli/src/agent/messageTranslator.ts:23-53`,
  `:290-358`).
- **di14.** `allow_once`, `allow_always`, `reject_once`, `reject_always`.
  "Always" is written to the project's `.dirac/permissions.json`, for every
  session in that workspace. Asked only inside a prompt, one at a time;
  `cancelled`, an RPC error or cancel rejects and fails the call; no
  timeout (`cli/src/agent/permissionHandler.ts:38-84`,
  `DiracAgent.ts:1011-1035`).
- **di15.** A question is a form with a required `optionId` and an "Other
  answer" that opens a second form (CHD-1). Only with `elicitation.form`;
  never URL (`cli/src/agent/taskMessageBridge.ts:550-640`).
- **di16.** A `plan` only from a plan-response card, its lines as entries
  (`DiracAgent.ts:2209-2255`).
- **di17.** Cancel rejects a pending permission, cancels a form, aborts the
  task and its subagents, closes calls `failed`, then answers `cancelled`
  (`DiracAgent.ts:1853-1931`).
- **di18.** Steering is its own `dev.dirac/whisper` notification, taken only
  mid-turn, reported by `dev.dirac/steering_status`; no `_session/steering`.
  A second prompt on a busy session fails "busy"; prompts of other sessions
  in the process wait their turn (`DiracAgent.ts:403-439`, `:1576-1602`).
- **di19.** `use_subagents` is one call of kind `other`; children have no
  session, their approvals come as the parent's, and they stop only with it
  (`taskMessageBridge.ts:255-298`; CHD-432 di1).
- **di20.** `usage_update {used, size, cost?}`, `cost` cumulative and only
  when the provider gives one. `PromptResponse.usage` is the session's
  running total since it was opened or loaded, not the turn's as the spec
  says (`taskMessageBridge.ts:115-232`).
- **di21.** After new, load and resume, and before every prompt
  (`DiracAgent.ts:2257-2299`).
- **di22.** Once, on the first prompt with text: a summary title and
  `updatedAt` (`DiracAgent.ts:2301-2316`).
- **di23.** Offered only with no provider set up: browser setup, ChatGPT
  sign-in, `env_var` `DIRAC_*`, and `terminal` under `auth.terminal`. With no
  provider a prompt fails with a plain error, not `authRequired`
  (`cli/src/agent/AcpAuthenticationManager.ts:36-103`).
- **di24.** `fs/*` only when both fs flags are set, `terminal/*` when
  `terminal` is; otherwise its own (`DiracAgent.ts:1241-1260`).
- **di25.** `mcpServers` is never read and no `mcpCapabilities` is sent
  (`DiracAgent.ts:1277-1337`).
- **di26.** `loadSession`, `sessionCapabilities {resume, close, delete}`,
  `promptCapabilities {image, embeddedContext}`, `auth.logout`, `providers`,
  and 18 `dev.dirac/*` keys in `_meta`, 19 under `--listen`
  (`DiracAgent.ts:1164-1214`).
- **di27.** `fs.readTextFile` and `fs.writeTextFile`, `terminal`,
  `elicitation.form`, `auth.terminal`, `_meta["terminal-auth"]`; nothing
  else (`cli/src/acp/ACPTextFileAccess.ts:14-31`).

**Custom.** Each sits behind a key in `agentCapabilities._meta`; a client
opts in by calling it.

- `dev.dirac/whisper` and `dev.dirac/steering_status`: steering, reported
  `queued` then `sent`. Dropped silently outside a turn.
- `dev.dirac/seq` on every update: an ordering number for replay. Free.
- `dev.dirac/client_annotation`: client events kept and replayed on load.
- `dev.dirac/permissions.list` and `.delete`: the stored "always" rules,
  which outlive the session.
- `dev.dirac/checkpoints.list` and `.restore`: rewrite workspace files.
- `dev.dirac/messages.pin`, `.unpin`, `.pinned`: pinned context, by an
  internal message id ACP never carries.
- `dev.dirac/worktree.provision` and `.integrate`: a session in its own git
  worktree, merged back on request.
- `providers/*` (draft): pick the provider from the client.
- `dev.dirac/permission.effect_previews`: advertised; nothing implements it.
- `--listen <socket>`: sessions outlive a disconnected client.

**In chord.** chord resumes whenever the agent offers `resume` and chord has
its own record, so every reopen of a dirac session chord recorded hits
method-not-found; only a session chord never recorded goes through load.
chord reads `PromptResponse.usage` as the turn's, so dirac's session totals
show as growing turns, and chord's estimate, made when dirac sends no cost
and the model has a price, adds the totals up and overcounts. chord's effort
control takes the first `thought_level` select, `reasoning_effort`;
`thinking_budget` is a plain option. `provider` shows as an ordinary option.
The booleans `auto_approve` and `yolo` are dropped. chord's @-mention links
are dropped; the prompt text still names the path. chord's own MCP server is
left out and the person's servers are ignored. Forms and the four permission
kinds work, with the "Other answer" enricher. A mid-turn prompt is queued,
which avoids dirac's busy error. Titles, close, delete and every
`dev.dirac/*` extension go unused; chord never calls `session/list`.

**Sources.**

- https://github.com/dirac-run/dirac, tag v0.5.21; `dirac-cli` 0.5.21, npm.
- `@agentclientprotocol/sdk` 1.3.0, npm.
- CHD-432's reading, `docs/design/registry-2026-10-17.md` (di1-di2).

#### factory-droid

- Name: Factory Droid
- Pinned: `droid` 0.244.0
- Run as: `npx -y droid@0.244.0 exec --output-format acp-daemon`
- Source: <https://factory.ai/product/cli>

Read at 0.244.0, the registry pin, released 2026-10-16 by Factory's
changelog. npm `droid@0.244.0` is only a shim and installer; the program is
the native binary `bin/droid` of `@factory/cli-darwin-arm64@0.244.0`, which
the installer takes from that optional dependency or from its npm tarball.
The package says only `"license": "UNLICENSED"`, and its source is private.
The binary is a `bun build --compile` executable that embeds minified JS.
Under the owner's rule of 2026-10-18, recorded on CHD-433, that JS was read
as plain text only for the ACP contract: the messages, fields and
capabilities droid sends and accepts, and how it behaves. Nothing was
decompiled, deobfuscated or beautified, and the binary was never run. Where
Factory's changelog or docs state a fact, they are cited first; the rest is
from `@factory/cli-darwin-arm64` 0.244.0. chord launches
`exec --output-format acp-daemon`; `--output-format acp` runs the same
daemon.

**Footnotes.**

- **dr1.** `initialize` answers 1 whatever version the client sends.
- **dr2.** The package metadata embedded in 0.244.0 declares
  `@agentclientprotocol/sdk` `^1.5.0`, and droid knows the client methods
  `mcp/connect` and `mcp/disconnect`, which 1.6.0 drops: so 1.5. The patch
  level is not established from the wire contract.
- **dr3.** droid answers initialize, authenticate, session new, load,
  resume, list, prompt, set_mode, set_config_option and `session/set_model`,
  and takes `session/cancel`. Any other request, fork, close and delete
  included, gets -32601.
- **dr4.** Without a login `session/new` fails `authRequired`; it takes
  `mcpServers` and answers `models`, `modes` and `configOptions`.
- **dr5.** Replays every message, tool calls as `completed`.
- **dr6.** Resume sends no replay.
- **dr7.** `session/list` takes the cwd and a cursor and answers 50 a page;
  entries carry `title`, `updatedAt` and `_meta.messageCount`.
- **dr8.** Modes `normal` ("Auto (Off)"), `spec`, `auto-low`,
  `auto-medium`, `auto-high`, cut to the org's maximum autonomy. Options
  `autonomy_level` (category `mode`), `model` and `reasoning_effort`
  (`thought_level`), its values the efforts the model supports.
  `current_mode_update` and `config_option_update` follow a change.
- **dr9.** `availableModels` in the session answer; `session/set_model`
  refuses a model not enabled.
- **dr10.** One user message: a `resource` becomes `<context ref="…">` text,
  a `resource_link` a `[@name](uri)` link, and `audio` is dropped.
- **dr11.** Kind chosen from the tool name: `edit`, `execute`, `read`,
  `search`, `think`, `other`. `rawOutput` only at completion, and on a
  running shell command's updates. `locations` only for file create, edit
  (path) and read (path and line). Some tools are never announced; which is
  not established.
- **dr12.** `diff` for file create and edit, text for the rest. `terminal`
  content and `_meta.terminal_*` only when the client declares
  `_meta.terminal_output: true` (Custom).
- **dr13.** A live call starts `pending`; only a running shell command sends
  `in_progress`; it ends `completed` or `failed`. A shell command still open
  when the turn ends is closed `failed` with no text.
- **dr14.** Options `allow_once`, `allow_always` and `reject_once`, with
  droid's own labels. One request covers a batch of tool uses but names only
  the last as `toolCall`, with `rawInput` and a title like `` `cmd` (low) ``.
  A `session/cancel` does not withdraw it; an error or `cancelled` counts as
  droid's cancel. No timeout.
- **dr15.** Form: `elicitation/create` when `elicitation.form` is declared,
  withdrawn with the turn (the `question_<i>` shape of
  `docs/design/CHD-1.md`). URL: only the sign-in link, sent outside any
  session while new, load, resume or `authenticate` waits.
- **dr16.** The todo tool's use becomes a `plan` update and no tool call,
  whatever the client declares.
- **dr17.** `session/cancel` stops the turn; the prompt answers `cancelled`.
  That background delegated tasks and commands end with it is in release
  notes .239 and .240 only (`n`).
- **dr18.** A second `session/prompt` is refused -32600 "A prompt is already
  running for this session". No steering method or `_meta`.
- **dr19.** A child session's updates never reach the client, so the parent's
  tool use stays one call; a child's permissions are asked under the parent.
  No stop per child.
- **dr20.** The prompt answers only `stopReason`; no `usage_update`.
- **dr21.** The enabled skills, right after new, load or resume, outside a
  turn; no built-in slash commands.
- **dr22.** No `session_info_update`; titles only in `session/list`.
- **dr23.** Factory's IDE integration docs name browser login and
  `FACTORY_API_KEY`. The methods are `device-pairing`, `factory-api-key`, or
  `customer-prem` on such a deployment. Without a login, new, load and
  resume fail `authRequired` (Custom, sign-in).
- **dr24.** stdio, http and sse servers are taken, but `mcpCapabilities` is
  not advertised, so a client reads http and sse as false; `acp` transport is
  refused.
- **dr25.** `loadSession`, list, resume, image, `embeddedContext` and
  `_meta["terminal-auth"]`; no `mcpCapabilities`, no audio.
- **dr26.** Only `elicitation.form`, `elicitation.url` and
  `_meta.terminal_output`.

**Custom.**

- `_meta.terminal_output` opt-in: a running shell command gets `terminal`
  content and `_meta.terminal_info`, `terminal_output` and `terminal_exit`.
  `terminal_output.data` is only the new part, under the name Claude's
  adapter uses for the whole output. On that path `rawOutput` is dropped.
  Without the opt-in every update resends the whole output so far.
- Sign-in by a URL elicitation with no `sessionId`, tied by `requestId` to
  the request it holds up. A client must declare `elicitation.url` and
  answer it while that request waits. Declined or cancelled, the request
  fails `authRequired` "Sign-in was cancelled. Retry to sign in."
- `session/set_model`: the same as the `model` option.
- `_meta.messageCount` on `session/list` entries.
- `_meta["terminal-auth"]: true`: no method or auth method here uses it;
  what it gives is unknown.
- A failed turn sends "Error: …" as reply text before the JSON-RPC error.
- The registry's `DROID_DISABLE_AUTO_UPDATE` occurs nowhere in the binary;
  `FACTORY_DROID_AUTO_UPDATE_ENABLED=false` turns auto-update off alone.

**In chord.** chord declares `elicitation.url`, so a droid that is not signed
in sends its sign-in link during `session/new`. chord subscribes to a
session's elicitations only in `#setUp`, after `session/new` has answered
(`src/session/conversation.ts:505-519, 1901-1904`), and a request nobody
listens to is answered `cancel` (`src/session/elicitations.ts:120-121`). So a
first run without a login or `FACTORY_API_KEY` fails to start with "Sign-in
was cancelled". This is read from droid 0.244.0 and chord's code, not
run. chord declares
`terminal_output_delta`, not `terminal_output`, so droid resends the whole
shell output as text on every update; chord draws it, at quadratic traffic.
If chord declared `terminal_output`, it would read droid's deltas as whole
replacements (`src/session/transcript/tools.ts:151-153, 170-205`) and show
only the last chunk. droid advertises no `mcpCapabilities`, so chord's own
server never goes in. Mode, model and effort work through the three options.
Forms reach the question box; permissions carry the real command in their
title and `rawInput`. A permission open at cancel is answered `cancelled` by
chord, which droid reads as `cancel`. chord queues a mid-turn prompt, which
droid would refuse anyway. No usage, so no meter and no estimate. Shell calls
still open at the turn's end read failed. chord never calls `session/list`,
so titles and message counts go unused, and it ignores `terminal-auth`.

**Sources.**

- npm `droid@0.244.0` and `@factory/cli-darwin-arm64@0.244.0`.
- `@agentclientprotocol/sdk` 1.5.0 to 1.8.0, for the version match.
- Factory's CLI changelog, 0.237 to 0.244, and its IDE integration docs.

#### fast-agent

- Name: fast-agent
- Pinned: `fast-agent-acp` 0.10.1
- Run as: `uvx fast-agent-acp@0.10.1 -x`
- Source: <https://github.com/evalstate/fast-agent>

Read at `fast-agent-acp` 0.10.1, the ACP Registry's pin, unchanged since
CHD-432, run through `uvx` with `-x` and `FAST_AGENT_MODEL=codexplan`. The
shim wheel requires `fast-agent-mcp==0.10.1`, which holds all the code;
paths below are in its `fast_agent/` package. Apache-2.0, with nothing
restricting reading. It does start on current uv, which corrects CHD-432:
`docs/design/registry-2026-10-17.md` has it as "May not start", saying it
pins a pre-release `uvx` will not resolve without `--prerelease=allow` and
that the shim's script points at a module it does not ship. With uv 0.13.1
(2026-10-13) it resolves with no flag, `fastmcp-slim==4.0.0b1` included, and
a fresh install's `fast-agent-acp` imports `fast_agent.cli.commands.acp`,
which the wheel ships. uv 0.6.12 still refuses without the flag, so whether
it starts depends on the person's uv. Installed, never run.

**Footnotes.**

- **fa1.** "Echo back the client's version"
  (`acp/server/agent_acp_server.py:364`), so 1 to chord.
- **fa2.** Python `agent-client-protocol` 0.10.1, exact pin (the wheel's
  `METADATA`); its `PROTOCOL_VERSION` is 1.
- **fa3.** v1: initialize, authenticate, new, load, list, resume, prompt,
  cancel, set_mode (`agent_acp_server.py:593-809`). It echoes
  `userMessageId` in the prompt answer (`acp/server/prompt_flow.py:383-386`).
  No set_model, config options, fork or close. No v2.
- **fa4.** Load replays text, `session_info_update` first; resume is an
  alias for load and replays too (CHD-432 fa5).
- **fa5.** `sessionId`, `cwd`, `title`, `updatedAt`, a cwd filter and cursor
  paging (`acp/server/session_store.py:316-375`).
- **fa6.** Fork, delete and title exist only as `/session` slash commands
  (CHD-432).
- **fa7.** Modes are its agents. Models change only by `/model`. Effort is
  fixed by the environment: `codexplan` means `reasoning=high` (CHD-432).
- **fa8.** Images go on as `input_image` with the data; audio becomes
  `[Unsupported audio content]`; an embedded resource's text is inlined
  (`acp/content_conversion.py:33-145`).
- **fa9.** A `resource_link` becomes an `input_file` with the link's URI;
  the Codex provider reads a `file://` path from disk and inlines it
  (`llm/provider/openai/codex_responses.py:115-150`). The path is cut from
  the URL with no percent-decoding
  (`llm/provider/openai/responses_files.py:134`), so a path with a space or
  a non-ASCII character is not found and the raw URL goes to the API.
  Whether the ChatGPT backend takes source files as `input_file` was not
  checked.
- **fa10.** Kinds inferred from words in the tool name
  (`acp/tool_kind_inference.py:22-58`). `rawInput` is the arguments,
  `rawOutput` the text parts or the error. Content is text, images and
  resources from MCP results; a diff only from its client-fs write tool
  (`acp/filesystem_runtime.py:468-490`); no terminal content. Locations are
  never set (`acp/tool_progress.py:240-262`, `:860-900`).
- **fa11.** `in_progress` is sent for some calls only (CHD-432).
- **fa12.** All four option kinds, each id equal to its kind (CHD-432).
- **fa13.** Cancel stops the session's newest turn task. A second prompt
  runs a second turn at once on the same history (CHD-432 fa2).
- **fa14.** Agents-as-tools send the child's calls flat in the parent with
  `_meta.parentToolCallId` (CHD-432 fa1).
- **fa15.** No usage; a text status line in `_meta["openhands.dev/metrics"]`
  on the answer and on an empty chunk (CHD-432 fa3).
- **fa16.** After `session/new`, as a background task: `/status`, `/tools`,
  `/model`, `/history`, `/clear`, `/session`, `/mcp` and ten more, plus the
  current agent's and plugins' (`acp/slash_commands.py:300-460`).
- **fa17.** Sent only on load and resume, with the stored title and
  `updatedAt`; never during a session (`session_store.py:261-283`).
- **fa18.** One `type: agent` method that returns hints. `codexplan` needs
  the Codex OAuth token the Codex CLI's login writes, or `fast-agent auth
  provider login codex`; without it the first prompt fails `auth_required`
  (`llm/provider/openai/codex_oauth.py:219-228`, `:416-437`).
- **fa19.** `fs/read_text_file` and `fs/write_text_file` as tools and
  `terminal/*` as the shell, each only when declared
  (`acp/server/session_runtime.py:1032-1120`).
- **fa20.** stdio, http and sse, with env and headers, become its own server
  settings per session (`acp/server/mcp_server_conversion.py:15-40`).
- **fa21.** `{_meta: {"co.huggingface": {structuredOutput: true}},
  promptCapabilities: {image: true, embeddedContext: true, audio: false},
  loadSession: true, mcpCapabilities: {http: S, sse: S}, sessionCapabilities:
  {list: {}, resume: {}}}`, S true when an agent uses MCP, as the default
  does (`agent_acp_server.py:314-345`).
- **fa22.** `fs.readTextFile`, `fs.writeTextFile`, `terminal`, and `_meta`,
  stored for status reports (`agent_acp_server.py:276-300`).

**Custom.**

- `_meta["co.huggingface"].structuredOutput` on `session/prompt`: a
  JSON-schema-shaped answer. A client must send a schema; slash commands
  refuse it.
- `_meta["openhands.dev/metrics"].status_line`: tokens and tools as text. A
  client must read `_meta`; a standard client gets no usage.
- `_meta.parentToolCallId`: a tree of agents-as-tools calls. A client must
  nest by it; otherwise the calls are flat and mixed.
- `auth_required` errors carry `envVars` and `docsUrl` in `data`.
- Launch flags `-x` (the registry's shell), `--no-permissions`,
  `--subagents`, agent cards.

**In chord.** chord sends every @-mention as a `resource_link`, never
embedded, though fast-agent advertises `embeddedContext`. fast-agent reads
the file from the link's path but does not decode it, and chord's links are
percent-encoded: a path with a space or a non-ASCII character reaches the
model as a bare `file://` URL. chord's own MCP server goes in, as `http` is
true, and so do the person's servers. chord reopens a recorded session with
`session/resume`, which replays, and chord, not expecting a replay, draws the
past twice. It never calls `session/list`. Usage is only in the `_meta`
line, which chord ignores, so there is no meter and no estimate. The
`parentToolCallId` tree reads flat, and titles sent on load are dropped.
Without a Codex login the first prompt fails `auth_required`. A mid-turn
prompt is queued, which keeps a second turn from running at once.

**Sources.**

- `fast-agent-acp` 0.10.1 and `fast-agent-mcp` 0.10.1 wheels, PyPI, and
  https://github.com/evalstate/fast-agent.
- uv 0.13.1 and 0.6.12, for the install check.
- CHD-432's reading, `docs/design/registry-2026-10-17.md` (fa1-fa6).

#### gemini

- Name: Gemini CLI
- Pinned: `@google/gemini-cli` 0.64.0
- Run as: `npx -y @google/gemini-cli@0.64.0 --acp`
- Source: <https://github.com/google-gemini/gemini-cli>

Read at `@google/gemini-cli` 0.64.0, the ACP Registry's pin, from the
repository https://github.com/google-gemini/gemini-cli at tag v0.64.0; paths
below are relative to `packages/cli/src/`, where `acp/` is the ACP layer.
CHD-432 compared the npm bundle of the same version. Apache-2.0, with nothing
restricting reading. Cells marked `r` come from CHD-432's reading
(`docs/design/registry-2026-10-17.md`, gemini ge1-ge9 and "gemini 0.63.0 →
0.64.0"). This reading adds one finding CHD-432 did not have: a mention
outside the workspace makes gemini ask a permission before its turn starts,
for a call chord has never seen (ge8).

**Footnotes.**

- **ge1.** It answers the SDK's `PROTOCOL_VERSION`
  (`acp/acpRpcDispatcher.ts:85`).
- **ge2.** `packages/cli/package.json:33`; `package-lock.json:92-94` resolves
  0.16.1.
- **ge3.** The dispatcher has `initialize`, `authenticate`, `newSession`,
  `loadSession`, `cancel`, `prompt`, `setSessionMode` and
  `unstable_setSessionModel`, and no `_` extension method
  (`acp/acpRpcDispatcher.ts:40-236`). No list, resume, fork, close or delete
  handler.
- **ge4.** `session/new` signs in from a saved login or `GEMINI_API_KEY`,
  else answers -32000 (CHD-432 ge6).
- **ge5.** Replays the history after its answer; 0.64.0 resolves the exact
  saved id. With no saved login it answers `authRequired` (CHD-432 ge6 and
  "gemini 0.63.0 → 0.64.0").
- **ge6.** `default`, `autoEdit`, `yolo` and `plan` (when enabled) through
  `session/set_mode`. A change from inside comes as an
  `agent_message_chunk` reading `[MODE_UPDATE] <mode>`, never as
  `current_mode_update` (`acp/acpSession.ts:179-189`).
- **ge7.** The `models` field and `unstable_setSessionModel`, with `auto`
  and fixed ids; no config options and no effort (CHD-432 ge5).
- **ge8.** Images and audio go to the model as inline data. An embedded
  resource's text joins the prompt, the block as `@uri`. A `file://`
  `resource_link` is read by gemini itself; a path outside the workspace
  first sends `session/request_permission` with a tool call id of its own
  that no `tool_call` announced, before the model turn starts. Any other uri
  becomes the text `@uri` (`acp/acpSession.ts:955-1113`, the ask at
  `1079-1113`).
- **ge9.** Kinds `read`, `edit`, `execute`, `search`, `delete`, `move`,
  `think`, `fetch`, `switch_mode`, `other`; a subagent is `think`
  (`acp/acpUtils.ts:202-222`). Text and diff content, the diff with
  `_meta.kind` add, delete or modify, and locations
  (`acp/acpSession.ts:710-761`). No `rawInput` or `rawOutput`. A call that
  asks goes `pending`, then to its end with no `in_progress` (CHD-432 ge9).
- **ge10.** `allow_once` and `reject_once`, plus `allow_always` for edit,
  exec, MCP and info calls; option ids are its own strings such as
  `proceed_once`, kinds are standard. `cancelled` cancels the tool and the
  call ends `failed`. No timeout (`acp/acpSession.ts:763-800`,
  `acp/acpUtils.ts:85-200`).
- **ge11.** No elicitation: its `ask_user` tool is off in ACP mode. No `plan`
  update; leaving plan mode is an Allow or Reject permission (CHD-432 ge7,
  ge8).
- **ge12.** One abort signal stops the model stream and the running tool, a
  subagent included (`acp/acpSession.ts:206-213`). With no turn running it
  throws inside the notification; an unknown session is -32602
  (`acp/acpRpcDispatcher.ts:189-198`).
- **ge13.** No steering. A second `session/prompt` aborts the running turn
  and runs alone (CHD-432 ge3).
- **ge14.** One tool call of kind `think`, no progress inside, no session of
  its own (CHD-432 ge1).
- **ge15.** `usage_update` `used` per model call and `size` the token limit;
  `PromptResponse.usage` with `totalTokens` = input + output, thinking
  outside it; no cost (CHD-432 ge4, "gemini 0.63.0 → 0.64.0").
- **ge16.** `memory`, `extensions`, `init`, `restore`, `about`, as
  `{name, description}` with no input hint. A prompt that starts with one is
  run by the agent and answered with zero usage
  (`acp/acpSession.ts:228-242`, `:355-371`; `acp/acpCommandHandler.ts:25-37`).
- **ge17.** `oauth-personal`, `gemini-api-key`, `vertex-ai` and `gateway`,
  none with a `type`, so all agent-run. `authenticate` also takes an API key
  in `_meta["api-key"]` or a gateway in `_meta.gateway`
  (`acp/acpRpcDispatcher.ts:47-140`). The ids are core's `AuthType` values,
  confirmed in the npm bundle's strings.
- **ge18.** `fs/read_text_file` and `fs/write_text_file`, each only when the
  client declares it, else its own files; never `terminal/*`
  (`acp/acpSessionManager.ts:126-136`, `acp/acpFileSystemService.ts:51-80`).
  `fs` is the only client capability it reads (`acp/acpRpcDispatcher.ts:43-45`).
- **ge19.** `sse` and `http` with headers, stdio with `env` and the session's
  `cwd`, merged over the person's own settings by name, so a client server
  replaces one of the same name (`acp/acpSessionManager.ts:380-425`).
- **ge20.** `loadSession`, `promptCapabilities` image, audio and
  `embeddedContext`, `mcpCapabilities` http and sse; no
  `sessionCapabilities`; `agentInfo` `gemini-cli`
  (`acp/acpRpcDispatcher.ts:91-102`).

**Custom.**

- `_meta.quota` on the prompt answer: input and output tokens and a
  per-model split. A client reads it; only the per-model split is beyond
  ACP's `usage` (`acp/acpSession.ts:365-405`).
- `[MODE_UPDATE] <mode>` reply text: the only word of a mode change from
  inside. A client must parse reply text; one that does not shows it and
  keeps a stale mode.
- `_meta["api-key"]` and `_meta.gateway` on `authenticate`: sign in from the
  client. The secret passes through the client.
- `_meta.kind` on diff content: add, delete or modify without comparing
  texts. Free.
- Off-spec: a concurrent prompt aborts the running one; thinking tokens sit
  outside `totalTokens`.

**In chord.** chord creates and loads sessions, sets models through
`session/set_model` and modes through `session/set_mode`, sends images, and
draws the context meter and answer usage. chord's estimate prices the
answer's tokens, but thinking tokens go unpriced and `auto` has no price, so
the default model shows no cost. `[MODE_UPDATE] plan` is drawn as reply text
and chord's mode stays where it was. Permissions work by kind. Commands show
as slash commands. chord's http MCP server goes in, and the person's sse
servers work. chord declares no `fs`, so gemini reads and writes its own
files. chord queues a mid-turn prompt, which avoids gemini's abort. chord
sends each `@` mention as a `resource_link`, which gemini reads; one outside
the workspace brings a permission before the turn's first update, for a
tool call chord has no `tool_call` for, and how that box and its answer read
in chord is not checked. chord never calls `authenticate`, so a load with no
saved login fails with gemini's message. `_meta.quota` and diff `_meta.kind`
are ignored; chord never calls `session/list`.

**Sources.**

- https://github.com/google-gemini/gemini-cli, tag v0.64.0.
- `@google/gemini-cli` 0.64.0, npm.
- CHD-432's reading, `docs/design/registry-2026-10-17.md` (ge1-ge9).

#### github-copilot-cli

- Name: Copilot
- Pinned: `@github/copilot` 1.0.98
- Run as: `npx -y @github/copilot@1.0.98 --acp`
- Source: <https://github.com/github/copilot-cli>

Read at `@github/copilot` 1.0.98, the ACP Registry's pin; the display name is
now Copilot. No source is public: the ACP server is inside the package's
native runtime. The package's licence, the GitHub Copilot CLI License,
allows installing, running and redistributing it unmodified, and forbids
modification, adaptation and derivative works, so nothing was decompiled.
Every cell rests on GitHub's ACP server docs, the release notes shipped in
the package's `changelog.json` (cited as "changelog" and a version), and,
for wire names only, the plain strings of the 1.0.98 runtime; no internals
are kept. A name found in the strings shows the runtime knows it, not when
it is sent, so such cells are `◐` or `?`. Every cell is `n`. CHD-432's
`_meta.quota` cell for Copilot (`docs/design/registry-2026-10-17.md`) has
no source; this reading found none, so its cost is `?` (co19).

**Footnotes.**

- **co1.** The docs: `copilot --acp` speaks NDJSON over stdio, or a port
  with `--port`, `initialize` first, in public preview. The protocol number
  and the ACP library are not stated; the method names are v1's.
- **co2.** v1 sessions, modes, config options, list, load, resume and
  close, plus a private `github.com/copilot/sessionEvent` notification
  carrying the runtime's own events (changelog 1.0.81, "raw event
  subscriptions"; runtime strings).
- **co3.** The docs: `initialize`, then a session, then prompts.
- **co4.** Changelog 0.0.410.
- **co5.** Resume is named in the runtime's strings; `--context` is applied
  again on resume (changelog 1.0.95).
- **co6.** `listSessions` and `nextCursor` appear in the strings, also used
  by the runtime's own host protocol, so ACP's list is not confirmed. No
  fork method name was found.
- **co7.** `closeSession` since changelog 1.0.78; no delete was found.
- **co8.** Modes `agent`, `plan` and `autopilot`, each linked to ACP's
  session-modes page; `current_mode_update` named (runtime strings).
  Autopilot is experimental and enables allow-all.
- **co9.** Model changes in a session (changelog 0.0.400); a model option
  with description, usage multiplier and enablement (0.0.403, 1.0.37);
  options sent again when the model changes (1.0.48).
- **co10.** Reasoning effort (changelog 0.0.421), custom agents (1.0.40),
  allow-all (1.0.39, 1.0.60), option descriptions (1.0.62);
  `config_option_update` named (runtime strings).
- **co11.** `--effort` or `--reasoning-effort`, `low` to `max`, sets every
  session's effort (docs, changelog 1.0.60).
- **co12.** Prompts take text (docs). `embeddedContext` is named beside the
  prompt capabilities; image, audio and links are not established.
- **co13.** `rawInput`, `rawOutput`, a diff's `oldText` and `locations` are
  named in the strings; every edit tool sends a diff (changelog 1.0.49).
- **co14.** `allow_once` and `allow_always` with "Allow once" and "Always
  allow" (runtime strings); no reject option name was found. What
  `cancelled` or a timeout does is not known.
- **co15.** SDK clients answer elicitations (changelog 1.0.10, 1.0.14). The
  runtime's strings say its question tool declines when the client cannot
  take elicitation; CHD-1 read that as declining under ACP. Whether a
  client declaring `elicitation.form`, as chord does, gets
  `elicitation/create` is not known.
- **co16.** A live plan since changelog 1.0.40, from its todo list.
- **co17.** A client's cancel aborts the turn (runtime strings); what else
  stops is not known.
- **co18.** "ACP clients receive subagent IDs" (changelog 1.0.81); the shape
  is not known.
- **co19.** `usage_update` named; token usage in prompt results since
  changelog 1.0.78, with thought and cache-write tokens named. No cost was
  found. CHD-432's "✓ `_meta.quota` n" for Copilot has no source in the
  notes, docs or strings read here.
- **co20.** Commands with descriptions and argument hints, skills as
  commands (changelog 1.0.39, 1.0.40); among them `/compact`, `/context`,
  `/usage`, `/plan`, `/review` (docs).
- **co21.** Live title updates (changelog 1.0.81).
- **co22.** One method, `copilot-login`, "Run `copilot login` in the
  terminal", marked `terminal-auth` (runtime strings); `authenticate`
  succeeds only after a Copilot login (changelog 1.0.69). Bring-your-own
  keys go by environment or config (0.0.401).
- **co23.** Servers taken when starting or loading a session (changelog
  1.0.25); MCP OAuth in ACP mode (1.0.14).
- **co24.** `loadSession`, `mcpCapabilities`, `promptCapabilities`,
  `embeddedContext`, `agentInfo` and `authMethods` are named together, and
  `clientCapabilities`; their values and what it reads are not known.

**Custom.**

- `github.com/copilot/sessionEvent`: the runtime's own events beside ACP's
  updates. How a client subscribes is not known; the shape is unpublished
  and the stream drops events when the client falls behind.
- `terminal-auth` on `copilot-login`: a login for the client to run in a
  terminal.
- Launch flags: `--effort`, `--available-tools`, `--excluded-tools`,
  `--context`, `--allow-all-*` or `--yolo`, `--autopilot`, `--port`. Each is
  per process; the registry passes only `--acp`.
- `autopilot` mode and allow-all: no asks reach the person; autopilot
  answers permissions and questions itself (changelog 1.0.64).
- Model metadata, usage multiplier and enablement, on the model option.
- It reads `clientInfo` for usage attribution and turns it off when two
  clients name different editors (runtime strings).

**In chord.** Nothing here was run, so this is what chord would do with what
the notes describe. chord creates, loads and resumes sessions, and never
calls `session/list`. Modes `agent`, `plan` and `autopilot` come as modes;
model, effort and agent as config options, with effort shown only if its
category is `thought_level`; allow-all, if a boolean, is not listed. chord
draws the plan, the context meter, answer usage and commands, and answers
permissions by kind. chord's http MCP server goes in only if Copilot
advertises `mcpCapabilities.http`, which is not known. Copilot's new model
ids are not in genai-prices, so no cost is estimated (CHD-381), and Copilot
bills premium requests, which no token price models. Ignored: titles,
`github.com/copilot/sessionEvent`, subagent ids, `terminal-auth`. Whether
Copilot's questions reach chord as forms, now that chord declares
`elicitation.form`, is open. README.md still says `GitHub Copilot`.

**Sources.**

- `@github/copilot` 1.0.98, npm: `changelog.json`, `LICENSE.md`, and the
  runtime's plain strings for wire names.
- https://docs.github.com/en/copilot/reference/copilot-cli-reference/acp-server
- Release notes 1.0.94-1.0.98, https://github.com/github/copilot-cli/releases
- CHD-432's reading, `docs/design/registry-2026-10-17.md` (co1).

#### glm-acp-agent

- Name: GLM Agent
- Pinned: `glm-acp-agent` 1.15.0
- Run as: `npx -y glm-acp-agent@1.15.0`
- Source: <https://github.com/stefandevo/glm-acp-agent>

Read at 1.15.0, the registry's pin, from the npm package
`glm-acp-agent@1.15.0` (tsc output, plain per-module JS with source maps),
which matches the repository's tag `v1.15.0`. Cites are relative to the
package root; `sdk/` stands for the package `@agentclientprotocol/sdk@0.20.0`.
Apache-2.0, so nothing limits reading it. glm is pinned to that old pre-1.0
SDK: `^0.20.0` allows only 0.20.x, and the tag's lock resolves 0.20.0, while
chord is on 1.8.0. It has no `_meta` and no extension method anywhere.

**Footnotes.**

- **gl1.** `dist/protocol/agent.js:170` answers the client's version when it
  is at most the SDK's, else the SDK's; `sdk/dist/schema/index.js:44` has
  `PROTOCOL_VERSION = 1`. chord sends 1. A client sending 0 gets 0 back.
- **gl2.** `package.json` `^0.20.0`; the repository's `package-lock.json` at
  `v1.15.0` resolves 0.20.0. Transport `AgentSideConnection` on
  `ndJsonStream` (`dist/protocol/connection.js:2,23-24`).
- **gl3.** Stable v1 methods plus, unstable in SDK 0.20, `session/fork`,
  `session/set_model`, the `env_var` auth method and the `userMessageId`
  echo (`sdk/dist/acp.js:61,108`;
  `dist/protocol/agent.js:194-206,337,601-609,1043`).
- **gl4.** `dist/protocol/agent.js:240-306` answers `models`, `modes` and
  `configOptions`. Any MCP server whose client creation or `listTools` fails
  rejects the whole call (`dist/tools/session-mcp-client.js:85-101,131-134`).
- **gl5.** Load replays user and assistant text only, no tool calls and no
  thoughts (`dist/protocol/agent.js:1636-1686`, comment at `:1676`). Resume
  restores with no replay (`:1201-1203`).
- **gl6.** `dist/protocol/agent.js:997-1037`: disk store merged with memory,
  `cwd` filter, newest first, `title` and `updatedAt`, no `nextCursor`.
- **gl7.** `dist/protocol/agent.js:1043-1061`: copies the whole session, no
  fork point, and aborts the source's running prompt first.
- **gl8.** `session/close` at `dist/protocol/agent.js:797`; SDK 0.20 has no
  delete method.
- **gl9.** From the registry study (`docs/design/registry-2026-10-17.md`
  §2): `default`, `accept_edits`, `bypass_permissions`.
- **gl10.** The registry study §2: a `models` state, `session/set_model`,
  and the `model` config option.
- **gl11.** `dist/protocol/agent.js:412-453`: three select options with
  categories `thought_level`, `mode`, `model`. Levels depend on the model and
  are clamped on a switch (`dist/llm/glm-client.js:66-91`); the default is
  the model's highest (`agent.js:264`).
- **gl12.** `dist/protocol/agent.js:2083-2160`. Images are off when
  `ACP_GLM_PROMPT_IMAGES` is `false` or `0`; a model without vision gets them
  through `npx @z_ai/mcp-server@latest`
  (`dist/tools/vision-mcp-client.js:129-138`).
  Audio becomes the text `[unsupported audio block]`; a resource blob becomes
  a link line; a `resource_link` becomes `[name](uri)`, nothing fetched.
- **gl13.** `dist/tools/executor.js` (kinds and statuses at `:287-293`,
  `:793-809`, `:1266-1301`, among others). Never `delete`, `move`, `search`,
  `think` or `switch_mode`. rawInput and rawOutput cut strings over 240
  characters (`:18-33,90-110`); the permission request carries the full
  rawInput (`:1191-1194`). Content is text only, capped at 16 KiB: no `diff`
  for write or edit, no `terminal`. Asking calls go `pending`, then
  `in_progress`, then `completed` or `failed`; others start `in_progress`.
- **gl14.** The registry study §2, and `dist/tools/executor.js:1168-1245`:
  `allow_once` "Allow" and `reject_once` "Skip"; any outcome but allow is a
  reject, and the request is dropped when the turn aborts.
- **gl15.** The registry study §2 and `docs/design/CHD-1.md`: it never asks.
- **gl16.** The registry study's gl4: `todowrite` is a completed `other` call.
- **gl17.** `dist/protocol/agent.js:793-796` aborts the turn's controller:
  the model stream, a pending permission, fs reads in flight.
- **gl18.** `dist/protocol/agent.js:581-583,599-618`: a concurrent
  `session/prompt` aborts the running turn, which answers `cancelled`, then
  runs. No `_session/steering`.
- **gl19.** The registry study §2: no subagents.
- **gl20.** No `usage_update`. `PromptResponse.usage` sums every model call
  of the turn, a cancelled one too: input, output, total, cache, thought
  (`dist/protocol/agent.js:691-694,1697-1712`). No cost.
- **gl21.** `dist/protocol/agent.js:308-335` sends the list on the next tick
  after new, load, resume or fork; `dist/protocol/slash-commands.js:1-40`
  reads `.claude/commands/**.md` and `.claude/skills/*/SKILL.md` under the
  cwd and the home directory, up to 200. The agent expands `/name` itself.
- **gl22.** `dist/protocol/agent.js:668-690`: after each turn that ends
  normally, `updatedAt`, and `title` the first time (the first prompt's first
  80 characters); `updatedAt` also on a model change (`:379-386`).
- **gl23.** The registry study's gl3: methods `z-ai-api-key` (agent) and
  `env_var` `Z_AI_API_KEY`; `authenticate` does nothing.
- **gl24.** `dist/tools/executor.js:496-560`: `fs/read_text_file` and
  `fs/write_text_file` only when the client declares them; commands run
  locally (`:818-863`), never `terminal/*`.
- **gl25.** `dist/tools/session-mcp-client.js:138-145`: `http` and stdio
  taken, `sse` throws "not supported yet", which fails session/new, load and
  resume as a whole (`:85-101`).
- **gl26.** `dist/protocol/agent.js:208-229`: `loadSession`,
  `mcpCapabilities.http`, `promptCapabilities {embeddedContext, image}`,
  `sessionCapabilities {close, list, fork, resume}`. No `_meta`.
- **gl27.** `dist/tools/executor.js:300,497,512-513,523` read only
  `fs.readTextFile` and `fs.writeTextFile`; the rest is stored, never read.

**Custom.**

- A concurrent `session/prompt` aborts the running turn (gl18). A client gets
  it by sending one; the turn ends `cancelled` with its tool work cut.
- `session/fork` aborts the source's running turn (gl7); forking a busy
  session cancels it.
- Claude Code's command and skill folders read as slash commands (gl21). It
  reads the person's own `.claude` tree, and inlines a body of up to 16 KiB.
- `AGENTS.md` or `CLAUDE.md` goes into the system prompt, up to 8 KiB
  (`dist/protocol/agent.js:29-33`): input tokens every turn.
- `web_search`, `web_reader` and vision call Z.AI services
  (`dist/tools/zai-mcp-client.js:6-7`): spend on the Z.AI plan, and vision
  installs `@z_ai/mcp-server@latest` from npm at run time, unpinned.
- `ACP_GLM_*` variables, `Z_AI_API_KEY` and `--max-turns` tune it; a client
  must set them itself. The turn cap answers `max_turn_requests`.
- A `messageId` is echoed as `userMessageId` (unstable); nothing to pay.

**In chord.** chord asks for version 1 and gets it, and adds its own http MCP
server because glm offers `mcpCapabilities.http`. It also passes the person's
MCP servers as they are: one `sse` entry, or any server whose tool listing
fails, chord's own included, fails glm's session/new, load or resume as a
whole. chord reopens with resume when it holds a record, else load, which
replays text only. Model, effort and mode come from glm's config options.
Usage comes only in the prompt answer, so there is no live meter; there is
no cost, so chord estimates one. Edits arrive with no diff, only a title,
paths and an elided rawInput, and rawOutput is never drawn. @ mentions reach
the model as `[name](uri)`, so it opens files with its own tool. chord queues
a mid-turn prompt, which keeps glm from aborting the running turn. chord
drops glm's `session_info_update` titles, never calls `session/list`, fork
or close, sends no `messageId`, and declares no `fs`, so glm edits on disk
itself.

**Sources.**

- npm `glm-acp-agent@1.15.0`; <https://github.com/stefandevo/glm-acp-agent>,
  tag `v1.15.0`.
- npm `@agentclientprotocol/sdk@0.20.0`.
- `docs/design/registry-2026-10-17.md` (CHD-432), `docs/design/CHD-1.md`.

#### grok-build

- Name: Grok Build
- Pinned: `@xai-official/grok` 1.0.63
- Run as: `npx -y @xai-official/grok@1.0.63 agent stdio`
- Source: <https://x.ai/cli>

Read at two versions, kept apart. The registry pins `@xai-official/grok`
1.0.63 (2026-10-17), a JavaScript wrapper that unpacks a native Rust binary
from `@xai-official/grok-<platform>`. The last public source is 1.0.45, at
https://github.com/xai-org/grok-build main `2bdd1d6a` (2026-09-29); nothing
after it is published as source. Cells marked `c` were read in that 1.0.45
source and checked against the 1.0.63 binary's strings: the darwin-arm64
binary was read as plain text only, never run, disassembled or decoded. The
binary embeds grok's user guide as markdown, and where the guide or x.ai's
per-version release notes (1.0.46 to 1.0.63) state a fact, they are cited
first. Apache-2.0 for the wrapper, the platform packages and the source, so
reading is not restricted; only wire facts are taken from the binary. Paths
are relative to the 1.0.45 repository, under
`crates/codegen/xai-grok-shell/src/` unless they begin with `crates/`. This
part corrects CHD-432's gr4 and `docs/design/CHD-1.md:41`: grok's question
request is on by default, not opt-in.

**Footnotes.**

- **gr1.** `initialize` answers version 1 whatever is asked
  (`agent/mvp_agent/acp_agent.rs:566`); the guide's TypeScript client sends 1.
- **gr2.** `agent-client-protocol` 0.10.4 with feature `unstable`, schema
  crate 0.11.4 (`Cargo.toml:123`, `Cargo.lock`). The 1.0.63 strings still
  name crate 0.10.4; the schema version is not visible there.
- **gr3.** v1 methods plus unstable `session/resume`, `session/close` and
  `session/set_model`; no `session/fork`, no `elicitation/create`, no
  `usage_update` (`agent/mvp_agent/acp_agent.rs:125-2381`). Over 300 `x.ai/*`
  extension names, sent with a leading `_`; the guide calls the set
  non-exhaustive and to be discovered from `initialize`.
- **gr4.** Answers `models`, `configOptions` and a large `_meta`, and no
  `modes` (`agent/mvp_agent/session_setup.rs:888-921`).
- **gr5.** Load replays the history and re-asks a pending plan approval
  (`agent/mvp_agent/session_setup.rs:1370-1392`). Resume refuses chat
  sessions and `additionalDirectories` (`:1997-2018`).
- **gr6.** `sessionCapabilities` close always, list and resume outside chat
  mode (`agent/mvp_agent/acp_agent.rs:552-560`); 1.0.51 notes: "supports
  listing sessions via ACP". Fork, delete and rename are `x.ai/session/*`
  methods (`:2035-2036`), still in 1.0.63's strings.
- **gr7.** No `availableModes` in any answer, yet `session/set_mode` takes
  `plan` and `default` and sends `current_mode_update`, also when the model
  enters plan mode itself (`session/acp_session_impl/session_mode.rs:44-56`).
- **gr8.** Unstable `models` and `session/set_model`. With no list, the
  public `Auto` id is used (1.0.51 notes), which has no price (CHD-432 gr2).
- **gr9.** Guide, "Session config options": `model` (category `model`) and
  `reasoning_effort` (`thought_level`: `minimal`, `low`, `medium`, `high`,
  `xhigh`, only for a model with `supportsReasoningEffort`); the answer is
  the complete list, mirrored by `config_option_update`; boolean values are
  refused. Source: `agent/session_config.rs:15-16, 111`.
- **gr10.** Images are accepted but `promptCapabilities.image` is not set;
  audio is refused with `invalid_params`; a `resource_link` with no `_meta`
  is also put into the text as `@path` and expanded as a file reference
  (`session/prompt_parser.rs:131-150`).
- **gr11.** Kinds `read`, `edit`, `search`, `execute`, `fetch`, `think`,
  `other`. rawInput on every call; rawOutput for shell and some other tools;
  locations for file tools; `pending`, `in_progress`, then `completed` or
  `failed` (`session/acp_session_impl/tool_calls.rs:2321-2741`). Every
  update's `_meta` carries `totalTokens`, `promptId` and more
  (`session/acp_session_impl/updates.rs:282-315`).
- **gr12.** Text and `diff` (`session/acp_conversion.rs:1235`); no `terminal`
  content anywhere.
- **gr13.** `allow_once`, `allow_always`, `reject_once`, `reject_always` by
  prompt type (`crates/codegen/xai-grok-workspace/src/permission/prompter.rs`);
  web fetches get always and never allow-domain options (1.0.51 notes).
- **gr14.** A `cancelled` answer is cancelled
  (`crates/codegen/xai-grok-workspace/src/permission/prompter.rs:783`). The
  1.0.63 strings describe a backstop deadline that times an unanswered
  permission request out, and a re-send when the client re-attaches; the
  length is not visible.
- **gr15.** No ACP elicitation. MCP servers' form and URL elicitation is
  relayed as `x.ai/mcp/elicit` (`session/mcp_elicitation.rs:59-140`).
- **gr16.** The todo tool sends `plan` updates
  (`session/acp_session_impl/tool_calls.rs:3050`).
- **gr17.** `session/cancel` stops subagents too unless
  `_meta.cancelSubagents: false`; opt-in `_meta.rewindIfNoOutput`
  (`agent/mvp_agent/acp_agent.rs:1878-1943`). 1.0.51 notes: a cancel no
  longer reverts workspace files.
- **gr18.** A concurrent `session/prompt` is queued by grok;
  `_meta.sendNow: true` sends it now and may cancel the running turn;
  `x.ai/queue/interject` turns a queued prompt into an interjection
  (`agent/mvp_agent/acp_agent.rs:1204-1209, 1392-1418`). No
  `_session/steering`.
- **gr19.** `x.ai/session_notification` on the parent's session id with
  `subagent_spawned`, `subagent_progress` and `subagent_finished`, whose
  subagent id is the child's session id (`agent/subagent/spawn.rs:570-598`).
  Stop one with `x.ai/subagent/cancel` or `x.ai/task/kill`.
- **gr20.** No `usage_update` and no `PromptResponse.usage`. Usage and cost
  exist only in `PromptResponse._meta`: tokens of the last model call, and
  `usage` for the whole prompt with `costUsdTicks`, 1e10 ticks to the dollar,
  left out when partial (`agent/mvp_agent/acp_agent.rs:1740-1760`,
  `extensions/notification.rs:104`). The guide's `grok usage` gives the same
  tick unit.
- **gr21.** Sent at start, on load and when skills or workflows change;
  `_meta.tools` lists tool names (`session/acp_session_impl/session_setup.rs:246-300`).
- **gr22.** `title` on automatic and manual renames, with
  `_meta["x.ai/titleIsManual"]` (`session/summary.rs:126-185`).
- **gr23.** `xai.api_key`, `cached_token`, `grok.com` and `oidc`, all of
  type `agent`; the default is in `initialize._meta.defaultAuthMethodId`
  (`agent/auth_method.rs:330-382`). Whether `session/new` works without
  `authenticate` was not read.
- **gr24.** `fs/*` only when both fs capabilities are declared, `terminal/*`
  only with `terminal`; otherwise its own files and PTY
  (`agent/mvp_agent/agent_ops.rs:4193-4234`).
- **gr25.** `mcpCapabilities` http and sse (`agent/mvp_agent/acp_agent.rs:578-580`).
- **gr26.** `loadSession`, `embeddedContext`, MCP http and sse,
  `sessionCapabilities` close, list and resume, and `_meta` with hooks and
  tool overrides (`agent/mvp_agent/acp_agent.rs:552-583`); 1.0.63's strings
  have the same `_meta` keys.
- **gr27.** `fs` (read and write together) and `terminal`, plus `_meta` keys
  such as `x.ai/fs_notify` and `x.ai/folderTrust`
  (`agent/mvp_agent/agent_ops.rs:4114-4285`). `elicitation`, `plan`,
  `subagents` and `session` are never read.

**Custom.**

- `x.ai/ask_user_question`, agent to client: the model's question tool, with
  `questions` and a `mode`. It is on by default: the guide's config table
  gives `features.ask_user_question` "Default true", also
  `GROK_ASK_USER_QUESTION`. Only `session/new` `_meta.askUserQuestion: false`
  takes the tool away (`agent/mvp_agent/agent_ops.rs:4689-4697`); the key is
  in 1.0.63's strings. A method-not-found becomes a tool error to the model,
  and the person never sees the question
  (`crates/codegen/xai-grok-tools/src/implementations/grok_build/ask_user_question/mod.rs:484-497`).
  The guide sets a 30-minute answer timeout by default.
- `x.ai/exit_plan_mode`, agent to client: plan approval, answered approved,
  abandoned or revise. No opt-in. Any error but a failed send,
  method-not-found included, ends the turn as cancelled with grok still in
  plan mode (`session/acp_session_impl/tool_calls.rs:2014-2215`). The guide
  says the model's `enter_plan_mode` asks the person first; 1.0.45 did not.
- `x.ai/session_notification`: about 60 kinds, among them subagents, turn
  usage, retries, compaction and model switches. Sent to every client.
- `x.ai/mcp/elicit`: MCP servers' forms; a failure cancels them toward the
  server.
- `PromptResponse._meta`: tokens and `costUsdTicks` (gr20).
- `_meta` on `session/new` (guide): `rules`, `systemPromptOverride`,
  `agentProfile`, `yoloMode`, `autoMode`; also `askUserQuestion`. On the
  prompt `sendNow`, on the cancel `cancelSubagents`.
- Client-to-agent methods for queue, fork, delete, rename, rewind and
  subagent stops; `x.ai/requestingSessionId` on permission requests (1.0.52).
- Launch flags `--always-approve`, `-m`, `--no-subagents`, and env
  `GROK_CONFIG`, `XAI_API_KEY` (guide); the registry passes only
  `agent stdio`.

**In chord.** chord starts grok, adds its own MCP server over http, reopens
with resume, and takes models and effort from the config options. grok uses
its own files and PTY, as chord declares neither. Questions break: the
question tool is on by default, chord answers it method-not-found, and the
model gets an error while the person sees nothing. If grok enters plan mode,
its plan approval gets method-not-found and the turn ends cancelled with grok
still in plan mode. grok sends `current_mode_update` without offering modes;
how chord draws that was not checked. Images are never sent, as grok does not
advertise them. A mention reaches grok both as chord's text and as an
`@path` it expands. chord shows no agent usage or cost: grok's are only in
`PromptResponse._meta`, which chord does not read, and its estimate has no
price for `Auto`. Titles, subagent events, MCP elicitation and the other
`x.ai/*` traffic are dropped. A background subagent's approval with no turn
running is refused (CHD-158). chord queues a mid-turn prompt itself, never
calls `session/list` or `authenticate`, and leaves close, fork and delete
unused.

**Sources.**

- `@xai-official/grok` and `@xai-official/grok-darwin-arm64` 1.0.63 on
  npm, with the user guide embedded in the binary.
- https://github.com/xai-org/grok-build at `2bdd1d6a` (1.0.45).
- x.ai's Grok Build release notes, 1.0.46 to 1.0.63.
- `agent-client-protocol` 0.10.4 and `agent-client-protocol-schema` 0.11.4
  on crates.io.

#### kilo

- Name: Kilo
- Pinned: `@kilocode/cli` 7.8.12
- Run as: `npx -y @kilocode/cli@7.8.12 acp`
- Source: <https://github.com/Kilo-Org/kilocode>

Kilo CLI 7.8.12, the registry pin (`@kilocode/cli`), read at tag `v7.8.12` of
<https://github.com/Kilo-Org/kilocode> (MIT, a fork of opencode, no limits on
reading). The ACP layer is `packages/opencode/src/acp/` with
`packages/opencode/src/kilocode/acp/`, started in process by
`packages/opencode/src/cli/cmd/acp.ts`. Paths are relative to
`packages/opencode/src/` unless they start with `packages/`. Cells marked `r`
are CHD-432's reading at 7.8.8; no ACP path changed up to 7.8.12. The
terminal login it names is opencode's command, not kilo's.

**Footnotes.**

- **ki1.** `acp/service.ts:94-141`: `protocolVersion: 1` (`:114`);
  `loadSession`, `mcpCapabilities {http, sse}`,
  `promptCapabilities {embeddedContext, image}`, `sessionCapabilities {close,
  fork, list, resume}`; `agentInfo {name: "Kilo"}`. One auth method,
  `kilo-login`, described as "Run `kilo auth login` in the terminal"
  (`:97-101`). The only client capability read is
  `_meta["terminal-auth"]`, which adds a `terminal-auth` `_meta` naming
  `command: "opencode", args: ["auth", "login"]` (`:104-112`).
- **ki2.** `packages/opencode/package.json:72`, `"0.21.0"`, exact.
- **ki3.** `acp/agent.ts:33-85` handles `initialize`, `authenticate`, new,
  load, list, resume, close, `unstable_forkSession`, the three setters with
  `unstable_setSessionModel`, `prompt` and `cancel`; no `_` methods.
- **ki4.** CHD-432: load replays every message (`acp/service.ts:213-246`),
  resume replays nothing (`:294-330`), close drops the session from the
  connection and aborts it (`:343-351`). No delete.
- **ki5.** `acp/service.ts:248-292`: 100 root sessions a page with a time
  cursor, each with its `title` (`:266`).
- **ki6.** `acp/service.ts:358-401`: a server-side copy that replays its last
  20 messages; MCP servers are registered for new, load and resume only
  (`:198`, `:235`, `:320`), not for a fork.
- **ki7.** CHD-432: only `configOptions` in the answers, no `models` or
  `modes` field (`acp/service.ts:200-209`); `session/set_mode` and
  `unstable_setSessionModel` work too (`:459-482`). No
  `current_mode_update` or `config_option_update` is ever sent.
- **ki8.** `acp/config-option.ts:38-41`, `:59-63`, `:77-80`: `model`
  (category `model`), `effort` (category `thought_level`, the model's
  variants, absent when it has none), `mode` (category `mode`, the server's
  agents).
- **ki9.** `acp/content.ts:29-115`: image as base64, `data:` or http(s) uri;
  audio dropped (not advertised); a text resource inlined as `[uri]` and its
  text, a blob as a file; a `file://` or `zed://` link becomes a file part,
  any other its uri as text (`:152-186`).
- **ki10.** Kinds `execute fetch edit search read think other`
  (`acp/tool.ts:40-69`); locations from file path, shell workdir or search
  path (`:72-100`); shell `rawInput` gains its workdir (`:270-272`); the end
  carries `content` and `rawOutput` (`:186-198`); edits as diffs
  (`:324-337`). A running `bash` call repeats its whole output so far as text
  content (`acp/event.ts:390-426`), not an ACP terminal.
- **ki11.** CHD-432: `allow_once`, `allow_always` (kept in the server's
  store) and `reject_once` (`acp/permission.ts:21-25`); skill shell batches
  and sandbox escalations offer once and reject only
  (`kilocode/acp/permission.ts:5-8`). A cancelled answer rejects.
- **ki12.** CHD-432: the `question` tool is off for `acp` clients unless
  `KILO_ENABLE_QUESTION_TOOL` is set (`tool/registry.ts:272`, `:313`), and the
  ACP layer has no handler for its events (`acp/event.ts:109-125`).
- **ki13.** CHD-432: no `plan` update in `acp/`.
- **ki14.** `acp/service.ts:353-357` aborts the session's run.
- **ki15.** CHD-432: no `_session/steering`. A concurrent `session/prompt` is
  queued and the running turn stops at its next step boundary, "superseded"
  (`session/prompt.ts:1487-1514`, `:1952-1964`).
- **ki16.** CHD-432: `task` is one call of kind `think` (`acp/tool.ts:65-66`);
  the child session is not in the ACP map, so its parts and its permission
  asks are dropped (`acp/event.ts:243-244`, `acp/permission.ts:54-55`).
- **ki17.** CHD-432: `usage_update` once the turn ends, with `cost` as the
  whole session's sum in USD, skipped when the context limit is unknown
  (`acp/usage.ts:205-221`); `PromptResponse.usage` carries token counts
  (`acp/service.ts:826-843`).
- **ki18.** `acp/service.ts:937-955`, after new, load and resume, as
  `{name, description}` with no `input`.
- **ki19.** No `session_info_update` in `acp/`; titles only in
  `session/list` (`acp/service.ts:266`).
- **ki20.** `authenticate` accepts `kilo-login` and does nothing
  (`acp/service.ts:143-148`); see ki1 for the terminal command.
- **ki21.** CHD-432: after an approved edit the agent sends
  `fs/write_text_file` without checking `clientCapabilities.fs`, fire and
  forget, before passing the approval on (`acp/permission.ts:93-97`,
  `:110-126`). Never `fs/read_text_file` or `terminal/*`.
- **ki22.** `acp/service.ts:1015-1028`: an entry with a `type` becomes one
  `remote` server (http and sse alike), one without a `local` command.
- **ki23.** Four, each a bullet under Custom below.

**Custom.**

- `_meta["terminal-auth"]` on the auth method: a command to log in from a
  terminal, given when the client sends
  `clientCapabilities._meta["terminal-auth"] = true`. It names
  `opencode auth login`, while the package installs `kilo` and `kilocode`
  (`packages/opencode/package.json:19-22`), so a client running it starts
  another program or none.
- `fs/write_text_file` after an approved edit, undeclared: an editor client
  sees the write. A client that declares no `fs` answers method-not-found;
  the agent ignores the answer, so nothing waits on it.
- `KILO_ENABLE_QUESTION_TOOL`: gives the model its `question` tool, but no
  question reaches an ACP client.
- Supersede-on-prompt: a second `session/prompt` redirects the turn at the
  next step. Not ACP steering.

**In chord.** chord uses new, load and resume (resume when it has its own
record), the `model`, `effort` and `mode` options, `usage_update` and
`PromptResponse.usage`, `available_commands_update`, permissions, images,
and offers its own http MCP server. @-mentions go as `resource_link` and
kilo reads them as files, so they reach the model. Every approved edit
brings an `fs/write_text_file` that chord refuses with method-not-found;
the edit itself is not lost. A mode or model kilo changes on its own is
never reported, so the status line can lag. The cost is the session's sum,
which is what ACP's `usage_update` means; a free model's 0 stops chord's
estimate (CHD-380). A subagent's own asks are dropped by kilo, so a `task`
that needs approval is never shown to the person. chord ignores list, fork,
close, the titles and `terminal-auth`.

**Sources.**

- Kilo `v7.8.12`, <https://github.com/Kilo-Org/kilocode/tree/v7.8.12>;
  `@kilocode/cli` 7.8.12 on npm.
- CHD-432's notes in
  [`design/registry-2026-10-17.md`](design/registry-2026-10-17.md)
  (ki1–ki7).

#### minimax-code

- Name: MiniMax Code
- Pinned: `@minimax-ai/code` 0.2.7
- Run as: `npx -y @minimax-ai/code@0.2.7 acp`
- Source: <https://agent.minimax.io>

`@minimax-ai/code` 0.2.7, the registry pin, published 2026-08-28; npm's
`latest` is 0.6.12, which was not read. Read from the npm package (MIT,
nothing obfuscated). The ACP server is `chunks/run-acp-command-X52GQQTB.js`,
minified with the SDK bundled in; `L<n>` below is a line of that file once
laid out by Prettier with default options. Notes named "the registry page's
mmN" are CHD-432's in
[`design/registry-2026-10-17.md`](design/registry-2026-10-17.md).

**Footnotes.**

- **mm1.** `initialize` answers the constant `1` (L82, L17873) whatever the
  client asks.
- **mm2.** The bundled method tables (L36-82) match
  `@agentclientprotocol/sdk` 1.0.0 to 1.4.0, with the client methods
  `mcp/connect` and `mcp/disconnect` that 1.8.0 dropped; handlers use 1.x's
  `onRequest` builder. The package predates 1.5, so the SDK is at most
  1.4.0; the patch release was not pinned down.
- **mm3.** Unstable in 1.4.0's schema and used: `session/fork` (L18047) and
  `plan_update` (L18683). The only client calls are `session/update`,
  `session/request_permission` and `elicitation/create` (L17216, L17249,
  L17673); `mcp/connect` is unused.
- **mm4.** Every session call fails `auth_required` without a login (the
  registry page's mm8 notes). A creation over the concurrency limit is
  refused `requestCancelled` (L17912); `additionalDirectories` is refused.
- **mm5.** Load replays history; load, resume and fork work only from the
  session's stored cwd (CHD-432's reading).
- **mm6.** Lists archived sessions, leaves out subagent sessions.
- **mm7.** `session/close` drops the attachment, aborts the prompt and
  clears the session's MCP servers (L18266-18287). No delete handler, so the
  SDK answers method-not-found.
- **mm8.** Legacy modes `default` and `plan`, plan only when the runtime
  allows it. The `set_mode` answer carries
  `_meta["minimax-code/transition"]: "next_prompt"` (L18312).
- **mm9.** The `model` config option; no `models` field. SDK 1.x has no
  `session/set_model` route (L36-63).
- **mm10.** `model`, `thinkingEffort` (`thought_level`, per model) and
  `permissionMode` (category `_permission`, scope `process`, L16239).
- **mm11.** `gS` (L19271-19282) keeps text and turns a `resource_link` into
  "Referenced resource: <name> (<uri>)" without fetching it; any other block
  is `invalid_params`.
- **mm12.** `Cd` (L16752) guesses the kind from substrings of the tool name.
  Each `tool_call` has a non-standard `name` (L16743). A diff is rebuilt from
  hunk and context lines, so `oldText`/`newText` are excerpts
  (L16815-16833); other content is file or summary text. Shell output is
  only in `rawOutput`.
- **mm13.** `gx` maps to `pending`, `in_progress`, `completed`, `failed`
  (L16772-16781). A call with no runtime id gets `minimax-code-tool-<n>`,
  restarting each turn (the registry page's mm7).
- **mm14.** `Nx` (L17212-17237) reads only `allow-once` and `allow-always`;
  anything else, `cancelled` included, is deny. A request resolved elsewhere
  is withdrawn by `$/cancel_request` (L17200). Its `toolCallId` is the
  runtime's request id, not the call's (the registry page's mm4).
- **mm15.** Form when `elicitation.form` is declared (L17245), with
  `<id>__other` for Other; otherwise only the first step, as a permission.
- **mm16.** A markdown `plan_update` by id for plan review, under
  `clientCapabilities.plan` (L18656); no entries.
- **mm17.** Cancel aborts the prompt's controller and the coordinator
  (L18591-18604); a cancel with no turn makes the next prompt answer
  `cancelled` at once. Whether delegated children stop was not read.
- **mm18.** A second `session/prompt` is refused `invalid_params` "A prompt
  is already active" (L18438-18442). `mcode/session/steer` steers text in
  (L16395-16436).
- **mm19.** Subagents are internal sessions, seen only through
  `mcode/session/delegation_update`; their asks go to the root session. Only
  the whole delegation can be stopped.
- **mm20.** `usage_update` with `used`, `size` and `cost` in USD after each
  prompt; no `PromptResponse.usage`.
- **mm21.** Ten commands (L15867-15878, L19067-19078), sent twice after new,
  load, resume or fork; the adapter answers them itself as one message chunk
  (L18446-18458).
- **mm22.** `title` and `updatedAt` on runtime events, also outside a turn
  (L18612-18633).
- **mm23.** `minimax-code-login`, `type: "terminal"`, args `["login"]`
  (L17880-17890), sent only when the client declares `auth.terminal` or
  `_meta["terminal-auth"]` (L17871).
- **mm24.** No `fs/*` or `terminal/*` call (see mm3).
- **mm25.** `qd` (L19032-19066) passes stdio, http and sse on; any other
  transport is `invalid_params`.
- **mm26.** L17868-17905: `loadSession`, `mcpCapabilities {http, sse}`, all
  prompt flags false, `sessionCapabilities {list, fork, resume, close}`,
  plus `_meta["minimax-code/extensions"]`.
- **mm27.** `clientCapabilities` is read at L17871 (auth), L17245
  (`elicitation.form`), L18656 (`plan`) and L16556 (the extensions key).
- **mm28.** Five, each a bullet under Custom below.

**Custom.**

- `mcode/session/*` notifications (delegation, queue, goal, current
  session): subagent activity and server-side state. A client declares
  `clientCapabilities._meta["minimax-code/extensions"]` (L16556) and reads
  private shapes; without it, subagent work is invisible but for its asks.
- `mcode/session/steer`, `queue/*`, `goal/*`, `delegation/{get,stop}` and
  `session/activate`: steering text into a turn, a follow-up queue, goals
  with a token budget, a stop of the whole delegation. Always registered;
  a client calls private methods. Goals can spend against a budget.
- `permissionMode` option: default, auto or bypass from the client. It is
  process-wide, so a change in one tab reaches every attached session.
- `next_prompt` transition `_meta` on `set_mode`: says when the mode
  applies. A client must hold its label until the next prompt.
- Off-spec: the `name` on `tool_call`, the permission's runtime id, and the
  one-step fallback for questions. A client cannot tie an ask to its card.

**In chord.** chord resumes when it has a record and loads otherwise; it
never calls list, fork or close. Modes, the `model` and `thinkingEffort`
options, and `permissionMode` in `/config` work; the mode label runs ahead
of the next-prompt switch. chord declares the form capability, so questions
come as real forms, and `plan`, so the markdown plan is drawn as reply text.
The agent's cost stops chord's estimate. chord's own MCP server goes in
over http (`mcpCapabilities.http` is true; CHD-432's table left the cell
blank). What reads wrong: a permission is not tied to its card, shell output
only in `rawOutput` is not drawn, and restarted tool ids land on old cards.
Titles, every `mcode/*` extension and the login method are ignored; chord
declares no terminal auth, so `authMethods` never arrives, and without a
prior login the start fails. chord queues its own mid-turn prompts, so the
refusal is not hit, and `session/set_model` is never reached.

**Sources.**

- `@minimax-ai/code` 0.2.7 on npm.
- `@agentclientprotocol/sdk` 1.0.0 to 1.4.0 on npm, for the method tables
  and the schema's stability marks.
- CHD-432's notes in
  [`design/registry-2026-10-17.md`](design/registry-2026-10-17.md).

#### minion-code

- Name: Minion Code
- Pinned: `minion-code` 0.1.44
- Run as: `uvx minion-code@0.1.44 acp`
- Source: <https://github.com/femto/minion-code>

`minion-code` 0.1.44, the registry pin, uploaded to PyPI 2026-03-15; the
newest, 0.1.45 (2026-10-05), was read for its metadata only. Read from the
PyPI wheel, plain Python source with no restriction met; paths are relative
to the wheel root, and SDK paths to the `agent-client-protocol` wheel of
the version named. The pin likely does not start under `uvx` today (mi2).
That is inferred from code and a dependency resolution that installed and
ran nothing; the agent was not run. The cells describe 0.1.44 on
`agent-client-protocol` 0.8.1, the newest it can import. Upstream is
<https://github.com/femto/minion-code>. Notes named "the registry page's
miN" are CHD-432's in
[`design/registry-2026-10-17.md`](design/registry-2026-10-17.md).

**Footnotes.**

- **mi1.** `min(client's, PROTOCOL_VERSION)`
  (`minion_code/acp_server/agent.py:142`), which is 1 in 0.8.1
  (`acp/meta.py:28`) and 0.12.1.
- **mi2.** `agent-client-protocol>=0.7.0`, no upper bound
  (`minion_code-0.1.44.dist-info/METADATA:13`). On 2026-10-18 `uv pip
  compile` resolves 0.12.1. `acp_server/agent.py:24-55` imports
  `AuthMethod`, `ModelInfo`, `SessionModelState` and
  `SetSessionModelResponse` from `acp.schema` at module level, and
  `acp_server/main.py:46` imports that module at module level. 0.12.1 has
  none of the four (`acp/schema.py:991-1073` has `AuthMethodAgent` and
  kin, and no module `__getattr__`); `AuthMethod` went in 0.9.0, the model
  types in 0.11, and 0.8.1 is the last with all four (`acp/schema.py:33`).
  So `minion-code acp` should die with an `ImportError` before
  `initialize`. A uv cache from the 0.8.1 days could still start it.
  0.1.45 requires `agent-client-protocol>=0.12.1`.
- **mi3.** `run_agent` is called without `use_unstable_protocol`
  (`acp_server/main.py:208`). 0.8.1 routes list, `set_model`, fork and
  resume as unstable (`acp/agent/router.py:40`, `:50-56`, `:71-72`), and
  then answers method-not-found (`acp/router.py:38-42`). This corrects the
  registry page's mi2 and mi3: the handlers that answer without doing
  anything are never reached.
- **mi4.** `auth_required` without OpenRouter credentials or
  `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` or `OPENROUTER_API_KEY` (CHD-432's
  reading).
- **mi5.** `loadSession` is not advertised; the handler finds only
  in-memory sessions. No close or delete handler.
- **mi6.** Five legacy modes, `default` to `bypass-permissions`, with
  `current_mode_update`.
- **mi7.** The legacy `models` field comes only after an OpenRouter login.
  `session/set_model` is method-not-found (mi3); 0.12.1 has no route for it.
- **mi8.** `acp_server/agent.py:361-373` joins text blocks with `\n` and
  drops every other block silently.
- **mi9.** `TOOL_KIND_MAP` (`acp_server/hooks.py:37-53`): `read`, `edit`,
  `search`, `execute`, `fetch`, `think`, else `other`. Output goes only to
  `rawOutput`, at the end. Content only for Python code calls. A permission
  carries a fresh `toolCallId` titled `Permission: <tool>`.
- **mi10.** `in_progress`, then `completed` or `failed`.
- **mi11.** It fails open: a `cancelled` answer, which chord sends on Esc,
  or an exception counts as allow. No timeout.
- **mi12.** No plan update.
- **mi13.** Cancel sets an event checked only between stream chunks
  (`acp_server/agent.py:448-453`), so a running tool goes on; background
  `bash`, `TaskCreate` and subagents are not stopped.
- **mi14.** `prompt` clears the cancel event and runs another
  `run_prompt` on the same agent, with no lock (`acp_server/agent.py:345-381`).
  An exception becomes "Error: …" text with `stopReason: "refusal"`
  (`:382-390`), as does an unknown session id (`:351-354`).
- **mi15.** Subagents run inside one `TaskCreate` call; the children send
  nothing and never ask permission.
- **mi16.** `openrouter-oauth`, no `type`, `_meta {"agent-auth": true}`. It
  opens a browser and waits up to 300 s on localhost:3000; a failure
  answers success.
- **mi17.** Only `session/update` and `session/request_permission`
  (`acp_server/hooks.py:185`).
- **mi18.** `mcpServers` is stored (`acp_server/agent.py:482`) and never
  given to the agent (`:521-531`).
- **mi19.** `AgentCapabilities(streaming=True)` (`acp_server/agent.py:140-157`):
  not an ACP field, so the wire carries the defaults, plus `authMethods`
  and `agentInfo`. `client_capabilities` is never read.
- **mi20.** Three, each a bullet under Custom below.

**Custom.**

- `_meta {"agent-auth": true}` on the auth method: the agent runs the
  OAuth. A client calls `authenticate` and waits up to 300 s; the browser
  opens on the agent's machine, and a failed login reads as success.
- `--dangerously-skip-permissions`: starts in `bypass-permissions`. A client
  adds the flag; the registry does not. No asks at all.
- `ext_method` and `ext_notification` answer every `_foo` request `{}`
  (`acp_server/agent.py:455-461`), so any extension request seems to work.

**In chord.** The start likely fails at import, and chord shows the start
failure with the stderr tail. If it starts: without a key, `auth_required`,
as chord never calls `authenticate`. After an OpenRouter login chord sets
the model by `session/set_model`, there being no `model` option, and gets a
method-not-found error. A session cannot be reopened: no `loadSession`, no
resume. Esc answers `cancelled`, and minion runs the tool. Output only in
`rawOutput` is not drawn. Mentions are dropped as links, though chord's
prompt text names the files. chord's own MCP server is not offered, and the
person's servers are ignored. chord queues its own mid-turn prompts and
sends no steering, so neither the second-prompt path nor the stubs are
reached. It logs full prompts to a file in the home directory (CHD-432's
reading).

**Sources.**

- `minion-code` 0.1.44 and 0.1.45 (metadata) on PyPI.
- `agent-client-protocol` 0.8.1, 0.9.0, 0.10.1, 0.11.1, 0.12.0 and 0.12.1
  on PyPI.
- CHD-432's notes in
  [`design/registry-2026-10-17.md`](design/registry-2026-10-17.md).

#### nova

- Name: Nova
- Pinned: `@compass-ai/nova` 1.1.55
- Run as: `npx -y @compass-ai/nova@1.1.55 acp`
- Source: <https://github.com/Compass-Agentic-Platform/nova>

Read at 1.1.55, the registry's pin, from the npm package
`@compass-ai/nova@1.1.55`. The public repository
<https://github.com/Compass-Agentic-Platform/nova> holds only a README, a
CHANGELOG to v1.0.66 and a licence for its docs; there is no source and no
ACP doc. The package's `LICENSE` ("Nova Proprietary Software License") and
`README.md:237` forbid reverse-engineering, decompiling or defeating
obfuscation, and `dist/cli.js` is obfuscated. Under the owner's rule of
2026-10-18, recorded on CHD-433, the bundle was read as plain text only for
the ACP contract: method names, fields and capabilities that stand there as
literals, and what they show of nova's behaviour. Nothing was deobfuscated,
decoded, beautified or run, and no copy is kept. Where the README or the
CHANGELOG state a fact, they are cited first. Cells that only decoding could
settle stay `?`. The launcher `scripts/bin-wrapper.mjs` falls back to
`node dist/cli.js acp`, as no platform package is a dependency.

**Footnotes.**

- **no1.** nova answers `initialize` with version 2 when the client's version
  is 2 or more, else 1. chord sends 1, so nova answers 1.
- **no2.** `package.json` has `vscode-jsonrpc` 8.2.1 and no ACP package, and
  no ACP SDK ships in the package; nova frames JSON-RPC itself.
- **no3.** nova accepts the v1 methods, the aliases `newSession`,
  `loadSession`, `listSessions`, `resumeSession`, `session/setModel` and
  `unstable_*`, its own `session/search` and `session/peer_identity/status`,
  and further methods whose names are not readable as plain text. At
  version 2 its permission request takes the v2 shape (no10).
- **no4.** New and load take `{cwd, mcpServers, systemPrompt}`; resume
  `{sessionId, cwd, mcpServers}`; list `{cwd, cursor}`; `session/search
  {query, cwd, limit, cursor}`; `session/delete`. Fork and close are
  advertised; that nova answers them as `session/fork` and `session/close`
  is not established from the wire contract or docs.
- **no5.** `session/set_mode {modeId}` and `session/set_model {modelId}` are
  accepted; which modes and models the session answer lists is not
  established.
- **no6.** The registry study (`docs/design/registry-2026-10-17.md`) §2: no
  config options, so no effort.
- **no7.** `promptCapabilities {embeddedContext: true, image: true}`, no
  audio; `README.md:48` says voice input is unavailable over ACP. How a
  `resource_link` is handled is not established.
- **no8.** A permission request's `toolCall` carries `toolCallId`,
  `status: 'pending'`, `title`, `kind`, `rawInput` and `locations`, the
  paths it touches. The kinds, content types, `rawOutput` and status changes
  of tool call updates are not established from the wire contract or docs.
- **no9.** The registry study's no2: "Always allow" was dropped in 1.1.55,
  leaving `allow_once` and `reject_once`.
- **no10.** At version 2 or more nova asks with `session/request_permission`
  in the v2 shape (`title`, `subject`). At version 1 the method it sends is
  not established: `permission/request` stands in the bundle as the
  candidate, and whether it goes out under that name cannot be read without
  decoding. Any outcome but `selected` rejects. A timeout is not established
  from the wire contract or docs. Requests carry
  `_meta.compass.permissionScope`.
- **no11.** The registry study's no3 and CHD-383: no `elicitation`; it asks
  through `session/requestUserInput`.
- **no12.** The registry study's no4: a one-entry plan that replaces itself.
- **no13.** CHANGELOG v1.0.64: abort kills the whole process tree, and plan
  cancellation works over ACP. `session/cancel` is taken as request or
  notification.
- **no14.** The registry study's no1: no plain-text sign of subagents.
- **no15.** The registry study §2: no usage, answer usage or cost.
- **no16.** `README.md:209` lists `/help`, `/model`, `/plan` and others, and
  `available_commands_update` stands once in the bundle; its payload is not
  established.
- **no17.** No `session_info_update` appears; the registry study §2 agrees.
- **no18.** `authMethods` holds one `type: "terminal"` method, "Nova Setup",
  only with `ACP_REQUIRE_AUTH=true` or no stored login; CHANGELOG v1.0.65
  gates sessions on it, and the README says to run `nova setup` first.
- **no19.** No `fs/*` or `terminal/*` request appears. nova can send a
  `file/write` notification; when is not established.
- **no20.** `mcpCapabilities {http: true, sse: true}`; CHANGELOG v1.0.65
  fixed SSE parsing.
- **no21.** `loadSession`, http and sse, image and embedded context, session
  `{fork, list, search, resume, close, delete, tools.list, agents.list}`,
  and `_meta` with `ownerApprovalRequired`, `sessionSkillScopeEnforced`,
  `sessionInstructionRefresh` and `peerIdentity`.
- **no22.** nova reads the protocol version, an auth-terminal flag and a
  delegation flag in `clientCapabilities._meta`; the flags' keys are not
  readable as plain text. Nothing readable on `fs`, `terminal`,
  `elicitation`, `plan` or `subagents`.

**Custom.**

- `_meta.compass.permissionScope` on approvals: operation, project root,
  paths, risk level. A client reads it; a private key, nothing lost if not.
- The permission method switches on the protocol version (no10). At 1 a
  standard client may never see an approval; at 2 it needs the v2 shape.
- Peer identity: sessions label themselves and message each other, each
  send asking permission; the setup method's name is not readable.
- `session/delegate`: nova hands work to the client, behind a `_meta` key
  that is not readable; the client then owns the double-submit risk.
- `session/requestUserInput`: questions; unanswered, they are lost.
- `systemPrompt` on new and load, a top-level off-spec parameter.
- Own session search, tool and agent lists, `file/write`,
  `session/suggestion`, a client-sent model or mode update, and method
  aliases; shapes partly unreadable.

**In chord.** chord negotiates version 1, so nova takes its version-1
permission path, and chord answers anything but `session/request_permission`
and `elicitation/create` with method-not-found. If that path sends
`permission/request`, every nova approval fails in chord without being
shown; one live check would settle it. Version 2 is no easy way out: chord
parses v1 only. Its questions through `session/requestUserInput` get
method-not-found (CHD-383). chord reopens by resume when it holds a record,
else load, adds its http MCP server, sends images, reads commands and sets
mode and model. It never calls `session/list`, fork, delete or close, sends
@ mentions as `resource_link` though nova takes embedded context, and ignores
`_meta.compass`, peers, delegation and `systemPrompt`. chord never calls
`authenticate`: without `nova setup` first, session/new may be refused. No
usage, title or config option comes, so the meter, the title and the effort
picker stay empty.

**Sources.**

- npm `@compass-ai/nova@1.1.55`: `LICENSE`, `README.md`, `CHANGELOG.md`,
  `package.json`, `scripts/bin-wrapper.mjs`, and `dist/cli.js` as plain text.
- <https://github.com/Compass-Agentic-Platform/nova> (README, CHANGELOG).
- `docs/design/registry-2026-10-17.md` (CHD-432), `docs/design/CHD-1.md`.

#### pi-acp

- Name: pi ACP
- Pinned: `pi-acp` 0.0.34
- Run as: `npx -y pi-acp@0.0.34`
- Source: <https://github.com/svkozak/pi-acp>

`pi-acp` 0.0.34, the registry pin and npm's newest (last modified
2026-09-24), read from the npm package and at tag `v0.0.34` of
<https://github.com/svkozak/pi-acp> (MIT, plain source). Paths are relative
to the repository root; SDK paths to the `@agentclientprotocol/sdk` 0.26.0
package. It is an adapter: it drives `pi` (`@earendil-works/pi-coding-agent`)
over pi's RPC mode, and `pi` must already be on PATH and logged in. Notes
named "the registry page's piN" are CHD-432's in
[`design/registry-2026-10-17.md`](design/registry-2026-10-17.md).

**Footnotes.**

- **pi1.** `src/acp/agent.ts:236-242` answers `1` whatever is asked.
- **pi2.** `package.json:49` asks `^0.26.0`, which resolves to 0.26.0, the
  only 0.26.x; it is not bundled, so npx installs it.
- **pi3.** List and delete are stable in 0.26 (`dist/acp.js:57-71`);
  `usage_update`, `session_info_update` and the unstable
  `type: "terminal"` auth method are used. 0.26 has no `session/set_model`
  route, and pi-acp has no `extMethod`, so its `unstable_setSessionModel`
  (`src/acp/agent.ts:1153`) is unreachable (`dist/acp.js:171-175`).
- **pi4.** Needs an absolute cwd; answers models, modes and config
  options. Startup info arrives as an agent message outside a turn.
- **pi5.** Replays text and tool results, not thoughts.
- **pi6.** No resume, fork or close. List reads pi's session files for the
  cwd, 50 a page, with `title` and `updatedAt`
  (`src/acp/agent.ts:909-936`). Delete unlinks pi's file and is idempotent.
- **pi7.** The legacy modes are pi's thinking levels ("Thinking: <level>");
  pi has no modes of its own.
- **pi8.** Config options `model` (ids `provider/model`) and
  `thought_level`, plus the legacy `models`. `session/set_model` is
  method-not-found (pi3).
- **pi9.** `src/acp/translate/prompt.ts:9-68`: text blocks joined with no
  separator; a `resource_link` becomes `\n[Context] <uri>`, unread; an
  embedded text resource is inlined, a blob named with its size, and only
  under `PI_ACP_ENABLE_EMBEDDED_CONTEXT=true`; audio becomes a marker text.
- **pi10.** `src/acp/session.ts:486-505`, `:625-673`, `:764-830`,
  `:1066-1078`. Kinds `read`, `edit` (`write`, `edit`), `execute` (`bash`),
  `other`. `rawInput` streams as arguments arrive; `rawOutput` on all but
  file edits. Bash content is `{type: "terminal", terminalId}` with
  `_meta.terminal_info`, `terminal_output` and `terminal_exit`. Status runs
  `pending`, `in_progress`, `completed` or `failed`, never back.
- **pi11.** pi asks no tool permissions. Its extensions' `confirm` comes
  as `allow_once`/`reject_once`, and `select` as one `allow_once` per
  choice. No elicitation.
- **pi12.** Cancel drops queued prompts ("Cleared queued prompts."), sends
  pi `abort`, and the turn answers `cancelled`
  (`src/acp/session.ts:396-416`).
- **pi13.** A second prompt is queued in the adapter with "Queued message
  (position N)." as agent text. pi's own steering is only the `/steering`
  and `/follow-up` commands; `/steering` sets pi's `steeringMode`
  (`src/acp/agent.ts:572-600`).
- **pi14.** `usage_update` with `used` and `size`; no usage in the answer;
  cost only in `/session`'s text.
- **pi15.** pi's prompts and skills, or file templates as a fallback, plus
  `/compact`, `/autocompact`, `/export`, `/session`, `/name`, `/steering`,
  `/follow-up` and `/changelog`; sent after new and load, outside a turn
  (`src/acp/agent.ts:60-100`, `:399-435`, `:1100-1120`).
- **pi16.** `title` and `updatedAt` only after `/name <name>`
  (`src/acp/agent.ts:552-558`). Other `session_info_update`s carry only
  `_meta.piAcp` (see Custom).
- **pi17.** `pi_terminal_login`, `type: "terminal"`, args
  `["--terminal-login"]`, always offered; `authenticate` does nothing
  (`src/acp/auth.ts:13-41`).
- **pi18.** The only client calls are `requestPermission` and
  `sessionUpdate`.
- **pi19.** `mcpServers` is stored and unused ("Pi doesn't support
  mcpServers", `src/acp/agent.ts:281-288`).
- **pi20.** `src/acp/agent.ts:241-268`: `loadSession`, image, embedded
  context per the env var, `mcpCapabilities` http and sse false,
  `sessionCapabilities {list, delete}`, `authMethods` always.
- **pi21.** Only `clientCapabilities._meta["terminal-auth"]`
  (`src/acp/agent.ts:250-252`).
- **pi22.** Six, each a bullet under Custom below.

**Custom.**

- `_meta.terminal_info`, `terminal_output`, `terminal_exit` on Bash calls,
  sent to every client: live shell output. `terminal_output.data` is a
  delta under the key chord reads as the whole output.
- `_meta.piAcp {queueDepth, running}` on `session_info_update` at each turn
  start, end, queue and cancel (`src/acp/session.ts:380-384`, `:407-411`,
  `:478-481`, `:546-549`, `:572-575`): the adapter's queue. Private.
- `_meta["terminal-auth"]` on the auth method, for a client that declares
  it: a `{command, args, label}` launch spec. Runs `pi` interactively.
- Slash commands `/steering`, `/follow-up`, `/name`, `/export`, `/session`,
  `/compact`, `/autocompact`, `/changelog`: steering mode, a title, an HTML
  export (a `resource_link` in the reply, `src/acp/agent.ts:840-858`), cost
  text. `/export` writes a file.
- `PI_ACP_ENABLE_EMBEDDED_CONTEXT` and `PI_ACP_PI_COMMAND` (`src/index.ts:7`,
  `README.md:118`): embedded resources and the pi binary. The registry's
  `env` is empty.
- Off-spec: extension questions as permissions, prompts queued in the
  adapter, and errors folded into `end_turn`
  (`src/acp/agent.ts:897-898`).

**In chord.** chord loads to reopen, there being no resume; it never calls
list or delete. The `model` and `thought_level` options work, and thinking
levels show again as modes. Images go in; `@` mentions arrive as
`[Context] file://…` lines glued to the text, while chord's text names the
files already. `usage_update` fills the meter; pi sends no cost. Commands
are read. Live shell output shows only its latest chunk, because chord
reads each `terminal_output` delta as the whole. Titles from `/name` and
the `piAcp` meta are dropped. chord declares no terminal auth and never
calls `authenticate` (a no-op here), so pi must be logged in already.
chord's own MCP server is not offered; the person's servers are passed and
unused. Under `--dangerously-skip-permissions` a select question gets its
first choice. An extension's prompt with no turn running is rejected
unseen (CHD-158). Failures end `end_turn`. chord queues its own mid-turn
prompts, so the adapter's queue is not reached.

**Sources.**

- `pi-acp` 0.0.34 on npm, and <https://github.com/svkozak/pi-acp/tree/v0.0.34>.
- `@agentclientprotocol/sdk` 0.26.0 on npm.
- CHD-432's notes in
  [`design/registry-2026-10-17.md`](design/registry-2026-10-17.md).

#### qoder

- Name: Qoder CLI
- Pinned: `@qoder-ai/qodercli` 0.2.14
- Run as: `npx -y @qoder-ai/qodercli@0.2.14 --acp`
- Source: <https://qoder.com>

`@qoder-ai/qodercli` 0.2.14, the registry pin, published 2026-05-13; npm's
`latest` is 1.1.73, about 60 releases on, and was not read. Read from the
npm package: one 38 MB bundle, `bundle/qodercli.js`, minified with its
strings partly behind a lookup table. 0.2.14 is Apache-2.0 (`LICENSE`,
`package.json`), so it is not under the bundle rule and its cells take a
plain `c`; 1.1.73's npm metadata has no licence field. This pass read the
bundle as shipped, as plain text, and decoded nothing; a fact hidden behind
the string table is `?`. The `repository` in `package.json` does not
resolve, so there is no public source. CHD-432's reader ran `webcrack` over
the obfuscated bundle; that is the owner's to weigh, and every fact that
rested only on that deobfuscated copy was dropped under the owner's rule.
The registry page's qoder notes stand here only where the shipped bundle
or Qoder's docs confirm them.

**Footnotes.**

- **qo1.** `initialize` answers a constant `1` (`bundle/qodercli.js:3992`,
  `:4006`) and stores `clientCapabilities` without reading the version.
- **qo2.** The ACP schema and method tables are a copy inside the bundle,
  in a Gemini-CLI-derived tree (`:3992`); `package.json` lists no
  dependencies. Which SDK release it was copied from is not stated.
- **qo3.** The agent (`:4006`) handles `initialize`, `authenticate`,
  `session/new`, `load`, `list`, `prompt`, `cancel`, `set_mode`,
  `set_config_option` and the unstable `session/set_model`; the copied
  tables name resume, fork and close, and no handler exists for them.
- **qo4.** `new`, `load` and `prompt` throw `authRequired` (-32000) unless
  `authenticate` succeeded or a persisted login was restored at start
  (`:4006`).
- **qo5.** `session/load` starts streaming the history without awaiting it
  and then answers (`:4006`).
- **qo6.** `{sessionId, cwd, title, updatedAt}` for the cwd asked, else the
  target directory (`:4006`).
- **qo7.** `default`, `acceptEdits`, `bypassPermissions`, and `plan` when
  plan is enabled (`:4016`). Qoder's ACP page names only Default and Bypass
  Permissions.
- **qo8.** `models` in the new and load answers; descriptions read like
  "Reasoning · Vision · 1x Credit" (`:4006`).
- **qo9.** `mode` and `model` select options come only in the answer to
  `session/set_config_option`, never in new or load (`:4006`, `:4016`). No
  effort option.
- **qo10.** Text as is; image and audio as inline data; a `file://`
  `resource_link` is read by the agent, asking leave for a path outside the
  project; another link becomes `@<uri>` text; an embedded resource becomes
  an `@<uri>` mention, with its content collected apart (`:4007`). Qoder's
  ACP page says "Supports images".
- **qo11.** A `tool_call` carries the tool's own name as title, `kind`
  from the ACP set (one tool kind maps to `think`), `rawInput`, and
  locations from path arguments. The result comes as `tool_call_update`
  with text content and the same text as `rawOutput` (`:4007`, `:4016`).
  Diffs (`path`, `oldText`, `newText`) appear only in permission requests
  (`:3999`). No terminal content was seen.
- **qo12.** The live `tool_call` is sent from the finished model message,
  not while arguments stream; its status sits behind the string table. The
  update ends `completed` or `failed` (`:4007`).
- **qo13.** Per kind of confirmation an `allow_always` ("Always allow …"),
  then "Allow" (`allow_once`) and "Reject", whose kind is behind the string
  table (`:4016`). A request unanswered after 30 s (`:3999`) rejects the
  tool; nothing withdraws the request. `cancelled` reads as cancel, and a
  turn's abort aborts the ask (`:4006`).
- **qo14.** The copied client-method table holds `fs/*`, `terminal/*`,
  `session/request_permission` and `session/update`; no
  `elicitation/create` (`:3992`).
- **qo15.** A plan comes as the text of a permission request (`:3999-4006`); no
  `plan` update was seen.
- **qo16.** Cancel aborts the running prompt; the loop then breaks and
  answers `end_turn` with its usage, or `cancelled` when the abort surfaces
  as an error. A cancel with no turn throws "Not currently generating"
  (`:4006`, `:4007`).
- **qo17.** A new `session/prompt` aborts the pending one before it starts
  (`:4007`).
- **qo18.** Qoder's ACP page lists "Subagent ✅"; how a subagent reaches
  the wire was not found in the plain text.
- **qo19.** The answer carries `_meta.quota {token_count {input_tokens,
  output_tokens}, model_usage [{model, token_count}]}`, zeros for a slash
  command (`:4007`). No `usage_update` was seen; `PromptResponse.usage`
  is not set. No cost.
- **qo20.** Sent right after new and load (`:4006`). Qoder's ACP page lists
  `/init`, `/memory`, `/about` and `/help`. A prompt starting with `/` or
  `$` is tried as a command first and ends `end_turn` (`:4007`).
- **qo21.** `session_info_update` appears in plain text only in the copied
  schema; updates whose kind is behind the string table leave it open.
- **qo22.** A qodercli login method with no `type` (a device flow: the
  agent opens the browser by shell command and waits 180 s) and
  `type: "env_var"` for `QODER_PERSONAL_ACCESS_TOKEN`, which is read only
  when that method is authenticated (`:4006`). At start only a persisted
  login is restored. Qoder's ACP page says the CLI detects the variable
  "to complete authentication at startup", so a client can set it "to allow
  Qoder CLI to automatically log in"; the page tracks 1.1.x.
- **qo23.** With `clientCapabilities.fs` declared, file access goes through
  the client (`:4006`). `terminal/*` is in the copied table; a use was not
  seen. The ACP page claims "File Operations or Terminal" through the IDE.
- **qo24.** stdio, http and sse servers are mapped into the session's
  config (`:4006`); the ACP page says "Stdio, SSE, Streamable HTTP".
- **qo25.** `loadSession`, `sessionCapabilities {list}`,
  `promptCapabilities` image, audio and embeddedContext all true,
  `mcpCapabilities` http and sse true (`:4006`).
- **qo26.** `clientCapabilities.fs` is the only field read in plain text
  (`:4006`).
- **qo27.** Seven, each a bullet under Custom below.

**Custom.**

- `_meta.quota` on the prompt answer: tokens per turn and per model. A
  client reads a private key; no cost and no context size.
- Config options only in `set_config_option`'s answer: a client must set
  one blind to discover them.
- The 30 s permission timeout: the agent rejects and goes on, and the
  client is not told; a late answer is ignored. Fails closed.
- A plan as a permission's text: the plan reads as Allow and Reject.
- A concurrent prompt aborts the running turn: its work is lost.
- The `env_var` login method, with `NO_BROWSER` and `QODER_CONFIG_DIR` from
  the README: headless login, a token in the agent's environment.
- Slash commands and the `$` prefix: `/init` writes `AGENTS.md` into the
  project; a prompt starting with `$` is taken as a command.

**In chord.** chord loads to reopen (no resume offered) and never calls
list. It sets models through `session/set_model`, there being no `model`
option in the new answer, and uses legacy modes. Images go in; `@`
mentions go as `file://` links, which qoder reads itself. chord's own MCP
server goes in over http. `_meta.quota` is ignored, so a qoder session
shows no usage. chord never calls `authenticate`, so without a prior
qodercli login the start fails `authRequired`. chord declares no `fs`, so
qoder uses its own. What reads wrong: after 30 s the permission box stays
open while the tool is already rejected; a plan comes as a permission; a
load's replay may arrive after the answer; a cancel may read as
`end_turn`; live titles are raw tool names. chord queues its own mid-turn
prompts, so the abort on a second prompt is not hit.

**Sources.**

- `@qoder-ai/qodercli` 0.2.14 on npm (`bundle/qodercli.js`, `README.md`,
  `LICENSE`); 1.1.73's npm metadata.
- Qoder's ACP page, <https://docs.qoder.com/en/cli/acp>, read 2026-10-18.
- CHD-432's notes in
  [`design/registry-2026-10-17.md`](design/registry-2026-10-17.md), kept
  only where confirmed above.

#### qwen-code

- Name: Qwen Code
- Pinned: `@qwen-code/qwen-code` 0.25.2
- Run as: `npx -y @qwen-code/qwen-code@0.25.2 --acp --experimental-skills`
- Source: <https://github.com/QwenLM/qwen-code>

Read at `@qwen-code/qwen-code` 0.25.2, the ACP Registry's pin, from the
repository https://github.com/QwenLM/qwen-code at tag v0.25.2; paths below
are relative to `packages/cli/src/acp-integration/`, except those starting
`acp-bridge/`, which are under `packages/acp-bridge/src/`. Apache-2.0, with
nothing restricting reading. The two largest files, `acpAgent.ts` and
`session/Session.ts`, were read by search and around each hit, not end to
end; the `qwen/*` control methods were listed, not read one by one. The
registry passes `--experimental-skills`. Two findings correct CHD-432
(`docs/design/registry-2026-10-17.md`): qwen sends no `_meta.quota` (qw13),
and its own turns bring requests with no turn of chord's running (qw20).

**Footnotes.**

- **qw1.** It answers the SDK's `PROTOCOL_VERSION`
  (`acpAgent.ts:5508`).
- **qw2.** `packages/cli/package.json:45` `^0.14.1`; `pnpm-lock.yaml`
  resolves 0.14.1.
- **qw3.** v1 plus `unstable_resumeSession`, `unstable_listSessions`,
  `unstable_setSessionModel` and `session_info_update`. Its own: the
  `_qwencode/*` turn methods, `craft/drainMidTurnQueue`, `deleteSession`,
  about 50 `qwen/*` methods and 11 `qwen/notify/*` notifications
  (`acpAgent.ts:5466-7181`, `:9646`; names in `acp-bridge/status.ts:129-260`).
- **qw4.** `session/new` answers modes, models and config options. Load,
  resume and list are handled (`acpAgent.ts:5751`, `:5909`, `:6483`,
  `:6786`). No standard fork, close or delete; its own `deleteSession`,
  `qwen/control/session/close` and `qwen/control/session/fork_agent`
  (`acpAgent.ts:9639`, `:12100`, `:13048`).
- **qw5.** Config options `mode`, `model` and, for models that support it, a
  reasoning effort of category `thought_level` (`acpAgent.ts:16677-16816`);
  no `config_option_update`. A mode change from inside sends
  `current_mode_update`, then `qwen/notify/session/mode-update`; a model
  change from inside sends only `qwen/notify/session/model-update`
  (`session/Session.ts:13073`, `:13312-13350`).
- **qw6.** Image and audio as inline data, clamped in size. An embedded
  resource goes in, the block as `@uri`. A `file://` `resource_link` is read
  as an @-path; any other uri, and any link over SSH, becomes text
  (`session/Session.ts:17655-17730`).
- **qw7.** Kinds from core's map, `switch_mode` for entering and leaving plan
  mode. `rawInput` always, `rawOutput` when the result has one; text and
  diff content, locations; `pending`, `in_progress`, then `completed` or
  `failed`. Each call also gets an update carrying only
  `_meta.toolLifecycle` (`session/emitters/tool-call-emitter.ts:219-512`,
  `acp-bridge/transcript-replay.ts:966-1017`).
- **qw8.** `allow_once`, also as "once and switch to default" when leaving
  plan mode; `allow_always` per kind, for the session, project or user;
  `reject_once`. `cancelled` cancels the call; an option not offered throws;
  requests go one at a time; no timeout. Its `ask_user_question` tool comes
  as a permission with the questions in `toolCall._meta.qwenQuestions`
  (`session/permissionUtils.ts:19-330`, `session/Session.ts:12856-12880`).
- **qw9.** A `plan` from its todo tool, with plan ids in `_meta`
  (`session/emitters/PlanEmitter.ts:27-41`).
- **qw10.** Cancel aborts the running prompt and any prompt waiting at
  admission; with no turn running it is ignored (`acpAgent.ts:7181-7200`).
  Subagent lifecycle updates go on for up to 30 s after (CHD-432 QW3).
- **qw11.** Between tool batches it asks the client for queued input with
  `craft/drainMidTurnQueue`, with a timeout and no capability gate;
  method-not-found switches it off for the session
  (`session/Session.ts:10003-10050`). A concurrent `session/prompt` waits
  until the turn ends.
- **qw12.** Subagents ride in its own `_meta` on the parent's updates; no
  `subagent_update`, no child session (CHD-432 qw1).
- **qw13.** `usage_update` `used` and `size` per main-session model round.
  No `usage` on `PromptResponse` and no cost. Per-round tokens also come in
  `_meta.usage` on an empty `agent_message_chunk`
  (`session/emitters/MessageEmitter.ts:300-345`,
  `acp-bridge/transcript-replay.ts:522-548`). No `quota` anywhere in the ACP
  layer or the bundle's ACP chunk. This corrects CHD-432's `_meta.quota`
  for qwen, which looks carried over from gemini.
- **qw14.** Commands and skills, skills also in `_meta.availableSkills`;
  held back while automatic work is held (`session/Session.ts:12825-12842`).
- **qw15.** `session_info_update` with `title` when a title is recorded,
  after a turn or `/rename`, then `qwen/notify/session/title-update`
  (`session/Session.ts:11466-11496`).
- **qw16.** One method, `openai`, with
  `_meta {type: "terminal", args: ["--auth-type=openai"]}`, not ACP's
  `type`; the reply is followed by an `authenticate/update` notification
  (`authMethods.ts:10-35`, `acpAgent.ts:5656`).
- **qw17.** `fs/read_text_file` and `fs/write_text_file`, each only when
  declared, else its own files; never `terminal/*`
  (`acpAgent.ts:15984-15990`, `service/filesystem.ts:142-235`). It also
  reads `_meta["qwen.goalProposals"]` and private `initialize._meta` keys
  (`acpAgent.ts:5468-5501`, `:15570`).
- **qw18.** Session servers above the person's settings; none in agent-host
  read-only mode (`acpAgent.ts:15381-15450`).
- **qw19.** `loadSession`, `promptCapabilities` image, audio and
  `embeddedContext`, `sessionCapabilities` list and resume,
  `mcpCapabilities` http and sse, `_meta.imageCapability`
  (`acpAgent.ts:5515-5535`).
- **qw20.** When a background agent, shell, monitor or workflow ends, or a
  cron job fires, qwen starts a turn of its own. It first sends the request
  `_qwencode/start_turn`; `{accepted: false}` defers the turn, and a -32601
  answer counts as admitted. The turn's updates and permissions follow, each
  permission with `_meta.backgroundTurn`, then `_qwencode/end_turn`. Goal
  turns send both as notifications. No capability gate
  (`session/Session.ts:3407-3413`, `:11340-11600`, `:12250-12360`,
  `:12716-12853`).

**Custom.**

- `_qwencode/start_turn` and `end_turn` (qw20): the agent reacts to finished
  background work by itself. A client needs nothing to get it; to manage it
  it must answer `start_turn`, show a turn it did not start, and answer
  permissions outside its own turns. It spends the model when the person
  did not ask.
- `craft/drainMidTurnQueue` (qw11): steering served by the client. One
  refused round trip per session for a client without it.
- `_meta.qwenQuestions` on a permission (qw8): the model's multiple-choice
  questions; answers have no ACP slot.
- `_meta.toolLifecycle`, `executionLifecycle`, `usage` and subagent keys:
  timing, provenance, per-round tokens; some ride on empty chunks.
- `qwen/notify/session/*` notifications: the only word of a model change
  from inside, plus titles, prompt suggestions, PR links and more.
- `_meta.availableSkills` on the commands: skills as commands. Free.
- About 50 `qwen/*` control methods, `deleteSession` and private
  `initialize._meta` keys: a daemon's control plane, some only for a
  trusted private parent.

**In chord.** chord creates, loads and resumes qwen sessions, and never calls
`session/list`. Modes, models and effort go through config options; chord
finds the `model` option and the `thought_level` effort. chord draws
`current_mode_update`, `plan`, the context meter, commands and permissions,
sends images and `resource_link` mentions, which qwen reads, and gives
qwen its http MCP server. With no `PromptResponse.usage` chord has no answer
tokens to price, so no cost shows. Requests with no turn running: ✓, which
corrects CHD-432's ✗. chord answers `_qwencode/start_turn` with
method-not-found, as it does every extension request, and qwen takes that
as admitted. The background turn's updates land under chord's last turn, and
its permissions arrive with no turn running, so chord refuses them unseen
(CHD-158). This corrects CHD-432's line that qwen does not widen CHD-158: it
does, for each background task that ends between turns. chord refuses
`craft/drainMidTurnQueue` once per session. Ignored: `_qwencode/end_turn`,
every `qwen/notify/*` (an inside model change never reaches chord's status
line), titles, `_meta.usage`, skills in `_meta`, and `_meta.qwenQuestions`,
so a question shows as a bare permission (CHD-383). Subagent updates after a
cancel can hold a queued prompt up to 5 s (CHD-432 QW3). chord never calls
`authenticate`; qwen's one method runs in a terminal.

**Sources.**

- https://github.com/QwenLM/qwen-code, tag v0.25.2.
- `@qwen-code/qwen-code` 0.25.2, npm, its ACP chunk searched only.
- CHD-432's reading, `docs/design/registry-2026-10-17.md` (qw1-qw7,
  QW1-QW4).

#### sigit

- Name: siGit Code
- Pinned: `@smbcloud/sigit` 1.7.0
- Run as: `npx -y @smbcloud/sigit@1.7.0`
- Source: <https://github.com/getsigit/sigit>

Read at 1.7.0, the registry's pin, in the npm wrapper `@smbcloud/sigit@1.7.0`
and the Rust source of <https://github.com/getsigit/sigit> at tag `v1.7.0`;
cites are relative to that repository, under `crates/cli/src/` unless named.
Apache-2.0, so nothing limits reading it. Inference runs on the device by
default through the `onde` engine, on a GGUF model from Hugging Face
(Qwen2.5-3B, a 1–2 GB first download); cloud tiers need a sigit.si sign-in,
and an `OPENAI_BASE_URL` endpoint spends on that account. The registry's
empty args start ACP because stdin is a pipe (`main.rs:6705-6714`), but they
do not load the model: the first prompt answers "No on-device model is
loaded. Run `/load`…" (`main.rs:3474-3490`). At every start it connects to
an MCP server at `https://sigit.si/api/v1/mcp`, signed in or not
(`mcp.rs:24-27,452-477`). The CHD-432 study had list, fork, resume, close and
delete unread; sigit offers all five.

**Footnotes.**

- **si1.** `main.rs:2236` answers `ProtocolVersion::V1` whatever the client
  asks; `README.md:139-153` says draft v2 is not enabled.
- **si2.** `agent-client-protocol` 2.2.0 and schema crate 1.9.1
  (`Cargo.lock:22-24,56-58`), with its own handlers (`main.rs:6084-6420`).
  The workspace's `ed-acp` does not serve the binary.
- **si3.** `schema::v1` (`main.rs:77-100`) and the one feature
  `unstable_session_fork` (`Cargo.toml`). No `session/set_model`, and no
  `PromptResponse.usage`, which needs a feature it leaves off.
- **si4.** `main.rs:3173-3211`: absolute `cwd` checked, MCP servers
  connected, `configOptions` and `modes` answered, commands sent.
- **si5.** `main.rs:620-716`: user chunks under one `messageId`, thoughts,
  messages, `write_todos` as `plan`, each other call as a finished
  `tool_call` with rawInput and rawOutput.
- **si6.** `main.rs:2888-2909`: no replay. A session is saved only after a
  turn completes (`main.rs:2738-2766`), so after a restart one with no
  finished turn answers `ResourceNotFound` "session <id> not found".
- **si7.** `main.rs:2799-2861`: saved sessions with a cwd and a message,
  optional absolute `cwd` filter, its own cursor, `title` and `updatedAt`.
- **si8.** `main.rs:3098-3171`: the whole current conversation under a new
  id, no fork point, replayed on the new id; grants and plan mode not carried.
- **si9.** `session/close` (`main.rs:3021-3066`) cancels the turn and drops
  state, MCP servers, grants and background commands; history stays.
  `session/delete` (`main.rs:3069-3077`) also removes it from the store.
- **si10.** `main.rs:4991-5064`, also as option `sigit-permission-mode`
  (category `mode`); `set_mode` works mid-turn (`main.rs:4538-4558`).
- **si11.** No `models` field and no `set_model`; option `sigit-model`,
  category `model` (`main.rs:5208-5217`): local GGUF picks and 15 cloud tiers.
  Picking an uncached model starts a download.
- **si12.** `main.rs:5086-5218`: `sigit-model`, `sigit-local-inference` (a
  boolean for a client that declares boolean options, else a `Local`/`Cloud`
  select) and `sigit-permission-mode`; `config_option_update` on change.
- **si13.** `main.rs:3305-3420,3509-3545`: media the backend cannot take is
  dropped with a notice; embedded text is inlined between fences; a
  `file://` link is read from disk by sigit, any other becomes a text line.
- **si14.** Kinds edit, delete, execute, read, search, fetch, think, other
  (`main.rs:361-374`); model loading and status lines are `think` calls
  (`main.rs:1412-1418`). Content: arguments as fenced JSON, then a `diff` for
  a write and the fenced result (`main.rs:423-451,3747-3760`), or `terminal`
  content when the client runs it. Locations for file tools
  (`main.rs:455-480`). `pending` when it will ask, else `in_progress`; ends
  `completed` or `failed` (`main.rs:3715-3721,3923-3933`). Also sets `name`.
- **si15.** `allow_once`, `allow_always`, `reject_once`, `reject_always`
  (`main.rs:4207-4219`). `cancelled` ends the turn `cancelled` and fails the
  round's later calls (`main.rs:3862-3906`); an error is a denial naming
  `SIGIT_PERMISSIONS=allow`. It waits with no timeout.
- **si16.** URL elicitation only inside `authenticate`, with
  `elicitation/complete` on success (`main.rs:6421-6479`); never a form.
- **si17.** `write_todos` becomes `plan`, live and replayed
  (`main.rs:3727-3733`); an empty list clears it.
- **si18.** `main.rs:4302-4316` stops the turn and its foreground command
  (`tools.rs:2949-2953`); background commands run on until `kill_command`,
  close or exit. `$/cancel_request` acts the same.
- **si19.** A second `session/prompt` waits on the session lock
  (`main.rs:2452-2466,6324`). No steering.
- **si20.** One `task` call running a nested read-only loop; in ACP it works
  only under an endpoint override and otherwise answers "not available
  on-device yet" (`tools.rs:741-758`; `main.rs:6139-6150`).
- **si21.** `usage_update {used, size}` after each model response, estimated
  when the endpoint gives no count (`main.rs:4141-4159`). No cost.
- **si22.** `main.rs:1738-1823`: 18 built-ins (`/load`, `/login`, `/models`…)
  and `.sigit/commands/*.md`, each run as prompt text.
- **si23.** `main.rs:2768-2790`: after each save, `updatedAt`, and `title`
  when it changed.
- **si24.** One `agent` method, "Sign in to siGit Code" (`main.rs:2229-2234`),
  a loopback browser flow (`main.rs:2303-2366`); optional on the device.
  `logout` too.
- **si25.** `fs/*` and `terminal/*` for foreground commands, only when the
  client declares them (`main.rs:2176-2200`); else its own.
- **si26.** `main.rs:2094-2130`: stdio and Streamable HTTP; `sse` is logged
  and ignored. The sigit.si server, and `smb`/`asc` when on PATH, come on top.
- **si27.** `main.rs:2241-2294`: `loadSession`, `auth.logout`, prompt
  `{image, audio, embeddedContext}`, `mcpCapabilities.http`, session
  `{fork, list, additionalDirectories, resume, close, delete}`. No steering.
- **si28.** `main.rs:2176-2222`: `fs`, `terminal`, `elicitation.url`,
  `session.configOptions.boolean`; never `plan`, `subagents` or `_meta`.

**Custom.**

- `_meta.sigit.active_model` in the initialize answer (`main.rs:905-951`):
  the start model before a session. A client reads `_meta`; the same comes
  as the `sigit-model` option once a session is open.
- Slash commands acting outside the protocol (`main.rs:5298,5757-5780`):
  `/login` opens a browser on the machine itself, and `/login <email>
  <password>` sends a password as prompt text. A client only passes text on;
  the password then sits in the client's record.
- `/load` loads the model, downloading it first (`main.rs:1395-1420`): disk,
  network and memory, before the first real prompt.
- Built-in MCP servers, on by default (`mcp.rs:24-37`): a connection to
  sigit.si at every start, with the token when signed in. Off with
  `SIGIT_MCP_OFFICIAL=off`.
- `SIGIT_*` variables and config files set permissions, model, endpoint and
  the client fs and terminal use; the registry passes no environment.
- One live session per process, others parked (`main.rs:2520-2600`); the
  `Inference` toggle is saved machine-wide (`settings.rs:209-213`).

**In chord.** chord asks for version 1, adds its http MCP server, opens
with session/new and reopens with resume when it holds a record, else load.
It never calls `session/list`, fork, close or delete, though sigit offers
them all; without close, parked state and background commands live until
the process exits. Mode and model come from sigit's options by category;
`/config` shows `Inference` as a select, since chord declares no boolean
options, and reads per session though it is machine-wide. `usage_update`
drives the meter with no cost, so chord estimates one. Plans and the four
permission kinds work. chord never calls `authenticate`, so the URL sign-in
never comes; `/login` and `/load` pass through as commands. A fresh start
answers the first prompt with the `/load` hint as an ordinary reply. A
resume refused after a restart names the id twice (CHD-139). chord declares
no `fs` or `terminal`, so command output comes as fenced text at the end.
chord drops titles and `_meta.sigit`, and does not draw `name`.

**Sources.**

- npm `@smbcloud/sigit@1.7.0`; <https://github.com/getsigit/sigit>, tag
  `v1.7.0`.
- crates.io `agent-client-protocol` 2.2.0, `agent-client-protocol-schema`
  1.9.1.
- `docs/design/registry-2026-10-17.md` (CHD-432).

### Own CLIs (`src/clis.ts`)

#### cursor

- Name: Cursor
- Run as: `agent acp`, from PATH
- Install: <https://cursor.com/docs/cli/installation>

Read at 2026.10.16-e3cb207, the release `https://cursor.com/install` named on
2026-10-18 and the ACP Registry's pin, from the archive
`https://downloads.cursor.com/lab/2026.10.16-e3cb207/darwin/arm64/agent-cli-package.tar.gz`,
with 2026.08.11-e8db854 beside it for comparison, and from Cursor's ACP docs
and CLI changelog. The CLI is a minified Node bundle. Cursor's Terms of
Service §1.5(i) forbid any attempt to "reverse engineer, disassemble,
decompile, decode, or otherwise attempt to derive or gain access to the
source code" of the Service. Under the owner's rule of 2026-10-18, recorded
on CHD-433, the bundle was read as plain text only for the ACP contract: the
messages, fields and capabilities it sends and accepts, and how it behaves.
Nothing was deobfuscated, beautified or decoded, and no copy is kept. Where
the docs or the changelog state a fact, they are cited first; the rest is
from Cursor CLI 2026.10.16-e3cb207. The registry's `cursor` is a proprietary
binary archive; chord takes only npx and uvx registry entries, so it starts
the person's own `agent`.

**Footnotes.**

- **cu1.** Cursor CLI 2026.10.16-e3cb207 ships
  `@agentclientprotocol/sdk` 0.14.1, a pre-1.0 release.
- **cu2.** v1 plus `unstable_listSessions` and `unstable_setSessionModel`, the
  draft subagent shape (ACP PR #1992) when the client asks for it, and
  `cursor/*` methods both ways. No v2.
- **cu3.** The answer carries `modes`, `models` and `configOptions`. Without
  a login it is refused with `authRequired` (cu17).
- **cu4.** Replays message and thought chunks and tool calls, then past
  subagents; one still running replays `disconnected`.
- **cu5.** The cwd filter must be absolute; a pagination `cursor` is refused
  with invalidParams.
- **cu6.** https://cursor.com/docs/cli/acp. `session/set_mode` also takes
  `code`, `architect` and `chat`; each change sends `current_mode_update`.
- **cu7.** Options `mode` and `model`; `unstable_setSessionModel` sets
  `model`. Only a client that declares
  `clientCapabilities._meta.parameterizedModelPicker: true` gets one option
  per model parameter, effort among them as `thought_level`; otherwise effort
  is baked into one long `model` list. No `config_option_update`.
- **cu8.** An embedded `resource` is inlined as text though `embeddedContext`
  is false. A `file:` link inside the project is read and inlined, cut at
  20 000 characters; any other link is named only.
- **cu9.** Kinds `execute`, `edit`, `delete`, `read`, `search`, `fetch`,
  `think`, `switch_mode`, `other`. `rawInput` is a trimmed object per tool,
  shell `{command}`. `rawOutput` per tool, shell `{exitCode, stdout,
  stderr}`. Content: a `diff` for edit and delete, text only for plan
  progress and `Watching:` calls, never `terminal`.
- **cu10.** Every tool call starts `pending` and ends `completed`; none is
  sent `failed`, so a failed command is `completed` with a non-zero
  `exitCode`. Only plan and `Watching:` calls send `in_progress`.
- **cu11.** https://cursor.com/docs/cli/acp. Asked for write, shell,
  delete, read (new at 2026.10.16), MCP and web. `cancelled` or a failed
  request is rejected. An approval that has no `toolCallId` is approved
  without asking the client, at 2026.08.11 too; which operations come that
  way is not established.
- **cu12.** No `elicitation/create`; questions go through
  `cursor/ask_question` (Custom), documented at
  https://cursor.com/docs/cli/acp.
- **cu13.** A `plan` update only when the model makes a plan in plan mode;
  todos go only to `cursor/update_todos`.
- **cu14.** Changelog v2026.09.15 and v2026.10.08. Cancel answers
  `cancelled`. With `subagents` declared it aborts the turn's subagents,
  waits up to a timeout and marks the rest `disconnected`; watched shells
  keep running.
- **cu15.** A second `session/prompt` cancels the running one. No
  `_session/steering`; the CLI's own steering (changelog v2026.08.11) is
  interactive only.
- **cu16.** Changelog v2026.09.15. With `subagents` declared:
  `subagent_spawned`, the child on its own session id, then
  `subagent_state_update` (`completed`, `failed`, `cancelled`,
  `disconnected`); `capabilities: {}`, so no stop. Without it, one
  `Task: …` call and a `cursor/task` request.
- **cu17.** https://cursor.com/docs/cli/acp: `agent login` or
  `CURSOR_API_KEY`. New, load and list fail `authRequired` without a stored
  login, a key or a token; `authenticate` (`cursor_login`) opens a browser
  login.
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

fx v0.0.14, released 2026-10-16 and still the latest release on 2026-10-18,
read at tag `v0.0.14` (commit 1a070af3) of <https://github.com/vercel-labs/fx>
(Apache-2.0, plain Zig, no limits on reading). It is not in the ACP Registry;
chord starts it from its own CLI table as `fx acp`. Paths are relative to the
repository root; `CHANGELOG.md` and <https://fx.sh/docs/using-fx/acp> are the
notes. `main` at c7f5a38a (2026-10-17, unreleased) changes only how replayed
tool rows are titled. The docs page still names a `code` mode, which 0.0.14
replaced with `auto`.

**Footnotes.**

- **fx1.** `src/acp/types.zig:19`, `:315`; any integer from the client is
  answered with 1 (`src/acp/server.zig:2462-2466`).
- **fx2.** Its own JSON-RPC and ACP types (`src/acp/jsonrpc.zig`,
  `src/acp/types.zig`); no SDK.
- **fx3.** `sessionCapabilities {list, resume, close, systemPrompt}`, v1
  session `notice` updates, `$/cancel_request` both ways, `mcpCapabilities.acp`
  (MCP over ACP) and form and URL elicitation (`src/acp/types.zig:313-332`).
- **fx4.** The answer carries `configOptions` and `modes`
  (`src/acp/sessions.zig:664-708`).
- **fx5.** Load replays history as chunks and tool calls
  (`src/acp/sessions.zig:1945-2264`); resume at `src/acp/server.zig:99`.
- **fx6.** Pages of 100 with saved titles, across workspaces when `cwd` is
  left out (`src/acp/sessions.zig:1736`; 0.0.7 in `CHANGELOG.md`).
- **fx7.** No fork method. `session/close` works; `session/remove` answers only
  in the wasm core (`src/acp/server.zig:102`, `:1438`, `:1479`).
- **fx8.** `src/builtins/modes.zig:11-23`. `auto` is the default: a safety
  model reviews a call instead of asking. `set_mode` answers `null` and no
  `current_mode_update` follows (`src/acp/server.zig:3962`). Since 0.0.14 a
  mode set over ACP becomes the person's saved fx mode, CLI included
  (`CHANGELOG.md:53`, `:103`).
- **fx9.** No `models` field and no `session/set_model` (method enum
  `src/acp/server.zig:68-115`). Options in order: `provider` and `model`
  (both category `model`), `mode`, `effort` (`thought_level`), then `fast`
  and `ultrafast` (category `model`) when the model has them
  (`src/acp/sessions.zig:664-695`, `:2345-2530`). No `config_option_update`;
  the new set comes in the `set_config_option` answer.
- **fx10.** `auto` first, then the model's levels
  (`src/acp/sessions.zig:2519-2545`).
- **fx11.** `promptCapabilities {image: true, audio: false, embeddedContext:
  true}`. A `file://` `resource` is inlined; `resource_link` has no branch and
  is skipped (`src/acp/prompt.zig:1735-1832`).
- **fx12.** Kinds read, edit, search, execute, fetch and other
  (`src/acp/tool_call_presentation.zig:23-38`). No `rawOutput`; extra
  top-level `name` and `command_result` (`src/acp/types.zig:243-299`).
- **fx13.** Text content only. Command output streams as one
  `tool_call_update` per chunk carrying only the newest chunk
  (`src/acp/prompt.zig:3302-3306`), so it replaces what came before.
- **fx14.** `in_progress` is sent at once (`src/acp/prompt.zig:2545-2546`).
- **fx15.** `allow_once`, `allow_always` ("Allow for this session"),
  `reject_once` (`src/acp/prompt.zig:2431-2436`). `cancelled`, an error or an
  unknown id denies (`src/acp/server.zig:1028-1043`, `:1364-1372`). It asks
  only in `ask` mode or under an ask rule; in `auto` a "caution" verdict
  denies without asking (`src/core/agent/runtime/tool_admission.zig:97-140`).
- **fx16.** Only MCP servers' elicitations, when the client declares the mode
  (`src/acp/prompt.zig:734-743`, `:3355-3470`); a URL one is followed by
  `elicitation/complete` (`:3720-3730`). fx's own question tool refuses under
  ACP (`src/tools/agent/ask_user_question.zig:94-96`).
- **fx17.** One cancel flag per turn covers its tools and subagents
  (`src/acp/server.zig:1383-1386`, `:3123-3133`); stopping work since 0.0.8.
- **fx18.** A mid-turn `session/prompt` joins only with `_meta.fx.steer:
  true`; without it the answer is `invalid_request` "Prompt already in
  progress" (`src/acp/server.zig:1425-1431`, `:1640-1700`).
- **fx19.** A child's tool calls and permissions come on the parent's session
  id (`src/acp/prompt.zig:1283-1291`); one child cannot be stopped
  (`src/tools/agent/subagent.zig:103-114`).
- **fx20.** `usage_update {used, size}` after each turn
  (`src/acp/sessions.zig:2307-2324`); answer usage has input, output, cache
  and reasoning tokens and no `totalTokens` (`src/acp/types.zig:396-417`).
  "ACP usage updates report context use and no longer include costs"
  (`CHANGELOG.md:108`).
- **fx21.** Sent once, empty (`src/acp/sessions.zig:707`).
- **fx22.** `{title, updatedAt}` after each turn and on load
  (`src/acp/types.zig:426-432`).
- **fx23.** `authMethods: []`; a provider auth failure mid-turn is agent text
  (`src/acp/prompt.zig:3282-3296`).
- **fx24.** The client's `fs` and `terminal` flags are stored and never read
  (`src/acp/server.zig:2811-2813`).
- **fx25.** `src/acp/mcp_servers.zig`; a given server that needs OAuth fails
  the session (`:186-199`).
- **fx26.** `src/acp/types.zig:313-332`, also `_meta.fx.steering: true`.
- **fx27.** `src/acp/server.zig:2453-2510`. `notice` is sent only with
  `clientCapabilities.session.notices` (`:2484-2488`), else as agent text.
- **fx28.** Twelve extensions, each a bullet under Custom below.

**Custom.**

- `_meta.fx.steer` on a mid-turn prompt, announced as
  `initialize._meta.fx.steering`: the message joins the running turn; text
  only, up to 64 KiB, its answer deferred to the turn's end. Private to fx.
- `systemPrompt` on `session/new` (RFD) or `_meta.fx.systemPrompt`:
  append-only instructions up to 64 KiB (`src/acp/client_instructions.zig`).
- `_meta.fx.toolCall {internal, mcp}` and top-level `name` on `tool_call`:
  hides fx's bookkeeping calls and names the MCP server and tool.
- `command_result` on the last `tool_call_update`: exit code, signal, timeout
  and byte counts (`src/acp/types.zig:498-520`). Off-spec, top level.
- `session_info_update._meta.fx.modelResponseRecovery`: retry state while a
  provider fails (`src/acp/types.zig:43-92`).
- `_meta.fx.profileMcpServers: true`: also loads the person's own fx MCP
  servers into the session.
- `_meta.fx.alwaysLoaded` per MCP server: eager or lazy tool schemas.
- `mcpCapabilities.acp` and `mcp/message`: MCP servers hosted by the client
  over the ACP connection.
- `_meta.fx.attachment` on image blocks: attach by reference.
- `stopReason` values `max_output_tokens`, `max_model_turns`, `refused`,
  `yielded` (`src/acp/types.zig:94-118`), outside ACP's set.
- `session/remove`, wasm core only; `libfx/*` methods, libfx builds only.
- Launch flags `--model`, `--ultrafast`, `--add-dir`, `--log-file`; the
  ultrafast tier is priced higher (0.0.13).

**In chord.** The model picker lists providers. chord takes the first select
option of category `model` (`src/session/models.ts:72-82`), which in fx is
`provider`, so the picker sets the provider and the status line names it.
fx's real `model` option, and `fast` and `ultrafast`, are left out of
`/config` because their category is `model` (`src/session/config.ts:33-38`,
`:60`); a person cannot pick an fx model in chord. With no cost from fx,
chord's estimate prices the model it holds (`src/session/enrichers.ts:794-795`),
the provider id, so no price is found (inferred). @-mentions go as
`resource_link` (`src/files.ts:50`) and fx drops them, so file contents never
reach the model. fx's steering key differs from `_meta.steering.supported`,
so messages from other agents queue. Subagents are flat; their permissions
come on the parent. A command's live output shows only the newest chunk. A
mode picked in chord becomes the person's fx default outside chord. Notices
arrive as agent text, since chord does not declare `session.notices`.
Non-standard stop reasons read as completed (`src/session/session.ts:579`).
Ignored: titles, the empty command list, `elicitation/complete`, every
`_meta.fx` key and `command_result`.

**Sources.**

- fx v0.0.14, <https://github.com/vercel-labs/fx/tree/v0.0.14>, and `main` at
  c7f5a38a; its `CHANGELOG.md`.
- <https://fx.sh/docs/using-fx/acp>.

#### goose

- Name: goose
- Run as: `goose acp`, from PATH
- Install: <https://goose-docs.ai/docs/getting-started/installation>

goose v1.55.0, released 2026-10-16 and still the latest release on
2026-10-18, read at tag `v1.55.0` (commit 2bcb8583) of
<https://github.com/block/goose> (release notes now link `aaif-goose/goose`;
Apache-2.0, plain Rust, no limits on reading). chord starts it from its own
CLI table as `goose acp`, from PATH. The ACP Registry lists goose 1.55.0 as
binary archives only, so chord's npx-only registry leaves it out; since v1.50
goose is also on npm as `@aaif/goose-acp` (bin `goose`), which the registry
entry does not use. Paths are relative to `crates/goose/src/` unless they
start with `crates/` or `ui/`; the notes are the GitHub release notes.

**Footnotes.**

- **go1.** `acp/server.rs:1824`; a test stamps v1 when the client offers v2
  (`:3624-3668`).
- **go2.** `agent-client-protocol` 2.2.0, `agent-client-protocol-schema`
  =1.9.1 (`Cargo.toml:24-26`); the V1 SDK pinned since v1.47.
- **go3.** `sessionCapabilities {list, delete, close}`; fork handled but not
  advertised; a private `_goose/unstable/*` method set. No resume, no v2.
- **go4.** Answers `modes` and `configOptions`, then `usage_update` and
  `available_commands_update` (`acp/response_builder.rs:113-129`,
  `:486-504`). With no provider configured it fails `auth_required`
  (`acp/server.rs:175-181`).
- **go5.** Full replay, `_meta.replayTail` honoured
  (`acp/server/load_session.rs:102-210`). With tool confirmations pending it
  starts a turn on its own after the answer and sends
  `session/request_permission` (`load_session.rs:251-379`, `:450-470`).
- **go6.** User, scheduled and ACP sessions; subagent and hidden ones are
  left out (`acp/server/list_sessions.rs:68`, `:175`).
- **go7.** `acp/server/dispatch.rs:432-470`, `acp/server/fork_session.rs`.
- **go8.** `acp/server/manage_sessions.rs:88`, `acp/server.rs:2597`.
- **go9.** `auto` (approve everything, the default unless `GOOSE_MODE` says
  otherwise), `approve`, `smart_approve`, `chat`
  (`crates/goose-provider-types/src/goose_mode.rs:22-32`). `set_mode` sends
  `current_mode_update` (`acp/server/dispatch.rs:358-385`).
- **go10.** No `models` field and no `session/set_model`. Options in order:
  `provider` (no category), `mode`, `model` (category `model`),
  `thinking_effort` (`thought_level`) (`acp/response_builder.rs:304-333`).
  `config_option_update` follows a set, a provider refresh and an effort
  change (`acp/server/dispatch.rs:152-210`, `:306-311`).
- **go11.** off, low, medium, high, max, or the provider's own levels
  (`acp/response_builder.rs:337-372`).
- **go12.** Audio dropped. A text `resource` is inlined, a blob dropped
  silently; a readable `file://` `resource_link` is inlined, others stay a
  link line (`acp/server.rs:648-669`, `:1307-1345`).
- **go13.** Its own tool calls carry no `kind`; only the client-backed fs and
  terminal tools set one (`acp/server/tool_calls/conversion.rs:117-145`).
  Content is text and image (`conversion.rs:235-271`); `locations` unless
  the tool is "ACP-aware" (`:308-321`).
- **go14.** `in_progress` only when an MCP notification arrives for the call
  (`conversion.rs:118`, `:293-299`).
- **go15.** `allow_always`, `allow_once`, `reject_once`, `reject_always`, ids
  and names the kind string (`acp/server.rs:1567-1580`). `cancelled`, an
  unknown id or an error cancels the tool (`acp/common.rs:55-65`). Asked only
  in `approve` and `smart_approve`.
- **go16.** Only MCP servers' elicitations, as forms, when the client
  declares `elicitation.form` (`acp/server/elicitation.rs:206-214`). URL
  ones are cancelled inside goose, "ACP URL elicitation is not supported"
  (`elicitation.rs:60-77`).
- **go17.** `todo_write` keeps free text, shown as a plain tool call
  (`agents/platform_extensions/todo.rs:17-90`).
- **go18.** Cancels the run's token, subagents included
  (`acp/server.rs:2388-2405`, `agents/state_machine/ops_subagent.rs:199-230`).
- **go19.** A mid-turn `session/prompt` is refused `invalid_params`
  (`acp/server.rs:1890-1898`); steering goes through
  `_goose/unstable/session/steer` with the run id (`:1959-2007`).
- **go20.** The `delegate` tool
  (`agents/platform_extensions/summon.rs:395-526`); a child's permissions
  and forms come on the parent's id (`agents/subagent_handler.rs:144-170`).
  One child cannot be stopped.
- **go21.** `usage_update` after new, load, every provider call and the turn
  (`acp/server.rs:2195-2213`); answer `{totalTokens, inputTokens,
  outputTokens}` (`:719-724`); `cost` only when goose knows it (`:760-790`).
- **go22.** A generated title after a turn (`acp/server.rs:371-405`).
- **go23.** One `agent` method, "Configure Provider"; `authenticate` answers
  `{}` and does nothing (`acp/server/dispatch.rs:37-41`).
- **go24.** Client-backed tools replace its own when `fs` or `terminal` is
  declared (`acp/server.rs:1056-1100`, `acp/fs.rs:29-375`).
- **go25.** `mcpCapabilities {http: true}`; an SSE server fails
  `session/new`, "SSE is unsupported" (`acp/server.rs:482-518`).
- **go26.** `acp/server.rs:359-369`, `:1808-1831`; also image, embedded
  context and `_meta.goose`.
- **go27.** `acp/server.rs:1781-1806`, `:411-463`. Not read: `elicitation.url`,
  `plan`, `subagents`, `session.compaction`.
- **go28.** Eight extensions, each a bullet under Custom below.

**Custom.**

- `_goose/unstable/session/steer` with `session_info_update._meta.goose
  .activeRunId`: steering into the running turn. Unstable private name.
- `_goose/unstable/session/update`, after declaring
  `_meta.goose.customNotifications`: subagent notices, accumulated and
  per-message tokens and cost (`acp/server.rs:1697-1773`).
- `tool_call_update._meta.toolNotification`: live shell output every 150 ms
  with no `content` (`acp/server/tool_notifications.rs:26-69`); unread, a
  running command shows nothing until it ends.
- `_meta.goose.toolCall {toolName, extensionName}`: tool identity.
- `_meta.goose.toolCallLabelEnrichment`, declared: generated tool titles, at
  the cost of extra model calls (inferred).
- `session/new` `_meta` (`hidden`, `provider`, `sessionTitle`,
  `enabledExtensions`, `recipe…`) and `_meta.replayTail` on load.
- `_goose/unstable/providers/*`, `schedules/*`, recipes and system prompt:
  provider setup with a device-code OAuth, cron recipes, instructions.
- Launch flags `--with-builtin` and `--enable-scheduler`; env `GOOSE_MODE`,
  `GOOSE_DISABLE_SESSION_NAMING` (`crates/goose-cli/src/cli.rs:831-847`).

**In chord.** Models, modes and effort fit: chord's first `model`-category
select is goose's `model` (`src/session/models.ts:72-82`), and `provider`,
having no category, shows in `/config` (`src/session/config.ts:33-38`). The
first start fails with a bare start error until the person runs
`goose configure` outside chord. The default `auto` mode never asks. A
reopened session with approvals pending makes goose ask with no turn
running; chord rejects such a request unseen (CHD-158) and goose cancels the
tool (inferred from both code paths, not run). An SSE server in the person's
settings fails `session/new`, since chord passes servers unchecked. Live
shell output never shows; URL elicitations never reach chord; subagents are
one long call that Esc stops whole. goose's own tool rows have no kind. A
cost of 0, if goose sends one for an unpriced model, would stop chord's
estimate (CHD-380; whether goose sends 0 or nothing was not traced).
Ignored: titles, `_meta.goose.*`, `replayTail`; a mid-turn prompt is queued.

**Sources.**

- goose v1.55.0, <https://github.com/block/goose/tree/v1.55.0>, and its
  release notes v1.46 to v1.55.
- `@aaif/goose-acp` 1.55.0 on npm.
- <https://goose-docs.ai/docs/gdk/acp/>.

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
§2.2(3) forbids reverse engineering or otherwise discovering its source.
The owner's rule of 2026-10-18, recorded on CHD-433, allows a plain-text
read of such a binary only for the ACP contract. For this part the binary
was not downloaded or read at all, so nothing was deobfuscated and no cell
rests on it: every cell is `n` or `?`. The registry lists the same version
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

This is deliverable 3 of CHD-433: every open task and open question this reading
closes or changes, and the new tasks it suggests, as a list for the owner.
Nothing here is filed or decided. Each item names its agents with the section 3
footnote that holds the fact, as in `dimcode (dm20)`; where the fact sits in an
agent's Custom or In chord paragraph instead, the item says so. "The registry
page" is CHD-432's study,
[`design/registry-2026-10-17.md`](design/registry-2026-10-17.md), and "§6 item
n" its section 6.

### Permission safety

- **dimcode runs other agents unasked.** dimcode registers up to 18 CLIs it
  finds on PATH (claude, codex, cursor and others) as its own subagents, started
  with their approvals bypassed and spending on the person's own accounts
  (dimcode, Custom). No ACP switch turns this off; only dimcode's config, or its
  `permission` option gating its `agent` tool, does. Whether chord says or asks
  anything is open.
- **sigit's `/login` puts a password in chord's record.** `/login <email>
  <password>` goes to the agent as prompt text (si22), so the password lands in
  chord's session record (sigit, Custom). Whether chord says or does anything
  about it is open.
- **sigit calls sigit.si at every start.** It connects to its MCP server there,
  signed in or not, until `SIGIT_MCP_OFFICIAL=off` is set (si26; sigit, Custom).
  Whether chord names that anywhere is open.
- **agoragentic spends money with no permission step.** `agoragentic_invoke`
  spends USDC from the account behind `AGORAGENTIC_API_KEY` (agoragentic-acp,
  Custom). At the pin it is an MCP tool; attached as an MCP server to another
  agent, chord would see only the host agent's tool call. Whether this is a
  permission-safety item or a note for the guide is the owner's.
- **cursor approves without asking.** Cursor CLI 2026.10.16 approves a request
  that has no `toolCallId` without asking the client (cu11). It also counts a
  plan as accepted when `cursor/create_plan` gets method-not-found, which is how
  chord answers it (cursor, Custom).
- **zeroclaw's edits cannot be approved.** chord's SDK schema refuses zeroclaw's
  `reject_with_edit` option kind, so in supervised mode every file edit or write
  is answered invalid-params before chord sees it (zc9; zeroclaw, In chord).
  `docs/design/CHD-1.md:639-640` reads as if zeroclaw's permissions work; it
  speaks of the question fallback, not tool approvals. Is this a
  permission-safety item beside §6 item 1, and is the CHD-1 line to be
  corrected?
- **autohand's telemetry.** autohand sends telemetry to `api.autohand.ai` by
  default, with a persistent device id, labelled `clientType: "zed"` whatever
  the client; `AUTOHAND_TELEMETRY=0` stops it (autohand, Custom). chord takes
  registry entries as they are. Whether chord says so, sets the variable, or
  leaves it is open.
- **Spend the person does not see.** codex asks a model for a title after the
  first turn (cx22) and, in its default `agent` mode, has a model reviewer
  approve calls (cx9). codebuddy runs turns nobody asked for when a background
  task ends, folded under the last turn, and its permission requests in them are
  refused unseen (codebuddy, Custom and In chord). claude requests and pays for
  a prompt suggestion every turn, shown only to AIR clients, and a title call
  per session (cl22; claude, Custom). Options found for claude: send
  `_meta.claudeCode.options.promptSuggestions: false` on `session/new`, declare
  AIR and take its shapes, ask upstream to publish suggestions to every client,
  or leave it; for codex and codebuddy, whether chord shows, counts, avoids or
  refuses the spend is open.
- **nova's approvals may never reach chord.** The switch is the negotiated
  protocol version: at 1, chord's version, the method nova sends is not
  established, and if it is `permission/request` chord refuses it (no1, no10).
  The options stand: one tiny live check, leaving nova as it reads, or version 2
  for nova with its v2 permission shape.
- **Agents that ask in ways chord cannot answer.** autohand asks only under
  `AUTOHAND_PERMISSION_MODE=external`, and then its requests lack `toolCall` and
  chord's SDK refuses them (ah14). dirac sends boolean options `auto_approve`
  and `yolo`, the second bypassing approvals, which chord drops as it declares
  no boolean options (di11). bob's `--trust`, `--auto-approve` and
  `--accept-license` are opt-in and unused; the first two weaken bob's own
  safety and the last is legal consent on the person's behalf (bo4). Should
  chord offer any of bob's, or tell a `-p` user about `--accept-license`?
- **kilo's undeclared writes.** kilo calls `fs/write_text_file` without checking
  that chord declares `fs` (ki21). It is fire and forget and the approval still
  goes to kilo's server, so with chord it costs one refused request per approved
  edit, not a lost edit; the server-side write was not followed.
- **§6 item 1 stands.** minion-code fails open on the `cancelled` answer chord
  sends on Esc (mi11). deepagents never asks (da11). qoder rejects a tool after
  30 s while chord's box stays open (qo13). `--dangerously-skip-permissions`
  answers pi's extension selects with their first choice (pi11).

### Questions that reach many agents

- **Drawing `rawOutput` when a call has no content.** This one reaches the most
  agents. Results come only in `rawOutput`, which chord keeps but never draws,
  from cursor's shell (cu9), codebuddy's successful foreground Bash (cb10),
  minion-code (mi9), auggie's shell, file-view and MCP results (au7), minimax
  (mm12) and cline (ci11). Options found: draw it, take it upstream per agent,
  or leave it. Beside it in §6 item 5: deepagents' `input` and `output` and its
  `error` and `cancelled` statuses, drawn as `Waiting…` (da9, da10); gemini's
  mode changes as `[MODE_UPDATE]` reply text (ge6); fast-agent's resume, drawn
  twice (fa4).
- **MCP servers passed unfiltered.** chord passes the person's servers to every
  agent without checking `mcpCapabilities`. openclaw refuses any non-empty
  `mcpServers` on new, load and resume, so with any server configured no session
  opens (oc3). bob (on SDK 1.3.0) fails its whole new, load or resume on a
  single sse entry rather than dropping it (bo22); opencode v2 (op21), goose
  (go25) and codex (cx24) refuse sse too. glm fails new, load and resume on any
  sse entry or any server whose tool listing fails (gl4, gl25). autohand drops
  every server, chord's own included (ah22), while auggie passes its http and
  sse servers on without advertising either (au15). Options found: leave it and
  say so, hold servers back from an agent that does not offer their transport,
  or take it upstream.
- **@-mentions sent only as `resource_link`.** chord never embeds a mention,
  though most of these agents advertise `embeddedContext`. deepagents turns a
  link into `[object Object]` (da8); fast-agent does not percent-decode the
  path, so a path with a space reaches the model as a bare `file://` URL (fa9);
  autohand reads the file from disk itself, outside chord's view (ah10); fx
  (fx11), dirac (di12) and zeroclaw (zc7) drop links; how nova handles them is
  not established (no7). Whether chord sends embedded resources to such agents
  is open.
- **The model picker takes a `provider` select.** chord takes the first select
  of category `model` as the model. In fx (fx9) and cline (ci8) that is
  `provider`, so `/model` lists providers and the real `model` option is hidden
  from `/config` too; goose's `provider` has no category (go10). Options found:
  prefer the option whose id is `model`; prefer the `models` field when the
  `model`-category select is not id `model`; ask upstream to categorise
  `provider` differently; or leave it.
- **Images.** autohand advertises `image` but the model gets only `[Image 1]`
  and a size (ah9); cline advertises it and drops images, so an image-only
  prompt ends at once (ci10); deepagents labels every image `image/png` (da7);
  grok takes images without advertising `promptCapabilities.image` (grok-build,
  In chord). Options found for the dropped ones: leave it, report upstream, or
  warn when an image goes to an agent known to drop it; whether chord sends
  images to grok is open.
- **Session titles.** glm (gl22), sigit (si23), dimcode (dm22), fast-agent
  (fa17), minimax (mm22), pi after `/name` (pi16), codebuddy (cb20), qwen
  (qw15), codex (cx22), claude (cl22) and, by CHD-432, bob (bo19) send titles in
  `session_info_update`, which chord drops; auggie sends none. Whether chord
  shows them is open; no task asks it.
- **The agent's own sessions.** chord wraps `session/list` but never calls it;
  its pickers read chord's own records. glm's list has no paging (gl6); codex's
  returns the person's other Codex threads from the CLI and VS Code (cx6);
  claude (cl6), sigit (si7) and fast-agent (fa5) list too. sigit, claude, codex,
  bob and pi offer close and delete, which chord never calls; sigit keeps parked
  state, grants and background commands until its process exits (si9), and
  codex's delete only archives (cx8). Whether chord wants a picker over the
  agent's list, or close and delete, is open.
- **Login and `authenticate`.** chord never calls `authenticate` (§6 item 3).
  Terminal methods: auggie (au14), minimax (mm23), dimcode (dm23) and kilo (ki1)
  list one only behind `auth.terminal` or `_meta["terminal-auth"]`, and pi
  always (pi17), so option (c), chord running it in a terminal of its own, would
  reach pi without that key; kilo's tells the person to run `opencode auth
  login` (ki1). Agent-run methods: cline's browser OAuth (ci21), bob's `sso`
  browser login (bo4), gemini's API key or gateway in `_meta`, a secret through
  chord (ge17), and goose's no-op, whose fix is `goose configure` outside chord
  (go4, go23). qoder reads its token variable only once its `env_var` method is
  authenticated, though its docs say the variable alone logs in (qo22); droid's
  sign-in is under New tasks. Whether an own CLI's sign-in failure names its own
  way in (`kimi login`, km23) is open.
- **Slash commands hidden behind chord's own.** chord's `/mcp` hides claude's
  (cl21); its `/mcp` and `/status` hide codex's (cx21), where Codex shows token
  usage and rate limits. The same names collide on devin (`/mcp`, `/help`,
  `/status`, dv21), kimi (`/help`, `/mcp`, `/status`, km22) and poolside
  (`/clear`, `/mcp`, po11). This widens U8 in the registry page.
- **Requests with no turn running (CHD-158).** Deterministic cases now: goose
  after loading a session with confirmations pending, qwen's own turns,
  codebuddy's unasked turns, opencode v2's children after a cancel, and auggie's
  indexing permission right after `session/new`. Details are under CHD-158
  below; the owner's Q29–Q32 options stand.
- **Steering dialects.** chord speaks only `_session/steering`. dimcode (dm18),
  dirac (di18), fx (fx18), goose (go19), kiro (kr13), minimax (mm18), poolside
  (po8), qwen (qw11) and grok (gr18) each steer through their own method or
  `_meta` key. Whether chord speaks any of them, asks an agent for
  `_meta.steering`, or keeps queueing is open; CHD-378 below has each agent's
  answer to a second prompt.
- **Private keys and agent-specific extensions.** Each needs chord to send or
  read a key one agent defines, so each is the owner's under the one rule:
  cursor's `_meta.parameterizedModelPicker` for efforts (cursor, Custom);
  claude's `_meta.claudeCode.options`, tying chord to Anthropic's SDK option
  names (claude, Custom); droid's and pi's `_meta.terminal_output` read as a
  delta (see New tasks); goose's live output in `_meta.toolNotification` (goose,
  Custom); nova's `_meta.compass.permissionScope` (no10); minimax's opt-in
  subagent notifications (mm19); fast-agent's usage status line (fa15); grok's
  `_meta.askUserQuestion: false` (grok, Custom); codebuddy's
  `_meta["codebuddy.ai"].question` (see New tasks); and qwen's
  `_qwencode/start_turn`, answered method-not-found (admits the turn),
  `{accepted: false}` (defers it), or served on screen (qw20).
- **Boolean config options.** dirac's `auto_approve` and `yolo` (di11) and
  Junie's likely `brave_mode` (Junie, Custom) are booleans; chord declares none
  and `/config` lists only selects. Whether chord declares and shows them is
  open.
- **Which opencode chord supports.** Two programs answer `opencode acp` as
  `agentInfo.name "OpenCode"`: v1 1.19.3 and v2 2.0.32, with different forms,
  child traffic, fs calls, slash handling and live output (op21). chord's
  question enricher in `src/session/enrichers.ts` matches neither: v2 titles the
  own-answer field `<header> (other)` and a subagent's message `<child>:
  Questions` (op10), so the fixture and the `askopencode` scenario test a shape
  no release sends. Which opencode, and what the enricher, fixture and scenario
  follow, is open.
- **Registry pins behind upstream, and agents that fail to start.** The registry
  pins qoder at 0.2.14 against npm's 1.1.73, about 60 releases behind, while its
  docs describe the newer one (qoder, intro); minimax at 0.2.7 against 0.6.12
  (minimax-code, intro); agoragentic at 1.3.0 against 1.3.6, which would turn
  the start failure into a canned refusal; and kimi's entry at the archived
  Python 1.52.0 (kimi, intro). minion-code 0.1.44 likely fails to import under
  `uvx` today, as uv resolves an `agent-client-protocol` without the types it
  imports; upstream 0.1.45 fixes the bound (mi2). agoragentic is not an ACP
  agent at the pin (ag3, ag4). §6 item 4's options apply: say why in the start
  failure, hide it, or report it upstream.
- **Live checks.** Several cells can only be settled by a tiny live run: an
  `initialize`-only check of `devin acp` (devin, intro), `junie --acp true` for
  `initialize`, `session/new` and one form (Junie, intro), one prompt on
  poolside, which spends the owner's account (po6), Copilot, also on the owner's
  account (github-copilot-cli, intro), and nova's approvals above. Which, if
  any, the owner allows is open.

### Open tasks

- **CHD-2** (new evidence), A list of the background tasks an agent runs: each
  one's state, its end, and a key to stop it: dimcode's background work is
  readable, as `background:<taskId>` calls with `_meta.lody.task` and one stop,
  `_lody/subagents/cancel` (dm19). codebuddy's backgrounded command already
  reaches chord with its `terminalId`, and its stop is a private method that
  starts no model call (codebuddy, Custom). claude's and codex's background work
  stays AIR-only, and declaring AIR changes subagent and Edit/Write shapes
  (claude, Custom; codex, Custom); grok (gr19), qwen and kimi show it only
  through their own methods or text, and bob, droid, cursor and devin give a
  list nothing to read.
- **CHD-55** (new evidence), After the agent fails to start, a submitted prompt
  sits in the box with no word and the status line goes blank: agoragentic lands
  here on every start (ag4). cursor (cu3), droid (dr4) and bob (bo4) fail
  `session/new` with `authRequired` without a login, bob also on an untrusted
  folder or an unaccepted licence; openclaw exits without a running Gateway
  (openclaw, In chord); a Python `kimi` 1.52.0 exits without answering
  `initialize` (kimi, In chord). Whether sigit's "No on-device model is loaded"
  first reply reads as a start failure is open (sigit, intro).
- **CHD-58** (new evidence), Record successful model changes in the transcript:
  kilo sends no `config_option_update`, so a model it picks itself is never
  reported (kilo, In chord); qwen reports one only through
  `qwen/notify/session/model-update` (qwen, Custom).
- **CHD-77** (new evidence), Fake agent: offer a second select config option so
  /config's Esc-back highlight can be seen on screen: Junie's `brave_mode` is
  likely a boolean, a kind the fake agent does not offer (Junie, Custom).
- **CHD-93** (new evidence), MCP servers: expand ${VAR} and ${VAR:-default} in
  .mcp.json as Claude Code does: beside the task, not in it: one sse entry, or
  one server whose tool listing fails, makes glm's whole session fail to open
  (gl4, gl25).
- **CHD-101** (new evidence), Rewind (Esc Esc) to an earlier prompt: claude
  (cl7) and codex (cx7) take a fork point through `_meta.jetbrains.air.fork`
  with no AIR declaration, and chord keeps each message's `messageId`; is an
  AIR-namespaced key acceptable for rewind, or only a field in the ACP spec? glm
  forks only the latest state and cancels the source's turn (gl7); sigit forks
  the whole conversation, a branch rather than a rewind (si8); kilo replays the
  last 20 messages (ki6); nova's fork is not established as `session/fork`
  (no4). bob, cline, droid, gemini, pi and dirac have none; grok and qwen have
  their own methods.
- **CHD-127** (changes), Live check with fx, second pass: rerun the CHD-126
  matrix against fx once its network works: fx's `code` mode is `auto` since
  0.0.14 (fx8), and the matrix needs rows for the `provider` picker, dropped
  @-mentions and the missing cost.
- **CHD-139** (new evidence), A refused resume names the session id twice:
  refused resumes occur on dirac for every session chord recorded, as
  `session/resume` is method-not-found (di6); on sigit for a session whose first
  turn never finished (si6); on openclaw once its bridge restarts (oc5). A kiro
  v2 `session/load` of a lost session never answers at all (kiro, In chord).
- **CHD-151** (new evidence), An @ mention followed by punctuation sends no
  link: dirac (di12) and zeroclaw (zc7) drop every `resource_link`, so mention
  links do nothing there whatever chord sends.
- **CHD-158** (changes), A subagent that outlives its turn and then asks
  permission is refused: qwen starts turns of its own when background work ends,
  chord's method-not-found to `_qwencode/start_turn` admits them, and their
  permissions come with no turn running (qw10, qw20). goose starts a turn and
  asks after loading a session with confirmations pending (go5, inferred);
  opencode v2 forwards the asks of a cancelled turn's children (op12);
  codebuddy's unasked turns and kimi's background subagents ask with no turn
  too. auggie's indexing permission
  comes right after `session/new`, and chord's unseen `reject_once` turns
  indexing off for the session (au9). bob's `sso` login through `authenticate`
  would also come before the first turn. dimcode, devin, kiro and poolside may
  ask outside a turn (unproven); cursor, openclaw and sigit do not widen it.
- **CHD-214** (new evidence), --resume with several ids: check every case and
  refusal against the help and the docs, and make them true and readable:
  `--resume` of a recorded dirac session fails as under CHD-139 (di6),
  openclaw's refused resume bears on its refusals (oc5), and goose reopens only
  by load (go5).
- **CHD-229** (new evidence), Open agent call: show the model actually selected
  when model is omitted: as under CHD-58, kilo and qwen do not report a model
  they pick, so chord shows the last value it had.
- **CHD-244** (new evidence), /new: refuse a missing own CLI before opening a
  tab, with its install hint: autohand's npx adapter needs `autohand-cli`
  installed globally, and `initialize` then offers only an install method
  (autohand, In chord). goose is also on npm as `@aaif/goose-acp` since v1.50;
  whether chord starts `goose acp` from PATH, falls back to `npx`, or asks the
  ACP Registry to list the package is open (goose, intro). The PATH check cannot
  tell the archived Python `kimi` from Kimi Code; whether chord says so is open
  (kimi, intro). Junie, kiro, opencode, poolside and zeroclaw are further cases;
  cursor still gets no hint; openclaw's hint says nothing of the Gateway.
- **CHD-333** (changes), A shell command in a permission wraps inside a flag at
  a hyphen: the premise now holds for droid, whose permission `toolCall` carries
  the tool's `rawInput` and a `` `<command>` (<risk>) `` title (factory-droid,
  In chord).
- **CHD-341** (new evidence), Resuming a session brings its team runs back:
  dirac's method-not-found resume stops team runs coming back (di6); openclaw
  refuses resume where load of the same id would replay (oc5); goose has no
  `session/resume`, so chord loads with a full replay, and goose honours
  `_meta.replayTail`, which chord does not send (go5). For dirac, the options
  found are: report upstream, fall back to `session/load` on method-not-found,
  which would be a workaround, or wait.
- **CHD-373** (changes), How much a team run, a task agent and the window have
  spent: dimcode's standard `usage_update` carries the session's total cost with
  no opt-in (dm20); dirac's `PromptResponse.usage` is a session total read as
  the turn's, so chord overcounts (di20); claude (cl20) and codex (cx20) send
  per-model `_meta.quota` to every client. grok's tokens and cost are only in
  `PromptResponse._meta` (gr20), goose's only behind a custom notification
  (go21), fast-agent's only as a text status line (fa15), qwen's only in
  `_meta.usage` on empty chunks (qw13). bob, cline, cursor, zeroclaw, kiro and
  devin send none; Copilot's premium requests have no ACP cost.
- **CHD-374** (changes), Does Codex's answer to a prompt carry the whole turn's
  tokens, or only its last request's?: in codex 2.2.2 the answer's usage is the
  whole turn's, while `usage_update.used` is still the last request's (cx20).
  dirac's is cumulative over the session (di20) and glm's sums every model call
  in the turn (gl20). How chord reads cumulative answer usage is open.
- **CHD-378** (new evidence), A person's message sent during a turn waits for
  the turn to end; the person wants a key that steers it into the running turn:
  a plain second `session/prompt` would abort the running turn on gemini (ge13),
  glm (gl18), openclaw (oc13), qoder and cursor (cu15); run a second loop at
  once on auggie (au11), fast-agent and deepagents; and be refused by bob
  (bo15), droid (dr18), kimi (km19), minimax (mm18), zeroclaw (zc13), dimcode
  (dm18), dirac (di18), opencode v2 and fx unflagged (fx18). codex ignores
  `idleBehavior: "promptRequired"`, so a late steer starts a new turn; devin
  (dv18), Junie and cline steer in their CLI but not over ACP. chord's queue
  avoids all of these; steering dialects are a question above.
- **CHD-380** (changes), An agent's cost of 0 hides chord's estimate: fx on a
  ChatGPT subscription would read $0.00: fx 0.0.14 sends no cost at all, so the
  example is out of date (fx20). dimcode sends 0 for an unpriced model (dm20);
  opencode's free models (op15) and kilo's report a true 0; goose may send 0 on
  unpriced local models, untraced (go21). claude sends its cost only at the
  turn's end (cl20); most others send none.
- **CHD-381** (new evidence), Update @pydantic/genai-prices from 0.1.9 to
  0.1.12: not in genai-prices: dirac's default `gemini-4-argon`, gemini's `auto`
  and own ids (gemini, In chord), Copilot's `claude-haiku-5.5` and
  `gemini-4-argon`, and grok's `Auto`. Whether fx's provider-prefixed ids match
  is unread.
- **CHD-382** (new evidence), Report chord's status to the terminal through OSC
  7501 (Program Status Protocol): fx emits OSC 7501 in its own TUI, which does
  not bear on `fx acp`.
- **CHD-383** (changes), Questions qwen, cursor and nova ask outside a form
  reach the person and are answered: grok belongs on the list; its
  `x.ai/ask_user_question` is on by default, chord answers it method-not-found,
  and only `_meta.askUserQuestion: false` turns it off (grok, Custom).
  `docs/design/CHD-1.md:41`, `:83` and `:641` call it opt-in; correcting them is
  the owner's. cursor falls back to a permission box with "Skip" per
  single-select question and drops multi-select ones (cu12; cursor, Custom); is
  that enough, and should `-p` with `--dangerously-skip-permissions` answer it
  with its first option? qwen's questions ride on a permission in
  `toolCall._meta.qwenQuestions` (qwen, Custom); nova still asks through
  `session/requestUserInput` (no11).
- **CHD-389** (changes), A task agent's question box is headed by its runtime's
  name: an opencode v2 subagent's question comes under `<child>: Questions`
  (op10).
- **CHD-390** (new evidence), ctrl+o's expanded tool output cuts long lines at
  the width instead of wrapping them: goose's live output travels in
  `_meta.toolNotification` (goose, Custom).
- **CHD-391** (new evidence), chord -p --output-format json says nothing of the
  questions an agent asked: bob's licence form comes at the start of every
  prompt until accepted, so `-p` declines it every run and the JSON says nothing
  (bo24).
- **CHD-392** (changes), Verify how minimax-code, devin, poolside, kiro and
  junie ask the person a question: bob's form (`properties.answer`, optional
  `properties.other`, bo13), Kimi Code 2.x's (km16) and opencode v2's (op10) are
  none of CHD-1's shapes, and none of the three is on the list; CHD-1's "kimi
  declines the tool" holds only for the Python CLI. zeroclaw's form is known and
  needs no place (zc10). minimax's is confirmed in code at a pin far behind
  upstream (mm15); devin's (dv16), Junie's (ju13), kiro's (kr11) and poolside's
  (po6) stay unknown. Copilot's question path under `elicitation.form` is open
  again (co15), and `CHD-1.md`'s cursor row lacks the permission fallback.
- **CHD-401** (new evidence), chord agents reads as a plain, readable list, not
  a wide table of raw commands: facts such a list could show: agoragentic opens
  no session (ag4), autohand needs `autohand-cli`, openclaw needs a running
  Gateway, zeroclaw's supervised edits cannot be approved. chord's "Kimi Code"
  fits its argv while the registry's `kimi` is "Kimi CLI" 1.52.0; kiro's argv
  may change when CLI 3.0 makes V3 the default.
- **CHD-404** (new evidence), A Bash call that is running reads as running:
  auggie (au8) and cursor (cu10) never send `in_progress`; droid sends it only
  for a running shell and closes open shell calls `failed` at the turn's end
  (dr13); goose's calls stay `pending` until done, its live output only in
  `_meta.toolNotification` (go14; goose, Custom). Whether a call with no
  `in_progress` reads as running is open.
- **CHD-405** (changes), /cost on a picked Codex child names claude, and says
  nothing of what a long first turn has spent: dimcode has its own session total
  to show (dm20); codex's turn usage lets a long first turn be counted whole,
  still with no cost (cx20); claude's `_meta.quota` is there to read (cl20).
  grok's cost is only in a private `_meta` (gr20); goose's standard usage
  carries cost only when it knows the price (go21); cursor, cline, bob and
  Copilot give nothing.
- **CHD-426** (new evidence), Claude's own cycle after a background task ends,
  and a resumed session's background tasks: codebuddy has the same cycle with no
  opt-in, marked by `_meta["codebuddy.ai/unsolicitedTurn"]` and a non-standard
  `session_end`, which chord folds under the last turn (codebuddy, Custom). kimi
  starts a turn when a background task ends and ACP drops it (kimi, In chord);
  codex restores async tasks only for AIR; cursor replays a running subagent as
  `disconnected`; devin parks subagents on interrupt (dv17); grok reports
  background work only on its own notification.
- **CHD-428** (new evidence), Remote Control on Claude: `/remote-control`
  reaches claude as a plain prompt; what chord sees of a prompt or permission
  answer sent from claude.ai was not read (cl21).

### Open questions

The thirteen questions `board questions -p CHD` lists as open, each with what
this reading does to it.

- **Q26 (CHD-2).** **Premise changes.** Declaring AIR still switches claude's
  subagents to the draft `subagent_spawned` shape and drops Edit's and Write's
  `rawInput` (claude, Custom), and codex's AIR changes every update's shape
  (codex, Custom). Without AIR, a cancel on a claude child's id stops that
  child (cl19), while background subagents outlive the parent's cancel (cl17);
  on codex a child id stops nothing (cx17). The question's "no other registry
  adapter" no longer holds: codebuddy stops one background task by the
  `terminalId` its backgrounded call carries opt-in or not, with no model call
  (cb10; codebuddy, Custom), its private opt-in needed only for the task's
  state and output; dimcode stops a subagent by `_lody/subagents/cancel`
  (dm19; dimcode, Custom) and grok by `x.ai/subagent/cancel` (gr19).
- **Q27 (CHD-409).** **Premise changes.** CHD-432's C11 reads the adapter bug
  as fixed upstream since claude 0.90, from code and not run. This reading
  adds nothing: claude-acp's part has no footnote on the Agent call's hook
  result.
- **Q28 (CHD-404).** **Premise changes.** The question rests on claude and
  codex; claude's Bash stays `pending` until done (cl13) and codex's call is
  `in_progress` while it waits on an approval (cx13), as it says. More agents
  never send `in_progress`: cursor, but for plan and `Watching:` calls (cu10),
  and auggie (au8); goose sends it only on an MCP notification (go14), droid
  only for a running shell (dr13). codebuddy sends `in_progress` every second
  while a shell call runs (cb10). codex also sends
  `session_info_update._meta.codex.threadStatus` (codex, Custom), whose values
  its part does not give.
- **Q29–Q32 (CHD-158).** The cases with no turn running are no longer only
  claude's and codex's; the options in the questions are untouched.
  - **Q29 (P1).** **Premise changes.** New cases: qwen's own turns (qw20),
    goose reopening a session with approvals pending (go5; goose, In chord,
    inferred), opencode v2's children after a cancel (op12), codebuddy's
    unasked turns (codebuddy, Custom and In chord), kimi's and grok's
    background subagents (kimi, In chord; grok, In chord), auggie's indexing
    permission right after `session/new` (au9), and droid's sign-in URL during
    `session/new`, before any session exists (dr15; factory-droid, In chord).
    Today's refusal is not inert: auggie's unseen `reject_once` turns indexing
    off for the session (auggie, In chord), and goose cancels the tool, inferred
    (goose, In chord). qwen marks such permissions `_meta.backgroundTurn` and
    lets a client defer the turn with `{accepted: false}` to
    `_qwencode/start_turn` (qw20). Not cases: gemini's permission for an unseen
    call id comes inside a prompt, before its first update (gemini, In chord);
    cline's queued second prompt is never reached, as chord queues its own
    (ci16; cline, In chord); minimax's part names no ask outside a turn, only
    subagent asks sent to the root session (mm19).
  - **Q30 (P2).** **Standing.** The agents' own clocks differ: grok times an
    unanswered permission out by a backstop deadline and re-sends it on
    re-attach (gr14), qoder rejects the tool after 30 s (qo13), and claude
    (cl14) and codex (cx14) set no timeout of their own.
  - **Q31 (P4).** **Standing.** Nothing an agent sends bears on which keys a
    box takes.
  - **Q32 (P3).** **Premise changes.** What the agent gets differs by agent:
    auggie's first prompt waits until its indexing permission is answered
    (au9), and kimi answers a prompt sent during a turn it started itself
    `end_turn` at once and runs it later, unseen (km19).
- **Q33–Q36 (CHD-389).** **Standing.** main, a `spawn_task` task, a long-lived
  child and a team member are chord's own askers; no agent's part has a field
  that names them.
- **Q37 (CHD-389).** **Premise changes.** For an agent's own subagent, the
  agent decides what can be named: opencode v2 already names the child in a
  subagent form's message, `<child>: Questions` (op10), while minimax's
  subagents ask on the root session (mm19) and dirac's children's approvals
  come as the parent's (di19), so neither can be told from main. grok names
  the asking session on permission requests, `x.ai/requestingSessionId`, but
  its questions never reach the person (grok, Custom).
- **Q38 (CHD-228).** **Standing.** It rests on chord's agents list, which no
  agent feeds.

### New tasks it suggests

New items that a question above already holds are not repeated here.

- **Fake-agent scenarios.** The fake agent cannot play shapes these agents send,
  so chord's behaviour on them has no test:
  - `authRequired` on `session/new`: bob, cursor, goose, kimi;
  - forms and permissions: bob's licence form at a prompt's start, cursor's
    question as a permission with Skip, kimi's `q<i>` form, opencode v2's
    `<header> (other)` form, zeroclaw's non-standard option kind and cancelled
    answer with `content`, grok's extension requests;
  - sessions: a kiro `session/load` that never answers, openclaw refusing resume
    while load works, a goose load that starts a turn with a permission request,
    `session_info_update`s carrying only `_meta` (kiro, opencode);
  - a second prompt refused: kimi's -32600, zeroclaw's `SESSION_BUSY`;
  - tool calls: output only in `rawOutput` or replaced chunk by chunk (cursor,
    bob, fx, kimi), skipping `in_progress` (cursor, zeroclaw), starting
    `in_progress` (openclaw), with no `kind` (goose), a call left `pending`
    after a cancelled permission (bob);
  - usage only in `PromptResponse._meta` (grok), tokens without `totalTokens`
    (fx), `usage_update` after the answer (kimi);
  - agent text outside a turn or after the answer (kimi, Junie), a
    `session/set_model` answered method-not-found (minion-code), a `provider`
    option first among model selects (fx) or uncategorised (goose), and
    openclaw's refusal of non-empty `mcpServers`.
- **droid's sign-in elicitation is cancelled.** An unsigned-in droid sends its
  sign-in URL elicitation during `session/new`, before chord subscribes to the
  session's elicitations, so chord answers `cancel` and the first run fails
  "Sign-in was cancelled" (dr15; read, not run). Options found: answer an
  elicitation that arrives with no session yet; stop declaring `elicitation.url`
  before a session is up, so droid fails with the device code in its error; or
  leave it, and the person signs in outside chord or sets `FACTORY_API_KEY`.
- **Deltas chord reads as the whole output.** droid's `_meta.terminal_output`
  carries only the new part under the name chord reads as the whole; chord
  declares `terminal_output_delta`, so droid resends the whole output as text,
  and declaring `terminal_output` would show only its last chunk (dr12;
  factory-droid, Custom). pi's is the same (pi10; pi-acp, In chord); reading
  either as a delta treats one agent's key differently.
- **grok's plan mode.** grok's `x.ai/exit_plan_mode` gets method-not-found, and
  grok ends the turn as cancelled while staying in plan mode (grok-build,
  Custom). How chord reads such a turn, and whether `exit_plan_mode` is ever
  answered, is open; no task covers it.
- **gemini's permission inside a prompt.** A `@` mention outside the workspace
  makes gemini ask before the turn's first update, with a tool call id no
  `tool_call` announced (gemini, In chord). Whether chord draws that box with a
  call to attach it to is not checked.
- **dirac's two effort selects.** dirac sends two `thought_level` selects and
  chord takes the first, `reasoning_effort`; which governs each model is not
  established (di11).
- **zeroclaw's agent alias.** chord sends no ZeroClaw agent alias, so
  `session/new` fails when ZeroClaw has several agents and no default (zeroclaw,
  In chord). Whether chord passes `agentAlias` on `session/new`, or `--agent`
  once released, is open.
- **codebuddy's questions.** Its `AskUserQuestion` tool is off unless the client
  declares `_meta["codebuddy.ai"].question: true`; chord would then answer
  `_codebuddy.ai/question` with `{outcome: "submitted", answers}` (codebuddy,
  Custom).
- **Notes for the guide or the agent list.** A fresh dimcode session is
  `read-only`, asking nothing and denying writes and commands (dm4, dm14); a
  mode picked in chord becomes the person's saved fx mode for the CLI too (fx8);
  goose cancels MCP URL elicitations itself though chord declares `url` (go16);
  the registry's `DROID_DISABLE_AUTO_UPDATE` occurs nowhere in droid 0.244.0,
  where only `FACTORY_DROID_AUTO_UPDATE_ENABLED=false` works (factory-droid,
  Custom). Whether each is a note, a mark or nothing is open.
- **A stale comment.** `src/acp/connection.ts:58-61` says claude answers
  `session/set_model`; claude 0.93.0 has no such handler (claude, In chord).
- **kiro after CLI 3.0.** Whether kiro's argv gains `--agent-engine=v3` before
  or after CLI 3.0, due at the end of October 2026, and whether kiro is read
  again then (kiro, intro).

### Corrections to CHD-432

What this reading found different from the registry page; each is corrected in
that page unless it says otherwise.

- claude's `session/fork` takes a fork point through `_meta.jetbrains.air.fork`
  without AIR, so "no fork point" holds for ACP, not this adapter (cl7).
- claude's own usage reaches every client through `_meta.quota` (cl20); qwen has
  no `_meta.quota` (qw13), and Copilot's cell had no source.
- codex's `PromptResponse.usage` is the whole turn's, so CHD-374 is affected
  (cx20).
- dimcode's usage and cost come in the standard `usage_update`, with 0 for an
  unpriced model, and its form is standard `elicitation/create`; `_lody` only
  adds extras (dm15, dm20).
- dirac advertises resume but defines only `unstable_resumeSession`, so chord's
  `session/resume` is method-not-found (di6); its answer usage is a session
  total (di20).
- fast-agent starts on current uv (0.13.1), not on uv 0.6.12.
- grok's questions are on by default, not opt-in (CHD-432's gr4; grok, Custom).
- qwen widens CHD-158 through its own turns (qw20).
- claude's `/mcp`, and codex's `/status` beside its `/mcp`, are hidden behind
  chord's (U8).
- bob's B6: after `session/cancel`, the next prompt waits for the cancelled turn
  to end rather than being refused.
- qoder: facts resting only on CHD-432's `webcrack` read of its bundle were
  dropped; whether that read was acceptable is the owner's to weigh.
- codex's own-usage cell, as `_meta.quota` reaches
  every client (codex, Custom), and its session-title cell, as it sends titles
  to every client (cx22); minion-code's mi2 (`session/set_model` is
  method-not-found, not a silent success) and mi3 (fork, resume and list are
  unreachable, not empty sessions) (mi7); minimax's blank "MCP over http" cell,
  which is ✓; pi's blank session-title cell, as pi sends titles after `/name`
  (pi16); and cline's `provider` picker, which the page did not mention: all
  corrected in that page.

## Sources

Each agent's part names what was read for it, by package and version or
public repository and tag, and its docs and release notes. Beside those:

- chord at HEAD 287fedc3 for section 2: `src/acp/`, `src/session/`,
  `src/headless.ts`, `src/agents.ts`, `src/clis.ts`, `src/registry.ts`, and
  `@agentclientprotocol/sdk` 1.8.0 as chord pins it.
- [`design/registry-2026-10-17.md`](design/registry-2026-10-17.md), CHD-432's
  study at the same registry pins, reused where a cell is marked `r` and
  corrected where this reading found otherwise.
- [`design/CHD-1.md`](design/CHD-1.md) for the forms and permissions of the
  agents it covers, and [`decisions.md`](decisions.md).
- The ACP Registry as fetched on 2026-10-17 (`src/registry.ts`), and on
  2026-10-18 for the entries chord does not take (`kimi`, `devin`).
- The ACP specification and schema at <https://agentclientprotocol.com>.
