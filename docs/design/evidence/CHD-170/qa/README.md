# CHD-170 independent QA

Checked current `main` at `840c788`, including the live-child resume fix
`c3588ab`. The designer's approval stands; these captures prove behaviour.

## What ran

- `deno task check`, including the fake ACP session, MCP and App tests.
- `deno task compile` for `aarch64-apple-darwin`.
- `deno task chord:fake` in an isolated tmux server at 120x40 and 80x24,
  including resizing the running window in both directions.
- The compiled binary with the same fake runtime, at both sizes.
- Keyboard input only, with temporary HOME, XDG configuration/state and
  scratch working directory. No real agent or model was used.

Results: full check passed, 1287 tests (20 steps), zero failures, 7m19s.
Compile passed and the resulting binary started and completed the flows
below. All seven privacy tests passed against the staged captures. An initial
standalone privacy invocation omitted write permission; rerunning with the
repository's normal test permissions passed.

## What was observed

- Open calls add parser and docs under main, without independent child tabs.
  Two messages each way draw as incoming and outgoing agent rows.
- Down enters the list from the empty draft; picking parser changes its
  transcript and named border. A person's `/echo` goes to parser.
- Docs' permission is marked in the list and in a background parent's tab.
  `ctrl+x a` picks docs and shows its permission. The sessions picker says
  `fake · 2 agents` and names docs' permission.
- From tab 2, `/resume` marks all three live records `open in 1`. Picking
  parser selects its existing conversation in tab 1. The same four fake PIDs
  remain: 70189, 70490, 70495 and 72000. Picking the parent selects main.
- `x` on waiting docs arms, then closes it and delivers the parent's
  `The person closed docs…` message. `close_agent(parser)` answers Closed;
  a later send is refused as closed. The last child gone removes the list.
- A selected child's fake error is visible. Esc interrupts its slow turn;
  the next `/echo` succeeds. Resize preserves the selected child and input.
- Closing the compiled parent's tab arms while docs waits, then closes both
  children and reports `Closed 1 fake and its 2 agents`.
- At 80x24 four children fold to `… +2 more`. The picked child's light
  border uses RGB 10,91,196; the dark 16-colour border uses SGR 94. The ANSI
  captures preserve these values. This is rendering evidence, not a new
  design or physical-terminal contrast review.

## Cleanup

Normal Ctrl+d quits restored `alternate=0` and `cursor=1` in the source and
compiled panes. `stty -a` showed `icanon` and `echo` in the restored source
shell. Process checks found none of the owned source or compiled processes:

- First source: 70109, 70146, 70189, 70490, 70495, 72000.
- Compiled: 71126, 71196, 71577, 71579, 76357.
- Second source: 86025, 86036, 86301, 86629, 86632, 87398, 87402.

The isolated tmux server was removed after these checks. Existing unrelated
agent processes and untracked evidence were left alone.

## Scope and library first

No implementation was changed and no new helper or dependency was added.
The recorded implementation trials remain `@mishieck/ink-titled-box` 0.4.2
and `@inkjs/ui` 2 Select, rejected for the fit issues in `decisions.md`.

No new follow-up was found. CHD-233, CHD-234, CHD-235 and CHD-237 stay separate;
the sixth 16-colour hue was not reassessed. CHD-218's parent-close decision
and CHD-171's reconstruction/persistence work are outside this acceptance.
No live hand check, push, publication or PR was performed.
