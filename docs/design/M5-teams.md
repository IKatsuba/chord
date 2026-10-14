# M5 — Teams, on screen

M5 lets a person describe in words how a piece of work should be done, keep
that as a **team**, and later hand the team a job and watch it get done
without driving each agent. A team is a **lead** and its **members**. The lead
is a long-lived agent of the person's session, as M4's are (CHD-167). The
members are the lead's own long-lived agents. The lead reports to the session
that gave it the job, and the person can look in on any of them through the
agent list. A team needs no daemon and no task board: it lives while the
window is open.

Everything here reuses M4: `open_agent`, `send_message`, `close_agent`, the
agent list under the prompt, the `←` and `→` rows with `@name` (CHD-225,
CHD-239), the permission box that opens when its agent is picked, the `x`
close, and CHD-171's resume. M5 adds the team file, the `/team` command, three
tools for the session the person opened, and one more level in the list.

The owner's binding decisions (CHD-240) are taken as given:

1. A team's lead may start members. Members start none. That is the only
   extra level.
2. Every member works in the session's directory, with no worktrees. Who
   edits which files, and when, is written in the team's own instructions and
   kept by the lead. chord's code does not enforce it.
3. A member's permission requests reach the person. The team file sets each
   member's starting mode, the way `/new` and the settings files set one per
   agent. There is no new permission system.
4. A team lives while the window is open. `--resume` brings it back the way
   M4 brings children back.

The owner then answered this design's open questions (2026-10-09, CHD-240),
with one principle over all of them: **keep teams flexible and restrict as
little as possible in code; let the agents agree among themselves rather
than have chord enforce rules.** The answers:

5. `--resume` does not reopen a team. The past is drawn, the closing note
   names the team, and `/team run` starts it again.
6. A member talks to its lead **and to the other open members of its team**,
   directly, with no limit on how many messages they trade (as for M4).
7. A lead opens the file's members, on the file's runtime, model and mode,
   **and task agents**. `spawn_task` is every agent's, members included, as
   an ordinary subagent is. It is not reserved for the lead.
8. Each message from the lead starts a turn of main's, with no flag. The
   lead decides when to write to main. Nothing in chord counts or gates
   reports.
9. A team may run **any number of times** in one window, as `bugfix`,
   `bugfix 2`, …. The runs agree on files among themselves, as members do.
10. Closing a parent (main, a tab or a team's lead) closes all its children:
    CHD-218's option A, confirmed and closed.

The mocks are in `evidence/CHD-240/mock/`, one file per state, at 120×40 and
80×24. I laid them out to exact widths from the real rows of
`deno task chord:fake` (`evidence/CHD-240/today/`: the `agents` scenario's
list, a child picked, the permission box and `/status`). The directory is
shown as `~/src/app`, and the agent the person talks to is `claude · Opus`.
Text captures cannot show colour, so colours are described beside each mock.

## The decisions, in short

| Question | Answer |
| --- | --- |
| The team file | Markdown with YAML frontmatter, `<name>.md`, in `.chord/teams/` for the project and in `teams/` beside the user's `settings.json` (`~/.config/chord/teams/`) for every project. On a name clash the project's file wins. The frontmatter holds the structure: description, lead, members, and each agent's runtime, model, mode and instructions. The body is how the team works, and every agent of the team gets it. Read with `@std/front-matter`, checked by zod. |
| A team's name | The file's name: `[a-z][a-z0-9-]{0,23}`, never `main` or `chord`. It is also the lead's name in the list and in messages (`← @bugfix`). A second run of the same team is `bugfix 2`, numbered as M4 numbers a second `codex`. |
| `/team` | `/team` (or `/team list`) opens the teams picker. Then `/team new <words>`, `/team show <name>`, `/team run <name> <job>` and `/team stop <name>`. A team is changed by asking the agent in plain words (owner, 2026-10-09: no `/team edit`). |
| Making a team | The session's agent proposes it through a new chord tool, `propose_team`, and the person saves it from a choice box shaped like the permission box: **this project / every project / tell the agent what to change**. chord writes the file, not the agent. |
| Handing over a job | **Both ways, one path.** `run_team {team, job}` is a tool on chord's server, so "hand it to bugfix" in plain words works. `/team run <name> <job>` does the same without spending a turn of main's. Both draw one `⏺ Team(bugfix) · claude · opus` row with the job under it. |
| What a lead may open | The file's members and task agents (owner, answer 7). The lead's `open_agent` takes `{member, prompt}`, and chord starts the member on the file's runtime, model and mode. `spawn_task` is every agent's, the lead's and each member's, as main's is. |
| Who talks to whom | The lead talks to `main`, to its members and to the leads of other runs in the session. A member talks to its lead and to the other open members of its team, directly (owner, answer 6). No limit on how many messages they trade. |
| The list | The lead is a row under `main`, with `team ·` before its runtime. Its open members are nested under it with CHD-149's `├─`/`└─`. When the whole list does not fit its row limit, a team folds to its lead's row, which carries the team's most urgent state and names the member (`● tester: permission 12s`). |
| A member picked | It works exactly like an M4 child. The box is titled `tester · bugfix`, and the permission box opens with `tester asks`. |
| Reports | M4's messages: `← @bugfix · claude` in main's transcript, and each one starts a turn of main's (owner, answer 8). The lead decides when to write: the team file's "Reporting" section suggests a decision needed, the job done, or the job not doable. chord counts and gates nothing. |
| Status | Without asking a model: the list's rows and `/team show bugfix`, which adds each agent's state and what it is on right now. By asking: the person asks main, which messages the lead, or picks the lead and asks it directly. |
| Closing the lead | Closes the team. `x` on the lead's row (armed while any of the team is busy), `/team stop`, or main's `close_agent`. chord tells main as M4 does. Closing a parent (main, a tab or a lead) closes all its children: CHD-218's option A, confirmed by the owner. |
| A member's agent exits | chord tells the lead (`← chord`), so it does not wait for ever on a member that is gone. This is new, and M4 children's parents get it too. |
| `--resume` | As CHD-171 has it (owner, answer 5): the past is drawn, the team is not reopened, and the closing note names it, with `/team run bugfix` as the way back. |
| Several runs | Any number of runs of one team per window (owner, answer 9): `bugfix`, `bugfix 2`, …. Each run is a lead of main's with its own members. A new run's lead is told which runs are already open, and the leads agree on files among themselves. chord refuses nothing for it. |

## 1. The team file

### Where it lives

- `.chord/teams/<name>.md` in the project (the working directory, where
  `.chord/settings.json` already lives).
- `teams/<name>.md` beside the user's `settings.json`, in chord's config
  directory (`~/.config/chord/teams/` on the usual setup), for every project.
- On a name clash the project's file wins, the same way the project's
  settings sit on top of the user's. `/team` lists the winner and says
  `this project · hides every project's` in its place column.
- chord reads them when `/team`, `run_team` or `list_teams` needs them, never
  at start, so a file saved in another window or by hand counts at once.

### The format

The frontmatter is for what chord reads: who the agents are and how each one
starts. The body is for what the agents read: how the team works. This splits
along the same line as Claude Code's own subagent files (`.claude/agents/*.md`,
YAML frontmatter and a markdown body), so the shape is already familiar to
someone who wrote one. The file's own name is the team's name, so there is no
`name` key that could disagree with it.

