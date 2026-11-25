# CTUI-37 interface draft: teams on screen, `/team`, `get_budgets`

The interface architect's answer to the brief's three interface questions:
every screen, state and word of teams, with the source line it comes from;
where each piece sits in the port's UI; and the capture plan. Then the units
for ship and the questions for the owner.

Sources are `../chord` at its current head. `src/` and `tests/` hold where
`docs/design/M5-teams.md` differs; section 8 lists each difference. The
mocks below are laid out by the source's rules (`teams.ts`, `proposal.ts`,
`agents.ts`), with M5's example team, which has `claude` and `codex`
members. The fake's team (`tests/fixtures/teams/fake/bugfix.md`) has
`fake · fake-large` / `fake · fake-small` instead. The cells are
illustrative: the acceptance is the original's capture beside the port's
(section 7), not these drawings. Colours are named beside each mock by the
port's theme roles (`theme.focus` is the original's `permission`).

No new key, no new action, no new colour role. The shortcuts panel does not
change (section 6).

## 1. What already exists in the port and is reused

- The save box: `lib/ui/dialogs/permission_prompt.dart` `_saveBoxOf`,
  `lib/ui/dialogs/permission.dart` `saveChoices`, `SaveBox` in
  `lib/session/transcript/types.dart`. CTUI-79 built it for the settings
  tool, from the same original shape (`askPerson` with `save`), so
  `propose_team` passes a `SaveBox` and draws nothing new.
- The asker row `tester · bugfix asks`: `lib/ui/dialogs/asker.dart`
  (`PickedAsker.team`) already draws a member's team dim.
- Pickers: `lib/ui/pickers/pickers.dart` (the `/resume` panel shape),
  `lib/ui/pickers/picker.dart`.
- The diff of a change's body: `lib/ui/transcript/tools/diff.dart`
  (`diffView`, `lineCount`, `plural`), on `dartdiff` (CTUI-6).
- The agents list, its states, marks, row limit and `… +N more`:
  `lib/ui/agents/agents.dart` and `agents_view.dart`; their headers say
  teams' folding and branches come with CTUI-37.
- `childLine`, `leftOpenLine`, `childEnded`: in the port without their team
  branches (`agents.dart:894`, `agents.dart:931`,
  `session/window_agents.dart:282`).
- `/team` is reserved in `lib/ui/prompt/commands.dart` (`reservedCommandNames`)
  but not offered in `localCommands`; `chord acp` lists only `new`
  (`lib/session/upstream.dart` `chordCommands`).
- The team part of a first prompt is already parsed by the record
  (`lib/session/record.dart` `_teamLabel`, `wrappedInTeam`) and replay skips
  it (`replay.dart:411-433`); nothing draws it yet.

## 2. The screens, state by state

Each subsection: where it sits in the port, the words verbatim with their
source line, the states, the styles, and the drawings.

### 2.1 `/team` in the slash list, `/help` and completion

- Slash list row: `/team` · `Describe, keep and run teams of agents`
  (`src/ui/prompt/commands.ts:111`). Port: add
  `CommandItem('team', 'Describe, keep and run teams of agents')` to
  `localCommands` in `lib/ui/prompt/commands.dart`, in the original's
  alphabetical place, between `status` and `theme`. `/help` lists it with
  the rest of `localCommands`.
- Names after `/team show `, `run ` and `stop ` (`commands.ts:172-214`):
  `teamQuery(draft)` matches `^/team +(show|run|stop) +([^\n]*)$`; for
  `show` and `run` the name has no space, for `stop` it runs to the end of
  the line (a run is `bugfix 2`). `teamItems` offers saved teams that are
  not broken for `show`/`run`, and the open runs' names for `stop`. Each
  item is `CommandItem(name, of: 'team', verb: form)`, drawn as `/new`'s
  agent rows are, its name alone. `completion` writes
  `/team <verb> <name> `. Enter on a highlighted `run` item completes the
  draft rather than running it, as the job is still to come
  (`commands.ts:378-382`). Port: `CommandItem` gains `verb`; `teamQuery`,
  `teamItems` and the `submitted` branch go beside `agentQuery`.
- The names are read when the draft reaches a team's name
  (`src/ui/prompt/state.ts:158-195`, `TeamNames`): the teams by name with
  a broken file marked, and the runs open. Plain state in
  `lib/ui/prompt/state.dart`, read by the window from the host.

States: no team saved: the list after `/team run ` is empty and closes, as
`/new`'s does with no agents; broken files are left out of `show`/`run`;
no run open: `stop` offers nothing.

### 2.2 The teams picker (`/team`, `/team list`)

Where: `lib/ui/pickers/pickers.dart` gains `TeamsPicker` beside the resume
picker, floating over the transcript as `/resume` does (guide line 220).
Its rows, title line and hint are pure functions in a new
`lib/ui/teams/teams.dart` (from `src/ui/teams/teams.ts`).

Words:

- Title `Teams`, bold in `theme.focus` (`src/ui/pickers/Pickers.tsx:620-630`).
- The line under it, dim (`teams.ts:190-197`, `team_command.ts:172-179`):
  - `Saved for this project in .chord/teams, and for every project in ~/.config/chord/teams.`
  - with no user directory: `Saved for this project in .chord/teams.`
  - below 100 columns (`NARROW`, `teams.ts:79`):
    `For this project in .chord/teams, for every project in ~/.config/chord/teams.`
    It wraps where it is wider than the box (`Pickers.tsx:607-613`); at 80
    columns it is 77 cells in a 76-cell box, so it takes two lines.
- A row (`teamChoices`, `teams.ts:95-187`): name, `4 agents · claude, codex`
  (`N agents` alone below 100 columns), the place
  (`this project`, `every project`, or `this project · hides every project's`),
  the running column when any team runs (`✻ working 6m` for one run,
  `✻ 2 runs` for more, `teams.ts:68-76`), then the description. Columns are
  padded to their widest, two spaces apart.
- A broken file's row: `✗ not read: <problem>` across the columns, then its
  path where the description starts; below 100 columns, no path
  (`teams.ts:156-169`).
- Empty: `No teams yet. /team new and a few words about the work makes one.`
  (`team_command.ts:150-151`), plain, a row under the line; no list and no
  hint's first half.
- The hint, dim (`teams.ts:204-225` and `useCloseHint`):
  - on a team: `Enter to hand it a job · /team show <name> · Esc to close`;
    below 100 columns `Enter to hand it a job · Esc to close`;
  - on a broken file: `Fix the file, or ask main to fix triage · Esc to close`;
    below 100 columns `Ask main to fix triage · Esc to close`;
  - empty: `Esc to close`.
  `Esc` is whatever `select:cancel` is bound to, capitalised.
