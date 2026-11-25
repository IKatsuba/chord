# CTUI-183 captures

The plan box's Note paging, commit 9f6186d7, captured in tmux from
`dart run tool/dev.dart chord --fake`: prompt `steps`, then `cursorplan`,
↓ ↓ to the Note, and a long note pasted. The header's directory is relabelled
`chorded-tui`.

Compared with ../chord's source (src/ui/dialogs/PlanBox.tsx and
permission.ts: requestView, requestStep, requestRule, requestCount):

- `120x40-tail.txt`: the Note at its tail, `── ↑ 17 lines above · pageup to
  scroll`, the half-window room as the original's flexBasis gives it.
- `120x40-pageup.txt`, `120x40-top.txt`: PgUp within `room - 2` of the top
  goes to the top, the rule turning to `↓ … below · pagedown to scroll`.
- `120x40-pagedown.txt`: PgDn back to the tail.
- `120x40-typed.txt`: paged up, then typing: the view returns to the tail
  and the cursor shows after the typed text.
- `120x40-off-note*.txt`: ❯ on a choice: the rule loses its key, and PgUp
  scrolls the transcript, the Note keeping its view.
- `80x24-tail.txt`, `80x24-pageup.txt`: a room of six, PgUp moving
  `room - 2` = 4 lines.
- `80x16-one-row*.txt`: a room of one: the counted row,
  `↑ 51 above · ↓ 39 below`, stepping one line per page key. The raw top
  kept from the earlier paging survives the resize, as the original's
  `top` state does.
