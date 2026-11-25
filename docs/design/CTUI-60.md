# CTUI-60: Diff rows wrap as the original

`Diff` wraps a long code row today by `TextLayout.compute(keepSpaces: true)`:
it breaks only at spaces, keeps every space, and starts the next row with
the spaces that did not fit. The original wraps a diff's code with
`wrapLine` (`../chord/src/ui/transcript/message.ts:194`), wrap-ansi with
`hard` and `trim`, in the transcript (`DiffRows`,
`../chord/src/ui/transcript/tools/Tool.tsx:865`) and measures the
permission dialog's diff the same way
(`../chord/src/ui/dialogs/permission.ts:231`). This adds that wrap to the
framework `Diff` as a mode; the port selects it.

## The call site

```dart
Diff.fromView(view, title: path, showTitle: false, wrap: DiffWrap.wrapAnsi)

Diff(oldText, newText, title: 'lib/a.dart', wrap: DiffWrap.wrapAnsi)
Diff.fromUnified(patch, wrap: DiffWrap.wrapAnsi)

SelectionSource.diff(id: id, revision: r, view: view, wrap: DiffWrap.wrapAnsi)
Diff.fromSelectionSource(source, wrap: DiffWrap.wrapAnsi) // checked, as title

final rows = Diff.measure(view, width, wrap: DiffWrap.wrapAnsi);
```

```dart
/// How a [Diff] wraps a code row longer than its room.
enum DiffWrap {
  /// Breaks only at spaces and drops none: spaces that do not fit start
  /// the next row. The default, as `Diff` has always drawn.
  keepSpaces,

  /// As wrap-ansi wraps with `hard` and `trim`: the row's leading indent is
  /// kept on its first row only, as much of it as leaves one cell for code;
  /// the rest wraps at spaces, drops the spaces at every break, and cuts a
  /// word wider than the room. The wrap chord's diffs use.
  wrapAnsi,
}
```

- **Name.** `wrap:` with a `DiffWrap`, beside `Text`'s `softWrap`; the
  values name the two existing `TextLayout` behaviours (`keepSpaces:` and
  `TextLayout.wrapAnsi`), so a reader of the framework knows both already.
  An enum, not a bool, so a third wrap is not a breaking change.
- **Default.** `DiffWrap.keepSpaces`, today's drawing, so no other caller
  and no framework test changes. The port passes `DiffWrap.wrapAnsi` at
  both its diffs (`tool.dart`, `permission_prompt.dart`).
- **Every constructor** takes it: `Diff`, `Diff.fromUnified`,
  `Diff.fromView`, and `SelectionSource.diff`, where it is part of the
  source's geometry, so a source shaped off-screen wraps as the widget
  draws it. `Diff.fromSelectionSource(wrap:)` is checked against the
  source as `title` and `showTitle` are, and may be omitted.
- **Measure.** `Diff.measure(DiffView view, int width, {DiffWrap wrap})`
  returns the rows `Diff.fromView(view, showTitle: false, wrap: wrap)`
  draws at `width` (gaps one row each). It runs the same per-line wrap the
  layout runs, one function, so drawn and measured heights cannot drift.
  The port's `requestHeight` calls it with `width - inputIndent` in place
  of its own `TextLayout.compute`.
- **`codeInsetRight`** (int, default 0, never negative), on every
  constructor, on `SelectionSource.diff` (checked against a bound source as
  `wrap` is) and on `Diff.measure`: cells the code's wrap room keeps free at
  the right while the row and its tint still fill the width. The original's
  transcript wraps a diff's code to its tool body (the row less the
  transcript's 2 cells) while the tint fills the row, so the port's
  transcript passes 2 and the permission dialog passes nothing. It is kept
  off `DiffWrap`, which says how a row breaks, not where.

## The row

The room for code is `max(width - numberWidth - 3 - codeInsetRight, 1)`,
the original's (number, a space, the sign, a space). Tabs become two spaces before
wrapping, the original's `TAB` in `diff.ts`, not wrap-ansi's 8-cell stop.

- **First row**: the number, dim and right-aligned; the sign in its colour;
  then the indent and the code.
- **Continuation rows**: the number's cells blank, two spaces where the
  sign and its space were, code from the code column (not under the
  indent: the original does not re-indent). No `↪` mark.
- **Background**: a changed row's tint fills the whole row width on every
  one of its rows, continuation rows included, as today.
- **Highlighting**: the line's highlighted span is wrapped glyph by glyph;
  colours carry across a break unchanged.
- **Empty line**: one row with the number and sign.
- **Gap** (`…`): unchanged, one row.
- **Selection**: rows keep their source offsets; copying a wrapped line
  gives its source text whole, the spaces dropped at a break included.

## What it draws

The same hunk in `DiffWrap.wrapAnsi`, as the port's transcript draws it
under `⎿` (five cells in): 115 cells at 120x40, 75 at 80x24, 40 for a
narrow dialog. Generated with wrap-ansi 10.0.2 and the original's
`wrapLine` rule.

At 120x40 (115 cells):

```text
11   export function greet(name: string): string {
12 -     return 'Hello, ' + name + '! Welcome back to the project, it is good to see you again today.';
12 +     return `Hello, ${name}! Welcome back to the project, it is good to see you again today, and here is a
     long_identifier_that_cannot_break_anywhere_at_all_in_this_row`;
13   }
```

At 80x24 (75 cells):

```text
11   export function greet(name: string): string {
12 -     return 'Hello, ' + name + '! Welcome back to the project, it is
     good to see you again today.';
12 +     return `Hello, ${name}! Welcome back to the project, it is good to
     see you again today, and here is a
     long_identifier_that_cannot_break_anywhere_at_all_in_this_row`;
13   }
```

Narrow (40 cells), a word wider than the room cut:

```text
11   export function greet(name:
     string): string {
12 -     return 'Hello, ' + name + '!
     Welcome back to the project, it
     is good to see you again
     today.';
12 +     return `Hello, ${name}! Welcome
     back to the project, it is good
     to see you again today, and
     here is a long_identifier_that_
     cannot_break_anywhere_at_all_in
     _this_row`;
13   }
```

Continuation rows are as wide as the first row's room less its indent
(31 cells above, not 35): wrap-ansi wraps the trimmed line to that room
and only the first row gets the indent back. That is the original's.

## Checked when it is built

- A framework test per mode: the rows at a width that breaks inside the
  indent, at a space, and inside a word; `Diff.measure` equal to the drawn
  height for both modes and for every width from 1 to the widest row.
- The port's permission height tests move to the original's rows.
- Captures of the transcript and the permission dialog beside the
  original's at 120x40 and 80x24 go under `docs/design/evidence/CTUI-60/`
  when the units are looked at.
