# CHD-87 — independent QA

QA ran on `main`, HEAD `e30562f`, including the approved theme fix `212c20e`.
The designer-approved appearance was left settled. No production code changed.

## Commands and setup

- Read CLAUDE.md, README.md, FEATURES.md, decisions.md, the CHD-87 sheet,
  the task discussion, and the `chord-tui` and `quarry` skills.
- `deno task check`: 536 tests, 20 steps, zero failures. An initial sandboxed
  run failed in UI lifecycle checks; the unchanged run with process access
  passed. That failed attempt was stopped before finishing QA.
- `deno task compile`: passed. QA ran the resulting native binary against
  `tests/fixtures/fake_agent.ts`, using Deno for the fake agent.
- Deno harnesses drove only tmux keys, with literal text and Enter sent
  separately. Each run had its own scratch working directory, XDG config and
  state under `/tmp/chd87-qa`. Dedicated tmux servers were removed afterwards.
- Matrix: seven themes × dark/white window-style × 120×40/80×24. Backgrounds
  were `bg=#1e1e1e,fg=#d4d4d4` and `bg=#ffffff,fg=#000000`. `NO_COLOR` and
  `COLORFGBG` were unset for this matrix; `COLORTERM=truecolor` was set.
- Captured plain text and `capture-pane -e` for markdown, edit in accept-edits
  mode, and `/theme`. A Deno audit decoded SGR roles and checked terminal
  height, picker contents, raw terminal restoration and effective stty modes.
- `/bin/ps -ax -o pid,ppid,command` checked for remaining fake-agent and
  compiled-client processes after all runs.

## Results

All 28 matrix combinations passed. Each matrix file combines four independent
captures, separated by their capture names: markdown top, markdown bottom,
edit and picker. Both terminal sizes show the seven choices, three-row sample,
key hint, prompt and status line. Auto identifies both styled backgrounds.

The light theme's changed rows carry `#dcf5e0` / `#fde2e2`, with `#1f2328`
text, on either terminal background. Dark and daltonized themes use their
specified tints. ANSI themes have no diff background or RGB colour escapes;
changed rows use SGR 31/32 or 91/92. Markdown keyword colours, picker roles
and the accept-edits status colour match the selected theme.

Independent key-driven checks passed:

- Preview changes the window; Escape restores the original theme without
  writing. Enter saves Light and adds the dim note. The notification setting
  remains intact, restarting shows Light selected, and choosing Light again
  does not rewrite the file.
- Invalid JSON is unchanged after a save attempt; the visible error says the
  selection lasts until chord quits. A project theme is reported and ignored;
  the user's Light remains selected and the project's plan-mode setting works.
- An unanswered query falls back to dark, or light from `COLORFGBG=0;15`.
  Ordinary typing, cursor movement and insertion still work.
- Escape closes a preview, interrupts a streaming turn, and rejects a
  permission. The fake agent's intentional error is visible in the transcript.
- Ctrl+g enters vi; keyboard editing and `:wq` return `draft edited` to the
  prompt. Input remains usable after suspend/resume through the stdin proxy.
- A picker survives resizing to 80×24, and a streaming turn survives resizing
  back to 120×40 before interruption.
- Late OSC 11 replies split after ESC at 120×40 and after ESC ] at 80×24,
  each with an 11-second gap before the rest, leave exactly `hi` in the draft.
- NO_COLOR markdown, edit, seven picker previews and save: eleven captures
  contain zero foreground/background colour SGRs, including inline code.
- With a PTY client attached to tmux, Auto reports light and dark correctly
  for the two explicit window-style backgrounds. These captures are at the
  attached client's size; they do not claim background detection in every
  external terminal or through an unstyled pane.
- `-p text` in a TTY prints the fake reply without an OSC 11 query or alternate
  screen. This was checked in the raw output, not inferred from a screenshot.

Quitting by `/exit` and by two Ctrl+C presses on an empty draft restores the
shell. Every matrix run has alternate-screen state 0 and cursor flag 1 after
exit; raw output leaves the alternate screen and shows the cursor. stty modes
match before/after, excluding Darwin's PENDIN bookkeeping bit. No fake agent
or compiled client remained in the final process check. No real agent or
model was used, and no owner configuration was changed.

## Evidence and disposition

The committed captures contain only the running TUI, from scratch directories.
Shell command echoes and raw logs remain in `/tmp/chd87-qa` because they contain
local executable paths. Harnesses and complete raw/check logs are there too.
Public captures were scanned for home paths before staging.

No new findings were filed. CHD-95 already records the rare literal
Escape-then-]digits ambiguity and delayed standalone Alt+]; CHD-90 remains
separate. CHD-89's original payload leak passed QA, and CHD-70's light diff
tints passed the matrix. Lead decides their closure with CHD-87.

Library-first record was verified: is-term-dark 1.1.1 was tried and used for
background detection; chalk, Ink and existing pickers/renderers were reused.
strip-ansi and ansi-regex were tried and rejected for stateful keyboard
filtering, as recorded in decisions.md. QA added no component or dependency.

Passing QA goes to chd-lead to close. Existing untracked CHD-32/CHD-76 evidence
was left untouched. No push, publication or PR.
