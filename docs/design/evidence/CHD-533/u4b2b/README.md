# U4b2b selected-team screen check

Visual PASS for the handed screen unit, with the fixture entry correction
and additional genuine delayed-link check described below.

## Provenance

- Production screen code: `e41230201ce1053da6be5a5b31d8f1440b7a0ae6`.
  `e4123020/` holds normal, members, refused, soft and long cases at
  120x40 and 80x24. Captured 2026-10-27, 19:14-19:15 UTC.
- Fixture-only followup: `e23c2b7de165d2769aaf25ebe615297d4fc50d42`.
  `e23c2b7d/` holds corrected receipt-only Resume, actual-ID inspection
  and delayed-link cases at both sizes. Captured 19:24-19:29 UTC.
  Production display code is unchanged by this followup.
- Approved presentation additions: `765eb9e0` (receipt-only Resume) and
  `3e32d051` (Chord-owned unlinked receipt report).

The later evidence commit contains captures and this note only. Each run
used an archive of its exact handed commit outside the shared checkout,
with dependencies linked from the checkout and preserved during QA.
Neither snapshot linked the original Git directory/index or a worktree.
The archived lockfile provides the dependency specification. No later source
work was used for these captures.

## Method

Run sequential own tmux sessions at 120x40 and 80x24 with the archived
tracked launcher:
`nice -n 19 bun tests/fixtures/selected_team_qa.ts <case>`.
Its fixed named QA directories isolate settings and state; every candidate
command is fake and resource sources are explicit fixtures. No live provider,
model, auth-source, credential or login call was used.

For normal, members, refused, soft and long, type `selectedteam` using
`send-keys -l`, then Enter separately. Capture the result, Home/PageDown
scrolling, ctrl+o and expanded saved choices. Files ending `bottom` show
the latest output; `home` and `pageN` cover the report's scrollback.
The members captures include its initial unopened reviewer and subsequent
confirmed reviewer in the expanded report.

For receipt, type `/resume`, capture the `Team attempt: fixture` picker,
then Enter. Capture both actual admitted attempts, long reasons and their
recorded failures/planned reviewers. Inspect an actual displayed run ID
with `/team show <ID>`, and scroll the returned report. This explicit
inspection adds a report; it does not relaunch the team.

For late, type `selectedlate`. Capture the planned Chord-owned report,
then release the fixture's start gate and capture the revised confirmed
report. Release its link gate and capture the actual delayed provider ACP
notification replacing the owned report with one ordinary Team row.
The fixture gates are bounded; this is a screen check, not a timing test.
Some `planned-home/page` captures already include the revision: filenames
name the capture phase, not a claim that state stayed frozen while scrolling.
Use the `planned-bottom` and `confirmed-bottom` pair for the same-ID state
comparison. At wide size the ID is `402ae7a3`; narrow uses `28ce705d`.

Every saved capture was inspected as terminal text, including intermediate
scroll positions and ANSI variants. ANSI variants were compared with plain
text and their emitted style attributes inspected; some preserve an extra
trailing space at a wrapped boundary. No images were generated.
All own sessions were killed; the final tmux query found no server and the
process query found no matching QA or fixture helper processes.

## Findings

No blocking visual finding. Job, full reason, uncertainty warnings and
planned versus actual configuration remain visible in ordinary scrollback.
Long narrow reasons wrap beside the gutter; ctrl+o exposes saved choices and
changes. The soft case distinguishes requested high effort from observed
medium with its advisory note. The refused case says the first job was not
delivered and keeps unobserved configuration unknown.

Receipt-only Resume uses its derived title and actual activity age, with no
synthetic prompt. The two real admitted attempts retain different run IDs.
The Chord-owned heading has no ACP tool marker; it explicitly says current
state unknown and historical observation during replay/inspection. Actual
refusal and unopened reviewer state remain visible, without a success claim.
Missing recorded time stays unknown.

Late-link captures show one latest same-run owned report changing from
unconfirmed to confirmed. The genuine linkage replaces that report with a
single normal Team row; no owned fallback remains. This dynamic observation
is separate from the developer's reducer/harness test evidence.

The original receipt launcher opened codex while its seed record belonged
to fake, so its existing runtime filter showed no session. The inspected
`e4123020/receipt-launcher-runtime-mismatch-120x40.txt` records that fixture
entry gap; it is not passing receipt evidence. An attempted `/new` fallback
was stopped and contributes no proof. The signed fixture-only followup fixes
the entry path; all passing receipt captures use that followup. Some local
capture waits were adjusted to account for headings outside the narrow
viewport and text wrapped across rows; no product/source edits were made.

Scope is a first visual look at the handed unit. Implementation review,
full suite, release targets, compiled execution and real-provider behavior
were not checked by designer. No later U5 work was inspected.
