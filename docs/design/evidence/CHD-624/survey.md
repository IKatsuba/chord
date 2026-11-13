# CHD-624 — survey: upstream ACP and the agents chord runs

A survey for the owner's decision, not a design. Read 2026-11-13 against
origin/main 49b4c650c (chord 0.70.0). For every runtime chord starts it says
what changed upstream since the version chord pins or last read, what several
runtimes now serve in common, and what chord could do with each item, with
options where it is a choice. Nothing here is decided; section 5 lists the
decisions that are the owner's.

How it was read: npm and PyPI metadata, GitHub releases, changelogs and
commits, the ACP schema and SDK diffs between tags, the ACP Registry as
fetched today (46 agents) and its own daily probe
(`.protocol-matrix/latest.json`), and packages unpacked and read as text,
never run. No agent was started and no prompt was sent. For the
licence-limited agents (bob, cursor, nova, auggie, factory-droid, poolside,
plus `@cursor/sdk`, proprietary) only what crosses the wire was read, docs
and release notes first, per the owner's rule of 2026-10-18 recorded in
[`agent-capabilities.md`](../../../agent-capabilities.md). Baseline: that
file (CHD-433, refreshed by CHD-561) and `src/registry.ts` (fetched
2026-11-01). Marks: `c` read in code or bundle, `n` release notes or docs,
`?` unknown.

## 1. Versions

### Protocol and chord's own dependencies

| Package | chord | Latest (date) | What it means for chord |
| --- | --- | --- | --- |
| `@agentclientprotocol/sdk` | 2.2.0, schema 1.28 | 2.6.0 (11-10), schema 1.31; v2 alpha.15 | Additive only: no exported type removed; `ToolCallContent` gains `session`, caught by chord's `default` branch c |
| ACP schema | 1.28.0 | 1.31.0 (11-10); 1.32.0 release PR open today | 1.32 brings a `speed` config category, initial config on `session/fork`, v2 `replay_complete` |
| `@opentui/core`, `@opentui/react` | 0.8.1 | 0.8.4 (11-10) | `suspend()` fix helps `$EDITOR`; text height (0.8.2) and width method (0.8.3) can move layout: needs a visual pass at 120x40 and 80x24 |
| `@anthropic-ai/claude-agent-sdk` | 0.3.316 | 0.3.323 (11-12) | chord uses only the usage getter in `src/platform/resource_worker.ts`; unchanged c |
| `@anthropic-ai/sdk` | 1.3.0 | 1.8.0 (11-10) | Imported nowhere; a peer of the agent SDK |
| `@modelcontextprotocol/sdk` | 1.32.2 | 1.32.2 | current |
| `@pydantic/genai-prices` | 0.2.1 | 0.2.3 (11-10) | prices Anthropic fast mode: chord's estimate under `/fast` (CHD-626) |
| `string-width` | ^8.3.0 | 9.0.0 (11-11) | Major; widths changed; must agree with OpenTUI's width method; stays out under the caret |
| `marked`, `markdansi`, others | — | patches and minors | Nothing of note |

### Runtimes

| Runtime | chord pins or last read | Latest (date) | ACP SDK in it | New ACP methods served |
| --- | --- | --- | --- | --- |
| claude (`claude-agent-acp`) | 0.99.1 | 0.107.0 (11-13) | 2.1.0 → 2.6.0 | `session/set_title`, `session/status`, `session/options` + initial config, `auth/status` + `auth/status_update`; v2 on request |
| codex (`codex-acp`) | 2.5.0 | 2.6.0 (11-08); 2.6.1 previews | ~2.1 → ~2.4 (main ~2.6) | `session/set_title`; `systemPrompt` (already at 2.5.0) |
| cursor (`agent acp`) | 2026.10.16 | 2026.11.11 | ? (licence) | none found |
| cursor-cloud (ours) | 0.1.0 on `@cursor/sdk` 1.3.1 | `@cursor/sdk` 1.3.1 is latest | 2.2.0 | serves none of them yet; the SDK could back several (section 2) |
| gemini | 0.66.0 | 0.68.0 (11-10); 0.69 preview | 0.16.1, exact | none |
| github-copilot-cli | 1.0.105 | 1.0.111 (11-13) | ? (closed) | none named |
| opencode v2 (`@opencode/cli`) | read at 2.0.32 | 2.3.0 (11-13) | 1.6.0 | none standard; `_session/steering` (2.2.7) |
| opencode v1 (`opencode-ai`) | read at 1.19.3 | 1.19.5 (10-28) | 0.21.0 | none |
| goose | read at 1.55.0 | 1.59.0 (11-10) | Rust 2.2.0 | none; `_meta.tags` on new and list |
| kiro | read at 2.31.1 | 3.3.0 (11-12) | ? | terminal auth; V3 engine by default |
| kimi (Kimi Code) | read at 2.2.0 | 2.6.2 (11-13) | ^1.3.0 | none; `logout` advertised |
| factory-droid | 1.1.0 | 1.10.0 (11-12) | ? | `auth/status` + `auth/status_update`, `logout` |
| dirac | 0.5.24 | 0.5.24 | 1.3.0 | `logout` advertised |
| devin, junie, openclaw, fx, zeroclaw, poolside | read in CHD-433 | point releases | unchanged where known | none |
| rest of the registry | `src/registry.ts` | section 2.8 | mostly 0.x–1.x | none |

