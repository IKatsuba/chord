# CTUI-37: teams, chord's team tools and get_budgets

The original's M5: team files, `/team` (list, new, show, run, stop), leads
opening members, several runs of one team, teams in the agents list and on
resume, chord's tools `list_teams`, `run_team` (with the per-run
`selection` of CHD-533), `propose_team` and `get_budgets` (CHD-548), the
`teamSelection` settings (already checked and merged in `settings.dart`
by CTUI-79, used as they are), and `chord acp`'s `/team` (CTUI-56's
split).

The specification is `../chord`, to the word: `src/teams.ts`,
`src/session/{team_command,team_selection,budgets,resource_normalization,
resource_access,codex_resources,agents_host,window_agents,conversation,
record,upstream,upstream_commands}.ts`, `src/platform/resource*.ts`,
`src/server/tools.ts`, `src/ui/teams/`, `src/ui/transcript/tools/
{proposal,resource_lines,selection_lines,chord}.ts` and `Tool.tsx`,
`src/ui/agents/agents.ts`, `src/ui/transcript/{spend,spend_table}.ts`,
`src/acp_agent.ts`, their tests and fake scenarios; `docs/guide.md`
("Teams", "Resource facts and team selection", "Children, teams and
commands"); `docs/design/M5-teams.md`, `CHD-533.md`, `CHD-548.md`.
**Where M5-teams.md and `src/` differ, `src/` holds** (interface draft
section 8 lists the sixteen places).

The design was drafted by the framework, interface and runtime
architects, reviewed by the critic, and revised once after the review.
The drafts are the record, under `docs/design/evidence/CTUI-37/drafts/`;
where this document and a draft disagree, this document holds. The
drafts carry what this document does not repeat: every word and screen
with its source line (interface sections 2 and 8), the check's order
(runtime 1.3), the host's order of steps (runtime 2.4-2.8), the readers'
wire and bounds (runtime 3), the failure table (runtime 4), cliffy's
cell rules and recorded cases (framework 2.3).

It builds on CTUI-35 (`docs/design/CTUI-35.md`, section 9's seams:
`ChildInfo.team` and `lead`, `Caller.role`, the left-open note) and
CTUI-36 (leads and members have monitors as children do).

## 1. Scope

In: everything above. Out: `/team choose` (removed by the owner in the
original); scheduling, reservations, quota enforcement; reopening teams on
resume; anything else the original does not do.

Nothing goes into the framework's `lib/` (section 6). The owner's
answers to the five questions are in section 11.

## 2. Team files

`example/chord/lib/teams.dart`, from `src/teams.ts` (runtime 1):

- `teamDirs`, `findTeams`: `<cwd>/.chord/teams` and `teams/` beside the
  user settings file; project wins a shared name (`hides`); code-unit
  sort; files read in parallel, **whenever needed, never cached**.
  Window-side reads are async and carry `(key, launch)` as CTUI-35's;
  an answer whose key or launch moved is dropped.
- `parseTeam`: UTF-8, BOM dropped, vfile-matter's frontmatter regex,
  `package:yaml` 3.1.4 (already in the lock, a direct dependency now),
  converted to plain maps before the check. The trial (runtime 1.4)
  read every input as npm `yaml` 2.9.1 does, which is what the original
  reads with (not `@std/yaml`, as the brief said).
- The check is our own, in zod's words and order, as CTUI-29 settled for
  settings; `problemOf`'s `<path>: <message>`; names refused with `"`
  or control characters through `agent_name.dart`. The test reads the
  original's problem table.
- `teamText` and `saveTeam`: the frontmatter written by **our own
  emitter** (owner, Q3), `example/chord/lib/yaml_stringify.dart`,
  byte-identical to npm `yaml` 2.9.1's `stringify` with default options
  for what chord writes (maps, a list of maps, strings): plain scalars
  where npm yaml leaves them plain, its quoting otherwise, block literals
  `|`, `|-`, `|+` with an indentation indicator where needed (multi-line
  instructions stay block scalars, as people read and edit them), `>`
  and line folding at 80 columns as npm yaml folds. Tested on fixtures
  recorded from npm `yaml` 2.9.1 (pinned in the test, with the command
  that made them) and, where bun and `../chord` are present, against npm
  `yaml` live on generated strings (skipped with a reason otherwise).
  Then the atomic write to a temporary beside the target and rename; on
  failure the temporary is removed and the old file is intact.
- `teamChanges` (deep equality from `collection`), `checkProposal`,
  `teamPart` (the `<team …>` block of a first prompt).
- The repository's `.chord/teams/architects.md` and `ship.md` load: a
  test reads both.

`lib/session/team_command.dart` (pure): `/team`'s parse, `ranNote`,
`teamRefusal`, `stoppedLine`, `NO_TEAMS`, `LEAD_ROLE`, `newTeamPrompt`,
`teamsSaved`, `briefly`, `andList` (written by hand: `a`, `a and b`,
`a, b, and c`, as `Intl.ListFormat` gives; Dart's `intl` has no list
format).

## 3. Runs in the host

As runtime 2, in `window_agents.dart`, `agents_host.dart` and
`server/tools.dart`:

- `runs: leadId → Run` holding the team **as read at run start**, held
  unmodifiable; members open only from it. Run names `bugfix`,
  `bugfix 2`, …, never reused in the window (closed names kept across
  `/clear` and `/resume`).
- Counting: a lead is one of main's 8 children; members count none and
  are bounded by the file.
- `run_team` and `/team run` take one path (`runTeamAt`), in the
  original's order; the run is registered before the lead's first prompt
  is delivered, so a lead's first-turn `open_agent` finds it.
- A lead's `open_agent {member, prompt}`: the file's member on its
  runtime, model, effort and mode, with its three occupied checks.
- `messageRecipients`: lead → main, its members, other runs' leads;
  member → its lead and its team's open members; `teamTell`'s refusals.
- `toolsOf` gains the lead and member branches; `spawn_task` and
  `list_agents` for every long-lived agent; `list_agents` gains each
  runtime's modes; `run_team` and `propose_team` refused to a fork;
  `get_budgets` for main and long-lived agents, not tasks.
- Closing: a parent closes its children. `dropChild` **starts** every
  member's close and then the lead's at once, joining them later with one
  aggregate error (`agents_host.ts:614-655`); nothing waits for a member
  before the lead's close starts. A lead's exit closes its members and
  tells main; a member's exit or failed turn tells its lead (and the M4
  parent rule, the same sentence for a plain child's parent).
- Records: `team` on a lead's header, the member's parent and name;
  `ran` for `/team run`'s call; the left-open note counts each run as
  `team <run> (<n> agents)`.

### Selected runs (`run_team` with `selection`)

`lib/session/team_selection.dart` and `runSelectedTeamAt` (runtime 2.5):
`RunSelection` checked by our checker, the merged `teamSelection` policy,
capabilities read per distinct runtime in turn, `freezeSelection`,
admission, receipts. **Receipt updates are appended**, as the original
does, to the record captured when the launch was admitted:
`Recording.captureServed` / `Conversation.captureServed` are ported
(`conversation.ts:2208-2228`, `record.ts:1300-1317`); a late update after
`/clear`, resume or close lands in that record, never in the
replacement's; an admitted attempt refused before any prompt marks its
record worth keeping; replay folds the latest update per run id. No
record rewrite is added.

## 4. `get_budgets`

As runtime 3. `lib/session/{budgets,resource_access,
resource_normalization,codex_resources}.dart` and
`lib/platform/{resources,resource_process,resource_executable,
resource_fixture,resource_worker}.dart`.

- `createResources(collectors: official | fixture | injected)`:
  `claude` and `codex` by default, in parallel, 10 s each, `[]` reads
  none, any other runtime `No limits reader for this runtime.`; the
  answer does not wait for a reader's cleanup, `close()` does and returns
  the cleanup failures (stderr after the terminal is restored; a leave
  step in `chord acp`). Cancellation through `cancellation_token`.
- Process groups, bounds and the cleanup ladder as
  `resource_process.ts`; executables resolved as
  `resource_executable.ts` with an injected inspection; `darwin-arm64`
  only; the Mach-O/ELF check our own (Q4).
- Codex: `codex app-server` over newline JSON-RPC; the request layer is
  `json_rpc_2` over a channel adapter of ours that adds `"jsonrpc":
  "2.0"` to what Codex sends and strips it from what chord sends (Q2).
- Claude: the two stream-json control requests SDK 0.3.325 sends for
  the experimental usage getter, spoken from Dart to the verified native
  `claude` in its own process group, with no worker re-exec (Q1);
  bounded at 256 KiB of stdout in total, failures answered in the
  original's unavailable words (runtime 3.3's table). The recording
  recipe and log are kept as evidence (runtime 3.2).
