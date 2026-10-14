# CHD-260 independent QA

Tested main at `6709a8e`, using only the scripted ACP agent. No live agent
was run. Designer approval remains accepted; these captures prove behavior.

## What ran

- `deno task compile`, then the produced macOS arm64 binary.
- Source and compiled full-screen runs in an isolated tmux server, with
  scratch working directories, config and state. `bugfix.md` came from
  `tests/fixtures/teams/fake/`. All TUI actions used keys.
- `team`, lead and member picking, ctrl+o expansion/folding, permission
  Allow (source) and Deny (compiled), direct member messages, `team2`,
  cross-run lead messages, member close, lead exit, team close and quit.
- A compiled member's `error` turn and `slow` turn interrupted with Esc
  after resizing to 80x24. Both runs resized between 120x40 and 80x24.
- Terminal mode comparisons and process inventories before and after quit.
- Required `deno task check`, including the concurrent member-open test.

## What was seen

Team and Open bodies wrap; the first job folds at three displayed lines at
80 columns and ctrl+o reveals the rest. Instructions are one dim line until
expanded. Lead/member views retain the file's model and mode. Member
messages arrive directly in the recipient's transcript. Reports start
main's turn. The second run is `bugfix 2`; its permission notice names the
run while two testers are open. Allow and Deny reach the fake agent.

Closing coder tells its lead. A fake lead crash removes its remaining
member and tells main the last stderr words. Closing a lead removes its
members and tells main; closing the first compiled run leaves the second
run open. Agent errors appear in the transcript. Esc ends the slow turn.

Both quit paths leave the alternate screen, restore the cursor, and
restore exactly the prior `stty` state. Final `ps` contains none of the
sampled owned process IDs (see `cleanup.txt`). The isolated tmux server
was stopped. Other runs' processes were neither changed nor stopped.

The flat list, role-specific `/mcp` prose, team close arming wording,
`/team` forms, and team resume naming remain the task's deferred scope.
The fake model/runtime names and flat list are the accepted differences
from the design mocks. No production code or dependency was changed by QA;
wrapping exercises the existing wrap-ansi implementation in both builds.

## Validation result

`deno task check` passed on the first run: types, lint, formatting, 1430
 tests and 20 steps, zero failures (8m31s). The concurrent-open regression
and the previously intermittent shell cleanup test both passed. The
staged captures passed all seven privacy tests. Final process inspection
also found no new orphan fake agent since source startup.
