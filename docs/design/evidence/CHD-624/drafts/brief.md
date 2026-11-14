# CHD-624 — brief: the upstream catch-up, first PR

The owner took every recommendation of
[the survey](../survey.md) (2026-11-13, recorded on CHD-624). CHD-624 is now
only the first of two PRs (D5 a): dependencies, pins and the behaviour the
Claude adapter's bump brings. The features F1–F5 moved to CHD-629, which
waits for this one; cursor-cloud's extras to CHD-630. Read the survey first;
its facts are not repeated here. The researchers' notes it rests on are in
`/tmp/chd624/notes/` on the lead's machine (not in the repository); ask the
lead for a part if you need it.

## The problem

chord pins ACP SDK 2.2.0, OpenTUI 0.8.1 and registry versions from
2026-11-01. Bumping them brings, beside fixes, two changes a person notices
with Claude (claude-agent-acp 0.99.1 → 0.107.0): sessions start in Auto, and
the adapter compacts an idle session on its own. The owner chose:

- **D1 b.** chord starts every Claude session in Manual (`default`) through
  initial `configOptions` on `session/new` (schema 1.31, advertised by
  `sessionCapabilities.options`), unless chord's settings name a start mode
  (`permissionMode` in `src/settings.ts`, `--permission-mode`, a team
  member's mode), in which case that one is sent. shift+tab cycles as today.
- **D2 a.** Idle compaction stays on. An unasked compaction is drawn
  "compacted while idle" and opens no working cycle.
- **D6.** `bun dev registry` refresh; autohand moves to `src/clis.ts` as
  `autohand --acp` (binary-only now); chord's own-CLI `kimi` is dropped for
  the registry's npx `kimi-code`; chord's `kiro` passes `--agent-engine=v3`.
- **D4 a.** chord keeps asking for ACP v1.

## In scope

1. `@agentclientprotocol/sdk` 2.6.0 in chord and `packages/cursor-cloud-acp`
   (the latter's spec only, no package release); `@opentui/core` and
   `@opentui/react` 0.8.4 with a visual pass at 120x40 and 80x24;
   `@anthropic-ai/claude-agent-sdk` 0.3.323 (latest at write time; recheck);
   `@pydantic/genai-prices` 0.2.3; patch bumps the survey lists.
   string-width stays on 8.
2. Registry refresh with D6, and the adapter pins it carries (claude 0.107.x,
   codex 2.6.0, gemini 0.68.0, copilot 1.0.111, qoder 1.x, the rest).
3. D1 and D2 as above.
4. Fixture checks, each a test against `tests/fixtures/fake_agent/` or an
   ACP stdio fixture: opencode v2's `_session/steering` announced at
   `initialize._meta.steering.supported`; goose's `session/prompt` failing
   -32603 `reason: "turn_failed"` drawn as a failed turn; codex 2.6.0's async
   question withdrawn by `$/cancel_request` at turn end closing chord's form;
   claude's `auth/status_update` notification arriving unhandled on SDK 2.6
   (no noise, no crash); an idle `compaction_update` outside a turn.
5. The stale parts: `docs/agent-capabilities.md` section 2 (B1–B3, B7–B8,
   B16, B18–B20, B23, line references, no `chord acp` part) and the new pins'
   cells; `src/session/cycles.ts:11`'s `dist/acp-agent.js`.

## What a person sees and presses

- A Claude session opens in Manual as on 0.99.1; the status line shows its
  mode from the start, with no flash of Auto. shift+tab cycles. A person whose
  settings name a mode gets that mode.
- An idle compaction shows in the transcript as the compaction does today,
  marked "compacted while idle"; no spinner, no "working", no notification
  that the agent waits.
- `chord agents` lists `kimi-code` (npx) instead of the own-CLI `kimi`,
  `autohand` as an own CLI marked by PATH, kiro launched with the engine
  flag. Copilot's name is "GitHub Copilot".
- No new key and no new command in this PR.

## Constraints

- AGENTS.md is binding: the one rule (library first; a library that does not
  fit goes to the owner), tests mirror `src/`, every action has a key, no
  live agent in tests.
- **D1's mechanism must be the one CHD-629's F3 extends**: F3 sends initial
  `configOptions` (model, effort, mode) for any agent that advertises
  `sessionCapabilities.options`, with set-after-new as the fallback. Build
  D1 as that general path, applied in this PR only to the start mode, and
  only where the agent advertises `options`, rather than a Claude special
  case. Say where Claude's adapter name is still needed, if anywhere.
- Load and resume: whether initial `configOptions` go on `session/load` and
  `session/resume` too, or only on new and fork (fork's is schema 1.32,
  not yet released).
- An adapter that ignores unknown initial options (the schema says ignore,
  not reject) must still end up in the asked mode, or chord must notice it
  did not.
- One PR at a time; the design names its own checks.

## Non-goals

`/rename`, `auth/status` on screen, notices, the `session` tool-call content
and F3 for model and effort (CHD-629); cursor-cloud-acp (CHD-630); ACP v2;
string-width 9; gemini 0.69's retry marks.

## Open questions, by owner

**protocol** (`drafts/protocol.md`):

- P1. Exactly what goes on the wire for D1: the `configOptions` entry shape,
  on which requests, gated how; how chord reads back the mode the agent
  actually started in (response `configOptions`, `current_mode_update`), and
  what it does when the agent ignored it. Where today's after-new
  `set_config_option` path lives and how D1 replaces or reuses it.
- P2. How D1 maps chord's `permissionMode` names to the agent's mode ids, and
  what happens with a mode the agent does not have.
- P3. How chord tells an idle compaction from one the person asked for, from
  what Claude 0.107 sends (no AIR flag): no turn running is the candidate;
  what else could start a compaction outside a turn (autonomous cycles,
  another client). Exact update sequence the adapter sends for it.
- P4. SDK 2.6's effect on chord's code paths: `auth/status_update` and other
  unknown notifications, `ToolCallContent.session`, anything typed
  differently. What `chord acp` answers for the new methods (method-not-found
  until CHD-629) and whether it must relay `configOptions` it is given.
- P5. The registry refresh: what the generator does with binary-only and
  duplicate entries, how kimi-code replaces `kimi` (sessions recorded under
  `kimi` must still resume), autohand and kiro entries in `src/clis.ts`.

**interface** (`drafts/interface.md`):

- I1. "compacted while idle": the exact line at 120x40 and 80x24, against
  today's compaction drawing; in the transcript, in a replay, and on resume.
- I2. The status line and header at session start under D1: what shows
  while the session opens, and when settings name a mode.
- I3. `chord agents` and the picker after D6: rows for kimi-code, autohand,
  kiro, "GitHub Copilot"; what a resumed `kimi` session says.
- I4. The OpenTUI 0.8.4 visual pass: which screens to capture (dialogs,
  emoji-heavy transcript, markdown, ScrollBox), at which sizes, and what
  counts as a regression.

**runtime** (`drafts/runtime.md`):

- R1. The idle compaction and chord's turn and cycle machinery
  (`src/session/cycles.ts`, `conversation.ts` near `CYCLE_WORK`): what
  happens today on a `compaction_update` with no turn, and what changes so
  it opens no working cycle, no notification and no OSC 7501 status.
- R2. Initial `configOptions` failure modes: an agent that rejects
  `session/new` because of them (strict validation, claude 0.100+), one that
  ignores them, a race with the first prompt; fallback order.
- R3. Each fixture check: which fixture, what it asserts, where its test
  lives; whether the fake agent needs a new script.
- R4. Ordering inside the PR (deps, refresh, D1, D2, docs) and the checks it
  runs; what the OpenTUI bump risks in the runtime (suspend, width method,
  env overrides).