- **Never a real reader under test**: the test catalog builds hosts with
  `fixture` or injected collectors; `tool/dev.dart --fake` defines
  `CHORD_RESOURCE_FIXTURE` at compile time (as the original's dev tools
  force fixtures with `--fake`), and a test proves that route never
  resolves an official collector.

## 5. Screens

Every word and layout is interface draft section 2, with its source line;
nothing is invented. Where each piece goes (interface section 3):

| Piece | Port |
| --- | --- |
| `/team` in the slash list, `/help`, completion of names after `show`, `run`, `stop` | `ui/prompt/commands.dart`, `state.dart` |
| Teams picker (`/resume`'s panel; Enter puts `/team run <name> `; broken file's problem; empty) | `ui/pickers/`, rows from `ui/teams/teams.dart` |
| `/team show` saved and running, `said`, `ran` entries | `ui/teams/teams_view.dart`, a `TeamShown` transcript entry folded by the reducer |
| `Team(<name>) · proposal` / `· change`, the save box | `ui/transcript/tools/proposal.dart`, `tool.dart`; CTUI-79's `SaveBox` |
| `List teams`, `Team(…)` rows and refusals, `Open(tester) · … · acceptEdits`, `Resources`, selection lines | `ui/transcript/tools/{chord,resource_lines,selection_lines}.dart` |
| Recorded receipt, `/team show <run ID>`, `Team attempt:` in `/resume` | `ui/teams/recorded_receipt*.dart` |
| Agents list: `team ·`, `├─`/`└─`, folding, folded state naming the member, size | `ui/agents/agents.dart`, `agents_view.dart` |
| Member header, box title `tester · bugfix`, status line, notification `tester (bugfix)` | `agents.dart` `childLine`, `ui/prompt/named_top.dart`, `window_agents.dart` |
| The instructions line `bugfix's instructions for tester · N lines` | `ui/transcript/message.dart` |
| `x` armed on a lead, `← chord` notes | `ui/app/closing.dart`, `window_agents.dart`, `agents_host.dart` |
| `/cost`'s team rows | `ui/transcript/{spend,spend_table}.dart` |
| `chord acp`'s `/team` answers, `[team, new]` then the agent's commands | `session/upstream_commands.dart`, `upstream.dart` |

