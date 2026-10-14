# CHD-312: part 8b against part 8a

Every screen this task moved, captured with `tmux capture-pane` on the fake
agent from part 8a (`f02b8568`) and from part 8b, the same keys each side,
at 120×40 and 80×24: the prompt, `?`, `/`, `@`, a permission, a form, a
link, `/model`, `/config`, `/theme`, `/mcp`, `/resume`, `/team`, ctrl+r, the
queue, two tabs and the start picker. Text and colours (`capture-pane -e`)
were compared; the files here are those that differ, and a few that do
not, for the look.

What differs:

- `mcp-80x24`: the sentence under the title wraps before `whether`. It is
  77 columns in a 76-column row; part 8a drew it to the border, over the
  padding.
- `team-80x24`: the user's teams directory breaks after a `/`, as
  OpenTUI's word wrap does.
- The working line's spinner frame (`permission-*`, `form-80x24`, the link)
  and `/mcp`'s loopback port, which differ from run to run.

Unchanged: `idle-80x24` and every other screen, in text and colour.

## The designer's look, below 80 columns

The same keys on part 8a and 8b, narrower than the 80×24 floor, to reach
the rows that are cut. Everything else checked there was identical: nine
tabs at 80 and 60 columns, the form at 48, scrolling with pgup, home and
end at 120×40 and 80×24.

- `tabs-44x24`: nine tabs, the ninth active. Part 8a cut the strip at its
  end with `…` and so hid the active tab; part 8b cuts the middle with
  `...` (`3 ...  7   8    9 fake`) and keeps it. A better result.
- `mcpask-48x24`: the MCP permission's `command:` argument. OpenTUI's word
  wrap breaks at the hyphen inside `--line-buffered` (`grep --line-` /
  `buffered`); part 8a kept the flag whole on the next row. This is option
  C's wrap as it is, but a shell command split inside a flag misreads.
