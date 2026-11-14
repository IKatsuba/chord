# CHD-629 — brief: `/rename`, the account, initial options, notices, subagent links

The second PR of CHD-624 (the owner's D5 a). CHD-624 is merged: ACP SDK
2.6.0, claude-agent-acp 0.107.x, codex-acp 2.6.0. The owner took the
survey's recommendations for F1–F5 (D3 a, D3 b "every agent"), and changed
D1 to Claude starting in Auto. Read first:

- `docs/design/evidence/CHD-624/survey.md` — which runtime serves what
  (sections 2.1, 2.2, 3, 4 F1–F5, 5 D3).
- `docs/design/CHD-624.md` and its `docs/decisions.md` entries of
  2026-11-13/14, in particular "Claude starts in Auto": what it hands F3.
- `docs/design/evidence/CHD-624/drafts/protocol.md` and `runtime.md`: their
  D1 parts designed initial options for the mode alone; they are F3's
  starting point, not its decision.
- `docs/design/CHD-445.md` (the agent's title), `CHD-626.md` (`/effort`,
  `/fast`, one config chain, `FAST_OPTIONS`), `CHD-627.md` (`/new --name`,
  chord's own word reader, "no renaming" of a child's name).

Everything below is for every agent chord runs, and for `chord acp`, which
serves ACP v1 to another client over chord's own sessions.

## The features

### F1 — `/rename <title>`

A person types `/rename <title>` and the session's title becomes it: where
the agent's title shows today (`/resume` picker, header, wherever CHD-445
draws it). chord's record keeps the title for every agent; where the agent
advertises `sessionCapabilities.title` (claude 0.105+, codex 2.6), chord also
calls `session/set_title`. The agent's own title takes over again only on
its next `session_info_update` (owner, D3 b). `chord acp` serves
`session/set_title`: it renames chord's record, and the agent's where served.

### F2 — the account in `/status`, a better sign-in failure

Where the agent advertises `agentCapabilities.auth.status` (claude 0.104+,
factory-droid 1.10), chord asks `auth/status` and listens to
`auth/status_update`. `/status` gains the signed-in account (e.g.
"Claude Max · name@org", from `AuthAccount` and its `description`). A start
that fails for sign-in says which account is missing before `session/new`,
not from the -32000 error. No new key. `chord acp` passes `auth/status`
through from the agent behind it and relays updates.

### F3 — sessions open on the chosen mode, model and effort

Where the agent advertises `sessionCapabilities.options` (claude 0.106+),
the starting values chord would set after `session/new` today
(`#applyStarting`: `--model`, `--permission-mode`, settings, team members'
mode/model/effort) go out as initial `configOptions` on `session/new`, so the
session opens on them. Elsewhere, set-after-new as today, which stays the
read-back and fallback. Carried from CHD-624:

- `session/options` before every start makes Claude run a throwaway Claude
  Code and the person's `SessionStart` hooks: config ids come from a table
  keyed by the adapter's `agentInfo.name`, beside `FAST_OPTIONS`.
- The mode step reads the current mode at its turn and rechecks after a
  fallback.
- The default goes on `session/new` only (not load, resume or fork, unless
  the design shows why).
- chord sends no start mode of its own: Claude's Auto default and the
  person's `permissions.defaultMode` keep deciding when nothing is named.

