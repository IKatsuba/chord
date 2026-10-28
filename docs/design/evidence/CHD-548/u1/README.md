# U1 run_team receipt screen check

Screen code: `38f59844`. Design: `6c2dac42` (§3). Captured 2026-10-28.

Launcher: `nice -n 19 bun tests/fixtures/selected_team_qa.ts normal`, one
tmux session per size, prompt `run the fixture team` sent with `send-keys -l`
and Enter separately; ctrl+o for the expanded receipt. Each PNG is the whole
window rendered from `capture-pane -p -e`.

- `u1-collapsed-120x40.png`, `u1-collapsed-80x24.png`: a new receipt with no
  recorded read ends at the role lines and `ctrl+o for saved definition and
  changes`; no `Read` line, no budget `Warning:` lines.
- `u1-expanded-120x40.png`: ctrl+o adds the run and saved-definition lines;
  still no `Read` line.

The Resources block above the receipt is the pre-U2 rendering; it is not part
of this unit. A receipt recorded with a read is covered by U1's unit tests;
the receipt-only launcher could not start against the uncommitted U2 tree.

Result: visual pass.
