# CHD-624 — protocol draft: P1–P5

Owner of this file: protocol. Read against `CHD-624` at 2dd35f6f9, the
claude-agent-acp 0.107.0 package (`dist/`, read as text), ACP SDK 2.2.0 and
2.6.0 (`dist/`), and the `session-options` RFD (schema 1.31). Marks: **c** read
in code, **n** notes or docs, **?** not settled from what can be read.

## Summary

- **D1** is one general step in `openSession`: when the agent advertises
  `sessionCapabilities.options`, the starting values whose config id chord
  knows go out as `configOptions` on `session/new` (and on load and resume
  for values the settings name). The existing `askStarting` pass stays and
  becomes the read-back and the fallback: it compares the answer with what
  was asked and sends `set_config_option` only where the agent did not take
  it. Claude's adapter name is needed in one place: chord's own default
  start mode, `default`, applied only to new sessions of that adapter.
- chord cannot name a config id before the session exists without either a
  table of known ids or a `session/options` call first. That choice is the
  owner's (Q1); it decides F3 in CHD-629 too.
- **D2**: an enricher marks the opening `compaction_update` of a compaction
  that began while chord had no request open for the session
  (`_meta["chord/unprompted"]`). Claude 0.107 sends chord nothing else that
  tells an idle compaction apart. The record keeps the mark, so a resume from
  the record draws it again. The update does not start a cycle today.
- **SDK 2.6**: additive. `auth/status_update` reaches no handler and is
  dropped without a log line. `chord acp` answers -32601 for the new methods
  and does not advertise `options`.
- **Registry**: kimi-code takes `kimi`'s place under the alias `kimi`
  (recommended, Q3), so records, settings and team files that name `kimi`
  keep working. autohand and kiro become `src/clis.ts` rows. The generator
  should say what a refresh drops.

## P1 — D1 on the wire

### Today

- The starting values come from `place.ts:184-188` (`startupOf(...).starting`,
  from `--permission-mode` or `agents.<name>.permissionMode`,
  `settings.ts:797-802`). For a child or team member they come from
  `agents_host.ts:1362-1367`, where a member's mode is `required: true`.
- `Conversation.#applyStarting` (`conversation.ts:3341-3404`) runs once the
  session is open. It runs before the modes are reported
  (`conversation.ts:3233-3236`) and before the record's first state entry
  (`recording.opened`, `conversation.ts:3297`). Each value goes through
  `askStarting` (`starting.ts:70-97`): a value the agent does not list is
  refused without asking, otherwise `session.setMode` is called.
- `session.setMode` (`session.ts:808-826`) sends `session/set_config_option`
  with the mode option's id (`modeConfigId`, `modes.ts:59-77`), or else
  `session/set_mode`.
