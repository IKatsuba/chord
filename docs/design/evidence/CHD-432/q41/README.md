# CHD-432 Q41 captures

Taken on 1f0abe7f with `bun dev chord --fake`, on a scratch directory,
scenario `claudesubagents`.

| File | What it shows |
| --- | --- |
| `before-sibling-120x40.txt` | two rows; reviewer is last, `└─` with `⎿` under it |
| `after-sibling-120x40.txt` | four rows; reviewer and tester now `├─`, `│  ⎿` in the same column as explorer's |
| `before-sibling-80x24.txt` | three rows; tester is last |
| `after-sibling-80x24.txt` | the watcher arrives; tester's `│  ⎿` lines up with the rows above |
| `folded-120x40.txt`, `.ansi`, `folded-80x24.txt`, `.ansi` | after `1`: Done, Failed, Cancelled all read `│  ⎿`, none a column right |
| `expanded-120x40.txt`, `.ansi`, `expanded-80x24.txt`, `.ansi` | the same, ctrl+o: each body (prompt, calls, `API Error: 529 Overloaded`) sits under its `⎿` |

On e11a4a1b (see `../u1/README.md`) Failed and Cancelled drew `│   ⎿`,
one column right, with their bodies shifted too. Fixed.
