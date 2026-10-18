# CHD-2 B1 captures: agent items

Taken on 495d64b2 with `bun dev chord --fake`.

| File | What it shows |
| --- | --- |
| `view-done-120x40.txt`, `.ansi` | `claudebackground`, Esc, then the view: `Run the test suite  agent  ✓ done in 4s` (success) once it ends past Esc, `Find the cancel path  agent  ■ stopped after 0s` (dim); a second earlier the first read `running 1s` |
| `standing-asking-80x24.txt` | `claudesubagents` while the explorer asks: `● 1 agent asking · ✗ 1 agent failed · ? 1 agent untracked · ■ 1 agent stopped`, wrapped between groups |
| `standing-80x24.txt` | the same after `1`: `✗ 1 agent failed · ? 1 agent untracked · ✓ 1 agent done · ■ 1 agent stopped` |
| `view-subagents-80x24.txt` | its view: done, failed (name wrapped in its column), stopped, untracked |

Not seen on screen: `● permission` on a row (the permission box holds the
keys while it is open, so the view cannot be opened then), `● waiting` (no
scenario), `■ stopping` (B3's `x`). The earlier prompt's ended items were
cleared by the next prompt, as CHD-424 says.
