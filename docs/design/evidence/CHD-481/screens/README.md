# CHD-481: whole-window screens

The full chord window on the fake agent, colour kept (`tmux capture-pane -e
-p`; view with `cat` in a terminal, or `less -R`), at 120×40 and 80×24. Two
monitors with the same description run, started 20 s apart through chord's
own `monitor` tool, as in the owner's case: `30-min heartbeat while the
owner is away`, running `for i in 1 2; do sleep 1; echo "heartbeat $i:
check the ship run for a stall"; sleep 1800; done` (one event each). `m1`
has a 1 h timeout; `m2` a 45 s one, so that its timeout is seen. The fake's
200-line `long` answer above them is filler.

The finals are taken from the built code, chd-481 at 82a89abf. The mocks
drawn before it was built are in this folder's history (4a2ef186).

| File | What it shows |
| --- | --- |
| `before-120x40.ansi`, `before-80x24.ansi` | Before CHD-481 (origin/main b4aed593): the background view, two rows that read the same. |
| `1-list-ids-120x40.ansi`, `1-list-ids-80x24.ansi` | The list: each row's kind names its id, `monitor · m1`, `monitor · m2`; the hint offers `Enter for details`. |
| `2-detail-120x40.ansi`, `2-detail-80x24.ansi` | `enter` on `m2`: its detail in place of the rows: description, state, start, timeout, owner, the command, the last batch and how long ago it came. |
| `3-detail-timed-out-120x40.ansi`, `3-detail-timed-out-80x24.ansi` | The same detail when `m2` reaches its timeout while open (Q126): it stays, titled `· ended`, `■ timed out after 45s` dim as a stop (CHD-482's Q85, not an error), chord's end sentence under the batch, no `x to stop`. |