A full example, `.chord/teams/bugfix.md`:

```markdown
---
description: Fixes a bug end to end — a failing test first, then the fix, then a review of the diff.
lead:
  agent: claude
  model: opus
  mode: default
  instructions: |
    Read the job and the code it points at until you can name the cause and
    the files involved. Then open tester first, and coder only once tester's
    test fails for the bug's own reason. Open reviewer last, on the diff.
    Close each member when its part is done. You edit nothing yourself.
members:
  - name: tester
    role: Writes the failing test, then proves the fix
    agent: claude
    model: sonnet
    mode: acceptEdits
    instructions: |
      Write the smallest test that fails because of the bug, not for any
      other reason, and run it to show that. Afterwards run the suite the
      lead names and report what fails, word for word.
  - name: coder
    role: Writes the fix, in the files the lead names
    agent: codex
    model: gpt-5.3-codex
    mode: auto
    instructions: |
      Make the failing test pass with the smallest change that fixes the
      cause. Do not touch tests. Report the files you changed and why.
  - name: reviewer
    role: Reads the diff and edits nothing
    agent: claude
    model: opus
    mode: plan
    instructions: |
      Read `git diff` and the test. Say what is wrong, or that nothing is.
      Never edit a file.
---

# How bugfix works

1. The lead reads the job, finds the files involved, and names who may edit
   which before anyone starts.
2. tester writes a test that fails for the bug's own reason. It edits
   `tests/` only, and reports the failure.
3. coder fixes the code so that test passes. It edits only the files the
   lead named for it, and never `tests/`.
4. reviewer reads the diff and edits nothing. If it finds a problem, the
   lead hands it back to coder.
5. tester runs the whole suite once more, and the lead reports to main.

## Who edits what

- One writer per file at a time. Before a member starts, the lead tells it
  which files are its own, and no other member edits them until it reports
  that it is done.
- A member that needs a file it does not own asks its owner directly, and
  tells the lead what the two of them agreed. It never edits the file "just
  quickly".
- Only one member at a time runs anything that writes outside its files, such
  as formatters, `--fix` and code generators.
- Another run of a team may be working in this directory. Before anyone
  starts, the lead asks the other runs' leads which files they hold, and
  keeps out of them.
- Nobody commits. The person commits.

## Reporting

The lead writes to main when it needs a decision only the person can make,
when the job is done, and when the job cannot be done. Nothing else: main
does not need every step.
```

The "Who edits what" section is how a team stays out of its own way in one
directory (owner decisions 2, 6 and 9). It is plain text that every agent
of the team reads, and the agents keep to it among themselves. `propose_team`'s description asks the
proposing agent to always write such a section, and a "Reporting" one too, so
a new team never lacks them. chord does not check that they are there: the
body is the team's own business.

### The check (zod)

In `src/teams.ts` (new), as `settings.ts` checks its files:

- **description**: a string, one line, 1–200 characters. The picker shows it,
  and `list_teams` gives it to the agent that chooses a team.
