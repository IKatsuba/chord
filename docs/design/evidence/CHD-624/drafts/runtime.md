# CHD-624 — runtime draft: R1–R4

Runtime's answers to the brief's R1–R4, read against the CHD-624 branch
(chord 0.70.0 + the survey commit), claude-agent-acp 0.107.0 and ACP SDK
2.6.0 unpacked as text. Marks: `c` read in code, `?` not established. Paths
into the adapter are relative to its `package/dist/`, into the SDK to its
`package/dist/`.

## R1. The idle compaction and chord's turn and cycle machinery

Revised once at the lead's request after critic findings 3, 4 and 8: the
cycle hold of the first draft is withdrawn.

### What the adapter sends (c)

The idle compaction is a turn the adapter queues itself:
`IdleCompaction.fire()` calls `this.prompt({…, prompt: [{type: "text",
text: "/compact"}]}, "idleCompaction")` (`v1/acp-agent.js:7886-7896`,
`idle-compaction.js:131-150`). With `origin !== "client"` it neither titles
the session nor clears prompt suggestions (`v1/acp-agent.js:1146-1158`), and
nothing is echoed as a `user_message_chunk`. To chord (which declares
`session.compaction`) its compaction reads as:

1. `compaction_update {status: "in_progress"}` at Claude Code's `compacting`
   status (`v1/acp-agent.js:3121-3123`, `context-compaction.js:202-218`);
2. `compaction_summary_chunk`s while the summary streams
   (`context-compaction.js:232-250`, fed by `stream_event` compaction blocks,
   `v1/acp-agent.js:4407-4424`);
3. `compaction_update {status: "completed", summary}` at `compact_boundary`,
   then a `usage_update {used: post_tokens, size}` with no cost
   (`v1/acp-agent.js:3134-3168`); on failure `compaction_update {status:
   "failed", error}` instead (`:3126-3131`);
4. the turn's result: a `usage_update` with `cost` (the session's running
   total) and `_meta["_claude/origin"]` only if Claude Code set an origin
   (`v1/acp-agent.js:3998-4011`). An adapter-sent prompt's origin is `?`;
   `AUTONOMOUS_RESULT_ORIGINS` (`result-end.js:86-92`) lists none for it, so
   chord's `cycleMark` reads no end in it. No `PromptResponse` reaches
   chord.

### Does `/compact` make the adapter forward a chunk to chord?

What can be read settles the adapter's side but not Claude Code's. The CLI
is not in `@anthropic-ai/claude-agent-sdk` 0.3.323 as text: the package
ships `sdk.mjs`, type files and a `manifest.json` that names per-platform
native `claude` binaries (2.1.323, 344–362 MB each) in separate packages,
which were not downloaded. The SDK's types say only that
`SDKLocalCommandOutputMessage` is "Output from a local slash command (e.g.
/voice, /usage). Displayed as assistant-style text in the transcript"
(`sdk.d.ts:5701-5710`). Whether Claude Code 2.1.323 sends one for
`/compact`, and with what text, is **`?`**.

The adapter (c) has four paths by which a `/compact` turn's own output could
reach chord as `CYCLE_WORK`. Two are closed and two stay open:

| Path | Condition to forward | Reaches chord as |
| --- | --- | --- |
| Result text | Not forwarded once compaction output was delivered (`!deliveredCompactionOutput`, `v1/acp-agent.js:3911`, `:4316-4321`) | nothing (closed) |
| Synthetic assistant frame (`model: "<synthetic>"`) after the compaction opened | Dropped while `compaction.hasDeliveredOutput` (`:4723-4734`, set by `open()`, `context-compaction.js:328-340`) | nothing (closed) |
| `system/local_command_output` | Forwarded unless it is `/usage`/`/mcp` structured output or the one copy of a failed compaction's error (`:3170-3187`, `context-compaction.js:190-200`, `:296`) | `agent_message_chunk {content, messageId}` (open) |
| `<local-command-stdout>` in a non-system message, or a synthetic frame that arrives before the compaction opened | Forwarded with the tags stripped (`:4737-4810`); its role decides the kind (`sdk-to-acp.js:162`) | `agent_message_chunk` for assistant role (open), `user_message_chunk` for user role (not `CYCLE_WORK`) |

