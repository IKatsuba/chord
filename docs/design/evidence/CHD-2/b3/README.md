# CHD-2 B3 captures: `x`

Taken on bf6bd953 with `bun dev chord --fake`.

| File | What it shows |
| --- | --- |
| `stopped-120x40.txt` | `claudebackground`, ↓, enter, `x` on "Run the test suite": `■ stopped after 0s`, the other row running on |
| `stopped-later-120x40.txt` | a few seconds on: the other row `✓ done in 2s` |
| `transcript-120x40.txt` | the view closed: the tester's block ends `Cancelled`, no `Interrupted by user`, the turn ends on its own; `✓ 1 agent done · ■ 1 agent stopped` |
| `nostop-80x24.txt` | `claudenostop`, `x`: `this agent offers no stop` (dim) in place of the keys, the row still running |

Not seen on screen: `■ stopping` (the fake answers the stop within a frame)
and `could not stop:` (the fake never refuses); both are in the unit's
tests.
