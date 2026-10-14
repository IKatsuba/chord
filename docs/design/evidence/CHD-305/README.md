# CHD-305: the flip, against main

Captures of `main` (3538862, on Ink) and of the branch `opentui` (on
OpenTUI 0.5.17), from source, on the fake agent, in one scratch directory
with the `bugfix` team saved for the project, at 120×40 and 80×24. Each step
is a `.txt` (the screen as text) and a `.ansi` (with its escapes):

1. `01-splash`: the splash, on an agent that never answers, so it holds.
2. `02-empty`: the empty window.
3. `03-markdown`: the `markdown` turn: markdown, a quote, a table and code
   blocks.
4. `04-edit`: the `edit` turn: a tool call and its diff.
5. `05-tools`: the `tools` turn: a tool call and its output.
6. `06-permission`: the `permission` turn's prompt.
7. `07-shortcuts`: `?`'s keys.
8. `08-model`: `/model`'s picker.
9. `09-team`: `/team`'s picker.
10. `11-after-quit`: the shell after ctrl+d, with the command that resumes.

`terminal-after.txt` is tmux's own flags once chord had quit (alternate
screen, each mouse mode) and whether `stty -a` was the same as before it
started.

## What differs

The text of every step is the same but for:

- the splash's mark at 120×40 and the spinner's star in `06-permission`,
  which are where their timers were when the screen was read;
- `11-after-quit`'s command, which names each tree's own path and its new
  session's id.

In the escapes:

- a border Ink drew dim is a fixed grey (`38;5;244`), as OpenTUI's
  border takes a colour and no attributes;
- the prompt's cursor is the terminal's own, where Ink drew an inverse
  cell, so tmux's text has none;
- OpenTUI writes a foreground on blank cells (`38;2;255;255;255`), which
  draws nothing.

## The ways out

`exit-paths.txt`: ctrl+c twice, ctrl+d, `/exit`, the start picker's Esc,
SIGTERM, SIGHUP, an uncaught exception and an unhandled rejection (the last
two from a module preloaded into chord that throws, or rejects, four
seconds in). Each one leaves `stty -a` as it was and no alternate screen or
mouse mode on; the errors are on stderr with their stack and chord exits 1.
