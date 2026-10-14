# CHD-128 independent QA

Checked on main at `f0594a7`, including the return fix `d6baeb7`.
This is QA evidence only; no implementation or appearance changes.

## Commands and procedure

Read the binding repository documents and the board's `quarry` and
`chord-tui` skills. Ran `deno task check` with process-query access and
`deno task compile`. The source launch was `deno run --quiet --allow-all
--config <repo>/deno.json <repo>/src/main.tsx fake --agent-command
<scratch>/agent.sh -C <scratch>/work`, with the flags below. The compiled
launch used `dist/aarch64-apple-darwin/chord` with the same arguments.

Each case had its own scratch working, configuration and state directories,
using `XDG_CONFIG_HOME` and `XDG_STATE_HOME`, and a dedicated tmux socket.
The executable `agent.sh` only execs `deno run --quiet --allow-env --config
<repo>/deno.json <repo>/tests/fixtures/fake_agent.ts`. No real agent was run.
The shell recorded `stty -g` before chord, then `stty -g`, `stty -a` and the
exit code immediately after it, before starting an interactive shell again.

Created panes at 120×40 and 80×24. All interactions with chord were keys:
literal text and Enter in separate tmux calls, with a settling pause.

- `start`: `CHORD_FAKE_HANG=start`; ctrl+d while Starting.
- `starting-model`: `CHORD_FAKE_HANG=config`, `--model fake-small`;
  ctrl+d while Starting.
- `starting-mode`: `CHORD_FAKE_HANG=config`, `--permission-mode plan`;
  ctrl+d while Starting.
- `clear`: the starting-model launch; `/clear`, wait for the replacement
  startup and record both owned agent PIDs, then ctrl+d while Starting.
- `config`: `CHORD_FAKE_HANG=config`; `/config`, Enter on Effort, `3` for
  High, then ctrl+d with the config answer still outstanding.
- `turn`: `CHORD_FAKE_HANG=turn`; send `text`, resize to the other tested
  size and back, Esc, then ctrl+d while Interrupting.
- `normal` and `binary`: unset `CHORD_FAKE_HANG`; send `error`, then `slow`,
  Esc, then `text`, and ctrl+d after the reply.

Before quit, `/bin/ps -axo pid=,ppid=,command=` identified descendants of
the pane's shell, including each fake-agent process. After exit, checked
every recorded PID and the pane's descendants again. Read tmux's
`alternate_on` and `cursor_flag`. Captured the before, stopping and shell
screens with `tmux capture-pane -p`; destroyed the isolated tmux server
and checked for processes bearing each scratch path after teardown.

## Observations

`deno task check` passed: types, lint, format and 797 tests (20 steps),
0 failed, in 7m7s. This includes the fake-only Session and Conversation
shutdown regressions for pending config, cancel-ignoring turn, startup,
starting model, starting mode and clear followed by close. `deno task compile`
completed successfully; the local binary started and passed the normal-agent
interaction at both sizes. The staged-evidence privacy check passed all
7 tests, and `git diff --cached --check` passed.

| Case | 120×40 quit | 80×24 quit |
| --- | --- | --- |
| start | 1.84 s | 1.84 s |
| starting-model | 4.80 s | 4.81 s |
| starting-mode | 4.80 s | 4.82 s |
| clear | 7.06 s | 7.17 s |
| config | 4.80 s | 4.81 s |
| turn | 1.84 s | 1.75 s |
| normal | 0.72 s | 0.72 s |
| binary | 0.71 s | 0.73 s |

Every case exited with code 0, alternate screen off, cursor shown,
canonical/echo input enabled, exact pre/post stty equality, no recorded
owned PID alive and no pane descendant left. The two clear cases each
recorded both retired and replacement agent PIDs. Timing includes the
700 ms pause for the stopping capture, command overhead and up to 100 ms
of completion polling. Both tmux servers
were destroyed, and no process with their scratch path survived teardown.

The hang cases, timing and terminal/process observations are in
`results.json`; normal and compiled launches are in `normal-results.json`.
Each result records the observed owned PIDs and agent PIDs, the survivors,
terminal flags and exact pre/post `stty -g` comparison.

The fake agent's deliberate turn error was visible as
`The fake agent failed on purpose.` Esc on its normal slow turn produced
`Interrupted by user`; a subsequent `text` prompt received
`Hello, world. This reply came in chunks.` The compiled binary exercised
the same interaction. The cancel-ignoring turn stayed Interrupting through
Esc, but quit still released it. Resizing that turn preserved the transcript
and prompt and left quit usable at both sizes.

The first normal-agent harness attempt accidentally exported an empty hang
value, which the fixture correctly rejects; those captures were replaced
by the corrected unset-variable run. That harness failure is not product
evidence.

The implementation retains acpx/runtime. Independently inspected pinned
acpx 0.19.4's public declarations: `ensureSession`, `close`, and `shutdown`
offer no close deadline or cancellation signal; the runtime timeout also
applies to turns, and `processLifecycle` is available. The implementation's
documented fallback bounds the close while using those existing lifecycle
hooks. No new library or product helper was written by QA.

No blocking findings or separate minor tasks. Unrelated untracked design
evidence was left alone. Captures use a neutral scratch cwd and shell prompt;
any repository path is redacted to `<repo>`.