- `-p` does the same in `oneshot.ts:136-172`, for effort and mode.
- The setup requests are built in `session.ts:511-527` (fork, new) and
  `session.ts:906-930` (`reopen`: resume or load). Each carries only
  `openingMeta` (`session.ts:885-893`: Claude's `promptSuggestions: false`).

So the screen already shows no flash of Auto under set-after-new. What D1
changes is that Claude's session is in Manual from its creation, which saves
a round trip, and that chord has a default start mode at all.

### The request

When `connection.init.agentCapabilities.sessionCapabilities.options` is
present (not `null`), `openSession` adds `configOptions` to the setup
request:

```json
{
  "jsonrpc": "2.0", "id": 2, "method": "session/new",
  "params": {
    "cwd": "/work/project",
    "mcpServers": [],
    "configOptions": [{ "configId": "mode", "value": "default" }],
    "_meta": { "claudeCode": { "options": { "promptSuggestions": false } } }
  }
}
```

- The shape is `InitialSessionConfigOption`, value form (SDK 2.6
  `types.gen.d.ts:5253-5279`). There is no `type` field: v1 defaults it to
  `id`. chord never sends `type: "boolean"`, because it does not declare
  `sessionCapabilities.configOptions.boolean`.
- There is one entry per config id, so the request never carries the
  duplicate that Claude refuses with -32602
  (`initial-config-options.js:17-27`).
- Order is model, then effort, then mode, which is the window's order and
  the RFD's "as the agent lists them" for Claude (`model` before `effort`).
  In this PR only the mode entry exists.
- An entry goes only when chord knows the config id before the session
  exists (Q1). With no known id, nothing is sent and the fallback below does
  the work.

Which requests carry it:

| Request | Settings-named start mode | chord's default (D1) |
| --- | --- | --- |
| `session/new` (window, `/clear`, children, team members, `-p`, `chord acp`) | sent | sent |
| `session/load`, `session/resume` | sent, as `#applyStarting` already asks it on a resumed session today | **not sent**: the adapter restores the session's own mode from its transcript (`session-mode.js:39-46`, c), as 0.99.1 did |
| `session/fork` | set after the fork: Claude 0.107 takes no `configOptions` on fork (`v1/acp-agent.js:725-748`, c) and schema 1.32 is not out | not sent: the fork continues its source's mode |

Fork's entries should move into the request once schema 1.32 ships and the
agent advertises it. That is CHD-629's to take.

### Reading back

Claude applies the entries before it answers (`withInitialConfigOptions`,
`v1/acp-agent.js:651-664`, c). The answer carries `modes` and
`configOptions` as they stand afterwards, and no `config_option_update` is
sent for them. chord already folds the answer into state
(`session.ts:616`, `stateOf(answer)`) and any early `current_mode_update`
(`session.ts:618-624`). So after `openSession` returns,
`session.modes().current` is the mode the agent actually started in.

`#applyStarting` and oneshot's asks stay as they are, with one change: the
`ask` becomes "nothing to do when `offered` says the current mode is already
the asked one; otherwise `session.setMode(id)`". That gives every case:

| Agent | What happens |
| --- | --- |
| Advertises `options` and took the entry | no further request; nothing in the transcript |
| Advertises `options` and ignored the entry (unknown id, value not offered at that point) | response's current ≠ asked → `set_config_option` as today → it takes it, or the refusal line `Could not start in default mode, chord's default for Claude: the agent offers …` |
| Does not advertise `options` (codex, every other agent; a person's own older Claude adapter) | as today: set after new |
| Refuses `session/new` because of the entries | a start failure, as for any `session/new` error (`session.ts` `startFailed`). The spec allows -32602 only for malformed or duplicate entries, and chord sends neither. Whether to retry without them is runtime's R2; my view is no retry |

What the agent does not have, chord does not ask for: `askStarting` already
refuses an id the agent does not list (`starting.ts:84-87`). With the
initial entry it is the same, because Claude skips a value it does not offer
(`initial-config-options.js:30-49`). The read-back then finds the value
missing from the listed ids and says so, with no second request.

### chord's default, and where Claude's name is still needed

The default is a fact about one adapter (0.101.0 made Auto its default), so
it sits beside `openingMeta` and is keyed by `agentInfo.name ===
CLAUDE_ADAPTER` (`enrich.ts:30`). It is not keyed by chord's agent name. That
also covers `agents.claude.command` and any other command that runs the
adapter.

- `openSession` exposes it as `session.startDefaults` (`{ mode: { id:
  'default', from: "chord's default for Claude" } }`) on a session it
  created with `session/new`, and as nothing on load, resume or fork.
- Callers resolve the mode as `starting.mode ?? session.startDefaults.mode`.
  A named mode (settings, flag, a team member's `required` mode) always wins.
- The default is never `required`: a refusal leaves the session on the
  agent's mode, and the transcript says so.
- The alternative is to key it by registry id (`claude-acp`, as
  `FAST_OPTIONS` does, `agents.ts:21-29`) and resolve it in `place.ts`.
  That needs no `Session` change but misses the adapter started under
  another name. Recommended: adapter name.

`CLAUDE_ADAPTER` is then needed only there. The entry mechanism itself is
general: it checks the capability and a config id.

### What the record keeps

Nothing new. `recording.opened(session)` writes the first `state` entry from
`session.modes().current` after the starting values are applied
(`record.ts:1150-1158`, `1250`), so a record shows Manual from its first line
either way. `--permission-mode` and the default are not recorded; a resume
decides again, as today.

## P2 — mode names

There is no mapping to do. chord's `permissionMode` is already the agent's
own mode id. It is passed through as `StartingValue.id` and checked against
the ids the agent lists (`starting.ts:84-87`). `--permission-mode acceptEdits`
means Claude's `acceptEdits`; for codex it means codex's ids. D1 keeps that.
The only id chord writes itself is `default`, read from the adapter
(`session-mode.js:283-325`: `default`, `acceptEdits`, `plan`, `auto`,
`bypassPermissions`, c).

- A mode the agent lacks, named in settings: refused before any request
  (`listedOnly`), as today. On an `options` agent the entry is skipped by the
  agent and the read-back gives the same refusal words. A team member's
  `required` mode still fails the member's start
  (`conversation.ts:3387-3389`).
- `bypassPermissions` where Claude bars it, or `auto` where Claude disables
  it (`disableAutoMode`): these are not listed, so they are refused the same
  way.
- `auto` on a model without it: Claude answers `acceptEdits` with a notice
  (`session-mode.js:5-14`). The read-back sees `acceptEdits` and tries
  `set_config_option auto`, which Claude refuses. The transcript then says
  "Could not start in auto mode…: <Claude's words>". That is right: the
  session is not in the mode that was asked.

**The person's Claude `permissions.defaultMode` (Q2).** Under D1 b, chord's
`default` is an explicit choice, so it beats `permissions.defaultMode` in the
person's Claude settings (`session-mode.js:30-36`: explicit first). On 0.99.1
that setting was honoured in chord. Nothing on the wire says whether a mode
came from that setting or from the adapter's built-in default:
`builtInDefault` stays inside the adapter, and `session/options` answers only
the resulting mode.

## P3 — telling an idle compaction apart

### What Claude 0.107 sends chord

chord declares `session.compaction` and not AIR, so an idle compaction
reaches it as the following, with no prompt of chord's open and no
`PromptResponse` (c, `v1/acp-agent.js:3119-3168, 3990-4012`,
`context-compaction.js:207-326`):

```json
{"sessionUpdate":"compaction_update","compactionId":"<uuid>","status":"in_progress"}
{"sessionUpdate":"compaction_summary_chunk","compactionId":"<uuid>","content":{"type":"text","text":"…"}}
{"sessionUpdate":"compaction_update","compactionId":"<uuid>","status":"completed","summary":[{"type":"text","text":"…"}]}
{"sessionUpdate":"usage_update","used":41200,"size":1000000}
{"sessionUpdate":"usage_update","used":41200,"size":1000000,"cost":{"amount":12.34,"currency":"USD"},"_meta":{"_claude/origin":?}}
```

- The summary chunks are optional, and the `summary` is left out when the
  chunks already carried it.
- On a failure the second `compaction_update` has `"status":"failed"` and
  `error`.
- `trigger: "idle"` goes only into AIR's `_meta` (`context-compaction.js:
  355-376`), so a manual `/compact`, an automatic one and an idle one look
  the same to chord.
- The `/compact` echo and its `<local-command-stdout>` are user messages that
  the live loop drops (`v1/acp-agent.js:2010-2016`, `message-filters.js:
  16-23`), so no `agent_message_chunk` is expected. Whether a
  `local_command_output` frame follows `/compact` is **?**.
- The last `usage_update` carries `_claude/origin` only if Claude Code gives
  the result an origin. For the adapter's own `/compact` that is **?**.
  Whatever it is, it is not one of the five autonomous kinds
  (`result-end.js:86-92`), so `cycleMark` returns nothing.

### The candidate and what else could match

chord knows one thing for certain: whether a request of its own that runs a
turn was open for the session when the compaction opened. The wire state
already tracks chord's open requests (`enrich.ts:89-110`, `heardFromChord`
`enrich.ts:141-156`). A compaction that opens while none of `session/prompt`,
`session/load`, `session/resume`, `session/new` or `session/fork` is open for
that session is **unprompted**. Here is how the alternatives stand:

| Source | Request open? | Marked |
| --- | --- | --- |
| Person's `/compact`, or Claude's automatic compaction inside a turn | `session/prompt` | no |
| Idle compaction (54 min, ≥200k, 1h cache) | none | **yes** |
| Compaction inside Claude's own cycle (a task-notification follow-up) | none | yes; the cycle is chord's to know, not the wire's (see below) |
| Replay on `session/load` (0.106 replays across compactions) | `session/load` | no; drawn as a past compaction |
| Another client on the same Claude session | — | cannot reach chord: chord's session lives in its own adapter process; another Claude client's work shows only on the next load |
| A steer that starts a turn | — | cannot happen: chord steers with `idleBehavior: "promptRequired"` (`session.ts:770`; the adapter answers `promptRequired`, `v1/acp-agent.js:1547`), so an idle session refuses the steer |

### Proposal

- **Enricher `unprompted`** in `enrichers.ts`, for every agent. Gating it to
  Claude would leave the fact unsaid for any other agent that compacts on
  its own. It applies to a `compaction_update` whose `compactionId` the wire
  has not seen for that session, when no turn-running request is open for
  the session. It adds `_meta["chord/unprompted"]: true` and names it under
  `chord/filled`, as AGENTS.md asks. Only the opening update is marked. A
  later update of the same compaction (completed after a prompt began, a
  late `completed`) is not judged again. The wire keeps the ids seen per
  session, so a replayed `completed`-only compaction counts as "first" too,
  and it is unmarked because `session/load` is open.
- **Reducer**: `Compaction` (`transcript/types.ts:271`) gains `unprompted?:
  true`, taken from the opening update in `mergeCompaction`
  (`compactions.ts:51-59`) and kept by later patches, because `kept` spreads
  it. No new action.
- **Record**: the update goes into the record whole, `_meta` included, so a
  resume from chord's record draws "compacted while idle" again. Older
  records have no key and draw as today. A session resumed by `session/load`
  with no record of chord's draws its replayed compactions plain: the agent
  does not tell chord the trigger.
- **`chord acp`**: the update and its `_meta` are relayed as they are to a
  client that declares `session.compaction` (`upstream.ts:81-93`). Other
  clients get nothing, as today.
- **Wording**: the mark says "no turn of chord's was running". "While idle"
  is wrong only for a compaction inside Claude's own cycle. The interface
  can tell that case by the entry's turn (a cycle's turn id). That is
  interface's I1.

### Turn and cycle effects, as the code reads today (for runtime's R1)

- `compaction_update` and `usage_update` are not in `CYCLE_WORK`
  (`cycles.ts:65-71`), and `cycleMark` gives nothing, so `#beginCycle`
  (`conversation.ts:3507-3527`) does not start a cycle. If a
  `local_command_output` chunk does arrive (the **?** above), it is an
  `agent_message_chunk`. On Claude (`startsOwnCycles`, `session.ts:752`) after
  a quiet spell that would open a cycle that no autonomous usage ever ends.
  The fake-agent fixture should cover both sequences.
- The updates are stamped with the last turn's id (`#stamp`,
  `conversation.ts:2238-2242`). The compaction is drawn under the last turn,
  and the cost on the final `usage_update` counts as that turn's late cost
  (`turn_costs.ts:227-243`, `conversation.ts:3445-3450`). So the idle
  compaction's cost is added to the person's last turn. Q4.
