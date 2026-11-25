# Unit 3 captures

Taken at 93a40dde, from a clean export of that commit, through
`dart run example/chord/tool/dev.dart chord --qa <name> --fake` beside
`(cd ../chord && bun dev chord --fake --qa <name>)`, with
`CHORD_FAKE_CHILD_RUNTIME=fake` and the fake's `bugfix.md` copied into
`.chord/teams/` before the prompt `team`. The capture directory is
relabelled `~/project` in both.

- `3-run-team-*`: main after `team`: List teams, Team(bugfix) and its job.
- `3-lead-open-*`: ↓ ↓ Enter to bugfix: the lead's Open(tester) and
  Open(coder) rows.
- `3-lead-list-teams-*`: `team` typed to the lead. The port's
  "Internal error" is the accepted G1 difference (docs/design/CTUI-35.md,
  docs/decisions.md), not unit 3's.

The agents list differs (no `team ·`, no `├─`/`└─`); that is unit 4.
The version line differs as everywhere.

- `3-left-open-*`, taken at 271d649e from a clean export: after `team`,
  ctrl+d with the team open, then chord started again in the same
  directory and state with `fake --resume` (the original with
  `-C <dir>`), choice 4, `team`. The last dim line names
  `team bugfix (3 agents)`. Text and styles match; only the version
  differs. The refusal for a closed run ("closed when this session was
  left") has no fake scenario that reaches it and was not captured.

# Unit 4 captures

Taken at 04dd069a from a clean export, the same route (`--qa`, the fake's
`bugfix.md` staged, `CHORD_FAKE_CHILD_RUNTIME=fake`).

- `4-list-unfolded-*-120x40`, `4-list-folded-*-80x24`: after `team`.
- `4-two-runs-*`: after `team2`; both runs fold to `3 agents` with the
  asking member named.
- `4-list-member-picked-*`, `4-member-view-*`: ↓ to `tester`, Enter: box
  title `tester · bugfix`.
- `4-member-header-*`, `4-member-ctrl-o-*`: the member's header and the
  instructions line, collapsed and expanded. The expanded text wraps a word
  earlier in the port only because its directory is `/private/tmp/…`
  before relabelling (CTUI-91).
- `4-lead-picked-*`, `4-x-armed-*`, `4-x-twice-*`: `bugfix` picked and `x`
  pressed while only a member's permission is pending. Both leave the team
  open and show no armed line; the armed line itself is not captured.

Differences are only timers and the version line.

# Unit 6 captures

Taken at 867add81 from a clean export, the same route, with no team file
before `propose`. In the port's captures `<qa config>` stands for the
`--qa` run's own configuration directory, which the port's dev runner sets
and the original's does not (the save box's second choice names it).

- `6-proposal-box-*`: `propose`, the box `Save team bugfix?`.
- `6-saved-*`, `6-proposal-top-*`: 1; the green saved line, and the
  headline, description and table scrolled into view.
- `6-change-efforts-box-*`, `6-change-*`, `6-change-box-*`,
  `6-change-top-*`: `proposeefforts`, then words: `Team(bugfix) · change`,
  `~` marks, the effort column and dim `was`, `Replace team bugfix?`.
- `6-again-box-*`: Esc, then words: tester on `bypassPermissions` in the
  warning colour, `was acceptEdits` dim.
- `6-ctrl-o-*`: ctrl+o, the opened table.
- `6-body-box-*-80x24`: after a save, words: `bugfix.md's body · 1
  addition, 1 removal`. `6-saved-*-80x24` and `6-body-box-*-80x24` were
  retaken at 42186dbe, where Markdown under `⎿` wraps as the original's.

# Unit 5 captures

