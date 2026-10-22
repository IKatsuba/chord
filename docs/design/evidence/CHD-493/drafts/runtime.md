# CHD-493 — runtime draft

Runtime architect's answers for the session layer, the CLI, failure modes,
the order of units and the tests. Read against origin/main `3f6f6656`
(v0.57.0). Line numbers are that tree's.

The one-sentence version: the window keeps exactly one main `Conversation`
for its whole life, under a key that never changes, with its long-lived
children beside it as today; every path that opened, switched or closed a
second one goes, and `tabs.ts`'s per-tab fold collapses to a fold over
`main` and its children. `/clear` and `/resume` already replace the main
session *inside* the same `Conversation` (`conversation.ts:718`
`clear()`), so no path needs to swap the main conversation out; this is
what makes the collapse safe.

Revised once after the critic's round (findings 1, 2, 3, 5, 6, 8): U1's
test migration completed, U2's inventory made from a full grep (§8), the
`-r a -r b` refusal names each record's agent and directory, the glyphs
move out of the strip, and a failure row for late MCP calls.

Design dependencies, marked where they apply: **[W]** the `--resume w-…`
answer, now protocol's (§4); **[N]** the lead's owner question on `/new`
(recommended: `/new` an alias of `/clear`, `/new <agent>` refused); **[R3]**
one session in two processes (§10).

## 1. What goes (session layer and CLI)