Nothing new is drawn: no flash of defaults. `chord acp` accepts initial
`configOptions` on `session/new` and passes them down; whether it then
advertises `options` (and so must serve `session/options`, the RFD's MUST)
is a question below.

### F4 — notices as a dim line

chord declares `session.notices` to agents and draws a `notice` update as
one dim line in the transcript, instead of dropping it (Claude sends "Auto
unavailable", why Fast went off, API errors; without the capability it
sends them as bold reply text). `chord acp` already relays `notice` to
clients that declare it (`src/session/upstream.ts:59`).

### F5 — the tool call names the subagent it started

The `session` tool-call content (claude 0.107, codex main) links a tool call
to the child session it started. Today `contentLines`' `default` draws it as
nothing. The tool call names the child (its row name in the agents list);
the child stays reachable as today (↓ into the agents list). No new key.
`chord acp` relays it, with ids aliased as it aliases children.

## Constraints

- AGENTS.md is binding: the one rule (SDK types for every method; no
  workaround around a library without the owner), every action a key in the
  shortcuts panel, logic in pure tested modules, tests only on fake ACP
  fixtures (`tests/fixtures/fake_agent/`).
- Main session only for new designs; no tabs (CHD-493).
- The wire is read, never guessed (CHD-624's rule): no inferring a
  capability, a config id or a title source from words.
- Each feature says what an agent without the method shows.
- Records: older records still load; new fields are optional.

## Non-goals

`systemPrompt` (F6), `session/status` (F7), terminal auth and `logout`
(F8), cursor-cloud-acp serving more (F9, CHD-630), archive, proxy chains,
ACP v2, renaming a child's name (CHD-627).

## Screens

Each draft that changes the screen gives it as text at 120x40 and 80x24,
with its states, as `docs/design/CHD-624.md` does.

## Open questions

### protocol (the agent's side, records, `chord acp`)

1. F1: exact wire order of `set_title` vs the record; does Claude or codex
   answer `set_title` with a `session_info_update`, and how is that told
   apart from the agent's own later title (D3 b)? What the record entry is
   (a chord-own entry, or a synthesised `session_info_update`), and how
   `sessions.ts`'s title reader (`:257`) takes it.
2. F1 on a child or a picked agent: does `/rename` apply there, and what
   about a session not yet started or closed?
3. F2: when chord calls `auth/status` (at `initialize`? on `/status`?), what
   it keeps, how `auth/status_update` reaches `/status`, and what "a better
   sign-in failure" reads from before `session/new`.
4. F3: the table: keys (`agentInfo.name`), ids for mode, model, effort;
   what goes on `session/new` vs load/resume/fork; read-back from the
   response's `configOptions`; interaction with CHD-626's one config chain.
5. F3 for `chord acp`: accept and pass down only, or advertise `options`
   and serve `session/options`? Its client's own initial options vs chord's
   settings.
6. F5: the `session` content's shape in SDK 2.6, how its id maps to a child
   chord already tracks (and when the child is not yet known), aliasing in
   `chord acp`.
7. F4: declaring `session.notices` changes what Claude sends: list what
   stops arriving as reply text.

### interface (screen, states, keys, state slices)

1. F1: `/rename`'s command entry, its argument (whole rest of line as
   `/fork <name>`), empty `/rename`, a refusal or failure line; where the new
   title shows; is there a key besides the command, and its shortcuts-panel
   line?
2. F2: the `/status` report's account line(s), signed out, unknown, an agent
   without `auth/status`; the sign-in failure screen at start.
3. F3: confirm nothing new is drawn; what a refused initial value shows
   (today's refusal line?).
4. F4: the dim notice line: glyph, colour, wrap, place in the transcript,
   repeats, and in the transcript view (ctrl+o).
5. F5: how the tool call's line names the child; a child unknown or gone.
6. All: 120x40 and 80x24 screens; state slices and pure reducers.

### runtime (processes, concurrency, failure, testability)

1. F1: `/rename` during a turn, before the session is open, while
   `set_title` is in flight; a refusal of `set_title`; record write order.
2. F2: an `auth/status` that hangs or errors; updates arriving before a
   session; per-process vs per-session state; children on the same process.
3. F3: initial options vs set-after-new ordering, the mode recheck after a
   fallback, the read-back, a stale table after a pin bump (how a test
   catches it), no `session/options` call.
4. F4/F5: nothing blocks a turn; a notice outside a turn opens no cycle
   (`cycles.ts`).
5. Fake agent scenarios and flags for each feature, and which tests reach
   them (`tests/` mirrors `src/`).

## For every draft

Name what you read with file:line. Say which questions you could not
answer from code and leave them open; mark any choice that is the owner's
(scope, a library that does not fit, changing what the task asks) with
options and a recommendation. Write only your own draft file in this
folder; touch no code.
