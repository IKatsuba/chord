# Note on the captured outputs

- The files under `results/` were written by `run.ts` from real runs and
  then relabelled: the scratch directory is `<scratch>`, the chord checkout
  is `../chord`, this directory is `.`, and any home directory, user name,
  host name or system temporary path would be `<home>`, `<user>`, `<host>`
  or `<scratch>`. Bearer tokens are `<token-main>` and `<token-task>`,
  MCP session ids `<session-n>` in order of appearance, other UUIDs
  `<uuid-n>`.
- `run.ts` deletes `dart/.dart_tool/` after a run, because pub writes
  absolute pub-cache paths into it; `dart pub get` in `dart/` makes it again.
