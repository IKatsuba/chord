# CHD-483: the final screens

The whole chord window on the fake agent, from the built code (chd-483 at
98331c3d), in the four themes: `dark`, `light`, and the terminal's own 16
colours, `dark-ansi` and `light-ansi`. Each is a `.ansi` file with its
colours (`cat` it in a terminal, or `less -R`) and a `.txt` beside it.

The scene, as in the design's captures: main idle; the team `bugfix`, its
lead and `coder` idle with a new reply, `tester` working; `parser` idle with
a new reply; `docs` asking a permission; `parser 2` exited (prompts `team`,
`agents`, `agentexit`, `CHORD_FAKE_LEAD_OPENS=tester,coder`,
`CHORD_FAKE_TESTER_PLAYS=costwait`).

What V1 changes, to look for: `✻ working …` in the theme's accent with dim
(green in the two 16-colour themes, whose accent is the warning's yellow),
`✓ new reply` dim instead of green; `● permission` and `✗ exited` keep
their full colour.

| File | What it shows |
| --- | --- |
| `folded-<theme>-120x40` | The list under the prompt with main picked: the team folded into its row, `✻ tester: working 34s  ✓ new reply`, then `parser`'s new reply, `docs`'s permission, `parser 2` exited. |
| `folded-<theme>-80x24` | The same at 80×24, where the list's limit folds `docs` and `parser 2` into `… +2 more`; the status line names the permission. |
| `docs-picked-<theme>-80x24` | `↓` into the list onto `docs`, so its `● permission` row shows at 80×24 beside the folded team's `✻ tester: working`. |

`<theme>` is `dark`, `light`, `dark-ansi` or `light-ansi`. The 120×40 and
80×24 sets were taken in separate sessions, so their times differ.
