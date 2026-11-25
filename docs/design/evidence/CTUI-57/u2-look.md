# U2: the port's wrap-ansi sites, looked at

Handed source: `345e7c4`, run from a clean archive of that commit (the shared tree held uncommitted work of the next unit), beside the original (`../chord`, v0.71.0), isolated `XDG_CONFIG_HOME` and `XDG_STATE_HOME`.

The look passes.

- `u2-agents-{o,p}-{120x40,80x24}.txt`: `chord agents`, whole scrollback. Identical to the original at both sizes, the 80-column command column wrapped as wrap-ansi `hard` wraps it (and the terminal's own wrap of the original's over-wide rows, reproduced).
- `u2-failed-{o,p}-{120x40,80x24}`: the fake's `alias` start failure. The failure rows are identical at both sizes (`…session/new requires` / `` `agentAlias` (alias of a configured [agents.<alias>] entry) `` at 80x24). The header differs only by the version, `· /help` and the working directory, all old.
- `u2-window-p-{120x40,80x24}.txt`: the CTUI-29 settings warning, from this commit; identical to `u1-window-o-*` but for the version and `· /help`.
- `u2-resume-p-{120x40,80x24}`: `tool/resume.dart --many`. The hanging titles wrap at spaces under their column; checked against wrap-ansi 10.0.2 under bun with `hard, trim` at the title's room: `Saved session 2 · 界😀 with a long title and` / `an_unbroken_title_tail`, `…descriptive title` / `across wrapped lines.`, as drawn.
- `u2-crash-p-*`, `u2-permission-p-*`: the fixtures' rows fit; nothing wraps and nothing changed from before.

Not done by decision of the lead: `permission.dart:152` diff rows stay `keepSpaces` (a new task goes to main), and `permission_prompt.dart:62` stays on U1's rule.
