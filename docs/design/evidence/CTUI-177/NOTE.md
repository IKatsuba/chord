# CTUI-177 evidence: a press held at the bottom

`orig-*` is `../chord` (v0.71.0, `bun dev chord --fake`), `port-*` is the
port at 646a0c40 (`dart run tool/dev.dart chord --fake`), both in tmux at the
size in the name, plain text from `capture-pane -p`. The capture directory in
the header is relabelled `<qa directory>`.

- `fitting`: prompt `hello`, a reply that fits the view.
- `tall`: prompt `long`, 200 lines, taller than the view, waited to its end.
- `held`: an SGR left press (`ESC [<0;10;R M`) held at the transcript's last
  row, R = 36 at 120x40 and 20 at 80x24, the row above the prompt's border.
- `released`: the matching release (`ESC [<0;10;R m`).

In all eight states, port and original are the same text but for the version
line, and neither draws a "lines below" rule, held or released (CHD-397).
`port-80x24-tall-wheel-up.txt` checks the rule is still drawn when the view is
scrolled back: one wheel step up shows "── ↓ 2 lines below · end to jump to
the bottom".
