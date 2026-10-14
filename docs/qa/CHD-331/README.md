# CHD-331 — forced exits reap owned processes

QA passes for implementation `421bf6d4` on `opentui`. This is the scoped
forced-exit repair, not CHD-310's whole-move acceptance or permission to
merge. Main remains at `3538862f`. Bun 1.4.2, macOS arm64, tmux 3.6a.

## What ran

- `bun run compile` produced the host binary. Its SHA-256 is in
  `verification.json`; every binary probe used that exact build.
- `bun run check` exercised types, lint, formatting and the fake-agent
  session/UI suite with process inspection available.
- 78 isolated keyboard-driven tmux probes, source and host binary at
  120×40 and 80×24, with scratch work/config/state directories. The pane's
  foreground command inherited real terminal stdin. Text and Enter were
  sent separately. No live agent or real model ran.
- All seven intercepted signals with a submitted hung turn:
  `SIGINT`, `SIGTERM`, `SIGQUIT`, `SIGABRT`, `SIGHUP`, `SIGPIPE`, `SIGBUS`.
- Uncaught exceptions, unhandled rejections, two exceptions 200 ms apart,
  TERM then HUP 200 ms apart, and an exception followed by HUP during close.
- TERM then HUP with two independently hung fake-agent tabs.
- Two running monitor groups under the fake's `CHORD_FAKE_HANG=config`
  mode, which ignores TERM and EOF and requires the existing SIGKILL
  escalation. Signal overlap, exceptions and rejections ran in all four
  build/size combinations; double exceptions also ran on source 80×24 and
  binary 120×40. All except the first source 80×24 signal probe also chose
  another effort through `/config`, whose request the fixture never answers.
- Ctrl+C twice and Ctrl+D controls against the hung-turn fixture, plus
  responsive-fixture error, Esc interrupt/recovery, resize in both
  directions and ordinary Ctrl+D quit on all four build/size combinations.

## What was seen

Every probe restored exact `stty -g`, left the alternate screen, showed the
cursor and disabled mouse tracking. Raw terminal output independently
contains alternate-screen leave, cursor show and mouse-disable sequences
for modes 1000, 1002, 1003 and 1006. Every recorded owned PID and every
member of the recorded agent/monitor process groups was absent after exit.
No probe orphan required killing.

Signals exited with `128 + signal`; TERM followed by HUP preserved the
first signal, exit 143. All injected crashes printed their error and stack
on stderr and exited 1. Both exception callbacks logged firing before the
double-crash probe exited. The mixed exception/HUP probes also exited 1.
Forced cleanup took approximately 4.0–4.2 seconds, including two hung tabs
and the monitor groups, within the unchanged process stop bounds. Hung
Ctrl+C/Ctrl+D controls exited 0 in approximately 4.0–4.5 seconds.

Responsive controls displayed `The fake agent failed on purpose.`, showed
`Interrupted by user` after Esc, then completed the next prompt. The reply
remained usable after narrowing/widening and returning to the original
size. Ordinary Ctrl+D exited 0 and restored exact terminal state.

The fix reuses `OpenSessions.closeAll` and the existing agent and monitor
process-group lifecycle helpers. QA introduced no component, renderer,
parser, protocol helper or dependency. The designer-approved appearance
was not judged again. No unrelated findings or separate tasks were filed.

## Reproduction

1. Use an isolated tmux socket/session and fresh XDG config/state and work
   directories. Use a neutral `/tmp` symlink to the checkout for public
   captures. Start source or the host binary with `fake --agent-command
   'env -u BUN_OPTIONS bun <neutral-checkout>/tests/fixtures/fake_agent/main.ts'`
   and `-C <scratch-work>`, setting `CHORD_FAKE_HANG=turn`.
2. Type `hello`, pause, then send Enter separately. Capture the submitted
   prompt and `Working…` before forcing the exit. Record chord's exact PID,
   its descendants and their process groups with `ps -axo pid,ppid,pgid,command`.
3. Send the signal to chord's PID. For overlap, send TERM then HUP 200 ms
   later. For two tabs, use Ctrl+X then C and submit `hello` in the new tab
   before signalling.
4. For crashes, set `BUN_OPTIONS='--preload <scratch>/crash.ts'` on chord.
   The production binary accepts this environment option. The fake command
   unsets it so only chord receives the injected crash. A preload can poll
   for a scratch trigger file, then throw or reject an Error; for overlap,
   schedule a second throw 200 ms later. Create the trigger only after the
   running capture and PID recording. Do not change the compiled artifact.
5. For monitor groups, set `CHORD_FAKE_HANG=config`, submit `monitors`, and
   wait for `Two monitors are running.`. Choose another effort through
   `/config` (Enter, Down, Enter). The existing fixture leaves that request
   unanswered while the two monitor processes remain alive.
6. After exit, compare before/after `stty -g`, capture the returned shell,
   read tmux's alternate/cursor/mouse flags and raw output, and check every
   recorded PID/group with `ps`. Remove the owned session/server and scratch
   work/config/state directories.

## Evidence and limits

`exits/<build>-<width>-<case>/` contains paired text/ANSI captures, exact
termios before/after, owned PID/group records, result JSON, crash stderr,
raw restoration counts and gzip-compressed unedited terminal output.
`verification.json` records the binary hash and all 78 results. The source
80×24 monitor-overlap probe established the wedged fixture's bounded stop
and live groups without submitting a config request; the other monitor
probes cover an unanswered config request too.

Only the host macOS arm64 binary was run. This repair's QA does not repeat
CHD-310's full M1–M5 acceptance, physical-terminal checks, other platforms,
or the settled appearance. No main merge, push, publish or PR occurred.
