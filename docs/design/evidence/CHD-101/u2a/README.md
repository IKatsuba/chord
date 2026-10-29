# U2a /fork screen check

Screen code: `3db649c8`. Design: `8990bb1d`, `1173d04d`, `e84d1b4f`,
`077cd018`. Captured 2026-10-28.

`CHORD_FAKE_FORK=1 bun dev chord --fake --qa d101` (no `CHORD_FAKE_FORK`
for the no-fork case, `CHORD_FAKE_REFUSE_FORK=1` for the failed fork), one
tmux session per size, text sent with `send-keys -l` and Enter separately.
Each PNG is the whole window rendered from `capture-pane -p -e`.

- `f-fork-*`: after `text` and `/fork`, the fork is picked: header
  `fork · fake · … · forked from main 3s ago`, the box titled `fork`, its
  row `fork · fake …` under main. Its view is empty: the copied transcript
  and divider are U2b.
- `f-main-80x24`: main keeps `› /fork ⎿ Forked into fork`.
- `f-named-120x40`: `/fork parser` from main after `/new`: rows main, its
  child `fake`, then the forks `fork` and `parser`.
- `f-clearrefused-120x40`: `/clear` on a fork:
  `A fork cannot be cleared yet · close it with x and /fork again`.
- `f-busy-80x24`: `/fork` while main works:
  `main is working · /fork once its turn ends`.
- `f-nofork-80x24`: `This agent does not fork sessions`.
- `f-failed-120x40`: `Could not fork: <the agent's reason>`.

Also checked as text: `/fork` with an ordinary child picked refuses
`/fork forks main or a fork`; main's `/clear` closes its child and leaves
both forks; `x` on a fork's row closes it.

Result: visual pass.
