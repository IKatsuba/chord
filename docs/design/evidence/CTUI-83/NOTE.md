# CTUI-83 U6 captures

Designer's look at U6 (commit 31786f37): x on an agent item in the
background view, beside the original.

Each `original-<size>-<state>.txt` is `../chord` (`bun dev chord --fake`),
each `port-<size>-<state>.txt` is the port
(`dart run example/chord/tool/dev.dart chord --fake`), at 120x40 and 80x24,
after the fake prompt named in the state: `background` (claudebackground),
`slowstop` (claudeslowstop), `nostop` (claudenostop), `waiting`
(claudewaiting), `subagents` (claudesubagents, answered 1).

The header's directory line is relabelled `<../chord>` and
`<port checkout>`. Apart from that, the version and running timers (one
second apart where the two were captured a moment apart), each pair is
the same text. The `.ansi` pair keeps colour for the waiting row and the
summary line; it differs only in the foreground set on blank cells.

`80x24-subagents-asking` is the clipped tree with an agent asking: the
tree's header and first rows are off screen, the last tree row, the
request and the summary line stay.
