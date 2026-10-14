# CHD-86 look: image paste

Taken from 2f2651a against the fake agent in tmux, with a 32×32 PNG in the
macOS clipboard and then with an emptied clipboard. Blank rows are trimmed.

## 120x40, prompt with an image and text

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ › what is [Image #1] this?                                                                                           │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
                                                                                   Fake Large with a 1M context window
```

## 120x40, sent

```
 › what is [Image #1] this?
 ⏺ Received an image: image/png, 829 bytes
   Hello, world. This reply came in chunks.
```

## 120x40, empty clipboard (the message is in the theme's warning colour, #ffc107 dark)

```
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  No image in the clipboard                                     Fake Large with a 1M context window · 99% context left
```

## 120x40, backspace over a placeholder: the defect

After `[Image #2] ` was pasted, one backspace took the trailing space and two
more left the half placeholder `[Image #` in the draft as plain text.

```
│ › [Image #                                                                                                           │
```

Claude Code 120x40, same clipboard, for reference: `what is [Image #1] this?`, then
ctrl+w and two backspaces. The second backspace removes `[Image #1]` whole and
leaves `❯ what is`. Its placeholder has no colour, the same as chord's.

## 80x24, two images in one prompt, sent

```
 › [Image #3] describe [Image #4] in one word

 ⏺ Received an image: image/png, 829 bytes

   Received an image: image/png, 829 bytes

   Hello, world. This reply came in chunks.

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts       Fake Large with a 1M context window · 99% context left
```

## 80x24, a pasted quoted path that wraps

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ › [Image #5] and a long line of words that should wrap past the edge of the  │
│   box at eighty                                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
```

## 80x24, empty clipboard

```
╰──────────────────────────────────────────────────────────────────────────────╯
  No image in the clipboard     Fake Large with a 1M context window · 99% left
```

## 80x24, ? panel

`ctrl + v to paste an image` sits under `ctrl + g to edit in $EDITOR`. With the
panel open, one transcript row stays above the box.

## Re-look at bdc81eb (atomic placeholder), fake agent, 32×32 PNG in the clipboard

120x40, `what is [Image #1] this?`, ←×6, backspace, backspace, `X`:

```
│ › what is [Image #1] this?
│ › what is  this?
│ › what is this?
│ › what isX this?
```

ctrl+w with the cursor right after `]` (trailing space removed first) takes it whole:

```
│ › cut [Image #5]
│ › cut
```

ctrl+w straight after the paste, while its trailing space is still there, does not:

```
│ › cut [Image #3]
│ › cut [Image
```

Enter then sends the half label, with no image:

```
 › cut [Image
 ⏺ Hello, world. This reply came in chunks.
```

Claude Code 120x40, the same clipboard, no prompt sent: `cut `, ctrl+v, ctrl+w:

```
❯ cut [Image #1]
❯ cut
```

Forward delete in tmux (`\e[3~`) deletes the character before the cursor even
in plain text (`abc d|ef` → `abc ef`), so "delete before `[`" cannot be seen
here; this does not come from CHD-86.

80x24, backspace after `]` and a send:

```
│ › one [Image #7] two                                                         │
│ › one  two                                                                   │
 › describe [Image #9] briefly
 ⏺ Received an image: image/png, 1117 bytes
   Hello, world. This reply came in chunks.
```

## Re-look at 86d620d (ctrl+w after a paste), fake agent, 1×1 PNG in the clipboard

120x40, `cut `, ctrl+v, ctrl+w, `x`, Enter:

```
│ › cut [Image #1]
│ › cut
│ › cut x
 › cut x
 ⏺ Hello, world. This reply came in chunks.
```

ctrl+w with the cursor before `now` (after the placeholder's trailing space), then ctrl+e and `Q`:

```
│ › see [Image #5] now
│ › see now
│ › see nowQ
```

Backspace after `]` still takes it whole; Enter sends no image:

```
│ › keep [Image #6] it
│ › keep  it
 › keep  it
 ⏺ Hello, world. This reply came in chunks.
```

80x24, a cut paste, then a kept one, then the clipboard emptied and ctrl+v:

```
│ › one [Image #7]                                                             │
│ › one                                                                        │
│ › one [Image #8] kept                                                        │
 › one [Image #8] kept
 ⏺ Received an image: image/png, 73 bytes
   Hello, world. This reply came in chunks.
  No image in the clipboard     Fake Large with a 1M context window · 99% left
```