Neither open path marks the chunk. It carries `content` and a `messageId`
(the SDK message's uuid or API message id, `applyMessageId`,
`sdk-to-acp.js:168`) and no `_meta`. Nothing in it names the compaction or
the idle trigger: `trigger: "idle"` goes only to AIR clients
(`context-compaction.js:318`). The adapter's own comments show that Claude
Code builds emit local-command output around compaction: "Claude also emits
a failed manual compaction's error as local-command stdout"
(`context-compaction.js:190-192`), and "On resume the SDK can replay a stale
frame from an earlier compact attempt" (`v1/acp-agent.js:4718-4722`). So the
chunk is possible, unmarked and unbounded in time within the turn. That is
case (4): no keyed suppression is possible, and runtime proposes no window.

### What chord does with it today (c)

- `#updated` (`src/session/conversation.ts:3410-3459`) runs `#beginCycle`
  for every top-level update. `#beginCycle` (`:3503-3534`) opens a cycle
  only on codebuddy's start mark, or on a Claude session
  (`startsOwnCycles`, `src/session/session.ts:752`) when the update is in
  `CYCLE_WORK` and the session has been quiet for `QUIET_MS` = 1 s
  (`conversation.ts:406`, `:3422`). `CYCLE_WORK`
  (`src/session/cycles.ts:68-74`) is message and thought chunks, tool calls
  and `plan`. **Steps 1–4 open no cycle**: `compaction_update`,
  `compaction_summary_chunk` and `usage_update` are not in it.
- The updates are stamped with `#lastTurnId` (`#stamp`,
  `conversation.ts:2237-2242`), and the reducer appends a compaction entry
  under that turn (`src/session/transcript/compactions.ts:13-83`), drawn in
  the transcript, not the spinner (`inSpinner`,
  `src/ui/transcript/compaction.ts:23-30`).
- "Working", OSC 7501 and the "agent waits" notification follow only
  `prompt`, `cycle_started` and `result` (`src/session/waits.ts:217-239`,
  `src/notify.ts:220-240`, `src/status.ts`). None of them moves for steps
  1–4.
- The cost: `TurnCosts.heard` (`src/session/turn_costs.ts:227-241`) gives
  step 4's cost to the last turn, which is over, under whose id the update
  is stamped. That is how chord counts any late Claude cost (O3).
- If an unmarked `agent_message_chunk` from an open path arrives after 1 s
  of quiet, a cycle opens that nothing ends. chord shows "working" until the
  next prompt takes the cycle over (`conversation.ts:3920-3922`). That is
  `claudecyclebare`'s documented behaviour
  (`tests/session/conversation_cycle_test.ts:83-93`). A chunk within 1 s of
  the last update folds under the last turn and opens nothing.

### What changes for D2

1. **No hold.** For the compaction-only sequence (steps 1–4), D2's "opens no
   working cycle, no notification, no OSC 7501 status" already holds without
   a change to the cycle machinery. `cycles.ts` and `#beginCycle` stay as
   they are.
2. **The mark.** Conversation decides `unasked` at a compaction's first
   update: `#idle()` (`conversation.ts:2124-2126`: no turn, not settling, no
   steers), no `#cycle` and no `#selfTurnId`. It sets `unasked: true` on that
   `update` event. The field is carried explicitly through `record.ts`'s
   `RecordEntry`, `updateEntry` and `recordActions`, which pick fields by
   name (`src/session/record.ts:725-735`, `:1030-1040`, `:1056-1080`). Older
   records read back without it. A replay is `#replaying` over recorded
   actions (`conversation.ts:3262-3273`), which never passes `#updated`, so
   the mark is not decided again. An agent's own `session/load` replay of a
   session chord never recorded has no turns, and its compactions carry no
   mark (`session.ts:568-582`).
3. **The open paths stay as today.** The behaviour if Claude Code does send
   an unmarked line is the owner's choice, among the options below. Until
   the owner picks, the fixture `idlecompactsays` records today's behaviour:
   the cycle opens and stays working until the next prompt.

### Owner options for an unmarked chunk during an idle compaction

- **(a) Accept, as today.** A chunk after 1 s of quiet leaves the window
  "working", with a status of working, until the person's next prompt.
  Nothing is built. Cost: a possible false "working" an hour into an idle
  session, of unknown frequency.
- **(b) Ask upstream for a marker.** Ask claude-agent-acp to put the
  compaction's `trigger` (or an `idleCompaction` flag) in `compaction_update`
  `_meta` for every client, not AIR only. Or ask it to give the idle
  compaction's result an autonomous `_claude/origin`, which chord's
  `cycleMark` already ends a cycle on. chord then keys on that field, with a
  bounded end, the result's usage. This follows the one rule; until then,
  (a).
