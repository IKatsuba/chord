# CTUI-164: the editing keys and selection of OpenTUI's textarea

The original's prompt is OpenTUI's textarea (`@opentui/core` 0.8.4, its
`defaultTextareaKeyBindings`,
`../chord/node_modules/@opentui/core/index.node.js:8547-8611`), with chord's
`PROMPT_KEYS` merged over them (`../chord/src/ui/prompt/Prompt.tsx:478-494`).
The owner's answer to Q386 was option 1: every inherited editing key, in-editor
selection included, in the framework's `TextArea`, listed in the shortcuts
panel.

This design has two halves. The framework half (sections 2-7) gives
`TextArea` and `TextAreaController` every action of OpenTUI's default table
and a keyboard selection. The port half (section 8) follows the owner's
answer, A: the captures show the original's prompt does not reach most of
those keys (section 1), and the port's editors keep the original's reach.

## 1. What the original does

Captured in `../chord` with `bun dev chord --fake` at 120x40, keys sent as
kitty or xterm sequences through tmux, on the draft

```text
alpha beta gamma
delta epsilon| zeta
```

(the cursor five graphemes from the end), and `|` typed after each key to show
where the cursor went and what the key changed:
`evidence/CTUI-164/original-keys-120x40.txt`, and the port in the same state,
`port-keys-120x40.txt`.

The original keeps from the textarea every key outside one list.
`TEXTAREA` (`../chord/src/ui/prompt/prompt.ts:147-180`) names the keys the
textarea may act on (the panel's set), and `textareaTakes` (`:271-290`) says
of the rest: "Every other key is the window's, as OpenTUI's textarea has more
keys of its own than the box ever had (ctrl+d deletes, home and end move)". A
key not in the list reaches the textarea only if it types text with neither
ctrl nor alt held, which lets super with a printable key through.

So, of OpenTUI's defaults, in the original's prompt:

| Key | OpenTUI action | Original's prompt | Port today |
| --- | --- | --- | --- |
| ← → ↑ ↓ | move | moves (↑↓ history at the edges) | same |
| alt+← alt+→ alt+b alt+f | word-backward/forward | moves | same |
| ctrl+a ctrl+e | line-home/end | moves | same, but see 1.1 |
| cmd+← cmd+→ | visual-line-home/end | moves (CTUI-163) | same |
| ctrl+w alt+backspace | delete-word-backward | deletes | same |
| ctrl+u ctrl+k | delete-to-line-start/end | deletes | same, but see 1.1 |
| backspace delete | backspace, delete | deletes | same |
| enter, shift/ctrl/alt+enter, ctrl+j | chord's submit, newline | as chord's | same |
| ctrl+z ctrl+y | chord's undo, redo | undo, redo | same |
| cmd+z | undo | **undoes** | nothing |
| cmd+shift+z | redo | **redoes** | nothing |
| cmd+a | select-all | **selects all** | nothing |
| shift+backspace | backspace | **nothing** | deletes |
| home end | buffer-home/end | the window's: scroll | same |
| cmd+↑ cmd+↓ | buffer-home/end | the window's: history, as ↑ ↓ | nothing |
| ctrl+d | delete | the window's: quit | same |
| ctrl+f ctrl+b | move-right/left | nothing | nothing |
| ctrl+← ctrl+→ | word-backward/forward | nothing | nothing |
| alt+a alt+e | visual-line-home/end | nothing | nothing |
| alt+d alt+delete ctrl+delete | delete-word-forward | nothing | nothing |
| ctrl+backspace | delete-word-backward | nothing | nothing |
| shift+delete | delete | nothing | nothing |
| ctrl+- ctrl+. | undo, redo | nothing | nothing |
| shift+← → ↑ ↓ | select by character/row | nothing | nothing |
| shift+alt+← → b f | select by word | nothing | nothing |
| ctrl+shift+a ctrl+shift+e | select to line start/end | nothing | nothing |
| shift+alt+a shift+alt+e | select to row start/end | nothing | nothing |
| cmd+shift+← → ↑ ↓ | select to row/text start/end | nothing | nothing |
| shift+home shift+end | select to text start/end | the window's | the window's |
| ctrl+shift+d | delete-line | not sent; kept from the textarea (ctrl held) | nothing |

"Nothing" means the draft and the cursor stay as they were; `textareaTakes`
gives the key to the window, which has nothing bound to it. alt+a and alt+e
were sent both as `ESC a` and as kitty `CSI 97;3u`, as CTUI-163 did; ctrl+f
and ctrl+b both as kitty and as the raw control bytes.

The Note editor of the question box (`../chord/src/ui/dialogs/questions.ts`,
`noteEdits`) takes less again: alt or cmd with ← →, backspace (shift held or
not), ctrl+w, and printable text with no ctrl, alt or cmd. cmd+a and cmd+z do
not reach it.

### 1.1 Where the shared keys act differently

Three keys the original's prompt and the port's both reach do different
things at a logical line's edge (`evidence/CTUI-164/line-edges-120x40.txt`),
as OpenTUI's `gotoLineHome`, `gotoLineEnd` and `deleteToLineStart` step over
the line break:

| Key, where | Original | Port today |
| --- | --- | --- |
| ctrl+a at a line's start, not the first line | to the previous line's end | stays |
| ctrl+e at a line's end, not the last line | to the next line's start | stays |
| ctrl+u at a line's start, not the first line | deletes the break before it, joining the lines | nothing |

ctrl+k at a line's end deletes nothing in both (OpenTUI's `deleteToLineEnd`
does not join), and cmd+←/→ stay on their row in both (CTUI-163). These are
the port's slips and are fixed in the framework (section 2).

