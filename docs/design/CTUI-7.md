# CTUI-7: Text area

A framework multiline editor. The original is `../chord/src/ui/prompt/`:
`TextArea.tsx`, `prompt.ts`, `history.ts` and `Prompt.tsx`. History, completion,
height policy and gutter marks belong to the port; this task adds no port screen.

## Call site and widget

```dart
final draft = TextAreaController();

TextArea(
  controller: draft,
  autofocus: true,
  maxHeight: 6,
  placeholder: 'Write a message',
  onSubmit: send,
  onChanged: changed,
  onKey: completeOrWalk,
  onEdge: (direction) => walkHistory(direction),
  unhandledKeys: const {'home', 'end'},
)
```

`TextArea` is a StatefulWidget. Optional parameters: `controller`
(TextAreaController), `focusNode`, `onSubmit(String)`, `onChanged(String)`,
`onKey(KeyEvent) -> bool`, `onEdge(TextAreaDirection) -> void`, `placeholder`,
`style`, `cursorStyle`, `placeholderStyle`. Defaults: `autofocus = false`,
`maxHeight = 10`, `unhandledKeys = const {'home', 'end'}`. Direction has
`up` and `down`. Text, steady block cursor and placeholder use TextInput's
existing theme roles. No prefix, border or gutter: compose those outside.

Grow from one row to min(content rows, maxHeight, available height).
maxHeight must be positive. Require bounded width; unbounded height is fine.
Zero available width/height paints nothing and preserves text and cursor;
it must not create division errors or phantom history edges. The widget owns
and disposes only controllers and focus nodes it creates. Replacement detaches
old listeners and uses the new object's state.

## Controller

`TextAreaController extends TextEditingController`, plain Dart, independent
of widgets/rendering/focus. Keep the base controller and TextInput behavior
unchanged, including whole-buffer deleteToStart/deleteToEnd and its old
whitespace-based deleteWordBefore. TextInput stays the existing widget,
including its existing newline support and Home/End aliases; do not rewrite
it as an area configuration. Existing users include Picker, the demo and
focus/lifecycle/theme tests.

Inherit text, cursor, length, beforeCursor, afterCursor, insert, backspace,
delete, clear and listener lifecycle. Text/cursor offsets count extended
grapheme clusters, including one per LF; assigning text places cursor at end;
assigning cursor clamps. Add these public operations:

| API | Meaning |
| --- | --- |
| cursorLine, cursorColumn | Zero-based logical line and grapheme column |
| moveLeft(), moveRight() | One grapheme, including crossing LF |
| moveWordLeft(), moveWordRight() | Native boundaries below |
| deleteWordBefore() override | Delete to native previous-word boundary; base unchanged |
| deleteBefore(int count) | Delete up to count graphemes before cursor; reject negative count |
| moveToLineStart(), moveToLineEnd() | Logical line boundaries, not wrapped row |
| deleteToLineStart(), deleteToLineEnd() | Delete inside logical line only; preserve LF; no-op at boundary |
| newline() | Insert LF, cursor immediately after it (original broken) |
| continueLine() -> bool | Replace immediately preceding backslash with LF and put cursor after LF; otherwise false without mutation (original continued) |
| moveUp(TextAreaLayout), moveDown(TextAreaLayout) -> bool | One visual row; false at first/last buffer row, without movement |
| layout({required int width, required int maxHeight}) -> TextAreaLayout | Settle wraps and scroll geometry |
| rowOffset | Read-only first visible visual row |
| TextAreaLayout? get lastLayout | Read-only snapshot settled by the area; null before first layout |

The area's constructor, text setter, insert and paste normalize CRLF and CR
to LF before segmentation. Paste inserts the whole normalized payload once,
never submits. Backspace at logical line start and Delete at logical line end
join lines. Trailing LF preserves an empty final line. One mutation notifies
once, with cursor already settled; no-op mutations/moves do not notify.
Cursor-only and geometry-only changes do not call onChanged.

Every edit, direct cursor assignment, horizontal/word/line movement or width
change resets the vertical goal. First up/down records the visual cell column.
Subsequent up/down keeps that goal through short rows, choosing the nearest
insertion boundary at or before it, never a wide grapheme's second cell.
An edge attempt leaves cursor/goal unchanged. Movement must not use stale
layout offsets after text/width changes.

### Word boundaries

The lead settled fidelity to installed OpenTUI EditBuffer, measured without
a terminal, instead of changing the old single-line controller's word rule.
These cases are the regression contract; offsets here count ASCII graphemes:

