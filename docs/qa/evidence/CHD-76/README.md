# CHD-76 independent QA

Checked the combined settings change at `6a59344` on main. The
designer-approved appearance was left closed.

## Commands run

- `deno task check`: 444 tests and 20 steps passed, zero failures.
- `deno task compile`: produced the host aarch64-apple-darwin binary.
- Source and compiled binary against `tests/fixtures/fake_agent.ts` in an
  isolated tmux server, driven by keys only at 120x40 and 80x24.
- Temporary HOME, XDG_CONFIG_HOME, XDG_STATE_HOME and working directories;
  the existing Deno cache was reused. No live agent was used.
- `/status`, `error`, `long`, Esc, `text`, shift+tab, Ctrl+D and double
  Ctrl+C; resize from 120x40 to 80x24.
- Before/after `stty -g`, tmux alternate-screen and cursor flags, a shell
  command after exit, and final `ps -ax -o pid,ppid,command`.
- Evidence privacy scan and `git diff --check`.

The first sandboxed check was stopped after process-inspection restrictions
caused fixture cleanup failures. The unchanged check passed with the
required process access. Harness mistakes in expected fixture wording,
macOS stty parsing and raw storage-field assumptions were corrected;
those were not product findings.

## Observations

The user file selected `user-fake`, supplied the fake command and selected
Fake Small with acceptEdits. The project selected `fake` and plan. Starting
without an agent argument opened fake in plan mode with Fake Small;
`/status` confirmed both. This proves project agent/mode precedence and
inheritance of the user command/model. An unknown `theme` key was visible
before the first prompt and was reported once on stderr.

At 80x24, `--permission-mode acceptEdits --model fake-large` over the same
files opened Accept edits with Fake Large, also confirmed by `/status`.
Unsupported `--model nope --permission-mode bogus` showed both flag names
and the offered ids; shift+tab still changed the mode. Malformed project
JSON under source execution showed its file and error while retaining
the user's valid model and mode.

The compiled project run survived resize to 80x24. The fake `error` turn
showed “The fake agent failed on purpose.” Esc interrupted `long`, showing
“Interrupted by user”; a subsequent `text` prompt completed successfully.

For the returned defect, project A selected acceptEdits and project B
selected plan. A session created in B, resumed with `-C A` and a distinct
fake command, opened B in plan with the user model. B's warning was shown
relative to B, and the user warning appeared once. Another distinct
command with explicit mode/model flags opened B in Accept edits with Fake
Large at 80x24.

The already-filed CHD-80 limitation was independently reproduced: reopening
the same record with the same command showed no startup mode; after the
first turn, `/status` reported Default despite B's plan setting. This is
separate from the repaired project-settings directory resolution.
CHD-79 already records the unrelated shell-test flake. No new minor task
was needed and no change-owned failure was found.

All eight completed fixtures exited 0. Ctrl+D and double Ctrl+C were both
exercised. Every before/after stty value matched exactly, tmux reported
alternate=0 and cursor=1, and the shell accepted a command. The isolated
server and scratch directory were removed. Final process inspection found
no remaining fixture or QA tmux process; unrelated processes were not
touched. `terminal-restoration.txt` records the fixture readbacks.

## Library first and limits

QA wrote no product component, renderer, parser or protocol helper. Zod
was exercised through settings tests, source startup and the compiled
binary. The engineer's Deno/compile trials of Zod and Valibot, and the
reason for choosing Zod, are recorded in decisions.md; QA did not repeat
the Valibot comparison. The full check includes fake-agent session and
conversation tests plus settings precedence, missing, malformed, unknown
and invalid-value cases. Keyboard behavior was checked in tmux; this does
not establish terminal-emulator-specific key negotiation.

Captures have neutral temporary paths. `CHD-80-*` captures document the
existing limitation, rather than a passing startup-mode assertion.