- A prompt sent while the idle compaction runs waits behind it in the
  adapter's queue (`v1/acp-agent.js:1210-1216`). The compaction's later
  updates arrive while the prompt is open; they are unmarked and fold into
  the entry already opened.

## P4 — SDK 2.6

- **Additive**: the 2.2→2.6 diff removes no export. The `SessionUpdate`
  kinds are the same 19 in both (c, `types.gen.d.ts` of each). The one
  widened union is `ToolCallContent` with `{type: "session", sessionId}`.
  The reducer stores it with the call's content, the record keeps it, and
  `src/ui/transcript/tools/tools.ts:518` draws nothing for it through its
  `default` branch. Drawing it is CHD-629's F5.
- **Unknown notifications.** chord builds its client with `acp.client()`
  and registers only requests (`connection.ts:310-359`). A notification no
  handler takes falls through `processIncomingMessage` and is dropped. Only
  a handler that throws logs "Error handling notification" (SDK 2.6
  `core/jsonrpc.js:626-676`). So `auth/status_update`, which Claude ≥0.104
  sends to every client, is dropped silently. So is `_auth/status_update`,
  which 0.99.1 already sends to chord today. The traffic tap still sees it,
  `updateIn` finds no `session/update` in it, and nothing reaches state,
  record or window. The fixture asserts that and that no stderr line appears.
