# CTUI-164 evidence

Captured with tmux at 120x40 (and 80x24 for the selection), the original
with `bun dev chord --fake` in `../chord` (v0.71.0, @opentui/core 0.8.4), the
port with `dart run tool/dev.dart chord --fake` on main b83c4410, each with
its own empty `XDG_STATE_HOME`. Keys were sent with `tmux send-keys -l` as
kitty (`CSI code;mods u`) or xterm (`CSI 1;mods D`) sequences.

- `original-keys-120x40.txt`, `port-keys-120x40.txt`: the draft
  `alpha beta gamma` / `delta epsilon zeta`, the cursor moved five graphemes
  left, the key, then `|` typed; prompt rows only. ctrl+c cleared the draft
  between keys.
- `original-select-all-edits.txt`: the same after cmd+a.
- `original-select-all-*.txt`: cmd+a on a two-line draft (120x40) and on a
  wrapped one (80x24); `*-colour.txt` are their prompt rows with escapes
  written as `ESC`, the selection on `48;5;66`. The header's directory line
  is relabelled `../chord`.
- `line-edges-120x40.txt`: ctrl+a, ctrl+e, ctrl+u, ctrl+k and cmd+←/→ at a
  logical line's start or end, both apps.
- `opentui-edit-buffer.txt`: OpenTUI's own `EditBuffer`, run headless under
  Bun from `../chord`'s installed package (read only), for `deleteLine` and
  the word boundaries: the text with `|` at the cursor after each call.

The 120x40 selection capture was typed with a tab between `delta` and
`epsilon`; the window took the tab, so the draft reads `deltaepsilon`.

- `u2-select-all-*.txt`: U2 (62dcb78a), `dart run example/text_area.dart`
  in tmux, cmd+a on the same two-line draft (120x40) and wrapped draft
  (80x24) as the original's captures; `*-colour.txt` are the selected rows,
  `48;5;66` as in the original.

- `hold-keys-120x40.txt`, `hold-line-edges-120x40.txt`: the port at
  356d334e (the hold). The keys file is identical to `port-keys-120x40.txt`
  (main); the line edges now match the original.

- `plan-note-120x40.txt`: the plan box Note in both apps (fake cursorplan).
- `panel-port-*.txt`: the port's shortcuts panel today (identical to the
  original's at 80x24); `panel-mock-*.txt`: with section 8's two lines.

- `u3-*`: U3 (b4bae2c5). `u3-keys-120x40.txt` differs from
  `original-keys-120x40.txt` only at cmd+↓ (history in the original);
  `u3-select-all-edits.txt` matches `original-select-all-edits.txt`;
  `u3-panel-*` are the panel with its two new lines; `u3-select-all-120x40*`
  the draft selected in `48;5;66`.
