# CHD-310 — whole-move acceptance after CHD-334

**QA passes the fake-only host acceptance.** Tested clean `opentui` at
`bdb55c16`, including repair `37e3eac9`. Main stays at `3538862f` for the
lead to fast-forward. The failed passes in the parent directories remain
historical evidence; CHD-331 and CHD-334 are now repaired.

## What ran

- `bun run compile`, then the actual host macOS arm64 binary in tmux.
  `verification.json` records its SHA-256.
- Foreground `bun run check`: static checks, 51 lint tests and 1,498 tests
  across 108 files, zero failures, 17,874 assertions, 504.96 seconds for
  the session/UI suite. The full gate is repeated on the staged evidence
  before commit; its result is reported on the task.
- Fresh CHD-299 M4/M5 and CHD-300 M3 keyboard recipes, plus all M1/M2
  rows, source and host binary at 120×40 and 80×24. Every session has
  isolated scratch work/config/state and a neutral repository symlink.
  Literal text and Enter are separate deliveries; every in-app action
  uses keys. Each main recipe resizes to the other size and back.
- Genuine saved-window resume, switching resumed tabs, `/clear`, `/new`
  and queued delivery; source/binary headless JSON, permission refusal
  and allowance, starting mode, piped context and error exits.
- 16 ordinary exits: Ctrl+C twice, Ctrl+D, `/exit` and start-picker Esc
  in every build/size combination.
- 36 forced exits: TERM, HUP, injected exception/rejection/double crash
  and TERM+HUP in every combination, plus overlapping signals and crashes
  with two monitor groups under a hung configuration request, and signals
  with two independently hung tabs. Production-binary injection uses
  `BUN_OPTIONS=--preload` without changing the binary; the fake does not
  inherit it.
- Six shortcuts open/dismiss cycles per combination, resize while open,
  then another reply. The full M1/M2 and rebound-key recipes also reach
  shortcuts. CHD-334's separate committed proof retains listener lifecycle
  and complete-instruction shrink/grow acceptance.
- Maintained `@ansi-tools/parser` audit of 100 raw terminal logs, exact
  before/after termios, tmux modes, recorded PIDs/groups and a final global
  owned-process audit. Compared functional markers with main's 16 retained
  M3/M4/M5/proposal capture sets.

## What was seen

The requested functional flows complete at both sizes from both builds:
streaming, markdown/code/diffs/thoughts, permission choices, multiline input,
history/search, plans, modes/models/config, commands/files/bash context,
usage/status, queues and scroll/resize; PNG clipboard receipt, editor return,
Vim, themes, terminal deltas/exit, nested subagent permission and compaction;
tasks, messages, child chat/close, monitors, proposals/save/show/run/stop,
members and teams on resume. Agent errors remain visible; Esc interrupts,
and the next prompt works. Headless errors exit 1; the other checked cases
exit 0. Every M1/M2 combination passes 23 functional markers.

CHD-334 holds: zero `MaxListenersExceededWarning` in all 100 raw logs,
clean dismissed/reply screens and continued input after repeated panel
resize. No warning suppression was introduced by QA.

CHD-331 holds: every dedicated ordinary/forced exit restores identical
`stty -g` and `stty -a`, leaves the alternate screen, restores the cursor
and disables mouse tracking. All 108 cleanup records pass. Crashes print
their stacks and exit 1; overlapping signals preserve TERM's 143. Hung
cleanup remains bounded at about four seconds, including monitor groups
and two tabs. No owned orphan needs killing.

All 148 recorded probe PIDs and 56 process groups have no survivor; the
global audit includes second-tab/child agents. Both isolated tmux servers
have no sessions. Raw teardown also disables mouse and bracketed-paste
modes. Original clipboard item data is restored exactly and private backups
are deleted. No `test.todo` or excluded Ink direct dependency remains.

## Evidence and limits

There are 1,046 paired text/ANSI screens. `matrices/` follows CHD-299/300's
evidence names; `m12/` contains M1/M2 and saved-window supplements;
`shortcuts/` contains repeated panel/resize/reply cases; `exits/` contains
ordinary and forced exits, crash stderr and termios records. Raw output is
gzip-compressed without editing. `verification.json`,
`functional-markers.json`, `baseline-comparison.json` and
`process-audit.json` hold the audit results.

Physical kitty shift+Enter (CHD-313), owner final acceptance, desktop
notification delivery, CHD-163's existing fixture gaps and CHD-300's
excluded splash/forms/rewind/Linux-display rows remain unjudged. Other
platform execution is not claimed; release-target build evidence remains
CHD-309. Approved appearance remains settled. Known role-cell truncation
remains CHD-333; no new unrelated finding/task was filed.

QA built no component, renderer, parser or protocol helper. Existing fake
fixtures, ACP/OpenTUI, Vim, clipboard, editor, maintained ANSI parser and
earlier keyboard drivers were reused; no new implementation library trial
applies. No implementation edits, live agent/model, merge, push, publish or
PR. Ready for chd-lead's closure and main fast-forward under the task's plan.
