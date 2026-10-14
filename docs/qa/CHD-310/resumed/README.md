# CHD-310 — resumed whole-move acceptance

**QA fails on CHD-334.** Implementation `77cf29fb` on `opentui`;
main remains at `3538862f`. CHD-331's forced-exit repair passes on this
tree. The first pass in the parent directory remains historical evidence.
No implementation changed and no live agent or model ran.

## What ran

- `bun run compile`: host macOS arm64 binary, then actual TUI startup and
  keyboard flows. `verification.json` records the binary's SHA-256.
- `bun run check`: static checks, 51 lint tests and 1,497 session/UI tests
  across 108 files, zero failures (502.83 seconds for the session/UI suite).
  The final full check on staged evidence also passes: 51 lint tests and
  1,497 tests, zero failures (505.67 seconds); staged privacy passes 7/7.
- Fresh keyboard-only tmux M1/M2 checks and CHD-299/CHD-300 M4/M5/M3
  recipes, source and host binary, each at 120×40 and 80×24. Each session
  uses scratch work, XDG config and state directories, with real terminal
  stdin. Text and Enter are separate key deliveries.
- M3's generated PNG clipboard, scripted editor, Vim motions, themes,
  terminal deltas/exit, nested subagents/permission, compaction/failure,
  MCP readback, rebound prompt/app actions, tab drafts and cross-directory
  picker. BEL, OSC 9 and OSC 777 are inspected in raw output.
- M4 lists, task work/permission/report, long-lived child chat/messages,
  close/refusal, monitor events and key stop; M5 proposal/save/show/run/stop,
  nested members/permission/folding, second run and resume without reopening.
- M1/M2 streams, markdown/code/diffs/thoughts, permissions, multiline input,
  history/search, plans, modes/models/config, slash/file completion, bash
  context, usage/status, queue return/delivery and scrolling/resize.
- Genuine saved-window resume, switching resumed tabs, `/clear`, `/new`
  and queued delivery. Source/binary headless JSON, permissions refused and
  allowed, starting mode, piped input and error exit.
- 16 ordinary exits: Ctrl+C twice, Ctrl+D, `/exit` and start-picker Esc
  in all four build/size combinations.
- 36 hung-fixture forced exits: TERM, HUP, exception, rejection, double
  exception and TERM+HUP in all four combinations; overlapping signals and
  exceptions with two live monitor groups under a hung configuration request;
  overlapping signals with two independently hung tabs. Crash injection
  uses `BUN_OPTIONS=--preload` on the production binary too, without changing
  its artifact, and is removed from the fake's environment.
- Independent raw-terminal inspection through the repository's maintained
  `@ansi-tools/parser`; exact before/after `stty -g` and `stty -a`, tmux
  flags and `ps` checks of recorded owned PIDs/process groups.
- Controlled shortcuts regression: current source versus the same source
  with only `tui.tsx` restored to `8c694102`, before the parent-resize
  subscription; then current source/binary at both sizes.

## What was seen

The requested functional flows complete, including visible fake errors,
Esc interruption/recovery, permissions, agents/teams, saved records, input
and usable resize. Headless errors exit 1 and the other checked headless
cases exit 0. **The shortcuts panel corrupts the full-screen display.**
Consequently the matrix is not a whole-move pass.

Every dedicated ordinary and forced exit restores identical `stty -g` and
`stty -a`, leaves the alternate screen, shows the cursor and disables mouse
tracking. No recorded owned PID or agent/monitor group survives. Signals
keep their expected codes; TERM+HUP exits 143 after the first signal's bounded
cleanup. Crashes print their errors/stacks and exit 1; both double-crash
callbacks fire. Hung cleanup takes about four seconds, including the two
tabs and monitor groups. No orphan needs killing. This reproves CHD-331's
repair on the final tree, including production-binary crashes.

## CHD-334 reproduction

1. Start a fresh fake-agent TUI in an isolated 120×40 tmux session, with
   scratch work/config/state directories.
2. Press `?` on an empty draft. Press Esc to dismiss it.
3. Capture the returned prompt. Send `text`, then Enter separately, and
   capture the reply.

The current bridge prints `MaxListenersExceededWarning` outside the renderer:
11 `resize` listeners were added to one `BoxRenderable2`, whose default
limit is 10. Warning fragments remain across the prompt and transcript
after dismissal and the next reply. Source and binary each emit three
warning writes at 120×40 and two at 80×24. The control emits zero and stays
clean. Both controls restore the terminal and reap the fake.

`Fitted`'s new parent-resize effect in `77cf29fb` subscribes once per fitted
text. The shortcuts column has enough fitted siblings to exceed that limit.
This is a regression introduced by CHD-332's shared-bridge correction,
not a request to change the approved appearance. CHD-334 asks the engineer
to retain correct parent refitting and listener disposal without warnings
or terminal corruption, keeping the existing shrink/grow and complete
instruction regressions. No blanket suppression of process warnings is
requested.

## Evidence and scope

- `matrices/`: fresh CHD-299/300 paired text/ANSI captures, cleanup records
  and compressed raw output.
- `m12/`: M1/M2 and saved-window captures with exact terminal records.
- `exits/`: ordinary and forced exits, recorded PIDs/groups, terminal flags,
  crash stderr and compressed raw output.
- `regression/`: current four-way reproduction and pre-subscription control.
- `headless/`: stdout/stderr from each checked policy and build.
- `baseline-comparison.json`: functional markers against retained main captures.
- `verification.json`: implementation/build identity, evidence counts,
  terminal/ownership results, notification bytes and warning inventory.

The five excluded Ink direct dependencies are absent from `package.json`
and `bun.lock`; no `test.todo` remains. Original clipboard item data is
restored and its private backups are deleted. Final owned-process and tmux
audits are clean. No unrelated minor task is filed; the known role-cell cut
remains CHD-333.

Physical kitty shift+Enter (CHD-313), desktop notification delivery,
CHD-163's existing fixture gaps and CHD-300's excluded splash/forms/rewind
and Linux-display rows remain unjudged. Other-platform build evidence stays
with CHD-309; only the host binary is run here. Owner final acceptance is
not claimed. Approved appearance is left settled.

QA builds no component, renderer, parser or protocol helper. Existing fake
fixtures, ACP/OpenTUI, Vim, clipboard, editor and ANSI-parser integrations
and earlier QA drivers are reused; no new implementation library trial
applies. CHD-334 blocks lead closure and main's fast-forward. Nothing is
pushed, published or opened as a PR.
