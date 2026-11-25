# B0b Picker presentation: visual acceptance

Handed API/fixture commit: `6c23d36`.

Ran `dart run example/picker_activation.dart --presentation` in an owned
tmux session at 80x24 and 120x40, then at 24x24 to expose wrapping.
Inspected the handed public constructor and parameter documentation;
wrapNavigation=false and showNumbers=true match the agreed design.

At standard sizes each choice has exactly one visible number. Up from
choice 1 wraps to choice 3; down returns to choice 1. At 24 columns, k and
j also wrap in both directions, revealing the newly highlighted choice.
Continuation lines align under the label's number, not under the text
after it. The existing overflow edge gutter remains, as designed.
Selected multiline content shares its styling. Disabling removes the
marker/style without moving its text. Re-enabling plus explicit focus
restores input; literal 2 records Answer: 2 despite no framework number
column. The layout reads clearly.

Pass for API shape and visual presentation. No suite was run by designer;
empty/single-choice and taller-than-viewport transitions remain behavioral
review/test coverage. This is a framework fixture, with no port comparison
required. Corrected B2 must separately show the original long option in
the permission box at both standard sizes.

The fixture quit through ctrl+c. No owned session or fixture process
remained. Captures retain terminal blank rows; ANSI captures preserve
selected/disabled attributes.