- **lead**: a strict object.
  - `agent`: a runtime chord knows (the registry's, `clis.ts`'s or a
    settings file's), checked by name when the file is read.
  - `model` (optional): a model id, as `list_agents` gives them. The
    runtime's own model is used if it is left out.
  - `mode` (optional): a mode id, as `list_agents` gives them. The runtime's
    own starting mode is used if it is left out.
  - `instructions` (optional): text.
- **members**: an array of 1–8 strict objects, the same as the lead plus:
  - `name`: `[a-z][a-z0-9-]{0,15}`, unique in the team, and not `main`,
    `chord` or the team's name.
  - `role`: one line, 1–80 characters. It is the column in `/team show` and
    the proposal.
  - `instructions`: required for a member.
- **the body**: not empty.

Model and mode ids are checked only when the agent opens, against what its
runtime offers. That is the moment M4 checks a model already, and checking
earlier would mean starting every runtime just to read a file. A refused open
is a failed `Open(…)` call in the lead's transcript, with chord's answer
(`codex has no mode yolo · read-only, auto, full-access`), so the lead can
tell main. For the proposing agent to pick real ids, **`list_agents` gains
each runtime's modes beside its models.** ACP gives both in the same
`session/new` answer, so this costs nothing extra.

A file that fails the check is still listed, with its first problem
(`✗ not read: members.1.agent is missing`). Running it is refused with the
problem (`80-8-broken.txt`). Problems are worded in
zod's paths, as the settings files' problems are.

**Library.** `jsr:@std/front-matter` (`extract` from `@std/front-matter/yaml`,
which parses with `@std/yaml`) for reading. I tried it with zod 4 on a team
file under `deno run` and from a `deno compile`d binary. Both parsed the
example, block scalars included, and a broken YAML flow gave a line and
column. Writing the file is `@std/yaml`'s `stringify` for the frontmatter
between two `---` lines, with the body after. `@std/front-matter` has no
writer, and `@std/yaml` is the parser it already uses. Passed over:
`gray-matter`, which is CommonJS on js-yaml 3 and has had no release since
2023, and the npm `front-matter`, which only reads.

## 2. `/team`

`/team` is chord's own slash command, like `/clear`. It goes in the slash list
with `Describe, keep and run teams of agents`. The words after it go with it,
as `/new codex` does (decisions, 2026-10-08).

| Form | Does |
| --- | --- |
| `/team`, `/team list` | The teams picker (`120-2-list.txt`) |
| `/team new <words>` | Asks the session's agent to propose a team for the work the words describe |
| `/team show <name>` | The team as a `⎿` report. While it runs, each agent's state too (part 5) |
| `/team run <name> <job>` | Hands the team the job (part 3) |
| `/team stop <name>` | Closes the lead and its members (part 6) |

Names are completed after `/team show`, `run` and `stop`, from the
same list the picker reads. There is no `delete`: a team is a file, and the
picker shows where it is. With a child picked, `/team` acts on the session as
a whole. Teams belong to the session the person opened, so `/team new` and
`/team run` talk to `main` whatever is picked, and say so on the status line
the first time: `/team talks to main`.

### Making a team: `/team new`

The person writes what they want in their own words, and chord sends it to
`main` as a prompt. The prompt is drawn as typed (`› /team new …`), and in
the agent's turn it is the words with a one-line preface naming
`propose_team`. The agent may read the code, ask questions and call
`list_agents`, and then it calls **`propose_team`**. That tool's input is the
file's schema as JSON (`name`, `description`, `lead`, `members`, `body`), and
its description explains the parts, the two sections the body must have, and
that ids come from `list_agents`.

chord checks the input. A call that fails the check is a failed call, with
zod's first problem under `⎿`, and the agent corrects it and calls again. A
call that passes draws the proposal and opens the save box
(`120-1-proposal.txt`):

```
 ⏺ A lead on Opus to split the work, and three members, one for each step. Only one of them edits a file at a time.

 ⏺ Team(bugfix) · proposal
   ⎿  Fixes a bug end to end: a failing test first, then the fix, then a review of the diff.

      lead      claude · opus           default      Splits the job, says who edits which files, reports to main
      tester    claude · sonnet         acceptEdits  Writes the failing test, then proves the fix
      coder     codex · gpt-5.3-codex   auto         Writes the fix, in the files the lead names
      reviewer  claude · opus           plan         Reads the diff and edits nothing

      How bugfix works
      1. The lead reads the job, finds the files involved, and names who may edit which before anyone starts.
      … +16 lines (ctrl+o to expand)

 ✸ Waiting for you… (4s)

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

- **The call is drawn as a proposal, not as JSON.** The headline is
  `Team(<name>) · proposal`. Under `⎿` come the description, one row per agent
  (name, `runtime · model`, mode, role), and the body as markdown, folded
  after its first lines as a message is. ctrl+o shows all of it, the members'
  instructions included. The lead's role is chord's words, `Splits the job,
  says who edits which files, reports to main`, unless the lead's
  instructions start with a role line.
- **Modes are the point of the table.** They are the permissions the person
  approves (owner decision 3), so each one gets a column of its own and is
  never cut. A mode that skips the person's ok (`bypassPermissions`,
  codex's `full-access`) is drawn in the `warning` colour, the same colour as
  the status line's `bypass permissions on`. The words stay plain for
  `NO_COLOR`, because the id itself says it. Where a row does not fit, the
  role is cut first (`80-1-proposal.txt`), then the model. Opened
  (ctrl+o), nothing is cut: each role goes on lines of its own under its
  row, from the agent column to the right edge, and where a row does not
  fit, the mode wraps first and the agent · model after it, both at their
  spaces (CHD-333).
- **The box is the permission box's shape** (`120-perm.txt` in `today/`), and
  works the same way: 1/2/3 or ↑ ↓ and Enter, Esc for the last. It also
  matches Claude Code's plan prompt ("No, keep planning"): the way out is "say
  what to change", not "deny". The question names the team, and each choice
  names the file it would write, so where a team lands is never a guess.
- **Saved** (`120-1-saved.txt`): chord writes the file. If it already exists,
  the box says `Replace team bugfix?` and shows the change as a diff (below).
  The call's last `⎿` line, in the `success` colour, reads
  `Saved to .chord/teams/bugfix.md · /team run bugfix <job> hands it a job`.
  The agent gets `Saved to .chord/teams/bugfix.md.` as the answer, and its
  turn goes on, usually with a line that says how to use the team.
- **Not saved** (`120-1-changes.txt`): the call answers `The person did not
  save it; they will say what to change.`, and its `⎿` line is dim:
  `Not saved · the person will say what to change`. The agent's turn ends,
  the focus is in the prompt, and the person's next words go to the agent as
  any prompt does. Its next `propose_team` draws a new proposal with a new
  box. I did not give the box a text field of its own: the prompt box is
  already where the person writes, with history, `@` and ctrl+g.
- **A write that fails** (no rights, a full disk) is a failed call, with the
  error under `⎿`. The agent hears it, and nothing is half-written, because
  chord writes to a file beside the target and renames it over, as
  `saveSetting` does.
- `propose_team` is only for sessions the person opened. It can be called
  without `/team new` ("make me a team that…"), because the box is still the
  person's own ok.

### Changing a team

There is no `/team edit` (owner, 2026-10-09). The person asks the agent in
plain words ("put bugfix's reviewer on codex"), and the agent changes the
team through `propose_team`:

- `propose_team` with an
  existing name draws `Team(bugfix) · change`, with the rows that changed
  marked and the body's change as a diff, drawn as an edit's diff is (jsdiff,
  as `Edit(…)` already draws). A `~` row whose mode changed says the mode it
  had, dim: `bypassPermissions was acceptEdits`. The diff sits under
  `bugfix.md's body · 1 addition, 1 removal` (not `Updated …`: nothing is
  written yet); folded it keeps its changed lines with one line of context,
  at most five, where the window has 30 rows, and none on a shorter one, so
  the table, that line and the box fit 80×24; ctrl+o draws it whole. The box asks `Replace team bugfix?`
  with `1. Yes, in .chord/teams/bugfix.md` and `2. No, tell claude what to
  change`. A team is saved back where it came from. Moving it between
  project and user is a file move, which the person can do themselves.

