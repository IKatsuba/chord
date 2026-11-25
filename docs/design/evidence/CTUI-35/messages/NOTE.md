# Messages and chord's tool rows: unit 24, commits 3ed64637 and 053cce17

The port's screens are its tests' (`messages_window_test`,
`message_colours_window_test`, `tools/chord_test`), printed at their end
at 120x40 and 80x24 (`port-*.txt`; fake-clock ages shown as `…`). The
original was run live at 80x24 (`agentsquiet`, then parser picked) and
compared on screen; the port cannot open the fake's children by hand at
this commit.

Equal to the original: `⏺ Open(parser) · fake · fake-small` with its
prompt under `⎿`; `← from @parser · fake` and `→ to @main` rows, the
text whole under `⎿`; the child's line on top. The arrow and name in the
other agent's colour follow the original (`useAgentColour`), not the
design's §3.3; main, chord and the queue stay uncoloured, as there.
