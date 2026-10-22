# CHD-493 — interface draft

The interface architect's draft: what a person sees and presses once a chord
process runs one main session. References are to origin/main `3f6f6656`
(v0.57.0). Screens were read from the code and checked against captures of
`bun dev chord --fake --qa iface` in tmux at 120×40 and 80×24 (the `agents`
scenario for children, `ctrl+x c` for a second tab), and Claude Code's own
`/clear` menu entry, read without sending a prompt.

The short of it: **the window becomes what chord with one tab already is.**
Every screen a single-tab chord draws today stays as it is; what goes is
what only appears with a second tab, plus the keys, commands, rows and
words that open, reach or count tabs. The one owner question is `/new`
(Q1, below); the design follows its recommended option.

## 1. What goes from the UI

| Thing | Where (origin/main) | Fate |
| --- | --- | --- |
| The tab strip | `src/ui/app/Strip.tsx` (61 lines), `src/ui/app/strip.ts` (197), `App.tsx:176,1113` | deleted; `GLYPHS` and the glyph reading move (§4) |
| `session:new` `ctrl+x c` | `bindings.ts:53`, `keys.ts` `new_session` | removed |
| `session:next`/`previous` `ctrl+x n`/`p`, `ctrl+x ctrl+n`/`ctrl+p` | `bindings.ts:54-58` | removed |
| `session:goto1`–`9` `ctrl+x 1`–`9` | `bindings.ts:59-67`, `TAB_NUMBERS`, `gotoAction` (`bindings.ts:118-141`) | removed |
| `session:list` `ctrl+x w` and the sessions picker | `bindings.ts:68`; `Pickers.tsx:329-386`; `picker.ts:188-300` (`TabRow`, `tabState`, `tabMark`, `tabChoices`); `pickers/state.ts:29-30,80-85` | removed |
| `session:close` `ctrl+x k`, its busy arming | `bindings.ts:70`; `sessions.ts:2689-2756` `closeFront`; `state.ts:211,282-283,768-779`; `closing.ts:141` `closeArmedLine` | removed |
| `/new` as "open a tab", `/new <agent>` | `prompt/commands.ts:71`, `app/commands.ts:113`, `sessions.ts` `openBeside` | `/new` becomes `/clear`'s alias (Q1) |
| The tenth-session refusal | `sessions.ts:2536-2540` (`Nine sessions are open; close one with ctrl+x k first`) | removed |
| `ctrl+d`/`/exit` arming with several open | `sessions.ts:2641-2678` `busyTabs`/`askQuit`; `closing.ts:192` `quitArmedLine` | removed: ctrl+d and `/exit` quit at once, as one tab does today |
| ctrl+c's armed count | `closing.ts:214` `ctrlCArmedLine(busy)` | the count goes: `Press ctrl+c again to quit` |
| `/status`'s `Sessions` row | `reports.ts:403-425`, `sessions.ts:2779` `counted` | removed |
| Window rows in `/resume` and the start picker | `picker.ts:100-180`, `Pickers.tsx:150-225`, `state.ts` `resume_listed.windows`, `sessions.ts:2980-3114` `pickWindow` | removed |
| `open in 2` in `/resume` | `picker.ts:118-139`, `sessions.ts:2826` `openTabs` | becomes `open now` for a child of this session (§3.7) |
| `Closed 2 fake · /resume opens it again` | `sessions.ts:2745-2755` | removed with `ctrl+x k` |
| Tab names in notices | `status.ts:153-290` `TabBehind.number/agent/waiter`, `… in 2 fake`, `N sessions wait/replied` | removed (§3.6) |
| `· N in this tab` | `BackgroundView.tsx:339` | `· N in this session` |
| `main is the session · ctrl+x k closes it` | `sessions.ts:2017-2029` | `main is the session · ctrl+d quits` (§3.4) |
| `No earlier fake session or window to resume` | `sessions.ts:2890`, `main.tsx:317` | `… session to resume …`; `main.tsx`'s start line is runtime's |
| `That window has a codex tab, which chord cannot start here.` | `sessions.ts:3016` | removed with `pickWindow` |
| `Not reopened: codex tab …, its record is gone` | `session/windows.ts:285` | removed with window records (runtime's) |
| `--resume`'s help, `… or a window (w-…) … a tab each` and the `… session or window` example | `cli.ts:44,63` | runtime's; one id or none |
| `list_sessions`' description `… runtime, model and tab` and its `tab` field | `server/tools.ts:172,725,745,897-898` | protocol's; its drawing is `transcript/tools/chord.ts:218` |
| `esc for the window · ctrl+c to quit` | `splash/splash.ts:18` | stays: "the window" is chord's screen, not a saved window |
| The panel's leader line | `keys.ts:92-145,389-420` | one plain line, `ctrl + x a` (§3.10) |
| The leader line's session words | `status.ts:604-707` `SESSION_WORDS`, digits, `list`, `close` | only `a the one that waits` is left of chord's (§3.2) |
| Tab subtotals in `/cost` | `spend.ts:169,462-495` (`kind: 'tab'`, `closed tab`), `spend_table.ts:38,373,417` (`This window`) | no tab level; the total reads `Total` (§3.12) |

No setting exists only for tabs: the settings table in `docs/guide.md`
(`agent`, `agents.<name>.*`, `preferredNotifChannel`, `theme`,
`editorMode`, `mouse`, `copyOnSelect`, `mcpServers`) all apply to one
session. What was "the tab's directory" (`sessions.ts:314-318`, a `Place`
per tab key) becomes the one place the window started in; children already
take their parent tab's place (`sessions.ts:1604`), so they take the
window's. Whether a resumed session from another directory still opens in
its own place is runtime's (`--resume <id>` today starts in the session's
own directory); on screen the header names whatever place the main session
works in, as today.

