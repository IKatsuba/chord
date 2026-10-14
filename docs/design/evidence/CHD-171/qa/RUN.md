# CHD-171 QA

Checked main `4f19edf`, including the reviewer-approved CHD-171 changes.
Appearance remains the designer's approved decision.

## What ran

- `deno task check`, in the foreground, with process-list access for the
  fake-process cleanup assertions.
- `deno task compile`, producing the local macOS arm64 binary.
- Source `deno task chord:fake` in an isolated tmux server, neutral scratch
  directory and separate `XDG_STATE_HOME` and `XDG_CONFIG_HOME`.
- Keyboard sequence: `task`, allow its Edit, wait for its report; `agents`,
  wait for parser messages; `task`, leave its Edit waiting; ctrl+c twice.
- Parent `--continue` at 120x40, folded and ctrl+o, Home and End, then resize
  to 80x24. `/resume`, select the named parser, inspect both sizes, quit.
- Remove only the second task's record from the isolated state directory;
  parent `--resume <id>`, folded and ctrl+o at both sizes. Restore that record;
  start a fresh source session and reopen the parent through `/resume`.
- Resumed parent: `agentclose`, `error`, `slow`, Escape, quit.
- Compiled binary with the same fake command and parent `--resume <id>`,
  folded and expanded at both sizes; `task`, deny its Edit, wait for failure.
- Additional synthetic crash-style fixture: copy only the parent record into
  another isolated state directory, truncate it after the second task's
  running update, omit that update's `at`, and resume in the compiled binary.
  This deliberately omits both task records and the later graceful ending.
- Inspect owned process descendants with `ps` during resume and after quit;
  inspect tmux cursor/alternate-screen flags; type a shell command after quit;
  remove the isolated tmux server and inspect processes again.

## What was seen

- Full check passed: 1366 tests, 20 steps, zero failures, 7m59s. Compile passed
  and the resulting binary was driven in tmux as described above.
- Both tasks restore from their own records. The completed task has five tool
  uses, its work, message to main and report. The cancelled task has three
  tool uses; its unfinished Edit has no Waiting or Running result line.
- Parent Open calls and messages both ways retain their transcript positions.
  The closing note names parser and docs; no agents list is restored.
- Removing the second task record preserves its Cancelled ending, removes
  the tool count, and draws the lost-work note only with ctrl+o. The ANSI
  captures retain its dim style. The other task remains intact.
- `/resume` identifies parser, docs and task descriptions. Reopened parser's
  header names it, its messages both ways draw, and quitting prints its own
  session resume command. The quit capture joins terminal-wrapped command
  lines and replaces repository paths with `<repo>`; other captures are raw
  tmux text or ANSI.
- Closed-child actions visibly refuse the old parser. The intentional agent
  error is shown. Escape interrupts the slow turn, and the next prompt works.
  The compiled denied task shows Failed and its error in a failed report.
- The synthetic unfinished task shows Disconnected without a duration or tool
  count, and its expanded lost-work note. A pending parent tool above it still
  says Waiting: filed separately as CHD-254, outside this child-block change.
- During parent resume, its shell descendants contain one fake agent; children
  are not reopened. After quit, only the shell remains. Cursor visible is 1,
  alternate screen is 0, and `echo QA_SHELL_RESTORED` executes in the shell.
  Canonical input and echo are restored. Removing tmux removes its owned shell.
- Read-only inspection of the generated records finds no task subagent work
  in the parent and finds tool calls in each task's own record.

No real agent or model was used. No implementation or dependency was added:
the checks use existing Ink, SDK fake scenarios, record machinery and tmux.
CHD-247, CHD-252 and CHD-253 remain their existing separate tasks; foreign
processes and unrelated untracked captures were not modified.