| Text | Expected movement |
| --- | --- |
| `one two` | Right 0 → 4 → 7; left 7 → 4 → 0 |
| `one.two` | Right 0 → 4 → 7; left 7 → 4 → 0 |
| `one_two` | Right 0 → 7; left 7 → 0 |
| `one  two` | Right 0 → 4 → 8; left 8 → 5 → 4 → 0 |
| `hello, world!` | Right 0 → 6 → 13; left 13 → 7 → 6 → 0 |
| `one\ntwo` | Right from 0 lands at next line start (4); left from 4, 5, 6 or 7 lands at previous line end (3) |

Letters, digits, underscore and non-ASCII text form runs; ASCII punctuation
and whitespace separate runs. Native forward movement advances one grapheme,
scans the remaining run and includes the next separator; backward steps back
first, scans the preceding run and stops after a separator. LF crossing uses
the table's explicit stop. Word deletion uses exactly the previous-word result.
Test punctuation, repeated separators, LF, CJK, combining clusters and emoji;
never split a cluster to reproduce native cell coordinates. Prompt.tsx's
wordCut override is chord's image-placeholder logic, out of scope. The future
port can convert its range to grapheme count and call deleteBefore.

## Visual layout and own scrolling

TextAreaLayout is an immutable plain Dart snapshot: rows, shownRows,
cursorRow, cursorColumn (cells), rowOffset, width and height. TextAreaRow
exposes text, line, piece, last, start/end grapheme offsets. line/piece are
zero-based. last means last in the whole buffer, not last visible. Empty
text has one empty row. This supplies the port's shownRows/gutterMark data
without introducing its marks into the framework.

Wrap by grapheme at cell boundaries, matching the original wrapMode='char',
not by words. Reuse existing glyphs, grapheme widths and layout; extend its
wrap mode as needed rather than silently using word wrap. Retain every space
and tab source offset; tabs use existing four-cell expansion. A grapheme
wider than the row remains atomic and clipped, without a spurious empty row
or cursor in its second cell.

At soft wrap, a shared insertion offset belongs to the following row. At the
end of an exactly full logical line, give the insertion cursor an empty
continuation row rather than overwrite the last character. Cursor before LF
is a blank cell on the preceding logical line; after LF it starts the next.
Include continuation rows for every exactly-full logical line independently
of cursor position, consistently in metadata and movement. For text `abc`
at width 3, rows stay `[abc, empty]` while EOF → Up → Down returns to EOF;
choosing a vertical target must not create another row afterward.
Unfocused layout has the same geometry and hides only cursor styling.

With available space, height is at least one. Clamp rowOffset to
0..max(0, rows.length-height); then change it only enough to reveal cursorRow.
Recompute after edits, recall, movement and resize. Preserve logical cursor
on width changes. No scroll action independent of cursor is added here.

layout may settle geometry during widget layout, but must not notify there.
Publish changed geometry through the existing post-layout notification phase
so a sibling gutter can settle in the same frame. `lastLayout` is the
snapshot the area settled last, published through that post-layout
notification; it is null before the first layout. The example status line
and future port gutter read `lastLayout`, rather than calling `layout()`
themselves: the actual area may receive fewer rows than maxHeight, so a
second layout call could report a different viewport. Plain controller tests
can still call `layout()` and inspect its returned snapshot directly. A
controller attached to two areas is an error.
The port later chooses min(10, max(3, floor(windowRows/3))) as promptRows;
the framework does not infer window height.

## Keys and hooks

unhandledKeys is a set of key strings parsed as KeyCombos. Matching keys
bypass hooks, area Actions and text insertion, reaching the ancestor unchanged.
Invalid strings fail on mount. Home/End are excluded by default and have no
built-in action even with an empty exclusion set; Ctrl+A/E move within a
logical line. Exclude other combinations to reserve window keys/chord starts.

After exclusions, onKey runs first: true consumes, false continues. A popup
can handle Tab, Enter, Escape or arrows here. For history walking, the port
handles Up/Down here from any row while a recalled prompt is untouched;
once edited it returns false, restoring visual movement and edge handoff.
The framework stores no history and does not infer walking state.

| Keys | Action description / effect |
| --- | --- |
| Enter | Submit: first try continueLine; otherwise onSubmit(text), without clearing |
| Shift+Enter, Alt+Enter, Ctrl+Enter, Ctrl+J | Insert newline |
| Left, Right | Move cursor left / Move cursor right |
| Up, Down | Move cursor up / Move cursor down; at visual edge call onEdge |
| Alt+B, Alt+Left | Move cursor back a word |
| Alt+F, Alt+Right | Move cursor forward a word |
| Backspace, Shift+Backspace | Delete character before cursor |
| Delete | Delete character after cursor |
| Ctrl+W, Alt+Backspace | Delete word before cursor |
| Ctrl+U, Ctrl+K | Delete to line start / Delete to line end |
| Ctrl+A, Ctrl+E | Move to line start / Move to line end |