### The selection the original has

cmd+a is the only way into a selection in the original's prompt
(`evidence/CTUI-164/original-select-all-120x40.txt`, `-80x24.txt`, with
colour). It selects the whole draft and paints its graphemes on the palette's
`selection` background (`ansi256(66)` in the dark theme; the line breaks and
the cells after each line's end are not painted). What each key then does,
from `original-select-all-edits.txt`:

| After cmd+a | Result |
| --- | --- |
| typing, paste | replace the selection |
| backspace, delete, ctrl+w, alt+backspace | delete the selection |
| ← alt+← ctrl+a cmd+← | collapse to the selection's start |
| → alt+→ ctrl+e cmd+→ | collapse to the selection's end |
| ↑ | collapses at the cursor (the end), then moves up a row |
| ↓ on the last row | history, as without a selection |
| shift+enter | collapses at the cursor, then breaks the line there |
| ctrl+u | deletes from the cursor to its line's start; the selection goes |
| ctrl+k | deletes nothing (the cursor is at the end); the selection stays, so the next key typed replaces it all |
| ctrl+z | collapses, undoes the last edit |
| cmd+a again | selects all again |
| ctrl+c | clears the draft: no copy |

This is OpenTUI's `EditBufferRenderable` (`chunk-bun-83k2gdpc.js`, from line
18666, read only): `insertOrReplaceSelection`, `deleteChar*` and
`deleteWord*` delete the selection when there is one; every move without
shift goes through `collapseSelectionToEdge("start" | "end")`, but
`moveCursorUp/Down`, which clear it and move from the cursor; `newLine`,
`deleteLine`, `undo` and `redo` clear it first; `deleteToLineStart/End`
ignore it.

## 2. The framework: every action

`TextArea` binds all of OpenTUI's defaults, but those whose OpenTUI action
chord replaced (enter submits; alt+enter breaks the line, as it already
does). Existing bindings keep their keys and descriptions. New ones:

