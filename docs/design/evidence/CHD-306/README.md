# CHD-306: the prompt restored, against main

Captures of `main` (3538862, on Ink) and of the branch `opentui` (on
OpenTUI 0.5.17), from source, on the fake agent, each in a scratch
directory of its own, at 120×40 and 80×24, by `capture.sh`. Each step is a
`.txt` (the screen as text, then the terminal cursor's cell and whether it
shows) and a `.ansi` (with its escapes):

- `search`: `say hello world` sent, then ctrl+r and `wor`.
- `normal`, `normal-bb`: vim mode, `keep this line` typed, Esc, then
  `b` twice.
- `rebound-before`, `rebound`: ctrl+k bound to `chat:submit` by the
  keybindings file; `one two` typed, ← three times, then ctrl+k.
- `gutter-end`, `gutter-start`: fourteen rows pasted, then ↑ fourteen
  times.
- `undo-typed`, `undo-1`, `undo-2`, `redo-1`: `one` and ` two`
  typed, then ctrl+z twice and ctrl+y once.
- `search-long` (the branch only, by hand): fourteen rows sent, then
  ctrl+r and `row 13`, at 80×24 and then resized to 120×40: the rows drawn
  over the textarea scroll with it, under the gutter's `↑`.
- `normal-dark`, `normal-light` (the branch only, by hand, not
  `capture.sh`): vim mode, `keep this line` typed, Esc, in a default pane
  and in one set light (`window-style fg=#112233,bg=#ddeeff`). The `.txt`'s
  last line adds the cursor's shape and colour as tmux has them, and the
  same in insert mode before the Esc.

## What differs

The text of every step is the same but for:

- the scratch directory's name in the header;
- the undo steps: `main` took `one two` back in one ctrl+z, as
  react-ink-textarea grouped edits made within a moment; the branch takes
  one key a ctrl+z, as OpenTUI's edit buffer does, which the owner took.

And in the escapes:

- none in `search`: both draw `wor` inverse (`ESC[7m`). Recaptured after
  the owner's last answer, from which the branch draws the box's rows with
  chord's own `Text` over the textarea while the search is open.
- `normal`: `main` draws the `e` under vim's cursor inverse and hides the
  terminal's cursor; the branch draws the terminal's own steady block on
  the same cell (`cursor 17,37 visible=1` at 120×40), as insert mode's is.
  The textarea sets that cursor's colour (OSC 12); it is the terminal's
  foreground as `useInk` has it, OpenTUI's guess in tmux: `#ffffff`
  in the default pane, `#000000` in the light one, in either mode, and
  `none` again once chord has quit. Recaptured after the designer's look,
  where it was white in both.
