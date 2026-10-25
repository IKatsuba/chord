# CHD-528: shortcuts scroll rules on their own rows

The design is [CHD-378's scrolling panel](../../CHD-378-steer.md).
No new screen design is introduced.

Before is origin/main `44834aa2`, captured in an isolated worktree.
After is handed-over U1 `2f5d910e`. Each PNG is the whole terminal window,
rendered from its matching `tmux capture-pane -e -p` `.ansi`; `.txt` keeps
the plain screen. Both the live screens and all PNGs were inspected.

For each `before-` and `after-` prefix:

| Suffix | Scene and position |
| --- | --- |
| `main-top-80x24` | Fresh main, panel just opened |
| `main-middle-80x24` | One Shift+Down from top: both rules |
| `main-end-80x24` | End: only the above rule |
| `main-reference-120x40` | Wide main: complete panel, no rules |
| `member-top-80x24` | Tester picked with parser, docs and two bugfix runs open; Home |
| `member-middle-80x24` | Three Shift+Down presses: both rules |
| `member-end-80x24` | End: only the above rule |
| `member-reference-120x40` | Wide member: complete panel, no rules |

The member's before top and middle reproduce the overprint. After, the
rules occupy their own rows and the adjacent shortcut rows are whole;
the end stays readable. The ordinary main views and wide references stay
readable too. Home, PageDown and PageUp were also exercised on U1, returning
to its clean member top. The screen look passes, with no findings left.

The existing fake `agentmentions` scenario supplies the roster, with
`CHORD_FAKE_TESTER_PLAYS=text` and the existing fake bugfix team installed
in the QA directory. From main, five Down presses and Enter pick tester.
No real model or agent was contacted. Captures use the dark theme with
inherited `NO_COLOR` removed and a task-local copy of the CHD-483 ANSI
renderer. No implementation or fixture files were changed by designer.

The baseline worktree and all designer tmux sessions were removed.
No light theme, wheel interaction, compile or whole-suite check was made
for this screen look; automated coverage is reported in the developer and
tester handovers.
