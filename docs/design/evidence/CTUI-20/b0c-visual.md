# B0c Picker viewport policies: visual acceptance

Handed commit: `b1ce1b3`. API design: `4bf644b`.

Ran `dart run example/picker_activation.dart --viewport` at 80x24 and
120x40. The public parameter names/defaults and descriptions match the
design. The opening view keeps Choices 1-3 above preferred Choice 4.
Home, End, PageUp and PageDown leave its view and selection unchanged.
Resizing preserves the chosen item and preceding rows. At Choice 12 the
footer remains `… +7 more`, correctly counting the seven wholly hidden
choices above the five visible choices. Navigating back with k reveals
Choice 1 and retains the below-hidden count. Text and ANSI captures record
both standard sizes. The screen reads clearly.

Pass for API and visible behavior. Zero-budget, tall-item and default
policy preservation are reviewer/tester coverage; designer ran no suite.
This is a framework fixture; corrected actual CLI inventory/viewport is
rechecked separately as C4. The fixture exited through ctrl+c and its
owned tmux session/process was closed.