| Keys | Description (key help) | Controller |
| --- | --- | --- |
| ctrl+f | Move cursor right | `moveRight()` |
| ctrl+b | Move cursor left | `moveLeft()` |
| ctrl+right | Move cursor forward a word | `moveWordRight()` |
| ctrl+left | Move cursor back a word | `moveWordLeft()` |
| alt+a | Move to row start | `moveToRowStart(layout)` |
| alt+e | Move to row end | `moveToRowEnd(layout)` |
| home, super+up | Move to text start | `moveToStart()` |
| end, super+down | Move to text end | `moveToEnd()` |
| ctrl+d, shift+delete | Delete character after cursor | `delete()` |
| ctrl+backspace | Delete word before cursor | `deleteWordBefore()` |
| alt+d, alt+delete, ctrl+delete | Delete word after cursor | `deleteWordAfter()` |
| ctrl+shift+d | Delete line | `deleteLine()` |
| ctrl+-, super+z | Undo | `undo()` |
| ctrl+., shift+super+z | Redo | `redo()` |
| shift+left | Select left | `moveLeft(select: true)` |
| shift+right | Select right | `moveRight(select: true)` |
| shift+up | Select up | `moveUp(layout, select: true)` |
| shift+down | Select down | `moveDown(layout, select: true)` |
| alt+shift+left, alt+shift+b | Select back a word | `moveWordLeft(select: true)` |
| alt+shift+right, alt+shift+f | Select forward a word | `moveWordRight(select: true)` |
| ctrl+shift+a | Select to line start | `moveToLineStart(select: true)` |
| ctrl+shift+e | Select to line end | `moveToLineEnd(select: true)` |
| alt+shift+a, shift+super+left | Select to row start | `moveToRowStart(layout, select: true)` |
| alt+shift+e, shift+super+right | Select to row end | `moveToRowEnd(layout, select: true)` |
| shift+home, shift+super+up | Select to text start | `moveToStart(select: true)` |
| shift+end, shift+super+down | Select to text end | `moveToEnd(select: true)` |
| super+a | Select all | `selectAll()` |

OpenTUI's `meta` is alt (option), as its `alt+b`/`alt+f` already are in the
framework; its `super` is cmd. Keys are spelled as `KeyCombo.parse` spells
them, modifiers in the order it prints them.

- **Descriptions** follow the existing ones: "Move cursor …" for a grapheme
  or word, "Move to …" for a place, "Delete … after cursor" beside the
  existing "… before cursor", "Select …" for each move that extends. "Text"
  is the whole buffer, "line" the logical line, "row" the visual row, as
  CTUI-163 settled. Key help merges keys with one description on one line, as
  it does today (`ctrl+z/ctrl+-/super+z Undo`).
- **Enabled**: as today, a binding that cannot act lets its key go on. The
  vertical selects follow up and down: shift+up is enabled while there is a
  row above the cursor's, shift+down while there is one below; neither calls
  `onEdge`. The row moves fall back to the logical line before the first
  layout, as `_row` does now. Everything else is always enabled.
- **home and end**: OpenTUI binds them to the text's ends, so the area does.
  The default `unhandledKeys` stays `{'home', 'end'}`, so an app that does not
  ask keeps them for itself, as today; an app passes `unhandledKeys: const {}`
  to have the area move on them. `shift+home` and `shift+end` are not in the
  default and select.
- **Action ids**: none, as CTUI-163 said; ids for the editor's keys are a task
  of their own.

`TextArea.editingKeys` (section 5) lists every key the area binds, so an app
can leave all but some of them (section 8, option A) without spelling them
out a second time.

### Word, line and text moves