Taken at 42186dbe (unit 5's fixes) from a clean export, the same route,
with the fake's `bugfix.md` and a broken `triage.md` (`# no frontmatter`)
staged. `<qa config>` as in unit 6.

- `5-slash-list-*`: `/te`. `5-completion-*`: `/team show b`.
- `5-picker-*`, `5-picker-broken-*`, `5-picker-enter-*`: `/team`; ↓ to
  triage; Enter on bugfix puts `/team run bugfix ` in the draft, and no
  `› /team` row is left.
- `5-show-saved-*`, `5-show-saved-ctrl-o-*`: `/team show bugfix`, folded
  and expanded, the body through Markdown.
- `5-run-*`, `5-show-running-*`: `/team run bugfix Fix issue 214.`, then
  `/team show bugfix` while it runs.
- `5-stop-refusals-*`, `5-refusal-*-80x24`: `/team stop bugfix`, then the
  refusals, each in red under `⎿`.

Differences are only timers, run ids and the version line.

# Unit 7 captures

Taken at 3bdf4454 from a clean export. The port runs
`CHORD_FAKE_RESOURCE_CASE=<case> dart run example/chord/tool/dev.dart chord --qa <name> --fake`
and the prompt `resources`. The original runs
`(cd ../chord && bun tests/fixtures/resource_qa.ts <case>)`, its own
Resources capture route (codex on the fake's `resources` scenario), and
the same prompt; its header therefore names `codex`. The original's
`bun dev chord --fake` is not used: its `--define` does not reach
`process.env['CHORD_RESOURCE_FIXTURE']`, so it reads the person's real
usage. Cases `normal`, `partial`, `timeout`, `unavailable`, each at
120x40 and resized to 80x24. Rows, styles and wording match; `timeout`'s
Read time differs by a second.

`5-show-saved-*` and `5-show-saved-ctrl-o-*` were retaken at 6de1caea
(the preview and count from `Markdown.blocksOf`): unchanged, `+24` at
120x40 and `+27` at 80x24, as the original's.

# Unit 9 captures

Taken at f7963a48 from a clean export. The original runs
`(cd ../chord && bun tests/fixtures/selected_team_qa.ts <case>)`, which
writes its settings (fake commands for `fake`, `codex` and `claude`,
`teamSelection: balanced`), the `fixture` team and fixture resources. The
port is started with exactly that layout written by a mirror script into
its own capture directory: the same settings and team file,
`CHORD_FAKE_SELECTION_CASE=<case>`, `-DCHORD_RESOURCE_FIXTURE=true`, and
`chord codex --agent-command '<bun> <fake> --scenario selectedteam'`.
Prompt `selectedteam`.

- `9-selected-<case>-120x40` for normal, members, refused, soft, long:
  identical but for run ids and timers.
- `9-selected-normal*-80x24`, `9-selected-normal-ctrl-o-*`: ctrl+o's
  saved definition and changes. At 80x24 the port breaks
  `effort agent default (` / `unconfirmed)` where the original keeps
  `(unconfirmed)` whole on the next row (sent back to developer).
- `9-show-run-*`: `x` on the lead, then `/team show <run ID>`: the
  recorded receipt, identical.
- `9-resume-attempt-*`: a refused attempt, ctrl+d, then `--resume` on the
  same state: both list the main session only.

`9-selected-normal-80x24` and `9-selected-normal-ctrl-o-80x24` were
retaken at 3274dd93: `(unconfirmed)` now moves whole, as the original's.
Because that fix changes how every tool's lines wrap, `3-recheck-team-*`
and `6-recheck-propose-*` (80x24, the same commit) check two other long
tool rows: identical but for timers.

# Unit 10 captures

Taken at fd75ba56 on the `team` route, with `CHORD_RESOURCE_FIXTURE=true`
in the original's environment so no real usage reader is reached.
`10-cost-run-*`: `team`, `/cost`. `10-cost-two-runs-*`: `team2`, `/cost`.
`10-cost-ended-*`: after `x` on coder. `10-cost-after-clear-*`: `/clear`,
`/cost`: `before /clear` and both runs `ended`; the order of an ended
run's agents differs (sent back to developer).

`9-receipt-resume-*` and `9-receipt-opened-*`, taken at 526588e0: the
original's `selected_team_qa.ts receipt` writes a record of two admitted,
refused attempts; both chords are then started on that same directory,
configuration and state with `fake --resume` (the original with `-C`).
Ctrl+a (the port's directory reads `/private/tmp/…`, CTUI-91), Enter.
`Team attempt: fixture` in /resume and the `Recorded Team receipt
(fixture)` blocks at the transcript's end match at 120x40 and 80x24.

`10-cost-after-clear-*` and `10-cost-settled-*` were retaken at 61107c10
with three runs (the keys started a third). An ended run's agents are
listed in the order their processes exit, in both: timing, not a rule, so
the order in these captures differs between the two and is not a finding.
The third run's `coder not reported` was a turn not finished at /clear;
the fake reports usage only at a turn's end.

`10-cost-run-*-80x24`, `10-cost-two-runs-*-80x24` and
`10-cost-member-closed-*-80x24`, taken at 61107c10: `team`, `/cost`;
`team2`, `/cost`; ↓ to the first run's coder, `x`, `/cost`. The notes
wrap under the note column; identical but for timers.
