# U5: initial tools look

Developer handover `9ce1556`. Ran `dart run tool/transcript_tools.dart`
from the port package in owned tmux at 120x40, then 80x24. NO_COLOR unset;
TERM=xterm-256color, COLORTERM=truecolor. Captures use capture-pane -p,
with -e for `.ansi.txt`. ctrl+o toggled details; Home/End exposed the top
and tail of the narrow fixture. ctrl+q exited; owned session removed.

The handed-over fixture reads consistently at both sizes: Read preview and
count, terminal last three lines with hidden count and separate exit note,
full edit rows and counts, Guardian reviewing line, running tool and failed
tool. Expansion reveals all Read/terminal rows and removes hidden hints.
`compare-*` puts original calls/shell/edit beside the compound fixture;
content differs, while outer original window furniture is outside U5.

This records an initial look only. Full visual handoff waits for U4a's
middle overflow on Guardian/Folded, and the requested long tool headline
and diff-path fixture checks. Those headlines must keep wrapping. No
additional visual finding arose from the short fixture. No live agent,
permission scenario or suite run was performed here.