- The running times are read once when the picker opens and do not tick
  (`Pickers.tsx:599-602`).

Keys: the picker's own (↑ ↓, Enter, Esc). Enter on a team puts
`/team run bugfix ` in the draft and closes the picker (`pickedDraft`,
`teams.ts:231-233`), also for a running team, which starts another run.
Enter on a broken file does nothing and the picker stays.

120x40 (box in `theme.focus`, title bold, second line dim, hint dim, `✗`
row's glyph in `error`):

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Teams                                                                                                                │
│ Saved for this project in .chord/teams, and for every project in ~/.config/chord/teams.                              │
│                                                                                                                      │
│ ❯ bugfix  4 agents · claude, codex  this project   ✻ working 6m  Fixes a bug end to end: a failing test first, then │
│           the fix, then a review of the diff.                                                                        │
│   review  3 agents · claude         every project                Reviews a branch before it goes to the owner        │
│   triage  ✗ not read: members.1.agent is missing                 ~/.config/chord/teams/triage.md                     │
│                                                                                                                      │
│ Enter to hand it a job · /team show <name> · Esc to close                                                            │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

80x24, `triage` highlighted:

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Teams                                                                        │
│ For this project in .chord/teams, for every project in                       │
│ ~/.config/chord/teams.                                                       │
│                                                                              │
│   bugfix  4 agents  this project   ✻ working 6m  Fixes a bug end to end: a   │
│           failing test first, then the fix, then a review of the diff.       │
│   review  3 agents  every project                Reviews a branch before it  │
│           goes to the owner                                                  │
│ ❯ triage  ✗ not read: members.1.agent is missing                             │
│                                                                              │
│ Ask main to fix triage · Esc to close                                        │
╰──────────────────────────────────────────────────────────────────────────────╯
```

Whether the description wraps under its row or is cut at the edge is the
original `PickerList`'s behaviour; M5 says cut, the guide says the
`/resume` picker's labels wrap (guide line 112). The capture decides and the
port follows it; drawn wrapped here.

### 2.3 `/team new <words>`

Drawn as typed, `› /team new …`; main's turn gets `newTeamPrompt(words)`
(`team_command.ts:162-169`):

`The person asks for a team of agents through /team new: work out the team for what they describe below, then call chord's propose_team with it (list_agents gives each runtime's models and modes).` then a blank line and the words.

Refused with nothing after `new`:
`/team new takes a few words about the work the team does`
(`team_command.ts:70-75`), as a `said` refusal (2.6). With a child picked,
the first `/team` form other than `list` in the window notes on the status
line `/team talks to main` once (`src/ui/app/commands.ts:99,334-339`).

### 2.4 `propose_team`: the proposal and the save box

Where: the call's row in `lib/ui/transcript/tools/tool.dart` gains the
`Proposal` body and `TableRow` (`src/ui/transcript/tools/Tool.tsx:492-640`);
the layout is a new `lib/ui/transcript/tools/proposal.dart` (from
`proposal.ts`). The box is the existing save box.

Headline (`src/ui/transcript/tools/chord.ts:101-110`): `Team(bugfix)` until
chord serves the call, then `Team(bugfix) · proposal`, or
`Team(bugfix) · change` for a name already saved.

Body under `⎿`, in order (`Tool.tsx:533-580`):

1. The description, dim, wrapped.
2. A blank line.
3. The table (`proposalTable`, `proposal.ts:242-442`): a row per agent, the
   lead first with role `Splits the job, says who edits which files, reports to main`
   (`team_command.ts:153-155`). Columns: name, `runtime · model`, effort
   (only where any agent sets one or had one; `—` for the runtime's own),
   mode (`—` for the runtime's own), role. Padding 2. Folded (no ctrl+o):
   the role narrows first down to 12 cells, then a changed effort's
   `was …` goes, then `runtime · model` narrows; role and runtime wrap in
   their columns, never cut; name, effort and mode never wrap. Where even
   that does not fit, the table is laid out as opened. Opened (ctrl+o):
   each role goes on lines of its own under its row, dim, from the runtime's
   column to the right edge; where the row does not fit, the mode wraps
   first, then the effort, then the runtime, a changed cell broken before
   its `was`.
4. The instructions, always (`proposalBody` with `expanded: true`,
   `Tool.tsx:524-529`): for each agent with instructions, a blank line,
   `lead's instructions` / `tester's instructions`, then its lines.
5. The body as markdown, after a blank line, whole. For a change whose
   body changed, no markdown body: the diff instead, headed
   `bugfix.md's body · 1 addition, 1 removal` (`proposal.ts:599-604`),
   drawn whole (`Tool.tsx:513-523`, `expanded: true`).
6. The answer's line (`savedLine`, `proposal.ts:501-516`):
   `Saved to .chord/teams/bugfix.md · /team run bugfix <job> hands it a job`
   in `success`, or `Not saved · the person will say what to change` dim.

Revised after review (F1 settled as (b)): the instructions, the body and a
change's diff are drawn whole, as `Tool.tsx` draws them. Only the table has
a folded and an opened layout, through ctrl+o. The folding helpers
`proposal.ts` still carries are not ported, and nothing here depends on
them: `bodyLines`, `changeRows` and the folded branch of `bodyChange`.
`proposalBody` is ported, because `/team show` of a saved team folds
through it (`keptLines`, 2.7, `Teams.tsx`). A proposal always calls it with
`expanded: true`.

Styles (`TableRow`, `Tool.tsx:589-640`): a mode that skips asking
(`bypassPermissions`, `full-access`, `proposal.ts:29-37`) in `warning`; a
changed effort's and mode's `was …` dim; a removed row (`-`) dim whole; the
role lines of an opened table dim. Marks on a change: `+` added, `~` changed,
`-` removed, in their own first column (`proposal.ts:168-172`).

Failed call (refused input): `⎿` the checker's first problem in `error`, as
any failed chord call (`chord.ts:178-186`); no box. A failed write: the
error under `⎿`, failed.

The box (`src/server/tools.ts:543-595`), the save box's layout:

- New: question `Save team bugfix?`; choices
  `1. Yes, for this project` + file `.chord/teams/bugfix.md`,
  `2. Yes, for every project` + file `~/.config/chord/teams/bugfix.md`
  (only when chord has a user directory),
  `3. No, tell claude what to change`. Esc picks the last; the hint is the
  save box's existing `Esc to tell claude what to change`.
