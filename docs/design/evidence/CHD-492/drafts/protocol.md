# CHD-492 — protocol draft

The agent's side, the records and what is stored, for a launcher-given window
id. Answers the brief's protocol questions by number. Read before writing:
`src/session/windows.ts`, `src/session/record.ts` (`FileRecording`),
`src/cli.ts`, `src/main.tsx` (start, quit), `src/ui/app/sessions.ts` (`quit`,
`clearFront`), `src/ui/app/renderer.tsx` (`dieBySignal`, `leave`),
`src/status.ts`, decisions.md's "Resume on chord's own session record", "A
window record, and `--resume w-…`", "Windows in `/resume`…", "Teams on
resume" and "OpenTUI part 6". Adapters read: `@agentclientprotocol/sdk`
1.8.0's schema, `@agentclientprotocol/claude-agent-acp` 0.93.0's
`dist/acp-agent.js` and `resumed-session.js` (from the npx cache). Codex's
adapter (`codex-acp` 2.2.2) ships a native binary; its behaviour on a
never-prompted session was not read and is marked unverified below.

## Summary of the picks

- One new flag, `--window <id>`, create-or-reopen, taking a full `w-…` id.
  `--resume w-…` keeps its meaning (reopen, refuse when missing). Chorded
  calls `chord [agent] --window w-<id>` every time, first start and reopen
  alike.
- The id stays chord's existing shape, `^w-[0-9a-z]+$`; a launcher picks
  `w-` + a UUID's 32 hex digits without dashes. No widening, so an older
  chord reads the file.
- The window record keeps its file and fields. Tab entries may lack
  `sessionId` (a tab no prompt went to yet) and `tabs` may be empty, for
  `--window` windows only. A record whose tabs all have a session reads in
  an older chord unchanged; one with a fresh tab or no tab does not (said
  below; the owner's).
- Nothing changes on the wire: `session/new`, `session/resume`,
  `session/load` exactly as today. No client-chosen session id (alternative
  d), no adapter `_meta`.
- The session record's "nothing until a prompt" stays.
- OSC 7501 carries nothing new: it has no field for it, and the id exists in
  the launcher already.

## 1. The flag and the id format

### Options

| | Shape | For | Against |
|---|---|---|---|
| A | `--window <id:string>`: create-or-reopen | A required value, so Cliffy's optional-value limit ("Windows in `/resume`") does not apply; one command for the launcher whatever happened at exit; `--resume`'s typo refusal stays | A second flag naming a window |
| B | `--session-id <uuid>` | Claude Code's name, which Chorded already calls | Promises what ACP cannot do: the id would not be the agent's session id (`NewSessionRequest` has `cwd`, `additionalDirectories`, `mcpServers`, `_meta` only, SDK 1.8.0), and a window holds several sessions. `chord --resume <that uuid>` would then mean a window under a session's name |
| C | `--resume w-<id>` creates when missing | No new flag | `--resume`'s refusal (`No window w-… among chord's records.`) is what catches a typo; creating instead hides it. `-r` is `[id:string]` with `collect`: `-r` alone is the picker and `-r w-a -r w-b` is refused as mixed — creation semantics on that option tangle with both |
| D | An environment variable (`CHORD_WINDOW`, Cliffy's `.env()`) | No argv change | Inherited by every process chord starts: an agent's bash running `chord` would open a second chord on the same id (the two-holders case runtime has to handle, made common) |

**Pick A.** `chord [agent] --window w-<id> [-C dir] [-m …] [--effort …]
[--permission-mode …]`.

- No record `windows/w-<id>.json`: a new window under that id, its first tab
  `[agent]` (or the default) in `-C`, written at once (runtime's question 1
  for when). From then on the id names it.
- A record there: opened as `--resume w-<id>` opens it today (each tab on its
  recorded agent and directory; `[agent]`, if named, must be every tab's;
  `-C` is not used, as a resumed session's record names its directory), plus
  the fresh tabs of question 3. A record that cannot be parsed is refused,
  not overwritten (`Window w-… 's record cannot be read.`, today's text): a
  window silently replaced is a window lost.
