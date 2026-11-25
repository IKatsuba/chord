# CTUI-68: the question box

The screens follow the original (`../chord/src/ui/dialogs/Questions.tsx`,
`questions.ts`, `asker.ts`, and `Form.tsx`'s `QuestionsRecord`); captures of
both side by side are under `evidence/CTUI-68/`. This file holds only what
the original does not settle: the one framework change the box needs.

## `TextArea.placeholderGap`

A focused, empty `TextArea` today draws one blank cell before its
placeholder, so the terminal cursor sits on the blank and the hint starts
one column later. That is the prompt's look: the original's `Prompt` draws
its block cursor before the hint. The question box's Note is an OpenTUI
textarea in the original, which puts the cursor on the placeholder's first
cell with no blank:

```text
original, focused:  │ ❯ Note  Additional answer or note
port today:         │ ❯ Note   Additional answer or note
```

The call site:

```dart
TextArea(
  controller: note,
  placeholder: 'Additional answer or note',
  placeholderStyle: Style(fg: RgbColor(0x66, 0x66, 0x66)),
  placeholderGap: false,
)
```

```dart
/// Whether a focused, empty area draws a blank cell for the cursor before
/// its placeholder; false puts the cursor on the placeholder's first cell.
final bool placeholderGap; // default true
```

- Default `true`, so the prompt and the plan box keep what they draw.
- Unfocused, the flag changes nothing: no blank is drawn either way.
- Nothing else moves: wrapping, scrolling and the cursor's position in a
  non-empty area are untouched; with `false` the cursor stays at column 0.
- Flutter has no counterpart (its hint always starts under the cursor, which
  is `false` here); a plain flag beside `placeholder` and
  `placeholderStyle` reads without a guide.

States to test, both values: focused empty (the gap or none, the cursor's
cell), unfocused empty (identical), focused with text (identical).