What it draws at 120x40 and 80x24 is the original's capture beside the
port's, taken per unit with the capture plan of interface section 7, on
the fixed dev route (unit 1); the drawings in the interface draft are
laid out by the source's rules and are illustrative. Notably (`src/`
over M5): the proposal's instructions, body and change diff are drawn
whole and only its table has an opened layout under ctrl+o; there is an
effort column; roles and runtimes wrap and are never cut; list states
are always shown with unseen marks in their own column; the shortcuts
panel stays `x to close an agent, stop background`.

**Keys: none new.** The save box's `1` `2` `3`, ↑ ↓ Enter and Esc are the
permission box's; the picker's are `/resume`'s; ↓, ↑ ↓, j k, `x`,
`ctrl+x a` and ctrl+o are unchanged actions, so `Actions`, the keymap and
the shortcuts panel do not change.

## 6. Framework

Nothing new in `lib/` (framework section 1): the body uses `Markdown`,
the change uses `diffTexts(...).view()` and `Diff.fromView`, widths use
`cellWidth`; the proposal table and `/team show`'s running table are
chord's own layout and stay in the port, as the agents list's rows did
in CTUI-35.

The two tables are printed by `@cliffy/table` 1.3.1 in the original,
whose cell wrapping matches neither of the framework's wrappers. The port
gets **`example/chord/lib/ui/teams/cliffy_row.dart`**: one row with fixed
column widths, padding 2, no border, cells wrapping at single spaces
(`consumed + next < n`, at least one word), an overlong word cut and
carried with no space removed, a span's width its columns plus the
paddings between, a column of 0 dropping its cell, as cliffy 1.3.1
does. **Graphemes stay whole and widths are the framework's
`cellWidth`** (owner, Q5, as CTUI-57 chose for wrap-ansi): an overlong
word is cut between graphemes, at least one grapheme per line, so a ZWJ
emoji is never cut after its joiner and counts 2. The nineteen cases
recorded from cliffy under bun (framework 2.3) stay in the test: those
whose lines are the same are pinned as the original's; those that differ
(ZWJ sequences, and combining marks at the cut) are pinned with the
port's lines beside the original's, as the recorded difference. No
cliffy width table is ported. The tables' own column widths, which the
original measures with string-width 8.3.0, use `cellWidth` as well.

