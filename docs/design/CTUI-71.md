# CTUI-71: a reply's code block is framed as the original's

`Markdown` draws a fenced code block in a box with its language and its
`[copy]`/`[run]` buttons on the top border. The port's box differs from the
original's (`../chord/src/ui/transcript/markdown.ts` `codeOf`,
`../chord/src/ui/transcript/Reply.tsx:244`): the title sits one cell too
far left, the code starts two cells too far right, and the box is two cells
wider. The two cells are `Code`'s `↪` column, from the CTUI-4 decision that
code wraps instead of being cut. The original no longer cuts: it wraps a
long line by character. The owner chose to match the original exactly,
with no `↪` in a reply's code block (CTUI-71, option A). `Code` and `Diff`
keep their own wrapping.

## The call site

Nothing changes at the call site, and no name is added:

```dart
Markdown(reply, onCopyCodeBlock: copy, runCodeBlockLanguages: {'sh'})
```

The new geometry is `Markdown`'s only geometry for a framed code block.
`Markdown`'s box exists to draw chord's replies, and an option whose only
other value draws a box the original does not have would be a parameter
nobody passes. `Code` (the widget) is untouched: `softWrap` with its `↪`
column, as CTUI-4 decided for code views.

## The box

With `widest` the widest code line in cells, `label` the language:

- **Width**: `min(room, max(widest + 4, label == '' ? 0 : label + 6,
  leastWidth(label, buttons)))`, at least 1. `+ 4` is the two borders and
  one cell of padding on each side. `leastWidth` and the buttons' giving
  way are unchanged (they already match).
- **Top border**: `┌─ label ─…─[copy]─[run]─┐`. The title starts at x=2
  (corner, one `─`, then ` label `), as OpenTUI places a title one cell
  past the corner. With no label, `┌──…`.
- **Label shown** only when the box is at least `label + 6` wide, the
  original's `labelled`.
- **Code rows**: `│ ` then the code at x=2, then padding to `│` at the
  right with one cell before it. No `↪` and no mark column.
- **Wrap**: by character, as OpenTUI's `wrapMode='char'`: a row holds as
  many graphemes as fit in `width - 4` cells and the next row starts with
  the next grapheme, whatever it is. No word breaking, no spaces dropped or
  added, no indent repeated. A wide grapheme that does not fit moves whole
  to the next row. Tabs as today.
- **Highlighting** carries across a break unchanged.
- **Empty line**: one empty row.
- **Bottom border**: `└─…─┘`.
- **Selection and copy**: a copy takes the block's source, as today; a
  drag over wrapped rows gives the source text with no break added.

## What it draws

From `markdowncode` in the fake. Each is the original's capture, and the
port must draw the same.

120x40:

```text
   ┌─ typescript ─[copy]─┐
   │ x                   │
   └─────────────────────┘

   ┌─ sh ───────────────────────────────────────────────────────────────────────[copy]─[run]─┐
   │ bun dev chord --fake --qa capture && tmux capture-pane -t chord-qa -p > /tmp/screen.txt │
   │                                                                                         │
   │ echo done                                                                               │
   └─────────────────────────────────────────────────────────────────────────────────────────┘
```

80x24 (here the break happens to fall after a space):

```text
   ┌─ sh ────────────────────────────────────────────────────────[copy]─[run]─┐
   │ bun dev chord --fake --qa capture && tmux capture-pane -t chord-qa -p >  │
   │ /tmp/screen.txt                                                          │
   │                                                                          │
   │ echo done                                                                │
   └──────────────────────────────────────────────────────────────────────────┘
```

60 columns, where the cut falls inside a word:

```text
   ┌─ sh ────────────────────────────────────[copy]─[run]─┐
   │ bun dev chord --fake --qa capture && tmux capture-pa │
   │ ne -t chord-qa -p > /tmp/screen.txt                  │
   │                                                      │
   │ echo done                                            │
   └──────────────────────────────────────────────────────┘
```

In a list item the box is indented with the item's text, as today:

```text
     ┌─ sh ─[copy]─[run]─┐
     │ bun dev check     │
     └───────────────────┘
```

## States

- **Selected** (picked with the code-pick keys): the border and title in the
  selected colour, as today. Only the geometry changes.
- **Streaming** (an open fence): no buttons, as today, and the width follows
  the widest line so far.
- **Narrow**: the box never exceeds the room; buttons give way as today.
- No new keys.

## Checked when it is built

- Framework tests of the box at the three widths above, a label too long to
  show, no label, a wide grapheme at the cut, and selection over a wrapped
  row.
- `Markdown.heightOf` equal to the drawn height for every width.
- The port's `markdowncode` at 120x40 and 80x24, and the 60-column case,
  beside the original's captures in `docs/design/evidence/CTUI-71/`.
- docs/decisions.md gets the entry superseding "CTUI-4: code blocks in
  Markdown wrap, unlike chord's" for reply code blocks (the lead's).
