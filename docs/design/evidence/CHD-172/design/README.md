# CHD-172 design look

Built at `9ef194e`. Source run in tmux, temporary HOME and XDG dirs, agents
`fake` and `fake2` both on `tests/fixtures/fake_agent/main.ts`.

Three sessions recorded first: `text` on fake in `proj`, `tools` on fake in
`other`, `permission` on fake2 in `other`. Then, from a third directory,
`chord --resume <proj/fake> <other/fake> <other/fake2>`.

- `120-t1`: strip `1 fake  2 fake  3 fake2`, tab 1 inverse+bold in front,
  header and strip directory `proj`, resumed title `text`.
- `120-t2`, `120-t3`: ctrl+x 2 / ctrl+x 3. Directory follows to `other`,
  header names `fake2` on tab 3, title `tools` / `permission`.
- `80-t3`, `80-t1`: resized to 80x24; strip, directory and prompt box fit
  on one line each, nothing clipped.
- `refuse-ten.txt`: the last line of `--resume` with ten ids, exit 2.

Strip colours are bold, dim and inverse only, so they hold in a dark and a
light terminal.
