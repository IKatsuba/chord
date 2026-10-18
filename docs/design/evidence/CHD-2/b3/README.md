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

## Second look, on 62a3b085 (after review's fixes)

| File | What it shows |
| --- | --- |
| `asking-x-120x40.txt`, `asking-x-80x24.txt` | `claudewaiting`, `x` on `● waiting 0s`: `■ stopped after 0s` |
| `stopped-80x24.txt` | `claudebackground`, `x`: `■ stopped after 0s` beside the other row running |
| `nostop-120x40.txt` | `claudenostop`, `x`: `this agent offers no stop`, which `j` on the lone row leaves |

- **`■ stopping` cannot be reached on the fake.** Its stop reports the
  subagent's `idle` at once (`claudeChildren` in
  `tests/fixtures/fake_agent/scenarios/subagents.ts`); thirty captures
  straight after `x`, on a running and on an asking row, all show
  `■ stopped`. Seeing it needs a fake stop that waits before its `idle`.
- **`could not stop:` cannot be reached on the fake.** `session/cancel` is
  a notification: no agent answers it, so the fake cannot refuse one; only
  a send that fails, such as a connection already gone, can.
