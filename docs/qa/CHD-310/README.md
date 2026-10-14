# CHD-310 — whole-move acceptance on OpenTUI

**Latest QA failed on CHD-334:** see [resumed acceptance](resumed/README.md).
CHD-331 is repaired and its final-tree exit probes pass.

The first pass below is historical. It failed on CHD-331 at implementation `699e16e` on
`opentui`; main remains at `3538862`. Bun 1.4.2, macOS arm64, tmux 3.6a.
No implementation changed, no live agent or model ran, and the approved
appearance was left settled.

## What ran

- `bun run compile`: built the host binary at
  `dist/bun-darwin-arm64/chord`.
- `bun run check`: 51 lint tests and 1,489 tests across 108 files, zero
  failures (495.86 seconds for the session/UI suite).
- Keyboard-only isolated `tmux -L chd310` sessions: source and host binary,
  each at 120×40 and 80×24, with fresh scratch work/config/state directories.
- CHD-299's M4/M5 and CHD-300's M3 recipes, using the existing fake agent,
  fake-runtime team fixture, scripted editor, and generated PNG clipboard.
- M1/M2 prompts, markdown/code/diffs, thought expansion, permission denial,
  multiline input/history/search, plan/status, shortcuts, mode/model/config,
  slash completion, file resource links, bash context, cost/context/status,
  queue cancellation/delivery, scrolling/expansion/resize, saved-window
  resume, `/clear`, `/new`, and quits.
- Headless fake turns on both builds: JSON, permission denial/allow,
  starting mode, piped input and visible errors.
- Every ordinary exit: Ctrl+C twice, Ctrl+D, `/exit`, start-picker Escape;
  SIGTERM, SIGHUP, and SIGINT as an additional path. Source also ran
  injected uncaught exceptions and unhandled rejections.
- An unresponsive fixture (`CHORD_FAKE_HANG=turn`) on forced exits and
  ordinary quits. Exact `stty -g`/`stty -a`, terminal flags, raw output and
  owned PIDs were recorded. Probe orphans were explicitly killed.
- No `test.todo` found in tests; JSON5 inspection confirmed that `ink`,
  `ink-select-input`, `ink-spinner`, `react-ink-textarea`, and
  `ink-testing-library` are absent from both manifests' direct dependencies.

The first restricted check was gated by loopback/`ps` permissions. Its owned
processes were stopped, including its deliberately wedged fake, and the
unchanged authorized run above passed.

## What was seen

The CHD-299 and CHD-300 rows worked in all four combinations. Captures show
lists, task permissions/work/reports, child chats/messages/close/refusal,
monitor events and key stop, team proposal/save/show/run/stop, nested members
and folding, independent second runs, and old children/teams on resume
without reopening. M3 captures show PNG receipt, editor return, Vim editing,
theme selection, terminal deltas/failing exit, subagents/permissions,
compaction/failure, matching MCP readback, rebound keys, tab drafts and
cross-directory pickers. They follow the same recipes as main's records in
`docs/qa/CHD-299` and `docs/qa/CHD-300`; timings and scratch identifiers differ.

M1/M2 captures show streamed replies and markdown, thought/diff expansion,
permission rejection, multiline/history/search, plans, modes/models/effort,
file receipt as a resource link, bash output delivered with the next prompt,
usage reports, queued input returned on interrupt and delivered after a
turn, and usable scrolling after expansion/resize. Saved windows reopened
both tabs; `/clear` made a fresh session and `/new fake` opened another tab.
Headless error turns exited 1; the other checked headless paths exited 0.

All responsive-fixture exits restored exact terminal state, left the
alternate screen, disabled mouse tracking, showed the cursor, and left no
owned agent. Source crash errors/stacks reached stderr and exited 1.
**Forced exits with an unresponsive agent did not reap that agent.**
Ctrl+C twice and Ctrl+D twice reaped the same unresponsive fixture.

The original clipboard item representations were restored with each type's
data equal. One initial AppKit helper restore omitted a text flavor; a
second restore recovered it and the final comparison passed. Private
clipboard backups remain outside the repository.

## CHD-331 reproduction

1. Create scratch work, XDG config and state directories; use a neutral
   `/tmp` symlink to the checkout for public captures.
2. In a 120×40 tmux pane run `CHORD_FAKE_HANG=turn bun run chord:fake -C
   <scratch>/work`, with the scratch XDG directories exported.
3. Type `text`, then send Enter separately. The fake never finishes the turn
   and ignores SIGTERM and stdin EOF by design.
4. Record chord's and its child's PIDs with `ps`. Send SIGTERM to chord's
   process, rather than its shell wrapper.
5. Chord exits 143 and restores exact terminal state, but `ps` still shows
   its fake agent, now orphaned. Kill that exact PID after recording it.

Also reproduced with host binary SIGTERM at 120×40 and SIGHUP at 80×24,
and source uncaught exception/unhandled rejection at 80×24. The latter use
Bun's preload option with a four-second timer throwing/rejecting an error,
while the unresponsive turn is active. Raw output records the error/stack.
`src/ui/tui.tsx`'s forced-exit handlers restore the renderer and terminate
without awaiting session/process cleanup. React unmount starts `closeAll`
without awaiting it; normal quit awaits it before renderer exit. Responsive
monitor cases (source SIGTERM and binary SIGHUP) did reap their recorded
descendants, which narrows the failure to cleanup that needs more time. This is an unmet exit acceptance
condition in part 2, regardless of whether an older signal path also leaked.

Use the existing session/process lifecycle helpers to bound cleanup; this
QA built no component, renderer, parser or protocol library. The existing
ACP SDK, OpenTUI, Vim, clipboard and editor integrations were exercised.

## Evidence and scope

- `matrices/<build>-<width>-m4|m5|proposal`: CHD-299's named steps.
- `matrices/<build>-<width>-m3|rebound|osc9|osc777|vim-extra|m3-other`:
  CHD-300's named steps, with text/ANSI captures and raw notification bytes.
- `m12/<build>-<width>-m12|window`: M1/M2 and saved-window steps.
- `exits/<case>`: exact before/after termios, PID ownership, final flags,
  result JSON and gzip-compressed unedited raw terminal output.
- `headless`: stdout/stderr for each runtime and policy.
- `verification.json`: binary hash, counts, restoration/cleanup results.

Production-binary injected crashes were not exercised; source crash proof
is explicit above. Desktop notification delivery, physical kitty
shift+Enter, and CHD-163's existing fixture gaps remain unjudged. CHD-300's
excluded splash/forms/rewind/Linux display rows remain outside its repeated
matrix. Final `bun run check` on the staged evidence tree also passed: 51 lint tests
and 1,489 tests, zero failures (504.77 seconds). Final staged privacy tests
passed 7/7. The whitespace audit permits blank EOF rows to retain terminal
capture dimensions. The final evidence contains 906 paired screens and 94
cleanup records.

This failed pass does not authorize a fast-forward. CHD-331 must be
fixed and forced-exit cleanup proved before the whole acceptance can pass.
