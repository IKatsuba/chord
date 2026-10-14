# CHD-43 independent QA

Checked the approved implementation at `04051ef`, using the scripted ACP agent
and an isolated tmux server. All input was sent by keys; each BTab was a separate
send, with captures taken after the screen settled. No live agent or model was
used.

## Commands

- `deno task check`: types, lint, formatting and fake-agent tests. The first run
  lacked sandbox permission to spawn `ps` for cleanup; the unchanged command
  was rerun with subprocess access and passed: 211 tests (20 steps), zero
  failures, plus types, lint and formatting.
- `deno task compile`: produced the host binary.
- `deno task chord:fake -C /tmp/chd43-qa/work`, with isolated XDG state.
- Compiled `chord fake -C /tmp/chd43-qa/work --agent-command <fake agent>`.
- `tmux send-keys`, `resize-window`, `capture-pane -p -e`, `display-message`;
  `ps` readback of the exact TUI and agent PIDs after quitting.

## Observations

- `120-0..3.ansi` and `80-0..3.ansi`: default, accept edits, plan, default.
  The same source process was resized from 120x40 to 80x24.
- `80-draft.ansi`: plan stays visible while typing a draft.
- `80-exitplan.ansi`: the agent leaves plan, restoring the default status.
- `80-error.ansi`: the agent's deliberate failure is visible.
- `80-mode-during-turn.ansi`: Shift+Tab changes mode while `slow` streams.
- `80-interrupt.ansi`: Escape interrupts the turn, preserving the mode.
- `80-lock.ansi`, `80-refused.ansi`, `120-refused-resize.ansi`: the agent
  reports plan through current_mode_update alone; a refused request for default
  displays the error and keeps plan, including after resize.
- `quit-warning.ansi`, `source-return.ansi`: two Ctrl+C presses return to the
  shell with exit 0. tmux reports alternate=0, cursor=1; the output stream
  includes alternate-screen exit and cursor-show sequences.
- `binary-*.ansi`: the compiled binary starts at 80x24, cycles the mode,
  interrupts a streaming turn, and quits with Ctrl+D, exit 0. tmux reports
  alternate=0, cursor=1; stty before/after values match exactly.
- Source TUI/agent PIDs 54225/54274 and binary TUI/agent PIDs 57048/57174 were
  absent after quit. The isolated tmux server was removed. Other fake-agent
  processes seen during concurrent tests were identified by their parent PIDs
  and were not attributed to the TUI.

Library first: the exercised path is Session.setMode → AcpxRuntime.setMode in
acpx 0.19.4, which dispatches session/set_mode. No direct SDK control or new
implementation was added by QA. Ink draws the status; cli-truncate remains the
library for model truncation. The appearance was already designer-approved.

CHD-50 already tracks the empty earlier captures. Existing CHD-32 evidence was
left untouched; no additional findings were filed.
