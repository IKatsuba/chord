# CHD-493 — protocol's draft

The agent's side of removing tabs: records, `/resume` and `--continue` as they
read them, OSC 7501's fold and title, `chord_session`, chord's MCP tools, old
window records, and CHD-445. Read on origin/main `3f6f6656` (v0.57.0).

The short of it: **nothing chord sends the agent over ACP changes, and the
session record's format does not change.** What goes is the window record's
writing and listing, the tab dimension of OSC 7501's fold, and `tab` in one
MCP tool's answer. What reads the records today still reads every record
written before.

## 1. What goes, and what stays, on this side

### Window records (`src/session/windows.ts`, 573 lines)

Goes (with their tests in `tests/session/windows_test.ts` and the callers in
`src/main.tsx:55-66`, `src/ui/app/sessions.ts:74`, `src/ui/app/state.ts:16`,
`src/ui/app/Start.tsx:4`, `src/ui/pickers/*`):

| Export | Line | Why it goes |
| --- | --- | --- |
| `newWindowId`, `writeWindow`, `windowText`, `windowOnQuit`, `windowMessage` | 80, 154, 93, 179, 197 | nothing writes a window record: a process has one session, which resumes by its own id |
| `windowTabs`, `missingNote`, `WindowTabs` | 229, 278, 209 | `--resume w-…` no longer opens tabs (§4) |
| `readWindows`, `earlierWindows`, `EarlierWindow`, `ResumeEntry`, `resumeEntries`, `windowIn`, `entriesIn` | 297–429 | `/resume` and the start picker list sessions only |
| `AGENTS_WIDTH`, `windowAgents`, `windowSummary`, `windowDirectory` | 435–515 | the window row |
| `windowRoom`, `capNote`, `windowElsewhereRefusal` | 522–572 | opening a window beside, and the cap |
| `mixedRefusal` | 202 | `--resume` takes one id (runtime's); a window id is refused on its own (§4) |
| `MAX_TABS` import | 27 | |

Stays, to read the old ones (§4): `WINDOW_PREFIX`, `WINDOW_ID`, `isWindowId`,
`WindowTab`, `WindowRecord`, `WindowSchema`, `parseWindow`, `readWindow`,
`windowsDir`, `windowFile`. The module's doc comment becomes "the window
records chord wrote before 0.58.0, read so `--resume w-…` can say what each
held". The rule in `src/session/AGENTS.md` ("records … are stored formats:
records written before a change must still read back") holds: they still
read back.

### Session records (`src/session/record.ts`, `replay.ts`, `sessions.ts`)

The format is unchanged: no entry type is added, removed or changed. Nothing
in `RecordEntry` (`record.ts:35-200`) names a tab; a tab-era record is a
session's record like any other and resumes as today. Doc comments only:

- `record.ts`'s `closed` entry (`record.ts:116-121`): "as the tab, `/clear`
  or `/resume` let the parent go" loses "the tab".
- `sessions.ts:1-6` loses "A whole window's, by its own record, is
  `windows.ts`'s"; `earlierSessions`' note "as two windows may leave"
  (`sessions.ts:185`) becomes "as two chords may leave" — two processes in
  two panes can still open one session, so the dedup by latest stays.

In `sessions.ts`, with runtime (who owns the CLI):

- `sessionsByIds`, `ResumedTab`'s plural use, and the `MAX_TABS` import
  (`sessions.ts:12`, `314-358`) go with `-r a -r b`; `sessionById`
  (`:284`) is what `--resume <id>` calls, as it does for one id today.
- `ResumableTab` and `resumeMessage` (`:398-432`) keep their behaviour for one
  session: `Resume this session with:` and one command. The plural branch
  (`Resume these sessions with:`) goes. `ResumableTab` is renamed
  `Resumable` (the name is the only change).
- `latestSession` (`--continue`, `:140`) and `earlierSessions` (`/resume`,
  `:187`) are unchanged: they read session records only, never windows.

What `/resume` and `--continue` read afterwards:

| Entry point | Reads | Change |
| --- | --- | --- |
| `--continue` | `readRecords` → `latestSession` (this agent, this directory, no `parent`) | none |
| `--resume <id>` | `readRecords` → `sessionById` | none; one id only (runtime) |
| `--resume` (picker) | `readRecords` → `earlierSessions` | no `readWindows`; refusal `No earlier <agent> session to resume.` (drops "or window", `main.tsx:317`) |
| `/resume` | `readRecords` → `earlierSessions(…, except = the main session's id)` | no window rows; the pick replaces the main session (interface/runtime) |
| `--resume w-…` | `readWindow` | refused with each session's command (§4) |

A note for interface: windows were listed "whatever their agents"
(`windows.ts:347`), sessions only for the running agent (`sessions.ts:191`).
A codex session that lived in a window run from `chord claude` was reachable
from `chord claude`'s `/resume` through its window row; afterwards only from
`chord codex`'s, or by the commands §4 prints. Nothing is lost; it is where
the person looks that moves.

## 2. OSC 7501 (CHD-382, CHD-491)

`src/status.ts` folds `Tabs` (`status.ts:151`): every tab and every child,
the first state in `blocked, error, working, done, idle`, ties to the oldest
`since`, then "further left" by `key`. The name in the message is
`notifiedName` (`tabs.ts:695`), which for a tab is `tabName` — the agent
alone while there is one tab (`tabs.ts:678-689`).

Afterwards the fold is over **the main session and its children**, the same
order and the same tie-break (key order is now main first, then children in
the order they opened, which is what "left" meant inside one tab). The
record a person sees with one session is byte for byte today's record with
one tab: today's single-tab path is the only path. So:

- `programStatus(tabs, title)` takes what runtime's state gives for the one
  session (its main `wait` and its children's) instead of `Tabs<C>`; the
  rule, `agentStatus`, `statusLine`, `TITLE_BYTES`, `MESSAGE_BYTES` and
  `sameStatus` are unchanged.
- The name in `message` is the main session's agent, or the child's name
  (`tester (bugfix)` for a member), as `notifiedName` gives it today; never
  `claude (2)`.
- **Title** (`App.tsx:912-921`): the main session's `Conversation.title ??
  openSessionLabel(firstPrompt)`; "front" drops from the comment and the
  guide. Q111 (the front tab's name) has nothing left to choose; Q119 (the
  agent's title, else the first prompt) holds as is.
- Example, a member waiting on a permission while the main session works:

  ```
  ESC ] 7501 ; state=blocked:app=chord:title=<b64 "fix the login form">:kind=permission:message=<b64 "tester (bugfix) needs your permission: Write notes.txt"> ESC \
  ```

  (field order and encoding as OpenTUI's `setProgramStatus` writes them;
  chord does not build these bytes.)

`src/status.ts:1-5`'s doc comment ("for every agent of every tab at once")
and `docs/guide.md:455-461` ("covers every agent in every tab", "names the
front tab's main session") are reworded. CHD-382 and CHD-491 have no entry in
`docs/decisions.md`; nothing there to overturn.

## 3. `chord_session` (CHD-492)

The variable says the main session's resumable id; there is one main session,
so the table in `docs/design/CHD-492.md` loses the row "until CHD-493 removes
tabs: the front tab changes" and nothing else. `App.tsx:925-935`'s hook reads
`tabs.find(tab => tab.key === front)`; it reads the main session instead.

What other changes in this task do to it:

- **A `/resume` pick replacing the main session** (interface/runtime): the
  picked session's id once it is open — already the table's "a `/resume`
  pick" row, which no longer means "a tab beside".
- **`/new`**: what it becomes is one owner question, the lead's. If it
  becomes "end this session and start a new one", the variable goes as on
  `/clear` — empty at once, the new id once its first prompt is flushed; if
  `/new` goes, nothing here changes.
- **No main session for a moment** (a quit stopping the agent; a replace
  between the old session closing and the new one opening, if runtime's
  sequence has one): keep the last value written, as `App.tsx:926-928`
  says today. The variable is never cleared by chord's own going.

`docs/decisions.md` 2026-10-21 "CHD-492: chord tells the terminal the session
id to resume, in a user variable (owner, Q124)", the bullet "… until CHD-493,
the front tab's" (`decisions.md:7033`): the clause goes; the rest holds.

## 4. Old window records and `--resume w-…`

People have `windows/w-<id>.json` files from 0.54.0–0.57.0, and may have
`chord --resume w-…` in their scrollback or scripts. Each session such a
record names has its own session record in `records/`, and is already
listed by `/resume` and found by `--resume <id>`: no work is lost when chord
stops opening windows. What is left is what `--resume w-…` says.

**Owner question PQ1 — what `chord --resume w-…` does.**

- **A. Refuse it, and print each session's command** (recommended). Read the
  record as today (`readWindow`), open nothing, exit as a `ResumeError` does
  (a `ValidationError` before the screen), with:

  ```
  w-1a2b3c4d was a window of 3 sessions; chord opens one session per run now. Resume each with:
  chord claude --cwd /work/app --resume 0199f1c2-7c1e-7d43-9a3b-5f0e2c1d4b6a
  chord codex --cwd '/work/my app' --resume 019a0b11-2f3e-7c40-8e1d-3b2a1c0d9e8f
  chord claude --cwd /work/app --resume 0199f1d0-0a1b-7c2d-8e3f-4a5b6c7d8e9f
  ```

  Built by `windowGone(record)` in `windows.ts`, in the record's tab order,
  one command per line so each is selected whole. A tab whose session record
  is gone is printed all the same: `--resume <id>` hands an id chord has no
  record of to the agent (`sessionById`), which may still have it.
  **Each command carries the tab's directory** (`WindowTab.cwd`) as
  `--cwd <dir>`: for an id chord has no record of, `sessionById` returns the
  invocation's directory (`sessions.ts:304`, from `main.tsx:275`'s
  `resolve(options.cwd)`), so without it the session would open wherever
  the person typed the command. `-C, --cwd <dir:string>` is the existing
  option (`src/cli.ts:17`), which does not conflict with `--resume`; for a
  session chord does have a record of, the record's directory wins as today
  (`main.tsx:404`) and `--cwd` names the same one. `resumeCommand`
  (`sessions.ts:376`) gains an optional `cwd`, written as `--cwd` after the
  agent and before `--resume`, quoted by the same `shellQuote` as
  `--agent-command` (`sessions.ts:436`); the quit's own command does not
  pass it, so it is unchanged. The record holds no `--agent-command`, so
  none is printed. Runtime's refusal of `-r a -r b` prints its commands
  through the same `resumeCommand`, so the two refusals read alike. An
  unknown or
  unreadable `w-…` keeps today's refusals (`No window w-… among chord's
  records.`, `Window w-…'s record cannot be read.`). No guess at which
  session the person wanted; this is what `windowMessage`'s quit already
  promised, said in commands that work now.
- **B. Open the recorded front tab's session**, and say on the status line
  which others it held, with their commands. One step fewer, but chord
  chooses one of several for the person — the guessing at ambiguous input
  the owner turned down for `-r` before.
- **C. Treat `w-…` as a session id.** It goes to the agent, which refuses
  it with an error that says nothing of windows. Not offered further.

**The files on disk**, whichever is chosen: left alone. chord never writes
`windows/` again and never lists it; it reads a file only when `--resume`
names it. Deleting a person's state on upgrade is not chord's to do; a later
release may drop the reading, which would be its own decision.

**`/resume`'s list and the start picker** drop window rows (§1). A window's
sessions stay listed as sessions, as they are today beside their window row.

**The quit** prints one session's command, never a window's. A process that
was opened from a window record before the upgrade does not exist after it,
so there is no "rewrite the record it came from" case left.

## 5. chord's MCP tools (`src/server/tools.ts`)

What the agent is told and what it calls are the same tools, by role
(`tools.ts:1350-1372`); only `list_sessions` carries a tab.

- **`list_sessions`** (`tools.ts:716-750`, `891-901`) answers one row now:
  the caller's main session, its id, runtime, model and long-lived agents.
  That is still worth a call: it is how an agent finds its children's ids
  and names again after a compaction, and chord's own refusal points to it
  (`ui/app/sessions.ts:1227`, `No agent … is open in this session;
  list_sessions names them`).
  - `SessionRow.tab` and `OpenSessionView.tab` (`tools.ts:172`, `:725`) go.
    An answer without `tab` is a smaller answer; nothing reads it but the
    agent.
  - The description becomes `"The session chord runs: its id, runtime and
    model, and the long-lived agents open in it, by id and name; yours
    marked \`you\`."` (`you` stays: a long-lived child does not get the tool,
    but the field costs nothing and keeps the shape).
  - **The renderer reads old answers too.** `ui/transcript/tools/chord.ts:209-221`
    draws `` `${session.tab} ${session.runtime}` ``; a record from 0.57.0
    keeps `served` answers with `tab`, and a new answer has none, which
    would draw `undefined claude`. The line becomes the runtime alone, with
    `(you)`, and the agents counted (`1 open · claude (you), 2 agents`);
    `tab` in an old answer is ignored. A test replays a 0.57.0 `served`
    line with `tab` and one without.
  - Alternative considered: remove `list_sessions`. It would change the
    tool set every person's session is given and `/mcp` lists, and old
    records' `served` lines for it must still draw anyway; nothing is
    gained. Not recommended.
- **`Caller.key`** (`tools.ts:57`) is "the key of the tab the session is in,
  a child's parent's". Runtime fixes the main session's key for the
  process, so it becomes "the main session's key; a child's parent's,
  which is the main session's". The tools keep reading it as they do; the
  contract is **today's lifecycle preserved, not improved**: the key does
  not tell an old session's requests from its replacement's, today or
  after (see §7a).
- Doc comments that say "tab" (`tools.ts:57`, `65`, `219`, `237-253`,
  `server.ts:2-3`, `decisions.md`'s "every tab opens…") say "the main
  session". `WindowView` keeps its name: chord's screen is still "the
  window" everywhere else (`server.ts` "one per window" is one per process).
- **`askPerson`** ("Asks the person in the caller's tab", `tools.ts:252`):
  in the one session's permission box. With one session no question can
  wait behind another tab; what a child's question does stays as today.

## 6. CHD-445 — what is left after CHD-491

What CHD-491 already did on this side:

- `Conversation.title` (`conversation.ts:368-371`, `619-635`) keeps the
  agent's last `session_info_update` title, `null` takes it back, an empty
  one is ignored; `/clear` resets it (`:787`).
- **The record already keeps it**: every update is a `type: "update"` line,
  whole (`record.ts:91-97`), and a resumed session restores the title by
  folding its history (`conversation.ts:678-682`). No new record field is
  needed, and none is proposed.

How the adapters send it (from `docs/agent-capabilities.md`):

- **claude** (cl22): one title per session, from a model call
  (`generate_session_title`), else the stored custom title, as
  `session_info_update`.
- **codex** (cx22): after the first turn, a model call on a separate
  ephemeral thread, as `session_info_update`.
- Both arrive after the first prompt, so the first-prompt fallback is what
  shows first in both. Whether either sends it again on `session/load` is
  not recorded in agent-capabilities.md and was not checked here; the
  design does not depend on it — the record's lines restore it, and a
  resend only replaces it.

What is left for CHD-445 once tabs go:

1. **`/resume`'s rows and the start picker**: name a session by its title.
   On this side, `summaryOf` (`sessions.ts:96-128`) reads the header and
   the prompt lines today, picked out by the line prefix
   `{"type":"prompt"`. It would also pick the lines of
   `session_info_update`s (an `update` line containing
   `"sessionUpdate":"session_info_update"`, parsed only then), fold them as
   `#titled` does — last wins, `null` clears, blank ignored — and add
   `title?: string` to `SessionRecord` and `Resume`. Subagents' updates
   (`subagentId` set) are left out, as `#titled` leaves them. Cost: one more
   `includes` per line of every record, which `summaryOf` already splits.
   `sessionLabel` then reads `title ?? prompt` (with `name · ` before it for
   a child's record, as now) — how it is drawn, long and wrapped, is
   interface's.
2. **The agents list's main row**: the title of the one main session, from
   `Conversation.title`; interface says where and how it wraps.
3. **Children**: a long-lived agent's or task's own agent may send a title
   too; its record keeps it like the main session's. Whether it shows beside
   chord's name for the child (`tester`, a task's description) is the open
   design question CHD-445 already lists.
4. **A title that changes mid-session**: already followed by
   `Conversation.title`; on screen it is interface's.

**Recommendation: rewrite CHD-445, do not close it.** The owner's decision
(2026-10-18) names three places; the tab is gone, the agents list and
`/resume` are not built. New title: "An agent's session title
(`session_info_update`) names the session in `/resume` and the agents list".
Body: drop "in its tab", keep the rest, add "the record already keeps the
title (CHD-491); `/resume`'s summary reads it from the record's update
lines, no format change". It needs no owner answer: it narrows the owner's
list by what the owner removed.

## 7. Failure cases

- **The agent exits.** The main session's wait says `exited`; OSC 7501 is
  `error` with `<agent> exited`, as today with one tab. `chord_session` is
  unchanged (still resumable). The record is closed as today.
- **A turn is cancelled.** Unchanged: no `done` for an Esc, the record keeps
  the cancel as it does.
- **An update arrives late, after the main session was replaced** (`/clear`,
  a `/resume` pick, `/new` if the owner makes it replace): already handled
  today, and unchanged. A `/resume` pick of a session already replaces
  inside the tab through `Conversation.clear()` (`ui/app/sessions.ts:2973-2976`),
  as `/clear` does; a late update of the let-go session is dropped by
  `#current(session)` (`conversation.ts:2665`, the update's path), so it
  reaches neither the new session's record nor its title. Contract: today's
  path kept, the pick still going through `clear()`. No new test; the
  existing `/clear` and pick tests stay.
- **A late MCP call from the let-go session**: today's lifecycle, preserved
  and not improved. Its person token keeps the same key until its session
  exits and the token is revoked (`ui/app/sessions.ts:445-467`), so a call
  it makes in that window already resolves to the replacement today, after
  `/clear` or a pick. Removing tabs neither causes nor fixes this; see §7a.
- **A window record that cannot be read**: today's `Window w-…'s record
  cannot be read.`; nothing else reads `windows/`, so a bad file there costs
  nothing else.

## 7a. A finding apart from CHD-493: late MCP calls after a replace

Not part of this task; for the lead to put on the board if wanted. Between
`/clear` (or a `/resume` pick) and the let-go session's exit, its token is
still admitted and its `Caller.key` names the main session, which is now the
replacement: `open_agent`, `spawn_task`, `send_message`, `close_agent`,
`run_team` or `monitor` from the old session act on the new one's children
and permission box. A fix would need the caller to name the session, not
only the slot: e.g. a generation (or the conversation's own session id)
carried in `Caller` when the token is minted, checked by `WindowView`
against the main session's current one, and a call from a stale one refused
(`The session that called this has been replaced.`), or the token revoked
at `clear()` rather than at exit. Test: on the fake agent, a tool call from
the let-go session after `/clear`, refused, with the new session's children
untouched.

## 8. Tests on this side

- `tests/session/windows_test.ts`: keeps `parseWindow` / `readWindow` cases
  (shape, wrong id, unreadable); drops the writing, listing, row, room and
  cap cases; adds `windowGone`'s text (§4 A): tab order, a gone record still
  printed, no `--agent-command`, each command with its tab's `--cwd`, a
  directory with a space quoted, and **a tab whose session record is gone
  and whose directory is not the one chord runs in**: its command names
  that directory, which `--resume` alone would not reach.
- `tests/session/sessions_test.ts`: `resumeCommand` with `cwd` (placed
  after the agent, quoted) and without (unchanged).
- `tests/cli_test.ts` / `tests/headless_test.ts`, which write windows with
  `writeWindow` (`cli_test.ts:12`, `headless_test.ts:19`): write the 0.57.0
  JSON as a fixture string instead, since `writeWindow` goes, and check the
  refusal (with runtime).
- `tests/status_test.ts`: the fold over one session and its children; the
  cases with several tabs go, a case per state with children stays.
- `tests/session/sessions_test.ts`: `sessionsByIds` cases go;
  `resumeMessage` keeps the single case. (CHD-445's title reading is that
  task's.)
- `tests/ui/transcript/tools/Tool_test.tsx` (or wherever `chord.ts`'s rows are tested): `list_sessions` drawn from an old
  answer with `tab` and a new one without.
- `tests/server/tools_test.ts`: `list_sessions`' answer has no `tab`.
- `tests/ui/pickers/Pickers_test.tsx`, `tests/ui/app/Start_test.tsx`,
  `tests/ui/app/sessions_test.tsx`: window rows go (interface/runtime).

## 9. `docs/decisions.md` entries this overturns

- **2026-10-08 "A window record, and `--resume w-…`"** — overturned. No
  window record is written; `--resume w-…` refuses with each session's
  command (§4, PQ1). What holds: the record's shape and the `w-` prefix, as
  read; an unreadable or unknown one's refusals.
- **2026-10-08 "Windows in `/resume`, and `--resume` with no id"** — the
  window row, "Enter on a window opens beside, or nothing", the cap note and
  windows in the start picker are overturned. What holds: `--resume`'s
  optional value (`[id:string]`) and its accepted limit, the start picker
  drawn on the renderer that then draws the window, and the refusals before
  the screen (`No earlier <agent> session to resume.`, without "or
  window").
- **2026-10-08 "chord's MCP server: …, a token per session, tools by role"**
  — "every tab opens … gets a fresh token, which names the tab" becomes
  "every session"; `list_sessions` gives no tab number. The rest holds.
- **2026-10-21 "CHD-492: chord tells the terminal the session id to resume,
  in a user variable (owner, Q124)"** — the clause "until CHD-493, the
  front tab's" goes.
- With runtime: **2026-10-08 "`-r <id> -r <id> …`: a tab each, each in its
  own place"** — `sessionsByIds` and its refusals go; "One id is as it was"
  holds.

## 10. Owner questions

- **PQ1 — `chord --resume w-…`** (§4). Options A (refuse, print each
  session's command), B (open the front tab's session, list the rest), C
  (pass it to the agent). **Recommended: A.** The design above follows A;
  B would change only §4 and its test.

## 11. Open questions for the team (not the owner's)

- **Runtime**: `-r a -r b`'s refusal prints its commands through
  `resumeCommand` with `cwd`, as `windowGone` does (§4).
- **Interface**: the `list_sessions` row's wording (§5); where the agents
  list shows the main session's title (CHD-445, §6).