Team folding is pure in `ui/agents/agents.dart`: `teamRows`,
`listRows(limit, height)` folding only when the wrapped rows exceed
`agentsRowLimit`, the picked agent's team unfolded, columns unmoved by
folding, `listTimed` looking into folded members.

## 7. Performance

At most 8 runs × 9 agents, plus forks and tasks: about 100 rows; folding
is one pass, at most two layouts per frame. `/team show` running reads
the frozen run and the roster, no file. Team files are a few KiB, read
async, parsed on the main isolate. `get_budgets` is off the frame path.
No benchmark is needed (runtime 5).

## 8. Failure modes

Runtime section 4's table is binding: concurrent runs named apart,
numbers not reused, the frozen team surviving file edits, two
`open_agent` of one member starting one, a lead closed while its
`open_agent` waits, lead exit closing members once, the ninth run
refused, `/clear` during a start, a refused selected lead's receipt, a
member's group outliving the ladder, a failed save leaving the old file,
an unanswered proposal, provider floods, a provider ignoring SIGTERM, a
quit during a read, an unsupported platform.

## 9. Tests

Never a real agent, never a real provider's usage endpoint. Pure modules
directly with the original's cases; widgets through the tester at
120x40 and 80x24; the host with scripted sessions and a fake
`ChordServer`; the server on loopback per role; the original's fake
agent with its `team`, `team2`, `teamlead`, `teamtester`, `teamcoder`,
`teamtask`, `propose`, `proposeagain`, `proposeefforts`, `selectedteam`,
`budgetawareteam`, `savedteamplain` scenarios and `fixture` resources;
the readers against the original's fixture providers
(`tests/fixtures/claude_resource_provider.ts`, `resource_provider.ts`)
through bun, skipped with a reason without bun or `../chord`, and a Dart
fake recording argv, env and lines; records on an isolated
`XDG_STATE_HOME`. The full list is runtime section 6, framework section
4 and interface section 10.

## 10. Units for ship, in order

Each unit ends with its tests passing and, where it changes the screen,
the original's capture beside the port's at 120x40 and 80x24.

1. **The dev route.** `tool/dev.dart --fake` defines
   `CHORD_RESOURCE_FIXTURE`, takes a staged working directory and
   isolated state and config; `dev_test` proves no official collector is
   resolved. Comes first because every capture uses it.
2. **Team files.** `teams.dart`, `team_command.dart`. Tests: the
   original's `teams_test.ts` and `team_command_test.ts` cases, the
   problem table, round trip and `teamText(teamOf(saved)) == saved`, a
   failed write, BOM, CRLF, empty frontmatter, both repository team
   files; `yaml_stringify.dart` against fixtures recorded from npm
   `yaml` 2.9.1 (the original's team fixtures, both repository files,
   quoting and block-scalar edge sets) and live against npm `yaml` under
   bun where present; the YAML error message pinned.
3. **Runs in the host.** Section 3 without selection: runs, names,
   lead's `open_agent`, messages, closing (stubborn member and lead
   bounded by the longest close), `toolsOf` branches, `list_teams`,
   `run_team`, `list_agents` modes, `← chord` notes, records and the
   left-open note; the `List teams`, `Team(…)` and member `Open(…)`
   rows. Tests: host scenarios of runtime 4; server `tools/list` per
   role; fake `team`, `team2`, `teamlead`, `teamtester`, `teamcoder`,
   `teamtask`, `savedteamplain`.
4. **The team in the list.** `teamRows`, folding, folded state, header,
   box title, status line, notification, instructions line, `x` armed on
   a lead, the resume note's team items. Tests: `agents_test.ts`'s team
   cases, `Teams_test.tsx`, `TeamsList_test.tsx`, `TeamsAsking_test.tsx`,
   closing tests, `AgentsResumed_test.tsx`'s team cases; captures.
5. **`cliffy_row` and `/team` in the window.** The helper with its
   recorded cases, graphemes whole, the differing cases pinned; slash list,
   completion, picker, `/team show` saved and running (`runningTable`),
   `/team run`, `/team stop`, `/team new`, `/team talks to main`.
   Tests: `tests/ui/teams/teams_test.ts`, `Teams_test.tsx`, prompt
   command tests, `team_launch_test.tsx`; captures.
