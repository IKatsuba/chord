# The agents list and the child line: unit 19, commit 30b87f5c

Nothing mounts the list in the window at this commit, so the port's
screens come from a scratch app (not in the repository) that mounts
`ChildLine` on top and `AgentsList` at the bottom of a real terminal with
the rows of the captured moment (main and parser idle, docs asking), on
the live clock, palette `paletteOf('dark', true)`. The original is
`CHORD_FAKE_CHILD_RUNTIME=fake bun dev chord --fake --qa agents` in
`../chord`, then `agentsquiet`.

- `*-120x40-asking.*`, `*-80x24-asking.*`: the prompt holding the keys.
- `*-80x24-focused.*`: ↓, the list holding the keys, main picked.
- `*-80x24-docs.*`: ↓ ↓ more, docs picked, its marks seen.
- `orig-120x40-parser-child-line.*`: parser picked, the child line at the
  top of its transcript; the port's line is on row 1 of each port capture.

Text and styles match cell for cell: names in the agents' colours, the
picked one bold, main uncoloured, details dim, `● permission` in the
warning colour, `❯` in the permission colour, effort and model giving way
at 80 columns, the clock ticking. The original's rows also paint the
gutter's blank cells in the permission colour, which shows nothing. The
child line is one column in in the original, inside the transcript's
margin; that margin is the window's (unit 20 on). Header paths are
relabelled `<project>`.
