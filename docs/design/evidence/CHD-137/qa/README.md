# CHD-137 independent QA

Checked implementation `20e2922` on main with the fixture agent only.
Appearance was already approved; these captures prove behaviour.

## Commands and inputs

- `deno task check` (types, lint, format, fake-agent tests).
- `deno task compile`, then the resulting macOS arm64 binary in an isolated
  tmux server, with temporary `XDG_STATE_HOME`, `XDG_CONFIG_HOME` and `-C`.
- Fake command: `deno run --quiet --allow-env --config <repo>/deno.json
  <repo>/tests/fixtures/fake_agent.ts --resume-only`. For the public refusal
  capture, a temporary shell wrapper runs that same fixture command.
- Send literal text and Enter separately: `edit`, `text`, quit with Ctrl+D,
  then run the printed resume command. Capture at 120x40; resize to 80x24.
- `/cost`, `text`, `/cost`, quit, reopen, `/cost`.
- `status`, quit, reopen with `--permission-mode acceptEdits`, `/status`.
- `error`, `slow`, Esc, quit.
- `--continue` without `--resume-only`; repeat with
  `CHORD_FAKE_REFUSE_LOAD=1`.
- New session in the record's directory: `/resume`, Enter. New session in
  another directory: `/resume`, Ctrl+A, Enter.
- Source launch with `deno run --allow-all <repo>/src/main.tsx`, the same
  isolated state/fixture, and `--continue`; Home, Ctrl+C twice.

## Observations

- Both sizes show the recorded edit's numbered additions/removal and reply.
  Resize retains the diff and input; context returns as 99% left.
- Restored tokens are 2,000 input, 400 output, 1,600 cache read (4,000 total).
  After another text turn they are 3,000, 600, 2,400 (6,000 total), unchanged
  after another reopen. The fake's cost is its reported cumulative value for
  each process; it resets when the fake process starts again.
- Historical plan mode is replaced by accepted starting Accept edits in
  `/status` and the status line. Without starting settings, the reopened
  agent's default mode is shown.
- Load shows only the fake's tools/text replay, once, with no recorded edit.
  Refused load shows Resource not found and leaves an input box.
- Local picker selects and opens the record. Other-directory local scope is
  empty; all-directory scope lists the record; selection gives the command
  to quit and open it in its own directory.
- The deliberate agent error is visible. Esc ends slow with Interrupted by
  user. Both Ctrl+D and Ctrl+C twice restore the shell, with tmux reporting
  `alternate_on=0`, `cursor_flag=1`; before/after `stty -g` matched exactly.
- The isolated tmux server was removed. Process cleanup is checked with `ps`.

No live agent, owner settings changes, push, publication or PR.
Captures were read and scanned for private paths before staging.

Validation: `deno task check` passed (830 tests, 20 steps, zero failures).
`deno task compile` passed and its binary ran all terminal checks above.
The privacy tests also passed after staging these captures (7 tests).
The first restricted check stalled during the wedged fake's initialize;
its runner and identified fake process group were stopped before the unchanged
check passed with process access. Final `ps` showed no fake agent, check runner
or isolated tmux server remaining. No separate minor findings were filed.