### The picker: `/team`

`120-2-list.txt`, `80-2-list.txt`:

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Teams                                                                                                                │
│ Saved for this project in .chord/teams, and for every project in ~/.config/chord/teams.                              │
│                                                                                                                      │
│ ❯ bugfix   4 agents · claude, codex  this project   ✻ working 6m  Fixes a bug end to end: a failing test first, the… │
│   review   3 agents · claude         every project                Reviews a branch before it goes to the owner       │
│   docs     2 agents · claude         this project                 Keeps README.md and docs/ in step with src/        │
│   triage   ✗ not read: members.1.agent is missing                 ~/.config/chord/teams/triage.md                    │
│                                                                                                                      │
│ Enter to hand it a job · /team show <name> · Esc to close                                                            │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

- It is `/resume`'s panel shape, `picker.ts`'s list. Each row has the name,
  the size and its runtimes, where it is saved, whether it is running in this
  window (`✻ working 6m`, the strip's glyph, or `✻ 2 runs` when it runs more
  than once), and the description cut at the edge.
- **Enter** puts `/team run bugfix ` in the draft and closes the picker, so
  the person types the job and sees the command they will send. That holds
  for a team that is already running too: the job starts another run. A
  running team's lead is reached through the agent list. On a broken file,
  Enter does nothing: its row already says the problem and the path. While
  the highlight is on it the hint offers no Enter and says
  `Fix the file, or ask main to fix triage · Esc to close` (at 80 columns
  `Ask main to fix triage · Esc to close`).
- At 80 columns the runtimes and the hint's second half go first.
- With no teams it says `No teams yet. /team new and a few words about the
  work makes one.`

### `/team show`

`120-2-show.txt`: a `⎿` report under the command, as `/status` gives
(`today/120-status.txt`). It has the file's path, the description, the agent
rows (name, runtime and model, mode, role), and the body folded, with ctrl+o
for the rest. The running form is part 5's.

## 3. Handing a team a job

**Recommendation: both, on one path.** `run_team {team, job}` on chord's
server, and `/team run <name> <job>`. Both call the same open in the window,
and both draw the same row.

- **"Hand it to bugfix" is a sentence to main**, which is what the owner
  described. Only main knows what "it" is: the bug they just found, the files
  it read. A tool lets main write the job brief from the whole conversation
  (`120-3-run.txt`):

  ```
   › good, hand it to bugfix

   ⏺ Team(bugfix) · claude · opus
     ⎿  Issue 214: a string at the end of a line loses its closing quote. readString in src/parse/tokenize.ts stops at
        the newline before it consumes the quote. Add a test that fails for that reason, fix it, and have the diff
        reviewed. Report to me when it is done.

   ⏺ bugfix has the job. Its lead will report here; you can look in with ↓.

   ← @bugfix · claude
     On it. tester is writing a failing test in tests/parse/tokenize_test.ts; coder waits for it and will edit
     src/parse/tokenize.ts only. I will report when the test fails for the bug's own reason.
  ```