- Later `chord --resume w-<id>` opens the same record as a reopen-only
  command, as today, and goes on writing to it (today's "opened from a
  record, quit again: the same record").

**Conflicts**, declared in Cliffy as `-p` declares its own: `--window` with
`--resume`, `--continue`, `--print`. With `-r` the window would be named
twice; with `-c` "latest session" and "this window" disagree; `-p` has no
window. `--agent-command` goes with `[agent]` as today, so it applies to the
agent it names in a reopened window, as it does on `--resume`.

### What a launcher may choose

- **Options:** (i) `w-` + 8 hex only, as chord mints; (ii) anything the
  existing regex takes, `w-[0-9a-z]+`; (iii) widen it to take a UUID with
  dashes (`w-[0-9a-z-]+`).
- **Pick (ii), with a length bound on input only.** `--window` takes
  `^w-[0-9a-z]{1,64}$`; a UUID's 32 hex digits without dashes fit
  (`w-3f2a…c9`, 34 characters). The read path keeps `^w-[0-9a-z]+$`, so
  every existing record and every new one reads in an older chord, whose
  `readWindow` and schema test the same regex. (iii) would make a new
  record with a dash in its id unreadable to an older chord's schema and
  `readWindow`; (i) collides too easily across one launcher's panes (2³²).
- **No rewriting of the value**: a value without `w-`, or with a dash or a
  capital, is refused with the accepted shape
  (`--window takes w- and up to 64 of 0-9 and a-z, as w-1a2b3c4d`), not
  prefixed, lowered or stripped (the one rule; no guessing at input).

Cliffy: a plain `<id:string>` option. No optional value, no `collect`, so
the limit the owner accepted for `--resume` does not reach it: `--window c`
is the id `c`… which the regex then refuses, as it lacks `w-`. Nothing of
argv is rewritten.

**What the owner decides:** the flag's name (`--window` against something
Chorded-shaped such as `--session-id`, which this draft argues against), and
whether a launcher-chosen id may be any `[0-9a-z]{1,64}` or only chord's 8
hex.

## 2. The record's schema

Today (`WindowSchema`): `{ id, at, tabs: [{ sessionId, agent, cwd }] min 1,
front }`, `front < tabs.length`. zod's `z.object` strips unknown keys rather
than refusing them, so an older chord reads any added optional field
silently.

### What changes

```jsonc
// windows/w-3f2a9b0c4d5e6f708192a3b4c5d6e7f8.json, written by --window
{
  "id": "w-3f2a9b0c4d5e6f708192a3b4c5d6e7f8",
  "at": 1792598400000,          // last written, epoch ms (was: when it quit)
  "tabs": [
    { "sessionId": "0199f1c2-…", "agent": "claude", "cwd": "/work/app" },
    { "agent": "codex", "cwd": "/work/app" },   // no prompt yet: fresh
    { "sessionId": "8d1e…", "agent": "claude", "cwd": "/work/lib" }
  ],
  "front": 1                    // index into tabs, all of them
}
```

- `tabs[].sessionId` becomes optional: absent for a tab whose session has no
  record (question 3). `front` indexes every tab, fresh ones included.
- `tabs` may be empty (`min(0)`) for a window whose last tab closed in a
  way that left it running (not possible today: the last tab's close is a
  quit) — in practice only a record written before the first tab opened,
  if runtime writes that early. If runtime writes after the first tab is
  placed, `min(1)` stays and only `sessionId` loosens. Runtime's question 1
  settles which; this draft prefers writing after the first tab is placed,
  which keeps `min(1)`.
- `at` means "last written". `/resume` sorts by it and its row says it as
  the last use, which it now is; the quit is the last write anyway.
- **No `live`/`ended` mark, no writer pid in the record.** A pid in a file
  rewritten on each change is stale after a SIGKILL exactly when it would be
  read; whether another chord holds an id is runtime's lock, kept outside
  the record. An "ended cleanly" mark would let the screen say "this window
  did not close cleanly", but nothing in the brief needs it; left out until
  interface asks for it.