- **(c) Settle the `?` first.** Read Claude Code 2.1.323's platform binary
  for this machine as strings (text only, never run), looking for what
  `/compact` writes as local-command output. A negative read cannot rule out
  other builds; a positive one says the text but gives no marker. It informs
  (a) against (b) and changes neither.
- **(d) Turn idle compaction off for chord's sessions** with
  `_meta.claudeCode.options.settings: {idleCompaction: false}` next to
  `promptSuggestions: false` (honoured from 0.106.0). This reverses D2 a and
  is listed only for completeness.

Runtime recommends (b), with (a) until upstream answers.

### Concurrency around it

| Situation | Expected outcome |
| --- | --- |
| The person sends a prompt while the idle compaction runs | chord's turn starts at once. The adapter queues it behind its own `/compact` turn (`turnQueue`, `v1/acp-agent.js:1208-1212`; `disarm("prompt")` only clears a timer not yet fired, `:1053-1054`). The compaction's remaining updates are stamped with the new turn and patch the same entry by id. Its `unasked` mark, set at its first update, stays. The turn shows working from its start, longer than usual. |
| Esc while the idle compaction runs, no turn | chord has no turn or cycle, so it sends nothing (`tests/session/conversation_cycle_test.ts:396`). The compaction finishes. D2 a keeps it on. |
| Esc during a turn queued behind it | `session/cancel` as today. Since 0.100.0 the adapter cancels only prompts received before the cancel. Whether that also stops the running `/compact` is `?`. chord's turn ends cancelled. A compaction the adapter leaves open is closed `cancelled` at the turn boundary (`context-compaction.js:150-170`) and drawn so (`compaction.ts:61`). |
| Compaction fails | `failed` with the error, drawn as today and marked `unasked`. The error's one local-command copy is consumed by the adapter. Any other text is an open path, so the owner options apply. |
| `/clear` or a resume while it runs | The old session is retired; its updates go to `#retiredHeard` (`conversation.ts:3466-3495`), which keeps only costs. The adapter disposes the idle timer on close (`v1/acp-agent.js:5604`). |
| Lost connection during it | `disconnected` as today (`conversation.ts:3301-3313`). An entry left `in_progress` stays drawn so, as any compaction cut off today. No state of D2's needs a reset, since D2 keeps none beyond the mark. |
| A long-lived child or team member idle for an hour | Children are Conversations (`src/session/agents_host.ts:1277`, `:2390`), so the mark applies. Their waits stay idle. A lead's `send_message` queues behind the compaction in the adapter. |
| Window closes during it | Close and process-group stop as today. Nothing new waits. |
| A compaction after the session reopened, with no turn yet | The adapter's `skipReason` needs a request recorded in this process (`idle-compaction.js:160-166`), so a resumed session compacts only after its first turn, and `#lastTurnId` is that turn's id. |
| Another client of the same session (Remote Control) compacts | Whether Remote Control can reach a chord-run session is unknown: chord neither sends nor blocks `/remote-control`, and the adapter's handling was not followed to a second client (`v1/acp-agent.js:1088-1106`). If it can, a compaction it starts is drawn "while idle". |

## R2. Initial `configOptions` failure modes

### Today's start path (c)

`openSession` sends `session/new` with `cwd`, `mcpServers` and
`openingMeta` (`src/session/session.ts:520-527`, `:887-891`). The session's
state comes from the answer (`:616`). Updates sent before the answer are
held in `early` and routed after it (`:619`). Conversation's `#setUp` then
runs `#applyStarting` (`conversation.ts:3234-3236`, `:3341-3400`) before it
reports modes (`#report`, `:3282`) and before `connected` (`:3318`). It runs
on new, resume and `/clear` alike, for the window and children
(`agents_host.ts:1365-1367`); `-p` asks through the same `askStarting`
(`src/session/oneshot.ts:16`). `askStarting` (`src/session/starting.ts:65-
104`) skips a value the agent does not list and turns a refusal into "Could
not start in … mode, set by …: …". A `required` value (a task's) fails the
start.

Two runtime facts follow from that order:

- **No race with the first prompt.** Nothing reaches `session/prompt` before
  `connected`, and `connected` comes after the starting values are asked.
