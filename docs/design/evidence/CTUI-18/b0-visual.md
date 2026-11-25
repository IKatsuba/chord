# B0 Picker activation: visual acceptance

API commit: `4c1bc28feac2d6b0a880a6ae63eca3e96a015aec`.
Fixture correction: `0e15839` (toggle ctrl+t, focus ctrl+g).
B0a API-only handover: `007a990`.

## Method

Ran `dart run example/picker_activation.dart` and
`dart run example/picker.dart` in designer-owned tmux sessions at 120x40
and 80x24. Also resized the rich example to 20x8. Captures are tmux
capture-pane text; paired `.ansi` files retain attributes where highlight
appearance was checked. This is a framework API, so no original port
screen comparison applies.

## Observed

- Enabled picker has a clear highlight and numbered rows. Overflow edge
  markers and hidden-choice count remain readable. Moving to Choice 8
  scrolls its row into view.
- Disabling removes the highlight and picker shortcuts; the current
  viewport and rows remain in place. Explicit focus requests, navigation,
  Enter, Esc, digits and slash do nothing while disabled.
- Re-enabling does not draw a highlight until the caller requests focus.
  The kept selected choice is then highlighted again.
- With query `12`, disabling during filter editing leaves `Filter: 12`
  and Choice 12 visible without a highlight or editor cursor. A focus
  request and typing while disabled leave it unchanged. Reactivation
  remains unfocused until requested; Enter then chooses 12 once.
- The rich example reads well at both standard sizes. Empty filtered
  results say `No matches.` at both sizes. At 20x8, title/gaps disappear,
  rows and hidden-choice count remain readable, and the hint ellipsizes.
- ANSI captures show selected bold styling disappears while disabled.

The initial activation fixture used ctrl+e/ctrl+f, consumed as editing keys
inside TextInput. Developer corrected the fixture to ctrl+t/ctrl+g in
`0e15839`; remaining checks used that fix. The initial 120x40 captures and
initial unfocused/focused 80x24 captures predate only this fixture key
change. Filter, refocus and final selection captures use the correction.

B0a's handed-over public constructor and documentation match the agreed
API. It adds no appearance; its behavioral tests and code review belong
to reviewer/tester. TextInput retains editing/submission keys, as recorded
in the design. No independent test suite or lifecycle audit was run here.
The empty unfiltered-items state was not exposed by these fixtures.

## Result and cleanup

Pass for B0 after its fixture correction; API shape accepted for B0a.
No remaining visual finding. Developer's reported tests are not claimed
as designer-run evidence. Both owned fixtures exited through their quit
bindings; no owned tmux session or matching fixture process remained.
No fake agent was started.