## 2. What stays exactly as it is

The header (`header/`), the transcript, the prompt box, the status line's
mode, model and context, the permission prompt and forms, the agents list
under the prompt and picking a child in it (↓ on an empty prompt, ↑ ↓ / j k,
Enter, Esc, `x`), the background summary and view (CHD-462, CHD-481,
CHD-487), `/team`, monitors, `/clear`, `/model`, `/config`, `/mcp`,
`/theme`, `/vim`, the crash screen and the splash. A child keeps its own
transcript, draft, queue, scroll and held window when picked, through the
same per-session state that tabs used (§4): the session layer's
"picked" child replaces the tab's front, not the swap itself.

## 3. Each feature that names a tab

### 3.1 The window, every state

Colour roles (`src/ui/theme/theme.ts`, `Palette`) are named in brackets
after a line; a line with none is the default `text`, `dim` is the DIM
attribute. The header's mark is drawn in `mark` tones.

**Empty, 120×40.** Row 1 is always the header; there is never a row above
it (today `App.tsx:1110-1113` adds the strip only with two tabs).

```
 ▀▄     chord v0.58.0                                                                    [mark; text bold]
 ▀▀▀▄   fake · Fake Large with a 1M context window                                       [text]
 ▄▀▀▀   ~/src/app                                                                        [dim]
 ▀▀     ? for shortcuts · /help                                                          [dim]
                                                                                    (rows 5–35 empty)
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                  Fake Large with a 1M context window · medium effort
```

Prompt border `[dim border, as today]`; status line left `[dim]`, right
`[plain]`.

**Empty, 80×24.** The same rows; the status line's right side cuts the
model first, as today:

```
 ▀▄     chord v0.58.0
 ▀▀▀▄   fake · Fake Large with a 1M context window
 ▄▀▀▀   ~/src/app
 ▀▀     ? for shortcuts · /help
                                                   (rows 5–19 empty)
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts          Fake Large with a 1M context window · medium effort
```

**Streaming, 120×40** (bottom rows; the rows above are the transcript):

```
 › fix the parser                                                                                         [text, dim ›]

 ⏺ Reading the tokenizer first.                                                                           [text]

 ⏺ Read(src/parse/tokenize.ts)                                                                            [text bold]
   ⎿  Read 212 lines                                                                                      [dim]

 ››› Working… (4s · esc to interrupt)                                                                     [accent]

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  esc to interrupt · ? for shortcuts                                       Fake Large with a 1M context window · 1% used
```

At 80×24 the same, the right side cut to `Fake Large with a 1M con… · 1%
used` as today. Nothing in streaming changes; it is drawn here only to show
that no strip glyph (`✻ 1 fake`) stands anywhere.

**Waiting on the person — a child asks, 120×40.** This is today's one-tab
screen, captured (`agents` scenario):

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ● docs needs your permission · ctrl+x a to go · ? for shortcuts        Fake Large with a 1M context window · 1% used
    main    fake · Fake Large with a 1M context window · medium  ◦ idle 3s
    parser  fake · Fake Small · medium                           ◦ idle 5s        ✓ new reply
    docs    fake · Fake Large with a 1M context window · medium  ● permission 6s  ← new message
```

`● docs needs your permission` `[warning]` (tone `waits`); `ctrl+x a to go`
is part of the notice, so `[warning]` too; agents list names `[agents[n]]`,
`● permission` `[warning]`, `✓ new reply` `[success]`, `← new message`
`[dim]`, `◦ idle` `[dim]`.

**Waiting, 80×24** (captured):

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ● docs needs your permission · ctrl+x a  Fake Large with a 1M con… · 1% used
    main    fake  ◦ idle 14s
    parser  fake  ◦ idle 16s        ✓ new reply
    docs    fake  ● permission 17s  ← new message
```

**Waiting — the main session's own request between turns** (CHD-158),
unchanged: `● permission asked between turns · ctrl+x a to answer` `[warning]`;
80×24 `● permission · ctrl+x a to answer`.

**Two or more agents ask:** `● 2 agents wait · ctrl+x a to go` `[warning]`.
The word is always `agents` now: `sessions` was the word for tabs behind
(`status.ts:233-235`).

**Error — a child gone, 120×40:**

```
  ✗ parser exited · ctrl+x a to go · ? for shortcuts                      Fake Large with a 1M context window · 1% used
    main    fake · Fake Large with a 1M context window · medium  ◦ idle 40s
    parser  fake · Fake Small · medium                           ✗ exited 2s
```

