# CHD-481: whole-window screens

The full chord window on the fake agent, colour kept (`tmux capture-pane -e
-p`; view with `cat` in a terminal, or `less -R`). Two monitors with the
same description run, started 20 s apart through chord's own `monitor` tool
with a 1 h timeout, as in the design's case: `30-min heartbeat while the
owner is away`, running `for i in 1 2; do sleep 1; echo "heartbeat $i:
check the ship run for a stall"; sleep 1800; done` (one event each). The
fake's 200-line `long` answer above them is filler.

Files marked **mock** are a real capture of the U1 window (2) with the
background frame replaced by the design's frame, drawn in the theme's
colours; nothing in a mock is built yet, and their times are made up to
match the case (`46m`, `1h`).

| File | What it shows |
| --- | --- |
| `1-today-120x40.ansi`, `1-today-80x24.ansi` | Today (origin/main b4aed593): the background view, two rows that read the same. |
| `2-ids-120x40.ansi`, `2-ids-80x24.ansi` | U1, built (chd-481 at 59308bc0): the same list with the id in the kind, `monitor · m1`, `monitor · m2`. |
| `3-detail-mock-120x40.ansi`, `3-detail-mock-80x24.ansi` | **Mock**, U3: `enter` on `m2` opens its detail in place of the rows: description, state, start, timeout, owner, command, last batch. |
| `4-1-stays-on-end-mock-120x40.ansi`, `-80x24.ansi` | **Mock**, Q126 option 1: `m1` times out while its detail is open; the detail stays on the end (`■ timed out after 1h`, dim: a stop in its own words, CHD-482 Q85; chord's sentence) until the person leaves it; the end's message is in the transcript above. |
| `4-2-back-to-list-mock-120x40.ansi`, `-80x24.ansi` | **Mock**, Q126 option 2: the same end sends the frame back to the list, `m1` gone, the `❯` on `m2`; the end is read in the transcript line above. |
| `4-3-next-detail-mock-120x40.ansi`, `-80x24.ansi` | **Mock**, Q126 option 3: the same end steps to the next item's detail, `m2`'s, in its place. |