- **`/team run bugfix <job>` hands over the person's own words, as they
  are**, without a turn of main's in between and without depending on the
  model to call a tool. It is also what the picker's Enter leads to
  (`120-3-run-typed.txt`). Main did not take part, so chord tells it through
  a note that rides ahead of main's next turn, as held bash output does, and
  starts no turn of its own:
  `<message from="chord">The person handed team bugfix this job: "…". Its
  lead is @bugfix and reports to you; send_message reaches it.</message>`.
  The lead's first report is usually that next turn.
- **The row** is `⏺ Team(<name>) · <lead's runtime> · <model>`, with the job
  under `⎿` and folded as a message. It is the `Open(…)` row with the team's
  word, and it stands in the place of the `run_team` call, the way an `Open`
  does. A refused run is a failed row with chord's words:
  `No team named bugfx · /team lists them`,
  `.chord/teams/triage.md is not a team chord can run: …`,
  `This session has 8 agents open; close one first`.
- **A team that is already running starts another run.** The new lead is
  `bugfix 2` (then `bugfix 3`, and a closed run's number is not reused while
  the window is open), and the row reads `⏺ Team(bugfix 2) · claude · opus`.
  The new lead's standing words name the runs already open and their leads,
  so the new one can ask them which files they hold before its members start
  (`120-4-two-runs.txt`). chord does not tell the older leads, and does not
  check for clashes: the runs agree among themselves, as members do.
- **`list_teams`** is the third new tool: each team's name, description,
  members with their roles, and the leads of its runs that are open. Main reads it before
  `run_team`, as it reads `list_agents` before `open_agent`. Its row is
  `List teams` with `⎿ 3 teams · bugfix, review, docs`.

### What the lead and its members are told

chord opens the lead as an M4 long-lived child of main, named after the team,
on the lead's runtime, model and mode. Its first prompt has two parts. The
first is the team, wrapped so the agent can tell it apart from the job. The
second is the job as a message from main:

```
<team name="bugfix" role="lead">
  chord's standing words: what a lead is, its tools, who it can talk to, that
  every member works in <directory> beside it, the other runs of teams open
  in this session and their leads, and that it closes its members when
  their part is done.
  The lead's instructions.
  The members: name, role, runtime · model, mode.
  How the team works: the body.
</team>
<message from="@main">the job</message>
```

A member's first prompt is the same shape, with `role="member"` and
`name="tester"`. The standing words say that it answers to `@bugfix`, that
it may message the team's other open members by name, and that it may start
task agents with `spawn_task` but opens no long-lived agents. Then come its
role and instructions, the team's members, and the body. After that comes the lead's message, the `prompt` the
lead opened it with.

**chord's standing words cover mechanics only:** tools, names and the
directory. How files are shared, how often to report and what order the work
goes in are all in the file, where the person can read and change them.

On screen, the team part is one dim line at the top of that agent's own
transcript, `⏺ bugfix's instructions for tester · 41 lines (ctrl+o to
expand)`. The message under it is drawn as any `← @bugfix` row
(`120-4-member-picked.txt`). The person sees that instructions went in,
without 40 lines of them in the way.

### The lead's tools

| Tool | For a lead | For a member |
| --- | --- | --- |
| `open_agent` | `{member, prompt}`: a member by its name in the file, started on the file's runtime, model and mode, with the team part ahead of the prompt. Refused for a name the file does not have, and for one already open. | — |
| `spawn_task`, `list_agents` | as main's: a task agent on any runtime and model, for a one-off job, drawn nested in the lead's turn as CHD-149 draws a subagent | the same |
| `send_message` | `to`: `main`, an open member by name, or the lead of another run open in the session | `to`: its lead, or another open member of its team by name |
| `close_agent` | an open member | — |
| `monitor`, `stop_monitor`, `list_monitors` | its own monitors, as M4's children have them | the same |

**`spawn_task` is every agent's** (owner, answer 7): the lead's, each
member's, and M4's long-lived children's too, so it is one rule for every
agent chord opens. A task agent itself starts none, and it reports to the
agent that spawned it, as main's do. Long-lived agents stay as the person
approved them: a lead opens only the file's members, on the file's modes,
and a member opens no long-lived agent. That keeps the extra long-lived
level exactly one.

**Messages are not routed through the lead.** A member's `send_message` to
`coder` draws `→ @coder` in its transcript and `← @tester · claude` in
coder's, as M4's messages do. The lead does not see it. Keeping the lead
informed is the team file's business ("tells the lead what the two of them
agreed"), not chord's. Nothing limits how many messages they trade
(owner, answer 6, as for M4).

A lead's calls draw as M4's do: `Open(tester) · claude · sonnet ·
acceptEdits`. The mode is added in dim after the model, and only on a
member's row, because only there did a file set it (`120-5-lead.txt`).

## 4. The team in the agent list

`120-4-team-list.txt`: a team at work, `tester` waiting on a permission,
`reviewer` finished, and an ordinary M4 child (`parser`) after the team.

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ● tester needs your permission · ctrl+x a to go · ? for shortcuts                              Opus · 10% context used
    main         claude · Opus
    bugfix       team · claude · Opus   ✓ replied 40s ago
    ├─ tester    claude · Sonnet        ● permission 12s
    ├─ coder     codex · gpt-5.3-codex
    └─ reviewer  claude · Opus          ✓ replied 1m ago
    parser       codex · gpt-5.3-codex  ✻ working 9s