- No `version` field: an older chord ignores it, so it would only tell a
  newer one what the shape already tells.

### Readable both ways

| Record | New chord | Older chord |
|---|---|---|
| Existing `w-` record | reads (every new field optional, regex unchanged) | reads |
| New, every tab with a session | reads | reads, byte for byte today's shape |
| New, a tab without a session | reads | `parseWindow` fails: `--resume` says `Window w-…'s record cannot be read.`; `/resume` leaves it out |
| New, no tab (only if `min(0)`) | reads | as above |

The third row is the cost of restoring fresh tabs in place. **Options** that
keep an older chord reading it: (a) fresh tabs in a separate optional field,
`fresh: [{ at: 1, agent, cwd }]`, with `tabs` the resumable ones only and
`front` into `tabs` — every new record stays readable by an older chord,
which reopens the prompted tabs and drops the fresh ones; the cost is two
lists to merge and a front that cannot point at a fresh tab without a second
field; (b) leave fresh tabs out altogether (question 3's option L), so the
record never needs the loosening. **Pick: the optional `sessionId`**, as the
simplest shape that says what the window was; the older chord's refusal is
honest and costs only a downgrade. **The owner's** if a downgrade must read
every new record, in which case (a).

### The rule for windows without `--window`

Unchanged: written at a clean quit, only with two or more prompted tabs,
id minted at quit. The continuous writing, the fresh tabs and the one-tab
window are for `--window` windows (and for a record they wrote, when it is
reopened by `--resume w-…`). This keeps decisions.md's two window decisions
for every window a person starts by hand, and `/resume`'s list free of a
one-tab window beside its own session's row for each of them. **The
owner's:** whether every window should write from start (a different and
larger change to the written decisions).

## 3. A tab with no prompt

**Options:**

- **F (fresh): written as `{ agent, cwd }`, reopened as a new session of its
  agent in its directory, at its place in the strip.** The window comes back
  with the same tabs in the same order and the same front, which is the
  brief's step 4.