6. **`propose_team` and the proposal.** The tool, the save box,
   `proposal.dart` (table folded and opened, marks, `was`, warning mode,
   body and diff whole, saved and not-saved lines). Tests:
   `proposal_test.ts` ported (without the unreachable helpers), widget
   tests at both sizes, fake `propose`, `proposeagain`, `proposeefforts`;
   a failed write; captures.
7. **`get_budgets` with fixtures.** `budgets`, normalization,
   `createResources`, the tool, the `Resources` block. Tests: pure,
   `resources_test`, fake `budgetawareteam` with fixture; captures of
   each fixture case.
8. **The readers.** Process ownership and the ladder, executable
   resolution and the native check, Codex's reader, Claude's reader.
   Tests: the original's fixture providers through bun (all their
   scenarios), the recording fake, flooding and oversize, compile tag.
   The Mach-O/ELF check and the Codex adapter are tested here too.
9. **Selected runs.** `team_selection`, `runSelectedTeamAt`,
   `captureServed`, appended receipts, `/team show <run ID>`,
   `RecordedReceipt`, `Team attempt:` in `/resume`. Tests:
   `team_selection_test.ts`, `selected_team_test.tsx` cases, fake
   `selectedteam` per case, late updates across `/clear`, resume and
   close, a refused no-prompt attempt kept.
10. **`/cost`'s team rows.** Tests: `TeamsSpend_test.tsx`, the spend
    table's team cases.
11. **`chord acp`'s `/team`** and the readers' leave step. Tests:
    `upstream_commands_test.ts` and `acp_agent_test.ts`'s `/team` cases
    in memory, the emitted `[team, new, …]` list, the leave step.

## 11. The owner's answers

Asked in one batch with options; answered by the owner through main.

- **Q1, Claude's usage reader: A.** The two control requests are spoken
  from Dart to the native `claude`, with no worker re-exec; the bound and
  the wording are the original's (runtime 3.3), the three worker-only
  phrases never produced.
- **Q2, Codex without `"jsonrpc"`: (a).** A channel adapter under
  `json_rpc_2`.
- **Q3, writing team files: (b).** Our own emitter, byte-identical to npm
  `yaml` for what chord writes, tested against npm `yaml` under bun:
  people read and edit team files, so multi-line instructions stay block
  scalars. `yaml_edit` 2.2.4 and `yaml_writer` 2.1.0 are logged as shown
  not to fit.
- **Q4: accepted.** Dart `yaml`'s message inside `not valid YAML (…)`, and
  our own Mach-O/ELF check.
- **Q5, Unicode in the two tables: (b).** Graphemes stay whole with the
  framework's widths, as in CTUI-57; the difference is recorded with
  pinned cases.

The lead's three decisions (unreachable folding helpers not ported, a
wide character in a one-cell column padding by zero, the tables' column
widths by `cellWidth`) were agreed by the owner.

## 12. Differences from the original

- The two cliffy tables keep graphemes whole and measure with
  `cellWidth`: a ZWJ sequence is never cut after its joiner and counts 2
  where cliffy counts 4; the tables' column widths differ from
  string-width 8.3.0's on rare lone code points. Pinned cases.
