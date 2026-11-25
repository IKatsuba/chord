# CTUI-117 evidence

## CTUI-91: the capture directory in the header

Captured live in tmux at 120x40 and 80x24, with the port run as
`dart run example/chord/tool/dev.dart chord --qa ctui91 --fake` at commit
0fdb30bb and the original run as `bun dev chord --qa ctui91 --fake` in ../chord.

`<qa-dir>` replaces the capture directory's path in every file, so that no
machine path is written down. On screen both programs showed that path exactly
as dev passes it with -C: the temporary root as given, not the
symlink-resolved form that the port drew before the fix. Apart from the
version number, which differs everywhere, the port's header matches the
original's line for line.

## CTUI-116: window reports name the shown agent's runtime

`ctui116-status-main-{port,original}-*.txt` show `/status` on main under each
program's dev route with `--qa ctui116 --fake`, captured live at commit
81ad82a6 and relabelled the same way (`<qa-dir>`, `<session-id>`). The two
match apart from the version number.

None of the original's fake routes can safely open a child on a runtime other
than main's. The visible change is therefore shown in the port's agent-free
fixture, `dart run example/chord/tool/children.dart --codex` (commit
5b5f4195), whose children carry the runtime name `codex` and start nothing:

- `ctui116-child-codex-*.txt`: parser picked; `/status` reads
  `Agent:     codex`, and `/effort` reads `codex offers no effort for .`. The
  empty model is the original's own wording in commands.ts when no model is
  reported.
- `ctui116-back-to-main-*.txt`: main picked again; `/status` reads
  `Agent:     fake`.

The parser header's `opened by main 498652h ago` comes from the fixture's
`openedAt: 0` and is not part of this unit.
