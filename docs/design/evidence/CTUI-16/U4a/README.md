# U4a: middle text overflow

Designer visual pass for developer commit `ae35835`.
Ran `dart run example/middle.dart` in owned tmux at 120x40 and 80x24,
with NO_COLOR unset, TERM=xterm-256color and COLORTERM=truecolor.
Captures use capture-pane -p, plus -e for `.ansi.txt`. ctrl+q exited.

Pass: narrow-width rows agree with the original CUT runtime. Overflow at
W=3 is empty; W=4 shows `...Z`; odd spare cells go to the tail; W=10 and
W=11 do not borrow unused head cells across a Japanese grapheme. W=12
retains the whole emoji sequence, W=13 adds one Japanese character, and
W=14 fits the original text. The full-width label preserves both ends
with ASCII `...`, stays on one row and recomputes at 80 columns.
No new visual finding; owned tmux session exited.

`original-budgets.txt` records a direct read-only runtime probe of the
original's CUT props through its own tests/ui/harness.tsx draw function,
using the installed OpenTUI and the same Unicode input. No original file
was edited. This verifies the small-width behavior against the original;
code review and tester checks cover the remaining pure layout cases.
Corrected PlanRecord/Guardian/Folded consumers have a separate handover.
