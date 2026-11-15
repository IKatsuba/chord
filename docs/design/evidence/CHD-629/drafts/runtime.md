# CHD-629 — runtime draft: F1–F5 at run time

Runtime's answers to the brief's runtime questions 1–5, read against
`CHD-629` at d82938bf5 (chord after CHD-624/626/627), ACP SDK 2.6.0
(`node_modules/@agentclientprotocol/sdk/dist/v1/`), and the
claude-agent-acp 0.107.0 npm tarball unpacked as text. Marks: `c` read in
code, `?` not established. Paths into the adapter are relative to its
`package/dist/`. codex-acp 2.6.0 ships as a native binary, so nothing about
codex below is `c`.

## What holds for all five

- **One agent process per chord session.** `openSession` starts its own
  agent (`openAgent`, `src/session/session.ts:463-474`) for main, each
  `/new` child, each task and team member, each fork and resume. ACP
  subagents (Claude's Task tool) are sessions inside their parent's
  process, routed by the tree (`src/session/subagents.ts:31-56`). So
  "per process" and "per `Session`" are the same thing in chord, and a
  subagent shares its parent's.
- **Processes.** None of F1–F5 starts a process of chord's own. Claude's
  adapter runs `claude auth status --json` itself, at most 5 s each
  (`AUTH_STATUS_PROBE_TIMEOUT_MS`, `auth-status.js:47-49`), inside the
  agent's process group, which chord stops as a whole
  (`src/platform/process.ts:58-70`, `:112`). Nothing new is needed in
  `src/platform/`, and nothing new needs to survive `bun build --compile`:
  no dependency, no worker, no native call. The one timer below (F2) is
  `node:timers/promises`' `delay` with an `AbortSignal`, the same as
  `#retirement` uses (`src/session/conversation.ts:1051-1072`).
- **No request without an answer bound by the agent's life.** Every request
  goes through `connection.ts`'s `ask` (`src/acp/connection.ts:390-443`).
  It rejects on the caller's signal or on the agent's exit, and refuses
  work that was already withdrawn. Every new call below uses it. A hang
  holds only what waits on that one answer.
- **Several sessions in one window.** Each `Conversation` has its own
  chains and state, and each child has its own process. Nothing below is
  shared across sessions. A `/rename`, an `auth/status` or a notice on one
  child never waits on another.

## F1 — `/rename <title>`

### What the agents do (c for Claude)

- Claude advertises `sessionCapabilities.title`
  (`v1/acp-agent.js:525-537`). `setSessionTitle` → `renameSession`
  (`v1/session-index.js:153-156`, `session-index/rename.js:20-76`). For a
  loaded session, `setExplicitTitle` (`session-titles.js:223-256`) first
  waits for any title generation in flight to end (`explicit.apply`), then
  marks the title `settled` so no generated title replaces it later
  (`:230`). It then **sends `session_info_update {title}` and only after
  that answers** `{title}` with the stored, normalised title
  (`:252-255`, `rename.js:31`). On the wire this is the echo first, then the
  answer, on one ordered stdout.
- A running session whose CLI cannot rename is refused -32600 ("cannot
  change its title while it runs", `rename.js:49-52`). The pinned CLI
  (2.1.323) has `renameSession`, so in practice a turn does not block a
  rename. `?` for a person's older Claude Code.
- SDK: an empty-after-normalisation title is -32602, an unknown session
  -32002 (`v1/acp.d.ts:535-539`, `SetSessionTitleRequest`,
  `unstable/schema/types.gen.d.ts:5641-5665`). The answer's `title` is what
  to display (`SetSessionTitleResponse`, `:3058-3075`).
- codex 2.6: advertises `title` (survey 2.2). Whether it echoes a
  `session_info_update`, and whether its own generated title can land after
  a rename, are `?`. The fake plays both (below).

### Ordering

`Conversation.rename(title)` runs in **a rename chain of its own**, not in
CHD-626's config chain (`#changes`, `conversation.ts:638`, `:2760-2796`,
`:2907-2936`). A rename and a model switch are independent on both sides:
Claude serialises config changes per session
(`serializeConfigurationChange`, `v1/acp-agent.js:5715-5720`) but renames
go through the session index. A hung `set_config_option` must not hold a
title, nor the other way round. Owner/lead choice R-a below.

One link, for an agent that advertises `title`:

1. When its turn in the chain comes, check `#current(session)`.
2. Write chord's own title entry to the record and set `#title` (record
   first: `#emit` feeds the record before the window, `conversation.ts:696-
   711`; `FileRecording` appends in queue order, `src/session/record.ts:
   1194`, `:1465-1507`).
