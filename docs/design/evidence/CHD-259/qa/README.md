# CHD-259 independent QA

Checked main `ad39596`, preserving the designer's appearance pass.

## What ran

- `deno task check` in the original workspace. Types passed; lint failed
  with 15 errors from an unrelated nested worktree (CHD-270).
- The unchanged full check in a clean temporary clone of the same commit,
  with process and loopback access for the fake-agent tests: types, lint,
  formatting and 1406 tests (20 steps) passed, zero failed, in 8m3s.
- `deno task compile` in the original workspace.
- Source and compiled TUI in an isolated tmux server, driven only by keys,
  at 120x40 and 80x24, with resize between them. Both used the repository's
  fake ACP agent, `CHORD_FAKE_STEP_MS=20`, a scratch working directory and
  isolated XDG config/state directories.
- `agenttask`, permission Allow, `agentexit`, `agentfail`, a prompt to the
  surviving failed child, `x` twice on a child with a task waiting for
  permission, `slow` followed by Esc, another prompt, and ctrl+d to quit.
- Session-record inspection for notification counts and cancellation;
  process snapshots before, during and after the TUI runs; tmux terminal
  flags after compiled quit.

## What was observed

- Tasks were nested in the child's transcript. The permission identified
  the task; its intermediate message and final report reached the child.
  Main's transcript did not receive those task reports.
- Each run recorded exactly one child-exit notification and one failed-turn
  notification from chord. The exit included the stderr tail and reopening
  advice; both notifications started a turn of main's.
- The failed child accepted another prompt. A streaming turn interrupted
  with Esc showed `Interrupted by user`, then accepted another prompt.
- The compiled close armed on the first `x`, then removed the child and its
  permission on the second. The child's task recorded `cancelled`; main
  received the person-close notification, with no task report afterward.
- Narrow permissions remained answerable and messages wrapped within the
  terminal. Resizing preserved the conversation and keyboard routing.
- Quit returned to the shell. The compiled terminal reported
  `alternate=0 cursor=1 command=zsh`. Source-owned processes and the
  compiled TUI's agents were absent from the post-quit process snapshot.
  The isolated tmux server was removed. One wedged fake left by the initial
  sandbox-limited check was identified and killed; unrelated processes
  were left alone.

Existing list/status wording remains tracked by CHD-269 and CHD-262.
An existing wait-tracking defect was also observed: once the spawning turn
ends, an unanswered task permission loses its attention mark, though its
box remains answerable when picked manually. The unchanged `watchWaits`
result handler clears its asking set. Filed separately as CHD-271.
CHD-270 still prevents the original workspace's unqualified full check
from passing; a clean-clone pass does not repair that gate.

No live agent was used. No implementation or dependency changed. The
existing Conversation, TaskAgent, Ink and MCP SDK were exercised; no new
component, parser, renderer or protocol helper required a library trial.
