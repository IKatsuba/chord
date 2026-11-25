# U54c2: exact resume row geometry live look

Handed implementation: signed `79dc587888abcc85653462903734f3ba5e744a90`.
Designer API/composition and screen look pass to reviewer, with the accepted
narrow difference below. No code audit or AOT performance pass is claimed.

The approved numeric seam exposes integer counts/reset only, separately
naming choice calls/projected choices, line passes/overflow passes and row
shaping. It is documented internal measurement support, not an app feature.
No broader diagnostics or package/API is proposed by this visual gate.

## Paired original and port

Original head `577b58167672e12c999aeaf4eed2a1a988513dc2`.
First ran original `bun dev chord --fake --qa designer-ctui54resume` to
confirm its normal QA window. For reproducible matching state, both live
windows then used identical isolated synthetic version-1 record projections
and the task checkout as cwd. Original used its source launcher with Bun's
production define and explicit fake command; port used bin/chord.dart with
the same fake command and separate XDG state/config. No original source was
edited and no real model/agent/account was reached.

Seed 30 compact type-first JSONL files, UUIDs with integer values 1..30;
header type=session/version=1/agent=fake and a single prompt/turn-1/images=0.
Times are one through thirty hours before capture setup. Even indices use
current cwd; odd indices use synthetic other-directory labels. Prompt zero:
`Inspect the saved notes and retain this descriptive title across wrapped lines.`
Other prompts: `Saved session <i> · 界😀 with a long title and an_unbroken_title_tail`.
No opened-only live record is offered as a saved prompt. Local has 15 choices;
all has 30. Both windows type `/resume` literally, then Enter in a separate
call; Ctrl+A changes scope. Capture 120x40 and 80x24 before further input.

The paired `u54c2-comparison-local-*` and `comparison-all-*` put original
beside port. Matching individual `.txt` and `.ansi` files remain the
source evidence. At both required sizes frame/title/body/gaps/hint, number
column, metadata alignment, title wrapping, selected style, arrows and hidden
counts match. Local at 120x40 shows nine choices plus six hidden; 80x24 shows
three partially visible choices plus twelve hidden. All scope stacks titles
at 80x24 and shows 28 hidden. The prompt/status rows stay fixed.

Established staged differences outside this slice remain: original version
0.71.0 versus port 0.0.1, and original compact header's additional `/help`.
No new difference at the standard sizes was found. Ages froze on opening.

At 32x10 all scope both omit acceptance/navigation because no choice fits.
Original overwrites the bottom border with the wrapped `Esc to close` text;
port clips that text and retains an intact border. Lead explicitly accepted
the port rendering under the standing small visible layout-slip/OpenTUI
quirk exclusion, recorded in signed decisions commit `c1fb6c8`. Keep both captures; do not
reproduce the overwrite. This pair establishes no source/cache regression.

## Handed agent-free fixture

Ran `dart run example/chord/tool/resume.dart --many`. At both required sizes
local rows and overflow remain legible; Ctrl+A switches scopes/remounts from
the top. `u54c2-fixture-many-*` and `fixture-all-*` retain these observations.
The fixture has frozen year-2000 dates/labels and six body rows; it is not
substituted for the matching live original/port state above.

Local 41x24 stacks metadata/title; neighboring 42x24 uses the hanging
layout. The long title wraps with the number inset, and hidden counts
change with actual visible choices. Both captures are retained. At 48x24
all-scope metadata remains one clipped line; the hint wraps below it.

`--many --tall --light` at 80x24 keeps choice one while Down scrolls one
physical row, from source lines1..6 to2..7. The tall selection suppresses
the hidden-choice footer. Resizing to120x40 preserves the selected item
and correct line rendering. `--many --zero --plain` at both sizes retains
scope/cancel hint only; Enter/Down/digit1 at80x24 select nothing. No chosen
status appeared. These cases have text/ANSI evidence; light uses NO_COLOR
removed and plain explicitly sets it. No image/display latency is measured.

Empty local scope (`--many --empty --light`) at120x40/80x24 draws
`No earlier sessions in this directory.` and only scope/cancel hint.
Ctrl+A restores all-directory choices and Enter reports `Selected saved-0`;
retained `fixture-empty-*` captures cover that transition without IO.

## Hygiene and limits

Captures replace the complete displayed task cwd with `fixture-project`;
complete synthetic other-directory paths are sanitized when present.
This shortening does not relayout original cells, so sanitized labels are
not a width oracle. Shared Unicode captions/titles and numeric counts are
unchanged. A first port launch wrongly included unsupported -C and exited
before any screen; it was corrected to run from the mandated task cwd.
No output from that setup error is treated as product rendering evidence.

All owned windows exited cooperatively (Esc then Ctrl+D for live fake,
Ctrl+Q for fixtures). The owned tmux server ended, no relevant Dart/Bun/fake
process remained, and all owned synthetic state/config/QA roots were removed.
Designer declared numeric idle before developer's actual-resume AOT runs
and performed no captures/builds/tests/edits/commits during that boundary.
AOT work/correctness counters and responsiveness are separate review/tester
gates. No unhanded implementation or test WIP was inspected.
