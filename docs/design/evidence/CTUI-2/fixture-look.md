# CTUI-2 fixture live look

Handed over U4 83d82d3, covering U1 02d8090 + 8d2aa35, U2a 099d0e2,
U2b a5b53ad + a5de657, U3 c2d6ed6 + 01dac57. Ran
`env -u NO_COLOR dart run example/layers.dart` in an owned tmux session,
at 120x40 and 80x24. Captures pair text with ANSI where style matters.
The session was removed after capture. Framework fixture, no port screen
or original-screen parity claim.

## Finding returned to developer

With Models open, Ctrl+t from auto to forced dark removes the layer and
returns shortcuts to the base. The plain-to-auto transition does the same.
The removed entry remains in the fixture's picker field: the first Ctrl+p
only clears that stale reference, and another press opens the picker.
Expected: theme changes restyle the same open entry, preserving focus and
selection. In example/layers.dart, the conditional Theme wrapper changes
Overlay's location/type ancestry. Keep the wrapper present for auto too.
Evidence: layers-picker-dark-120x40 and layers-theme-lost-120x40.
A fix and designer re-look are required before U4 goes to reviewer.

## Observed successful states

- Focused picker, light/dark/plain at both sizes: filled cells hide the
  transcript within the surface; text outside it remains visible. Tab
  visibly moves the marker to Balanced, Enter draws `chose Balanced` and
  returns focus/shortcut hints to the prompt. ANSI confirms focus colours
  change between dark/light; plain uses bold without colour.
- Missing anchor hides the layer and its keys. Restoring returns the same
  selected field. Growing the prompt moves the layer upward and protects
  the gap, prompt and permanent rows; page build count is unchanged.
- Frameless passive completions occupy four full-width rows including
  their rule, with the prompt still holding keys, at 120x40 and 80x24.
- At 80x24, scrolled baseline and open picker both report page builds 7,
  rows 66, offset 30, scrolled back. After stream growth under the open
  picker: rows 72, offset 30. Closing retains rows 72 and offset 30.
- Tall layers reach row zero at both sizes and stop above the protected
  prompt gap. Their raw fixture content is clipped; preserving a Dialog's
  title/hint/choices under shortage belongs to CTUI-8, not this fixture.
- At 80x5 with a two-row prompt there is no layer room. No picker or entry
  keys paint; normal base hints remain. Restoring 80x24 restores the layer.

The first theme-loss captures temporarily used light/plain filenames; those
files were replaced with actual open light/plain picker captures after
reopening under forced themes. layers-after-theme-toggle-120x40 records
an additional successful reopening, not a separate finding.

## Theme finding re-look: 1b867c9

Ran the handed-back fixture in owned tmux at both required sizes, paused
the stream, opened Models and focused Balanced. Cycled auto -> dark -> light
-> plain -> auto at 120x40 and 80x24. The same open picker and Balanced
focus remain through every transition; ANSI shows the frame restyled.
Rows and offset remain unchanged across each theme cycle (theme dependency
rebuilds are expected). Escape then one Ctrl+p cleanly reopens at 80x24,
with no stale-reference extra press. layers-fixed-* captures provide the
full cycle. Finding cleared; all CTUI-2 live-look gates now pass. Session
removed. No change to earlier movement/scroll/zero-room observations.
