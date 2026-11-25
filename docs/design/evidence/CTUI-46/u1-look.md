# CTUI-46 U1 visual pass

Handed implementation: `20d3f0f`. Designer ran the named standalone
`dart run example/chord/tool/raw_output.dart` fixture in an owned tmux
session at 120x40 and 80x24. The Read headline and two Python source rows
are clear and aligned, with no exit-code JSON. No key is needed to reach
the state; Ctrl+Q exits. Both plain and ANSI captures are saved here.

Original `bun dev chord --fake --qa rawoutputs` was run at the same sizes,
then sent `rawoutputs` literally and Enter separately. It shows a View
file result as source alone and preserves Search's matches/files JSON.
`u1-comparison-*` places that broad original scenario on the left and the
synthetic port Read on the right. They are different scenarios; this is
not an exact same-source or same-wire parity claim. The original fake
contains no exit-only object. Main approved suppressing only the numeric
zero exit-only object as a small visible slip of both source versions.
Exact real-agent update order remains unobserved; developer regressions
cover before/same/after content ordering.

Visual result: pass for the handed unit. Empty surrounding rows, source
indent and colours read correctly at both sizes. Captures contain no
private directory. Original fixture session was killed; the port exited
with Ctrl+Q. No real agent, model, suite or compile ran in this visual look.
