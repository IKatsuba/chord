# CTUI-7 screen look

Handed-over units: TextArea widget e2c3387 and example caabbfb, with the
lastLayout design addition in 6e5f0a6. Ran `dart run example/text_area.dart`
in designer-owned tmux at 120x40 and 80x24. Captures are actual panes; ANSI
companions preserve cursor and dim styling. Text entered with send-keys -l;
Enter and modified keys sent separately. The owned session was killed and
its absence verified after capture.

Appearance passes: title, frame geometry, editable padding, placeholder,
dim one-based status line and hint read clearly at both sizes. KeyHelp
clips to one row as disclosed; Ctrl+Q remains visible in the dedicated hint.
Wrapped text retains wide graphemes and all text after resize. Enter echoes
and clears. Six pasted logical lines reveal rows 3–6; three Up presses retain
that window and a fourth reveals rows 2–5. Alt+Enter inserts a line; a cursor
on the wide grapheme uses inverse styling for the complete grapheme.

Blocking finding: Ctrl+J submits rather than inserting a newline. After
literal `alpha`, sending C-j echoes alpha above and clears the area; KeyHelp
still lists ctrl+j Insert newline. See 120x40-ctrl-j-submits.txt. Sent to
developer and lead; reviewer handoff held pending correction or owner decision.

Evidence map:

- 120x40-empty: initial empty focused state.
- 120x40-wrapped and 80x24-wrapped-resized: same long text after resize.
- 80x24-submitted and 120x40-submitted: Enter echo and cleared area.
- 80x24-scrolled and 120x40-scrolled: six logical lines, cursor at end.
- 80x24-up-three and 80x24-up-four: vertical reveal boundary.
- 120x40-alt-enter-wide-cursor and 80x24-alt-enter-wide-cursor: newline and wide cursor.

This example exposes no unfocus action, so runtime unfocused styling was
not observed. Shift+Enter and Ctrl+Enter protocol reporting were not measured.
Widget tests in the developer handoff cover those bindings. This is a
framework example; no port screen or original-screen equivalence is claimed.

## Ctrl+J recheck

Fix handed over as c88eec1: repeated the running example at 120x40 and
80x24. Ctrl+J after alpha creates logical line 2; after beta at 80x24 it
creates logical line 3. CR Enter then echoes both lines and clears the area.
See 120x40-ctrl-j-fixed.txt, 80x24-ctrl-j-fixed.txt and both
enter-after-fix.txt captures. The finding above is resolved on the normal
raw-terminal path; retained failing capture records the original symptom.
The owned recheck tmux session was killed and absence verified.

Developer also handed over c8b6e65, preserving Enter when raw stty setup
fails and the fallback leaves ICRNL active. That fallback is not reached by
this tmux run and is not visually verified; its code/tests go to reviewer.
No remaining visual blocker on the measured normal terminal path.