Bind named edits with actual Bindings through an internal Actions ancestor
of the area's Focus, one binding per alias with the descriptions above.
Focus handles the hook and printable insertion; bindings execute named edits.
Excluded keys have no binding. Up/Down at an edge without onEdge have no
enabled binding and propagate; with onEdge they consume once and call it once.
KeyHelp sees focused editing bindings plus ancestor actions. Hook-owned
commands need app-owned Actions descriptions; hooks are not another shortcut
registry. As for ListView's aliases, KeyHelp may list aliases separately until
the shortcuts panel groups them. Do not invent another keymap API.

Unlisted named keys, modified text, Ctrl+D, Ctrl+B/F, Home/End, page keys,
undo/redo and shifted navigation propagate. TextInput keeps its old aliases.
Cmd+Left/Right are a known input gap: KeyEvent lacks a command/super modifier.
The lead agreed to report it to main. Do not map command to Alt or claim
these original keys work.

## Example and screen

Add example/text_area.dart: title; expanding space for last submission;
framed area with one blank column outside each border and one space inside
each side, maxHeight 4; a short hint and
KeyHelp. Ctrl+Q quits via Actions. Submit echoes text above and clears via
the example's callback. Content width is window width minus six cells. Label
logical cursor and shown row range on a dim line immediately below the frame
and above the hint: `line 6, column 7 · rows 3–6 of 6`. All numbers are
one-based; column counts graphemes and rows count visual rows. Empty reads
`line 1, column 1 · rows 1–1 of 1`. This demonstrates own scrolling without
a framework gutter. Border columns are 1 through window width minus 2;
editable width is window width minus 6. This is a framework demo, not a port
screen; no original screen comparison is claimed.

Schematic mocks below are not observed captures. ▉ means a styled blank
cursor cell; cursor on text styles the existing whole grapheme. Actual
review evidence must be full 120x40 and 80x24 panes saved under
`docs/design/evidence/CTUI-7/`. Borders belong to the example. The schematic
borders below are abbreviated; the explicit column geometry above governs
implementation, including the outer blank columns and position label.

120x40 empty/focused, blank middle rows omitted:

```text
Text area

┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ ▉Write a message                                                                                                     │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
Enter sends · Shift+Enter adds a line · Ctrl+Q quits
```

80x24 wrapped/focused, schematic text flow:

```text
Text area

┌──────────────────────────────────────────────────────────────────────────────┐
│ A long message wraps by cells; wide characters 界🙂 stay together, and these   │
│ words continue on the next visual row.▉                                       │
└──────────────────────────────────────────────────────────────────────────────┘
Enter sends · Shift+Enter adds a line · Ctrl+Q quits
```

At either size enter six logical lines, line 1 through line 6. The four-row
area shows this (extend border/padding by 40 cells at 120 columns):

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ line 3                                                                       │
│ line 4                                                                       │
│ line 5                                                                       │
│ line 6▉                                                                      │
└──────────────────────────────────────────────────────────────────────────────┘
```

Report rowOffset 2, cursorRow 5, shown logical lines 2..5; only line 6 is last.
Three Up presses retain offset 2 and goal column 6; a fourth reveals line 2
and moves offset to 1. An unfocused area keeps geometry and hides cursor.
Empty/unfocused placeholder starts in the first cell. Empty/focused draws a
blank cursor before dim placeholder, following TextInput's taste. Placeholder
is display-only, clipped to the empty row, and adds no editable rows. Cursor
on wide text styles both cells; before LF or EOF it styles a blank cell.
Narrow resize preserves text/logical cursor, wraps and reveals it, with no
horizontal scrollbar.

## Acceptance and scope

Controller tests: every mutation, normalization, no-op/notification behavior,
word table, continued/broken mid-line, logical line cuts and grapheme safety.
Rows: exact-width ending, trailing LF, spaces/tabs, wide/combining/emoji text,
vertical goal, edges, scrolling and resize. Widget checks at both sizes:
placeholder/focus, submit/newline aliases, paste, scrolling, hooks, excluded
keys reaching ancestor Actions and editing descriptions in KeyHelp. Keep
existing TextInput tests green. Designer runs only handed-over screen units
in named tmux sessions at both sizes, captures them and kills owned sessions
before handing to reviewer.

Reuse existing characters dependency and width/layout code. This is terminal
editing/layout, not a new parser or matcher. No vim, undo/redo, selection,
images, mentions, history store, completion engine, chord gutter or CTUI-17
prompt integration.
