# CHD-262 QA

Checked implementation `89316d3`, on main. Designer approval and its four
accepted differences from the mocks are retained. Appearance was not reopened.

## What ran

- `deno task check`: types, lint, formatting and the complete fake-agent suite;
  1460 tests (20 steps), zero failures, 8m32s. Staged evidence also passes the
  seven privacy tests.
- `deno task compile`: the host binary, then its startup in tmux.
- Source (`deno task chord:fake`) and compiled binary with the same fixture
  command: keyboard-only isolated tmux at 120x40 and 80x24, neutral scratch
  directories, separate XDG config/state, and the saved fake bugfix team.
- `team`, `agents`, `team2`; arrows, Enter, Esc, `ctrl+x a`, `x`, and `ctrl+d`.
  Text and Enter were sent separately. Captures are raw `capture-pane -p`.
- Actual AgentsList rendered probes with main and lead idle/seen, no monitor,
  and only one folded member timed: permission, working and unseen reply.
- Actual fake-agent window probes for OSC9 member notifications in two runs.
- `error` and `slow`, Esc interruption at both sizes, terminal mode snapshots,
  tmux alternate-screen/cursor flags, and process inspection before/after quit.

No live agent or model was used. No application code or dependency was changed;
QA wrote no component, renderer, parser or protocol helper and tried no library.
The implementation's existing Ink/string-width/cli-truncate scope and prior
widget trials remain as recorded in decisions.md and the reviewer handover.

## What was seen

- At 120x40 one team and parser/docs fit: lead runtime/model and nested members.
  At 80x24 the team folds to `team · fake · 3 agents`, naming tester's permission.
- Picking the lead unfolds it; moving through its members and past it refolds
  it. Up from parser lands on the lead and unfolds it. Esc back to the prompt
  with a member picked keeps its team open.
- Two runs fold independently. Focusing one leaves the other folded. The status
  line identifies `tester · bugfix 2`; attention reaches the member's permission
  and the box identifies its run. Source captures show tester's header; the
  compiled 120-4-member-picked capture shows coder's corresponding member header.
- The first x on an idle lead with a waiting member arms with the team sentence.
  Moving away disarms. Confirming on compiled bugfix 2 removes that lead and
  both members, tells main which closed, and leaves bugfix open. An idle source
  team closes on one x.
- Folded permission time in the compiled TUI advances from 1m 42s to 1m 44s.
  The isolated rendered probes advance permission/working/reply from 12s to 14s,
  without another timed row masking the timer gate. See folded-timing.txt.
- OSC9 names `tester (bugfix)` and `tester (bugfix 2)` exactly once each.
  See notifications.txt. Desktop display was not checked; tmux uses BEL.
- The fake agent's intentional error is shown. Esc stops slow work and draws
  `Interrupted by user`; the window remains usable at both sizes.
- Both quits return to zsh, alternate screen off and cursor visible. Echo,
  canonical input and signal flags match the initial modes; only macOS PENDIN
  differs. Every UI/agent PID identified from the owned process trees is gone.
  The isolated tmux server is removed. Unrelated pre-existing processes were
  left alone, including the wedged fixture noted by review.

The fake team has two members (three agents total), and uses fake model names.
These are fixture differences from the mocks, as already accepted on the task.
With parser/docs still open, five folded rows exceed the narrow list's limit;
closing those unrelated rows gives the two-run acceptance captures with both
leads visible. Scrolling and hidden-row counts remain the existing list rules.
