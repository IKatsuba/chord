# C4 actual startup CLI and B0c/B0d: visual acceptance

Initial CLI handover: `753f6d7`. Port offering/options fix: `ce3fd15`,
with first-result latch `ccfa367`. Picker base: `b1ce1b3`; corrected
minimal reset/resize and option handling: `55ac03c` plus `eeab17f`.
Terminal ownership fix: `2f1492f`; final guard follow-up: `ace051b`.

## Actual commands and scope

Ran `dart run example/chord/bin/chord.dart` with no agent, beside the
original's plain `bun dev chord` from its checkout, at 120x40 and 80x24.
Used the real PATH-derived inventory and actual working directories.
Saved captures replace private directory prefixes with `<checkout>`;
real directory suffixes were verified live. Redacted strings must not be
used to measure their original centering. The art/list geometry remains
as captured. Text/ANSI and side-by-side files retain versions and directory
differences, which are expected.

Only the port's no-override Claude route was selected, after developer
confirmed that it opens the existing interim window without connecting to
an agent. The original was only navigated and canceled. Explicit
`dart run example/chord/bin/chord.dart claude` served as the safe interim
comparison. No real agent or model was started.

## Findings and final observations

The initial actual CLI showed 37 agents versus the original's 29, opening
at preferred Claude rather than retaining preceding rows. End could move
the view away from its highlight, and the last-item footer disappeared.
The lead kept all four findings in scope. ce3fd15 plus B0c now match the
original default inventory of 29, including omission of the eight missing
own-CLI agents. Claude remains item 4, with items 1-3 visible above it.
Home/End/PageUp/PageDown are inert. At the last item, both show the same
outside-view footer: +17 at 80x24 and +15 at 120x40.

The first correction still lost preceding rows on 120x40 to 80x24 resize.
The lead extended the opt-in policy to minimal movement from the current
view. The final recheck retains Claude and items 1-3 across that resize;
resizing the last-item view back to 120x40 also matches the original.
Fresh starts at each standard size match the same geometry and inventory.
B0c visual acceptance includes 55ac03c and eeab17f.

The first safe selection produced a blank, key-dead terminal while its
Dart process remained alive. Explicit Claude displayed the interim as
expected. That failed-process capture is deliberately retained; the owned
stuck process was terminated and its session removed before further work.
B0d now lends one caller-owned terminal to the selector and window. In
fresh 2f1492f runs, selection displays the expected interim at both sizes;
the selected 80x24 frame is identical to the explicit route before path
redaction. Ctrl+C exits both processes. A further fresh ace051b run at
80x24 again matches that explicit interim frame and exits on Ctrl+C.
The public injected-input constructor and Future<void> close signature
match the approved B0d design. Backing-stream lifecycle/code details are
reviewer/tester coverage, not a designer audit.

Fresh startup cancellation passes: Ctrl+C at 80x24 and Esc at 120x40 each
return exit status 0, leave alternate screen mode, and restore the exact
pre-run stty state. c4-final-cancellation.txt records those observations.
The original's Esc and Ctrl+C cancellation were also checked live.

## Result and limits

Pass for corrected C3/C4 and the B0c/B0d visible integration. No visual
finding remains. Initial/fixed-attempt captures preserve the earlier
failures; final-* captures and ace-picked are the successful states.

Designer ran no test suite or native compile. Post-pick PATH refusal,
forced-exit cleanup, cached-stream after-close behavior and injected-source
ownership were not manually reproduced here; their code and test gates
belong to reviewer/tester. No automatic terminal color-depth claim is
added beyond the C3 artwork evidence.

All owned selectors, interim windows and holder shells exited or were
removed. Final selected-route Ctrl+C exits were verified by process and
tmux checks. No owned process, tmux session or child agent remained.
