# Task blocks: unit 26 (interface I8)

The original, `../chord`, `bun dev chord --fake --qa <name>` in a 120x40
and an 80x24 tmux window, captured with `tmux capture-pane -e`. The QA
directory in the header is relabelled `<project>`.

- `orig-80x24-task-asking.*`: prompt `task`, the task's edit waiting on
  its permission while its parent's turn runs.
- `orig-*-task-between.*`: the same once the parent's turn has ended:
  `Agent(Fix the tokenizer) · fake asks · between turns`, `ctrl+x a to
  answer`, the status notice `● permission · ctrl+x a to answer`.
- `orig-120x40-task-done.*`: ctrl+x a, `1`: the ended block, `Done (5 tool
  uses · 2.0k tokens · $0.0125 · 19s)`, and the task's `←` messages.
- `orig-120x40-task-cost.*`: `/cost`: the task under main, two in, `task
  agent, ended`.
- `orig-*-tasktwo.*`: prompt `tasktwo`: `Running 2 agents…`, each row
  `Agent(<name>) · fake · 0 tool uses`, the tree's `│` in colour 244, and
  `2 agents still running` on the status line. The original's `background
  2 tasks running` row under it is CTUI-36's; the port draws none.
- `orig-*-tasktwo-cost.*`: `/cost` with the two at work: `task agent,
  running: counted when it ends`, Total `2 running`; at 80 columns the
  note wraps in its cell.
- `orig-120x40-tasktwo-esc.*`: prompt `slow`, Esc: `■ Watch the deploy ·
  task · stopped with esc after 16s` for each.
- `orig-80x24-taskmaxeffort.*`: prompt `taskmaxeffort`: max refused, the
  block names the runtime's own, `Agent(Tune the parser) · fake ·
  fake-small · medium`.

The port's counterparts are tests, not captures:
`example/chord/test/ui/transcript/agents/tasks_test.dart` (blocks cell for
cell with their styles at 120 and 80 columns, the ended line, the refused
effort, the stop line), `test/ui/app/tasks_window_test.dart` (the status
line after the turn with no row under the list, the permission and form
headings, `/cost`), `test/ui/transcript/spend_tasks_test.dart` (the
`/cost` table lines of the captures above) and
`test/ui/status/task_notice_test.dart`.