- **New typed fields chord uses**: `sessionCapabilities.options` and
  `NewSessionRequest/LoadSessionRequest/ResumeSessionRequest.configOptions`
  (P1). `stopWaitingOnCancel` (2.4) is not needed: chord's `ask()` and
  `answer()` already race the signal (`connection.ts:267-307, 384-436`).
- **`chord acp`**: its builder registers only its methods
  (`agent_app.ts:150-161`). `session/options`, `session/set_title`,
  `session/status`, `session/archive`, `auth/status` and `logout` therefore
  get -32601 from the SDK with no code. Its `initialize` keeps
  `sessionCapabilities: {list, resume, close}` (`acp_agent.ts:1806`) with no
  `options`. Its client therefore must not send `configOptions`. If one
  does, chord ignores them, and it does not relay them in this PR: relaying
  means advertising `options`, which means serving `session/options` (the
  RFD's MUST). That is CHD-629. chord acp's own downstream sessions get D1
  like the window's: they open through the same `Conversation` and
  `openSession`. Their answer's `configOptions` come from
  `answeredConfig(state)` (`acp_agent.ts:815`), so they already show the
  mode actually in force.

## P5 — the registry refresh

**The generator** (`scripts/dev/registry.ts:61-97`) freezes only `npx`
(preferred) and `uvx` entries. It returns nothing for a binary-only entry, so
autohand drops out without a word. It refuses a package that is not pinned
to an exact version. A name in both the registry and `src/clis.ts` is the
registry's (`agents.ts:110-117`). Today's binary-only newcomers (kiro,
muse-code, opencode v2, goose…) do not collide with anything, because they
are not frozen. One proposal in scope: `bun dev registry` prints each id
that was in `src/registry.ts` and is not in the new set, with its reason
(binary-only, inexact pin, gone). Then a refresh cannot silently drop an
agent again. Lead's call whether this goes in this PR.

**kimi → kimi-code (Q3).** The registry's `kimi-code` (npx
`@moonshot-ai/kimi-code@2.6.1 acp`) is the program chord runs today as
`kimi acp` from PATH. Its bin is `kimi` (n, c registry notes). Records name
`agent: "kimi"` (`record.ts` `session` line), and so can settings
(`agents.kimi.*`), `offeredAgents`, team files and `--resume`. Options:

