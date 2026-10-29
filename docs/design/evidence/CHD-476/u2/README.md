# U2 clearing a child: screen check

Screen code: `8481faad` (the clear_agent call lines from U1 `c64463e9` and
its fixes). Design: `073bf484`, `9b4c4e0b`. Captured 2026-10-29.

`bun dev chord --fake --qa d101` (`CHORD_FAKE_FORK=1` for the fork; the
fixture team `bugfix` copied into the QA directory for the lead case), one
tmux session per case, text sent with `send-keys -l` and Enter separately.
Each PNG is the whole window rendered from `capture-pane -p -e`.

- `k-child-120x40`: `/new`, `text`, `/clear`: the child's view is empty
  under its header; row, name and pick kept.
- `k-notice-120x40`: main's `← from chord` notice in the design's words.
- `k-busy-80x24`: `agentcost`, `Later.` queued to the working parser,
  `/clear`: the turn stops, `Later.` is back in the box, parser `◦ idle`.
- `k-tool-120x40`: `agentclear` on main: `Clear(parser)` /
  `Fresh session · id …` / `1 queued message from main was not
  delivered.`, then `Clear(nobody)` refused in the failed style.
- `k-fork-80x24`: `/clear` in a fork empties its view; main gets nothing.
- `k-lead-120x40`: the bugfix lead's view with `Clear(tester)`; tester
  stays its member.

Result: visual pass.
