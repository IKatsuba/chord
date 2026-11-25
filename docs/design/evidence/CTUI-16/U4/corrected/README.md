# U4 long-plan recheck: remaining marker style finding

Checked developer fix `ef2d78f` with transcript_entries.dart --plan-long
in owned tmux at 120x40 and 80x24, with the same color environment as U4.
Captures replaced startup-only blank frames after waiting for rendering.
ctrl+q exited and the owned session was removed.

The text cuts now match original PlanRecord exactly at both sizes.
`original-plan-long.txt` renders the original component through its own
read-only draw harness, with matching outer padding and the same long
completed-step text. No original files were edited.

One remaining finding was sent developer: the port strikes through the
ASCII marker as well as the source text. Original PlanEntry has a dim Text
base and a strikethrough child span; CUT inserts a dim-only marker.
`original-marker-style.txt` confirms that installed OpenTUI behavior:
source head/tail attributes 130 (DIM|STRIKETHROUGH), marker attributes 2
(DIM). Port ANSI captures show SGR 9 continuously across the marker.
Keep the Text base dim and restrict strike to source spans. U4 remains
blocked until that fix and visual recheck; the earlier U4 pass does not
cover this long-step boundary.