| Where | What goes | What stays |
|---|---|---|
| `src/session/tabs.ts` | `MAX_TABS` (:13), `Tab`, `Tabs`, `noTabs`, `frontTab`, `tabOf`, `position`, `tabName`, `full`, `openTab`, `show`, `closeTab`, `step`/`nextTab`/`previousTab`/`goTo`, `listStart`, `waitsOf`, `mergedWait`, `shownWait`, `askingChild`, `waitingChild` (only the strip, the sessions picker, the tab-behind notice and `/status`'s `Sessions:` read the last four) | the wait fold (`TabWait`, `Failure`, `FAILURES`, `repliedSince`, `failedSince`, `failureOf`, `idle`, `waitAfter`), children (`ChildInfo`, `Child`, `MAX_CHILDREN`, `openChild`, `closeChild`, `ownChildren`, `isLead`, `membersOf`, `namedChild`, `childName`, `runName`, `childEnded`), picking (`pick`, `movePick`, `keyed`, `shownKey`, `pickedChild`, `agentOf`), `notifiedName`, the attention order (`attentionOrder`, `attend`, `Rank`, `attended`), `hear` — all re-homed, §2 |
| `src/session/open_sessions.ts` | `open(agent)` for a second tab, `close(key)` of a tab, `next`, `previous`, `goTo`, the cap check | one main start, children, `pick`, `movePick`, `keyed`, `attend`, `closeChild`, `closeAll` with its earlier-close bookkeeping (`#closing`, :71), `closingHeard` |
| `src/session/sessions.ts` | `ResumedTab` (:314), `sessionsByIds` (:327), the `MAX_TABS` import, the plural branch of `resumeMessage` (:398) | `readRecords`, `summaryOf`, `latestSession` (`--continue`), `earlierSessions`, `sessionLabel`, `openSessionLabel`, `sessionsIn`, `elsewhereRefusal`, `sessionById`, `resumeCommand`, `ResumeError` |
| `src/session/windows.ts` | everything that writes or lists windows: `newWindowId`, `windowText`, `writeWindow`, `windowOnQuit`, `windowMessage`, `mixedRefusal`, `windowTabs`, `WindowTabs`, `readWindows`, `EarlierWindow`, `earlierWindows`, `ResumeEntry`, `resumeEntries`, `windowIn`, `entriesIn`, `AGENTS_WIDTH`, `windowAgents`, `windowSummary`, `windowDirectory`, `windowRoom`, `capNote`, `windowElsewhereRefusal` | **[W]** what protocol keeps for the `w-…` answer (its draft); runtime only needs `isWindowId` and a pure answer it can throw as `ResumeError` before the terminal is taken |
| `src/ui/app/strip.ts`, `Strip.tsx` | the strip's geometry (`StripTab`, `StripPiece`, `StripView`, `stripLayout`) | `TabGlyph`, `GLYPHS`, `TabGlyphs`, `tabGlyphs`, `glyphsOf` move to `src/ui/agents/glyphs.ts` (read by the agents list, background, teams, status and pickers); names are interface's |
| `src/session/window_monitors.ts` | `tabOf` lookup by the caller's tab key; "another tab has its own" | the caller's own monitors, the eight shared by main and its children |
| `src/cli.ts` | `-r` help: "or a window (w-…)", "repeated, a tab each"; example "Pick an earlier session or window" | `-r, --resume [id:string]` with `collect: true` (kept so chord, not Cliffy, words the refusal of several, §4), `-c`, the `conflicts` |
| `src/main.tsx` | `fromWindow`, `resumed[]`/`resumes`, the loop reading every resumed directory (:445–452), the `unstartable` check over several (:535–546), the `refuseMissing` list for several, `resumedFront`/`resumedNote` props, `windowOnQuit`/`writeWindow`/`windowMessage` on quit (:656–685), the start picker's `windows` | one `readPlace(cwd)`, one `refuseMissing`, `-r` with no id → start picker of sessions, `--continue`, `resumeMessage` of the one session |
| `src/ui/app/sessions.ts` (runtime parts of `useSessions`) | `places` map and `placeOf(key)`/`frontPlace()` (:314–318) → the one `place`; `resuming` map → one ref; `OpeningTab`, `resumes`/`resumedFront`/`resumedNote` (:229–253, :1733–1760); `openBeside` (:2510); `busyTabs` (:2639); `closeFront` (:2694); `tabRows`, `counted`, `listFrom`, `pickTab`, `pickWindow` (:3000–3110); the tab half of the waits notice (:3199–3220) and `closeArmedLine`/`quitArmedLine` inputs; `onQuit(tabs, front)` | `heard`, `retiredHeard`, `keepSpend`, children, `/clear` (`clearFront`), `/resume` in place (`pickSession`, minus "go to tab N"), `attend`, `quit` |
| `src/status.ts` | "every agent of every tab" fold over `tabs.tabs` (:154) | the same fold over main + children (protocol owns the record's shape) |

`src/acp/`, `src/platform/`, `src/session/conversation.ts`, `record.ts`,
`tasks.ts`, `monitors.ts` and `renderer.tsx`'s signal path do not change:
none of them knows a tab.

## 2. Module layout after the change

Names are proposals; ship may rename, but the split is the point: the
per-agent wait fold has nothing to do with tabs and is read by four UI
modules, so it gets its own small module first, and the state over it
becomes one main and its children.

### `src/session/waits.ts` (new, moved out of `tabs.ts:22–116`, `:944–1059`)

Pure. `AgentWait` (today's `TabWait`; the old name kept as a deprecated
alias for one unit is *not* proposed — every importer is touched in U3
anyway), `Asking`, `Failure`, `FAILURES`, `repliedSince`, `failedSince`,
`failureOf`, `idle`, and `waitAfter` exported as
`heardWait(before, event, now, { front })`. Importers:
`ui/agents/agents.ts`, `ui/pickers/picker.ts`, `ui/status/status.ts`,
`src/status.ts`. Tests: `tests/session/waits_test.ts`.

### `src/session/window_agents.ts` (replaces `tabs.ts`)

Pure state of the one window:

```ts
interface WindowAgents<C> {
  /** The person's session; none before its start. Its key never changes. */
  readonly main: { key; agent; conversation: C; wait: AgentWait } | undefined;
  readonly children: readonly Child<C>[];   // as Tab.children
  readonly picked: number;                   // main's key or a child's
  readonly closed: readonly ChildInfo[];
  readonly opened: number;                   // colours
  readonly nextKey: number;                  // children's keys; main takes 1
  readonly attended?: { key; rank: Rank };
}
```

Functions: `noAgents()`, `openMain(agents, agent, conversation)` (once;
a second call is a programming error and returns the state unchanged),
`agentOf`, `shownKey` (= `picked`), `pickedChild`, `isLead`, `membersOf`,
`namedChild`, `childName`, `runName`, `childEnded`, `openChild` (no tab
key), `closeChild`, `ownChildren`, `keyed`, `pick`, `movePick`,
`notifiedName` (main by its agent alone, as one tab is named today by
`tabName` at `tabs.ts:685`; a child as now), `attentionOrder`, `attend`,
`hear`. `Rank.key` keeps breaking ties: main's key is the lowest, children
follow in opening order, so "further left" becomes "main, then the list's
order", which is what the list under the prompt draws.

Kept keys, not positions: `all.sessions` in the window state is keyed by
these numbers, and a late event from a closed child must still miss
(`closingHeard`). Nothing about that changes.

A fixed main key is today's behaviour, not a new one: `/clear`
(`clearFront`, `ui/app/sessions.ts:2330`) and a `/resume` pick
(`pickSession`, :2959–2982) already keep the tab's key and call
`Conversation.clear()` on it; the person's MCP token is admitted per
session under that key (`server.admit({ role: 'person', key, … })`, :438)
and revoked only on that session's `exited` (:462). So a window with one
tab already runs every main session it ever has under one key; the
collapse keeps exactly that (see F17).

### `src/session/open_agents.ts` (replaces `open_sessions.ts`)

`OpenAgents<C extends Driven>`: `start(agent)` makes and starts main's
conversation once; `main`, `front` (the picked one's conversation),
`conversationOf(key)`, `openChild(info, make)`, `closeChild(key)`,
`pick`, `movePick`, `keyed`, `attend`, `closeAll()`. `closeAll` closes main
and every child at once and waits for those and every earlier close, the
same `#closing` bookkeeping and `AggregateError` as today (:233–252).
`Driven` stays.

### `src/session/window_monitors.ts` (kept, on `WindowAgents`)

`monitorsOwner(agents, caller)`: main's conversation for a caller with
main's key and no `agent`, a child's by id, none for a task or a key that
is not main's (a stale caller from a session that has since closed gets
`This session has closed`, as today). The eight are shared by main and its
children, as a tab's were. `MonitorCaller.key` stays so the server's caller
shape need not move in the same unit (protocol may drop it later).

### `src/session/sessions.ts` (kept, shrunk)

`ResumableTab` → `Resumable { agent; sessionId }` (the `cwd` was only for
the window record). `resumeMessage(session: Resumable | undefined,
override)` returns `Resume this session with:\n<command>` or nothing; the
quit line stays without `--cwd`, as today: chord's own record gives the
directory, and the session was just used here.

`resumeCommand(agent, sessionId, agentCommand?)` gains an optional `cwd`
(an options object in place of the third positional is the cleaner
signature; ship's call): `chord <agent> [--agent-command …] [--cwd <dir>]
--resume <id>`, the directory absolute and through the same `shellQuote`
(`sessions.ts:425`) as `--agent-command`. `--cwd` exists (`cli.ts`, `-C,
--cwd <dir:string>`); with a record, `main.tsx:404` takes the record's
directory over it (`resume?.cwd ?? options.cwd`), so the flag is harmless
there and only decides the directory once the record is gone, where
`sessionById` hands the agent the id with `cwd` from the command line
(:302). Both refusals of §4 use it, so the commands they print stay right
if a record is deleted later.

### `src/ui/app/sessions.ts` (`useSessions`, runtime parts)

- One `place: Place`. `Place` and `SessionStart` stay: children
  (`open_agent`, `run_team`, `spawn_task`) and the `/model` runtimes probe
  (`runtimesOf`, :1587) still start agents by `startupOf`. `runtimesAt`
  becomes one lazily made `Runtimes`.
- One `resuming: Resume | undefined` ref: set from `--resume`/`--continue`
  at start and by `/resume`'s pick, read when main's conversation opens its
  next session.
- `onQuit(session: Resumable | undefined)`: main's, if a prompt or message
  went to it; children are never printed (as today, where only tabs were).
- `openIds()` (today's `openTabs`, :2829): session id → key over main and
  children, so `/resume` on a session open as a child picks that child
  rather than loading it twice; main's own is already left out of the list
  (`except`).

## 3. Concurrency and failure scenarios

Each is what the person sees and what the processes do. "As today" means
as a window with one tab behaves on `3f6f6656`; the test that pins it is
named where one exists or is needed.

| # | Scenario | Expected outcome |
|---|---|---|
| F1 | Main's agent never comes up (spawn fails, `initialize` refused, command refused by CHD-466) | Error line in the transcript; wait `unseen: failed / start` is not set (main is shown); OSC 7501 `error`. `/clear` starts a fresh session on a new process (`clear()` → `start()`); ctrl+d quits at once, printing nothing (no prompt went). As today. |
| F2 | Main's agent exits mid-session | `disconnected` → `exited` on main's wait, error line; children stay up (their own processes) and a child's `send_message` to main is refused as today. `/clear` starts a fresh main session and closes the children (`clearFront`, :2330). Quit prints main's resume command. As today. |
| F3 | Main hangs on close (quit, `/clear`'s old session) | Bounded as "Quitting is bounded, whatever the agent answers" (2026-10-06): stdin end, SIGTERM to its process group, SIGKILL (`acp/process.ts:198`); `closeAll` waits for main, children and every earlier close; the window exits after. Unchanged. |
| F4 | Quit while main is still starting (CHD-489) | `closeAll` aborts the start (`#stops`), the agent is reaped; `withWindow` fails a test that leaves one. `AppStart_test.tsx` keeps this with "tab" → "main". |
| F5 | Signal or crash (SIGINT/TERM/HUP…, uncaught error) | `closeOnForcedExit(() => agents.closeAll())` (`sessions.ts:1763`) closes main and children within their bounds while the terminal is given back (`renderer.tsx` `leave`); chord dies by the signal. **No resume line on a signal**, as today; CHD-492's user variable already holds main's id. Unchanged. |
| F6 | A child hangs, floods or exits | Unchanged: children are not touched. `MAX_CHILDREN` (8) and the monitors' eight stay per window. |
| F7 | A child asks for a permission while main is shown | The status line's notice of agents behind names the child (the `others` half of `waitsNotice`, :3170–3195, stays); the notification names it by `notifiedName`; `ctrl+x a` (`session:attention`, kept for children — interface) goes to it. The tab half of the notice goes. |
| F8 | Late events from a closed child or a session `/clear` let go | `closingHeard` / `retired_*` keep what it spent (CHD-373); unchanged. `sessions_test.tsx` keeps these with main instead of "tab". |
| F9 | `/resume` picks a session open as one of this window's children | Picks that child; no second conversation on its record. Today's "go to tab N, pick the child" minus the tab. |
| F10 | `/resume` picks a session in another directory | Refused with its command (`elsewhereRefusal`); unchanged. The window has one directory for its life: main's. |
| F11 | `/resume` or `/clear` while a turn runs / a child is picked | `resumeRefusal` and `/clear clears main; pick main first`; unchanged. |
| F12 | ctrl+d or `/exit` | Quits at once: one session never armed (`busyTabs` returned `[]` under two tabs, :2640). ctrl+c keeps its own two-press arming with no session count. Whether a busy *child* should arm ctrl+d is not this task's (open question O2). |
| F13 | `chord -r a -r b` | Refused before anything starts, chord's own words, a command per id with its record's agent and directory (§4). Nothing is spawned, no terminal is taken. |
| F14 | `chord --resume w-1a2b3c4d` with an old record on disk | **[W]** Answered before the terminal is taken, as protocol words it, each tab with its agent and directory. Window files are never written again; runtime only places the check before `terminalSetup`. |
| F15 | Two chord processes on one session (two panes running `--continue` in one directory, `--resume X` twice, `/resume` of a session another process has open) | **[R3]** Both conversations write `records/<id>.jsonl`; each record line is appended whole, so the file stays readable, but the turns interleave and the agent sees two clients. This exists today across processes; inside one window the tab guard (`openTabs`, :2829) prevented it. With tabs gone, side-by-side sessions are always separate processes, so the window guard no longer covers the common case. No lock is designed here (the brief's non-goal). |
| F16 | A keybindings file binding a removed `session:` action | Interface's; runtime only notes that `loadKeybindings` problems are said before the window (main.tsx `report(keys.problems)`), so the person sees it once. |
| F17 | A late MCP call from the session `/clear` or a `/resume` pick let go (its agent still exiting, its person token not yet revoked) | **Today's behaviour is kept, not improved.** The old token still names main's key until the old session's `exited` revokes it (`ui/app/sessions.ts:462`), so a call that lands in that window is served as main's: `send_message` reaches main's current session, `monitor` counts against main's eight, as with one tab on `3f6f6656`. Children of the old session are closed by `clearFront`/`pickSession` first, so they cannot be reached. Tightening this (a token per session generation) is a separate task if wanted; nothing here makes it worse. |

## 4. The CLI

- **`--resume` with one id, `--continue`, `-r` with no id:** as today.
  The start picker lists sessions only (interface for `Start.tsx`).
- **Several ids (`-r a -r b`)**: Cliffy's `collect` stays, so `main.tsx`
  sees every id and refuses with its own sentences, before any terminal or
  agent. No argv rewriting, no guessing which to open. Dropping `collect`
  would make Cliffy refuse with its generic duplicate-option error. (Runtime's
  call, not the owner's: the owner's list removes several ids; this only
  words the refusal.) A pure `severalRefusal(records, ids, { agent, cwd,
  agentCommand })` in `sessions.ts` builds it, one line per id in the order
  given:
  - an id chord has a record of: the record's agent and directory
    (`latest` of the records with that id, as `sessionsByIds` read them),
    `--agent-command` only when that agent is the one the command line
    overrides (Q56's rule, as `resumeMessage` applies it);
  - an id chord has no record of: the agent and directory of this
    invocation, and the line says so, so nothing is presented as known
    that is not: `chord codex --cwd /src/app --resume 0199… (no record;
    the agent and directory are this command's)`.
  - a named `[agent]` that differs from a record's agent is not resolved
    here: the line carries the record's agent, and running it is checked
    as one `--resume` always is.

  ```
  --resume opens one session; it was given 3. Open each in a chord of its own:
  chord claude --cwd /src/app --resume 4f1c…
  chord codex --cwd /src/lib --resume 9a2e…
  chord claude --cwd /src/app --resume 0199… (no record; the agent and directory are this command's)
  ```
  The same id twice is still said once per time given; it is a refusal,
  not a plan.
- **`-r` with no id among ids** (`-r -r a`): the existing refusal (:299).
- **`--resume w-…`** **[W]**: protocol's text and function; each tab's
  line carries its `cwd` through `resumeCommand`'s `cwd` (§2), the form
  above. Runtime's part: the check runs right after argv, before
  `terminalSetup`, so it prints on a plain terminal and exits as the other
  `ValidationError`s do. If protocol's form differs from the one above, the
  lead settles one form for both refusals.
- **Quit**: one line, `Resume this session with:` and main's command, or
  nothing when no prompt or message went to main. No window record.
  `--agent-command` goes with it when the person typed one (Q56, as now).
- **Signals**: unchanged (F5).

## 5. Per-agent startup, place and directory

- `startupOf` stays, one per window, from the session's directory: the
  children's runtimes and the `/model` probe use it. Its "each tab starts on
  its own agent's values" use for `/new <agent>` goes with `/new <agent>` **[N]**.
- One place for the window's life: the directory of the session it opened
  (`--resume`'s record's, else `--cwd`). `main.tsx` reads one directory's
  settings and `.mcp.json`. "The window's own settings stay those of the
  first tab's directory" becomes "of the session's directory", which was
  already the only case with one tab.
- Bash-mode commands stay keyed by session key in `App.tsx` (interface's
  slice); `stopCommand(front)` on a tab close goes with the close.

## 6. Waits and attention without tabs

- Each agent's wait folds exactly as now (`heardWait`), per main and per
  child. `unseen` is set only while that agent is not the one shown,
  `ended` on any turn end; both as today.
- The attention order is over main and its children only; `attend`'s walk,
  `attended` and the Q46 hand-pick rule are unchanged. Every attention test
  that today uses two tabs is rewritten with main and children (§8).
- No per-tab fold remains: `mergedWait`/`shownWait`/`askingChild`/
  `waitingChild` go with their only readers.
- Notifications name main by its agent alone (what `tabName` gave a single
  tab) and a child by `notifiedName`; "behind" now means "a child not
  shown, or main while a child is shown". OSC 7501's fold is protocol's.

## 7. Order of units for the ship team

Four units, in this order, each a branch from origin/main after the one
before has merged, each leaving `bun dev check` green and carrying the docs
it makes stale (README, `docs/guide.md`, `docs/FEATURES.md`,
`docs/agent-capabilities.md`, screenshots) in the same PR. Each unit that
adds, removes or renames a test file ends with `bun dev test
--update-timings` and commits `tests/timings.json` (an unrecorded or
missing file fails the bare run's comparison). The reason for the order:
first remove every way a second tab can come into being, so that the
collapse in U3 is a refactor with nothing visible to lose. U1 and U2 both
change `useSessions` and the harness, so they are sequential.

### U1 — windows and several ids go (runtime; protocol for `w-…`, interface for rows)

The ways a window opens several tabs at once.

- `cli.ts` help and examples; `main.tsx`: one id, several refused with
  `severalRefusal` (§4), `w-…` answered **[W]**, one place read, no
  `resumes`, no window written on quit. The quit message keeps the plural
  `Resume these sessions with:` for this unit only (tabs from `ctrl+x c`
  still exist until U2; it is today's fallback when a window record fails
  to write, so nothing new).
- `sessions.ts`: `sessionsByIds`, `ResumedTab` go; `severalRefusal` and
  `resumeCommand`'s `cwd` come.
- `windows.ts`: shrinks to what protocol keeps for `w-…`.
- `useSessions` and the harness: `resumes`/`resumedFront`/`resumedNote`/
  `OpeningTab` go; `resume` + `place` (both exist already) carry a single
  resumed session. `pickWindow` (a window picked in `/resume` opened tabs
  beside) goes; `/resume` and the start picker list sessions only.
- Tests, every one that names the removed API or behaviour:

| File | Case | Outcome |
|---|---|---|
| `tests/headless_test.ts` | import of `writeWindow` (:19); `seedRecords` writing a window (:668) | Seed the window as a fixture string: the 0.57.0 JSON as `windowText` wrote it (`{"id":"w-0b5c5f9e","at":3,"tabs":[…],"front":0}` pretty-printed, newline-terminated) written with `writeFile` to `windows/w-0b5c5f9e.json`; no import from `windows.ts`. |
| `tests/headless_test.ts` | :692 "a restore asks PATH for its tabs' agents" | Rewritten in three: (a) one `-r <id>` whose record's agent is `cursor` still reaches PATH validation and names cursor, not the default (the guarantee kept); (b) `-r a -r b` gets `severalRefusal`'s text, exit 1, and **nothing** asks PATH; (c) `-r w-0b5c5f9e` gets protocol's answer, exit 1, nothing asks PATH. Add (d): records of two agents (`cursor` and `claude`) and one unknown id: each line names its record's agent and directory, the unknown one this command's with its note. |
| `tests/cli_test.ts` | :75 several ids open a tab each | Rewritten to `severalRefusal` from argv, the mixed-agent case among them. |
| `tests/cli_test.ts` | :188 ten ids, an unknown id among several, the same id twice | Rewritten: all refused by `severalRefusal`; ten is no longer special. |
| `tests/cli_test.ts` | :316 CHD-466 U2, `window restore` variant | Rewritten to the `w-…` answer **[W]**; the `session resume` variant stays. |
| `tests/cli_test.ts` | :103, :90, :114, :133, :160, :230, :265 | Stay. |
| `tests/session/windows_test.ts` | all | Rewritten to what protocol keeps (its draft). |
| `tests/session/sessions_test.ts` | :220, :255 | Deleted; replaced by `severalRefusal` cases (known, unknown, mixed agents, `--agent-command` only for the overridden agent, a directory that needs quoting). `resumeCommand` with `cwd`: one case next to :311. |
| `tests/ui/app/AppResume_test.tsx` | :105 several resumed open as tabs; :332 a window record's tabs | Deleted. |
| `tests/ui/app/AppResume_test.tsx` | :224 CHD-466 model probe where the asking session works | Rewritten as two windows each resuming **one** session with `resume` + `place` (one place whose `startupOf` refuses codex, one that allows it), each driving `/model codexmodels`: never started where refused, read where not. Keeps the guarantee that the resumed directory's startup decides the probe; drops the tab switch. |
| `tests/ui/app/terminal_test.ts` | :207 (passes `resumes: [one]` at :243) | Rewritten to `resume` + `place`; expectations unchanged. |
| `tests/ui/app/render.tsx` | `resumes` option (:147, :211, :253) | Replaced by `resume` + `place`. |
| `tests/ui/app/sessions_test.tsx` | `resumes: undefined` (:115, :736, :920) | The field goes. |
| `tests/ui/app/sessions_test.tsx` | :286 restoring into an unused tab (window reuse) | Deleted. |
| `tests/ui/pickers/Pickers_test.tsx` | :920 Enter on a saved window adds tabs | Deleted. |
| `tests/ui/pickers/picker_test.ts`, `state_test.ts`, `tests/ui/app/Start_test.tsx` | window rows | Interface's; deleted or rewritten to sessions only. |

### U2 — tab keys, the strip and the sessions picker go; `/new` per **[N]** (interface-led; runtime parts listed)

The ways a second tab opens or is switched to. **Conditional on [N]**: the
`/new <agent>` rows below assume the lead's recommendation (`/new` an
alias of `/clear`, `/new <agent>` refused). Under "keep `/new <agent>` as a
new main of another agent" those rows stay as they are and U3 must keep a
main-replacement path (§2 then needs `openMain` to close and replace); the
rest of the unit is the same either way, because main is never replaced by
any *other* path.

- Runtime parts: `openBeside` and the tenth-session refusal; `closeFront`
  and the busy-close arming; `busyTabs` and ctrl+d's arming; `tabRows`,
  `counted` (`/status`'s `Sessions:`), `listFrom`, `pickTab`; `/resume`'s
  "open in N" → F9; the tab half of the waits notice; `OpenSessions`'s
  `next`/`previous`/`goTo`/`close` and the cap (`open` is then called once).
- The glyphs move to `src/ui/agents/glyphs.ts` with their cases from
  `tests/ui/app/strip_test.ts:135` (all of "a tab shows its state…",
  CHD-471) into `tests/ui/agents/glyphs_test.ts`; only the strip's geometry
  and its tests go.
- Quit message becomes singular here: with U2 in, one tab is all there is.
- A second runtime in tests: tests that used `/new <agent>` only to have an
  agent of another runtime in the window get it as a long-lived child.
  That needs one fake-agent addition: the `agents` family opens its
  children on `fake` only (`scenarios/agents.ts:36`, :44); add a scenario
  `agentother` that opens one child on the runtime named by the fake's
  `--child-runtime <name>` argument (as `--hang` is an argument), default
  `codex`. The harness's `startupOf` already maps any runtime name to a
  command, so a `codex` child is the fake under that name.
- Tests, from the full grep in §8. "main + child" means the same guarantee
  between main and a long-lived child picked with the agents list
  (`ctrl+x ↓` / `ctrl+x a`, kept), "child on another runtime" the
  `agentother` scenario.

| File | Case | Outcome |
|---|---|---|
| `App_test.tsx` | :38 CHD-382 "a blocked tab behind wins over a working front tab" | Rewritten main + child: a blocked child wins over a working main. |
| `App_test.tsx` | :685 strip vs header | Keep the one-session half; the two-session half deleted. |
| `App_test.tsx` | :709 ctrl+x c / leader switching | Deleted. |
| `App_test.tsx` | :747, :798, :842 `/new <agent>` on its settings' model/effort, names from settings | **[N]** Deleted; the starting values per runtime stay covered for children (`AgentsTasks_test.tsx` :319, `tests/settings_test.ts` `startupOf`). A new case: `/new` clears as `/clear` does, `/new codex` is refused with the lead's wording. |
| `App_test.tsx` | :893 permission behind is a glyph and notice, ctrl+x a goes to it | Rewritten main + child (child asks, main shown). |
| `App_test.tsx` | :938 a digit after the leader goes to a tab | Deleted (no digit actions). |
| `App_test.tsx` | :967 ctrl+x w | Deleted. |
| `App_test.tsx` | :1006 `/resume` marks a session open in another tab | Deleted; F9 is `AgentsClose_test.tsx` :274 rewritten (below). |
| `App_test.tsx` | :1039 `/clear` in tab 2 | Deleted; `/clear` is :561. |
| `App_test.tsx` | :1061, :1115, :1168 ctrl+x k | Deleted; `stopCommand` on a `/resume` pick and on quit keeps it, and gets one main-only case if no test covers it. |
| `App_test.tsx` | :1205 ctrl+d arms with a session working | Rewritten: ctrl+d quits at once, prints main's one command, no agent left. |
| `App_test.tsx` | :1249 a form half filled in a session behind | Rewritten main + child: a form in the child, half filled, pick main, pick the child back: values and focus as left. |
| `AppResume_test.tsx` | :510, :558 (sessions picker click; ctrl+x w) | :510 deleted; :558's draft-and-cursor guarantee rewritten on the agents list (pick a child after a click). |
| `AppSpend_test.tsx` | :207 closed child, clear history and closed tab in `/cost` | Rewritten: the closed-tab part deleted; closed child and `/clear` history stay. |
| `AppSpend_test.tsx` | :519 an estimate beside a silent agent (`/new silent`) | Rewritten: `silent` as a child on another runtime. |
| `AppSpend_test.tsx` | :652, :757 prices across runtimes (`/new dirac`) | Rewritten: the second runtime as a child; the per-model prices and model-switch estimates are the same code. |
| `AppStart_test.tsx` | :37 "a tab's agent still starting" (`/new codex` wedged) | Rewritten: the window's own main is the wedged one (`startupOf` gives `wedged(tag)` for main's agent; do not `ready()`); still gone once the window closes. |
| `AppStart_test.tsx` | :74, :261, :295 (`/new codex` as the second start) | Rewritten: the start is a child on another runtime (`agentother`), the given-up/rejected/late-delivered start the child's. |
| `AppStart_test.tsx` | :174 `quit`/`close` × `child`/`tab` | The `close`×`tab` variant (ctrl+x k, :224) deleted; `quit`×`tab` becomes `quit`×main; the `child` variants stay. |
| `AgentsTasks_test.tsx` | :319 a refusal beats a warm probe (`/new codex`, :389) | Rewritten: the refused runtime asked as a child (`open_agent`) instead of `/new`. |
| `AgentsSpend_test.tsx` | :86 child, main and another tab keep their own report (`/new other`, ctrl+x 1) | Rewritten: the "other tab" becomes a second child on another runtime. |
| `AgentsSpend_test.tsx` | :281 a working child's unread message (ctrl+x c/1/2/w) | Rewritten without tabs: the child's unread message seen in the agents list, cleared by picking that child only. |
| `Agents_test.tsx` | :243 a child's exit in a tab behind | Rewritten: a child's exit while main is shown is named for the child. |
| `Agents_test.tsx` | :563 a click while the sessions picker is open | Deleted. |
| `AgentsClose_test.tsx` | :149 closing a parent closes its children (ctrl+x k) | Rewritten: `/clear` on main closes its children, asking nothing (today's `/clear` asks nothing); the "asking first while one waits" half moves to quit (ctrl+c's arming) only if that is kept — else deleted. |
| `AgentsClose_test.tsx` | :274 `/resume` marks a live child open in its tab | Rewritten to F9: `/resume` on a live child's session picks the child, no second agent. |
| `AgentsClose_test.tsx` | :326 CHD-264 (ctrl+x c) | Rewritten main + child; the tab half deleted. |
| `AgentsClose_test.tsx` | :342 picker owners (ctrl+x w, 1, 2) | The sessions-picker owner deleted; the agents-list owner and notices kept. |
| `Monitors_test.tsx` | :60 a resumed session draws its monitors again (ctrl+x c, 1, k to get a fresh tab) | Rewritten: resume by `resume` + `place` into the window's own main; no tab needed. |
| `TeamsSpend_test.tsx` | :170 `/new codex` refused with the cause | **[N]** Rewritten to the new `/new <agent>` refusal, or deleted if interface covers it. |
| `Tasks_test.tsx` | :501 two sessions with reused call ids keep their own served results | Rewritten main + child (both on fake, reusing call ids). |
| `SelectionEdges_test.tsx` | :75 a late copy from a cleared tab | Rewritten: `/clear` on main, the late copy leaves the next session untouched (the tab switch was only to get away). |
| `Background_test.tsx` | :93 ended monitors absent in their tab and another tab | Rewritten main + child. |
| `Background_test.tsx` | :355 the view is modal: session keys do nothing | Stays; its key list drops the removed actions (ctrl+x stays for `ctrl+x a`). |
| `Form_test.tsx` | :290 two sessions keep separate form values and open lists | Rewritten main + child. |
| `Form_test.tsx` | :331 a form cancels independently of a hung turn in another session | Rewritten: hung turn in main, form in the child. |
| `Questions_test.tsx` | :368 switching restores the question, secret draft and countdown | Rewritten main + child. |
| `Questions_test.tsx` | :415 a short request withdrawn behind never reopens | Rewritten main + child. |
| `Permission_test.tsx` | :696 two sessions answer their own overflowing requests | Rewritten main + child. |
| `PermissionBetween_test.tsx` | :165 attention answers from `${focus}` (ctrl+x w) | The `sessions picker` focus variant deleted; the others stay. |
| `PromptKeys_test.tsx` | :302 a cancelled turn and another session keep independent drafts | Rewritten main + child. |
| `PromptImage_test.tsx` | :473, :509, :548 a read while another tab comes forward | Rewritten: the read finishes after the person picks a child; it lands in the draft it began in (`stateOf(key)`, the same code). |
| `PromptImage_test.tsx` | :676, :854 ctrl+v while an agent starts; a `${child ? 'child' : 'tab'}` that fails or starts | The `tab` variants become a child on another runtime; the `child` variants stay. |
| `TranscriptBack_test.tsx` | :98 two sessions scrolled back keep their own top entry | Rewritten main + child (held scroll per key). |
| `tests/ui/app/tasks_test.ts` | :50 (`closeArmedLine` at :61) | The `closeArmedLine` assertion deleted; `busyOf`'s order stays. |
| `tests/ui/app/closing_test.ts` | :86, :102 armed close and quit lines | Deleted with the lines; :183's tab wording becomes main's. |
| `tests/ui/app/strip_test.ts`, `Strip_test.tsx` | all but the glyph cases | Deleted; glyphs moved (above). |
| `tests/ui/app/keys_test.ts` :121, `tests/ui/prompt/commands_test.ts` :210–:345, `tests/ui/prompt/state_test.ts` :88, `tests/ui/shortcuts/*`, `tests/ui/status/status_test.ts`, `tests/ui/pickers/*` | `/new`'s list, session actions, leader line, tab notices | Interface's; `/new`'s agent list per **[N]**. |
| `tests/session/open_sessions_test.ts` | :242 past nine | Deleted. |
| `tests/ui/app/sessions_test.tsx` | :180 two busy tabs close concurrently | Rewritten: busy main (via `/clear`) and busy child close concurrently, each final cost once. |
| `tests/ui/app/sessions_test.tsx` | :619 a task ends into its retired record after the replacement tab closes | Rewritten: after quit (closeAll) instead of a tab close. |

### U3 — the state collapses (runtime)

A refactor: nothing on screen changes.

- `tabs.ts` → `waits.ts` + `window_agents.ts`; `open_sessions.ts` →
  `open_agents.ts`; `window_monitors.ts`, `src/status.ts`,
  `ui/agents/agents.ts`, `ui/pickers/picker.ts`, `ui/status/status.ts`,
  `ui/transcript/spend.ts` (`Tab`, `tabName` in `KeptPlace`; interface
  words), `ui/app/App.tsx` and `useSessions` onto them; `Resumable` and the
  one-session `resumeMessage`.
- Tests: `tests/session/tabs_test.ts` split into
  `tests/session/waits_test.ts` (:185–:443, :1029–:1135, :1138–:1470,
  :1576–:1633) and `tests/session/window_agents_test.ts` (:443–:562
  rewritten over main + children, :620–:959, :976–:1027, :1490–:1558);
  deleted: :111–:179, :575, :787, :1655, :1671, and :516/:533 (a tab to
  the left closing; the child-close case is covered at :720).
  `tests/session/open_sessions_test.ts` → `tests/session/open_agents_test.ts`
  (:35 becomes main + a child on the fake agent, both running, a wait in one
  leaving the other; :131–:217 on children; :264, :315 kept).
  `tests/session/window_monitors_test.ts` :102 rewritten (main and children
  share the eight). `tests/status_test.ts` :82, :93, :250 rewritten with
  children. `tests/session/sessions_test.ts`: a `resumeMessage` case for
  one session and for none. `tests/ui/agents/agents_test.ts`,
  `tests/ui/transcript/spend_test.ts`, `tests/ui/status/status_test.ts`:
  imports move to `waits.ts`; cases unchanged.

### U4 — words (protocol-led)

What still says "tab" in what chord tells agents and terminals:
`list_sessions`'s `tab` field and description (`server/tools.ts:172`,
:725, :898), the "front tab" wording of CHD-492, comments. Protocol owns
its content and may fold it into U3 if small. Runtime has nothing here but
review.

## 8. Tests: the full grep, and the guarantees kept

The grep, over every file git tracks under `tests/`, for
`leader(window, 'c'|'n'|'p'|'w'|'k'|'1'–'9')`, `CTRL_N` after the leader,
raw `CTRL_X` writes, `/new`, `MAX_TABS`, imports of `session/tabs.ts`,
`session/windows.ts`, `session/open_sessions.ts`, `resumes`,
`resumedFront`, `closeArmedLine`, `quitArmedLine`, `busyTabs`,
`stripLayout`, `tabChoices` and `session:new|next|previous|goto|list|close`
(`ctrl+x a` / `↓` hits left out: attention stays). Every hit has an outcome
in U1 or U2 above, or here:

- **Imports only, moved in U3:** `tests/status_test.ts`,
  `tests/session/window_monitors_test.ts`, `tests/ui/agents/agents_test.ts`,
  `tests/ui/status/status_test.ts`, `tests/ui/transcript/spend_test.ts`,
  `tests/ui/pickers/picker_test.ts`.
- **Whole files that go:** `tests/ui/app/Strip_test.tsx`,
  `tests/ui/app/strip_test.ts` (less its glyph cases), U2;
  `tests/session/tabs_test.ts`, `tests/session/open_sessions_test.ts` as
  files, U3 (rewritten under new names).
- **False hits, no change:** `tests/session/record_test.ts:2449` ("active
  resumes" in a title); `tests/ui/app/terminal_test.ts:380` (a comment).
- **Interface's, listed for completeness:** `tests/ui/shortcuts/bindings_test.ts`
  (:612, :956, :991, :1035), `Shortcuts_test.tsx`, `keys_test.tsx`,
  `tests/ui/app/keys_test.ts`, `tests/ui/prompt/commands_test.ts`,
  `tests/ui/prompt/state_test.ts`, `tests/ui/pickers/state_test.ts`,
  `tests/ui/dialogs/PermissionQueue_test.tsx`, `Link_test.tsx`,
  `Asker_test.tsx`, `tests/ui/background/BackgroundFrame_test.tsx`,
  `BackgroundDetailRoom_test.tsx`, `tests/ui/agents/Teams_test.tsx`,
  `tests/ui/app/AppCycle_test.tsx`: their `ctrl+x` hits are `ctrl+x a`/`↓`
  or key-table rows; each removed action's row goes with the action.

Per-agent guarantees the tab tests carried, and where each lives after:

| Guarantee | Test after |
|---|---|
| draft, cursor and images per agent | `PromptKeys_test.tsx` :302, `PromptImage_test.tsx` :473–:571 (main + child) |
| form values, open lists and focus per agent | `Form_test.tsx` :290, `App_test.tsx` :1249 (main + child) |
| question, secret draft and countdown per agent | `Questions_test.tsx` :368, :415 |
| permission queues per agent | `Permission_test.tsx` :696 |
| held scroll per agent | `TranscriptBack_test.tsx` :98 |
| a late copy never reaches the next session | `SelectionEdges_test.tsx` :75 (`/clear`) |
| a late read lands where it began | `PromptImage_test.tsx` :473–:548 |
| busy child and monitor cleanup on close | `AgentsClose_test.tsx` :149 (`/clear`), `Background_test.tsx` :93, `Monitors_test.tsx` :60 |
| retired spend kept once | `sessions_test.tsx` :180, :395–:619, `AppSpend_test.tsx` :207 |
| served results per agent with reused call ids | `Tasks_test.tsx` :501 |
| a start stopped with the window, any agent | `AppStart_test.tsx` :37, :74, :174, :261, :295 |
| the resumed directory decides startup and the model probe | `AppResume_test.tsx` :224 (single resume ×2), `headless_test.ts` (a), `cli_test.ts` :316 |

- **Fake agent:** one addition, `agentother` (U2), for a child on another
  runtime; everything else plays on existing scenarios (`agents`,
  `agentchild`, `agentclose`, `misbehaving`, CHD-489's `--hang start`).
  The CLI refusals are pure or argv-level and need no agent.
- **Timing:** the deletions take load out of the slowest UI files
  (`App_test.tsx` 44.5 s loses about a third of its window tests;
  `AppResume_test.tsx` 15 s trades two multi-agent windows for two
  single ones). Main + child rewrites start two fake agents where two tabs
  did, so their files stay near their records. The new pure files are
  milliseconds; `open_agents_test.ts` ≈ `open_sessions_test.ts` (0.8 s).
  No file nears 90 s. `tests/timings.json` is refreshed at the end of U1,
  U2 and U3.

## 9. Decisions overturned (by heading), and what of each holds

- **2026-10-06 "Several sessions in one window are chord's to build"** —
  overturned by the owner (2026-10-21).
- **2026-10-06 "Several sessions: a tab list of chord's own, each tab its
  own `Conversation`"** — the tab list goes. Holds: keys, not places, name
  an agent; the wait fold from `watchWaits`; the attention order and
  `ctrl+x a`'s walk, now over main and children; "no library".
- **2026-10-06 "Several sessions: a session behind that needs the
  person"** — the tab half (`tabName`, `fake (2)`, "sessions wait") goes;
  the notice of a child behind and once-per-wait notifications hold.
- **2026-10-07 "Several sessions: closing one, and quitting with several
  open"** — `ctrl+x k`, the busy-close arming, ctrl+d's arming with several
  and `Resume these sessions with:` go. Holds: `busyOf` (agent close
  arming), `closeAll` waiting for every close, an armed line standing
  alone.
- **2026-10-08 "The sessions picker, and `/resume` knowing the open
  sessions"** — the picker goes; "`/resume` never loads a session twice"
  holds, for a child (F9).
- **2026-10-08 "`/new <agent>`, each agent's starting values, and
  `/status`'s sessions"** — `/new` beside, the tenth session and
  `Sessions:` go **[N]**; `startupOf` holds for children; "what is drawn
  is the front tab's agent" becomes main's (or the picked child's, as
  today).
- **2026-10-08 "`-r <id> -r <id> …`: a tab each, each in its own place"**
  — overturned. Holds: Cliffy's repeated option (kept only to refuse
  several with chord's words), "one id is as it was", no argv rewriting.
  The per-tab place goes: one place, the session's directory.
- **2026-10-08 "A window record, and `--resume w-…`"** — no record is
  written; `--resume w-…` per **[W]** (protocol); the zod reader holds for the
  refusal.
- **2026-10-08 "Windows in `/resume`, and `--resume` with no id"** — the
  window rows and "Enter on a window opens beside" go. Holds: `[id:string]`
  with the owner's accepted Cliffy limit; the start picker on the window's
  renderer; the refusals with nothing to pick.
- **2026-10-08 "Long-lived agents: a list under the prompt, picked as a
  tab is"** — holds; "keyed as a tab is" reads "keyed from the window's
  counter".
- **2026-10-21 "CHD-492: …user variable"** — "until CHD-493, the front
  tab's" becomes "the main session's" (protocol words it).

## 10. Owner questions

R1 (`--resume w-…`) moved to protocol with the window record's handling;
R2 (`/new`) is now the lead's one question **[N]**. Runtime's design holds
under every answer to both: the `w-…` answer is a pure function called
before the terminal, and main is replaced by no path but, under the
"keep `/new <agent>`" answer, that one, which U3 would then keep (§7 U2).

**R3. One session in two chord processes.** With tabs gone, the window's
guard against opening one session twice covers only children; two panes
running `chord --continue` in one directory open the same session twice
(F15). Options:

- A. As today across processes: say it in `docs/guide.md` ("`--continue`
  in two panes opens the same session in both"), nothing more.
- B. A task to design a guard (a record that a session is open, which a
  second opener reads), knowing Q120–Q123 turned a lock down for CHD-492.

Recommendation: **A** now; B only if the owner wants the guarantee tabs
used to give. Nothing in this design depends on the choice.

## 11. Open questions (not the owner's)

- O1. Names: `waits.ts`/`window_agents.ts`/`open_agents.ts` are proposals;
  interface's state-slice names should match (lead to settle).
- O2. Should ctrl+d arm while a child is busy, as it did for a busy tab
  behind? Today with one tab it does not; this design keeps that. A
  separate task if wanted.
- O3. After main's agent exits, the only way back into that session is to
  quit and run the printed command (`/resume` leaves main's own id out).
  Same as one tab today; worth a line in the guide.
