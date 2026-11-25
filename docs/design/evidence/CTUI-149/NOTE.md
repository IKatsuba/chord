# CTUI-149 captures

`dart run bin/chord.dart --help` at commit 2c46c235, captured in tmux at
120x40 and 80x24; the help's own lines only, without the shell prompt.

`-r, --resume [id]` now starts its words in the same column as every other
option, as the original's help lays out `-r, --resume [id:string]`
(../chord src/cli.ts, read, not run). At 80x24 the long lines are wrapped by
the terminal, not by chord; the help itself does not depend on the width.
