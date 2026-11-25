# The chat switch and the named top: unit 21, commit 84c19985

The port cannot open the fake's children by hand at this commit, so its
screens are the tests' (`test/ui/app/chat_switch_test.dart`,
`test/ui/prompt/named_top_test.dart`), printed at the moment they assert.
The original's are `../agents-list/orig-120x40-parser-child-line.*`
(parser picked after `agentsquiet`).

- `port-child-picked-120x40-80x24.txt`: parser in front: the child line
  one column in, `╭─ parser ─…╮` on the prompt. Equal to the original's
  first row and prompt top, text and styles (the original's `.ansi`: the
  corner and fill in parser's colour, ` parser` bold, the space after it
  not, the whole border in the colour).
- `port-named-top-and-news.txt`: the named top alone at both sizes, and
  `── ↓ new output · N lines below · end to jump to the bottom ──` on a
  child picked again after news while hidden.

The status hint and the list's `❯` with parser picked differ from the
original's capture because the list's keys are unit 23, not this one.
Neither of developer's departures is one from the original: the child
line is not selectable (`selectable: false` there), and in bash mode the
name takes the edge's colour, as the original's `NamedTop`.
