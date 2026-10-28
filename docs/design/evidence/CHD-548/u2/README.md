# U2 Resources block screen check

Screen code: `d68cab61`. Design: `6c2dac42` (§1, §2). Captured 2026-10-28.

Launcher: `nice -n 19 bun tests/fixtures/resource_qa.ts <case>` (fake agent,
fixture limits), one tmux session per case and size, prompt `resources` sent
with `send-keys -l` and Enter separately. Each PNG is the whole window
rendered from `capture-pane -p -e`.

- `u2-normal-*`: one window line per provider, agent first.
- `u2-partial-*`: a known and an unknown window per provider
  (`usage unknown · reset unknown`).
- `u2-unavailable-*`: `<agent>: unavailable · <reason>` per provider, ordinary
  body text, done marker.
- `u2-timeout-running-80x24.png`: the call while it waits (existing
  `Waiting…` body and turn progress).
- `u2-timeout-80x24.png`: both providers `Timed out after 10 s.` after the
  real 10 s.

Not reached on screen, no launcher case: one provider read beside one not
read, an empty answer (`No providers read.`), a line long enough to wrap at
80 columns, and an older-format answer in a resumed session
(`Recorded in an older format; not shown.`); the unit tests cover them.

Result: visual pass.
