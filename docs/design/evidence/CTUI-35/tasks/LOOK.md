# Designer's look at unit 26, commit 67ebd6e5

`port-*-window-tests.txt`: `test/ui/app/tasks_window_test.dart`'s screens
at their end (fake-clock ages shown as `(…)`), beside the original's
captures in this folder (NOTE.md).

Equal to the original: the block headline `Agent(Fix the tokenizer) ·
fake · fake-small`; the box title `Agent(Fix the tokenizer) · fake asks ·
between turns` with `ctrl+x a to answer`; the form's `· fake asks for
input · between turns`; `/cost`'s task rows indented under main, `task
agent, running: counted when it ends` wrapping at the same place, `N
running` in the Total; `1 agent still running` in the status line.

Differences, all decided or explained: no `background` row under the
list (the owner's, until CTUI-36); the status notice reads `● permission
asked between turns` where the port's test has no model on the right, and
the original's short `● permission` where it has one, as
`betweenNotice`'s `short`; the block's earlier work lines differ by
fixture.
