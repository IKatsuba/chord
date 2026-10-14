# CHD-299 — M4 and M5 end to end on Bun

QA on main, implementation commit `a715528`, Bun 1.4.2, macOS arm64.
All agent traffic used `tests/fixtures/fake_agent/main.ts`; no live agent or
model was used. The designer-approved appearance was not reconsidered.

## What ran

- `bun run compile`, producing `dist/bun-darwin-arm64/chord`.
- Source: `bun run chord:fake -C /tmp/chd299/<case>/work`.
- Binary: `dist/bun-darwin-arm64/chord fake -C /tmp/chd299/<case>/work
  --agent-command 'bun /tmp/chd299-repo/tests/fixtures/fake_agent/main.ts'`.
- Each launch in an isolated `tmux -L chd299` session at either 120×40 or
  80×24, with separate `XDG_CONFIG_HOME` and `XDG_STATE_HOME` under that
  case's scratch directory. `/tmp/chd299-repo` was a symlink to the checkout,
  keeping startup and quit captures public-ready.
- Literal prompt text and Enter were sent separately. Every in-app action
  used keys: arrows, Enter, Escape, digits, ctrl+o, ctrl+x a, x, page up/down,
  Home/End, and ctrl+d. No MCP calls were injected from outside the fake agent.
- Each M4/M5 session was resized to the other acceptance size and back.
- `stty -g` immediately before launch and after quit in the same
  non-interactive shell; tmux's alternate-screen and cursor flags after quit;
  raw terminal output for binary setup/teardown; `ps` cleanup checks.

For a repeat, create neutral scratch config/state/work directories, define
`agents.fake.command` as the fixture command in the scratch project's
`.chord/settings.json`, and copy `tests/fixtures/teams/fake/bugfix.md` into its
`.chord/teams/`. Never run these scenarios against an account-backed runtime.

## Keyboard reproduction

M4:

1. Type `chordcalls`: lists all runtimes, the fake models, and sessions; the
   unknown `fakx` task is visibly refused.
2. Type `task`; capture the nested task and its permission, press 1, wait for
   its report, and use ctrl+o/page up to inspect its work.
3. Type `agents`; inspect messages to/from parser and the children under the
   prompt. Down, Down, Enter picks parser; type `text` to prove the person's
   prompt reaches that child. ctrl+x a picks docs; capture its permission and
   press 1. Down, Up, Up, Enter returns to main.
4. Type `chordtools` to inspect the actual list response naming parser and
   docs (the first source 120 case used `chordcalls` again instead).
5. Type `agentclose`: parser closes and its subsequent message is refused.
6. Type `monitor`; wait for the error event. Down three times focuses its
   running row; x stops it. Up and Enter return to main for the stopped event.
7. Type `error` and inspect the visible failure; type `slow`, then Escape
   interrupts it. Resize and restore the window. Quit with ctrl+d, twice
   when chord arms for busy work.
8. Relaunch with `--resume <main-session-id>` using the same scratch state.
   Inspect the closing note, then ctrl+o and scrolling for old task work,
   reports, Open/Close calls, and messages. Quit again.

M5:

1. In the proposal case type `/team new a bugfix team`, capture the proposal
   table and save box, then press 1. Capture the saved result and quit.
2. In the lifecycle case use the existing fake-runtime bugfix fixture.
   The proposal fixture deliberately proposes claude/codex models; those
   saved proposals were inspected but never run. The separate lifecycle
   fixture keeps every lead/member process on the fake runtime.
3. `/team` opens the picker; Escape closes it. `/team show bugfix` shows the
   saved team. `/team run bugfix Issue 214 fix the closing quote` starts it.
4. Down, Down, Enter picks the lead: inspect Open(tester), Open(coder), their
   runtime/model/mode, and messages. ctrl+x a picks tester; press 1 to answer
   its permission, and inspect the result and direct coder/tester messages.
5. Return to main with Down, Up, Up, Enter. `/team show bugfix` reports the
   running agents. `/team run bugfix Issue 219 fix parseDate` creates
   `bugfix 2`; inspect folding, then ctrl+x a unfolds its tester. Press 1.
