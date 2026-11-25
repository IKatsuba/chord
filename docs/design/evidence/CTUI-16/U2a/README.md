# U2a: reusable diff views

Designer visual pass for developer commit `625f413`.
Ran `dart run example/diff_view.dart` in a designer-owned tmux session at
120x40, then resized to 80x24. NO_COLOR was unset; TERM was xterm-256color
and COLORTERM truecolor. Plain captures use capture-pane -p; ANSI captures
add -e. ctrl+o toggled capped/full and back; ctrl+q exited the app.

Pass: both sizes keep the complete 2-addition/2-removal headline. The
capped view shows ten model rows including its inter-hunk gap and reports
seven hidden lines. The full view reveals those lines and removes the
hidden message. At 80 columns the changed lines wrap under the code column
with empty continuation gutters; wrapping leaves the hidden count at
seven. The path is not repeated as a title. Keys remain visible, and the
full narrow view fits without clipping its final source row or key help.
ANSI captures retain full-row added/removed backgrounds and syntax colors.

Compared row furniture with the original edit and rewrite captures under
`../original/`: shared number gutter, sign, continuation alignment and
inter-hunk gap agree after accounting for the port's outer result gutter.
This framework fixture intentionally demonstrates a capped consumer;
ordinary port tool diffs remain uncapped, as the original does. No new
visual findings. This is a visual pass, not a code review or suite run.
The owned tmux session exited after ctrl+q.