- Change: `Replace team bugfix?`; `1. Yes, in .chord/teams/bugfix.md`,
  `2. No, tell claude what to change`.
- `claude` is the proposing session's runtime (`places.agent`).

120x40, a new team, the box open (headline accent while waiting, `⎿` body
dim but the table plain, `acceptEdits`/`default` plain; box in
`theme.focus`):

```text
 ⏺ Team(bugfix) · proposal
   ⎿  Fixes a bug end to end: a failing test first, then the fix, then a review of the diff.

      lead      claude · opus          default      Splits the job, says who edits which files, reports to main
      tester    claude · sonnet        acceptEdits  Writes the failing test, then proves the fix
      coder     codex · gpt-5.3-codex  auto         Writes the fix, in the files the lead names
      reviewer  claude · opus          plan         Reads the diff and edits nothing

      lead's instructions
      Read the job and the code it points at until you can name the cause and
      …
      How bugfix works
      1. The lead reads the job, finds the files involved, and names who may edit which before anyone starts.
      …

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Save team bugfix?                                                                                                    │
│                                                                                                                      │
│ ❯ 1. Yes, for this project      .chord/teams/bugfix.md                                                               │
│   2. Yes, for every project     ~/.config/chord/teams/bugfix.md                                                      │
│   3. No, tell claude what to change                                                                                  │
│                                                                                                                      │
│ Esc to tell claude what to change                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

80x24, folded table, role wrapping in its column (75 cells beside `⎿`:
name 8, runtime 21, mode 11, role 29):

```text
 ⏺ Team(bugfix) · proposal
   ⎿  Fixes a bug end to end: a failing test first, then the fix, then a
      review of the diff.

      lead      claude · opus          default      Splits the job, says who
                                                    edits which files, reports
                                                    to main
      tester    claude · sonnet        acceptEdits  Writes the failing test,
                                                    then proves the fix
      …
╭──────────────────────────────────────────────────────────────────────────────╮
│ Save team bugfix?                                                            │
│ …                                                                            │
```

The transcript scrolls under the box as the settings tool's does
(`permission_scroll.dart`); the box keeps its choices.

A change, 120x40 (`~` row; `bypassPermissions` in `warning`, `was
acceptEdits` dim):

```text
 ⏺ Team(bugfix) · change
   ⎿  Fixes a bug end to end: a failing test first, then the fix, then a review of the diff.

         lead      claude · opus          default                          Splits the job, says who edits which files, …
      ~  tester    claude · sonnet        bypassPermissions was acceptEdits  Writes the failing test, then proves the fix
      ~  reviewer  codex · gpt-5.3-codex  read-only was plan               Reads the diff and edits nothing
      …
      bugfix.md's body · 1 addition, 1 removal
      …diff…
      Saved to .chord/teams/bugfix.md · /team run bugfix <job> hands it a job
```

States: waiting on the person (box open, `✻ Waiting for you…`); saved;
not saved; refused input; write failed; change with and without a body
change; efforts present (`proposeefforts`) and their `was` (`proposeeffortsagain`);
narrow (role wraps; at the narrowest the opened layout).

### 2.5 `run_team` and `/team run`: the `Team(…)` row

Headline (`chord.ts:96-97`, `opened(false)`): `Team(bugfix) · claude · opus`,
the run's name as chord answered (`Team(bugfix 2) · …` for a second run),
then the lead's runtime, model and effort from the answer; no mode.
Under `⎿` (`chord.ts:257-261`): the job's lines, folded as a message, then
the selection lines for a selected run (2.10).

Refusals, a failed row in `error` (sources: `team_command.ts:121-132`,
`agents_host.ts:1787,1924,2160`):

- `No team named bugfx · /team lists them`
- `.chord/teams/triage.md is not a team chord can run: <problem>` (run_team,
  one line), and through `/team run`:
  `.chord/teams/triage.md is not a team chord can run:` then the problem on
  its own line.
- `This session has 8 agents open; close_agent one first`
- `This launch was cancelled; no run started.`
- `This session has closed`

`/team run <name> <job>` (`commands.ts`, `TeamShown` kind `ran`): the
command as typed, `› /team run bugfix …`, then the same `Team(bugfix)` row
as `run_team`'s, ended, with no turn of main's. Main hears
`ranNote` ahead of its next turn (`team_command.ts:110-115`):
`The person handed team bugfix this job: "<job>". Its lead is @bugfix and reports to you; send_message reaches it.`
Refusals for the typed form: `Which team? /team lists them`,
`/team run bugfix takes the job after the name`.

120x40:

```text
 › /team run bugfix Issue 214: a string at the end of a line loses its closing quote.

 ⏺ Team(bugfix) · claude · opus
   ⎿  Issue 214: a string at the end of a line loses its closing quote.
