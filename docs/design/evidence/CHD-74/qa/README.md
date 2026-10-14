# CHD-74 independent QA

Checked feature and race fix at `7dc9822` on `main`. Appearance remains
designer-approved. These are independent `tmux capture-pane` captures, with
plain text and ANSI for the six required states.

## Commands run

- `deno task check`: 408 tests, 20 steps, no failures. Process-inspection
  access was needed for the suite's `ps` cleanup checks.
- `deno task compile`: produced the local standalone binary.
- Source: `deno run --allow-all src/main.tsx fake --agent-command <fake agent>`
  in tmux at 120x40, with an isolated `XDG_STATE_HOME` and scratch `-C` directory.
- Compiled binary: `dist/aarch64-apple-darwin/chord fake --agent-command
  <fake agent>` in a separate tmux pane at 80x24, with separate state and cwd.
- The fake command was Deno running `tests/fixtures/fake_agent.ts` with the
  repository's `deno.json`. No live agent was used.
- `tmux send-keys` sent literal text and Enter separately. `capture-pane`
  read the screen; `resize-window` changed the open picker to 80x24 and back.
- `ps -axo pid=,ppid=,command=` established descendant fake-agent PIDs and
  checked their exit. `stty -g` and tmux's `alternate_on` and `cursor_flag`
  checked terminal restoration.

## Observed behavior

Three earlier sessions were created through the TUI by sending `/echo` prompts
and `/clear`. Only their isolated records' `last_used_at` timestamps were then
set to 5 minutes, 3 hours and 2 days ago, to make ordering visible.

At both sizes, `/res` offered `/resume`; Tab completed it and Enter opened the
picker. It contained exactly those three sessions, newest first, with relative
times and the long first prompt truncated. Up and Down moved the highlight.
The open source picker survived a resize to 80x24 and back, and navigation
continued. Esc closed it; `/status` confirmed the current session ID stayed.

Reopening, pressing Down and Enter replayed the middle session in this window.
The previous transcript disappeared. `/status` matched the seeded session ID,
and `/echo continued in place` answered while keeping that ID. The previous
fake-agent PID had exited. Reopening the picker excluded the current session.

During `long`, `/resume` displayed the refusal sentence and opened no picker.
Esc interrupted the turn, and the interface accepted `error` next; the agent's
failure sentence was visible. Fresh directories displayed the no-earlier-session
sentence at both sizes, without an empty picker.

The full suite exercised the delayed-read regression against the fake agent:
hold the session-record read, start a turn, then release it. Refusal is shown,
no picker opens, and session identity remains. Reducer cases also reject stale
completion after clear, closing and a newer request.

Ctrl+D quit the source run; Ctrl+C twice quit the compiled run. Both fresh
directory runs also quit successfully. Each returned exit code 0, restored the
cursor and left the alternate screen (`cursor_flag=1`, `alternate_on=0`), and
had byte-identical before/after `stty -g` settings. Each observed fake-agent PID
was absent from `ps` afterwards. The isolated tmux server was removed.

Library reuse is unchanged: the existing picker, Ink truncation,
`Intl.RelativeTimeFormat`, and acpx session records and replay. The prior
`ink-select-input` and `@inkjs/ui` Select trials are in `docs/decisions.md`.
QA added evidence only. No new library or implementation was written.

No new findings were filed. CHD-77 already tracks the shared list's hidden-row
count. The pre-existing CHD-32 evidence was left untouched.