`✗ parser exited` `[error]` (tone `ended`), `✗ exited` `[error]`. Several:
`✗ 1 exited · 1 turn failed · ctrl+x a to go`. The tab form
`✗ parser exited in 2 fake` (`status.ts:273-279`) goes. At 80×24:
`✗ parser exited · ctrl+x a` then the right side as room allows.

**Error — the main session's agent exits or fails to start:** today's
one-tab screen, unchanged: the error line in the transcript `[error]`, the
connection state on the status line; nothing names a tab.

**Narrow (80×24) with a picker or the background view open:** unchanged,
the frame takes the window's width as today (`BackgroundView.tsx:80-90`).

### 3.2 The `ctrl+x` keys

| Key | Action | After | Rebindable |
| --- | --- | --- | --- |
| `ctrl+x c` | `session:new` | gone | — |
| `ctrl+x n` `ctrl+x ctrl+n` | `session:next` | gone | — |
| `ctrl+x p` `ctrl+x ctrl+p` | `session:previous` | gone | — |
| `ctrl+x 1`–`9` | `session:goto1`–`9` | gone | — |
| `ctrl+x w` | `session:list` | gone: the agents list under the prompt already shows every child with its state and unseen mark, which is what the picker added over the strip | — |
| `ctrl+x k` | `session:close` | gone: with one session it is `askQuit` (`sessions.ts:2697-2699`), so it only duplicated ctrl+d; a child closes with `x` in the list | — |
| `ctrl+x a` | `session:attention` | **stays**, same name, `Global`, rebindable | yes |