3. Send `session/set_title` through `ask`.
4. The echo `session_info_update` (Claude) arrives as any title does
   (`#titled`, `conversation.ts:770-784`) and is recorded as the agent's.
5. The answer: if its `title` differs from what is shown now, take it (the
   spec's "display the stored title"). Recheck `#current(session)` first.

The chord entry is written when the link runs, not when the command is
typed. Then record order is wire order. Two quick `/rename a`, `/rename b`
read `chord:a, echo:a, chord:b, echo:b`. Writing both at typing time would
give `chord:a, chord:b, echo:a, echo:b`, and the header would flip back to
`a` for one echo.

For an agent without `title`, steps 3–5 are skipped and the link is
synchronous. The record still renames (D3 b).

Precedence is "last title line wins", whoever wrote it: chord's entry or the
agent's `session_info_update`. The window (`#title`) and the record reader
(`recordedTitle`, `src/session/sessions.ts:257-290`) must fold the same way.
The reader's fast filter only parses lines starting `{"type":"update"`
(`:270-275`). Chord's entry, whatever its shape (protocol's P1), must pass
that filter or the filter must widen, with a `tests/session/sessions_test.ts`
case. Older records have no such entry and read as today.

### Scenarios

| Case | Expected |
| --- | --- |
| `/rename` while the session starts (`#session` unset, or set but `#setUp` not done) | Refused with one line (interface's words). Not queued: a start that fails leaves a queued title nowhere to go. `notUp` today is silent (`conversation.ts:369-376`), so the window must say it. |
| `/rename` during a turn | Sent at once, as `/model` mid-turn is (CHD-626). The turn is untouched. Claude takes it (CLI 2.1.323). A -32600 refusal: see refusal. |
| A second `/rename` while `set_title` is in flight | Queued behind it, FIFO. The last typed wins on both sides. No coalescing: each was typed. |
| `set_title` refused (-32602 empty after normalisation, -32600 busy, any error) | chord's entry stands (D3 b: chord's record renames for every agent). One line says the agent kept its own title, with `agentMessageOf`'s words (`src/session/starting.ts:52-67`). The agent's next `session_info_update` takes over, as D3 b says. |
| `set_title` hangs | Holds only the rename chain. `/clear`, close and quit work as today: `ask` rejects on the agent's exit or close. No timeout, matching CHD-626's "no timeout" for the config chain. A third `/rename` waits. |
| `/clear` or resume replaces the session mid-rename | The old answer is ignored (`#current`). A late echo goes to `#retiredHeard` (`conversation.ts:3418-3422`). The new session gets a new chain, reset where `#changes` is reset (`:945`). Whether the title carries over to the new session is protocol's (Q2). |
| The agent's process exited | `ask` rejects at once. chord's entry stands, and the line says the agent is gone. |
| The agent's own generated title lands after a rename | Takes over, by D3 b. Claude cannot do this (`settled`, `session-titles.js:230`); codex `?`. |
| A task's session | `#titled` ignores agent titles there (`conversation.ts:776-778`, Q200). Whether `/rename` applies is protocol's (Q2). Runtime has no constraint. |

## F2 — the account

### What Claude does (c)

- The identity is **connection-scoped, never per session**
  (`auth-status.js:5-9`). The adapter probes at `initialize` without
  waiting (`v1/acp-agent.js:495`), at each session creation (before a guard
  may refuse it, `:7672-7678`), at the start of each prompt, and on each
  `auth/status`. It pushes `auth/status_update` only when the payload
  changes (`auth-status.js:36-38`). A push can land mid-turn.