- a. **Alias**: `ALIASES.kimi = 'kimi-code'` (`agents.ts:16-19`, as for
  claude and codex) and drop the `kimi` row from `src/clis.ts`. `chord kimi`,
  records, settings and team files keep working unchanged. `chord agents`
  shows `kimi` with the title "Kimi Code" and runner npx.
  *Recommended.*
- b. Name it `kimi-code` and map a recorded `kimi` to `kimi-code` where a
  record is resumed. `agents.kimi.*` settings, `offeredAgents` and team files
  naming `kimi` then stop matching. Each would need its own rename or its
  own "unknown agent" line.
- c. Name it `kimi-code` with no mapping. Records under `kimi` resume only
  with `--agent-command`. This breaks the brief's constraint.

Either way the session store is the same program's. Whether 2.6.1 reads
sessions written by the 2.2–2.5 versions people have on PATH is **?**. A
failure then reads as the agent's own words on resume.

**autohand.** New row in `src/clis.ts`, sorted in:
`{ name: 'autohand', title: 'Autohand', argv: ['autohand', '--acp'],
install: <the repository's install page> }`, with the doc line above it per
the table's rule (`clis.ts:1-8`). The registry PR #702 and the v0.9.11 notes
name `autohand --acp` (n). Whoever builds it must find the install URL in
autohandai/code-cli's own docs. The name stays `autohand`, so records keep
their agent. Sessions of the archived adapter (`@autohandai/autohand-acp`)
may not exist in the native CLI's store (**?**): a resume fails in the
agent's words.

