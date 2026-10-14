# CHD-99 independent QA

Implementation under test: `846d5b7`, with the incoming CHD-98 working-tree
changes preserved. Source at 120×40; freshly compiled binary at 80×24.
All sessions used the fixture fake agent, an isolated tmux server, scratch
XDG config/state and a neutral working directory. Input was keys only;
literal text and Enter were separate sends. No live agent was used.

Ran `deno task check`, `deno task compile`, keyboard acceptance below,
`git diff --check`, a private-path scan of this evidence, terminal-state
readback and `/bin/ps` cleanup verification.

## Keyboard acceptance

- `/vim` saves `editorMode: vim`. A compiled restart reads it and starts in
  insert mode. Toggling off saves `normal`; another restart has no mode mark.
- Both sizes: type `alpha beta gamma delta epsilon`, Esc, `0dw`, `02w`,
  Enter. `dw` leaves `beta gamma delta epsilon`; counted motion highlights
  the `d` of `delta` in the ANSI capture. Enter sends the whole draft and
  returns to insert. Session record readback confirms the prompt and fake reply.
- Resize 80×24 → 120×40 → 80×24 preserves the draft, mode and cursor.
- On an empty normal-mode box, `?` opens the complete panel at 80×24,
  including `/vim for vim mode`. Esc closes it and keeps normal mode.
- `slow`: first Esc changes insert to normal and leaves the turn running;
  second Esc displays `Interrupted by user`. `error` displays the fake
  agent's failure at both sizes.
- `/model` closes on the first Esc, retaining insert mode. A permission's
  first Esc rejects it, reports `Permission: deny`, and retains insert.
- Held images loaded from a scratch PNG become `[Image #1]` and
  `[Image #2]`. Esc, `03lx` or `03ldw` removes the whole placeholder.
- `one\n\ntwo`, cursor on the blank line, `ddp` → `one\ntwo\n`.
  `\none\ntwo`, cursor on the first line, `2ddp` → `two\n\none`.
  `one\n`, cursor on the last line, `ddP` → `\none`.
- `a\nb\nc`, cursor on `b`, `2ddp` restores the three lines. `2cc`
  and `cj` retain a blank replacement line; typing `z` produces `a\nz`.
  Esc then `u` restores all three original lines.
- Ctrl+D and two Ctrl+C quit paths exit zero. All three sessions restore
  exactly the original `stty -g`; tmux reports alternate screen off and
  cursor on. Raw output includes the screen-leave and cursor-show escapes.
  `receipts.json` records these checks without machine paths.

Text and ANSI files are paired; ANSI retains the standout cursor. Quit
screen dumps are excluded because the resume command embeds the fixture's
absolute source path. Cleanup is recorded by the public receipts instead.

Library exercised: `@replit/codemirror-vim-core` 0.1.0, in source and compiled
TUI. The engineer's trials and passed-over DOM/other-editor candidates remain
recorded in `docs/decisions.md`. QA added no editor, parser or dependency.

Existing follow-ups carried forward: CHD-103 spinner hint, CHD-104 two trailing
blank lines, CHD-105 cleanup comment. No new finding was filed by QA.

## Results

`deno task check`: 672 tests passed, 20 steps, zero failures (6m9s).
`deno task compile`: succeeded; the fresh binary started and passed the
80×24 keyboard acceptance. The staged-evidence privacy test passed 7/7;
`git diff --check`, staged diff check and the private-path scan passed.
Capture assertions verified both sizes' marks, counted cursor, delivery,
errors and cancellation, plus permission ownership and atomic image cuts.
Final `/bin/ps` readback found no fixture fake agent or QA runner remaining.
The incoming tracked diff was compared byte for byte and preserved.
