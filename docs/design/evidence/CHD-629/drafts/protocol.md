# CHD-629 — protocol draft: F1–F5 on the wire, in the record, in `chord acp`

Owner of this file: protocol. Read against `CHD-629` at d82938bf5, ACP SDK
2.6.0 (`node_modules/@agentclientprotocol/sdk/dist/v1/unstable/schema/types.gen.d.ts`,
cited `types:<line>`), claude-agent-acp 0.107.0 (the registry's pin,
`src/registry.ts:61`; fetched with `npm pack` into a scratch directory and
read as text, never run; cited `claude:<file>:<line>` under `dist/`), and
codex-acp at the `v2.6.0` tag and at `main` (TypeScript sources through
`gh api`; cited `codex:<file>:<line>`). Marks: **c** read in code, **?** not
settled from what can be read. Nothing here was run against a live agent.

## Summary

- **F1.** Claude and codex both answer `session/set_title` by sending a
  `session_info_update` with the stored title **before** the response, for a
  session loaded on the connection (chord's always are), and both then stop
  generating titles of their own. chord therefore needs no rule to tell the
  echo from the agent's later title: last one wins, as CHD-491 already reads
  titles. The record gets a chord-own line, `{"type":"renamed",…}`, written
  after the agent took the title (or at once for an agent without
  `sessionCapabilities.title`); it is not a synthesised ACP update.
- **F2.** `auth/status` once per agent process, sent right after
  `initialize` beside `session/new`, plus `auth/status_update` heard on the
  connection. Kept in memory only (the schema says SHOULD NOT log it).
  Claude logged out does **not** refuse `session/new` today; its first
  prompt fails. So "a start that fails for sign-in" is new behaviour for
  Claude: an owner choice (O3).
- **F3.** A table keyed by `agentInfo.name` gives Claude's ids `model`,
  `effort`, `mode`. The values go as `configOptions` on `session/new` only,
  in that order. `#applyStarting` stays and becomes the read-back: it asks
  only for a value the answer does not show, and the mode step reads the
  mode again after asking. `chord acp`: recommended not to advertise
  `options` (O4).
- **F4.** Declaring `session.notices` changes what Claude **and codex 2.6.0**
  send. Seven Claude sources and five codex sources move from reply text
  (or thoughts, or nothing) to `notice`. Claude then **drops** its `info`
  level hook and system messages, which chord shows today as reply text.
  API retries are not notices on v1 (they go to AIR only), contrary to the
  survey.
- **F5.** `{type:"session", sessionId}` in a tool call's content names a
  subagent chord already holds (`Subagent.id`), always after its
  `subagent_update` (both adapters check "announced"). For Claude in the RFD
  form chord gets, the **launching** Agent/Task call is hidden. The
  reference lands on TaskStop and SendMessage calls, and on a launch only
  when a permission prompt showed it. codex 2.6.0 sends none; main sends it
  on collaboration calls, possibly several per call. `chord acp` aliases the
  id as it aliases children, and strips it for a client without `subagents`.

## F1 — `/rename <title>`

### What the agents do (c)

| | Claude 0.107 | codex 2.6.0 |
| --- | --- | --- |
| Advertises | `sessionCapabilities.title: {}` (`claude:v1/acp-agent.js:536-537`) | `sessionCapabilities.title` (survey 2.2; `codex:src/SessionIndexService.ts:245`) |
| Normalises | whitespace folded, cut to 256 with `…` (`claude:session-titles.js` `sanitizeTitle`); empty → -32602 `title must be a non-empty string` (`claude:session-index/service.js:59-66`) | `normalizeSessionTitle`; empty → -32602, same words (`codex:src/SessionIndexTitles.ts:62-66`) |
| Echo | `setExplicitTitle` persists, then sends `session_info_update {title}` with no `updatedAt`, then the request answers (`claude:session-titles.js` `setExplicitTitle`; `claude:session-index/rename.js:20-31`) | persists, then sends `session_info_update {title}` "here, not left to the echo", then answers (`codex:src/SessionIndexTitles.ts:104-118`) |
| Its own titles after | never generated again: `explicit.settledByClient`. At turn end it adopts a custom title **someone else** stored, such as the person's `/rename` in the `claude` CLI (`onTurnEnd`) | automatic writes skipped for good (`writeAutomaticTitle`). A stale automatic echo is suppressed by codex itself (`isStaleAutomaticTitleEcho`) |
| On load or resume | `publishCurrent` re-sends the stored title | codex sends `thread/name` updates as before |
| Refusals | -32002 unknown session; `invalidRequest` "The Claude Code CLI of this session cannot change its title while it runs." for an old CLI without `renameSession` (`rename.js:44-48`) | its app server's error, mapped by `renameRequestError` |
| Own `/rename` command | **?** (Claude Code's own commands come from the CLI and were not run) | yes, `rename` in its available commands (`codex:src/CodexCommands.ts:288-292`); chord's own command of the same name wins and the agent's is hidden (`src/ui/prompt/commands.ts:129-131`) |

The schema: "The Agent responds only after it has stored the title. After a
successful response, the Agent SHOULD NOT replace the title with one it
generates automatically" (`types:5636-5637`). The response's `title` is "the
title the Agent stored… Clients SHOULD display this value"
(`types:3058-3065`).

### Wire order (window or `chord acp`, any session chord holds live)

```
chord → agent  {"jsonrpc":"2.0","id":7,"method":"session/set_title",
                "params":{"sessionId":"S","title":"Fix the   parser"}}
agent → chord  {"method":"session/update","params":{"sessionId":"S",
                "update":{"sessionUpdate":"session_info_update","title":"Fix the parser"}}}
agent → chord  {"jsonrpc":"2.0","id":7,"result":{"title":"Fix the parser"}}
record         {"type":"renamed","title":"Fix the parser","at":1763100000000}
```

1. chord trims the typed title; an empty one is refused before any request
   (interface words it). No other normalisation: the agent's answer is what
   is kept.
2. When `init.agentCapabilities.sessionCapabilities.title` is present,
   `Session.setTitle(title)` sends `session/set_title` through the SDK's
   typed method (`acp.d.ts:69` `session/set_title`). chord adds a method to
   `Agent` (`src/acp/connection.ts:113-205`) that throws without asking
   when the agent does not offer it, as `forkSession` does
   (`connection.ts:512-519`).
3. The echo goes through the enrichers and the reducer as any
   `session_info_update` does. It is recorded as an `update` line, and
   `Conversation.#titled` takes it (`src/session/conversation.ts:770-784`).
4. On the response, if the session is still the current one
   (`#current(session)`, after the await), `Conversation` emits
   `{type:"renamed", title: response.title}`. The recording writes the line,
   and `#title` takes the title. The response's title wins over the typed
   one, per the schema.
5. Without the capability, steps 2–3 are skipped. chord emits `renamed`
   with the trimmed title at once.

How the echo is told from the agent's own later title: it need not be.
Every title source replaces the last, in arrival order, which is CHD-491's
rule. The echo equals the response, so it changes nothing. A later
`session_info_update` from the agent is, by D3 b, the agent's title taking
over. With Claude and codex, that happens only if the title was renamed
outside chord (Claude adopts another client's stored title; codex relays
`thread/name/updated`). With an agent that does not take `set_title`, it is
its next title, whenever it sends one. No source is guessed from words.

### The record entry

```ts
/** The person named the session (CHD-629); the agent took it where it offers to. */
| { readonly type: 'renamed'; readonly title: string; readonly at: number }
```

- **A chord-own line, not a synthesised `session_info_update`** (lead's
  call; recommended). A synthesised update would need no reader change, but
  the record would then hold an ACP event no agent sent, against the spirit
  of `src/session/AGENTS.md` ("never invent … ACP events"). It would also
  be hard to tell from the agent's later echo on resume.
- **Readers.** `recordedTitle()` (`src/session/sessions.ts:257-297`) reads
  `{"type":"renamed"` lines too, with the same fast prefix check, in line
  order with the `session_info_update` lines, last one wins, through
  `titleLine`. `recordActions` (`src/session/record.ts:630`) maps it to a
  past action `{type:'renamed', title}`. The opening loop in `Conversation`
  (`conversation.ts:831-835`) folds it beside the `update` actions. The
  transcript reducer ignores it: CHD-445 draws no line for a title change
  (`docs/design/CHD-445.md:287-296`). Whether `/rename` leaves a `note`
  under the command is interface's.
- **Older records** have no such line and read as today. An **older chord**
  reading a newer record skips it: `recordActions`' switch has no default
  (`record.ts:658-…`) and the `/resume` reader's prefix check passes over it.
  The session then shows the agent's last title, which for Claude and codex
  is the same.
- **Held lines.** `FileRecording` holds a session's lines until its first
  prompt (`record.ts:1191-1196`). Should a rename alone make a session worth
  keeping, as an admitted receipt does (`captureServed`, `record.ts:1236-1252`)?
  Recommended: no, it is held like the rest. Claude's set_title on a session
  with no transcript works while its CLI runs (`mayBeUnwritten`,
  `rename.js:24-27`), but whether such a session then resumes is **?**. Q1.
- **`/clear` and fork.** `/clear` opens a new session: the title goes
  (`conversation.ts:947`). A rename answered after `/clear` is dropped by
  the `#current` check. The agent kept it for the old session, which
  re-sends it on its next load. A fork is the agent's new session and gets
  no chord rename.
- **Resume.** For a recorded session, the agent's replay is not drawn
  (`session.ts:556-571`), so the record's `renamed` stands until a live
  `session_info_update`. Claude's `publishCurrent` re-sends the same title.
  An agent without `set_title` that re-sends its own title on load takes
  over again, which is D3 b's consequence.

### Refusal and failure (owner choice O1)

When the agent refuses `set_title` (-32602, -32002, Claude's `invalidRequest`,
an internal error) or exits mid-request:

- **a.** The rename fails whole: nothing is recorded, and the refusal line
  carries the agent's words (`agentMessageOf`, `src/session/starting.ts:46-61`).
  *Recommended*: otherwise chord would show a title the agent's own list
  does not have, and Claude's `publishCurrent` would silently put its own
  back on the next resume.
- **b.** chord records `renamed` anyway, as it does for an agent without the
  capability, and says the agent kept its own.

### Which sessions (brief Q2)

| Target | `/rename` |
| --- | --- |
| main | yes |
| a long-lived child (`/new`, `open_agent`, a team member) | yes: its own `Conversation`, process and record (CHD-627's names are untouched: this is the session's title, not the child's name) |
| a task (`spawn_task`) | refused: a task keeps its `spawn_task` title, and `#titled` ignores the agent's title for one (`conversation.ts:771-775`, CHD-445 Q200) |
| an adapter's own subagent | not chord's session; CHD-445 gives it no title |
| a session still starting (no session id) | refused, no queue (recommended; runtime may choose otherwise) |
| a session whose agent exited, or a closed child | refused: nothing to send to, and nothing live to draw |

### `chord acp`

- **Advertise** `sessionCapabilities: {list, resume, close, title: {}}`
  (`src/acp_agent.ts:1806`) for every agent: chord's record takes any
  agent's rename. Register `session/set_title` in `connectAgentApp`
  (`src/acp/agent_app.ts:150-174`) with the SDK's handler type
  (`acp.d.ts:535-539`).
- **A live session**: the same `Conversation` path as the window. The
  response is `{title}`, the agent's stored title or chord's trimmed one. The
  agent's echo already reaches the client through `mapUpdate`
  (`session_info_update` is in `OPEN`, `src/session/upstream.ts:62-73`). Empty
  → -32602, as both adapters word it.
- **A listed session that is not loaded** (the schema allows any session in
  `session/list` to be retitled, `types:5632-5634`). Owner choice O2:
  - a. Append `renamed` to its record only. Claude's `publishCurrent` puts
    its own title back on the next load.
  - b. Start the session's agent, `initialize`, `session/set_title` where it
    is offered, close it, then record. Claude and codex both rename a
    session that is not loaded (`rename.js:41-60`, `SessionIndexTitles.ts:56`).
    *Recommended* for agents that offer it, with (a) for the rest; it costs
    a process start per such rename.
  - c. Refuse with -32002. This is against the schema for a session chord
    lists.
- **Unknown id** → -32002.
- **`session/list` titles.** Today they are the first prompt
  (`acp_agent.ts:1828-1833`), not the agent's title, though `earlierSessions`
  carries `title` (`sessions.ts:248`). With F1 the client would not see its
  own rename in the list. Fix in the same PR: `title: title ?? prompt`.
- **Load replay to the client**: a `renamed` past action goes up as a
  `session_info_update` from chord. Here chord *is* the agent, so it is
  chord's own update, not an invented downstream one.

## F2 — the account in `/status`, sign-in before `session/new`

### What the agents send (c)

- Claude advertises `agentCapabilities.auth.status: {}`
  (`claude:v1/acp-agent.js:561-565`). At `initialize` it starts a
  `claude auth status --json` probe in the background, bounded at 5 s
  (`claude:auth-status.js:54`), and pushes `auth/status_update` when it lands,
  "after this response, never before it" (`v1/acp-agent.js:488-495`). It
  pushes again only when the payload changes (`auth-status-reporter.js` `set`).
  `auth/status` with nothing read yet joins that probe; with an identity, it
  answers at once and re-probes in the background (`status()`).
- Payload (`toAcpAuthStatus`, `claude:auth-status.js:74-96`):

```json
{"state":"authenticated","accounts":[{"label":"Claude Max","active":true,
  "email":"name@example.org","organization":"Example",
  "_meta":{"claudeCode":{"kind":"account","plan":"max"}}}]}
{"state":"authenticated","accounts":[{"label":"Anthropic API key","active":true,
  "description":"ANTHROPIC_API_KEY","_meta":{"claudeCode":{"kind":"api_key","detail":"ANTHROPIC_API_KEY"}}}]}
{"state":"unauthenticated"}
{"state":"unknown"}
```

  Labels include `Claude Ultra` (tier `max_20x`), `Claude subscription` with
  description `OAuth token`, `AWS Bedrock`, `Google Vertex AI`, `Custom model
  gateway` (`auth-status.js:107-275`). `name` is never sent. For a
  subscription, `description` is left out "the client falls back to
  `account.email`" (`auth-status.js:262`).
- Claude also pushes `_auth/status_update`, its older extension. chord reads
  only the ACP method.
- codex 2.6.0 does not serve it (survey 2.2). factory-droid does (survey 3);
  its payload was not read (**?**).
- The schema: `AuthState` is `authenticated | unauthenticated | not_required |
  unknown | string`, an unknown word read as `unknown`; account fields are
  "display information only… SHOULD NOT log them or send them elsewhere"
  (`types:2447-2540`); updates "MAY [be sent] at any time after `initialize`"
  (`types:4395-4402`).

### Where chord asks and listens

- **Listener**: `openAgent` registers `onNotification('auth/status_update')`
  on its SDK client builder (`connection.ts:309-359`, which registers only
  requests today, so the update is dropped,
  `docs/design/evidence/CHD-624/drafts/protocol.md` P4). It keeps the
  latest payload on `Agent` (`authStatus(): AuthStatusResponse | undefined`
  plus a subscription). Registering it before `initialize` loses nothing.
- **Ask**: when `init.agentCapabilities.auth?.status` is present,
  `openSession` sends `auth/status` right after `initialize`, **beside**
  `session/new` rather than before it (`session.ts:505-528`). Claude joins its
  own probe, so the ask costs no second CLI run. The answer and every later
  update replace the kept status, last one wins (the agent "SHOULD only send
  it when the reported status differs").
- **`Session`** exposes `account()`, which is the connection's latest
  status, and an `account` event that `Conversation` passes to the window as
  a state event. It is per process. Each child has its own process
  (`openAgent` per `openSession`, `session.ts:465`), so its own account.
- **Not recorded, not relayed to tools**: no record line, no `-p` output, no
  MCP tool. The schema says not to log it, and `src/session/AGENTS.md`
  says "never infer account identity". `/status` draws it from memory.
- **Agents without `auth.status`**: no request, no state. `/status` shows
  no account line (interface's words).

### The sign-in failure (owner choice O3)

Today's sign-in path reads only a -32000 from a session request of the start
(`asSignIn`, `src/session/sign_in.ts:62-89`, called at `session.ts:588`).
Claude logged out does **not** refuse `session/new`. It refuses only for
`--hide-claude-auth` or a startup reason such as `org_pin_mismatch`
(`claude:startup-failure.js:10-33`, `hide-claude-auth.js:121-126`). Its first
prompt fails instead, with `authRequired` (`v1/acp-agent.js:4287, 4833`), and
chord draws that as an ordinary turn error, since `signInOf` is read only at
start (`conversation.ts:384`, `headless.ts:313`). With F2, chord learns
`unauthenticated` before or during `session/new`:

- **a.** The start fails as a `SignInNeeded`. If `auth/status` answers
  `unauthenticated` first, chord stops waiting on `session/new` and closes
  the agent (one process per session, so nothing else is lost). If
  `session/new` answers first, chord awaits the status, bounded by Claude's
  own 5 s probe, before it reports `connected`. The message is chord's own,
  from the protocol: the state, and the configured accounts if any are
  listed. The ways in come from `authMethods`, as today. Claude sends chord
  none (terminal and gateway methods only to clients that declare them,
  `v1/acp-agent.js:518-524, 576-579`), so the way on is `wayOn`.
  *Recommended*: it is the brief's "before `session/new`, not from the
  -32000 error". One cost: a logged-out Claude still launches a Claude
  Code query, and the person's `SessionStart` hooks run in it, before chord
  closes it.
- **b.** The same, but awaiting `auth/status` before sending `session/new`.
  Nothing is launched when signed out, but every Claude start waits for the
  probe first.
- **c.** Open the session anyway and only say "not signed in" in the
  transcript; the first prompt fails as today.

`unknown`, `not_required` and any other word never fail a start. A later
`unauthenticated` update (a logout mid-session) only changes `/status`.

### `chord acp`

`chord acp` answers `initialize` with no agent running (`acp_agent.ts:1790-1815`),
so it cannot know whether its agent offers `auth.status`.

- Advertise `agentCapabilities.auth.status: {}` always. Serve `auth/status`
  by passing it to the newest live main session's connection when that one
  offers it; otherwise answer `{state:"unknown"}`. That is a valid answer,
  and the client must read it so.
- Relay `auth/status_update` from main sessions' connections of the startup
  agent only, deduplicated by payload. Children's processes may be other
  agents, and the method has no session id.
- Not served: `logout` (F8).

## F3 — sessions open on the chosen mode, model and effort

### What Claude does with initial options (c)

- `newSession` takes `configOptions` out, creates the session as usual, then
  sets each entry in list order through the same `selectSessionConfigOption`
  as `session/set_config_option`, with `duringSetup` true. No update goes
  out for them; the response carries the modes and options as they stand
  after (`claude:v1/acp-agent.js:600-613, 652-662`). So "opens on them" means
  the answer already shows them. Claude Code itself still starts on its
  defaults and is switched before the answer.
- An entry that fails with -32602 (unknown id, wrong type, value not
  offered) is skipped silently. Any other failure is logged and skipped. The
  option keeps its value (`claude:initial-config-options.js:30-49`). Two
  entries with one id → -32602 for the whole request, before any session
  starts (`:17-27`).
- `duringSetup`: the Auto fallback's warning waits for the next prompt
  (`v1/acp-agent.js:5717-5721`). With F4 it then arrives as a notice.
- Load and resume take `configOptions` too, applied after the replay
  (`:757-781`). Fork takes none: `unstable_forkSession` ignores them
  (`:725-748`), and SDK 2.6's `ForkSessionRequest` has no such field.
- Ids: `mode` (`claude:session-mode.js:5`), `model` (`session-model.js:5`),
  `effort` (`session-config-ids.js:5`), `fast` (`session-fast-mode.js:9`).

### The table

Beside `FAST_OPTIONS` (`src/agents.ts:21-29`), but keyed by
`init.agentInfo.name` as the brief says. `FAST_OPTIONS` is keyed by registry
id, so the two tables differ in key (Q2 for the lead). The adapter name also
covers `agents.claude.command` and any command that runs the adapter, and it
is known when needed: `session/new` follows `initialize`.

```ts
/**
 * The config ids an adapter takes as initial `configOptions` (CHD-629), read
 * from its source and rechecked when its pin moves; asking `session/options`
 * first would make Claude run a throwaway Claude Code and the person's
 * SessionStart hooks (CHD-624).
 */
const INITIAL_OPTIONS = {
  '@agentclientprotocol/claude-agent-acp': { model: 'model', effort: 'effort', mode: 'mode' },
};
```

A stale id degrades to today: Claude skips the unknown id, and the read-back
sets the value after `session/new` with the id the session reports
(`modelConfigId`, `effortsOf(state).option`, `modeConfigId`,
`src/session/session.ts:780-852`).

### The request

When `sessionCapabilities.options` is present **and** the table has the
adapter, `openSession` adds the starting values it is handed:

```json
{"jsonrpc":"2.0","id":2,"method":"session/new","params":{
  "cwd":"/work/project","mcpServers":[],
  "configOptions":[
    {"configId":"model","value":"<the --model id>"},
    {"configId":"effort","value":"high"},
    {"configId":"mode","value":"plan"}],
  "_meta":{"claudeCode":{"options":{"promptSuggestions":false}}}}}
```

- Value form only (`InitialSessionConfigOption`, `types:5253-5279`): no
  `type`, since chord declares no `configOptions.boolean`. One entry per id.
- The order is model, effort, mode. That is `#applyStarting`'s order
  (`conversation.ts:3344-3383`), and Claude applies "in list order, so a model
  entry decides which effort levels a later entry can pick"
  (`initial-config-options.js:28-31`).
- Only values that are named go out: `--model`, `--permission-mode`,
  settings (`place.ts:184-188`), and a team member's or child's values
  (`agents_host.ts`). chord adds no default (D1 a). `fast` is not a
  starting value today and stays out.
- **`session/new` only**: the window, `/clear`, children, team members,
  `-p` (`oneshot.ts`) and `chord acp`'s sessions, all through `openSession`.
  Not load or resume: they keep set-after-open, which is the read-back
  anyway. The values gain nothing on screen there, since chord shows nothing
  before `#setUp` ends. Claude restores a resumed session's mode from its
  transcript. Not fork: neither the SDK nor Claude takes them.

### The read-back (one change to `askStarting`)

`#applyStarting` and oneshot's asks run as today, after `openSession`
returns with the answer folded into state (`session.ts:616`). Each ask gains
one step at each end:

1. **Before**: if the session already reports the asked id as current
   (`models().current`, `efforts().current`, `modes().current`), nothing is
   sent. This covers a value Claude took at setup, and an agent that
   already starts on it.
2. Otherwise, as today: refuse a value not listed (`starting.ts:84-87`), or
   ask through `setModel`/`setEffort`/`setMode`.
3. **After, mode only**: read `modes().current` again. If it is not the
   asked id, the agent fell back (Claude's `auto` → `acceptEdits` where Auto
   is unavailable, `claude:session-mode.js:10-14, 200-224`), and the ask is a
   refusal: "the agent is in acceptEdits" (interface words it). This is
   CHD-624's "the mode step reads the current mode at its turn and rechecks
   after a fallback". For codex, the enrichers already fill in the mode
   after `set_mode` (`session.ts:811-815`), so the reread sees it.

Every refusal reads as today: a value Claude skipped at setup is either not
listed ("the agent offers …", no request), or listed and refused again by
`set_config_option` in the agent's own words. A required value (a team
member's mode) still fails the start (`conversation.ts:3390-3392`). Nothing
new is drawn: modes and models are reported only after `#applyStarting`
(`conversation.ts:3236-3245`), as today.

**CHD-626's one chain** is untouched. Starting values are applied before
`connected`, when no person's change can be queued. The read-back's asks are
the same calls the chain makes later.

**Record**: nothing new. The first `state` line is written from the session
as it stands after the starting values (`record.ts:1254-1290`).

### `chord acp` (owner choice O4)

The schema says the client sends `configOptions` only to an agent that
advertises `options`, and advertising it means serving `session/options`:
"MUST NOT create or resume a session" (`types:5577-5585`).

- **a.** Advertise `options`. Serve `session/options` for a live session
  from `configOptionsOf(state)` (`upstream.ts:445-…`). For a new one, start
  the agent, `initialize`, pass `session/options` through where it is
  offered, and close it. An agent without it cannot be answered: an empty
  list means "no config options" (`types:3036-3040`), which would be false
  for codex.
- **b.** Do not advertise. If a client sends `configOptions` anyway, fold the
  entries into the session's starting values by the same ids `chord acp`
  lists (`configSetter`, `upstream.ts:498-…`). They then go down as initial
  options to Claude, or are set after new elsewhere. A client's value beats
  chord's settings for that session; a team member's values are chord's own
  and stay. *Recommended*: no extra process, the RFD is Draft, and a
  compliant client keeps using `set_config_option` as today.
- **c.** Do not advertise, and ignore `configOptions`.

## F4 — notices

### The declaration

`CLIENT_CAPABILITIES.session` becomes `{ compaction: {}, notices: {} }`
(`connection.ts:229-235`). `NoticeCapabilities` is `{}`-shaped
(`types:4674-4677`). Both adapters test it as a plain object
(`claude:session-notices.js:7-10`, `codex:src/SessionNotice.ts:3-6`).

### What changes on the wire (c)

**Claude 0.107** (`claude:session-notices.js`, `v1/acp-agent.js`, `session-mode.js`, `async-tasks.js`, `subagent-replay.js`):

| Source | Today (no `notices`) | With `notices` |
| --- | --- | --- |
| A client MCP server failed or needs auth (`:1321-1340`) | `agent_message_chunk` blockquote `> **MCP server "x" failed to start:** …` with `_meta.claudeCode.kind: "mcpServerStatus"` | `notice` warning or info, `MCP server "x" failed to start` / `Its tools are unavailable…` |
| Claude Code `informational`, level `warning` or above (hook `systemMessage`, a Stop hook's reason) (`:3480-3500`) | `**Warning:** <text>` as reply text | `notice`, deduplicated per `tool_use_id`. A hook-blocked turn's result that only repeats it is then not sent as text |
| `informational`, level `info` | plain reply text | **nothing**: "info is transcript-only noise" (`:3481-3482`) |
| Model refusal fallback (`:3711-3730`) | bold reply text | `notice` warning "Model fallback" |
| Fast mode went off or on (`:7183-7188`) | bold reply text | `notice` |
| Auto mode unavailable (`session-mode.js:213-224`) | `**Auto mode unavailable:** …` | `notice` warning; during setup it waits for the next prompt |
| An async task stopped by the person (`async-tasks.js:324`) | bold reply text | `notice` info "Task stopped by user" |
| Missing subagent history on load (`subagent-replay.js:336-338, 529-537`) | nothing | `notice` info "Some subagent history is not available" |
| `api_retry` and other session failures (`:3672-3696`, `session-failure-extension.js:250-252`) | AIR only | AIR only: **not** notices (the brief's "API errors" does not hold on v1) |

**codex 2.6.0** (`codex:src/CodexEventHandler.ts:847-890, 1061-1070`), which
the brief does not name:

| Source | Today | With `notices` |
| --- | --- | --- |
| Config warning | `Config warning: …` reply text | `notice` warning |
| Deprecation | nothing | `notice` warning |
| Warning | `Warning: …` reply text | `notice` warning |
| Model rerouted | thought chunk | `notice` info "Model rerouted" |
| Context compacted (the legacy event) | `*Context compacted…*` reply text | `notice` info |

Wire examples (`codex:src/__tests__/CodexACPAgent/data/session-notices-wire.json`):

```json
{"sessionUpdate":"notice","severity":"warning","title":"Unknown key `foo`","description":"in ~/.codex/config.toml"}
{"sessionUpdate":"notice","severity":"warning","title":"Auto mode unavailable","description":"…"}
```

### Reducer, record, cycles

- **Reducer**: a new module `src/session/transcript/notices.ts`, one function
  for `case 'notice'` in `applyUpdate` (`reducer.ts:327-394`, which drops it
  today in `default`). It appends
  `{kind:'notice', turnId, severity, title, description?}`, and never merges
  two notices (they have no id). `severity` is kept as sent; an unknown word
  is the reader's to treat as `info`. A subagent's notice goes into that
  subagent's entries, as its other updates do.
- **Record**: the update is recorded whole, as every update is
  (`record.ts:100-110`), so a resume draws it again (O5). Older records have
  none.
- **Cycles**: `notice` is not in `CYCLE_WORK` (`src/session/cycles.ts:67-73`),
  so a notice outside a turn opens no Claude cycle. Today the same advice,
  as an `agent_message_chunk` after a quiet spell, can open a cycle on Claude
  (`startsOwnCycles`, `session.ts:752`). F4 removes that.
- **Turn stamp**: a notice outside a turn is stamped with the last turn's id
  (`#stamp`), as compactions are. This is interface's to place.
- **`chord acp`**: relays `notice` to clients that declare it
  (`upstream.ts:59`). A client that does not gets nothing; chord does not
  re-word it as reply text. Q4.

## F5 — the tool call names the subagent

### Shape (c)

`ToolCallContent` gains `SessionReference & {type:"session"}`
(`types:220-228`), with `sessionId` and `_meta` only. "The referenced session
must already be known to the Client through ordinary session setup or a
`subagent_update` announcement. The reference does not establish ownership,
grant any Client-initiated controls, or report that the referenced session
received or finished any work."

```json
{"sessionUpdate":"tool_call_update","toolCallId":"toolu_9","status":"completed",
 "content":[{"type":"content","content":{"type":"text","text":"Stopped."}},
            {"type":"session","sessionId":"S-child-3"}]}
```

### Who sends it, and where

- **Claude 0.107, RFD form** (chord declares `subagents: {}`,
  `connection.ts:232`; `claude:acp-subagents.js:4-8`). The reference is
  appended after a call's content, on every report that carries content
  (`withSessionReference`, `native-subagents.js:1610-1625`), when the call
  operates on an **announced** child of another session (`withTarget`,
  `:1208-1221`):
  - a TaskStop or SendMessage call naming the child by agent id;
  - a SendMessage that resumed the child and stays shown because a
    permission request showed it;
  - an Agent/Task launch that stays shown for that same reason.
  An ordinary launch is **not shown as a tool call** in the RFD form. Its
  updates are held, and the parent's `session_message` replaces it
  (`routeRfdLaunch`, `:1076-1110`). chord draws such a child as its
  `Agent(<title>)` block from the `subagent_update`. So "the tool call that
  started a subagent" is, with Claude, mostly a SendMessage or TaskStop
  call, or a launch the person approved. Replays on load add the same
  references (`subagent-replay.js:33-43`).
- **codex 2.6.0**: none. **codex main**: on each collaboration tool call,
  one reference per announced receiver, as the call's whole standard content
  (`codex:src/subagents/StandardSubagentEventRouter.ts:790-799`). A call may
  name **several** children; a spawn's start may name none, its completion
  the new child.

### How chord reads it

- The reducer already keeps `content` whole (`transcript/tools.ts:69-80`).
  The record keeps the update whole, so a resume has it. No reducer change.
- One pure reader beside `subagentsIn` (`src/session/subagents.ts:59-66`):
  `referenced(call, entries): Subagent[]`. It maps each `session` item, in
  order and deduplicated, to the `Subagent` with that `id` at any depth.
  The window names each by `agentItemName` (`transcript/subagents.ts:688-694`),
  the name its background row has. Interface draws it.
- **Not known**: an id with no `Subagent` reads as nothing. With both
  adapters this happens only to a record missing the `subagent_update`
  (they send the reference only after the announcement). A reference to
  main's own id, or to a chord child (`spawn_task`, `open_agent`), is not
  sent by any adapter read here. chord does not guess at one.
- **Gone child**: the `Subagent` stays in the transcript with its end state,
  so the name still resolves.

### `chord acp`

In `rewritten` (`upstream.ts:338-…`), `tool_call` and `tool_call_update`
map each `session` item's `sessionId` through `upstreamIdOf`, as
`session_message` ids are mapped. For a client without `subagents`, those
items are dropped, since the client was never told of the child. An update
whose content was only references then goes with `content: []`, which is the
same content less the references. An id the session has not announced is
also dropped, never sent as it is (`asksIn`'s reasoning, `upstream.ts:237-239`).

## Failure cases

| Case | What happens |
| --- | --- |
| Agent exits while `set_title` is open | request rejects; refusal line; nothing recorded (O1 a) |
| `/clear` while `set_title` is open | the answer is for a retired session: dropped by `#current`; the new session's record untouched |
| Two `/rename`s in quick succession | Claude overlaps them (`explicitChanges`), codex queues them (`writes.run`); the record must follow request order, so chord sends one at a time per session (runtime's R1) |
| `/rename` during a turn | independent of the turn; both adapters serialise against title generation |
| Late agent title after `renamed` | takes over (D3 b); with Claude and codex only a rename made outside chord |
| `auth/status` hangs | Claude bounds its probe at 5 s; chord's own bound and what a hang does to the start are runtime's R2 |
| `auth/status_update` before any session | kept on the connection; read when `Session` is built |
| Logout mid-session (`unauthenticated` update) | `/status` changes; the session is not closed |
| Initial options refuse the whole `session/new` (-32602 duplicate) | cannot happen: one entry per id; any other `session/new` error is a start failure as today, no retry without the options |
| Claude skips an initial value | read-back sets it after new, or says the refusal as today |
| A stale table id | skipped by the agent; read-back sets it by the session's own id |
| Agent exits during `session/new` with options | start failure at `session/new`, as today |
| Notice outside a turn | stamped with the last turn; opens no cycle |
| Notice in a replay on `session/load` (Claude's missing-history notice) | drawn only for a session chord has no record of, as any replay |
| `session` reference before the child is known | drawn as nothing; not possible with Claude or codex main |
| Older record | no `renamed`, no `notice`, no `session` items: drawn as today |

## Open questions

- **O1 (owner): `set_title` refused** — a. nothing recorded, refusal line
  (*recommended*); b. chord records its rename anyway.
- **O2 (owner): `chord acp` renaming a listed session that is not loaded**
  — a. record only; b. start its agent, `set_title`, record (*recommended*
  where offered, a. elsewhere); c. -32002.
- **O3 (owner): Claude signed out at start** — a. fail the start as a
  sign-in once `auth/status` says `unauthenticated`, `session/new` sent
  beside it (*recommended*); b. await `auth/status` before `session/new`;
  c. open and only say it. Today Claude's start does not fail; the first
  prompt does, as a plain error.
- **O4 (owner): `chord acp` and `options`** — a. advertise and serve
  `session/options` with a process per call; b. do not advertise, fold a
  client's `configOptions` in if sent (*recommended*); c. ignore them.
- **O5 (owner or lead): notices in the record** — keep them, so a resume
  draws them (*recommended*; the record keeps every update whole), or drop
  them as live-only, as the schema describes notices.
- **O6 (owner): Claude's `info` messages** — with `notices` declared, Claude
  sends nothing for `informational` messages at level `info`, which chord
  shows as reply text today. This is the adapter's behaviour; chord can only
  accept it or leave `notices` undeclared.
- **Q1 (lead):** does a rename alone make a never-prompted session worth
  keeping in the record? Recommended no.
- **Q2 (lead):** the F3 table's key, `agentInfo.name` (brief, *recommended*),
  differs from `FAST_OPTIONS`' registry id. Keep both side by side as they
  are, or move `FAST_OPTIONS` to the adapter name too (out of scope unless
  wanted).
- **Q3 (lead or interface):** F5 with Claude rarely lands on a launch; the
  screen should expect it on SendMessage and TaskStop calls.
- **Q4 (lead):** `chord acp` and a client without `session.notices`: drop
  the notice (today, *recommended*) or re-word it as reply text, as the
  adapters do.
- **?** Whether Claude Code lists its own `/rename` among the agent's
  commands (not read: comes from the CLI at run time); chord's command would
  hide it either way.
- **?** factory-droid's `auth/status` payload was not read.
