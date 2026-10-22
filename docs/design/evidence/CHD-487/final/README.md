# CHD-487: the final screens

The whole chord window on the fake agent, from the built code (chd-487 at
330e3888), dark theme, each as a `.ansi` file with its colours (`cat` it in
a terminal, or `less -R`) and a `.txt` beside it, at 120×40 and 80×24. Each
is the background view's detail, opened with `↓` to the summary line,
`enter`, `enter`.

| File | What it shows |
| --- | --- |
| `running-<size>` | A running subagent's detail (`claudebackground`): the description and state pinned, `› ` and the task it was given, then its work as `ctrl+o` draws it, followed live. |
| `ended-<size>` | The same subagent ended while its detail was open (Q136): ` · ended`, `✓ done in 4s`, no `x to stop`; at 80×24 its work is paged, opened at its end. |
| `nostop-<size>` | A codex-form subagent, which cannot be stopped (`subagentstatesstay`), after `x`: `this agent offers no stop` in the hint's place. Its name is its whole task, so no `› ` line repeats it. |
| `task-<size>` | chord's own task (`tasklong`): `working 2s · 0 tool uses · task · fake · main`, its task, its work. |

`<size>` is `120x40` or `80x24`. The fake's task has no model, so its kind
reads `task · fake`.
