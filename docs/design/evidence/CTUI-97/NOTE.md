# CTUI-97: teams picker highlight after a tiny resize

Verdict: the original shares the slip, at 120x40 and at 80x24. After moving
to the broken `triage` and resizing through 1x1, 0x1 (tmux clamps it to 1x1),
1x1 and 30x12, back to the starting size, the highlight is on `1. bugfix`
while the hint still says "fix triage", and Enter puts `/team run bugfix` in
the prompt. The port draws the same in every step.

Why, in `../chord/src/ui/pickers/Pickers.tsx`:

- 603-605: the picker keeps `highlighted` as its own state, fed by
  `PickerList`'s `onMove` (647), and the hint reads it (660-668).
- 615-616 and 642-655: at a size with no row for the list `listed` is 0, so
  `PickerList` is unmounted, and with it its own cursor. Mounted again, it
  starts at its first row, while `highlighted` still names `triage`; Enter
  goes by `PickerList`'s cursor and picks `bugfix`.

## How captured

tmux sessions of 120x40 and 80x24, `capture-pane -p`, text sent with
`send-keys -l` and Enter in its own call; sizes changed with
`tmux resize-window`.

- Original: `cd ../chord && XDG_CONFIG_HOME=<config> bun dev chord --fake
  --qa <name>` (`--qa` runs in a fresh directory with its own state beside
  it; `XDG_CONFIG_HOME` is a fresh empty directory, so no user teams).
- Port: `dart run example/chord/tool/dev.dart chord --fake --qa <name>`
  (fresh directory, state and configuration).
- In both, once started, the project's `.chord/teams/` got the port's
  `example/chord/test/fixtures/teams/fake/bugfix.md` and a `triage.md` holding
  `# no frontmatter`, as in `team_command_window_test.dart`. Then `/team`,
  Enter, Down.

Files, per side (`original-` or `port-`) and size:

- `-1-triage.txt`: `triage` highlighted, hint names it.
- `-2a-at-30x12.txt`: at 30x12, the list gone (no row for it).
- `-2-after-resize.txt`: back at the starting size: highlight on `bugfix`,
  hint still names triage.
- `-3-enter.txt`: after Enter: `/team run bugfix`.

At 30x12 the two sides wrap the user-teams line differently only because
their configuration paths differ in length; nothing else differs.

## Relabelling

The capture directory is shown as `<project>`, the configuration directory
as `<config>`; where the real path wrapped onto a second row, the leftover
fragment was cut down to `chord/teams.`. Rows holding these labels no longer
line up with the frame's right border.
