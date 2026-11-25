# CTUI-26 interface evidence

Observed original: `577b58167672e12c999aeaf4eed2a1a988513dc2`.
Observed current port: `c32e433417abba75f0a5378edec65c3c5546af36`.
Captured with an owned isolated tmux server, original fake only, no model.
Each txt is a plain pane capture; matching ansi retains captured styles.
Files are **sanitized captures**, not untouched terminal dumps or port parity
proof. Screen dimensions appear in filenames; `32` means 32x10.

## Inputs and reproduction

Use fresh synthetic XDG state/config/cache and two synthetic project folders.
Records live in the state's chord/records folder. Seed 18 version-1 sessions
for agent fake, ids interface-0 through interface-17, age i hours. Every third
record belongs to the other synthetic directory, the rest to this project.
First prompt is `Saved session example <i+1>`, except interface-1 uses
`Inspect wrapping, history and session resume behavior across a deliberately
long saved session title with extra details 2`. Each record has a session
header and prompt entry (turn-1, images 0). Use compact JSON, type field first:
the original discovery fast path recognizes the exact compact prompt prefix.
Initial spaced JSON setup was rejected by original discovery and rerun;
retained page captures come from compact records.

From original checkout, the standard QA entry point was also run:
`bun dev chord --fake --qa ctui26-interface`; its fresh idle window is
`original-120-qa-idle`. It resets its state each run, so seeded multi-invocation
resume evidence uses the equivalent source launcher with isolated XDG state:
`bun --define 'process.env.NODE_ENV:"production"' src/main.tsx fake
--agent-command '<bun> ../chord/tests/fixtures/fake_agent/main.ts'
-C <synthetic-project> [--resume]`. Angle-bracket labels are parameters, not
literal runnable paths. Source/fake executable paths must be resolved by the
runner without editing original. No configuration from a real user is used.

Current port launched with `dart run example/chord/bin/chord.dart fake
--agent-command '<bun> ../chord/tests/fixtures/fake_agent/main.ts'`, in the
same synthetic project with isolated XDG variables. `--resume` was added for
the explicit CLI rejection capture. Original and port version strings differ.

## Capture key sequence

- Original `--resume` at 120x40: start; Ctrl+A all; resize 80x24 all; Ctrl+A
  here; Esc exit.
- Original normal fake at 80x24: type `/resume`, Enter; Ctrl+A all; Enter on
  first (other-directory) session; capture reopen report; resize 120x40;
  type `/resume`, Enter; capture local overlay; Ctrl+D quit.
- Current port at 120x40: idle; type `/resume`, Enter; resize 80x24; capture
  still-typed draft; Ctrl+D quit. No accepted command report is claimed.
- Current port at 80x24: launch with `--resume`; capture help and exit-2 error.
- Original startup with isolated settings theme light at 120x40, resize 80x24;
  Esc. Repeat with NO_COLOR=1 for plain captures.
- Original startup from empty synthetic local directory, keeping existing
  records elsewhere: 120x40, 80x24, then 32x10; Esc.
- Original normal fake: type `permission`, Enter; wait for permission;
  capture 120x40 then 80x24; Esc reject then Ctrl+D quit.

## Sanitization and limits

Absolute synthetic cwd labels became `fixture-project`, `fixture-other` or
`fixture-state/empty`; QA cwd became `fixture-project`. Original source and
port source roots became `../chord` and `.` when a complete path appeared.
Rows containing wrapped absolute fake command paths were replaced with
`[synthetic fake command redacted; original row wrapped here]`. These
substitutions shorten labels without relaying out terminal output, so retained
line breaks are observations but sanitized column positions are not an exact
width oracle. Use source geometry rules for implementation. Tmux's dead-pane
footer is harness output, not product wording.

No real data, account, agent credentials or model was used. Existing original
was read and executed, never edited. App runs received cooperative Esc/Ctrl+D before the owned tmux server was
killed. One verified owned port capture process remained after Ctrl+D and
SIGTERM; it was stopped with SIGKILL after rechecking its command and start
time. This capture-run cleanup observation is not attributed to a product
baseline failure. Final process-table checks found no retained fake-agent or
owned capture processes. No persistent tmux server is retained. Synthetic temporary data is not user data; it is not a production
record fixture or compatibility pass. Combined streaming/picker, picker
suspension, reopen error and resumed/omission port screens remain ship gates,
as listed in the interface draft.
