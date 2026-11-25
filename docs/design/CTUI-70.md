# CTUI-70: a form block taller than `maxRows`

The framework `Form` (docs/design/CTUI-33.md §1) scrolls its field area by
whole field blocks, as the original's `formRows` (../chord
src/ui/dialogs/form.ts:933-974) does, early return included. When the
focused block does not fit (a choice list opened with more options than
rows), or a block before the focused one does not fit, the view stops at
that block and draws only `↓ N more fields`: the focused field and its
highlighted option are not shown. `rows(0)` still gives that one count
row. This design replaces the "Scrolling" paragraph of CTUI-33 §1 that
records the defect, and nothing else: every other rule of CTUI-33 holds.

## Departure from the original

The original has the same defect (form.ts:961, `end === top`), and the
port's form box inherits whatever the framework does. This is a deliberate
departure, recorded here so nobody "restores" parity:

- Original: a block taller than the limit ends the view; the focused block
  can be out of view; the limit can be exceeded by one row at limit 0.
- Here: the focused field and, with a list open, its highlighted option
  are always in view, and the field area never has more than `maxRows`
  rows (none at all at 0).

Where every block fits, the rows are exactly the original's (and
CTUI-33's): the same first view from the top, the same count rows. None
of the fake's form scenarios in the port reaches the new path (their lists
have three options and the box gives the fields 9 rows or more at 80x24),
so the port draws as before; it only stops losing the focus in a tall
form.

## API

No new parameter. `Form.maxRows` and `FormData.rows([int? limit])` keep
their meaning; `rows` gains the guarantee. One new row kind, beside
`FormMoreRow`:

```dart
/// Options of the open list scrolled out of view above or below.
final class FormMoreOptionsRow extends FormRow {
  /// [count] options out of view, above when [up].
  const FormMoreOptionsRow({required this.up, required this.count});

  final bool up;
  final int count;
}
```

A separate class rather than a flag on `FormMoreRow`: it is drawn in
another column and counts another thing, and a `switch` over `FormRow`
should be told about it.

## The rule

`rows(limit)`:

1. `limit` null, or every row fits: every row (unchanged).
2. `limit` 0 or less: no rows. The widget then draws no field area and
   no blank row before the buttons (it already skips the blank row when
   `rows` is empty).
3. The anchor block is the focused field's; with the focus on a button,
   the first field's. The view is the first one from the top, made of
   whole blocks with their `↑`/`↓ N more fields` rows, that holds the
   anchor block whole (unchanged), except that a block which does not fit
   no longer ends the search: a view that misses the anchor is passed
   over, whatever stopped it. This alone fixes "a taller block before the
   focused one".
4. If no whole-block view holds the anchor block (it is taller than the
   limit less its count rows), the view is the anchor block alone, cut.
   Rows are claimed in this order, each only while a row is left:
   1. the field row;
   2. the highlighted option, when a list is open;
   3. `↑ N more fields`, when fields are above;
   4. `↓ N more fields`, when fields are below;
   5. the note (shown problem, else the focused field's description);
   6. more options: the largest window of consecutive options, with its
      `↑`/`↓ N more options` rows, that fits in what is left. The window
      is the first one from the top that holds the highlight (the same
      rule as for fields), so the highlight sits on its last row once it
      has moved past the first page, and the first page shows while it is
      on it. If even one count row does not fit beside the highlight, the
      highlight shows alone.

   Drawn top to bottom: `↑ N more fields`, the field row, `↑ N more
   options`, the options, `↓ N more options`, the note, `↓ N more fields`.

Never more than `limit` rows; with a list open and `limit` 2 or more, the
field and its highlighted option are both shown.

## What it draws

The option count rows are dim, at the options' label column (the value
column plus the 2-cell gutter), and read `↑ 1 more option` /
`↓ 8 more options`. The field count rows are as before. No other glyph,
colour or column changes.

