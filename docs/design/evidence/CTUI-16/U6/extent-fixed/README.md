# U6 extent fix: visual recheck

Visual recheck of fix `b4489d9` over U6 `4575a12`.
Ran the same transcript_list.dart fixture in owned tmux at 120x40 and
80x24. Same color environment and capture flags as initial U6 evidence.
End followed output with no rule, PageUp held and showed new-output/count,
Home returned to the first thought, ctrl+o changed its displayed height,
and resize kept the screen coherent. No new visual regression. ctrl+q
stopped output; owned session exited and was removed.

The supplied running fixture does not expose the offscreen unchanged-entry
settlement or PathView replacement that caused reviewer's geometry finding.
Those cases remain established by developer's focused regressions and
source re-review, not by these screenshots. This recheck confirms the
handed-over fix preserves the existing on-screen presentation. Initial U6
original comparisons remain applicable.