- **No flash of Auto, on either path.** The mode is first reported after
  `#applyStarting`. A set-after-new `default` is never seen as Auto first.
  Initial `configOptions` save one round trip; they do not fix a race.

### The general path

A pure module, `src/session/initial_options.ts` (test
`tests/session/initial_options_test.ts`):

- `initialEntries(init, starting, known)` returns the
  `InitialSessionConfigOption[]` for a setup request. It is empty unless
  `init.agentCapabilities.sessionCapabilities.options` is present. It holds
  at most one entry per `configId`, so Claude's duplicate check
  (`initial-config-options.js:17-26`) can never fire. In this PR it carries
  the start mode only; F3 adds model and effort in the order the agent
  lists them.
- `unmet(starting, answer)` returns the starting values the setup answer
  does not show as current: mode by `modesOf`/`modeConfigId`'s
  `currentValue`, later model and effort.

`openSession` takes the entries and puts them on `session/new`. Conversation
hands only `unmet` to `#applyStarting`, so set-after-new is both the
fallback and the check. Claude's adapter name is needed nowhere in this
path.

`known` is the problem. An entry needs the agent's `configId` before the
session exists, which the RFD answers with `session/options`. For an
unheld session, Claude's adapter answers it by starting a throwaway Claude
Code query that runs the user's `SessionStart` hooks
(`v1/acp-agent.js:615-643`). That is a second Claude Code start, and a
second run of the person's hooks, on every session start. See O1: the
config id's source belongs to protocol (P1) and maybe the owner. Runtime's
constraint is that the start path must not call `session/options`.

### Failure modes and expected outcomes