`example/form.dart --narrow` (maxRows 8) with Region given twelve options
(the example gains `--long-list` for this; see Example). The rows are the
same at 120x40 and 80x24; only the hint differs, long and short as
CTUI-33's table.

Region opened, the highlight on 1:

```text
    ↑ 5 more fields
❯ * Region         ▾
                   ❯ 1. Europe
                     2. United States
                     3. Asia Pacific
                     4. Canada
                     ↓ 8 more options
    ↓ 1 more field
```

↓ six times, the highlight on 7:

```text
    ↑ 5 more fields
❯ * Region         ▾
                     ↑ 4 more options
                     5. Japan
                     6. India
                   ❯ 7. Brazil
                     ↓ 5 more options
    ↓ 1 more field
```

The highlight on 12, the last:

```text
    ↑ 5 more fields
❯ * Region         ▾
                     ↑ 8 more options
                     9. South Africa
                     10. Middle East
                     11. Mexico
                   ❯ 12. Korea
    ↓ 1 more field
```

A shown problem with the list open (the note is claimed before extra
options, so the window shrinks by one):

```text
    ↑ 5 more fields
❯ ⚠ Region         ▾
                   ❯ 1. Europe
                     2. United States
                     3. Asia Pacific
                     ↓ 9 more options
                   Required
    ↓ 1 more field
```

Tiny limits, Region focused with its list open, highlight on 1:

```text
maxRows 1:  ❯ * Region         ▾

maxRows 2:  ❯ * Region         ▾
                               ❯ 1. Europe

maxRows 3:      ↑ 5 more fields
            ❯ * Region         ▾
                               ❯ 1. Europe

maxRows 0:  (no field area; the buttons and the hint only)
```

The whole screen at 80x24, `--narrow --long-list`, highlight on 7:

```text
 New deployment

    ↑ 5 more fields
❯ * Region         ▾
                     ↑ 4 more options
                     5. Japan
                     6. India
                   ❯ 7. Brazil
                     ↓ 5 more options
    ↓ 1 more field

  Accept   Decline

↑↓ · 1–9 or Enter to pick · ← to close · Esc to cancel

Gave: nothing yet
Ctrl+Q quits
```

At 120x40 the same, with the long hint `↑↓ to move · 1–9 or Enter to
pick · ← to close the list · Esc to cancel`. The digit keys still pick
options 1 to 9 by number whether or not they are in view, as CTUI-33
(and the original) bind them; the window then follows the highlight.

A multi-choice list cuts the same way, its rows `☒`/`☐` as before.

## States

- Empty, focused/unfocused (`enabled: false`), narrow: as CTUI-33.
- Overflowing: every block fits, as CTUI-33; a block does not, as above.
- `maxRows` smaller than the count rows need: the claim order decides; the
  field row first.

## Keys

None new and none changed. ↑↓ (and `k`/`j`) move the highlight as before;
the window is derived from the highlight on every frame, so there is no
scroll state to keep, and a form left and come back to shows the same
window.

## Example and tests

- `example/form.dart --long-list` gives Region twelve options; with
  `--narrow` it shows the partial view. (AGENTS.md's command list gains
  the line; writer's.)
- Reducer tests on `FormData.rows`, plain Dart: twelve options at limit 8
  with the highlight on the first, a middle and the last option (rows as
  the captures above); a shown note with the list open; limits 0, 1, 2
  and 3; a two-row block (a shown problem) before the focused field at
  limit 2, which today hides the focus; the focus on the buttons with the
  first block taller than the limit; and every case asserting
  `rows.length <= limit` and, with a list open, that the focused field
  row and the highlighted option are present.
- A cut-free form (every block fits) gives the same rows as before: the
  existing scrolling tests stay as they are.
- Widget tests at 120x40 and 80x24 through the tester: `--long-list`'s
  form at `maxRows: 8`, open, ↓ six times, the screen as above; `maxRows:
  0` draws the buttons with no blank row above them.