None of the agents read, other than claude and codex, carries the strings
the SDK gained at 2.3–2.6 (`session/set_title`, `session/status`,
`session/archive`, `session/options`, `terminal/cancel`). Every agent the
registry probe reached answers protocol version 1, and claude-agent-acp is
the only one that serves version 2.

## 2. Per runtime

### 2.1 Claude — `@agentclientprotocol/claude-agent-acp` 0.99.1 → 0.107.0

Ten releases, 2026-11-02 to 11-13; bundles Claude Code 2.1.323.

New on v1, which chord speaks (c, `v1/acp-agent.js`):

- `session/set_title`, `session/status` (0.105.0), `session/options` and
  initial `configOptions` on new, load and resume (0.106.0), `auth/status`
  and the `auth/status_update` notification with
  `AuthAccount.description`, which tells Claude Ultra from Max (0.104).
  `sessionCapabilities` adds `title`, `status` and `options`;
  `agentCapabilities.auth` adds `status`. Still no `session/set_model` and
  no standard archive.
- **Auto mode by default (0.101.0).** A new session starts in `auto` unless
  the person's Claude settings name `permissions.defaultMode`; 0.99.1
  started in Manual (`default`). Modes are `default`, `acceptEdits`,
  `plan`, `auto`, `bypassPermissions`; config ids unchanged (`mode`,
  `model`, `effort`, `fast`, `ultracode`, `agent`).
- **Idle compaction (0.101.0).** 54 minutes after the last request, if it
  used the 1-hour prompt cache and the context is at least 200k tokens, the
  adapter runs `/compact` on its own, outside any turn of chord's. chord sees
  an ordinary `compaction_update`; only JetBrains AIR is told it was idle.
  Opt-out: `idleCompaction: false` in Claude settings or in
  `_meta.claudeCode.options.settings` on `session/new` (honoured since
  0.106.0); `DISABLE_AUTO_COMPACT` turns off all auto-compaction.
- **Load replays the history before each compaction (0.106.0)**: longer
  loads, `compaction_update` entries inside a replay.
- The checklist moves from `plan` to `plan_update`/`plan_removed` by id for
  clients that declare `plan`, as chord does (0.102.0); subagent checklists
  get `plan:<toolUseId>` ids (0.103.0). chord's reducer has the shape.
- `usage_update.size` reads 1M until Claude Code reports the real window
  (0.107.0): chord's context meter may show x/1M at start.
- Stricter validation (0.100.0): relative `cwd` or `additionalDirectories`
  → -32602, wrong-typed `set_config_option` refused; `session/close` cancels
  open permissions and forms with `$/cancel_request` first.
- `subagent_update` carries `cwd` and may say `unknown`; tool calls name the
  child session they started (the new `session` content).
- 0.103.0 narrows the package's exports to `lib.ts`; chord imports nothing
  from it. The registry adds Bun single-file binaries beside npx; chord's
  generator keeps npx.

