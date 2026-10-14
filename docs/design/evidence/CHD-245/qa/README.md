# CHD-245 independent QA

Tested main at `d300693`, including CHD-245 implementation `4f19edf`.
The designer-approved appearance and permission state 7 were outside judgment.

Ran `deno task check`, `deno task compile`, and keyboard-only fake-agent
matrices in private tmux sessions at 120×40 and 80×24, from source and the
compiled aarch64-apple-darwin binary. Each used a neutral temporary working
directory and isolated XDG configuration and state. No live agent was used.

Prompts: `monitor`, `monitors`, `monitorexit`, `monitorflood`, `monitorchild`,
`error`, `slow`, `text`; `/clear` separated scenarios. Keys: arrows, `x`,
`?`, Esc, ctrl+o, ctrl+d and the `--resume` picker. Each session was resized
to the other size and back. Captures are unedited tmux text; `.ansi` keeps
arrow colors and dim end sentences. Narrow parent resume ends at the final
notes; `9-resumed` separately captures the child's restored event and stop.

Observed event rows followed by agent replies, two running monitors,
immediate stop/removal and focus recovery, child monitor ownership despite
both sessions having `m1`, nonzero exit/flood rows, folding/expansion,
shortcuts fitting, visible agent errors, interruption and next-prompt
recovery, and restored event/stop rows with no monitor restart. The capped
80-column list kept its focused final row visible. Its total-hidden wording
is the already-filed CHD-255 finding.

Terminal byte measurement: after one startup bell, the initial monitor turn
added one bell, its event reply added zero, and its person-stop reply added
one. The focused final monitor's natural exit returned keys to the prompt.
Permission-inside-monitor notification behavior is covered by the existing
`tests/notify_test.ts` test, rather than this terminal probe.

Quit returned every pane to its shell: alternate screen off, cursor visible,
and canonical input/echo and other stty flags restored. The shell's PENDIN
bit was cleared; no input-mode difference remained. Owned agent and monitor
processes were checked with `ps`; the private tmux server was then removed.

Library-first: exercised existing Ink Text, wrap-ansi, string-width and
cli-truncate in source and compiled rendering; no implementation or library
was added. CHD-256 already tracks the decision entry's wrapper attribution.

Validation: `deno task check` passed types, lint, formatting and 1,367 tests
(20 steps), zero failures, in 8m2s. Compilation passed. The staged capture
privacy check passed seven tests. Final `ps` showed no owned test, UI agent,
monitor or tmux process; one older wedged fixture present in the starting
inventory was left untouched.