- Word moves and word deletes use the boundaries the controller already has
  (`_wordLeft`, `_wordRight`, OpenTUI's `getPrev/NextWordBoundary`):
  `deleteWordAfter` deletes from the cursor to where `moveWordRight` lands,
  a line break on the way included. Checked against OpenTUI's own edit buffer
  run headless (`evidence/CTUI-164/opentui-edit-buffer.txt`): from before
  ` zeta` in the draft above with a third line `omega`, the next boundary is
  the start of `omega`.
- `moveToLineStart` and `moveToLineEnd` take OpenTUI's step at the edge
  (section 1.1): already at its line's start, the cursor goes to the previous
  line's end; already at its line's end, to the next line's start; at the
  text's start or end it stays. `deleteToLineStart` at a line's start deletes
  the break before it, as `backspace` would; at the text's start nothing. Their
  `///` lines say so. The row moves' fallback before the first layout
  (`_row` in `TextArea`) keeps the cursor's own line and does not step:
  cmd+← at a line's start stays, in both apps.
- `deleteLine` deletes the cursor's logical line with one line break: the
  break after it, the cursor going to the next line's start; on the last
  line, the break before it, the cursor going to the previous line's end; the
  only line leaves the text empty (`opentui-edit-buffer.txt`).
- `moveToStart` and `moveToEnd` go to offset 0 and to `length`.

## 3. The selection model

On `TextAreaController`, plain Dart, tested without a widget. The selection
is an anchor and the cursor; Flutter's names:

```dart
/// A range of the text: from [baseOffset], where it was started, to
/// [extentOffset], where the cursor is; in graphemes.
@immutable
class TextSelection {
  /// A selection from [baseOffset] to [extentOffset].
  const TextSelection({required this.baseOffset, required this.extentOffset});

  /// No selection: the cursor alone at [offset].
  const TextSelection.collapsed({required int offset});

  /// Where the selection was started: the end that stays as it extends.
  final int baseOffset;

  /// Where the cursor is: the end that moves.
  final int extentOffset;

  /// The smaller of the two ends.
  int get start;

  /// The larger of the two ends.
  int get end;

  /// Whether nothing is selected: both ends at one offset.
  bool get isCollapsed;
}
```

On the controller:

```dart
/// The selection; collapsed at [cursor] when nothing is selected. Setting it
/// clamps both ends to the text and moves the cursor to its extent.
TextSelection get selection;
set selection(TextSelection value);

/// Whether some text is selected.
bool get hasSelection;

/// The selected text; empty when nothing is selected.
String get selectedText;

/// Selects the whole text, the cursor at its end.
void selectAll();
```

and `select` on each move (`{bool select = false}`, named, so every existing
call stays as it is): `moveLeft`, `moveRight`, `moveWordLeft`,
`moveWordRight`, `moveToLineStart`, `moveToLineEnd`, `moveToStart`,
`moveToEnd`, `moveUp(layout)`, `moveDown(layout)`,
`moveToRowStart(layout)`, `moveToRowEnd(layout)`.

### Rules

1. **Cursor is the extent.** `cursor` reads `selection.extentOffset`.
   Setting `cursor` collapses the selection there, so everything that sets
   the cursor today (history, completion, the port's reducers) keeps working
   and clears any selection. Setting `text`, `replace` and `clear` collapse
   it too.
2. **Extending.** A move with `select: true` leaves the base where it is,
   or, with nothing selected, at the cursor, and moves the extent as the plain
   move would move the cursor. A selection that comes back to its base is
   collapsed. The vertical goal column works for selecting moves as for plain
   ones.
3. **Collapsing.** A plain move with a selection does not move from the
   cursor: it collapses to an edge, as OpenTUI's `collapseSelectionToEdge`.
   `moveLeft`, `moveWordLeft`, `moveToLineStart`, `moveToRowStart` and
   `moveToStart` collapse to `selection.start`; `moveRight`,
   `moveWordRight`, `moveToLineEnd`, `moveToRowEnd` and `moveToEnd` to
   `selection.end`. `moveUp` and `moveDown` collapse at the cursor and then
   move a row from it; on the first or last row they collapse and return
   false, so ↑/↓ at the edge still reach `onEdge`.
4. **Replacing.** `insert` (typing, paste, `newline`'s break is not one: see
   5) replaces the selection: the text between `start` and `end` goes, the
   inserted text goes in its place, the cursor after it.
5. **Deleting.** `backspace`, `delete`, `deleteWordBefore`, `deleteWordAfter`
   and `deleteBefore` delete the selection, and only it, when there is one.
   `newline` and `deleteLine` collapse at the cursor first and then act as
   without a selection, as OpenTUI's do. `continueLine` (the backslash
   before Enter) likewise.
6. **ctrl+u and ctrl+k ignore the selection**, as OpenTUI's
   `deleteToLineStart` and `deleteToLineEnd` do: they act from the cursor
   as without one. When they delete something the selection is gone with the
   text it covered; when they delete nothing it stays as it was. Pinned by
   `original-select-all-edits.txt`: after cmd+a (the cursor at the text's
   end), ctrl+k deletes nothing, the whole draft stays selected, and the
   next typed `|` replaces it all (`│ › |`); ctrl+u deletes the last
   line's text and the `|` lands at that line's start, replacing nothing
   (`alpha beta gamma` / `|`). Settled by the lead: the original's
   behaviour, not a collapse of our own.
7. **Undo and redo.** A replace or delete of a selection is one edit, one
   undo step. `undo` and `redo` collapse the selection and restore text and
   cursor as now; a selection is not part of an undo step (OpenTUI's `undo`
   clears it). Selecting alone is no edit: it adds no step.
8. **Notifying.** A change of selection notifies listeners, as a cursor move
   does now.

## 4. Drawing

`TextArea` paints the selected graphemes with `Theme.of(context).selection`
merged over their style (the theme's "background of selected cells"), so
text keeps its colour, bold and the spans of `textSpanBuilder`, and takes the
selection's background. Line breaks and the cells after a line's end are not
painted, nor the empty row after a line that fills its last row, as the
original's capture shows. A tab paints its four cells (the framework's
rule: the original's window takes a tab before its draft can hold one); a
wide grapheme both of its cells. The cursor is drawn at the extent as it is
now, on top. The selection is drawn focused or not (OpenTUI keeps it on
blur), and never on
the placeholder. A new `selectionStyle` parameter overrides the theme, as
`style` and `placeholderStyle` do:

```dart
/// Selected text; the theme's selection if null.
final Style? selectionStyle;
```

At 120x40, the framework's `example/text_area.dart` after cmd+a on two lines
(`▒` marks the selection's background; the original's colour capture is
`evidence/CTUI-164/original-select-all-120x40.txt`):

```text
▒alpha beta gamma▒
▒delta epsilon zeta▒█
```

drawn as the two lines' graphemes on the selection background, nothing after
them, and the block cursor after `zeta`. At 80x24 a selection across a
wrapped line paints each row's graphemes, the wrap adding nothing: a row cut
inside a word is painted to its last grapheme and the next row from its
first.

States: empty, nothing to select (cmd+a selects nothing, the placeholder
stays unpainted); focused or unfocused, as above; overflowing, the rows
scrolled out are not drawn and the extent stays revealed as the cursor is
now; narrow, as wrapped rows above; width 0, nothing drawn and the model
unchanged.

## 5. Public API

On `TextArea`:

```dart
/// Every key the area binds, as [KeyCombo.parse] spells it, with the
/// description key help shows for it.
static const Map<String, String> editingKeys;

/// Selected text; the theme's selection if null.
final Style? selectionStyle;
```

On `TextAreaController`, beside section 3's: `moveToStart({bool select})`,
`moveToEnd({bool select})`, `deleteWordAfter()`, `deleteLine()`, each with a
`///` line as written in section 2's table.

`TextSelection` lives in `lib/src/foundation/text_editing.dart` and is
exported by `chord_tui.dart`.

## 6. SelectionArea, SelectionEditor and copy

Two selections, kept apart:

- **`SelectionArea`** is the pointer's: a drag over the window's semantic
  sources, the editor's rows among them through `SelectionEditor`. It reads
  the editor's text and layout and never changes them.
- **The editor's selection** is the keyboard's, in `TextAreaController`.
  `SelectionEditor` goes on registering the editor as a source unchanged: a
  drag over a draft selects its cells for copy, as now, without touching the
  controller's selection.

In the original both are OpenTUI's one renderer selection: a drag that starts
clears the textarea's, and a key the window answers clears a drag's before it
acts (`../chord/src/ui/app/keys.ts:606-614`). The framework does not join
them; an app that wants one selection on screen collapses the editor's when
its `SelectionArea` reports a range (`onSelectionChanged`), and clears the
area's on a key, as the port already does for the second.

**Copy.** The original has no key that copies a textarea selection: with
cmd+a's selection shown, ctrl+c clears the draft, and its copy action reads
the drag's selection only (`../chord/src/ui/app/terminal.ts:583`). The
framework gives `selectedText` and binds no copy key, and the port adds
none: cmd+a then ctrl+c clears the draft, as in the original. Settled by the
lead; a copy key would be a departure only the owner can ask for.

## 7. Tests the framework units need

Per key in section 2, a `TextArea` test through the tester: draft, key, the
screen and the controller's text, cursor and selection. Per rule in section
3, a controller test without a widget, the selection cases of
`original-select-all-edits.txt` and `line-edges-120x40.txt` among them.
Drawing: a selection across a wrapped line, a tab and a wide grapheme, with
`textSpanBuilder` spans kept, at 120x40 and 80x24. Key help: the new lines
and the merged ones.

## 8. The port: option A

The owner chose A (`docs/decisions.md`, 6d72d7aa): the port's editors reach
what the original's reach. U3 replaces the hold (356d334e) with this.

### The prompt

- **Keys.** The prompt's `unhandledKeys` take `TextArea.editingKeys` less
  the original's `TEXTAREA` list (`lib/ui/prompt/prompt.dart` `_textarea`)
  and less `super+a`, `super+z` and `shift+super+z`, the three that the
  original's `textareaTakes` lets through as printable keys with neither ctrl
  nor alt. shift+backspace is no longer kept out of that set as the hold kept
  it, so it stops deleting (`original-keys-120x40.txt`: nothing). The prompt
  therefore gains cmd+a, cmd+z and cmd+shift+z, and the line-edge steps of
  section 1.1 come with ctrl+a, ctrl+e and ctrl+u, as the hold already shows
  (`hold-line-edges-120x40.txt`). Every other key of section 2 does what
  `port-keys-120x40.txt` shows: nothing, or the window's.
- **The window first.** A key the keymap gives to a window action is the
  window's, as the original's listener runs before its textarea: the
  existing `taken` and `off` sets go on being added.
- **The selection's colour** is the palette's `selection` role, as the
  original's `useSelectable` gives its draft (dark `ansi256(66)`, light
  `ansi256(152)`, plain slate): the prompt passes
  `selectionStyle: chordThemeOf(context).selection`. The framework theme's
  default would be inverse.
- **What collapses it.** A draft set from outside (a history walk, a taken
  completion, sending, ctrl+c's clear, the editor's return, a kept draft)
  sets the controller's text, which collapses the selection (rule 1).
  ctrl+c with a selection clears the draft and copies nothing (section 6).
- **The pointer.** The original has one selection on screen. When the
  window's `SelectionArea` reports a range that is not empty, the prompt's
  controller collapses its selection at its cursor, as a drag clears
  OpenTUI's textarea selection. A key pressed while a drag's selection is
  shown already clears that selection first, in the port as in the original
  (`../chord/src/ui/app/keys.ts:606-614`), so cmd+a with a drag shown clears
  the drag and selects the draft.
- **Undo.** cmd+z and cmd+shift+z keep the window's copy of the draft in step,
  as ctrl+z and ctrl+y do: in the original, `a` then cmd+z empties the draft
  and the status line's `? for shortcuts` comes back at once. The
  controller's `onChanged` already gives that.
- **Vim mode.** Insert mode is the text area, so it gets the same keys.
  Normal mode keeps `vimTakes` as it is; nothing in it changes.

### The question box's Note

Unchanged. The original's `noteEdits` (`../chord/src/ui/dialogs/questions.ts`)
refuses cmd except with ← →, so none of the three reaches it, and shift with
backspace still deletes there. The port's `onKey` already filters through
`noteEdits`.

### The plan box's Note

The original's (`evidence/CTUI-164/plan-note-120x40.txt`) is no textarea. It
is a text row edited at its end by `edited()`
(`../chord/src/ui/dialogs/questions.ts:233`):

- Typing appends.
- backspace, shift+backspace and alt+backspace delete the last character.
- ctrl+w deletes the last word, and ctrl+u clears the row.
- Nothing moves: ←, →, alt or cmd with them, and ctrl+a, ctrl+e, ctrl+b and
  ctrl+f do nothing, as do delete, ctrl+k, alt+d and ctrl+z.
- cmd+z, cmd+shift+z and cmd+a type `z`, `Z` and `a`: `edited` checks ctrl
  and alt but not cmd.

The port's, on main and with the hold, is a `TextArea` with a cursor. ←, →,
the word and line moves, delete, ctrl+k and ctrl+z all act, ctrl+u deletes
only to the line's start, and alt+backspace deletes a word. That gap is older
than this task and is not about OpenTUI's keys, so U3 keeps the plan Note's
hold as it is (the port's keys on main). The end-only row is
CTUI-178; cmd+a, cmd+z and cmd+shift+z typing a letter, the original's slip,
is not ported (section 9).

### The shortcuts panel

The panel gets two entries in the port's list (`lib/ui/shortcuts/`),
straight after `cmd + ← →  to line start or end`. Like that line, they are
fixed keys with no action and carry `prompt` presses for the key test:

| key | does | prompt presses |
| --- | --- | --- |
| `cmd + a` | `to select all input` | `cmd + a` |
| `cmd + z` | `to undo, with shift to redo` | `cmd + z`, `cmd + shift + z` |

- "input" as in `ctrl + c  to clear input`.
- One line for undo and redo keeps the panel one line shorter at 80x24, and
  at 35 cells it fits the first column's 40.
- They carry no `questions` presses: the Note gets neither.
- The readline keys stay off the panel, as in the original (`keys.ts`:
  "Typing and editing the draft … are not listed, as in Claude Code").
  The owner's listing is of the keys the prompt now reaches from OpenTUI's
  defaults, and those are the three.

At 120x40 the panel's 45 entries flow into three columns of 15
(`panel-mock-120x40.txt`, beside today's `panel-port-120x40.txt`):

```text
  enter to send                           pgup pgdn or wheel to scroll            ctrl + d or ctrl + c twice to quit
  ...
  cmd + ← → to line start or end          tab to complete a command               enter to pick the highlighted choice
  cmd + a to select all input             tab enter to add a file or agent        esc to reject a permission
  cmd + z to undo, with shift to redo     esc to close completions                esc ← to leave a picker or shortcuts
  ↑ ↓ for prompts, agents, background     ! for bash mode                         ctrl + a to show all directories
  ...
```

At 80x24, two columns of 23, the first 17 rows shown and
`── ↓ 6 lines below · pagedown to scroll ──` under them, where today it says
5 (`panel-mock-80x24.txt`, beside `panel-port-80x24.txt`).

### The port's tests

- A window test at 120x40 and 80x24. cmd+a paints the draft in the palette's
  selection (`ansi256(66)` in dark), and a typed character replaces it.
  cmd+z and cmd+shift+z undo and redo, and the status line's hint follows the
  draft. shift+backspace does nothing. Every other key held before still does
  nothing (the hold's test, adapted).
- A drag over the transcript collapses the prompt's selection.
- The key test answers the two entries' prompt presses.
- The panel's geometry at both sizes.
- The plan Note's hold test stays.

## 9. Questions

For the lead, to main where they are the owner's:

1. The scope (section 8): A, the owner's answer.

Settled by the lead:

2. No copy key for the editor's selection; the original has none (section 6).
3. ctrl+u and ctrl+k with a selection do what the original does (rule 6).
4. shift+backspace in the prompt stops deleting with option A, the Note
   keeping it, as the original's does; it is part of the owner's answer.
5. The line-edge slips of section 1.1 are fixed in the framework.

6. The plan box's Note's end-only row is a task of its own, CTUI-178; U3
   keeps the plan Note's hold.
7. The original's plan Note typing a letter for cmd+a, cmd+z and
   cmd+shift+z is not ported.

Settled by main:

8. The panel lists only the three keys the prompt newly reaches (section
   8); the readline keys stay unlisted, as in the original.
