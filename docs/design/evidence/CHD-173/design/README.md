# CHD-173 design look, second pass

Built at `5e8fa93`. Source run in tmux, temporary HOME, XDG and DENO state
under `/tmp` (rewritten to `/tmp/chd173d` here), agents `fake` and `fake2`
both on `tests/fixtures/fake_agent/main.ts`.

Three tabs from `proj` (fake, fake, fake2), quit with tab 3 in front:
`Resume this window with:` / `chord --resume w-…`. Both fake tabs' session
records deleted, the window opened again.

- `80-missing-two.txt`, `120-missing-two.txt`: the plural note,
  `Not reopened: 2 tabs whose records are gone (fake 770f57f5, fake b5285ea8)`,
  dim, whole at 80 (the model name gives way, as status notes do) and beside
  the model name at 120. The one tab left opens with no tab strip.

The one-missing case is the engineer's `build/*-missing` captures.
