# CHD-151 QA evidence

Checked implementation `12552e0` on main. These are fresh keyboard-only tmux
captures, with source and compiled chord using the repository's fake ACP agent.
The session directory, configuration and records were isolated under `/tmp`.
The existing designer approval remains the authority for appearance.

## Ran

- `deno task check` on the current tree, with process-inspection access for
  the fake-agent cleanup tests.
- `deno task compile`, then the produced macOS arm64 binary in tmux.
- Source `subagent` at 120x40, resized to 80x24 during permission and background
  work, then back to 120x40 during expanded work. Number key 1 allowed the write.
- A second source turn at both widths; Esc after the second child failed.
  Sent `text` afterwards to prove the prompt still worked.
- Compiled `subagent` at 80x24; number key 3 denied the write. Ctrl+o, Home, End,
  Page Up and Page Down opened and scrolled its work. Then `subagentupdate` and
  `error` exercised ACP-native state and an agent error answer.
- An independent Deno reducer-to-view probe: child spawn, grandchild A,
  first child plan, grandchild B, later plan update.
- Source Ctrl+D and compiled Ctrl+C twice; tmux terminal flags, termios and
  owned process IDs before and after exit; stopped the isolated tmux server.

## Saw

- Grouped children update their current calls. The 80-column long title drops
  counts and keeps its brackets and tree glyphs.
- Permission names the asking child and marks its waiting call. Allow and Deny
  reach that child's write. The denial appears in its expanded work.
- The third child stands alone, starts with Initializing, then shows Bash.
  After the parent ends, the footer says `1 agent still running`; its eventual
  Done restores the shortcut hint without another prompt.
- Ctrl+o shows the task, thoughts, latest child plan, tool output and error,
  with the grandchild folded. The plan stays out of the parent's prompt list.
  Scrolling and resizing keep the work reachable.
- Esc leaves the failed child Failed, cancels the other child and grandchild,
  and shows Interrupted by user. The next text prompt succeeds.
- ACP-native idle becomes Done. The deliberate agent failure is shown as
  `The fake agent failed on purpose.`
- The ordering probe gives `agents[A], latest plan, agents[B]`, with planAt 1.
- Both exits returned to the shell, alternate screen off and cursor visible
  (`alternate_on=0`, `cursor_flag=1`). Termios matched except for macOS's
  transient PENDIN flag. Source UI/fake PIDs 11906/11939 and compiled
  UI/fake PIDs 28721/28800 were absent after exit. No QA tmux server remains.
  The pre-existing orphan fake PID 78189 belongs to CHD-158 and was left alone.

## Scope

The designer accepted pure-test coverage for the parent's plan beside children,
Codex wait, the lone child's full latest-three/+N fold, and the all-Done group
header: the fake does not emit those combinations. These captures do not claim
those combinations were driven in tmux. No live agent was used.

No production code or dependencies changed in QA. The engineer's documented
library trial was ink-tree-view 0.4.0 under Deno; its interactive one-row tree
API did not fit these transcript blocks. ink-task-list 2.0.0 was considered
and is flat. The finding remains in decisions.md.

## Build result

`deno task check` passed: 942 tests, 20 steps, zero failures (4m59s).
`deno task compile` succeeded and the resulting binary passed the keyboard
checks above. No blocking or incidental defect was found in this QA pass.
