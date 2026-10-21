# CHD-492 — interface draft

The interface architect's answers to the brief's interface questions, by
number. The flag is protocol's question 1; this draft writes it as
`--window w-<id>` (create, or reopen if the record exists) and keeps
`--resume w-<id>` as it is today (reopen, refuse if missing). Where the pick
of flag changes a screen, the screen says so.

What was read: the brief, the board survey (#9619), AGENTS.md,
`src/ui/AGENTS.md`, decisions.md's "A window record, and `--resume w-…`",
"Windows in `/resume`", "Several sessions: closing one, and quitting with
several open" and "Resume on chord's own session record",
`src/session/windows.ts`, `src/session/tabs.ts`,
`src/session/open_sessions.ts`, `src/main.tsx`'s quit path,
`src/ui/app/sessions.ts`'s `quit`, `src/ui/app/state.ts`,
`src/ui/status/Status.tsx`, `src/ui/pickers/picker.ts`.

What was captured (chord 0.56.0 from source on the fake agent,
`--qa chd492`, tmux 120×40 and 80×24, no live agent): an empty window, a
two-tab window and its quit message, `/resume` listing a saved window,
`/status`, and `--resume w-zzzzzzzz` refused. The screens below are drawn
from those captures; rows that stay blank are folded into one `┆` line
saying how many.

Colour roles named beside each screen are `src/ui/theme/theme.ts`'s
`Palette` keys; "dim" is the text attribute the status line already uses
for what is not a notice.

## Principle

A launcher-named window should look exactly like any other window while it
runs. The person did not type the id; Chorded did. Nothing on screen
announces it, nothing asks about it, nothing new takes a key. The id shows
in two places a person already looks for ids: `/status` and the quit
message. Everything else is the existing reopen path with fewer refusals.

## 1. What a person sees

### 1a. Start with a new id

Options: (i) nothing new on screen; (ii) a header line `window w-3f9c0a12`
under the directory; (iii) a status-line note at start.

**Pick (i).** The header already holds version, agent, model and directory,
and Claude Code's own header names no session id. A note at start would
cover `? for shortcuts` on every Chorded pane for no action the person can
take. The id is reachable through `/status` (below), which already prints
the tab's `Session:`.

120×40, `chord --window w-3f9c0a12 --fake`, before any prompt. Identical to
`chord --fake` today:

```
 ▀▄     chord v0.56.0                                                        mark: mark; version: default
 ▀▀▀▄   fake · Fake Large with a 1M context window                           dim
 ▄▀▀▀   /tmp/chord-qa.chd492                                                 dim
 ▀▀     ? for shortcuts · /help                                              dim
┆ 32 blank rows
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                  Fake Large with a 1M context window · medium effort
```

80×24: the same, 16 blank rows, status line
`  ? for shortcuts          Fake Large with a 1M context window · medium effort`.

`/status` grows one row, `Window:`, only in a window that has a record
(launcher-named, or opened from one). Roles as today's report (labels dim,
values default):

```
 › /status
   ⎿  Agent:     fake
      Model:     Fake Large with a 1M context window
      Mode:      Default
      Session:   abc463ea-9e37-4f8f-8ba0-6ced95214ef0
      Window:    w-3f9c0a12
      Directory: /tmp/chord-qa.chd492
```

At 80×24 the rows are the same; the UUID fits (11 + 36 columns).

The row is drawn by `src/ui/transcript/reports.ts` from a `windowId` the
window state holds (§3). A tab with no session yet prints `Session:` as it
does today; the window row is there either way.

### 1b. Reopen

`chord --window w-3f9c0a12` (or `chord --resume w-3f9c0a12`) on a record
that exists: the tabs open in order, the recorded front tab is in front, as
`--resume w-…` does today. Two things are new, both from protocol's
answers to its questions 2 and 3:

- A tab recorded with no prompt (no session record) opens as a **fresh
  session of its agent in its directory**: a tab in the strip whose
  transcript is the empty header, as a `ctrl+x c` tab is. No note: nothing
  was lost, there was nothing in it.
- The front is the tab that was in front, prompted or not, since every tab
  is now recorded. Today's rule ("one with no prompt gives the front to the
  nearest resumable tab on its left") is a quit-time rule for a record that
  leaves those tabs out; with them in, it goes.

