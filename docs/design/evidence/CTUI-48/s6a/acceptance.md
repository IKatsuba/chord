# S6a designer acceptance

Implementation: `4f3c500c67776e7e30e8293070ef98f054416b5c`.
Approved design parent: `2588ac7d5824243c160c734fd0329574152c1228`.
Developer held a clean exact runtime window. No API/screen finding; hand this
framework unit directly to reviewer. No port implementation was inspected.

Markdown.selectedCodeBlock and onCopyCodeBlock retain the approved public
names, types and defaults; fromSelectionSource validates the frozen callback
geometry setting. No additional public constructor surface was introduced.
The controls read consistently with the existing widget API.

Run capture.py from repository root. It launches
`env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dart run test/fixtures/markdown_controls.dart`,
adding --light or --plain. Six runs cover120x40 and80x24 in dark/light/plain.
The initial independent120x40 dark probe is also retained. All actions use the
fixture's registered keys; its two header rows list them. All pointer input is
synthetic SGR via send-keys -l; it proves protocol routing, not physical input.
The only copy callback records text in fixture state; no clipboard is involved.

Every `<theme>-<size>-<state>` has plain .txt and ANSI .ansi captures.

| State suffix | Live result at both sizes and all three themes |
| --- | --- |
| initial | One TS control; quote and open Dart fence have no control. |
| clicked | Copies1 is `\tcopy body\n\ntail`, preserving the tab and blank row without a structural final LF. |
| quote-emphasized | Quoted frame/label changes tone; outer quote bar stays dim; no button appears. |
| quote-recorded | Ctrl+Y records quoted body through the same callback; Copies2. |
| closed | F2 closes Dart; now two ordinary controls. |
| last-emphasized | Dart frame/label/button use the picked tone; button bold. |
| covered-no-copy | F3 overwrites the first border; old button-cell click does not increment Copies2. |
| selected | A body drag followed by Ctrl+S reads `copy`. |
| moved-no-copy | Pressing a button clears that range; movement before release does not copy. |
| revision-no-copy | F2 changes the source while pressed; old release does not copy. |
| wheel-no-copy | A wheel report at the button does not copy. |
| narrow15 / narrow14 | TS label+button fits at15 columns; at14 the button is omitted and body wraps normally. |

Ordinary button text is terminal foreground against a dim frame, with one dash
after the word and no blank button padding. Picked dark/light frame accents
match the active ThemeData; plain uses terminal foreground with a bold picked
button. All plain captures have no foreground/background SGR. At80x24 the
whole normal fixture, draft and recording feedback remain visible and readable.
At the extra14/15-column probes the instructional header wraps and some bottom
feedback is clipped; these probes judge the code control, not a promised tiny
fixture layout. Resizing back and quitting succeeds.

This standalone framework screen is not a port screen, so no original pairing
or real port pick-mode claim is made. The mounted Markdown sits outside a lazy
list; the handed tests prove its public visible descriptor query. S6b retains
the port catalog/keys/help/coexistence and negative current plain Plan/Tool
cases. Reflow/disposal, all six word-cell hits, partial/unknown coverage and
reentrant capture safety have handed automated coverage; they are not additional
live claims inferred from these captures.

handed-checks.txt retains final developer result excerpts: framework1132 and
port590 passed on the same implementation bytes, with command manifests in the
ignored build directory. No suite, compile, real model/agent, clipboard or
physical pointer check was run by designer. No pre-implementation runtime was
reconstructed and no live failure/fix claim is made.

All six final panes and the initial probe exited0. The owned tmux server and
fixture processes are gone; cleanup.json records checks. Capture privacy scans
found no private path. Only this assigned evidence directory was written.