```

The fake's: `Team(bugfix) · fake · fake-large`. 80x24 wraps the job.

### 2.6 `/team` refusals and plain lines (`TeamShown` kind `said`)

Under the typed command, one `⎿` line per line, wrapped, `error` when
refused (`src/ui/teams/Teams.tsx:79-89`). Words (`team_command.ts:56-99`,
`teams.ts:31-36`, `agents_host.ts:2938`):

- `Which team? /team lists them`
- `/team run bugfix takes the job after the name`
- `/team new takes a few words about the work the team does`
- `/team has no edit; it takes list, new, show, run or stop`
- `Which run? The list under the prompt names them` (`/team stop` alone)
- `No run named bugfix is open · the list under the prompt names them`
- `No team named bugfx · /team lists them`
- `/team stop` done, plain (`stoppedLine`, `team_command.ts:138-147`):
  `Stopped bugfix: its lead is closed · /resume lists it`, or
  `Stopped bugfix: its lead, tester, coder, and reviewer are closed · /resume lists them`
  (`Intl.ListFormat('en')`, which puts a comma before `and`; the port's
  `_listed` in `agents.dart` does the same).

### 2.7 `/team show`

Where: `TeamEntry` in a new `lib/ui/teams/teams_view.dart` (from
`Teams.tsx`), drawn by `lib/ui/transcript/transcript.dart` for a
`team_shown` entry; the running table's layout in `lib/ui/teams/teams.dart`.

Saved, not running (`Teams.tsx:118-174`):

1. `bugfix · .chord/teams/bugfix.md`, cut at the edge.
2. The description, dim, wrapped.
3. A blank line.
4. The table, as a proposal's, unmarked (`proposalTable(agentRows(team), width, false, expanded)`).
5. The body folded: its first 3 non-blank lines where the window has 30
   rows or more, else 1 (`keptLines`, `Teams.tsx:36-38`), after a blank
   line; then `… +N lines (ctrl+o to expand)` dim. ctrl+o shows each agent's
   instructions and the whole body.

Running (`Teams.tsx:181-267`, `teams.ts:240-467`):

1. `bugfix · .chord/teams/bugfix.md · working 6m on "<the whole job, whitespace folded>"`,
   wrapped hard, never cut (CHD-471). A name that is a run's shows the
   run's (`bugfix 2`).
2. A selected run's selection lines (2.10), wrapped.
3. A blank line.
4. `runningTable`: name, `runtime · model · effort`, mode (`—` when
   unset), state, mark, then the latest headline. State words:
   `not opened` for a member not open, `idle` for an open agent with no
   state, else `<glyph> <words>` as the list says them (`● permission 12s`,
   `✻ working 41s`, `◦ idle 3m`, `✗ exited`). Mark: `✓ new reply`,
   `← new message`, `✗ turn failed`. Latest headline: `Edit(src/a.ts)`,
   `→ to @coder`, `← from @tester · claude` (`headlineText`,
   `messageHeadline`, `teams.ts:39-65`). State and mark in their tones
   (`working` accent dim, `warning`, `error`, `dim`), `not opened` dim.
   Nothing is cut: the headline wraps beside the row while that keeps 20
   cells, else under the row from the runtime's column; where the row's own
   columns are too wide, runtime then name wrap in a third of the width,
   then state and mark go under the row, then the mode with them.

120x40, running:

```text
 › /team show bugfix
   ⎿  bugfix · .chord/teams/bugfix.md · working 6m on "Issue 214: a string at the end of a line loses its closing
      quote."

      lead      claude · opus          default      ✻ working 8s                   → to @coder
      tester    claude · sonnet        acceptEdits  ● permission 12s               Bash(deno task test tests/parse)
      coder     codex · gpt-5.3-codex  auto         ✻ working 41s     ✓ new reply  Edit(src/parse/tokenize.ts)
      reviewer  claude · opus          plan         not opened
```

80x24, the headline under each row:

```text
 › /team show bugfix
   ⎿  bugfix · .chord/teams/bugfix.md · working 6m on "Issue 214: a string at
      the end of a line loses its closing quote."

      lead      claude · opus          default      ✻ working 8s
                → to @coder
      tester    claude · sonnet        acceptEdits  ● permission 12s
                Bash(deno task test tests/parse)
      …
```

The table is a snapshot taken when the command ran (`Teams.tsx:216`, held
in the scrolling transcript); it does not tick.

`/team show <run ID>` of a recorded selected run: `RecordedReceipt`
(2.10), `historical`.

Refusals: as 2.6 (`Which team? /team lists them`, `No team named …`, a
broken file's `… is not a team chord can run:` and problem).

### 2.8 The agents list, the header, the box and the status line

Where: `lib/ui/agents/agents.dart` (pure) and `agents_view.dart`;
`lib/session/window_agents.dart` (`namedChild`, `notifiedName`);
`lib/ui/app/window.dart` builds the rows.

Rows (`src/ui/app/sessions.ts:1022-1036`, `agents.ts:237-305,465-520`):

- A lead's runtime column starts `team · `: `team · claude · Opus`.
- Members follow their lead, `├─ ` / `└─ ` before the name, the tree dim and
  the name in the member's colour (`agents.ts:359,580`). The name column's
  width counts folded members as if unfolded, so folding moves no column
  (`agents.ts:472-482`).
- States and marks are the list's (CTUI-35): `● permission 12s`,
  `● input 12s`, `✻ working 41s`, `◦ idle 3m`, `✗ exited`,
  `✗ failed to start`; marks `✗ turn failed`, `✓ new reply`, `← new message`.
- Folding (`listRows`, `agents.ts:297-305`): when the rows, counted in
  their wrapped lines, exceed the limit (`agentsRowLimit`: 4 at 24 rows, 6
  at 40), every team but the one the picked agent is in folds to its lead's
  row. A lead with no member open does not fold.
- A folded lead: `team · claude · 4 agents` (the size where the model
  would be, `agents.ts:495-498`), state the most urgent of lead and
  members, naming a member (`● tester: permission 12s`,
  `✻ coder: working 1m`), or `◦ idle <since the last stopped>`
  (`teamState`, `agents.ts:205-235`); mark the first unseen of all of them,
  unnamed (`agentMark`, `agents.ts:160-177`).
- ↑ ↓ / j k walk the rows drawn; picking a member of a folded team unfolds
  it, as the picked agent's team never folds.

120x40, a team unfolded and a child after it:

```text
  ● tester needs your permission · ctrl+x a to go · ? for shortcuts                              Opus · 10% context used
    main         claude · Opus          ◦ idle 2m
    bugfix       team · claude · Opus   ◦ idle 40s        ✓ new reply
    ├─ tester    claude · Sonnet        ● permission 12s
    ├─ coder     codex · gpt-5.3-codex  ✻ working 41s
    └─ reviewer  claude · Opus          ◦ idle 1m
    parser       codex · gpt-5.3-codex  ✻ working 9s
```

80x24, folded (four rows; marks as their glyph alone where the words do
not fit):

```text
  ● tester needs your permission · ctrl+x a                    Opus · 10% used
    main         claude · Opus             ◦ idle 2m
    bugfix       team · claude · 4 agents  ● tester: permission 12s  ✓
    parser       codex · gpt-5.3-codex     ✻ working 9s
```

Two runs, both folded (`bugfix 2` named by `childName`'s numbering; run
numbers are never reused in the process, guide line 1463).

Header of a picked lead or member (`childLine`, `agents.ts:1015-1059`):

- lead: `bugfix · team · claude · Opus · opened by @main 6m ago`
- member: `tester · claude · Sonnet · bugfix's member · opened by @bugfix 6m ago`

(the name in its colour, the rest dim, as today's `childLine`).

The box's title (`src/ui/prompt/Prompt.tsx:513-532`,
`src/ui/app/App.tsx:736`): `tester · bugfix`, the name in its colour,
` · bugfix` dim, `bugfix` being the lead's name, so `tester · bugfix 2`
for the second run. Port: `PromptAgent`/`NamedTop` in
`lib/ui/prompt/named_top.dart` gain `team`.

Status line (`waitsNotice`, `src/ui/status/status.ts:193-230`, with
`namedChild`, `window_agents.ts:260-275`): `● tester needs your permission`;
when another open run has a member of the same name,
`● tester · bugfix 2 needs your permission`. `ctrl+x a` picks it (and so
unfolds its team).

