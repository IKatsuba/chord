# CHD-432 U5 captures

Taken on 1b62dfb3 with `bun dev chord --fake`, prompt `claudeexitplan`.

| File | What it shows |
| --- | --- |
| `asking-120x40.txt` | `Approve(Plan)` with the plan under it, and the permission box |
| `approved-120x40.txt`, `.ansi` | after `1`: `Exited(Plan Mode)` with only its answered permission, the plan once as a plan, accept edits on |
| `rejected-120x40.txt`, `rejected-80x24.txt` | the prompt again, after `3`: the plan stays on the call, behind `Error: `, then `Rejected Approve Plan` |

Seen and not U5's, raised with the lead:

- A rejected plan reads `Error: # Route updates by session`: chord's prefix
  for a failed call's content, on the person's own plan. What a real Claude
  sends there for a client that is not AIR is unread; the fake keeps the
  plan rather than invent a message.
- The call's title splits at its first space into `Approve(Plan)` and
  `Exited(Plan Mode)`, as any title does today.