- `auth/status` waits for a probe only while no identity is known yet.
  Otherwise it answers at once and starts a fresh probe in the background
  (`auth-status-reporter.js:107-115`). "Cannot determine" is
  `state: "unknown"` (`auth-status.js:40-44`).
- `AuthStatusUpdateNotification` has no `sessionId`
  (`unstable/schema/types.gen.d.ts:4402-4420`). `AuthAccount` fields are
  "display only… SHOULD NOT log them or send them elsewhere"
  (`:2498-2520`).
- Signed out, Claude fails at a **prompt** (-32000 `authRequired`,
  `v1/acp-agent.js:2671-2677`, `:4287`, `:4833`) or at `session/new` with a
  startup failure reason (`startup-failure.js:25-33`). The brief's "before
  `session/new`" covers only the second. Protocol and interface should say
  what the first shows.

### Design

A pure fold, `src/session/auth_status.ts` (state `unknown` →
answer/push, in arrival order; ACP gives no revision, the CHD-626 rule).
It is held per agent connection:

- **Feed 1: the push.** It is read off the traffic tap, as
  `elicitation/complete` is today (`session.ts:431-442`). It is not a
  `session/update`, so it is not held in `early` (`:448-452`), and it
  folds from the moment `initialize` is answered, before any session
  exists.
- **Feed 2: one `auth/status` request,** sent right after `initialize`
  when `agentCapabilities.auth.status` is advertised. It is sent with the
  start's signal and **not awaited by the start path**: `session/new` goes
  at once, as today. Sent then, Claude's request joins the probe that
  `initialize` started rather than spawning a second CLI run
  (`auth-status-reporter.js:107-113`).
- **The failure.** When a start fails with -32000 (`asSignIn`,
  `session.ts:584-589`), the failure is worded from the fold as it stands.
  If the request is still pending, the fold waits for it for at most
  **`AUTH_WAIT_MS` = 1000** (abortable, monotonic) and words the failure
  from whatever it has by then. Past the bound it falls back to today's
  words. A successful start never waits.
- **`/status`** reads the fold synchronously and sends nothing. Claude
  already re-probes at every prompt, so the fold is as fresh as a request
  would make it, without another CLI spawn per `/status`.

