# CTUI-107 evidence: /theme and /mcp take the transcript's rows

Commits 7cc5973b and its fix 8c9b38b0. The original and the port side by
side in tmux on the fake, isolated empty XDG_STATE_HOME each:

    (cd ../chord && bun dev chord --fake --qa room107)
    dart run example/chord/tool/dev.dart chord --fake --qa room107

Prompt `agents` (three children listed under the prompt), then `/theme`
(and, after Esc, `/mcp`), captured at 120x40 and 80x24, then the window
resized to 14 rows (`*-shrunk14`).

- At full size both pickers are identical to the original.
- Shrunk to 14 rows, /theme drops its list and keeps title, subtitle and
  `Esc to go back to Auto`; /mcp keeps its title, subtitle and
  `Esc to close`. The header stays out of the way, as the original.
- `port-before-fix-*-theme-shrunk14.txt` (7cc5973b): the tight /theme frame
  shrink-wrapped to 53 cells; `port-fix-*` (8c9b38b0) spans the full width,
  identical to `original-*-theme-shrunk14.txt`.

The qa directory is relabelled `<project>`; idle timers differ by nature.

Fix ad4d3269 (Esc after a resize takes the list): `esc-*`. /theme opened
at 120x40, the window resized to 80x14 (the list drops), Esc, then back to
80x24. The original on the fake (`--qa esc107`, no children); the port on
`tool/children.dart --many --tall --tasks` (scripted children, no agent).
In both, Esc closes the tight picker and it stays closed at 80x24.
