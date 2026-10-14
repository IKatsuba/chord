# CHD-254 captures

Source `deno task chord:fake` in tmux, with a scratch working directory and
its own `XDG_STATE_HOME` and `XDG_CONFIG_HOME`: `task`, allow its Edit;
`agents`; `task`, leave its Edit waiting; ctrl+c twice. Only the parent's
record was copied into a second state directory, cut right after the second
task's `subagent_update` with state `running`, before its served
`spawn_task` answer, and with that line's `at` removed; no task record was
copied. The parent was resumed with `--resume <id>` at 120x40, captured
folded and with ctrl+o, then resized to 80x24 and captured with ctrl+o and
folded again.

`Tool(mcp__chord__spawn_task)` draws its headline with no `Waiting…` line
in all four. `Waiting on parser.` is the fake agent's reply, not a call's
status. No real agent was used.
