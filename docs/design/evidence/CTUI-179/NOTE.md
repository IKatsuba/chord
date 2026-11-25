# CTUI-179 evidence

Captured with tmux, the original with `bun dev chord --fake` in `../chord`
(v0.71.0), the port with `dart run tool/dev.dart chord --fake`, each with its
own empty `XDG_STATE_HOME`. cmd+↑ and cmd+↓ were sent with `send-keys -l` as
`CSI 1;9A` and `CSI 1;9B`; the prompt box and the rows under it are kept.

- `history-{original,port}-{120x40,80x24}.txt` (port at 9cec600a): one
  prompt sent, a draft typed; cmd+↓ sets it aside, cmd+↑ brings it back, a
  second cmd+↑ shows the sent prompt, cmd+↓ the draft again. Then a
  three-line draft, the cursor on its second row: cmd+↑ and cmd+↓ do
  nothing; at 80x24 a `|` typed after shows the cursor did not move. The
  same check was made by hand at 120x40. Identical in both apps.
- `list-original-*.txt`, `list-port-*.txt` (port at 673ac46a): `/` then `@`
  typed with their list open; ↓, cmd+↓, cmd+↑, cmd+↑, cmd+↓. In the original
  cmd+↑ and cmd+↓ do nothing while a list is open (the prompt, the list's
  highlight and the hidden status hint unchanged), though the same bytes walk
  history with no list; a plain ↓ moves the highlight from /clear to
  /config. The port matches, highlight included (checked with
  `capture-pane -e`). The list rows above the box are not in these files.
- `list-port-ab75dcb4-*.txt`: the rejected fix, where cmd+↓ emptied the
  prompt and cmd+↑ showed the sent prompt while a list was open.
- `panel-{original,port}-80x24.txt`: the shortcuts panel; the port lists no
  cmd+↑/↓, as the original. Its other differences (cmd + a, cmd + z, esc to
  close completions) were settled in CTUI-164.
