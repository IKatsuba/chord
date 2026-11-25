# CTUI-106 evidence: children fixture flags past the child cap

Commit 22aac990. Captured in tmux at 120x40 and 80x24 with an isolated,
empty XDG_STATE_HOME (a scratch directory, not named here), about two
seconds after start:

    dart run example/chord/tool/children.dart <flags>

- `*-many.txt`: --many alone, main and eight children (`… +6 more` at
  80x24), as before.
- `*-many-tall-tasks.txt`: the combination that crashed before the fix now
  opens; the tall child is listed and the total stays main plus eight.
- `*-many-tall-tasks-failed-unseen.txt`: with --failed and --unseen, lexer
  shows `✗ failed to start`, parser `✓ new reply`, docs `← new message`,
  and the status line counts the failure; still main plus eight.

`.ansi` files are the same panes with colour (`capture-pane -e`).