```

- **The lead is a row of main's**, in the order it opened, named after the
  team. Its second column starts with `team ·`, dim like the rest, so a lead
  reads as a team before any member is open. At 80 columns the model is
  dropped first, as for any row, and `team` stays.
- **Members are nested under their lead**, in the order they opened, with
  CHD-149's `├─` and `└─` in the name column. The tree is dim, and the
  member's name takes its colour. Only open members are drawn: the list is
  of agents that are running, as it is in M4. `/team show` lists the rest as
  `not opened`.
- **Colours**: members take the next of the six `agents` colours in the
  order they opened, in the same sequence as main's children, so no two
  agents in view share a colour until the seventh. The lead keeps its own.
- **States** are M4's, per agent: `● permission`, `✗ failed`/`exited`,
  `← message from @bugfix`, `✓ replied`, `✻ working`.
- **A member that waits** is named on the status line (`● tester needs your
  permission · ctrl+x a to go`), and `ctrl+x a` picks it, unfolding the team
  if it is folded. When another open run has a member of the same name, the
  status line adds the run (`● tester · bugfix 2 needs your permission`).
  The terminal's notification always names it with its team:
  `tester (bugfix) needs your permission`.
- **A member's task agents** are drawn in its own transcript, nested in its
  turn as main's are. They are not rows of the list, as M4's task agents are
  not.
- **Limits.** A lead holds up to 8 members, the file's maximum, and counts as
  one of main's 8 children. Each run is one of those 8. The list keeps its `max(2, ⌊rows / 6⌋)` rows (6
  at 40, 4 at 24). Members do not raise it, because the prompt's room matters
  more.

### Folding, at 80×24

Main, a lead with three members and `parser` make six rows, and 24 rows give
the list four. **When the whole list does not fit, each team folds to its
lead's row** (`80-4-team-list.txt`):

```
  ● tester needs your permission · ctrl+x a                    Opus · 10% used
    main         claude · Opus
    bugfix       team · claude · 4 agents  ● tester: permission 12s
    parser       codex · gpt-5.3-codex     ✻ working 9s
```

- A folded lead's row shows its size in place of its model
  (`team · claude · 4 agents`) and the most urgent state among the lead and
  its members, naming the member when it is one (`● tester: permission
  12s`). This is the same rule the sessions picker uses for a tab's children.
- **With the focus in the list**, the team the `❯` is on unfolds and the list
  scrolls as it does today (`80-4-team-focused.txt`, `80-4-member-picked.txt`).
  ↑ ↓ walk lead and members in order. A team the `❯` is not on stays folded.
- At 120×40 one team of four fits beside main and a child, so nothing folds.
  Two full teams would fold.

### Several runs of one team

`120-4-two-runs.txt`, `80-4-two-runs.txt`: `bugfix` on issue 214 and
`bugfix 2` on issue 219, with three and two members open. Nine rows do not
fit six, so at 120×40 both fold, and at 80×24 too:

```
  ● tester · bugfix 2 needs your permission · ctrl+x a to go · ? for shortcuts               Opus · 12% context used
    main         claude · Opus
    bugfix       team · claude · 4 agents  ✻ coder: working 1m
    bugfix 2     team · claude · 4 agents  ● tester: permission 5s
```

- **Each run is a lead row of main's**, in the order it started, named as
  M4 names a second child of one runtime. Both have a `tester`, so the
  status line names the run, and the picked member's box is titled
  `tester · bugfix 2`.
- **The runs talk lead to lead.** In the mock, `bugfix 2`'s first report
  says it asked `bugfix` which files it holds. Those messages are drawn in
  the two leads' transcripts as any `→`/`←` pair, and main sees neither.
- Unfolding, picking and closing are per run, as for one team. `/team stop
  bugfix` stops the run named `bugfix`, and `/team stop bugfix 2` the other.

### A member picked

`120-4-member-picked.txt`: ↓ into the list, and down to `tester`.

```
 tester · claude · Sonnet · bugfix's member · opened by @bugfix 6m ago

 ⏺ bugfix's instructions for tester · 41 lines (ctrl+o to expand)

 ← @bugfix
   Write a test in tests/parse/tokenize_test.ts that fails because a string at the end of a line loses its closing
   quote. Edit tests/ only. Tell me when it fails for that reason.
 …
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ tester asks                                                                                                          │
│ Bash deno task test tests/parse                                                                                      │
 …
╭─ tester · bugfix ────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

- It works exactly like an M4 child: picking swaps the transcript, the
  queue, the draft, the permission box and the status line's model. The
  header line adds `bugfix's member` and `opened by @bugfix`.
- **The box's title is `tester · bugfix`**: the name in its colour, then
  `· bugfix` dim. Two teams can both have a `tester`, and the box must say
  which one the prompt goes to. Message rows need no team name: a member's
  rows only ever appear in the transcripts of its own team, where the name
  is unique.
- **The person may write to a member.** It is their prompt, `›`, as with any
  child. The lead is not told. A person who wants the lead to know tells the
  lead.