**kiro.** `argv: ['kiro-cli', 'acp', '--agent-engine=v3']`
(kiro.dev/docs/cli/acp names `--agent-engine`, n). V3 has no
`session/set_model` and uses config options, which chord's `setModel`
already prefers (`session.ts:780-801`). Whether a V2-written session resumes
under V3 is **?**.

**Copilot** keeps the id `github-copilot-cli`, so records are unaffected.
Only the title becomes "GitHub Copilot".

## Failure cases

| Case | What happens |
| --- | --- |
| Agent exits during `session/new` with entries | start failure at `session/new`, as today; no session, nothing recorded |
| Agent ignores the entry | read-back, then set after new, then a refusal line if that fails too |
| Agent accepts the entry, then a `current_mode_update` moves it before chord reads | folded from `early` before `openSession` returns; the read-back sees the moved mode and asks again, so the asked mode wins |
| Person cancels the start (quit, `/clear`) mid-`session/new` | `signal` aborts the request as today; no fallback request goes (`ask()` refuses withdrawn work, `connection.ts:398-402`) |
| A turn is cancelled during a compaction | the compaction opened under the prompt and stays unmarked; a late `completed` patches it |
| Idle compaction arrives after `/clear` let the session go | `#retiredHeard`; only its cost is kept (`conversation.ts:3465-3495`) |
| Idle compaction while a permission or form is open | not possible: the adapter counts open inputs as busy (`v1/acp-agent.js:7886-7891`) |
| Record written before this change | no `chord/unprompted`; drawn as today |

## Open questions

- **Q1 (owner): how chord knows a config id before the session exists.** The
  RFD expects `session/options` first. Its FAQ: without it, clients "could
  only send values they had seen in an earlier session".
  - a. A table of known config ids per agent, read from the adapter's source
    and rechecked when the pin moves, beside `FAST_OPTIONS`
    (`agents.ts:21-29`, the owner's CHD-626 O3). Claude: `mode`, `model`,
    `effort` (`session-model.js:5`, `session-config-ids.js`, `session-mode.js:5`, c). A stale id is ignored by the
    agent per the spec, and the read-back then sets the value after new. It
    adds no round trip. *Recommended.*
  - b. `session/options` before every `session/new`. This is the spec's
    route, but Claude answers it by starting a throwaway Claude Code query
    that runs the person's `SessionStart` hooks
    (`v1/acp-agent.js:604-621`). Every session would start Claude twice and
    run those hooks twice.
  - c. Ids learned from an earlier session of the same agent in this process
    or in chord's records. The first session of a process, the one a person
    sees, would still set after new.
- **Q2 (owner): Claude's `permissions.defaultMode`.** Under D1 b, chord's
  `default` overrides a mode the person set in Claude's own settings, which
  chord honoured on 0.99.1. Options:
  - a. Accept it, and say in the release notes that the mode is set with
    chord's `permissionMode` for `claude`. *Recommended*: it is what D1 b
    says.
  - b. Read Claude's settings files to find `defaultMode`. That means
    reading another program's layered configuration (user, project, local,
    managed) and guessing its merge. Not recommended.
  - c. Send the default only through `session/options` + compare. This does
    not work: the answer cannot tell a configured `auto` from the built-in
    one.
- **Q3 (owner or lead): kimi's name**, options a–c in P5. a recommended.
- **Q4 (lead or runtime): the idle compaction's cost.** As the code reads,
  it is added to the last turn's figures as a late cost. The options are to
  leave it so, or to give an unprompted compaction's cost its own line under
  the compaction entry. The second touches `TurnCosts` and the record's
  `usage` events.
- **Q5 (lead): the generator's drop report** (P5): in this PR or not.
