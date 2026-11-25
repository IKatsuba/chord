# CTUI-178 evidence

Captured with tmux, the original with `bun dev chord --fake` in `../chord`
(v0.71.0), the port with `dart run tool/dev.dart chord --fake` at 8492abda,
each with its own empty `XDG_STATE_HOME`: `cursorplan` sent, j j to the
Note. Colour lines write the escape as `ESC`.

- `note-{original,port}-{80x24,120x40}.txt`: the empty Note focused and
  away (its leading inverse cell, then a blank one); the CTUI-164 key list
  on `alpha beta gamma` (the Note cleared with ctrl+u, ← twice, the key,
  then `|`); a long note wrapping at spaces; ↑ from its last row to the
  options, j j back (the second j typed); ↓ on the Note; a word filling the
  line, the cursor's inverse cell on a row of its own, then one more
  character; a word longer than the line, broken.
  The only differences: cmd+a, cmd+z and cmd+shift+z type a, z and Z in the
  original and nothing in the port (not ported, CTUI-164 section 9 item 7);
  and the original writes a white foreground on blank cells where the port
  writes none, which draws nothing.
- `short-{original,port}-80x12.txt`: a long note, the window resized to
  80x12: the Note shows its last row and `↑ 5 lines above`. Identical, and
  identical again after ↑ to the options.