- **The lead picked** (`120-5-lead.txt`) shows the team at work from the
  inside: its `Open(…)` calls with their modes, `→ @tester`, `← @tester ·
  claude`, and `→ @main` for its reports. The box is titled `bugfix`.

## 5. Reports, and asking for status

**Reports are M4's messages.** The lead's `send_message` to main draws
`← @bugfix · claude` in main's transcript and starts main's turn, and main
answers the person in its own words (`120-3-run.txt`, `120-4-team-list.txt`).
Nothing new is drawn. Every report starts a turn of main's, with no flag to
hold one back (owner, answer 8). The lead decides when to write, and the
team file's "Reporting" section is where the person shapes that, so a
person who finds the lead too chatty, or too quiet, edits a sentence, not a
setting. chord counts and gates nothing.

**The person can ask for status in three ways, from cheapest to richest:**

1. **Look.** The list's rows say who is working, waiting, finished or failed,
   and `/team show bugfix` adds what each agent is on right now, with no
   model asked (`120-2-show-running.txt`):

   ```
    › /team show bugfix
      ⎿  bugfix · .chord/teams/bugfix.md · working 6m on "strings at the end of a line lose their closing quote; see…"

         lead      claude · opus           default      ✻ working 8s       → @coder
         tester    claude · sonnet         acceptEdits  ● permission 12s   Bash(deno task test tests/parse)
         coder     codex · gpt-5.3-codex   auto         ✻ working 41s      Edit(src/parse/tokenize.ts)
         reviewer  claude · opus           plan         not opened
   ```

   The last column is each agent's latest call or message headline, as its
   transcript draws it. It is a snapshot, the same as `/status`.
2. **Ask main.** "How is bugfix doing?" Main sends the lead a message, and
   the lead's answer comes back as a `← @bugfix` row. Nothing new is needed
   for this.
3. **Ask the lead.** Pick `bugfix` in the list and type. The answer is in the
   lead's transcript.

I did not add a `/team status` with a model's summary. The first way gives
the facts at once, and the other two already ask a model.

## 6. Closing

**Closing a parent closes all its children** (owner, answer 10: CHD-218's
option A, confirmed). That holds for main, for a tab and for a team's lead,
so **closing the lead closes the team**: the members are the lead's
children, as M4 already closes a parent's children with it (CHD-167 part
5). Closing a member, or a lead, cancels its task agents as well, as
closing main cancels main's.

- **`x` on the lead's row.** If any agent of the team is working or waiting,
  the first press arms it (`80-6-close-armed.txt`):
  `bugfix and its 3 members are working · x again to stop them and close`.
  An idle team closes on the first press.
- **`x` on a member's row** closes that member alone, as for any child, and
  chord tells the lead with M4's sentence: `The person closed coder (codex ·
  gpt-5.3-codex, id 3c9e01b4). It takes no more messages; open_agent opens
  it again.` The lead may open it again. It is still in the file.
- **`/team stop bugfix`** closes the team with no arming, because the person
  typed the command on purpose, and reports under the command
  (`120-6-stop.txt`): `⎿ Stopped bugfix: its lead and tester, coder and
  reviewer are closed · /resume lists them`.
- **Main is told** whenever the person closed the team, with `← chord`
  (`120-6-closed.txt`): `The person closed team bugfix: its lead (claude ·
  opus, id 7f3a9c2e) and its members tester, coder and reviewer. It takes no
  more messages; run_team starts it again.` Main's own `close_agent` on the
  lead does the same without the message, because main asked for it.
- **A member's agent exits or its turn fails**: the list shows `✗ exited` or
  `✗ failed`, and chord tells the lead with `← chord`: `coder's agent exited:
  <the agent's last words>. open_agent opens it again.` M4 tells no parent
  today, and a lead waiting on a member's report would wait for ever. This
  goes to M4's children's parents as well, as one rule.
- **The lead's own agent exits**: its members are closed, as when it is
  closed, and main is told `bugfix's lead exited: … Its members are closed;
  run_team starts the team again.`
- **Closing main** (the tab, `/clear`, `/resume` in its place) closes its
  team with its other children, each recorded. The busy words count a team's
  agents among the session's (`1 claude has 4 agents working`), so
  `ctrl+x k` arms first. **Quitting** closes everything, as now.
- **Closing one run** leaves the other runs of that team open. The leads
  still open are not told: a lead that was waiting on the closed one hears
  `bugfix is closed` when it next messages it, as M4 answers a message to a
  closed child.

## 7. `--resume`

As CHD-171 has it (`120-7-resume.txt`, `80-7-resume.txt`). The past is drawn
from main's record: the `Team(…)` row, the `← @bugfix` reports and the
`← chord` lines. The team is not reopened, and the closing note names it
beside any other child:

```
 ⏺ parser (codex) and team bugfix (4 agents) were open when this session was left and are not reopened · /resume lists
   them · /team run bugfix starts the team again
```

- The lead's record names main as its parent and `team: bugfix`. Each
  member's record names the lead as its parent and its member name. So
  `/resume` lists them like any child (`bugfix · claude`, `tester · claude`),
  and one reopened there is the person's own, with no team around it.
- The closing note counts the team as one item. `/team run bugfix` starts a
  fresh team with no memory of the last run. The work it did is in the
  working tree, and main's transcript says what it was told.
- A window record holds sessions, not children, so `--resume w-…` changes
  nothing here: each tab is drawn as above.
