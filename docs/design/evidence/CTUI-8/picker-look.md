# Picker live look

Handed over 04b43cb + c3c3a58, based on pure state b306ff2. Ran
`env -u NO_COLOR dart run example/picker.dart` in an owned tmux session at
120x40 and 80x24, then 80x4 and 80x3. Text and ANSI captures are paired
where style matters. Session removed. This framework fixture needs no
original port screen comparison; rows are judged against the source-derived
design, not as a completed chord picker screen.

Two findings returned together to developer before reviewer handoff:

1. Initial KeyHelp omits enabled navigation, acceptance, number and scroll
   keys. At both initial 120x40 and after six Down presses reaching multiline
   Choice 7, it lists only Edit filter, Cancel picker and Quit. Arrow keys
   work. Entering and leaving filter mode makes navigation descriptions
   appear. The editor also lists only Escape Finish editing filter and Quit,
   despite Enter finishing editing too. Expected enabled described Actions
   to appear on the first settled frame, with editor Enter included.
2. The example does not constrain Picker to its viewport room: at 80x3 no
   choice is visible (title, blank row, Filter: 2 only), but pressing 4 still
   accepts Choice 22. Restoring 80x24 visibly reports Chosen: choice 22.
   Its nonflex Picker under Column receives unbounded height. The example
   must bound the list, protect permanent rows and disable acceptance when
   no choice fits. The advertised 80x4 no-room example actually paints one
   choice row. Captures record both widths before and after hidden input.

Successful observations: aligned dotted numbers, whole-row focus styling,
multiline Choice 7 with its edge markers and exact hidden-choice footer,
query 2 ranking, digits and j editing instead of navigating in editor,
no match decoration, numbered navigation selection, No matches for 2j,
first Esc retains the query and leaves editing, second Esc cancels visibly.
Re-look of both findings required before reviewer handoff. No broad suite
or implementation audit run by designer for this screen unit.

## Re-look: 52473eb

Ran the same owned tmux fixture at both required sizes, plus 80x3/80x4.
Initial navigation hints now list enabled navigation/selection keys, and
the editor lists both Enter and Escape Finish editing filter. At 80x3,
pressing 4 and Enter and then restoring 80x24 leaves Chosen: nothing yet.
The functional fixes pass. Captures use picker-fixed-* names.

One part of finding 2 remains: permanent rows are still not protected in
the short fixture. At 80x4 the title and blank rows consume the screen above
Chosen, with KeyHelp clipped away. At 80x3 neither Chosen nor KeyHelp is
visible. Returned to developer to drop title/gaps before permanent status
and active hints when height is short. This is fixture composition; no
remaining hidden-acceptance observation. Session removed after captures.

## Fixture composition re-look: fcc2db4

The lead split widget acceptance from this example-only correction. Live
80x4 now shows Filter, one visible choice with lower-edge marker, Chosen
and active KeyHelp. At 80x3 it shows Filter, Chosen and exactly the enabled
no-choice editing/cancel/quit hints. Title and blank rows give way first.
Both permanent rows stay visible. Remaining fixture finding cleared;
picker-final-* text/ANSI captures prove the two short states. Session
removed. The prior 120x40/80x24 captures and functional fix checks stand.

## Reviewed focus change and theme completion

Handed over fbf0273 and both-size focus assertion commit 4207a57.
Live filter query 14, multiline result and editor focus survive the resize
120x40 -> 80x24 -> 80x4 -> 80x24. The lead explicitly accepted the unfocused
state through headless screen assertions rather than a separate external
focus fixture. Ran `dart test test/widgets/picker_test.dart -n 'only while the picker has focus'`:
2 pass, one per required size. Plain unfocused rows/no marker, focused
marker, editor focus and clearing after focus returns to the prompt are
asserted. The unfocused-state gate is clear on that stated basis.

Completed light and plain live runs at both required sizes, using
COLORFGBG=0;15 with NO_COLOR unset, and NO_COLOR=1, respectively. A new
styling finding appears in custom itemBuilder content: the selected row's
marker and number take theme.focus/bold, but Text(item.label) and multiline
continuations remain plain. The builder has no highlighted argument; the
row must supply inherited selection style for ordinary custom content.
Returned to developer; default-label focus assertions do not cover this.
ANSI picker-light-* and picker-plain-* show reset before the selected
custom label. All owned tmux sessions removed.

## Custom content style finding re-look: 7d9776f

Ran the example in light and plain modes at both required sizes, filtered
to multiline Choice 14 with the editor focused. Both label lines now inherit
theme.focus+bold in light mode and bold without colour in plain mode.
Text/ANSI picker-style-fixed-* captures confirm the style runs cover the
label and continuation, not only marker/number. Ran the handed-over
`a builder's lines take the highlighted row's style` assertion: 1 pass,
covering explicit red override and reset when unfocused. Finding cleared;
no remaining Picker visual gate. All owned sessions removed.