Notification (`notifiedName`, `window_agents.ts:558-580`, `waitMessage`,
`src/notify.ts:291-303`): a member is `tester (bugfix)`:
`tester (bugfix) needs your permission`,
`tester (bugfix) asks for input: …`,
`tester (bugfix) is waiting for your input`.

The team part line (`teamPartLine`, `src/ui/transcript/message.ts:245-257`;
`TeamPartLine`, `Transcript.tsx:786-823`): at the top of a lead's or
member's transcript, `⏺` in the gutter, dim:
`bugfix's instructions for the lead · 58 lines (ctrl+o to expand)` /
`bugfix's instructions for tester · 41 lines (ctrl+o to expand)`;
opened, the `(… to expand)` goes and the part's text follows, dim,
indented 2. `1 line` in the singular. The message after it is the
`← from @main` / `← from @bugfix` row as any.

A lead's `Open(…)` rows (`chord.ts:62-73,88-95`):
`Open(tester) · claude · sonnet · high · acceptEdits`, the mode only on a
member's open.

`x` on a lead (`teamCloseArmedLine`, `src/ui/app/closing.ts:39-50`;
`sessions.ts:1559-1569`): when any of the team works or waits, the first
press arms: `bugfix and its 3 members are working · x again to stop them and close`
(`its member` for one); an idle team closes on the first press. On a member
it is today's child line (`agentCloseArmedLine`).

### 2.9 `← chord` notes

Delivered as messages from `chord` (`← from chord`), each a turn of the
recipient's:

- The person closed a member, to its lead (`agents_host.ts:2708-2715`):
  `The person closed coder (codex · gpt-5.3-codex, id 3c9e01b4). It takes no more messages; open_agent opens it again.`
  (a child not in a team keeps `open_agent starts another.`).
- The person closed a team, to main:
  `The person closed team bugfix: its lead (claude · opus, id 7f3a9c2e) and its members tester, coder, and reviewer. It takes no more messages; run_team starts it again.`
  (no `and its members …` with none open).
- A member's agent exited, to its lead (and any child's to its parent,
  `childEnded`, `window_agents.ts:338-370`):
  `coder's agent exited: <its last words>. open_agent opens it again.`
- A turn failed:
  `coder's turn failed: <error>. It is still open; send_message reaches it.`
- A lead's agent exited, to main:
  `bugfix's lead exited: <its last words>. Its members are closed; run_team starts the team again.`

### 2.10 Selection receipts and `Resources`

`get_budgets`'s row (`chord.ts:76-77,202-203`, `resource_lines.ts`):
headline `Resources`; under `⎿`, dim:

- `Read: 17:05:13 UTC · advisory snapshot`
- per window: `claude · 5h: 12% used · reset 18:05 UTC · models unknown`
  (label the duration `5h`/`7d`/`90m`, or the window's name when it has
  none; `usage unknown`; `reset unknown`; the reset's UTC date ahead when
  not the read's day; `models opus, sonnet`, `models none`,
  `models unknown`)
- `codex: no windows reported`
- `codex: unavailable · <reason>` (the answer's words)
- `No providers read.`
- an answer that does not parse: `Recorded in an older format; not shown.`

No ctrl+o view; a failed call is today's failed row. CHD-548 has the
mocks at 120x40 and 80x24 and the states (running, read, partial, all
unavailable, empty, error, narrow); the port draws them as they are.

`list_teams`'s row (`chord.ts:98-99,262-268`): `List teams`, `⎿ 3 teams · bugfix, review, docs`
(`1 team`; `+N more` past four).

Selection lines (`selection_lines.ts`), under a selected run's `Team(…)`
row and in `/team show`'s running form:

- `Selection: agent-selected · this run`
- `Reason: <reason>`
- `Warning: <warning>` each
- `Billing: unknown · advisory`
- `Planned for this run:`
- per role: `<name>[ (lead)]: <runtime> · model <m> · effort <e> · mode <md>`,
  unknowns `runtime unknown`, `agent default (unconfirmed)`; then
  `Actual: not opened · configuration unconfirmed`, or
  `Actual: <state> · session runtime <r> · model <m> · effort <e> · mode <md>`;
  then `<name>: <note>` where it has one
- only for a receipt recorded with a read: `Read 2026-10-27 13:40:00 UTC · advisory`
- folded: `ctrl+o for saved definition and changes`; opened:
  `Run: <run id> · saved definition: <name> (<place>)`, then per role
  `<name> saved: <configuration>` and `Changes from saved: none` or the
  fields.

A refused selected run: the error first, then these lines
(`chord.ts:179-186`).

`RecordedReceipt` (`src/ui/teams/RecordedReceipt.tsx`): a heading
`Recorded Team receipt (bugfix)`, then under `⎿`:
`Recorded by Chord · current state unknown` (`· historical observation`
from `/team show <run ID>`), `Recorded: time unknown`, the job's lines, the
selection lines as recorded (`Actual at recording: …`), and
`Recorded failure: <error>` in `error` when it failed. The first two lines
and the `Read`/`Billing:`/`Run:` lines dim. Shown for receipts the
transcript holds with no ACP call linked (`recorded_receipts.ts`).

`/resume` row of a recorded attempt with no prompt:
`Team attempt: bugfix` (`src/session/sessions.ts:244`).

### 2.11 Resume

The past is drawn from main's record (the `Team(…)` rows, the `← @bugfix`
reports, the `← chord` lines). The left-open note (`leftOpenLine`,
`agents.ts:1062-1097`), dim, after the past:

- `parser (codex) and team bugfix (4 agents) were open when this session was left and are not reopened · /resume lists them · /team run bugfix starts the team again`
- one run alone: `team bugfix (4 agents) was open when this session was left and is not reopened · /resume lists them · /team run bugfix starts the team again`
- two runs: `team bugfix (3 agents) and team bugfix 2 (3 agents) were open … · /team run bugfix starts the team again`
- two teams: `… · /team run bugfix and /team run docs start the teams again`

Each run is one item with its count; each team's way back is named once.

### 2.12 `chord acp`'s `/team`

Where: `lib/session/upstream_commands.dart` (texts) and
`lib/session/upstream.dart` (`chordCommands`, `commandOf`); the server's
prompt handler answers.

Command list (`src/session/upstream.ts:126-139`), revised after review:
the original's list is `[team, new]`, so `team` goes first in the port's
`chordCommands`, ahead of the `new` entry already there. Its entry:
`{name: 'team', description: 'Show and run teams of agents', input: {hint: 'list | run <name> <job> | show <name> | stop <run> | new <words>'}}`.

