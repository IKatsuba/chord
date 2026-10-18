# CHD-432 U1 captures

Taken on e11a4a1b with `bun dev chord --fake`, on a scratch directory.

| File | Scenario | What it shows |
| --- | --- | --- |
| `running-120x40.txt` | `claudesubagents`, before the permission | three ended rows beside one asking |
| `folded-120x40.txt`, `.ansi` | `claudesubagents`, after `1` | `4 agents ended · 1 failed, 1 untracked, 1 cancelled`, red marker |
| `expanded-120x40.txt`, `.ansi` | the same, ctrl+o | `API Error: 529 Overloaded` under Failed (error role), Untracked's note (dim) |
| `folded-80x24.txt` | `claudesubagents`, then `subagentupdate` | the group at 80 columns; `Ended (1 tool use · 0s)` |
| `expanded-80x24.txt` | the same, ctrl+o | Ended's note: "The agent did not say how it ended." |

Known, under Q41 and not U1's: a group row that is not the last and ended
before the first one draws `│   ⎿` one column right of `│  ⎿`, with its
body shifted too, folded and in ctrl+o. It is an OpenTUI 0.6.0 gap (a
removed `paddingLeft` does not reset), on main before U1.