| Case | Expected |
| --- | --- |
| Agent without `auth.status` (every agent but claude 0.104+ and factory-droid) | No request. Pushes are folded if they come anyway. `/status` shows no account line (interface's words). |
| `auth/status` hangs | The fold stays `unknown`. Nothing waits on it but a failed start, for ≤ 1 s. Close or exit rejects it through `ask`. No retry. |
| `auth/status` errors (-32601 although advertised, or any other) | The fold becomes "unavailable". No line, no stderr. Pushes still fold. |
| A push before any session, or between `initialize` and `session/new` | Folded. Nothing is drawn until a `Conversation` reads it. |
| A push mid-turn (Claude's prompt-start probe) | Folded. No cycle opens: it is not a `session/update`, so `#updated` never sees it. |
| A child, task or team member | Its own process, its own fold. `/status` in its view reads its own. Several Claude children run several probes, as they do today without chord asking. |
| An ACP subagent | No fold of its own. It is its parent's process. |
| `/clear` | A new process (`openSession` again), so a new fold. Its first push or answer replaces "unknown". |
| Privacy | The fold is never written to a session record, and `chord acp` relays it only to its client. chord writes no traffic log to disk (`Traffic` reaches only `session.ts:431`). |

`chord acp`: whether it advertises `auth.status` and serves it from the
fold of whichever session the client means is protocol's (P3). Runtime's
constraint is that the fold exists only once an agent process does. Before
the client's first `session/new`, chord acp has no agent to ask.

## F3 — initial options

### Today (c)

`openSession` sends `session/new` with `cwd`, `mcpServers`, `openingMeta`
(`session.ts:520-526`, `:890-894`), folds the answer (`:616`) and the
early updates (`:619-626`). `Conversation.#setUp` runs `#applyStarting`
(`conversation.ts:3239`, `:3344-3404`) before the first `model` event
(`:3246`) and the first `#report` (`:3285`), and so before `connected`
(`:3321`). That is why no default flashes today.

`#applyStarting` calls `session.setModel/setEffort/setMode` **directly,
outside `#changes`**. `#session` is already set (`:821`) before
`#setUp` runs. A change asked in that window would run beside the start
asks, not after them. Whether the window can issue one then is `?`: no
modes or models have been reported yet, but a child's MCP mode change or a
typed `/fast` was not traced.

### Design

A pure module, `src/session/initial_options.ts`, with
`tests/session/initial_options_test.ts`:

- `INITIAL_CONFIG_IDS`, keyed by `agentInfo.name` (`CLAUDE_ADAPTER`,
  `src/session/enrich.ts:30`): `{model: 'model', effort: 'effort',
  mode: 'mode'}` for claude-agent-acp. It sits beside `FAST_OPTIONS`
  (`src/agents.ts:24-32`). Note that `FAST_OPTIONS` is keyed by registry id
  instead. That key misses a person's `--agent-command` running Claude's
  adapter, and the brief's `agentInfo.name` does not. Which key both
  tables use is R-c.
- `initialEntries(init, starting)` returns `InitialSessionConfigOption[]`.
  It is empty unless `sessionCapabilities.options` is advertised and the
  table has the agent. It holds one entry per `configId`, in the order
  **model, effort, mode**. Claude applies entries in list order and checks
  each against the options the earlier ones left (`initial-config-
  options.js:28-50`), which is the CHD-626 chain's order. A model entry
  therefore decides which efforts a later entry can pick, and the mode
  goes last because a model without Auto moves `auto` to `acceptEdits`
  (`session-mode.js:150-163`).
- `unmet(starting, state)` returns the starting values the answer's state
  does not show as current.

`openSession` puts the entries on **`session/new` only**. That covers the
window's start, `/clear`, children, team members, `-p`
(`src/session/oneshot.ts:91`) and `chord acp`'s sessions. Load and resume
keep set-after-new for explicit values, as today: Claude restores a resumed
session's own mode (protocol draft of CHD-624), and nothing is gained by
moving them. Fork has no `configOptions` in 0.107 or schema 1.31.

`#applyStarting` then becomes the first link of the session's one chain
(`#changes`). It asks only what `unmet` holds, through `askStarting` as
today, in the same order. A change asked while the start runs then queues
behind it. Each ask reads its value **at its turn**: the mode ask checks
`session.modes().current` just before sending and does nothing if it is
already the asked id.

**The mode recheck.** After the mode ask answers, chord reads the current
mode once more. If it is not the asked one but the ask succeeded (Claude's
Auto fallback: `set_config_option` answers success with `acceptEdits`,
`session-mode.js:168-194`), chord **does not ask again** and draws no
refusal line. The agent decided, and its notice says why (F4). Every value
is asked at most twice: once as an entry, once set-after-new. There is no
loop.

The Auto fallback, worked through:

1. The entry `mode: auto` is applied during setup. The answer shows
   `acceptEdits`, and Claude defers its warning to the first prompt
   (`deferWarning`, `session-mode.js:188-190`, `:231-239`).
2. `unmet` holds `auto`, so chord sends `set_config_option(mode, auto)`.
   Claude falls back again and publishes the warning now, because it is
   not during setup (`:191`, `publishFallbackWarning` `:205-229`). It
   answers success. The warning is marked shown, so no second one comes at
   the first prompt.
3. The recheck reads `acceptEdits` and stops.

The notice arrives before `connected`. It is held until `subscribe`
(`session.ts:658-665`) and drawn as F4's line before the first prompt. That
costs one round trip and moves the warning earlier, which is acceptable.
Telling "skipped" apart from "fell back" from the answer alone is
impossible, so chord does not try.

**`session/options` is never called** (CHD-624: it starts a throwaway
Claude Code and the person's `SessionStart` hooks,
`v1/acp-agent.js:604-643`). This is a test assertion, below.

### Failure modes

| Case | Expected |
| --- | --- |
| Agent without `options`, or not in the table | No entries. Set-after-new exactly as today. |
| Entry applied | `unmet` is empty and no `set_*` follows: one round trip saved per value. |
| Entry skipped silently (unknown id, value not offered, Claude logs it, `initial-config-options.js:41-49`) | `unmet` holds it. `askStarting` asks or refuses as today ("Could not start on … effort …: the agent offers …"). |
| **Stale table after a pin bump** (the id was renamed) | Same as skipped: the answer's `configOptions` lack the id, so the value is unmet and set-after-new uses the id from the answer (`modeConfigId`, `modelConfigId`, `effortsOf`, `session.ts:780-858`). The person sees nothing different. Only the saved round trip is lost. See below for how a test catches it. |
| The answer moves the mode after applying it (an early `current_mode_update`) | Folded before `openSession` returns (`:619-626`). The ask at its turn sees it and asks, so the asked mode wins. |
| `session/new` rejected for the field (-32602) | Not reachable with one entry per id. No retry (CHD-624 O2). It is a start failure with the agent's words. |
| `session/new` hangs while applying entries | Same as a hang today: the start's signal aborts it. No new timer. |
| A required value (a task's mode or model) not applied | `unmet` asks for it. A refusal fails the start (`starting.ts:16-20`, `conversation.ts:3390-3392`), unchanged. |
| A model entry applied, effort entry not offered by that model | Claude skips the effort. `unmet` asks it after new against the post-model set (`listedOnly`), which yields today's refusal line. The model stays. |
| `/clear` mid-start | The old start is let go (`conversation.ts:818-845`). The new session builds its own entries. |

**How a test catches a stale table.** No test may reach the real adapter, so
no test under `tests/` can see a renamed id. What can be tested is that a
stale id is harmless: the fake with `--config-ids renamed` (below) offers
`x-mode`/`x-model`/`x-effort`, skips the table's ids as Claude would, and the
test asserts the session still starts on the asked values through
set-after-new, with no refusal line. Catching the rename itself is R-b.

## F4 — notices

### Run-time effects of declaring `session.notices` (c)

- **Claude stops sending notices as reply text.** `noticeOrTranscriptUpdate`
  (`session-notices.js:25-34`) picks `notice` when the client declares it,
  and otherwise an `agent_message_chunk` holding a bold blockquote. Senders:
  MCP server startup failures at session creation (`v1/acp-agent.js:
  1320-1340`), informational SDK messages (`:3495`), model refusal fallback
  (`:3705-3726`), the Fast state (`:7184-7189`), and the Auto fallback
  (`session-mode.js:205-229`).
- **Cycles.** `notice` is not in `CYCLE_WORK` (`src/session/cycles.ts:
  68-74`), and `cycleMark` reads nothing from it (`:32-61`). A notice
  outside a turn opens no cycle. Today the same text arrives as
  `agent_message_chunk`, which **is** `CYCLE_WORK`. For Claude
  (`startsOwnCycles`, `session.ts:752`), an idle Fast-state change, or an
  MCP startup notice heard right after `subscribe`, can therefore open a
  cycle that no autonomous `usage_update` ends (`conversation.ts:3533-
  3564`). Declaring the capability removes that path. `?` whether it
  happens today: not reproduced.
- **Quiet.** Every update sets `#heardAt` (`conversation.ts:3430`), so a
  notice in the quiet after a turn delays a queued message by at most
  `QUIET_MS` (1 s, `:406`), and a retiring session's close is bounded by
  `SETTLE_LIMIT_MS` (5 s, `:413`, `:1051-1072`). Recommended: keep it. A
  notice is the agent still speaking, and singling it out would be reading
  words.
- **Nothing blocks.** A notice is a notification. No turn, chain or request
  waits on it.
- **Placement.** A notice before any turn (MCP startup during
  `session/new`, the Auto fallback in F3 step 2) is held in `early`/`held`
  and emitted after `subscribe` in `#setUp`, before `connected`. The
  transcript reducer must place it with no turn, as `#applyStarting`'s
  `failed` lines are. Today it falls to `default` (`src/session/
  transcript/reducer.ts:392`). It becomes a module of its own,
  `transcript/notices.ts` (`src/session/AGENTS.md`: one module per kind).
  A notice after a turn's answer folds under the last turn, as any late
  update does.
- **The record** keeps it as an update line, as it keeps every update. A
  resume redraws it. Older records have none.

### Where the declaration reaches

`CLIENT_CAPABILITIES` is one constant for every connection
(`src/acp/connection.ts:228-234`): the window, `-p` and `chord acp`.
Declaring `notices` there changes two consumers that do not draw a
transcript:

- **`-p`.** `headless.ts`'s reply takes only `agent_message_chunk`
  (`src/headless.ts:60-90`, `:294-300`). Today Claude's notices reach `-p`'s
  stdout as reply text. Once declared they would vanish. Recommended:
  `-p` writes a notice to stderr as `chord: <title>: <description>`, beside
  dimcode's `onNotice` (`:309-310`), in text format. R-d.
- **`chord acp`'s clients.** `reaches` relays `notice` only to a client that
  declares it (`src/session/upstream.ts:41-58`, `:80-92`). A client without
  it used to get Claude's bold text through chord, and would now get
  nothing. R-e.

## F5 — the tool call that names a subagent

### What Claude sends (c)

`withSessionReference` (`native-subagents.js:1602-1624`) appends
`{type: "session", sessionId}` to the content of a `tool_call`, or of a
`tool_call_update` that carries content, for the Agent/Task call that
launched the child and for TaskStop/SendMessage calls that target it
(`:1185-1221`). A content-less update is left alone. "The RFD requires the
announcement before the reference, so a call whose child is not announced
yet gets none" (`:1203-1205`). Replays carry it too (`subagent-replay.js:
42`). The SDK shape is `SessionReference {sessionId, _meta?}`
(`unstable/schema/types.gen.d.ts:220-228`).

### Runtime rules

- The reference is resolved **at draw time**, against the subagents the
  transcript holds (`subagentPath`, `subagents.ts:80-100`), not when it
  arrives. The reducer keeps the content as is: no state to patch, and no
  dependence on arrival order. A child announced later, against the RFD,
  still resolves once it appears.
- A reference **never grows the tree**. Only `subagent_update` adds a
  subagent (`subagents.ts:46-52`). A reference to a session never announced
  is drawn as unknown and grants no routing, as `strangerask` is refused
  today.
- Nothing is requested and nothing waits. A gone child (its row closed)
  keeps its name in the transcript entry. The agents list decides whether ↓
  still reaches it.
- `chord acp` aliases the `sessionId` inside the content as it aliases the
  child's updates (`UpstreamSession.children`, `upstream.ts:110-122`). An
  unknown id is passed on unaliased. That is protocol's to confirm (Q6).

## The fake agent

Each new flag and scenario is listed in `tests/fixtures/fake_agent/AGENTS.md`
in the same change. Scenarios go into the family modules named. Flags go in
`options.ts` with an environment twin, as every flag there has.

| Feature | Flag / scenario | What it plays |
| --- | --- | --- |
| F1 | `--set-title <echo\|silent\|refuse\|hang>` (`CHORD_FAKE_SET_TITLE`) | Advertises `sessionCapabilities.title` and serves `session/set_title`. It trims and cuts at 80 characters. `echo` sends `session_info_update {title}` and then answers, as Claude does. `silent` answers without an update (codex `?`). `refuse` answers -32600, as Claude does with a CLI that cannot rename. `hang` answers only once `<cwd>/.fake-gate/release` exists (≤ 10 s). An empty title is -32602 in every mode. |
| F1 | scenario `titledlater` (`text.ts`) | Waits for `<cwd>/.fake-gate/release`, then sends its own `session_info_update`, so D3 b's takeover is tested after a rename. |
| F2 | `--auth-status <authenticated\|unauthenticated\|unknown\|error\|hang>` (`CHORD_FAKE_AUTH_STATUS`) | Advertises `agentCapabilities.auth.status` and answers `auth/status` with an `AuthAccount` (`Claude Max`, `description`, `email: fake@example.com`). `error` answers -32603. `hang` never answers. With `--auth-push` it also pushes `auth/status_update` right after answering `initialize`, as Claude's first probe does. |
| F2 | scenario `authchanged` (`misbehaving.ts`, beside `authstatus`) | Pushes a different account mid-turn, then says a line. |
| F2 | existing `--auth-required methods` combined with `--auth-status unauthenticated` | Exercises the failure wording at `session/new`. `--auth-required prompt` (new value) fails the first prompt with -32000, as Claude does signed out. |
| F3 | `--options <apply\|ignore\|reject>` (`CHORD_FAKE_OPTIONS`) | Advertises `sessionCapabilities.options`. `apply` applies entries in order and skips unknown ids and values not offered (no error). `ignore` drops them all. `reject` answers -32602 when any are present. |
| F3 | `--config-ids renamed` (`CHORD_FAKE_CONFIG_IDS`) | The fake's options are `x-model`, `x-effort`, `x-mode`: a stale table. |
| F3 | `--auto-fallback` (`CHORD_FAKE_AUTO_FALLBACK`, with the existing `--auto-mode`) | `auto` on the small model becomes `acceptEdits`. During setup the notice waits for the first prompt. Otherwise it goes at once, once per session. |
| F3 | `opened` (existing scenario) | Also reports the request's `configOptions`, and a count of `session/options` requests heard. Every request is counted by method in `client.ts`. |
| F4 | scenarios `notice`, `noticeidle` (`text.ts`); flag `--start-notice <text>` (`CHORD_FAKE_START_NOTICE`) | Sent as `notice` when the client declared `session.notices` (`client.ts`), and otherwise as Claude's bold blockquote `agent_message_chunk`. `notice` sends one in a turn. `noticeidle` sends one after `turn.over` plus the cycles' `QUIET` (`scenarios/cycles.ts:15`), with no turn. `--start-notice`, like `--first-message`, sends one before `session/new`'s answer, as Claude's MCP startup notice comes. Run with `--adapter claude` for the cycle checks. |
| F5 | scenarios `subagentlinked`, `subagentstranger` (`subagents.ts`) | `subagentlinked` announces a child with `subagent_update`, then sends the parent's `tool_call` with `{type: "session"}` content, a content-less `tool_call_update`, and the child's work and completion. `subagentstranger` references a session it never announced. |

## Test plan

Pure modules first, then the session layer on the fake, then the window
through `tests/ui/harness.tsx`. No test reaches a real agent. All waits use
`until` (10 s, monotonic).

| Test file | Reaches | Asserts |
| --- | --- | --- |
| `tests/session/initial_options_test.ts` (new) | `initial_options.ts` | Entries only with `options` advertised and the agent in the table. Order model, effort, mode. One entry per id. `unmet` against answers that took, skipped and moved values. |
| `tests/session/auth_status_test.ts` (new) | `auth_status.ts` | Fold of answer and pushes in arrival order. `unknown` → answer, `error` → unavailable, an unrecognised `state` → `unknown` (the SDK's MUST, `types.gen.d.ts:2447-2455`). |
| `tests/session/transcript/notices_test.ts` (new) | `transcript/notices.ts` | A notice in a turn, after its answer, and before any turn. Replayed from a record. |
| `tests/session/transcript/tools_test.ts` | `tools.ts` | `session` content kept through a content-less `tool_call_update`, and replaced by one with content. |
| `tests/session/sessions_test.ts`, `record_test.ts` | `sessions.ts`, `record.ts` | Last title line wins across chord entries and agent updates. An older record without chord entries reads as today. The fast filter sees the new line. |
| `tests/acp/connection_test.ts` | `connection.ts` | `initialize` declares `session.notices`. `auth/status_update` still prints no SDK noise (beside the `authstatus` test). |
| `tests/session/session_test.ts` | `openSession` | `--options apply`: `session/new` carries the entries, no `set_config_option` follows, and `opened` counts zero `session/options`. `ignore`: one set per value. `reject`: the start fails with the agent's words. Resume and fork carry no entries. Without `--options`, the request is byte-for-byte today's. `--auth-status hang`: the start is not delayed. `--auth-required methods --auth-status unauthenticated`: the failure names the account. A hung status with a failed start words it within ~1 s. |
| `tests/session/conversation_launch_test.ts` | `#applyStarting` | Asked mode, model and effort on `apply`, `ignore` and `--config-ids renamed`, with no refusal line. `--auto-fallback`: exactly two mode asks, ending on `acceptEdits`, no refusal line, and one notice before `connected`. A team member's required mode refused fails the start. A `setMode` called during the start runs after the start asks (the chain). |
| `tests/session/conversation_test.ts` | `Conversation.rename` | Each `--set-title` mode. Two renames in flight end on the second, with record order equal to wire order. `/clear` mid-rename drops the old answer. A rename during the `slow` scenario leaves the turn alone. `titledlater` takes over after a rename. A rename while starting is refused. |
| `tests/session/conversation_cycle_test.ts` | cycles | `--adapter claude`, `noticeidle`: no `cycle_started`, no second `result`, and a prompt sent after it runs at once. The undeclared bold text from today's path is kept as a regression: it documents what the capability removes. |
| `tests/session/oneshot_test.ts`, `tests/headless_test.ts` | `-p` | Entries go on `-p`'s `session/new`. A notice goes to stderr (if R-d is taken), and stdout holds the reply only. |
| `tests/session/upstream_test.ts`, `tests/acp_agent_test.ts`, `tests/acp_agent_children_test.ts` | `chord acp` | `session/set_title` served (record, plus the agent where it serves it). `auth/status` passed through. `notice` relay per R-e. The `session` content's id aliased like a child's. |
| `tests/ui/…` (interface's paths) | the window, through `harness.tsx` | The `/rename` row and refusal lines, the `/status` account line, the dim notice line, and the tool call naming its child, at 120x40 and 80x24. |

Runs, per AGENTS.md: the reached files above and `bun dev quality chord
--static` per commit. CHD-629 touches `connection.ts`'s capabilities, which
every session reaches, so PR CI's full run is the broad check. A local full
run adds nothing.

## Open questions

- **R-a (lead).** `/rename` in its own chain (recommended: a hung config
  change must not hold a title, and the agents keep them apart), or in
  CHD-626's one chain (one ordering for everything a session is asked).
- **R-b (owner).** How a renamed config id is caught at a pin bump, given
  that tests never reach the adapter. (a) Accept it: the read-back makes it
  harmless and costs one round trip. Add a line to the pin-bump checklist
  to recheck `INITIAL_CONFIG_IDS` beside `FAST_OPTIONS`, which has the same
  gap today. *Recommended.* (b) `bun dev registry` fetches the pinned
  adapter's tarball and checks that the table's ids appear as its config-id
  constants. It catches renames but reads the adapter's source text.
  (c) A live check at release, outside `bun dev quality chord`, which
  spends the owner's account.
- **R-c (lead/protocol).** Key both tables by `agentInfo.name` (works for
  `--agent-command`, known after `initialize` and before `session/new`), or
  keep `FAST_OPTIONS` on the registry id and key only the new one by name.
  Recommended: both by `agentInfo.name`, in this PR, since the change
  makes the other stale.
- **R-d (owner).** `-p` and notices once `session.notices` is declared:
  (a) stderr as `chord: <title>: <description>`, *recommended*; (b) drop
  them; (c) declare `notices` only for the window.
- **R-e (owner via lead).** `chord acp` clients that do not declare
  `notices`: (a) declare `session.notices` to the agent only when the
  upstream client did, which makes `CLIENT_CAPABILITIES` a per-open
  parameter of `openAgent`. Each acp session starts its agent after the
  client's `initialize`, so this is possible. *Recommended.* (b) Always
  declare, and chord turns `notice` into text for such clients: chord
  rewriting the agent's output. (c) Drop them, a regression for those
  clients.
- **R-f (protocol/interface).** Claude signed out fails at the first prompt
  (-32000), not only at `session/new`. Should F2's "better failure" cover
  the turn failure too? Runtime's fold serves both. The 1 s wait applies
  only to a failed start.
- **R-g (lead).** `AUTH_WAIT_MS` = 1000 for a failed start's wording.
  Claude's probe is bounded at 5 s. A shorter wait sometimes gives today's
  words, and a longer one delays the failure screen.
- **Open from code (`?`).** Whether codex 2.6 echoes `set_title` and can
  retitle after it. Whether anything can call a session's setters between
  `#session` being set and `#applyStarting` ending (moving the start asks
  into `#changes` makes the answer harmless either way). Whether an
  undeclared notice opens a never-ending Claude cycle today.
