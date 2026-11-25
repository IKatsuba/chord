# CTUI-174 evidence

Captured with tmux, the original with `bun dev chord --fake` in `../chord`
(v0.71.0), the port with `dart run tool/dev.dart chord --fake`, each with its
own empty `XDG_STATE_HOME`; the header's directory line reads `<dir>`.
Every case: `askclaude` sent, Down Down to the Note, then the note
`alpha bravo … victor whiskey` typed, wrapping to three rows at 80x24.

- `note-{original,port}-{80x24,120x40}.txt` (port at 084fb800): the whole
  screen with the note typed; then cmd+← and `[`; cmd+→ and
  ` xray yankee zulu`; then 40 backspaces sent at once. Identical in both
  apps at both sizes.
- `shrink-{original,port}-80x24.txt` (port at 084fb800): ten slow
  backspaces (three rows, the third empty under the cursor), an eleventh
  (two rows, the hint moves up), thirteen more at once, `Q`, then ↑ to the
  options with the Note's text kept. Identical.
- `*-8be6c583-*.txt`: the first fix, where the Note drew three rows but
  lost its keys once it shrank back to two (the thirteen backspaces and
  `Q` did nothing).