**What `ctrl+x a` does after.** Exactly its single-tab behaviour today
(`keys.ts:582-598`, `sessions.ts:2554-2561`), checked in the capture: first
the main session's own request between turns (the keys go into its box);
otherwise the agent of this session that has waited longest (`main` or a
child), in the attention order the session layer keeps, round on each press;
from the background view it closes the view first (CHD-462). With nothing
waiting the status line says `Nothing waits on you` `[plain]` in place of
`No session waits`, as `main` and children are agents, not sessions. The
attention order itself (tabs first, then the front tab's children) is
runtime's to reduce to one level; the screen depends only on "the next one
in order".

`ctrl+x` stays a leader: `ctrl+x a` keeps its key so the hints people learnt
(`· ctrl+x a to go`) keep working, and a person's own `ctrl+x …` chords
(the guide's `ctrl+x ctrl+e` example) keep a leader line. The leader line is
built from what is bound (`status.ts:625-707`), so after the removal it
reads, at both sizes (47 columns fits 80):

```
120×40:  ctrl+x …  a the one that waits · esc never mind                     [dim keys bold, as today]
80×24:   ctrl+x …  a the one that waits · esc never mind
```

With a person's `ctrl+x ctrl+e` bound: `ctrl+x …  a the one that waits ·
ctrl+e edit in $EDITOR · esc never mind`, the other action's words from
the panel as today.

Keys freed (`ctrl+x c n p w k 1–9`) are bound to nothing; a person's file
may bind them. `ctrl+n`/`ctrl+p` stay free of chord.

### 3.3 `/new`

Owner question Q1. Designed on the recommended option: **`/new` is
`/clear`'s alias, as Claude Code's menu lists `/clear (new)`.** The command
menu shows one row:

```
  ❯ /clear (new)   Start a new session with an empty transcript                [accent on the highlighted row, dim description]
```

Typing `/new` filters to that row; Enter on `/new` runs `/clear`
(`app/commands.ts:84-109`), refusals and all, and history keeps what was
typed.

The mechanism is as small as one alias needs, and exists only if the owner
picks (a). `/clear`'s entry in `CHORD_COMMANDS` (`prompt/commands.ts:38-43`)
gets `alias: 'new'` (one optional string, not a list). **An alias takes a
chord command name in every place a name does:**

- **Collisions:** `commandItems` (`prompt/commands.ts:108-130`) builds
  `ours` from every name and every alias, so an agent that advertises `new`
  is left out of the menu, as one named `clear` is now. Without this, the
  agent's `/new` row would come back while Enter ran `/clear`.
- **Typing and filtering:** the menu's fzf filter matches the alias too (a
  second key in fzf's `selector`; no new library). The row shows
  `/clear (new)`.
- **Tab completion:** Tab on `/ne` completes to `/new`, the name that was
  typed, not `/clear`. So completing and then pressing Enter goes the same
  way as typing the name out.
- **Dispatch:** the parser that reads a submitted `/name args` maps `new`
  to `clear` before it looks up chord's commands. Enter, Tab then Enter,
  and a `/new` brought back from history all reach the same `/clear`.

Test (`tests/ui/prompt/commands_test.ts`, beside the existing collision
case): an agent advertising `new` and `clear` yields one chord row
`/clear (new)` and no agent `new` row. Typing `/new` + Enter, and `/ne` +
Tab + Enter, each run chord's `/clear` and send the agent nothing
(`tests/ui/app/` on the harness).

`/new codex` (words after it) is refused in the transcript, as an unknown
agent is today, without clearing anything: `/new starts a new fake session
here; for codex, run chord codex in another pane` `[error, failed note]`.
The `/new ` agent list (`prompt/commands.ts:213`, `of: 'new'`) goes, with
`openBeside` and `startupOf`'s use for a tab; `startupOf` itself stays, as
children start on any runtime through it (`sessions.ts:1596,1635`).

### 3.4 The agents list

Unchanged on screen and in keys, with one note. `x` on `main` today says
`main is the session · ctrl+x k closes it` (`sessions.ts:2017-2029`,
pinned by `tests/ui/agents/Agents_test.tsx:139`). With `ctrl+x k` gone it
says `main is the session · ctrl+d quits` `[plain]`, naming the fixed quit
key. ctrl+d cannot be rebound, so the note has no unbound form.

Its row type's comment "the tab's own for
`main`" (`agents.ts:19`) becomes the main session's key. `agents.ts:11-12`
imports `TabWait`, `failureOf` from `session/tabs.ts` and `GLYPHS` from
`app/strip.ts`; both move (§4). The decision "Long-lived agents: a list
under the prompt, picked as a tab is" holds; only "as a tab is" stops
meaning anything, as there is no tab to compare it to.

### 3.5 The background view (CHD-487)

Unchanged but one word: the frame's title reads `Background · 3 in this
session` (`BackgroundView.tsx:339`), counting main's items and its
children's and members' as today ("the front tab's items" in the guide).
Its colours stay `[permission]` border and title, `[dim]` count.

```
120×40:
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Background · 3 in this session                                                                                       │
│ ❯ tests      monitor · m25   ● running 2m  main                                                                      │
│   explore    agent           ● running 40s main                                                                      │
│   lint       task · fake     ✓ done 1m     parser                                                                    │
│                                                                                                                      │
│ ↑ ↓ to move · enter for details · x to stop · esc to close                                                           │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
80×24: the same frame at 80 columns; the title fits whole (32 columns).
```

The row and hint lines above are illustrative; their layout is CHD-487's
and does not change. `hidden` (`BackgroundView.tsx:189-193`, "a request in
the front tab") reads "a request of this session's".

### 3.6 Notifications and the waits notice

**The waits notice** (`status.ts:153-290`) reads only the session's own
agents: today's `others` (`sessions.ts:3175-3196`, the front tab's agents
but the one picked) and nothing for tabs behind. So:

- `TabBehind` becomes `AgentWaiting { name, wait, task? }`: `number`,
  `agent` and `waiter` go, as they only named a tab.
- `asking`: one named, `● docs needs your permission`, `● docs asks for
  input`, a task by its box's name (CHD-431, `short`: `● main's task needs
  your permission`); more counted, `● N agents wait`.
- `failed`: `✗ parser exited`, `✗ parser's turn failed`, counted by kind.
- The `replied` branch goes: it fires only for an unnamed tab
  (`status.ts:221-224`); a child's reply is the list's `✓ new reply`.
- The key after it stays `session:attention`'s, `to go` while it fits.

**Terminal notifications** (OSC 9/777/BEL, `sessions.ts:325`): the name is
`notifiedName` without the tab number: the agent's name for the main
session (`fake needs your permission: Write notes.txt`, as one tab reads
today), the child's name (`docs needs your permission: …`), a member with
its run (`tester (bugfix) …`). `fake (2)` never appears. The fold of waits
per tab into one notification per wait is runtime's; on screen nothing else
changes. OSC 7501's root record and `title` are protocol's.

### 3.7 `/resume` and the start picker

**Rows.** Sessions only, newest first, as today; no `▣ 3 sessions · …`
window row. Old window records are not listed (records and `--resume w-…`
are protocol's and runtime's); their sessions are listed already, one row
each (`docs/guide.md:65-66`), so nothing a person had becomes unreachable.
The subtitle loses "and saved windows":

```
120×40:
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Resume a session                                                                                       [text bold]   │
│ fake's earlier sessions in this directory.                                                             [dim]         │
│                                                                                                                      │
│ ❯ 1. 1 minute ago   open now  parser · agentchild                                       [accent on ❯ row]            │
│   2. 1 minute ago             docs · permission                                                                      │
│   3. 2 hours ago              fix the tokenizer                                                                      │
│                                                                                                                      │
│ Enter to resume · Ctrl+a for all directories · Esc to close                                            [dim]         │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
80×24:
╭──────────────────────────────────────────────────────────────────────────────╮
│ Resume a session                                                             │
│ fake's earlier sessions in this directory.                                   │
│                                                                              │
│ ❯ 1. 1 minute ago   open now  parser · agentchild                            │
│   2. 1 minute ago             docs · permission                              │
│   3. 2 hours ago              fix the tokenizer                              │
│                                                                              │
│ Enter to resume · Ctrl+a for all directories · Esc to close                  │
╰──────────────────────────────────────────────────────────────────────────────╯
```

Empty list: `No earlier sessions in this directory.` and in the transcript
`No earlier fake session to resume, here or in any other directory.`
(`sessions.ts:2890-2891` without "or window"). With ctrl+a the directory
column is the session's own; `+1` per other directory was a window's and
goes.

**`open now`** replaces `open in N`: the main session is already left out
(`state.sessionId`), so a session open now is a child of this session.
Enter on it picks that child in the agents list (today's `pickSession`
branch, `sessions.ts:2916-2932`, with the tab step gone) and loads nothing
twice.

**Enter on any other row replaces the main session in place**, as it does
inside a tab today: the transcript empties and the chosen session's past
plays in, the current main's long-lived children close with it as on
`/clear`, the refusals stay (`resumeRefusal` while a turn runs; a session
from another directory is refused with its `chord <agent> --resume <id>`).
Nothing opens beside. Esc leaves things as they were.

**The start picker** (`chord --resume` with no id, `Start.tsx`,
`Pickers.tsx:212`): the same rows, subtitle `Pick one of fake's earlier
sessions to open.`; Enter opens what it picks as its own `--resume` would,
Esc quits with nothing started. `--continue` is runtime's.

### 3.8 `/status`

The `Sessions` row goes (`reports.ts:401-425`): with one tab it was never
drawn, so `/status` reads as it does today with one session:

```
 › /status
   ⎿  Agent      fake
      Model      Fake Large with a 1M context window
      Mode       default
      Session    2cf0ac9a-f86c-4e98-92e1-731e6bf3c1cc
      Directory  ~/src/app
```

No count of children replaces it; the agents list shows them.

### 3.9 Closing and quitting

- `ctrl+x k` and its armed line go (§3.2).
- **ctrl+d and `/exit` quit at once**, as one tab does today (decision
  2026-10-07: "one session quits as it always has"), children and teams
  closing with it. `quitArmed: 'ctrl+d'` and `quitArmedLine` go.
- **ctrl+c twice** stays: `Press ctrl+c again to quit` `[plain]`, alone on
  the status line, without a count of busy sessions.
- `x` on a busy child or team lead keeps its arming:
  `parser is working · x again to stop it and close`,
  `bugfix and its 3 members are working · x again to stop them and close`
  (`closing.ts:153-180`, `busyOf` stays).
- **On quit** the terminal gets `Resume this session with:` and one
  command (`sessions.ts:2652-2672` with one entry); never `Resume these
  sessions with:` or `Resume this window with:`. Which ids are printed is
  runtime's.

### 3.10 The shortcuts panel

The leader entry (`keys.ts:389-420`) becomes one plain entry, and
`SESSION_ACTIONS`, `sessionDoes`, `LEADER`, `leaderLines` and the
`leader` field go (`keys.ts:85-145,544-546`):

```ts
{
  key: 'ctrl + x a',
  does: 'for what waits on you',
  commands: ['key_pending', 'attend_session'],
  presses: ['ctrl + x', 'a'],
  actions: ['session:attention'],
}
```

`key_pending` stays named by it, as `keys_test.tsx` checks every command
`keyCommand` answers. Rebound, the line names the bound keys as any other
entry does (`shortcuts()`'s general path). The panel keeps 40 lines, so 20
rows a column at 80×24, one line swapped for one:

```
80×24 (rows 4–23):
  enter to send                           esc to close commands or files
  shift or \ + enter for a newline        ! for bash mode
  ctrl + g to edit in $EDITOR             backspace to leave bash mode
  ctrl + v to paste an image              esc to interrupt or stop a command
  alt + ← → to move by word               shift + tab to cycle modes
  cmd + ← → to line start or end          ctrl + o for verbose output
  ↑ ↓ for prompts, agents, background     ctrl + c to clear input
  x to close an agent, stop background    ctrl + d or ctrl + c twice to quit
  enter for background, details, a call   ctrl + x a for what waits on you
  ctrl + r to search prompts              1–9 to pick a choice
  tab enter to take a match               ↑ ↓ or j k to move between choices
  esc to cancel a search                  enter to pick the highlighted choice
  pgup pgdn or wheel to scroll            esc to reject a permission
  shift + ↑ ↓ to scroll a line            esc ← to leave a picker or shortcuts
  home end for the top and the bottom     ctrl + a to show all directories
  ctrl + c to copy                        tab ← → ↑ ↓ space to answer forms
  / @ for commands or files               ctrl + c to stop the turn and its form
  ↑ ↓ to pick a command or file           /vim for vim mode
  tab to complete a command               ? for shortcuts
  tab enter to add a file                 any key to quit the crash screen
```

At 120×40 the same 40 lines in three columns of 14, 14 and 12, as today.
Keys `[text bold]`, words `[dim]`, as today. `close_sessions_picker` leaves
`esc ←`'s command list (`keys.ts:461`).

### 3.11 Keybinding files naming removed actions

A file that binds a removed action keeps working; that one binding is left
out with words that say why, rather than today's generic `unknown action
"session:new", ignored` (`bindings.ts:380-383`):

```
keybindings.json: session:new went with tabs: chord runs one session, ignored
keybindings.json: 3 problems · session:next went with tabs: chord runs one session, ignored
```

shown where every keybindings problem is shown now (the transcript's
warning at start, stderr, and the status line's count; `keybindingsNotice`,
`bindings.ts:725-740`). `bindings.ts` keeps a `REMOVED` list of the eleven
names (`session:new`, `next`, `previous`, `goto1`–`9`, `list`, `close`)
consulted before `isAction`; `null` on a key that one of them held is no
problem, as `null` names no action. Nothing is rewritten in the file. The
guide's action list (`docs/guide.md:555-560`) keeps `session:attention`
only, and says the others were removed in 0.58.0.

### 3.12 `/cost`

The table has no tab level: its top-level rows are `main` (and each main
session `/clear` or a resume let go, ended), each child, each team run with
its members, each task under whoever started it. The `1 fake` subtotal row
and `closed tab` go (`spend.ts:462-495`), and the total row reads `Total`
in place of `This window` (`spend_table.ts:373,417`), as the window is the
terminal's now. The table still appears once there is more than one part,
a task included, as today. The spend kept for closed parts is runtime's;
`KeptSpend.tab`/`tabName` go with tabs.

## 4. State slices, pure logic, components

Per-session state stays per session: `SessionState`
(`app/state.ts:128-185`, with `PromptSession`, `ViewSession`,
`DialogsState`) is still kept by key in `WindowedState.sessions`
(`state.ts:1022-1032`), because picking a child swaps it in exactly as a
tab switch did. What goes is the tab level above children. "Per tab" in the
brief's list maps as:

| Brief's "per tab" state | Today | After |
| --- | --- | --- |
| draft, cursor, images, queue | `PromptSession` by session key | unchanged: main and each child keep their own |
| scroll, mounted tail | `ViewSession` by key | unchanged |
| dialogs (permission/form box) | `DialogsState` by key | unchanged |
| place / directory | `sessions.ts:314` `places: Map<key, Place>` | one `Place`; the map and `frontPlace` go |
| bash command | `bash.stop(key)` by key | unchanged by key; `stopCommand(front)` from `closeFront` goes |

Slice by slice:

- **`app/state.ts`** (`WindowState`): `closeArmed`, `close_armed`,
  `close_disarmed` go; `quitArmed` narrows to `false | 'ctrl+c'`;
  `keptSpend`'s comment loses "tabs"; `sessionsNote` stays for `ctrl+x a`'s
  `Nothing waits on you`, `/team talks to main` and child notes (rename is
  optional; keep the name to keep the diff small). `WindowedAction`'s
  `session_opened` goes; `session_shown`, `session_closed`, `agent_opened`,
  `in_session`, `spend_*`, `retired_heard`, `closing_heard` stay, with
  "tab" in their comments read as "the main session". `front` keeps its
  name: the session on screen, main or a picked child.
- **`pickers/state.ts`**: `sessionsPicker`, `sessions_picker_opened`,
  `sessions_picker_closed` go; `ResumePicker.windows` and
  `resume_listed.windows` go.
- **`shortcuts/state.ts`**: the sessions picker's Esc case (`:194`) goes.
- **`background/state.ts`**: no field changes; comments only.
- **`prompt/state.ts`**, **`transcript/state.ts`**, **`dialogs/state.ts`**:
  no change.

Pure logic beside the components:

- `app/strip.ts`, `app/Strip.tsx`: deleted. `GLYPHS`, `TabGlyph`,
  `TabGlyphs`, `tabGlyphs`, `glyphsOf` move to **`src/ui/agents/glyphs.ts`**
  as `GLYPHS`, `WaitGlyph`, `waitGlyphs`: their users are the agents list,
  the background, the status line, teams and the resume picker
  (`agents.ts:12`, `background.ts:24`, `status.ts:29`, `teams.ts:17`,
  `picker.ts:21`), and the agents list is where the states are worded.
  The `Wait` type and `failureOf` come from wherever runtime puts the waits
  now in `session/tabs.ts`. The glyph cases of
  `tests/ui/app/strip_test.ts` (`:6` and `:135` onward: idle and working,
  working with an unseen reply, exited against a failed turn, a message,
  asking with a failure) move with them to
  `tests/ui/agents/glyphs_test.ts`. Only the strip's geometry cases
  (`:81-133`) go.
- `app/keys.ts`: `KeyCommand`s `new_session`, `next_session`,
  `previous_session`, `goto_session_1`–`9`, `close_session`,
  `list_sessions`, `close_sessions_picker` and their `Step`s
  (`open_session`, `next_session`, `previous_session`, `goto_session`,
  `close_session`) go; `attend_session` and `key_pending` stay; the
  "armed close is taken back" step (`keys.ts:530-534`) goes.
- `app/closing.ts`: `BusyTab`, `closeArmedLine`, `quitArmedLine`,
  `sessionsBusy` go; `ctrlCArmedLine()` takes no count; `busyOf`,
  `agentCloseArmedLine`, `teamCloseArmedLine` stay.
- `status/status.ts`: `waitsNotice` over `AgentWaiting` (§3.6);
  `leaderItems` keeps `session:attention` and the person's own chords.
- `pickers/picker.ts`: `TabRow`, `tabState`, `tabMark`, `tabChoices` and
  the window rows go; `open in N` becomes `open now`.
- `shortcuts/bindings.ts`, `shortcuts/keys.ts`: §3.2, §3.10, §3.11.
- `prompt/commands.ts`: `aliases` on `CommandItem` (§3.3).
- `transcript/spend.ts`, `spend_table.ts`: §3.12.
- `app/sessions.ts` (3332 lines) loses `openBeside`, `closeFront`,
  `busyTabs`, `tabRows`, `counted`, `listFrom`, `pickTab`, `openTabs`
  (becomes "the child with this id"), `pickWindow`, the strip in `lines`,
  and the tab step of `pickSession`; its split with the session layer is
  runtime's.

OpenTUI: nothing new is drawn, and nothing is drawn by a new component. The
strip was chord's own spans on `text`; it goes. Every remaining screen is
`box`/`text`/`span` through `theme/text.ts` and the pickers' existing
`PickerList`, as today. There is no OpenTUI component to take here and none
missing.

## 5. Docs and screenshots

- **README.md**: "Many agents in one window" (`:68-74`) becomes "Agents
  beside the main one": long-lived agents, teams and tasks under the
  prompt, their state at a glance, `ctrl+x a` to what waits; image
  `docs/images/agents.png`. "Pick up where you left off" (`:96-99`) drops
  windows. The keys table (`:149-150`) drops `ctrl+x c` / `/new codex` and
  `ctrl+x 1…9`, and gains `ctrl+x a` | `go to what waits on you`.
- **docs/images/tabs.png** is deleted; **docs/images/agents.png** is new,
  from a `scripts/dev/screenshots.ts` shot on the fake `agents` scenario
  waiting on `docs`'s permission (the 120×40 capture in §3.1); the `tabs`
  shot (`screenshots.ts:105-121`) goes. `resume.png` is retaken, as its
  subtitle changes. `scripts/` is the ship team's to change.
- **docs/guide.md**: `:54-55` (`-r a -r b`, `--resume w-…`), `:60-77`
  (windows in `/resume`), `:83-131` (tabs, strip, `ctrl+x` keys, sessions
  picker, close, window records) rewritten to one session, keeping the
  waits notice and `ctrl+x a` text for children; `:148-160` (several
  `--resume`); `:184` (iTerm2 tabs: the terminal's, stays); `:224`
  (header "under the row of tabs"); `:230` (`✻` in the tab); `:404-410`
  (`/cost` table); `:452-453` (notification names the tab); `:458-459`,
  `:491` (OSC 7501 "every tab", "front tab"; protocol's words); `:555-560`
  (keybinding actions, §3.11); `:580` (ctrl+ч then `с` opens a session:
  use `а` for `ctrl+x a`); `:639-674`, `:713`, `:808`, `:880-886`,
  `:915`, `:923`, `:948` ("tab" for the session).
- **docs/guide.md** also: `:474` "until it restarts or its tab closes"
  becomes "until it restarts or its session closes". A full grep of
  the guide for `tab`/`window` hits lines 54 56 65 67-73 88 90 93 94 102
  105 128 131 150 153 162 167 171 184 224 230 404 407 410 452 458 459 474
  491 639 640 647 664 808 880 886 907 915. Of these, 162 167 171 184 and
  907 are the Tab key, iTerm2's tabs or shift+tab, and they stay. The rest
  are covered above.
- **README.md** also: `:132` `chord --resume  # pick an earlier session or
  window` loses "or window"; `:6` ("keyboard-driven window, side by side")
  and `:137` ("Inside the window:") mean chord's screen and stay.
- **docs/FEATURES.md**: row `:60` "Resume a whole window" and row `:89`
  "Several sessions in one window" go; `:56` drops `/new` from the client
  commands, or lists it as `/clear`'s alias; `:143` "chord's own session
  and window records" becomes "chord's own session records"; `:81`
  ("the terminal's tab") and `:130`, `:148` ("while the window is open",
  "in one window") mean the terminal's tab and chord's screen, and stay.
- **docs/agent-capabilities.md**: `:3178`, `:5635` say "tab" for a
  session; reword.
- Designs that name tabs (`docs/design/CHD-114.md`, `CHD-471.md`,
  `CHD-487.md`) are records and stay as written.

## 6. Decisions overturned (interface side)

- **2026-10-06 "Several sessions in one window are chord's to build"** —
  overturned by the owner's call of 2026-10-21.
- **2026-10-06 "Several sessions: the strip, the leader line and the
  `session:` keys"** — the strip and every `session:` key but `ctrl+x a`
  go. Holds: the leader line built from what is bound, and a chord begun
  taking the next key from every widget.
- **2026-10-06 "Several sessions: a session behind that needs the person"**
  — the tabs behind, their glyphs and `fake (2)` go. Holds: the notice for
  the session's own agents, its order (permission, then failure), the key
  after it, `ctrl+x a` as `session:attention`.
- **2026-10-07 "Several sessions: closing one, and quitting with several
  open"** — `ctrl+x k`, its arming, ctrl+d/`/exit` arming and `Resume
  these sessions with:` go. Holds: `busyOf`, an armed line standing alone,
  the agents' `x` arming built on it.
- **2026-10-08 "The sessions picker, and `/resume` knowing the open
  sessions"** — the picker goes. Holds: `/resume` never loads a session
  twice, now for a child (`open now`, Enter picks it).
- **2026-10-08 "`/new <agent>`, each agent's starting values, and
  `/status`'s sessions"** — `/new` as a tab, `/new <agent>`, the tenth
  session and the `Sessions` row go. Holds: `startupOf` for children's
  runtimes. "What is drawn is the front tab's agent" reads "the main
  session's agent".
- **2026-10-08 "Long-lived agents: a list under the prompt, picked as a tab
  is"** — holds whole; only its comparison to tabs is moot.
- **2026-10-08 "Windows in `/resume`, and `--resume` with no id"** — the
  window rows go from both pickers; `--resume` with no id holds.
- **2026-10-06 "Custom keybindings: Claude Code's file shape, a parser and
  matcher of chord's own"** — holds; adds removed names with their own
  words (§3.11).
- **2026-10-09 "`/team`: the picker, show, run and stop"** — "the front
  tab's `main`" reads "`main`"; holds.
- **2026-10-07 "M4: agents start agents through an MCP server chord
  serves"**, its tab clauses:
  - "a task agent's in the parent's tab": holds as "in the parent's
    session".
  - "A message is a turn": `<message from="codex · tab 2">` and the row
    `← codex · tab 2` are already gone from the code (`session/tasks.ts`'s
    `fromLine` names no tab). The record of them stays as written.
  - "a tab behind that got one is marked as a session that waits is": goes.
    A child's message is the agents list's `← new message`.
  - "makes its parent busy, so `ctrl+x k` and quitting arm": goes with
    `ctrl+x k` and quit arming. A busy child still arms `x` on its lead.
  - "with no tab of their own, left open they would be out of sight":
    holds as the reason children close with their parent.
  - "never longer than the tabs' nine": the eight-children cap holds; its
    reason reads "with `main`, nine rows".
- **2026-10-13 "CHD-355: the person's own sessions start on an effort from
  the files or `--effort`"** — "the window's first session, each `/new`
  and `-p` ask for it": `/new` drops out. Under Q1 (a) `/new` is `/clear`,
  and `/clear` starts the same agent's next session on the same startup.
  What remains is the main session, each `/clear` and `-p`. The refusal
  line and the files-over-flag order hold.

The session-layer headings (2026-10-06 "a tab list of chord's own",
2026-10-08 "`-r <id> -r <id>`", "A window record, and `--resume w-…`",
CHD-492's "until CHD-493, the front tab's") are runtime's and protocol's.

## 7. UI tests

Go: `tests/ui/app/strip_test.ts`'s geometry cases (its glyph cases move
to `tests/ui/agents/glyphs_test.ts`, §4), the sessions picker's and the tab
switching, closing, `/new` beside and window-pick cases in
`tests/ui/app/` and `tests/ui/pickers/`, `closing_test`'s `closeArmedLine`
and `quitArmedLine` cases. Rewritten: `tests/ui/shortcuts/keys_test.tsx`
(the `ctrl + x a` entry; no digits, `c n p w k`), `bindings_test`
(removed names give their words), `status_test`'s `waitsNotice` and leader
line cases, `picker_test`'s resume rows (`open now`, no windows),
`reports_test`'s `/status`, `spend_test`/`spend_table_test` (no tab level,
`Total`), the command menu's alias. Stay: the agents list, background,
teams, permission and form tests, which already run with one tab. The
order of units and `tests/timings.json` are runtime's.

## Owner questions

### Q1. What does `/new` become?

Context: `/new` opens a tab beside the one in front, `/new codex` one of
another agent (2026-10-08). With one session per process nothing opens
beside. Claude Code lists `/clear (new)`: `/new` is its alias for a fresh
session (checked in Claude Code 2.1.307's command menu, no prompt sent).

- **(a) `/new` is `/clear`'s alias, as in Claude Code; `/new <agent>` is
  refused with a pointer to `chord <agent>` in another pane.**
  Recommended: Claude Code's name for the same thing, one meaning, nothing
  to learn, and "a session of another agent" is a new process, the
  terminal's job by the owner's call.
- (b) `/new` alone is `/clear`; `/new <agent>` ends this session and starts
  one of the named agent in its place (header, model, modes, MCP servers
  read again for that agent). Keeps a way to switch agent without leaving
  chord, at the cost of a main session whose agent changes mid-process,
  which `/resume`'s agent-scoped list, quit's command and OSC 7501 would
  each have to follow.
- (c) `/new` goes from chord's commands. Then nothing of chord's holds the
  name, so **an agent that advertises its own `/new` gets it back**: it is
  listed in the menu as the agent's, and Enter sends it to the agent as a
  prompt, as with any agent command. An agent that advertises none gets
  `/new` typed as plain text. Least code, but a person used to `/new` gets
  whatever the agent does with it.

The design above follows (a): §3.3, §5's FEATURES.md row.

## Notes for the lead

- The captures ran `bun dev chord --fake` from the shared checkout (the
  worktree has no `node_modules`), at `3f6f6656`, the same commit. Its
  session records went to the default state directory, as `--qa` changes
  only the working directory: three fake sessions under
  `/tmp/chord-qa.iface`. No live agent was used; Claude Code was opened
  (2.1.307) only to read its `/new` menu entry, no prompt sent.
- Depends on runtime for: the waits and attention order reduced to one
  session's agents, `Wait`/`failureOf`'s new home, which ids quit prints,
  `--resume` with several ids and `w-…`. On protocol for: window records,
  OSC 7501, `list_sessions`' `tab` field (`transcript/tools/chord.ts:218`
  draws `${session.tab} ${session.runtime}`; it needs a new label if the
  field goes).