- Several runs are named one by one, each with its own count (`team bugfix
  (3 agents) and team bugfix 2 (3 agents)`), so next to another child no run
  borrows a count it does not have; the way back is the one `/team run
  bugfix` (CHD-264).

The owner chose this over reopening the lead from its record (answer 5).

## Keys

| Key | Where | Does | `keys.ts` / panel | Bindable |
| --- | --- | --- | --- | --- |
| `1` `2` `3`, `↑ ↓` + `enter`, `esc` | the save box | save here / save for every project / say what to change | the box says so, as the permission box does | no (as the permission box) |
| `enter` | the teams picker | `/team run <name> ` into the draft, or pick the running lead | its last line | no (as `/resume`'s) |
| `↓`, `↑ ↓`, `j k` | agent list | as M4, walking lead and members in order and unfolding the team the `❯` is in | unchanged | unchanged |
| `x` | agent list | closes the picked agent. On a lead, its team, twice if busy | the panel line becomes `x to close an agent or a team, or stop a monitor` | `agents:close`, unchanged |
| `ctrl+x a` | anywhere | reaches a member's wait, unfolding its team | unchanged | unchanged |

No new key. `/team` goes in the slash list and in `/help`'s commands.

## Rejected

- **The team as JSON or YAML only, with no markdown body.** The part that
  matters most, how the team works, is prose that a person edits. In a YAML
  string it loses its headings and lists, and in JSON its line breaks.
- **One markdown body with a `## tester` section per member** in place of
  frontmatter instructions. chord would have to parse markdown headings to
  find an agent's runtime and mode, and a stray heading in the prose would
  read as a member.
- **A `name` key in the frontmatter.** It would be the file's name written a
  second time, and the two could disagree.
- **The agent writes the file with its own Write tool.** chord could not
  check it before it lands, the person's ok would be a file-write permission
  rather than "save this team", and a team saved for every project would
  mean an agent writing in the user's config directory.
- **`/team run` alone** (no tool). "Hand it to the team" would not work as
  words, and the job brief would lose what main knows. **`run_team` alone**
  (no command). The person could not hand over their own words without a
  model in between, and the picker's Enter would have nothing to lead to.
- **The lead may open any agent (M4's `open_agent` as it is).** The team the
  person approved, modes included, would only be a suggestion. The owner
  kept long-lived agents to the file's members and gave every agent task
  agents instead (answer 7).
- **Members talking to their lead alone**, and **one run of a team per
  window**: the design's first recommendations. The owner chose to let the
  agents agree among themselves rather than have chord keep them apart
  (answers 6 and 9).
- **A chord-side guard on files**, such as locks, or refusing a second run
  that names the same files. The owner's principle is that the agents agree
  on it, and the team file says how.
- **Members not yet open drawn in the list, dim.** They are not agents yet.
  Nothing can be picked, written to or closed there, and on 24 rows they
  would push out agents that are working.
- **A team in a tab of its own.** The owner dropped tabs for children on
  2026-10-07, and a team is children.
- **Notes from the lead that do not start main's turn**, with a flag on
  `send_message` for one that needs an answer. Main could not answer a lead
  that forgot the flag, and the owner chose one rule for every message
  (answer 8).

## For the engineers

Build tasks, in order, filed under CHD-240:

1. **Team files** (`src/teams.ts`): find, read (`@std/front-matter`), check
   (zod), write (`@std/yaml` + rename), project over user. `list_agents`
   gains each runtime's modes. Tests on files in a temporary directory.
2. **The agents' new tools and the deeper level**: `list_teams`,
   `propose_team` (with the save box), `run_team` and several runs named
   `bugfix 2`; a lead's `open_agent {member, prompt}`, `send_message` to
   main, its members and other runs' leads, `close_agent`; a member's
   `send_message` to its lead and its team's open members; `spawn_task` and
   `list_agents` for every agent chord opens; the team part of each first
   prompt; `← chord` to a parent whose child exits or fails (M4's too).
   Part 1's check, part 2's proposal and save box, part 3, part 6.
3. **`/team`**: the command and its forms, the picker, `show` with its
   running form, `stop`.
   Part 2, and part 5's `/team show`.
4. **The team in the list**: `team ·`, nesting, folding, several runs, the
   member's box title and header, the instructions line, `x` on a lead, the
   status line and notification wording. Part 4, and part 6's arming.
5. **Resume**: the records' `team` and member names, and the closing note's
   team items. Part 7.

The mocks are the acceptance: each state at 120×40 and 80×24, captured
against the fake agent (which needs a `team` scenario that runs a lead
opening two members, one asking for a permission, and the members
messaging each other), saved under each task's `evidence/`. **The one
rule:** before drawing the proposal's table, try `@cliffy/table`, which
`chord agents` already uses, against the rows in `120-1-proposal.txt`, cut
by column as described. Use the save box as the permission box already is
(`ink-select-input`). The tree glyphs are CHD-149's and need nothing new.

## The owner's answers

The open questions this design ended with were answered on 2026-10-09
(CHD-240), and the parts above follow them. In short: `--resume` does not
reopen a team (A); a member talks to its lead and its team's open members
(B); a lead opens the file's members and task agents, and `spawn_task` is
every agent's (C, widened); every message from the lead starts a turn of
main's (A); any number of runs per window (B); closing a parent closes all
its children (CHD-218's A, closed).