- **L (left out): not written,** as the quit leaves it out today; the window
  reopens with its prompted tabs only, the front moving to the nearest
  prompted one on its left (today's rule).
- **R (agent's session reopened):** write its `sessionId` and ask the agent
  to `session/resume` or `session/load` it. Not possible for Claude:
  claude-agent-acp says in `recreateLiveSession` that "Claude Code writes the
  conversation at the first prompt, so resuming a session that was never
  prompted fails with `resourceNotFound`"; its fallback to a fresh query
  under the same id only works on the same connection, which a new chord
  process does not have. Codex: unverified (the adapter is a native
  binary); if it differs it is still one agent's behaviour, and the brief's
  non-goals exclude it.

**Pick F.** It costs one optional field (question 2) and gives the launcher
the window as it was; a fresh tab loses nothing, as it had nothing. On the
wire it is today's `session/new` for that tab:

```json
{ "jsonrpc": "2.0", "id": 3, "method": "session/new",
  "params": { "cwd": "/work/app", "mcpServers": [ … chord's, as today … ] } }
```

and a recorded tab is today's reopen, by `session/resume` where the agent's
`sessionCapabilities.resume` is offered, else `session/load`:

```json
{ "jsonrpc": "2.0", "id": 4, "method": "session/resume",
  "params": { "sessionId": "0199f1c2-…", "cwd": "/work/app", "mcpServers": [ … ] } }
```

drawn from chord's record either way ("A parent resumed after its agents
ran"). A fresh tab's model, effort and mode start as a new session of that
agent starts in that directory, from the files (`-m` and the rest apply as
they do on `--resume`), not from anything recorded: nothing was.

**The owner's:** F against L, if restoring something that never held a
conversation is judged noise.

## 4. Which tabs the record holds, and `/clear`

The record is the strip: one entry per tab, in order, the front by index.

- **`/clear`** lets the tab's session go and opens a new one, which has no
  record until its first prompt. The tab's entry loses its `sessionId` and
  becomes fresh (`{ agent, cwd }`) at once; after the new session's first
  prompt it takes the new id. The old session is still in `/resume`'s list
  as its own session. Writing the old id until the new one is prompted would
  reopen the conversation the person cleared.
- **A tab opened by `ctrl+x c`, by `/new <agent>`, by `/resume` (Enter on a
  session or a window):** in. They are tabs; a window `/resume` opened beside
  joins this window's record, as its tabs join the strip.
- **Team and task agents:** out. They are a tab's children (`tab.children`),
  not tabs; their records name their parent, and a reopened parent draws
  their work from them; `--resume` does not reopen them ("Teams on resume",
  the owner's answer 5). Writing them would reopen what the owner decided
  stays closed.
- **A tab whose agent exited, or failed to start:** in, with its `sessionId`
  if it had one; it is reopened as any other, and fails again as it did if
  the agent is still unable.
- **A tab closed (`ctrl+x k`, `/exit` of one tab):** out at once.

When a tab "has a session" for the record: the test the quit already uses,
`resumableSession` (a `user` or `message` entry in its transcript), so the
window and the quit never disagree. This needs no new event from
`FileRecording`. The race it leaves: the window record written in the
milliseconds between a first prompt and its session record's first flush,
then a SIGKILL — the window names a session with no record. `windowTabs`
already handles that: the tab is left out and the status line says so
(`Not reopened: claude tab 0199f1c2, its record is gone`). The alternative,
a `recorded` signal from `FileRecording` once its first line is on disk, is
exact but adds a channel from the recording to the window for a
milliseconds-wide case; not picked, listed for the critic.

## 5. "Nothing until a prompt"

**Kept.** Options:

- **Keep:** a never-prompted session leaves no session record.
- **Write the `session` line at open:** gives every fresh tab a record.

The second gains nothing for a reopen: the agent cannot reopen such a
session (question 3, R), so the tab is a fresh session either way, and the
window record already holds its agent and directory. It would cost
`/resume`'s list rows for sessions that never held anything, or a new filter
for them, and it overturns the decision for every session, not only
`--window` ones.

## 6. OSC 7501

**Report nothing new.** OpenTUI's `ProgramStatus` (0.6.x `types.d.ts`) has
`id` (the record's path, an address, not data), `app`, `title`, `message`,
`state`, `progress` and `kind`. None is a field for a resume id: `title` and
`message` are what a person is shown, and putting an id in them would be
using a display field as a data channel. And it would not help: the
launcher-given id is the launcher's already, before chord starts, and a
chord-minted one would still be unknown after a SIGKILL that came before
the first report. Alternative (c) is rejected for this design.

**Open, for Chorded rather than chord:** if the Program Status Protocol
grows a field for "how to resume me", chord could fill it for windows
started without `--window`. Not needed for CHRD-412.

## The agent's side, end to end

Nothing chord sends or reads over ACP changes. Per tab, at reopen:

| Tab in the record | Sent | Drawn from |
|---|---|---|
| `sessionId`, record present | `session/resume` if offered, else `session/load` | chord's record, as today |
| `sessionId`, record gone | nothing; tab left out, `sessionsNote` says so | — |
| no `sessionId` | `session/new` in its `cwd` | nothing |

Alternative (d), a client-chosen agent session id, is rejected up front:
not in ACP's `session/new` (v1 or v2, SDK 1.8.0). claude-agent-acp has
internal routes to a chosen id (`_meta.claudeCode.options.resume` on
`session/new`, `options.sessionId` passed to the Claude Agent SDK), but they
are one adapter's private `_meta`, not the protocol, and using them is the
adapter-specific workaround the one rule forbids.

## Reducer actions and state

No transcript reducer action changes: nothing on the wire does. The window
record is derived, not reduced: a pure function of the tab strip (tab order,
each tab's agent, its place's `cwd`, `resumableSession` of its session, the
front key) to a `WindowRecord`, of the same inputs `quit` in
`src/ui/app/sessions.ts` reads today; where it lives and which state changes
trigger a write are interface's (its question 3) and runtime's (its
question 1). From the protocol side, the changes that alter the result:
a tab opened, closed or moved; the front changed; a tab's first `user` or
`message` entry; `/clear`; a window opened beside by `/resume`. A session
update, a turn's end, a cancel, a permission: none.

`windowTabs` (`src/session/windows.ts`) changes in two places: a tab with no
`sessionId` becomes a fresh tab (agent and directory, no `resume`) rather
than being looked up, and "none of the window's sessions is among chord's
records" is refused only when nothing at all opens — a record of fresh tabs
opens them. `ResumedTab` grows the fresh case, or a sibling type; that is
the ship team's.

## What the record keeps

- Per tab: agent (by the name chord starts it by), directory, and the
  agent's session id once a prompt went to it.
- The front, by index over all tabs.
- When it was last written.
- Not kept: drafts, scroll, model/mode of a fresh tab (non-goals; a recorded
  tab's are in its session record already), children, which tab was picked
  inside a tab, the strip's attention state.

## Failure cases (protocol side)

- **The agent exits mid-session.** The tab stays in the record with its id;
  the session record holds what was heard. Reopen resumes it.
- **A turn is cancelled.** No window change; the session record already
  has the prompt, so the tab has its id.
- **An update arrives late** (after `/clear`, after the tab closed, after a
  quit began): the window record does not read updates. A cleared session's
  late lines go to its own record through `FileRecording`'s retired path
  (CHD-373) as today; a closed tab's to its record if it is still being
  written, else nowhere, as today.
- **`/clear` then SIGKILL before the next prompt.** The record says the tab
  is fresh; it reopens fresh, which is what the person had.
- **The session record is gone or unreadable at reopen.** The tab is left out
  with today's note; the rest open.
- **The agent can neither resume nor load.** As `--resume <id>` today: that
  tab says so; the window opens. A fresh tab only needs `session/new`.
- **An agent in the record is not known any more** (removed from settings,
  not installed). Today `main.tsx` refuses the whole start
  (`Session … is of agent …`). For a launcher the window would then never
  reopen. Open question below.
- **A directory gone.** Claude's adapter refuses `session/load` /
  `session/new` for a missing `cwd` (`validateCwd`); the tab shows the
  agent's error. Runtime decides whether chord checks first.
- **Two chords on one id, a half-written file, an unwritable state
  directory:** runtime's.

## Open questions

For the owner (through the lead):

1. Flag name and shape: `--window w-<id>` create-or-reopen (picked) against
   `--session-id` or `--resume` creating.
2. A launcher-chosen id: `w-[0-9a-z]{1,64}` (picked) or only chord's
   `w-` + 8 hex.
3. A never-prompted tab: reopened fresh in place (picked) or left out.
4. Older chord reading a new record with a fresh tab: refused as unreadable
   (picked), or the separate `fresh` list that keeps it readable.
5. Whether windows started without `--window` also write from start (not
   picked; keeps both written window decisions for them).

For the team:

6. Interface: one tab started with `--window` — does the quit print the
   window command (the launcher's) or the session's? This draft assumes the
   window command, since the window record exists either way.
7. Runtime: whether the first write comes before or after the first tab is
   placed, which decides `tabs`' `min(1)` (question 2).
8. All: a record naming an agent chord no longer knows — refuse the start as
   today, or open the other tabs and say which was not? The latter changes
   today's refusal for `--resume w-…` too.
9. Critic: the `resumableSession` test against a `recorded` signal from
   `FileRecording` (question 4).

## Libraries tried

None new. Everything above uses what chord has: Cliffy's `.option` with
`conflicts` for the flag (its `.env()` looked at and not picked, question 1
D), zod for the schema (its default stripping of unknown keys is what keeps
an older chord reading added fields), `crypto.randomUUID()` for chord's own
ids, the existing write-and-rename for the file, and the SDK 1.8.0's
`session/new`/`resume`/`load` unchanged. Read, not run: claude-agent-acp
0.93.0's session creation and reopen paths, for question 3.
