# CHD-306 QA at d83a213

Fresh keyboard-only checks in tmux 3.6a, with an isolated server, scratch
working/config/state directories and the repository fake ACP agent. Source
and the host darwin-arm64 binary were exercised at 120×40 and 80×24.
The designer-approved appearance and the owner's choices remain accepted.

## What was run

- `bun run compile`: host binary built and started in tmux.
- Source and binary: bind ctrl+k to `chat:submit` in a keybindings file,
  send `say hello world, word`, ctrl+r `wor`, add `x`, Esc; search again,
  Enter, type `X`. Both matches are inverse; no-match keeps the last result;
  Esc cancels; Enter restores an editable prompt with no inverse left over.
- Type `a`, `b`, `c` as separate keys, Left, ctrl+z, ctrl+y: `ab`, then
  `abc`, as the owner accepted. Captures retain the opposite sizes for
  source and binary; both were checked at both sizes.
- Paste fourteen lines, move to the first line: `› row 1` and `↓` at the
  bottom. At the end and in the middle, `↑` and `↓` follow the visible rows.
  Send, ctrl+r `row 13`, resize between 120×40 and 80×24: the search overlay
  follows the textarea and keeps `row 13` inverse.
- Narrow source search across a wrap: `beyond` splits into inverse `beyo`
  and `nd`, on the same rows as the editable textarea. Enter and type `X`
  edits at the end. Source and binary search after `say a` plus a tab:
  exactly `auth` is inverse, with both tab spaces plain.
- Vim: `keep this line`, Esc, `i X Esc`, resize, `i Y Esc`. Draft and cursor
  agree: `keep this linXe`, then `keep this linYXe`. Source and binary both
  use a white block in a dark pane and a black block in a light pane
  (`window-style fg=#112233,bg=#ddeeff`). The normal cursor is at 17,37
  (120×40) or 17,21 (80×24); insert is one cell later.
- Source and binary: `error` visibly reports `The fake agent failed on
  purpose.`; `slow`, Esc visibly reports `Interrupted by user`. These were
  checked at both sizes.
- Two scratch rendered probes through `withWindow`, at 120×40 and 80×24,
  use the pixelClipboard fixture data: `cut`, ctrl+v, ctrl+w, ctrl+z,
  ctrl+y, ctrl+z, Enter. Cut leaves `cut `; undo restores `[Image #1]`;
  redo removes it; the last undo restores its image and Enter reports
  `Received an image: image/png, 70 bytes`. Both probes passed (4 assertions)
  and the helper verified their fake-agent processes stopped.

The `.txt` files are plain captures; `.ansi` files keep attributes. Image
captures come from OpenTUI's test renderer, not the system clipboard. The
existing main/branch evidence one directory above supplies the main
comparison; fresh search, gutter and vim cells agree with it, subject to
accepted key-by-key undo and the terminal's native vim cursor.

## Exit and cleanup

| Run | Exit | Result |
| --- | --- | --- |
| Source vim, light, 80×24 | Clear draft, ctrl+c twice | 0 |
| Binary vim, dark, 120×40 | Clear draft, ctrl+c twice | 0 |
| Source normal, 80×24 | ctrl+d | 0 |
| Binary normal, 120×40 | `/exit` | 0 |
| Source vim, dark, 80×24 | SIGTERM | 143 |
| Binary vim, light, 120×40 | SIGHUP | 129 |

Every run returned to the shell with identical `stty -g`, a visible cursor,
`alternate=0`, cursor shape `default` and colour `none`. Raw terminal output
contained `CSI ?1049l`, `CSI ?25h`, mouse-disable sequences for 1000, 1002,
1003 and 1006, and OSC 112 to reset cursor colour. `ps` showed none of the
recorded owned chord/agent PIDs remaining and no agent using this QA's
scratch command. All QA tmux sessions were removed. The three pre-existing
`/tmp/chord-flip` agents were left untouched.

## Validation

Foreground `bun run check` with process access passed: 1465 pass, 12 todo,
0 fail, 17761 assertions, 458.67 seconds. Static checks and all 51 lint
tests passed. After adding the evidence, `bun run check:static` passed
again, the staged-tree privacy test passed (7 tests), and
`git diff --cached --check` passed. The remaining todos belong to deferred
migration work, including the accepted CHD-319 Unicode limitation.

## Scope

No implementation changed, no new library or workaround was introduced,
and no real agent/model was used. The reviewed trials remain the evidence
for library fit: LineNumberRenderable, textarea highlights/default cursor,
native deleteRange, Text char wrap and OpenTUI 0.6.0. CHD-319's accepted
Unicode run offset, CHD-320's viewport limitation and the separate
CHD-317/321/322 findings remain outside this pass. A real palette-answering
terminal, kitty protocol and other platform binaries were not checked.