v2 only, which chord does not get on v1: `terminal/cancel`,
`toolCall/cancel`, workflow cards, the background-work list (Monitor calls,
subagents' background Bash). On v1 those go to AIR clients only.

To check with the fake agent before the bump, not settled from code: whether
chord's SDK logs noise for the unknown `auth/status_update`, and whether an
idle compaction, arriving outside a turn, opens a working cycle in
`src/session/cycles.ts` that never ends.

### 2.2 Codex — `@agentclientprotocol/codex-acp` 2.5.0 → 2.6.0

2.6.0 (2026-11-08; the registry already pins it), on codex ^0.166.0 (codex
itself is at 0.169.0):

- `session/set_title` (`sessionCapabilities.title`); titles already arrive
  as `session_info_update`.
- Custom permission profiles appear as extra modes: chord's mode cycle and
  picker can list more entries.
- Async-question `elicitation/create` no longer blocks the turn and is
  withdrawn with `$/cancel_request` when the turn ends; chord passes the
  request's signal to its form, so it should close (worth a fixture).
- Not served, by its own notes: `session/status`, `auth/status`, archive,
  `session/options`, proxy, `terminal/cancel`. `systemPrompt` was already
  advertised at 2.5.0 (agent-capabilities' footnote cx25 misses it).

Unreleased main (2.6.1 previews): the checklist as a `plan_update` of
`items` (chord handles it; check that a resent `planId` replaces rather than
appends); subagents per the RFD with the task as `session_message` and
`description` becoming a role token such as `default` (chord may label a
child by it: check); a `session` tool-call content; and
`sessionCapabilities.subagents` no longer sent to non-AIR clients (chord
does not read it). No break found.

### 2.3 Cursor CLI — `agent acp`, 2026.10.16 → 2026.11.11

The changelog stops at 2026.10.22 and has no ACP entry after 10.08; the ACP
docs are unchanged; the method names in the bundle are the same. A few new
per-tool input field names appear, whether in `rawInput` on the wire is `?`.
Nothing to take.

### 2.4 cursor-cloud — `@chorded/cursor-cloud-acp` 0.1.0 on `@cursor/sdk` 1.3.1

`@cursor/sdk` 1.3.1 is still the latest (published notes stop at 1.0.40).
The package today serves `initialize`, `authenticate`, new, prompt, cancel,
`set_config_option`, list, resume, load and close on ACP SDK 2.2.0; no
`session_info_update`, no `usage_update`, MCP servers held back.

What the SDK already has that the package leaves unused (from its public
types and docs): archive, unarchive and delete, with `includeArchived` on
list; agent and run status; `Agent.cancelRun`; usage with dollar cost
(`getUsage`); `auth.status` and logout; the agent's name, usable as a
title. Not available for cloud agents: rename (so no `session/set_title`),
`systemPrompt`, fork, steering. Cloud MCP: stdio runs in the VM, http and
sse go through Cursor's backend; forwarding the person's servers is a policy
question (CHD-622 held them back).

### 2.5 Gemini CLI — 0.66.0 → 0.68.0

Still on ACP SDK 0.16.1, no new methods. 0.67 adds
`_meta["gemini-cli"].mcp` (server and tool) on MCP permission requests.
0.68 sends the history replay before it answers `session/load` (it used to
answer first). In the 0.69 preview a retried stream marks its first chunk
with `_meta.retry`/`reset`; without handling, chord would show the broken
reply and the retry run together.

### 2.6 GitHub Copilot CLI — 1.0.105 → 1.0.111

Release notes only: the package no longer ships `changelog.json` and the
binary has no readable strings, so later readings rest on notes and docs.
ACP sessions show in Copilot's own history; `session/cancel` stops the
active turn only, leaving background tasks and shells running; a hook that
answers "ask" reaches the client as `session/request_permission`. SDK and
protocol `?`. The registry renames it "GitHub Copilot".

### 2.7 OpenCode, and chord's other own CLIs

- **opencode v2** (2.0.32 → 2.3.0): `_session/steering` announced by
  `initialize._meta.steering.supported` (2.2.7) — the same extension chord
  already sends to Claude, so mid-turn steering should reach opencode with
  no change (to confirm with a fixture); 2.2.6 deletes a session closed
  without ever being prompted; 2.3.0 streams a background subagent's report
  and the parent's reaction (whether outside a prompt is `?`). The registry
  now means v2 by `opencode`. v1 1.19.5: no ACP change.
- **goose** 1.55 → 1.59: a turn that ends on a model error now fails
  `session/prompt` with -32603 `reason: "turn_failed"` (chord should show it
  as a failed turn, as for any error answer); client `fs`/`terminal`
  delegation removed (chord declares neither); `_meta.tags` on `session/new`
  filters `session/list`.
- **kiro** 2.31 → 3.3: signed out, every request but `initialize` and
  `authenticate` fails auth-required; clients declaring terminal auth get a
  "Log in" method. 3.0 starts "new clients" on the V3 engine (no
  `session/set_model`, config options instead); how a client counts as new is
  undocumented. The registry launches `kiro-cli acp --agent-engine=v3`;
  chord passes no engine flag.
- **kimi** 2.2 → 2.6.2: a prompt to a session open in another Kimi client
  fails `session.occupied`; startup requests are queued. The registry adds
  npx `kimi-code` — the same program chord runs as `kimi` from PATH — and
  marks its old `kimi` "Legacy, archived".
- devin, junie (a "Sandbox" config option), openclaw (SDK 1.5 → 1.7, still
  refuses MCP servers), fx 0.0.16, zeroclaw 0.9.0, poolside 1.0.16: no wire
  change of consequence.

### 2.8 The rest of the ACP Registry

Fourteen pins moved, with no change of args or env. Of consequence on the
next `bun dev registry`:

- **autohand** became binary-only (native `autohand --acp`, 0.9.11); the
  generator freezes only npx and uvx, so a refresh drops it.
- **kimi-code** is added (npx), duplicating chord's own `kimi`.
- **qoder** jumps 0.2.14 → 1.1.89; its baseline cells are stale.
- New binary-only entries chord cannot freeze: kiro (`--agent-engine=v3`),
  muse-code (Meta, `MUSE_EXPERIMENTAL_ACP=on`).
- Quarantined or stale upstream: agoragentic, deepagents, fast-agent,
  minion-code; minimax-code stays at 0.2.7 while npm has 0.7.7.

Only **factory-droid** 1.10.0 serves `auth/status` (and `logout`); dirac and
kimi-code advertise `logout`. None of the others serves a 1.29–1.31 method,
`systemPrompt` or v2. fast-agent echoes whatever protocol version the client
asks — as agoragentic, deepagents, minimax, kilo, cline, pi and qoder did in
the baseline — so it would claim v2 while speaking v1 if chord ever asked
for 2.

## 3. The common part

What the protocol added since schema 1.28, and who serves it today.
"Unstable" is the SDK's `/unstable` entry, which chord already imports.

| Feature | ACP status | Served by | chord today |
| --- | --- | --- | --- |
| Session title, agent's: `session_info_update` | stable | claude, codex, kimi, fx, others | read and kept (CHD-445, CHD-491) |
| Set the title: `session/set_title` | unstable, Draft RFD | claude, codex | — |
| `session/status` (open / saved) | unstable, Draft | claude | — |
| `session/archive`, `unarchive`, list filter | unstable, Draft | none (claude only as AIR `_session/archive`); cursor-cloud's SDK could | — |
| `auth/status`, `auth/status_update`, `AuthAccount.description` | unstable, Draft | claude, factory-droid; cursor-cloud's SDK could | `authMethods` read only to word a failed start |
| Terminal auth (`auth.terminal` / `_meta["terminal-auth"]`) | stable capability | kiro, opencode, copilot, claude | not declared |
| `logout` | stable | claude, factory-droid, dirac, kimi | — |
| `session/options` + initial `configOptions` | unstable, Draft | claude | sets options after `session/new` |
| Client system prompt: `systemPrompt` | **stable** since 1.30 | claude, codex | — |
| Notices: `notice` update | stable | claude (and others as bold text without it) | not declared, dropped |
| Session tool-call content (`session` link to a child) | unstable, Draft | claude 0.107, codex main | drawn as nothing |
| Steering, `_session/steering` | extension; RFD PR #1261 | claude, opencode v2 | sent where advertised (CHD-535) |
| `terminal/cancel`, `tool_call/cancel`, background work | **v2 only** | claude on v2 | — |
| Proxy chains: `proxy/initialize`, `proxy/successor` | unstable, Draft | none | — |
| ACP protocol version 2 | alpha.15; RFDs back to Draft today | claude only | asks for 1 |

Next likely to land (schema 1.32): a `speed` config category, which fits
`/fast`; initial config on `session/fork`; subagents moving to Preview.

## 4. Proposals

Each item: take up **now** (this task, 0.71.0), **later** (its own task), or
**not**; what a person sees and under which key; what `chord acp` passes
through or serves. Keys follow chord's rule: every action has a key in the
shortcuts panel; slash commands are listed in `src/ui/prompt/commands.ts`.

### Dependencies and pins

| # | Item | Proposal |
| --- | --- | --- |
| P1 | ACP SDK 2.2.0 → 2.6.0, both chord and cursor-cloud-acp | **Now.** Additive; it is what gives types to every protocol item below. Nothing on screen. |
| P2 | OpenTUI 0.8.1 → 0.8.4 | **Now**, with a visual pass at 120x40 and 80x24 (dialogs, emoji widths). The `suspend()` and ScrollBox fixes are bugs chord can hit. |
| P3 | claude-agent-sdk 0.3.323, `@anthropic-ai/sdk` 1.8.0, genai-prices 0.2.3, patches | **Now**; genai-prices gives fast-mode prices to `/fast`. |
| P4 | string-width 9 | **Not** in this task: a major that must agree with OpenTUI's width method. |
| P5 | Registry refresh (`bun dev registry`): claude 0.107.0, codex 2.6.0, gemini 0.68.0, copilot 1.0.111, qoder 1.x and the rest | **Now**, with the claude bump gated by decisions D1–D2 and the fallout of D6. |
| P6 | Kiro engine flag, opencode v2, goose `turn_failed`, kimi `occupied` | **Now** as checks against fixtures where chord's behaviour depends on them; the kiro flag is D6. |
| P7 | Gemini 0.69 `_meta.retry`/`reset` | **Later**, when the registry pins 0.69: drop the broken partial reply. |

### Protocol features

| # | Item | Proposal | Person sees, key | `chord acp` |
| --- | --- | --- | --- | --- |
| F1 | `session/set_title` | **Now** (claude, codex) | `/rename <title>` on main or the picked agent, where `sessionCapabilities.title` is advertised; elsewhere chord's own record only, or refused (D3b). The new title shows where the agent's title shows today (`/resume` picker, header). | Serve `session/set_title`: renames chord's record, and the agent's where it takes it. |
| F2 | `auth/status` + `auth/status_update` | **Now** (claude, factory-droid; cursor-cloud by F9) | The account line in `/status` ("Claude Max · name@org"); a start that fails for sign-in says which account is missing before `session/new` instead of from the -32000 error. No new key. | Pass through: serve `auth/status` from the agent behind it, relay updates. |
| F3 | `session/options` + initial `configOptions` | **Now** (claude) | Nothing new drawn: a session opens already on the start mode, model and effort chord sets (`/new --model`, team members' settings, D1), with no flash of the defaults. Falls back to set-after-new elsewhere. | Accept initial `configOptions` on `session/new` and pass them down. |
| F4 | Notices: declare `session.notices`, draw `notice` | **Now** (claude) | Claude's notices ("Auto unavailable", why Fast went off, API errors) as one dim notice line in the transcript instead of bold reply text. | Already relays `notice` to clients that declare it. |
| F5 | Session tool-call content | **Now**, small | The tool call that started a subagent names it and the child's row is reachable from it (↓ into the agents list as today); no new key. | Relay as is (ids aliased like children). |
| F6 | Client `systemPrompt` (stable) | **Later**, or D3c | Nothing until chord has a use: candidates are a team's or a child's instructions as `append` instead of the first prompt, or a person's own `systemPrompt` setting. | Pass a client's `systemPrompt` down where the agent advertises it. |
| F7 | `session/status` | **Later** | Nothing visible: lets `/resume` pick load or resume without guessing; only claude serves it. | Serve from chord's own records. |
| F8 | Terminal auth + `logout` | **Later** (own task) | "Sign in" from a failed start runs the agent's login in a terminal (kiro, opencode, copilot, claude). Needs its own design for the terminal handoff. | Not served. |
| F9 | cursor-cloud-acp serves more | **Now or later** (D7) | Archive or delete a cloud agent from `/resume`, run status in the list, cost from `getUsage()`, the cloud agent's name as title, `auth/status`. | Comes through like any agent. |
| F10 | `session/archive` | **Not** now: no agent serves the standard method. | — | — |
| F11 | Proxy chains | **Not**: no agent, no use in chord. | — | — |
| F12 | `terminal/cancel`, background work, ACP v2 | **Not** in this task (D4). | — | `chord acp` keeps answering v1. |
| F13 | Claude idle compaction | Per D2. | An unasked compaction marked "compacted while idle" in the transcript. | Relayed as `compaction_update`. |

### What is stale in chord's own docs

`docs/agent-capabilities.md` section 2 no longer matches the code in B1, B2,
B3, B7–B8, B16, B18, B19, B20 and B23 (titles, fork, elicitation complete,
per-child cancel, steering of the person's prompts, `session_message` are now
used), its line references have moved, and it has no part for `chord acp`'s
own side. `src/session/cycles.ts:11` cites `dist/acp-agent.js`, now
`dist/result-end.js`. Proposal: fix in the same PR as the pin bump, per the
rule that a change fixes what it makes stale.

## 5. Decisions for the owner

**D1 — Claude's Auto mode by default.** The 0.107.0 bump makes every new
Claude session in chord start in Auto, where Claude decides permissions,
unless the person's own Claude settings name a default mode.

- a. Take the adapter's default; say so in the release notes.
- b. chord starts Claude in Manual (`default`) through initial
  `configOptions` (F3), unless chord's settings name a start mode; the person
  switches with shift+tab as today. *Recommended*: permission safety is high
  in the backlog, and it keeps what a person saw on 0.99.1.
- c. Ask once, at the first Claude start after the update.

**D2 — Claude's idle compaction.**

- a. Leave it on; mark an unasked compaction "compacted while idle"; make
  sure it opens no working cycle. *Recommended*: it saves the cost of
  re-reading a 200k context after the cache expires.
- b. Turn it off for chord's sessions through `_meta.claudeCode.options.settings`.
- c. A chord setting, on by default.

**D3 — Which protocol features in this task.**

- a. P1–P3, P5–P6 and F1–F5 now; F6–F8 and F9 later; F10–F12 not.
  *Recommended.*
- b. As (a) but F1's `/rename` only where the agent advertises
  `sessionCapabilities.title`, refused elsewhere — versus renaming chord's
  record for every agent. *Recommended: every agent*, the agent's own
  title taking over again only on its next `session_info_update`. Note that
  CHD-627 settled "no renaming" for a child's name; this renames a session's
  title, not a child's name.
- c. Take F6 (`systemPrompt`) now for teams' and children's instructions.
  Not recommended until a design shows what moves out of the first prompt.

**D4 — ACP v2.** Still alpha; its RFDs went back to Draft today; only claude
serves it, and at least eight registry agents echo whatever version is
asked.

- a. Not in this task; a task of its own once v2 is stable. *Recommended.*
- b. A spike now behind a flag, claude only.

**D5 — How it ships within 0.71.0**, one PR at a time.

- a. Two PRs in order: dependencies, pins and the D1–D2 handling first;
  then the features. *Recommended*: the bump carries the behaviour changes a
  person notices and can be reverted alone.
- b. One PR for all.
- c. A PR per feature.

**D6 — Registry refresh fallout.**

- autohand drops out of the npx registry. a. Let it go. b. Add it to
  `src/clis.ts` as `autohand --acp`. *Recommended: b* if the owner wants to
  keep every agent chord had; otherwise a.
- kimi-code (npx) duplicates chord's own `kimi`. a. Keep both. b. Drop the
  own-CLI `kimi`, use the registry's. c. Keep the own CLI and skip the
  registry's entry. *Recommended: b*: npx needs nothing on PATH and the
  version is pinned.
- kiro's engine. a. Pass `--agent-engine=v3` as the registry does.
  b. Leave it to Kiro. *Recommended: a*, so chord's kiro is the same on
  every machine.

**D7 — cursor-cloud-acp (F9).**

- a. Later, its own task and its own package release. *Recommended*: it
  needs a 0.2.0 publish before chord can pin it, and its MCP question
  (forwarding the person's servers to the cloud) is a policy of its own.
- b. Now, with archive, status, usage, title and `auth/status`.
