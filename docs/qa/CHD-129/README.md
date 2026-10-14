# CHD-129 QA

Checked on main at `d6baeb7`, including the reviewed change `6692759`.
The designer's appearance approval remains accepted.

## Ran

- `deno task check` on the current tree. The restricted attempt was stopped
  after sandbox failures; the unchanged command was rerun with process access.
  Result: 794 passed, 20 steps, zero failures (7m05s), including immediate mode
  readback, starting mode, refusal and legacy fallback fixture coverage.
- `deno task compile` for macOS arm64.
- Source and compiled TUI in a dedicated tmux server, with isolated
  `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and `-C /tmp/chd129-qa/work`.
  Both used the fixture agent with `CHORD_FAKE_SILENT_SET_MODE=1`.
- Keyboard-only Shift+Tab, prompts `lock`, `error`, `slow` and `mode`, Esc,
  Ctrl+D and Ctrl+C twice; resize between 120x40 and 80x24.
- tmux alternate-screen/cursor state, exact before/after `stty -g`, and
  `ps` for the recorded TUI and agent PIDs, followed by tmux server cleanup.
- Capture privacy scan and `git diff --check`.

## Saw

- Source: default -> acceptEdits -> plan -> default reads back immediately,
  before any prompt, at both sizes. Each state has a capture.
- Fresh source `--permission-mode plan` shows plan before any prompt at both
  sizes. Fresh compiled `--permission-mode acceptEdits` shows accept edits
  before any prompt at both sizes; the `mode` scenario confirms acceptEdits
  inside the turn.
- Compiled: Shift+Tab changes acceptEdits to plan before any prompt; the
  `mode` scenario confirms plan inside the turn.
- Source and compiled: `lock`, then Shift+Tab, shows
  `Could not switch to default mode: The fake agent holds its mode.` once,
  and the status line keeps plan at both sizes.
- Source: `error` shows `The fake agent failed on purpose.`; `slow` survives
  a resize while streaming, and Esc reports `Interrupted by user`. Plan stays
  accurate through both.
- Source Ctrl+D and compiled Ctrl+C twice restore `alternate=0`, `cursor=1`.
  Both restore the exact terminal settings baseline. Recorded PIDs are gone;
  the final process snapshot has no child of the QA shell and no TUI/agent
  working in the QA scratch directory. The isolated tmux server was removed.
- Captures contain no private home path or account name.

## Scope

The maintained `acpx/runtime.setConfigOption` path was exercised through fake
agent integration tests and both running builds. No dependency or protocol
helper was added. The fake advertises default, acceptEdits and plan, so those
IDs were used; the real adapter's read-only ID is not advertised by the fake.
No live agent was used. CHD-80 resume replay and headless mode remain outside
this task. No task-owned defect or minor finding was found.
