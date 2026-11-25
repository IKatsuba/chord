# CTUI-163: cmd+←/→ go to the shown row's start or end

The original's prompt is OpenTUI's textarea. There cmd+← and cmd+→
(`super+left`, `super+right`) are `visual-line-home` and `visual-line-end`:
the start and end of the row the cursor is drawn on, wrapped or not
(`../chord/docs/guide.md:259-262`). ctrl+a and ctrl+e are `line-home` and
`line-end`, the logical line. The port's `TextArea` binds both pairs to the
logical line.

## What the original does

Captured in `../chord` with `bun dev chord --fake`, the keys sent as kitty
sequences, and a character typed after each move to show where the cursor
went: `evidence/CTUI-163/original-80x24.txt` and `original-120x40.txt`. At
80x24 the prompt row is 74 cells, wrapped by character:

```text
# up, then super+left, then '[' typed: lands at the shown row's start
│ › one two three four five six seven eight nine ten eleven twelve thirteen fo │
│   [urteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twen │

# super+right, then ']' typed: lands before the row's last character
│   [urteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twe] │
│   nty-two twenty-three twenty-four twenty-five                               │

# super+right again, from the wrap boundary: that next row's end
│   nty-two twenty-three twenty-four twenty-five}                              │

# ctrl+a, then '^' typed: the logical line's start
│ › ^one two three four five six seven eight nine ten eleven twelve thirteen f │
```

So:

1. **Start** is the first grapheme of the row the cursor is drawn on.
2. **End** of a row its line goes on from is *before* the row's last
   grapheme: the offset after it is the next row's start, where the cursor
   would be drawn on the next row. End of a line's last row is the line's
   end.
3. **At a wrap boundary** the cursor is drawn at the next row's start, and
   that is the row it moves in.
4. A second press does nothing more: the cursor stays on its row.

alt+a and alt+e are bound to the same actions in OpenTUI's defaults, but
neither moved in the original's prompt (sent as `ESC a` and as kitty
`CSI 97;3u`); the guide does not name them. They stay out.

## The framework

In `packages/chord_tui/lib/src/foundation/text_editing.dart`, on
`TextAreaController`, beside `moveUp` and `moveDown`, which already work on
the same `TextAreaLayout`:

```dart
/// Moves the cursor to the start of the visual row it is drawn on in
/// [layout]; a cursor at a wrap boundary is on the row after it.
void moveToRowStart(TextAreaLayout layout);

/// Moves the cursor to the end of the visual row it is drawn on in
/// [layout]: before the row's last grapheme when its line goes on in the
/// next row, so the cursor stays on this row; the line's end otherwise.
void moveToRowEnd(TextAreaLayout layout);
```

Why there, and not in `text/`:

- The rows the cursor moves in must be the rows the area paints. Those are
  `TextAreaController._rows` (cut by grapheme, a tab four cells, a
  grapheme wider than a row alone on its row, an empty row after a line
  that fills its last row), not `TextLayout`'s word wrap. `TextAreaLayout`
  carries them, and its `cursorRow` already places a boundary cursor on
  the next row.
- It is pure Dart with no widget: a test lays out at a width and calls it.
- A stale layout, or one from before the last change, is laid out again at
  the last width, as `_moveRows` does.
- Both forget the vertical goal column, as `left` and `right` do (through
  `cursor =`).

Wide characters need nothing of their own: offsets are graphemes, so
"before the last grapheme" never splits one, and the cell left empty at a
row's end when a wide grapheme did not fit is not a place the cursor can
be. A row holding one grapheme whose line goes on has start equal to end.

On the empty row after a line that fills its last row, start and end are
both that row; the row before it ends before its last grapheme, since its
line goes on. With width 0 nothing wraps, and the moves equal
`moveToLineStart` and `moveToLineEnd`.

## The bindings

In `TextArea._bindings()`:

```dart
('ctrl+a', 'Move to line start', c.moveToLineStart, true),
('ctrl+e', 'Move to line end', c.moveToLineEnd, true),
('super+left', 'Move to row start', () => _row(c.moveToRowStart), true),
('super+right', 'Move to row end', () => _row(c.moveToRowEnd), true),
```

where `_row` passes `_current()` and, before the first layout (null, or
height 0), falls back to the logical line, as nothing is shown to move in.

- **Descriptions**: "Move to row start" and "Move to row end". "Row" is
  the framework's word for a visual row (`TextAreaRow`, `moveUp`'s "one
  visual row up"), and the key help no longer merges super+left with
  ctrl+a, since they now differ: `ctrl+a Move to line start` and
  `super+left Move to row start` are two lines. The existing tests that
  read `ctrl+a/super+left Move to line start`
  (`test/widgets/text_area_test.dart`, `test/input_kitty_test.dart`,
  `test/terminal_services_example_tester_test.dart`) change with it.
- **Action ids**: none. No `TextArea` binding carries an id today, so none
  can be moved by a `Keymap`; giving these two ids alone would make them
  the only rebindable editing keys. Ids for the editor's keys are a task
  of their own.
- `unhandledKeys` keeps working on them as on every other key.

At 120x40 and 80x24 nothing on screen changes but where the cursor lands
and the key help's two lines.

## The port

Nothing in the port's code is needed for the moves:

- **The prompt** (`lib/ui/prompt/prompt_input.dart`) is a `TextArea`; its
  `cmd+left`/`cmd+right` stay in the textarea's own keys
  (`lib/ui/prompt/prompt.dart` `_textarea`), so they reach the new
  bindings. The shortcuts panel keeps the original's wording, "to line
  start or end" (`../chord/src/ui/shortcuts/keys.ts:139`).
- **The question Note editor** (`lib/ui/dialogs/questions_box.dart`) is a
  `TextArea` whose `onKey` gives `noteEdits` keys back to the editor;
  `noteEdits` already hands it meta/super with ← and →, as the original's
  `questions.ts:204-212`. So super+←/→ there go to the row's ends too.

Port tests: one in the prompt and one in the Note editor, each with text
that wraps at 80x24, pressing super+left and super+right on a wrapped row
and checking where the cursor is drawn, and ctrl+a and ctrl+e still on the
logical line.

## Amendment, 2026-11-23: ctrl+a and ctrl+e in the Note

The paragraph above is wrong for the Note editor. The original's
`noteEdits` (`../chord/src/ui/dialogs/questions.ts:204-212`) hands the Note
only meta/super with ← and →, backspace, ctrl+w and plain characters; ctrl+a
and ctrl+e are not among them, so the Note's editor never moves on them.
The original wins: the ctrl+a/ctrl+e logical-line check belongs to the
prompt's test only, and the Note's test checks super+left and super+right
alone.

Checked in tmux beside the original after U10 (c820d04b), with the fake's
`askclaude` and a long note: `evidence/CTUI-163/port-*.txt` (the prompt)
match `original-*.txt` line for line at 120x40 and 80x24, and
`note-*-120x40.txt` match. At 80x24 the port's Note shows two of its three
rows and leaves the cursor's row undrawn (`note-port-80x24.txt` beside
`note-original-80x24.txt`); main shows the same before this task, so it is
the Note's height, not these moves, and is reported apart.
