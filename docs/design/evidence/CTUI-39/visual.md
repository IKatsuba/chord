# CTUI-39 designer look

Handed over: U1 cd3e7cb, U2 0af1f41. Ran `dart run example/demo.dart`
in the designer's own tmux session; session removed after captures.

At 120x40 and 80x24 the header reads cleanly, the theme label is complete
and right aligned, and the log, prompt and key hints retain their layout.
These first captures inherited NO_COLOR and visibly say `no colour`.
For the exact boundary, ran with NO_COLOR unset: the complete automatic
theme label fits at 48 columns and disappears whole at 47, leaving a clean
header. Ctrl+t makes the shorter `dark (ctrl+t)` label appear at 47.
Widening to 80 preserves the complete label. Text and ANSI captures are
paired. No visual finding. This is a framework demo; no original port
comparison applies. The focused test results are developer's handover,
not a designer audit or a claim of tester acceptance.