- A wide character in a one-cell column pads by zero where the original
  throws `RangeError` (the original's slip, fixed).
- The proposal's unreachable folding helpers are not ported.
- A broken frontmatter names Dart `yaml`'s parse message.
- Claude's usage is read with no worker process; the 256 KiB bound is on
  `claude`'s output in total rather than on the worker's printed result.

Each is an entry in `docs/decisions.md`.

## 13. Addendum: `Markdown.blocksOf`

The one framework addition, by the owner's choice (decisions.md, "CTUI-37:
rendered Markdown lines are public in the framework"). `/team show` folds a
team's body to a preview and a `+N lines` count. The original takes both
from its renderer's top-level blocks, `markdown(team.body, width, …)` into
`proposalBody` (`src/ui/teams/Teams.tsx` 131-142,
`src/ui/transcript/tools/proposal.ts` 555-584). The port takes them from
the rows its own `Markdown` widget draws, through one static call beside
the existing `Markdown.heightOf`.

### The call

```dart
final blocks = Markdown.blocksOf(team.body, room, theme: Theme.of(context));

// The original's proposalBody, unchanged in shape:
final body = [
  for (final (i, block) in blocks.indexed) ...[
    if (i > 0) const TextSpan(''),
    ...block,
  ],
];
final preview = blocks
    .expand((rows) => rows)
    .where((row) => row.toPlainText().trim().isNotEmpty)
    .take(keep)
    .toList();
// Each row is drawn as Text.rich(row), one terminal row each.
```

```dart
class Markdown extends StatefulWidget {
  /// The rows a [Markdown] of [text] draws at [width] cells with [theme],
  /// split at its top-level blocks: one list of rows per block, each row a
  /// span of the glyphs and styles the widget paints there. The blank row
  /// the widget puts between two blocks is not in either, so a caller that
  /// folds or counts Markdown of its own puts it back where it needs it.
  static List<List<TextSpan>> blocksOf(
    String text,
    int width, {
    required ThemeData theme,
    bool quoteBars = true,
  });
}
```

- **Name and place.** A static on `Markdown`, as `heightOf` is, so it
  reads as "what this widget would draw". Flutter has no counterpart;
  `…Of` follows `heightOf` and Flutter's `Theme.of`-style lookups.
- **Arguments.** `text` and `width` positional, as `heightOf` takes its
  source and width. `theme` is required: the widget reads it from the
  context, and a silent plain default would give rows that differ from
  what is on screen. `quoteBars` defaults as the widget's does. Nothing
  else: no growing, selected code block or code buttons; this is a
  finished document, laid out as a non-growing widget with no controls.
- **Return.** `List<List<TextSpan>>`: blocks, then rows, then one
  `TextSpan` per row whose children are the row's runs, each with its
  resolved `Style`. `TextSpan` is already public and drawn by `Text.rich`,
  so no new type is needed. A row is the cells the widget paints, from
  column 0: a gap between glyphs is a plain space, a row tint is carried
  on the row's cells up to its painted width, and trailing unstyled
  spaces are dropped. A blank row inside a block (a loose list's, a code
  block's) is `TextSpan('')`.
- **Blocks.** The visible top-level blocks, in order, as the widget lays
  them out with `spaced: true`; a block the widget does not draw (an
  image alone, an empty document) gives no entry, and a block it draws
  (a lone link definition, which it shows as written) gives one. Nested
  blocks (list items, a quote's paragraphs) stay inside their top-level
  block.
- **Same as the widget, by construction.** It runs the same shaping the
  widget paints from (`shapeSelectionSource` over a Markdown source), cut
  at the gap rows the shaping inserts between top-level blocks. No second
  layout, no parsing of its own.
- **One exception to identity (lead's choice, 87fbeb7a).** Where the
  widget's cell holds a lone glyph of no width (a zero-width space
  U+200B, a lone combining mark such as U+0301), `blocksOf` gives that
  cell a space in the same style, since a row of spans cannot hold a cell
  with nothing of width in it. Columns, styles and every other cell stay
  identical. Pinned in `test/widgets/markdown_blocks_test.dart` by "a
  glyph of no width alone in a code frame, a zero-width space or a lone
  combining mark, takes its cell and the row still ends", and by the
  group "glyphs of no width", cell-for-cell against the widget at 40 and
  80 columns.

### Tests (`test/widgets/markdown_blocks_test.dart`)

1. Two paragraphs, a heading and a list give three or four blocks in
   order, with the heading's rows bold and underlined in the theme's
   heading style and the list's numbers dim, as the widget draws them.
2. **Identity with the widget.** For a body with a heading, a tight and a
   loose list, inline code with `__` in it, a fenced block with a blank
   line inside, a quote and a table: rendering `Markdown(text)` at
   widths 40, 77 and 120 through the tester gives, row for row, the
   blocks joined by one blank row (text and style per cell).
3. `sum(rows) + (blocks - 1) == Markdown.heightOf(...)` for the same text
   and width.
4. Wrapping follows `width`: a paragraph wider than it wraps to the
   widget's rows; a block that fits is one row.
5. A fence with a blank line inside stays one block, its blank row
   inside it as `TextSpan('')`; inline code containing `__` is one
   inline run (the cases the port's first splitter got wrong).
6. Empty text and image-only text give `[]`; a lone link definition
   gives the one block the widget draws for it (identity wins over a
   guess at what should be hidden).
7. `quoteBars: false` gives a quote's rows without the bar, as the widget
   with `quoteBars: false`.
8. The port's own check stays in `example/chord`: /team show's preview
   and `+N lines` for the fake's `bugfix.md` at 120x40 (`+24`) and 80x24
   (`+27`), as in `docs/design/evidence/CTUI-37/5-show-saved-*`.

The README's widget list and AGENTS.md need no new example; writer adds a
line for `Markdown.blocksOf` where `heightOf` is mentioned, if anywhere.