| Mode | Expected outcome |
| --- | --- |
| Agent does not advertise `options` (every registry agent but Claude today) | No entries. Explicit starting values go through set-after-new as today. D1's implicit Manual is not sent (D1 applies only where `options` is advertised). |
| Agent applies the entry (Claude 0.107: entries applied before the answer, no updates sent, `v1/acp-agent.js:646-660`) | The answer shows the mode, `unmet` is empty, and no `set_config_option` follows. One round trip fewer than today. |
| Agent advertises `options` but ignores or skips the entry: unknown id, value not offered, or a refusal (Claude logs it and skips it, `initial-config-options.js:37-50`) | The answer shows another mode, so `unmet` holds it and `#applyStarting` asks with `set_config_option` / `set_mode`. If that is refused, the transcript gets the "Could not start in … mode" line, the same as today. Chord notices whatever the agent did. |
| Agent rejects `session/new` because of the field (-32602) | Claude cannot do this with one entry per id. No other agent advertises `options`. Recommendation: no retry. The start fails with the agent's words through `startFailed` (`session.ts:583-612`), as any refused `session/new` does. One test. A retry without the field is O2. |
| Agent hangs on `session/new` while applying entries | The same as a hang today: the start's signal (quit, picker cancel) aborts it. No new timer. |
| `required` value (a task agent's mode) not applied | `unmet` asks for it. A refusal fails the task's start (`starting.ts:16-20`), unchanged. |
| Load and resume | The RFD applies entries on top of the restored configuration. Explicit starting values go on `session/load`/`session/resume` too, matching today's `#applyStarting` on resume. D1's implicit `default` does **not**: it would override a resumed session's own mode. |
| Fork | Schema 1.32 is not released, so no entries on `session/fork`. Set-after-new as today. |
| `/clear` | A new session gets the same treatment as new. |

## R3. Fixture checks

Every check runs against `tests/fixtures/fake_agent/`, never a real agent.
Scenario names follow the family modules, and each new scenario and flag is
listed in `tests/fixtures/fake_agent/AGENTS.md` in the same change.

| Check | Fake change | What the test asserts | Test file |
| --- | --- | --- | --- |
| opencode v2 steering | `--steering opencode` added to `STEERINGS` (`options.ts:385`). It advertises `_meta.steering.supported: true` with no `idleBehavior` semantics, answers `injected` in a turn, and with no turn answers `{outcome: "promptRequired", reason: "noRunningTurn"}` whatever was asked. It never starts a turn. | `agent.steering` is true (`steeringOf`, `src/acp/connection.ts:584-593`). A steer mid-turn is injected. A steer that misses the turn is refused and sent as the next prompt, with no turn of the agent's own. | `tests/session/conversation_steer_test.ts` |
| goose `turn_failed` | New `turnfailed` in `scenarios/misbehaving.ts`: says a line, then throws `RequestError(-32603, "…", {reason: "turn_failed"})`. | The turn ends `failed` with the message, as a turn error and not a connection failure. The agent stays up and the next prompt runs. The waits show a failed turn. | `tests/session/conversation_test.ts`, beside `error` |
| codex 2.6 async question withdrawn | New `askcodexasync` in `scenarios/forms.ts`: sends `elicitation/create` with `_meta.codex.delivery: "async"`, ends its turn without waiting, then after `turn.over` aborts the request's `cancellationSignal`, so the SDK sends `$/cancel_request`. | The form opens in the turn and outlives the turn's end. The withdrawal settles it (`elicitation_settled`). The box closes, nothing is answered, and the notify watch's `asking` empties. The prompt queue is not held after it. | `tests/session/elicitation_test.ts`; window: `tests/ui/dialogs/Questions_test.tsx`, beside `askcodexwait` |
| claude `auth/status_update` | New `authstatus` in `misbehaving.ts`: sends `_auth/status_update` and `auth/status_update` with an `AuthStatus`-shaped body, then says a line. | No `console.error`/`warn`, which the SDK prints only when a notification handler throws (`core/jsonrpc.js:657-675`; an unhandled notification is dropped, `:651-656`). The turn completes and nothing is drawn. Runs on SDK 2.6, where `auth/status_update` is a known method. | `tests/acp/connection_test.ts`, beside the `unknown` test (`:663-689`) |
| idle `compaction_update` outside a turn | New `idlecompact`, `idlecompactfail` and `idlecompactsays` in `scenarios/compaction.ts`. After `turn.over` plus the cycles' `QUIET` (1.5 s, `scenarios/cycles.ts:15`) they send steps 1–4 as `notify` with no turn: summary chunks with a 1.2 s stall before the first, then a cost `usage_update` with no origin. `…fail` ends `failed`. `…says` also sends an untagged `agent_message_chunk` 1.2 s after `completed`, standing in for the `?` local-command line. Run with `--adapter claude`. | `idlecompact`/`…fail`: no `cycle_started` and no second `result`. The compaction entry is under the last turn and marked `unasked`. Waits never show working, and notify has no `turn_ended`. A prompt sent mid-compaction runs and the entry is patched in place. The record keeps the mark and a resume draws it. `idlecompactsays` documents today's behaviour, pending the owner's option in R1: a `cycle_started` and no `result` until the next prompt takes the cycle over. | `tests/session/conversation_cycle_test.ts` (new `describe`), `tests/session/record_test.ts` |
| D1 initial options | `--options <apply\|ignore\|reject>` and `--start-mode auto` in `options.ts`. They advertise `sessionCapabilities.options`. New sessions start in `auto` (Claude 0.107). `apply` applies entries in order and skips unknown ones. `ignore` drops them. `reject` answers -32602 when any are present. `opened()` records `configOptions` for the test to read. | With `apply`, `session/new` carries `[{configId, value: "default"}]` and no `set_config_option` follows. The first `mode` event is Manual. A settings mode is sent instead. With `ignore`, one `set_config_option` follows and the mode ends `default`. With `reject`, the start fails with the agent's words. Without `--options`, nothing new goes on the wire. Resume carries explicit values only. A team member's mode is sent. | `tests/session/session_test.ts`, `tests/session/conversation_launch_test.ts`; pure: `tests/session/initial_options_test.ts` |

All waits use `until` (10 s, monotonic). The idle scenarios use real time for
the quiet gap, as `claudecycle` does, and never 54 minutes: the fake plays
the adapter's output, not its timer.

## R4. Ordering inside the PR, checks, OpenTUI risks

One branch, `CHD-624`, with commits in an order that keeps every commit
honest. No commit launches claude-agent-acp 0.107 before D1 and D2 are in:

1. **deps**: `@agentclientprotocol/sdk` 2.6.0 (chord and
   `packages/cursor-cloud-acp` spec), `@opentui/*` 0.8.4,
   `@anthropic-ai/claude-agent-sdk` 0.3.323, `@pydantic/genai-prices` 0.2.3,
   the patch bumps, `bun.lock`, and the `auth/status_update` fixture.
   Checks: `bun check`, `bun dev quality chord --static`, `tests/acp/`,
   `tests/session/`, `tests/ui/`, `bun dev quality cursor-cloud-acp`,
   `bun dev compile` with `bun dev selftest dist/<target>/chord` (OpenTUI's
   native library and its new ABI check at load), and the visual pass (I4).
2. **D1**: `initial_options.ts`, the `openSession` and `#applyStarting`
   change, the fake's `--options`/`--start-mode`, and its tests.
3. **D2**: the `unasked` mark, its record field, the fake's
   `idlecompact*`, and their tests.
4. **fixture checks** not tied to a step above: opencode steering,
   `turnfailed`, `askcodexasync`.
5. **registry**: `bun dev registry` with D6's `src/clis.ts` changes and their
   tests. This is when chord starts launching 0.107.0.
6. **docs**: `docs/agent-capabilities.md` section 2, `src/session/cycles.ts`'s
   comment (`dist/acp-agent.js` → `dist/result-end.js`, 0.99.1 → 0.107.0),
   and `docs/guide.md` for D1/D2 where it describes start mode and
   compaction.

Each commit runs its reached tests and `--static`. The whole suite runs in PR
CI (`static`, three `tests` shards, `compile`, `node`). The dependency step
is broad, so CI is the full run for it. Running it again locally adds
nothing.

### What the OpenTUI bump risks at run time

- **Width method (0.8.3).** chord forces `OPENTUI_FORCE_UNICODE` under tmux
  (`src/ui/app/terminal_width.ts:1-42`). The workaround is for
  anomalyco/opentui#1654, and `seesTmux` mirrors "`terminal.zig` at 0.8.1".
  0.8.3 detects first by DECRPM 2027 and XTVERSION and marks tmux ≥ 3.6 as
  unicode. Before the bump, read 0.8.4's `terminal.zig`. If #1654 is fixed
  or the detection now covers tmux, delete `terminal_width.ts` and its test
  in this PR. Otherwise update the comment's version and re-check
  `seesTmux`'s order. Check at 80x24 and 120x40 in tmux, which is where QA
  runs.
- **`suspend()` (0.8.2).** It keeps raw mode until the promise settles, then
  discards queued stdin. chord awaits it before `$EDITOR`
  (`src/ui/app/renderer.tsx:44-70`), so it takes the fix as is. Keys typed
  between the editor's exit and `resume()` are dropped, which is intended.
  Check once by hand: the `open_editor` key in tmux, type in the
  editor, quit, and the prompt holds the text with no stray mouse report.
- **`OTUI_STDOUT_THREAD` (`renderer.tsx:228-245`).** chord sets it around
  `createCliRenderer` and puts it back. Confirm that 0.8.4 still reads it
  synchronously in `createCliRenderer` (`tests/ui/app/renderer_test.ts`).
  If it reads it later, frames could interleave with chord's own bytes
  (Q336).
- **Text height (0.8.2)** and the **culled ScrollBox fix (0.8.4)** are layout
  risks. They belong to I4's visual pass, not runtime.
- **`bun build --compile`.** 0.8.3 adds `OPENTUI_LIB_PATH` and an ABI check
  at load. The `compile` CI job and a local `selftest` of the binary cover
  it, and `scripts/dev/compile_test.ts` covers the boundary fixture.

## Open questions

- **O0 (owner).** An unmarked chunk Claude Code may send during an idle
  compaction: R1's options (a)–(d). Runtime recommends (b), asking upstream
  for a marker, with (a) until then.

- **O1 (protocol/lead; owner if the options are unacceptable).** Where D1
  gets the mode's `configId` before `session/new`: (a) `session/options`
  first, which costs a second Claude Code start and a second run of the
  person's `SessionStart` hooks per session start, and which runtime advises
  against; (b) the id the same agent gave in an earlier answer in this
  chord process, with set-after-new for the first session; (c) set-after-new
  only in this PR, with `initialEntries` built but fed only once F3 brings
  `session/options` to a picker. Runtime recommends (c) or (b). Both meet
  D1's visible requirements, Manual from the start with no flash, through
  today's order.
- **O2 (lead).** Retry `session/new` once without `configOptions` on -32602?
  Recommended: no. No agent but Claude advertises `options`, and Claude does
  not reject single entries.
- **O3 (owner, via lead).** Who an idle compaction's cost belongs to:
  (a) the last turn, as today and as every late Claude cost (recommended: no
  record change, the session sum is right); (b) a costed entry of its own,
  which needs a non-turn cost line in the record.
- **O4 (protocol).** Whether `chord acp` sessions get D1's implicit Manual
  when the upstream client sent its own `configOptions` (P4).
