# CHD-2 B2 captures: the view and the summary line

Taken on b2db8bdc with `bun dev chord --fake`.

| File | What it shows |
| --- | --- |
| `view-waiting-120x40.txt`, `.ansi` | `claudewaiting`: `● 1 agent asking` on the summary line; in the view `● waiting 1s` in the warning colour, then `✓ done in 2s` |
| `view-80x24.txt` | `steps`, then `claudesubagents` answered `1`: four agent rows, a name wrapped two cells in |
| `enter-reviewer-80x24.txt` | `j`, `enter` on the reviewer's row: the transcript scrolled to its own `├─` row, as high as scrolling allows (one line below) |

The drawing matches CHD-2.md's mocks. The mocks' mix with a monitor, a
task and an owner other than `main` is not in one scenario; CHD-424's
captures cover those kinds.