6. `/team stop bugfix 2` closes that run and both members; inspect chord's
   message and the surviving first run. Resize and restore; quit.
7. Relaunch with `--resume <main-session-id>`: the past reports and closed
   run are shown, the open run is named with three agents, and no children
   are reopened. `/team run bugfix Fresh resumed job` starts a fresh run.
   Quit while its member permission waits, confirming busy-quit teardown.

## Evidence map

Each `source-120`, `source-80`, `binary-120`, and `binary-80` prefix has
`-m4`, `-proposal`, and `-m5` directories. Numbered `.txt` files are raw tmux
text captures; matching `.ansi` files retain colours. Expanded/scroll captures
show rows that cannot fit simultaneously in the narrow viewport. Captures are
not edited or normalized.

| Acceptance | Captures within each case |
| --- | --- |
| list_agents/list_sessions | M4 lists-and-refusal; list-children-json where present |
| nested spawn_task and report | M4 task-permission, task-report, task-past/expanded |
| child chat, person prompt, messages both ways | M4 children-messages, parser-chat, parser-messages, parser-person-prompt |
| child permission and answer | M4 docs-permission, docs-allowed |
| close_agent and refusal | M4 close-refused-message |
| monitor transcript/running row/x stop | M4 monitor-event-running, monitor-focused, monitor-stopped-message; first source-120 stopped message is in resume-no-reopen |
| children/tasks/messages on resume, no reopen | M4 resume-no-reopen and resume-past/forward captures |
| proposal and save | proposal proposal-save-box, saved |
| show/run/stop | M5 team-show, team-show-running, team-run-report, stop-second |
| lead opens members, nesting/folding | M5 lead-members/lead-past, second-run-folded, second-member-unfolded/permission |
| report to main | M5 team-run-report/main-report and second-run-folded |
| second run | M5 second-run-folded, second-member, stop-second, first-run-survives |
| team resume and way back | M5 resume-no-reopen, resume-past, resume-fresh-run |
| error/interrupt/resize | M4 agent-error, interrupt, resize-other/back; M5 resize-other/back |
| quit/terminal | cleanup.json and cleanup-first.json within each case |

## What was seen

Every listed M4/M5 flow worked from source and the host binary at both sizes.
Permission choices reached the fake agent; task reports reached main; messages
retained their sender; selecting a child changed both transcript and prompt.
Monitor x removed its row and delivered the stopped message. `bugfix 2` had its
own lead and members; stopping it preserved the first run. Resume showed saved
work and messages without starting children or teams, and named `/team run`
as the way to start a new team.

All captured quits exited 0 with identical before/after `stty`,
`alternate=0`, and `cursor=1`. Binary raw output contained alternate-screen
entry/leave and cursor-show sequences. This proves tmux behavior, not physical
kitty keyboard negotiation or desktop notification display.

No component, parser, renderer, protocol helper, or library was built for this
QA task, so no new library trial was needed. The existing fixtures, ACP/MCP
SDKs, and Ink interface were exercised as built.

## Checks and findings

`bun run check` passed: 51 lint tests and 1,508 tests across 109 files,
zero failures (the fake/session/UI suite took 481.15 seconds). The full check
ran in the foreground with loopback and process-query access. The first
restricted attempt could not bind its loopback servers or run `ps`; it was
stopped, its identified wedged fake was killed, and the unchanged check was
rerun with access. Expected fixture shell diagnostics and the Vim suite's
caught library diagnostics appeared on stderr; they did not fail the check.

The seven privacy tests passed against the staged captures. No private paths
were found in this task's evidence. `git diff --cached --check` passed.
`ps` after the full check and matrix found no fake agents or monitor shells;
tmux reported no CHD-299 server running. A supplemental source resume overlapped
an active binary case; its process snapshot explicitly names that other case,
whose subsequent cleanup and the final audit prove its exit.

No new functional findings were identified, so no new finding tasks were
filed. No implementation code changed. Evidence and verification results are
committed locally on main for chd-lead to close CHD-299 and consider CHD-160.
