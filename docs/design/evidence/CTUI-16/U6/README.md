# U6: transcript list and below-rule

Designer visual pass for developer commit `4575a12`.
Ran `dart run tool/transcript_list.dart` from the port package in owned
tmux at 120x40, resized to 80x24 and back. NO_COLOR unset with
TERM=xterm-256color and COLORTERM=truecolor. Captures use -p, plus -e for
`.ansi.txt`. The fixture appends output every 300 ms; counts vary by frame.

Pass: initial view follows the latest output with no below-rule. PageUp
holds the first visible entry while news grows: held and held-later wide
captures both start at output 115, while lines below grow from 86 to 180.
Resize to 80x24 retains that first entry. Shift+Up moves by one row. Home
reaches the first thought/entry; ctrl+o toggles thought height without
losing the top. End restores following and removes the rule. Returning
to wide width keeps the beginning stable before End resumes following.

The rule overlays the last transcript row immediately above the footer;
its dim rail, arrow, bold accented new-output words, count and End hint
agree with original/long-paused-streaming captures. Original and fixture
content and footer heights differ; compare rule furniture and behavior,
not exact counts across the two runs. Existing CTUI-1 decision allows Home
to reach the first entry immediately. The fixture has no working-status
line or active permission, which belong to separate screen tasks.

No new visual findings. ctrl+q stopped the fixture; owned tmux session
exited and was removed. This is a visual check, not a suite run or a
performance measurement.