120×40, three tabs recorded (fake prompted, claude prompted, fake never
prompted), front 2. Strip: front tab in `permission`'s highlight as today's
strip draws it, others dim:

```
 chord   1 fake   [2 claude]   3 fake                                                              /tmp/chord-qa.chd492
 ▀▄     chord v0.56.0
 ▀▀▀▄   claude · Sonnet
 ▄▀▀▀   /tmp/chord-qa.chd492
 ▀▀     ? for shortcuts · /help

 › hi two

 ⏺ Hello, world. This reply came in chunks.
┆ 26 blank rows
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                Fake Large with a 1M context window · medium effort · 1% context used
```

(`[2 claude]` marks the front tab here; on screen it is the strip's own
front style, not brackets.)

80×24: the strip is `chord   1 fake   2 claude   3 fake` with the directory
right-aligned in the 80 columns, as captured for two tabs; 10 blank rows.

### 1c. A tab left out on reopen

Today's note, through `sessionsNote` on the status line, coloured as a
notice (default foreground; `error` only for a failure, which this is not):

```
  Not reopened: codex tab 1a2b3c4d, its record is gone                Fake Large with a 1M context window · medium effort
```

New reasons a tab can be left out, each worded the same way, by agent and
short id, never by tab number (decisions.md's reason stands):

| Case | Note |
|---|---|
| session record gone (today) | `Not reopened: codex tab 1a2b3c4d, its record is gone` |
| directory gone | `Not reopened: codex tab 1a2b3c4d, ~/src/app is gone` |
| agent no longer known | `Not reopened: codex tab 1a2b3c4d, chord has no agent codex` |
| several | `Not reopened: 2 tabs (codex 1a2b3c4d: record gone, fake 9e0f…: ~/x gone)` |

A never-prompted tab has no short id; it is named `fake tab (new)` in the
same notes. An agent that can neither load nor resume is not a reopen
failure the window decides: it is today's per-tab start failure, drawn in
that tab as today.

At 80 columns the note is cut at the picker's edge as every
`sessionsNote` is; the single-tab wording is 52 columns and fits beside
nothing (the note stands alone at 80, as the model is dropped for an armed
line). If the agent-command case needs more room, it gets the shorter
`Not reopened: codex 1a2b3c4d (no such agent)`. This is
`windows.ts`'s `missingNote`, extended, pure and tested there.

If every tab is left out, today `--resume w-…` refuses (`None of window …'s
sessions is among chord's records.`). With `--window`, which creates when
missing, that would be a refusal of a window the launcher can no longer
open at all. **Pick:** `--window` opens one fresh tab of the default agent
in the launcher's directory and says why on the status line
(`Window w-3f9c0a12 had nothing left to reopen; this is a new tab`);
`--resume w-…` keeps refusing. Owner's call if `--window` should refuse too.

### 1d. Reopen of a window another chord holds

Options: (i) refuse before the screen is taken, on stderr, exit 1; (ii) open
it anyway under a new id; (iii) take it over from the holder; (iv) open it
read-only.

**Pick (i).** Two chords on one record means two writers and two copies of
each agent session; (ii) hands Chorded an id it did not choose, (iii) needs
a way to tell the other chord to stop writing (runtime), (iv) is a mode
chord has nowhere else. The holder is named so the person can find it:

```
$ chord --window w-3f9c0a12
error: Window w-3f9c0a12 is open in another chord (pid 4242).
```

Exit status non-zero, nothing drawn. How "holds" is known (lock, pid,
stale lock after SIGKILL) is runtime's question 2; a stale holder is not
refused.

Today's refusal of a missing window goes through Cliffy's `ValidationError`,
which prints the whole help before the error: captured at 80×24, the error
is the last row under 30 rows of help. For a launcher that reads stderr
that is noise; for a person it buries the line. Whether this refusal
should print help is a question for the owner, not a workaround: Cliffy
prints help for a `ValidationError` by design, and the alternative is a
different error class that exits without help (Cliffy's own behaviour for
any error that is not a `ValidationError`). **Pick:** the held-window
refusal is not a usage error, so it is not a `ValidationError`; the
missing-window one stays as decided.

### 1e. A record that cannot be written

Options: (i) refuse to start; (ii) start and say so once on the status
line; (iii) start and say nothing until quit.

**Pick (ii).** The person can still work; their session records are
separate files. Refusing a whole pane because `windows/` is not writable is
worse than a resume that does not come back. The note uses the startup
`warnings` path (the same one settings problems use), in `warning`:

120×40:

```
  chord cannot save window w-3f9c0a12 (EACCES): it will not reopen    Fake Large with a 1M context window · medium effort
```

80×24 (stands alone, the model dropped as an armed line drops it):

```
  chord cannot save window w-3f9c0a12: it will not reopen
```

A later write that fails after earlier ones succeeded says the same once,
then nothing more until one succeeds again (then nothing: success is not
announced). On quit, the stderr line of today (`chord could not save this
window: …`) and the per-session commands in its place, as decided.

Owner's call: whether a launcher-named window should instead refuse to
start (i), since the launcher asked for exactly that guarantee.

### 1f. Narrow

80×24 changes nothing new: no new row is added to header, strip or status
line. The only width-sensitive text is the notes in 1c and 1e, each with
the short wording given.

## 2. The quit message

Today: two or more prompted tabs → `Resume this window with:`; one →
`Resume this session with:` and the session's command.

Options for a window that has a record from the start: (i) always the
window command, whatever the tab count; (ii) today's rule (one tab: the
session command); (iii) both; (iv) nothing, since the launcher holds the
id (protocol's question to this draft).

**Pick (i)** for a window that has a record (launcher-named or opened from
one):

```
Resume this window with:
chord --resume w-3f9c0a12
```

even with one tab, and even with no prompted tab. Reason: the record exists
and is current, it reopens more than the session command does (the front,
the never-prompted tabs, the directory), and the line is the same one the
launcher will call, so what the person sees in scrollback agrees with what
Chorded does. Printing a session command for one tab would offer a second
way back that skips the record. (iii) doubles the lines for no gain.
(iv) leaves a person who ran `chord --window …` by hand, or whose launcher
is gone, with no way back in the scrollback. The line is the only way a
person learns the id, apart from `/status`.

The command printed is `--resume w-…`, not `--window w-…`: it names the
reopen, which is what the line says. With protocol's pick of a single
create-or-reopen flag the line names that flag.

A window started plain (`chord`, no id) keeps today's rule unchanged unless
protocol and runtime have every window keep a record from start, in which
case it takes (i) too. That is the written decision the brief names; its
change is the owner's.

On SIGHUP/SIGTERM nothing is printed: the terminal is gone or going. The
launcher already has the id.

## 3. State slices and the pure function

Where the window's shape lives today:

- the tab strip: `src/session/tabs.ts`'s `Tabs<C>`, pure, held by
  `OpenSessions` (`src/session/open_sessions.ts`), not a `state.ts` slice;
- each tab's session id and whether a prompt went to it: the tab's
  `SessionState` (`src/ui/app/state.ts`), read by `resumableSession`;
- each tab's directory: `placeOf(key).cwd` in `src/ui/app/sessions.ts`.

The record is built today only inside `sessions.ts`'s `quit`, inline.

**Pick: derive the record, do not enumerate events.** One pure function,
in `src/session/windows.ts` beside (and replacing) `windowOnQuit`:

```
windowNow(
  tabs: readonly { agent; cwd; sessionId?: string; prompted: boolean }[],
  front: number,        // index of the front tab in `tabs`
  { id, at },
): WindowRecord
```

It takes plain data, imports nothing from `ui/`, and is tested in
`tests/session/windows_test.ts` against each case: no tabs, one
unprompted tab, `/clear`ed tab (new session id), front out of range, a tab
whose session id is not yet known. `sessions.ts` keeps only the gathering it
already does in `quit` (moved into a function both `quit` and the writer
call), and the writer compares `windowText` of the new record, without
`at`, to the last one written; equal means no write. The events that change
it then need no list kept by hand, but for the record they are:

| Change | Where it happens |
|---|---|
| tab opened (`ctrl+x c`, `/resume` beside, window reopen) | `OpenSessions.open` → `openTab` |
| tab closed (`ctrl+x k`, last close is quit) | `OpenSessions.close` → `closeTab` |
| front changed (`ctrl+x n/p`, `ctrl+x 1…9`, `ctrl+x a`, `show`) | `nextTab`, `previousTab`, `goTo`, `attend`, `show` |
| session id known (`session/new` answered) | tab's `SessionState.sessionId` |
| first prompt or message | `resumableSession` turns defined |
| `/clear` | tab's `sessionId` replaced (`clearFront`) |
| directory | fixed per tab today; listed for completeness |

There is **no tab reorder** in chord today (the brief lists it); nothing to
write for it until one exists, and the derived record covers it then.

Children (task agents, long-lived agents, team members) are not tabs and
are not in the record (protocol's 4). The derived function takes tabs only,
so they stay out without a rule.

New window state: `windowId?: string` on `WindowState` in
`src/ui/app/state.ts` (the window's, not a session's; set once from the
`--window`/`--resume w-` id at mount, through the prop `App` already takes
as `resumedFront`), read by `/status`'s report and the quit message, and a
`windowSaveFailed?: string` beside `keysFailed`, which is how the status
line already shows a failure that stands. No feature folder gains a slice;
both are window-wide and `app/state.ts` holds those.

When the write happens (debounce, the signal path) is runtime's; the
interface only promises the derivation is cheap (≤ 9 tabs, no I/O) and can
run on every change.

## 4. `/resume` and one-tab or empty window records

With records written from start, `windows/` will hold windows with one tab
and with no prompted tab, which today never exist.

Options: (i) list every window record; (ii) list only those with two or
more tabs that have a session record; (iii) list all, one-tab ones marked.

**Pick (ii).** `/resume` merges an earlier window into *this* one; a window
row is worth its line only when it brings back more than one session. A
one-tab window's session already has its own row beside it, newer or equal
in time, so its window row is a duplicate; an all-unprompted window would
open blank tabs. Today's rule "none of whose sessions has a record left is
not offered" generalises to "fewer than two".

The row's count counts tabs with a record, not all recorded tabs:

```
│ ❯ 1. just now  ▣ 2 sessions · fake, claude · hi two                                                                 │
│   2. just now  hi two                                                                                                │
│   3. just now  hello                                                                                                 │
```

(captured shape; `permission` for border, title, `❯` and highlight; time
and directory dim.) A window recorded with a third, unprompted tab still
reads `▣ 2 sessions`, and Enter on it opens the two, not a blank third:
`/resume` adds sessions to a window, it does not recreate one. Only the
start-time reopen (`--window` / `--resume w-…`) recreates the fresh tabs.

The start picker (`chord --resume` with no id) uses the same list.

A window another chord holds is listed as today and gets no mark: whether
`/resume` should refuse a held window or a session open in another chord is
a wider question than this task (it is not refused for sessions today).
Noted as open for the owner.

## 5. Keys

**None.** Every new behaviour is driven by a flag and by changes that
already have keys (`ctrl+x c`, `ctrl+x k`, `ctrl+x 1…9`, `/clear`,
`/status`, ctrl+d). Nothing to add to `src/ui/shortcuts/keys.ts` or
`bindings.ts`; the shortcuts panel and `tests/ui/shortcuts/keys_test.tsx`
are unchanged.

## OpenTUI

Nothing new is drawn by a component chord does not have: the strip, header,
status line, transcript report and picker rows are today's `box`/`text`/
`span` through `theme/text.ts`. No OpenTUI component was needed or tried.

## Libraries tried

None needed on the interface side: the record builder is a map over tabs
already in hand, its equality check is a string compare of `windowText`,
and the notes are a handful of sentences in `windows.ts`. Cliffy's help on
`ValidationError` (1d) is used as it is, with the question of whether a
refusal is a usage error put to the owner.

## For the owner

1. A launcher-named window always prints the window command on quit, one
   tab included (2) — and whether plain windows follow, which changes the
   written "two or more prompted tabs" decision.
2. A record that cannot be written: start and warn (picked) or refuse to
   start (1e).
3. `--window` on a record with nothing left to reopen: a fresh tab with a
   note (picked) or a refusal (1c).
4. Whether a refusal that is not a usage error (window held elsewhere)
   prints Cliffy's help (1d).
5. Whether `/resume` should know a window or session is open in another
   chord (4); left as today.