Texts (`src/session/upstream_commands.ts`), plain, `·` between parts, a
file's text on one line (`oneLine`):

- `/team list` (`teamsText`, 93-116): `Teams:` blank line, `- bugfix · 4 agents · claude, codex · this project · working 6m · <description>`
  per team (`- triage · not read: <problem>` for a broken file; `2 runs`
  for more than one), or `No teams yet. /team new and a few words about the work makes one.`;
  then `Runs open:` with `- bugfix 2 · team bugfix · working 3m` per run, or
  `No run is open.`; then the saved line (2.2); then, with teams,
  `/team show and a name shows a team; /team run, a name and a job starts one.`
  Blocks are separated by a blank line.
- `/team show <name>` (`teamText`, 128-140): `bugfix · .chord/teams/bugfix.md`,
  the description, `Agents:` and
  `- lead · claude · opus · high · default · Splits the job, …` /
  `- tester · claude · sonnet · acceptEdits · Writes …` (unset parts left
  out).
- A run (`runText`, 143-177): `bugfix 2 · .chord/teams/bugfix.md · working 3m on "<job>"`,
  the description, `Agents:` with `- lead (bugfix 2) · open · …` and
  `open`/`not open` per member; no state, mark or headline.
- A selected run, refused (`selectedRunRefusal`, 180-185):
  `bugfix is a selected run, and only chord's window shows its receipt: chord -r with this session's id, then /team show 7f3a9c21 there`
  (the port's CLI takes `-r`, `lib/cli.dart:98`).
- `/team run` (`startedText`, 191-196):
  `Team bugfix started. Its lead is bugfix 2; /team stop bugfix 2 ends it.`
  and the effort note as its own block.
- `/team stop` (`ACP_TEAM_WORDS`, 20-25):
  `Stopped bugfix 2: its lead is closed · chord with its agent's name and -r lists it`,
  `Stopped bugfix 2: its lead, developer, and tester are closed · chord with each agent's name and -r lists them`,
  `Which run? /team lists them`, `No run named bugfix is open · /team lists them`.
- Refusals as the guide's list (guide lines 862-878), including
  `/team takes text alone, and this prompt had other blocks beside it. Nothing ran; send the command by itself.`
  and `This session has closed`.
- `/team new <words>` is a normal turn with `newTeamPrompt(words)` as the
  agent's text and the typed words as the user's (`acp_agent.ts:2004-2010`).
  Its `propose_team` asks the client through `session/request_permission`
  titled `Team(bugfix)`, the file's text as detail, with the save box's
  options (runtime's draft).

## 3. Where each piece sits, and whose state it is

| Piece | Port file (new or extended) | Pure logic | Widget's own state | Passed in by the app |
| --- | --- | --- | --- | --- |
| `/team` words, refusals, notes | `lib/session/team_command.dart` (new) | all | — | — |
| Picker rows, hint, line, running table | `lib/ui/teams/teams.dart` (new) | all | — | — |
| Teams picker | `lib/ui/pickers/pickers.dart` | — | highlight, choices read once | listing, columns, rows, room |
| `/team show`, `said`, `ran` entry | `lib/ui/teams/teams_view.dart` (new) | via `teams.dart`, `proposal.dart` | — | `TeamShown`, expanded, width |
| Recorded receipt | `lib/ui/teams/recorded_receipt_view.dart`, `recorded_receipts.dart` (new) | selection, which receipts | — | call, historical |
| Proposal table, body, saved line | `lib/ui/transcript/tools/proposal.dart` (new), `tool.dart` | all layout | — | call, expanded, window rows |
| Resource and selection lines | `lib/ui/transcript/tools/resource_lines.dart`, `selection_lines.dart` (new) | all | — | answer |
| Headlines and lines of the new tools | `lib/ui/transcript/tools/chord.dart` | all | — | call |
| Team part line | `lib/ui/transcript/message.dart`, `transcript.dart` | `teamPartLine` | — | part, expanded, key |
| Agents list: `team ·`, branches, folding | `lib/ui/agents/agents.dart`, `agents_view.dart` | `teamRows`, `teamState`, `listRows` | — | rows, limit, picked |
| Header, left-open note | `lib/ui/agents/agents.dart` (`childLine`, `leftOpenLine`) | all | — | child, now |
| Box title | `lib/ui/prompt/named_top.dart` | — | — | name, colour, team |
| Status line, notification names | `lib/session/window_agents.dart` (`namedChild`, `notifiedName`) | all | — | roster |
| `x` arming | `lib/ui/app/closing.dart` | `teamCloseArmedLine` | — | members, key |
| `← chord` notes | `lib/session/window_agents.dart`, `agents_host.dart` | sentences | — | — |
| `/team` in the slash list, completion | `lib/ui/prompt/commands.dart`, `state.dart` | `teamQuery`, `teamItems`, `submitted` | — | `TeamNames` |
| `/cost`'s team rows | `lib/ui/transcript/spend_table.dart`, `spend.dart` | `teamRows` | — | parts |
| `chord acp`'s `/team` | `lib/session/upstream_commands.dart`, `upstream.dart` | all texts | — | listing, runs |

The `TeamShown` value (`said`, `ran`, `show` with an optional `running`,
`receipt`) is a transcript entry of main's, folded by the transcript
reducer (`team_shown`), so it is plain data and tested without a widget.

`/cost`'s table (guide lines 604-606, `src/ui/transcript/spend_table.ts:189-220`):
a team run's row is its name with the sum, its note
`team run: bugfix $0.12 · tester $0.40 · coder not reported`
(`team run, ended: …` once closed), then the members' tasks under it with
their owner. The port's `spend.dart` and `spend_table.dart` say team runs
come with their parts; this is that part.

## 4. Framework

Nothing new expected from the interface side: the picker, the save box,
the diff view, the table-free column text and folding are in place. Two
layouts the original does with `@cliffy/table` (the proposal table and the
running table, each row its own table with fixed column widths and words
wrapping inside a column) need a column-wrapping text helper; whether
`TextLayout` and the table widths already in `lib/` (`test/foundation`,
`example/fold.dart`) cover it is framework's question. The port's layout
functions should return lines and spans as `proposal.ts`/`teams.ts` do, so
they test without a widget.

## 5. Keys

| Key | Where | Does | Action / panel |
| --- | --- | --- | --- |
| `1` `2` `3`, ↑ ↓ + Enter, Esc | save box | save here / every project / say what to change | existing save box, not bindable (as the permission box) |
| ↑ ↓, Enter, Esc | teams picker | move / `/team run <name> ` into the draft / close | existing picker keys; the hint names Enter and the close key |
| ↓, ↑ ↓, j k | agents list | walk lead and members, the picked team unfolded | `history:previous`/`next`, unchanged |
| `x` | agents list | close the picked agent; on a lead its team, armed twice while busy | `agents:close`, unchanged |
| `ctrl+x a` | anywhere | reach a member's wait, unfolding its team | `session:attention`, unchanged |
| `ctrl+o` | transcript | open the proposal table's roles, `/team show`'s body and instructions, the part line, the receipt's saved definition | `app:toggleTranscript`, unchanged |
| Tab / Enter on a `run` completion | prompt | completes `/team run <name> ` | completion's own |

No new action, so nothing new for `Actions`, the keymap or the shortcuts
panel.

## 6. The shortcuts panel

Unchanged. The original's panel line for `x` is
`x to close an agent, stop background` (`src/ui/shortcuts/keys.ts:171`),
which the port already has (`lib/ui/shortcuts/keys.dart:91-96`). M5's
`x to close an agent or a team, or stop a monitor` was superseded by the
background view (CTUI-36 in the port), and src holds.

## 7. Captures

Original: `(cd ../chord && bun dev chord --fake --qa ctui37-<state>)` in a
tmux window of 120x40 and of 80x24. `--qa` makes its directory afresh, so
before the scenario's prompt copy the fake's team into it:
`../chord/tests/fixtures/teams/fake/bugfix.md` to `.chord/teams/bugfix.md`
(teams are read when needed, never at start, so the copy counts at once).
Children on the fake: `CHORD_FAKE_CHILD_RUNTIME=fake` where the port's tests
set it.

Port (revised after review): today `example/chord/tool/dev.dart --fake`
cannot take these captures. It sets the repository root as the working
directory and its own `XDG_STATE_HOME` (`tool/dev.dart:125-130`), so a
`.chord/teams/bugfix.md` staged in a capture directory is never read. It
also does not force fixture resources. The port's captures therefore depend
on **runtime's dev-runner unit**. That unit makes `dev.dart chord --fake`
take a staged capture directory as its working directory, with isolated
state and config there, and makes it read resources from the fixture source
(as the original's `CHORD_RESOURCE_FIXTURE=true`, with the case chosen as
`CHORD_FAKE_RESOURCE_CASE` chooses it), with a regression test. The route
is then `dart run example/chord/tool/dev.dart chord --fake` through that
unit's capture-directory option (its exact flag is runtime's). Before the
scenario's prompt, `.chord/teams/bugfix.md` is copied into that directory,
as for the original. No port capture is taken before that unit lands.

Text captures with
`capture-pane -p`, colour with `-p -e` (`.ansi`). Directories relabelled
`~/project`, as CTUI-36's NOTE.md does. Files:
`docs/design/evidence/CTUI-37/<unit>-<state>-{original,port}-{120x40,80x24}.{txt,ansi}`.

| State | Scenario and keys |
| --- | --- |
| slash list | type `/te` |
| picker, teams and one broken | add a broken `.chord/teams/triage.md`; `/team` |
| picker, running | after `team`: `/team` |
| picker, empty | no team file; `/team` |
| picker Enter | `/team`, Enter: the draft `/team run bugfix ` |
| completion | `/team show `, `/team stop ` with a run open |
| `/team new` | `CHORD_FAKE_SCENARIO=propose`, then `/team new a team that fixes bugs` (the fake plays a scenario only for a prompt that is its name, else the default) |
| proposal, box open | `propose` |
| saved | `propose`, 1 |
| not saved | `propose`, Esc |
| change | after a save, `proposeagain` |
| efforts and `was` | `proposeefforts`, 1, then `proposeeffortsagain` |
| ctrl+o on a proposal | `propose`, ctrl+o |
| `run_team` | `team` |
| second run, both folded | `team`, then `team2` |
| list unfolded | `team` at 120x40 |
| list folded | `team` at 80x24 |
| member asking, status line, asker row | `team` until `tester` asks (`teamtester`) |
| member picked: header, part line, box title | ↓ to `tester` |
| lead picked: `Open(…)` rows | ↓ to `bugfix` (`teamlead`) |
| ctrl+o on the part line | member picked, ctrl+o |
| `x` armed on a lead | `team`, ↓ to `bugfix`, `x` |
| team closed by `x`, `← chord` to main | `x` again; back to main |
| member closed, `← chord` to lead | ↓ to `coder`, `x` |
| member exited / turn failed | `teamcoder` / `teamreviewer` (the fake's failing members) |
| `/team show bugfix`, saved | `/team show bugfix` with no run |
| `/team show bugfix`, running | `team`, then `/team show bugfix` |
| `/team stop bugfix` | `team`, `/team stop bugfix` |
| `/team` refusals | `/team run bugfx x`, `/team run bugfix`, `/team edit`, `/team stop nope` |
| `/team run bugfix <job>` | typed, then a prompt to main to show `ranNote` was heard |
| member's task | `teamtask` |
| resume note | `team`, `/clear`, `/resume`, Enter |
| `Resources` | `CHORD_RESOURCE_FIXTURE=true`, `CHORD_FAKE_RESOURCE_CASE` = `normal`, `partial`, `timeout`, `unavailable`; prompt `resources` |
| selected run, receipt, `/team show <run ID>`, `Team attempt:` | `../chord/tests/fixtures/selected_team_qa.ts` cases `normal`, `members`, `refused`, `soft`, `long`, `receipt`, `late`, as `tests/ui/app/selected_team_test.tsx` runs them; scenarios `selectedteam`, `budgetawareteam`, `savedteamplain` |
| `/cost` with a team | `team`, then `/cost` |
| `chord acp` `/team` | no capture; the port's ACP tests check the texts against the original's tests |

The port's capture directory and state have no home path in them; NOTE.md
records the head each capture was taken at, as CTUI-36's does.

## 8. Where M5-teams.md and src differ (src holds)

1. **The proposal is drawn whole.** M5 folds the body after its first
   lines with `… +16 lines (ctrl+o to expand)`; src draws the members'
   instructions and the body always (`Tool.tsx:524-529`, CHD-422), and
   ctrl+o only lays the table out opened.
2. **A change's diff is whole.** M5 folds it to five changed rows at 30
   rows; src draws it whole (`Tool.tsx:513-523`), as the guide says.
3. **Roles wrap, not cut.** M5 cuts the role, then the model; src wraps
   both in their columns (CHD-422/CHD-333) and lays the table out opened
   where even that does not fit.
4. **Efforts.** src adds an effort column (CHD-356) where any agent sets
   one, `high was medium` for a changed effort, effort in `/team show`'s
   rows, in `Open(tester) · claude · sonnet · high · acceptEdits`, and in
   `chord acp`'s rows.
5. **States in the list.** M5 has `✓ replied 40s ago`; src has a state
   always (`◦ idle 3m`) and unseen marks in their own column
   (`✓ new reply`, `← new message`, `✗ turn failed`, CHD-471). A folded
   team's mark is the first unseen of all, unnamed.
6. **What stays unfolded.** M5: the team under the `❯`. src: the team of
   the picked agent (`teamRows`); in the list the `❯` is the pick, so it
   reads the same, and a member picked from `ctrl+x a` unfolds its team.
   Rows are counted in their wrapped lines.
7. **`/team show` running.** M5 cuts the job with `…` and has one state
   column; src wraps the whole job, adds the mark column and
   `runtime · model · effort`, wraps the headline (nothing cut, CHD-471),
   and adds selection lines for a selected run. `/team show` of a saved
   team keeps 3 body lines at 30 rows, else 1, and ctrl+o adds the
   instructions.
8. **`/team show <run ID>`** and recorded receipts, `Team attempt:` in
   `/resume`: not in M5 (CHD-533).
9. **`/team stop`'s line** lists with a comma before `and`
   (`its lead, tester, coder, and reviewer are closed`) and has the
   `its lead is closed · /resume lists it` form; M5 writes
   `its lead and tester, coder and reviewer`.
10. **The instructions line** exists for the lead too:
    `bugfix's instructions for the lead · 58 lines`.
11. **The limit refusal** says `close_agent one first`, not `close one
    first`.
12. **The turn-failed note** (`… It is still open; send_message reaches
    it.`) is src's addition to M5's exit note; a member closed by the person
    ends `open_agent opens it again.`, a plain child `starts another.`
13. **The shortcuts panel** keeps `x to close an agent, stop background`;
    M5's `x to close an agent or a team, or stop a monitor` is gone.
14. **The picker** narrows below 100 columns (`NARROW`), drops the path of
    a broken file there, and has `this project · hides every project's`.
15. **Names** may not hold `"` or control characters; `list_teams` has a
    top-level `runs` (runtime's); `/team choose` is gone (owner).
16. **The ACP command list** says `Show and run teams of agents`, not the
    window's `Describe, keep and run teams of agents`.

## 9. Port differences

None proposed. Everything above is the original's words and layout.
Where the framework cannot draw a layout exactly (section 4), framework
says so and the lead asks.

## 10. Units for ship, in order

Each unit's tests are the original's named tests ported, plus a tester
check at 120x40 and 80x24 against the capture of the same state.

1. **Words and logic, no screen.** `team_command.dart`, `teams.dart`
   (picker rows, hint, line, `runningWords`, `pickedDraft`,
   `runningHeader`, `runningTable`), `proposal.dart`,
   `resource_lines.dart`, `selection_lines.dart`. Tests from
   `tests/session/team_command_test.ts`, `tests/ui/teams/teams_test.ts`,
   `tests/ui/transcript/tools/proposal_test.ts`, `resource_lines_test.ts`,
   `selection_lines_test.ts`.
2. **The new tools' rows.** `chord.dart` headlines and lines for
   `list_teams`, `run_team`, `propose_team`, `get_budgets`, a member's
   `Open(…)`; the `Proposal` body and `TableRow` in `tool.dart`, with the
   save box wired (runtime's tool). Tests: `chord` tool tests for each
   headline and line, widget tests for the proposal at both sizes with the
   table folded and opened, and with the body and diff always whole (revised
   after review: F1 (b)); a change with marks and `was`, a warning mode,
   saved/not saved lines; `Resources` in each CHD-548 state.
3. **`/team` in the window.** Slash list entry, completion (`teamQuery`,
   `teamItems`, `submitted`), the picker, `TeamEntry` (`said`, `ran`,
   `show` saved and running), `/team talks to main`, `ranNote`. Tests from
   `tests/ui/teams/Teams_test.tsx`, `tests/ui/prompt` command tests,
   `tests/ui/app/team_launch_test.tsx`; picker at 120x40 and 80x24, empty,
   broken highlighted, Enter's draft.
4. **The team in the list.** `team ·`, branches, folding, `teamState`,
   folded mark, header `childLine` branches, part line, box title,
   status line `namedChild`, notification `notifiedName`,
   `teamCloseArmedLine`, the `← chord` sentences. Tests from
   `tests/ui/agents/Teams_test.tsx`, `TeamsList_test.tsx`,
   `TeamsAsking_test.tsx`, `agents_test.ts`'s team cases,
   `tests/ui/app/closing` tests, `window_agents` tests.
5. **Receipts and resume.** `RecordedReceipt`, `recorded_receipts`,
   `/team show <run ID>`, `Team attempt:` in `/resume`, `leftOpenLine`'s
   team items. Tests from `tests/ui/teams/RecordedReceipt_test.tsx`,
   `recorded_receipts_test.ts`, `tests/ui/app/selected_team_test.tsx`,
   `AgentsResumed_test.tsx`'s team cases.
6. **`/cost`'s team rows.** `spend.dart`, `spend_table.dart`. Tests from
   `tests/ui/agents/TeamsSpend_test.tsx` and the spend table's team cases.
7. **`chord acp`'s `/team`.** `team` in `chordCommands`, the texts, the
   forms answered. Tests from `tests/session/upstream_commands_test.ts`
   and `tests/acp_agent_test.ts`'s `/team` cases, in-memory, including that
   the command list is `[team, new]` in that order.

Units 2 to 7 need the runtime's host pieces (files, runs, `toolsOf`,
records) under them; the lead orders them against runtime's units. Revised
after review: every port capture (section 7) also depends on runtime's
dev-runner unit (a staged capture directory with isolated state, fixture
resources), so that unit comes before the first unit whose tester check
compares captures.

## 11. Questions for the owner

Revised after review.

1. **Claude in `Resources`. This is a question only if the owner does not
   take runtime's Q1(A).** If the owner takes Q1(A), the port reads
   Claude's usage, and the block is the original's. If not, the port answers
   Claude as unavailable. The default `agents`, `['claude', 'codex']`,
   stays as the original has it, and the block shows
   `claude: unavailable · <reason>`. The reason must say why honestly,
   e.g. `claude: unavailable · this build has no reader for Claude Code`.
   The owner confirms the words.
2. None else from the interface: every word and layout above is the
   original's.
