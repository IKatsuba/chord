# U4 final marker-style recheck

Pass for fix `4c9cbf2` over `ef2d78f`, production U4 `e79711d`.
Ran transcript_entries.dart --plan-long in owned tmux at 120x40 and 80x24,
with NO_COLOR unset and truecolor terminal settings as before. ctrl+q
exited. Captures use -p; `.ansi.txt` uses -p -e.

The text matches the original runtime reference in ../corrected/ at both
sizes. The ANSI capture now resets to dim at `...`, then restores strike
for the tail. This matches the original DIM-only marker between
DIM|STRIKETHROUGH source spans. Both U4 long-plan findings are resolved;
earlier entry-state and wrapping captures remain applicable. No visual
finding remains for U4. Owned session exited and was removed.
