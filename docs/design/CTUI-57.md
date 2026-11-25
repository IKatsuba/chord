# CTUI-57: wrap at OpenTUI's word-wrap breaks

API gate for unit U1. The framework's word wrap (`TextLayout.compute`,
which `Text` and everything drawn through it use) breaks only at a space
or a tab. The original draws plain text through OpenTUI's `<text>`, whose
default `wrapMode` is `word`, and OpenTUI's word wrap also breaks after
`/` and its other break characters. CTUI-29 found it at 80x24 (the
settings warning, [original](evidence/CTUI-29/u29b2a-window-o-80x24.txt)
beside [port](evidence/CTUI-29/u29b2a-window-p-80x24.txt)):

```text
original:  ⏺ .chord/settings.json: "theme" is read only from /tmp/ctui29-look/cfg/chord/
             settings.json, ignored
port:      ⏺ .chord/settings.json: "theme" is read only from
             /tmp/ctui29-look/cfg/chord/settings.json, ignored
```

After U1 the port draws the original's two rows. At 120x40 the row fits
and nothing changes.

## How the set was found

The set is OpenTUI 0.8.4's (the version `../chord` installs), and it lives
in OpenTUI's native code. A throwaway bun script, outside both
repositories, imported `@opentui/core` and `@opentui/core/testing` from
`../chord/node_modules`, opened `createTestRenderer`, added one
`TextRenderable` of a fixed width in `wrapMode: "word"` per probe,
rendered twice and read `captureCharFrame()`. Each ASCII punctuation
character, tab, the Unicode spaces and a sample of Unicode punctuation was
put in `ab abc<c>defghij` at width 10, then targeted cases (edge, runs,
overlong words, CJK, kana, Hangul, emoji). The results are
[opentui-break-set.txt](evidence/CTUI-57/opentui-break-set.txt) and
[opentui-wrap-cases.txt](evidence/CTUI-57/opentui-wrap-cases.txt). The
probes agree with OpenTUI's source at tag v0.8.4,
`packages/native/src/utf8.zig` (`isAsciiWrapBreak`,
`unicodeLayoutWrapBreakKind`, `isCjkWordCodepoint`,
`isCjkIntercharacterBreak`, `isCjkAsciiTransition`), which settles the
ranges the probes only sampled.

## The break set

A break opportunity is a place between two graphemes where a row may end.

| Kind | Graphemes | Where the row may end | At the break |
| --- | --- | --- | --- |
| whitespace | space, tab, U+00A0, U+1680, U+2000–U+200A, U+200B, U+202F, U+205F, U+3000 | after it | dropped: not drawn at the row's end nor the next row's start |
| punctuation | `- / \ . , ; : ! ? ( ) [ ] { }`, U+00AD, U+2010, U+3001, U+3002, U+FF01, U+FF0C, U+FF1A, U+FF1F | after it | stays at the end of the row before |
| CJK | between two CJK graphemes, except before U+3099, U+309A, U+30A0, U+30FB | between them | nothing dropped |
| script change | between a CJK grapheme and an ASCII word grapheme (`A–Z a–z 0–9 _`), either order | between them | nothing dropped |

A CJK grapheme is one whose first code point is in Han (U+3400–U+4DBF,
U+4E00–U+9FFF, U+F900–U+FAFF, U+20000–U+2A6DF, U+2A700–U+2EE5D,
U+2F800–U+2FA1F), Hiragana and Katakana (U+3040–U+30FF, U+31F0–U+31FF,
U+FF66–U+FF9D) or Hangul (U+1100–U+11FF, U+3130–U+318F, U+A960–U+A97F,
U+AC00–U+D7FF).

Not breaks, as OpenTUI: every other ASCII punctuation (`" # $ % & ' * + < =
> @ ^ _ \` | ~`), U+2011, en and em dashes, `…`, U+FF0F, U+2028, U+2029,
emoji. A break never falls before a punctuation grapheme: `(` ends a row
(`x (` / `abcdefghij` / `k)`).

What the probes show, with the rows OpenTUI draws:

| Source, width | Rows |
| --- | --- |
| `aaaa/bbbb/cccc/dddd/eeee`, 10 | `aaaa/bbbb/` `cccc/dddd/` `eeee` |
| `src/ui/app/App.tsx:12`, 8 | `src/ui/` `app/App.` `tsx:12` |
| `http://example.com/a/b`, 10 | `http://` `example.` `com/a/b` |
| `ab cd-efgh`, 4 | `ab` `cd-` `efgh` |
| `abcdefghi/jkl`, 10 | `abcdefghi/` `jkl` |
| `abcdefghij/kl`, 10 | `abcdefghij` `/kl` (no hanging: `/` does not fit, the overlong token is cut) |
| `abcdefghij.`, 10 | `abcdefghij` `.` |
| `ab abcdefg中hij`, 10 | `ab abcdefg` `中hij` |
| `ab あいうえおかき`, 10 | `ab あいう` `えおかき` |
| `ab 😀😀😀😀😀😀`, 10 | `ab` `😀😀😀😀😀` `😀` |

No grapheme hangs past the edge: a break character that does not fit is
not squeezed in; the row ends before it if there is an opportunity there,
else the token is cut at the width as today.

## Two more rules of OpenTUI's word wrap

The probes found two more differences in the same function. They are not
the break set, but they are OpenTUI's word wrap, which the original
specifies, and the lead took both into U1.

1. **A word wider than the row starts its own row, then is cut.** A word
   here is the run between two break opportunities. When it does not fit
   what is left of the row and is wider than the whole row, the row ends
   at the opportunity before it, the word starts a fresh row and is cut at
   the width there; a row that is still empty takes it at once. Today the
   framework continues it on the current row.

   | Source, width | OpenTUI | Framework today |
   | --- | --- | --- |
   | `ab abcdefghijkl`, 10 | `ab` `abcdefghij` `kl` | `ab abcdefg` `hijkl` |
   | `abcd abcdefghijkl`, 10 | `abcd` `abcdefghij` `kl` | `abcd abcde` `fghijkl` |
   | `x (abcdefghijk)`, 10 | `x (` `abcdefghij` `k)` | `x (abcdefg` `hijk)` |
   | `aaaa/bbbbbbbbbbbbbbb`, 10 | `aaaa/` `bbbbbbbbbb` `bbbbb` | `aaaa/bbbbb` `bbbbbbbbbb` |
   | `ab 😀😀😀😀😀😀`, 10 | `ab` `😀😀😀😀😀` `😀` | `ab 😀😀😀` `😀😀😀` |
   | `aaaaaaaaaaaa`, 5 | `aaaaa` `aaaaa` `aa` | the same |

   CJK runs break between their graphemes, so they never are overlong:
   `ab 中文中文中文中文` at 10 is `ab 中文中` / `文中文中文` in both.

2. **A whitespace run at a break is dropped whole.** Every whitespace
   grapheme of the run where a row ends is dropped, at the end of that row
   and at the start of the next. Today the spaces that did not fit start
   the next row. Leading whitespace of a source line, before any break, is
   kept in both, unless the word after it is overlong: then the row of only
   that whitespace ends before the word, its whitespace dropped, so the line
   starts with an empty row (found by tester in U3, 0b51d19).

   | Source, width | OpenTUI | Framework today |
   | --- | --- | --- |
   | `abcdefghij   kl`, 10 | `abcdefghij` `kl` | `abcdefghij` `  kl` |
   | `abcdefgh   ijk`, 10 | `abcdefgh` `ijk` | the same |
   | `ab    cdefghijkl`, 10 | `ab` `cdefghijkl` | the same |
   | `abcdefghi .`, 10 | `abcdefghi` `.` | the same |
   | `  indented longword here`, 10 | `  indented` `longword` `here` | the same |
   | `    xxxxxxxxxxxxxxx`, 10 | `` (empty) `xxxxxxxxxx` `xxxxx` | `    xxxxxx` `xxxxxxxxx` |
   | `  ab xxxxxxxxxxxxxxx`, 10 | `  ab` `xxxxxxxxxx` `xxxxx` | `  ab xxxxx` `xxxxxxxxxx` |
   | `  xxxxxxxx`, 10 | `  xxxxxxxx` | the same |

Both rules are for the same path as the break set: `TextLayout.compute`
without `keepSpaces`. `keepSpaces` keeps its own rules (it drops no space
and cuts a long word where it runs out), and Markdown paragraphs keep their
own overlong-word fallback, matched against the original in 5420954; they
take only the shared break rule.

## Where it applies

Default, no new parameter. Flutter's `Text` breaks lines by Unicode line
breaking with no switch for it, and OpenTUI's `<text>` wraps in `word` mode
by default; a Flutter reader expects `softWrap: true` to break a path at
`/`. Nothing in docs/decisions.md settles space-only breaking.

| Built on the layout | After U1 | Why |
| --- | --- | --- |
| `Text` (plain, rich and ANSI), `TextLayout.compute` with `softWrap` (default) | new breaks | the original's plain `<text>` |
| `softWrap: false`, `TextOverflow.ellipsis` and `middle` cuts | unchanged | no wrapping |
| `keepSpaces: true` (`Code`, `Diff`, code rows of selection layouts, the port's permission diff rows) | unchanged, spaces only | the original wraps code in `char` mode (`Reply.tsx`), not `word`; neither word set matches it, and code and diff evidence would churn for nothing |
| `Markdown` paragraphs (`wrapMarkdownLine`) | the same set | it already breaks after the ASCII punctuation, which is exactly OpenTUI's; it uses the shared rule instead of its own `_paragraphBreaks`, which adds the Unicode spaces, Unicode punctuation and CJK |
| `Markdown` tables (`table: true`) | unchanged | markdansi's whitespace-only cells and orphan tails (CTUI-4) |
| `TextArea`, `TextInput` | unchanged | the original's prompt is `wrapMode='char'`; input is one row |
| `Picker` labels, dialog text, the port's transcript rows, start hints, crash and failure screens | new breaks, through `Text` or `TextLayout.compute` | the original's `<text>` |

Selection and copy read source offsets, so a row ending after `/` copies
as the unbroken source: `TextLineSource.softBreak` marks it and nothing is
inserted or dropped (a dropped whitespace is still in the copied source,
as today).

## API

No public API is added or changed. `Glyph.isSpace` keeps its meaning (a
space or tab, the cells `keepSpaces` keeps and ellipsis trims). The rule
lives in a new internal file, `lib/src/text/wrap_breaks.dart`, not exported
by `lib/chorded_tui.dart`, used by `layout.dart` and `markdown_layout.dart`:

```dart
/// What a grapheme does at a word-wrap break, as OpenTUI's word wrap.
enum WrapBreak { none, whitespace, punctuation }

/// The break kind of [grapheme], by its first code point.
WrapBreak wrapBreakOf(String grapheme);

/// Whether a row may end between [before] and [after] without either
/// being a break character: two CJK graphemes, or CJK beside an ASCII
/// word grapheme.
bool breaksBetween(String before, String after);
```

The documentation changes:

```dart
/// Whether lines wrap; the [DefaultTextStyle]'s, else true, when null.
/// A line wraps after a space or a break character (`/`, `-`, `.`, and
/// the others OpenTUI's word wrap breaks after), between CJK graphemes,
/// and cuts a word wider than the line.
final bool? softWrap;
```

and `TextLayout.compute`'s: "Lays [span] out in [maxWidth] cells, wrapping
as `Text.softWrap` says. With [keepSpaces], wrapping breaks only at spaces
and drops none: ..." (the rest as today).

## Tests U1 needs

In a new `test/text/wrap_breaks_test.dart` and in `test/text_test.dart`,
through `TextLayout.compute` and through `Text` with the tester:

- every row of the probe table above, at its width, exactly; the
  CTUI-29 sentence at the port's 80-column room gives the original's two
  rows;
- every break character of the table breaks after itself at width 10 in
  `ab abc<c>defghij`, and every listed non-break does not (the same
  probe), whitespace kinds dropped at the break;
- a punctuation break keeps styles: the `/` keeps its span's style on the
  row before, the next row starts with the next span's;
- `TextLineSource` start, end and `softBreak` across a `/` break, and a
  selection copy across it gives the source unchanged;
- `keepSpaces: true` still breaks only at spaces (`a/b/c` code is cut,
  not broken at `/`); `softWrap: false`, ellipsis and middle unchanged;
- Markdown paragraphs get the Unicode additions (U+00A0, U+2010, U+3001)
  and tables still do not break at punctuation;
- every row of the two tables of OpenTUI's other rules, exactly, and the
  rows that are "the same" stay so; a whitespace run dropped at a break
  still copies whole from the source.

Expected to change: the last assertion of `test/widgets/markdown_wrap_test.dart`'s
`paragraph punctuation breaks retain styles and plain Text policy`
(`Text('prefix abc/defghijklmnop')` at 20 becomes `prefix abc/` /
`defghijklmnop`), and any framework or port test whose text has a break
character within a word at the wrap edge; each is updated to the
original's rows, and a port one is checked against `../chord` where it
draws that screen. The developer names every changed expectation in the
handover.

## Screen check

The designer looks at U1 with `dart run example/markdown_wrap.dart` and at
the CTUI-29 settings warning beside the original at 120x40 and 80x24
(setup in [u29b2a-look.md](evidence/CTUI-29/u29b2a-look.md)). Captures go
under `docs/design/evidence/CTUI-57/`.

## U1b: wrap-ansi's wrap

U1 is the original's `<text>`. Where the original wraps a string itself
before drawing it, it calls the `wrap-ansi` package, which breaks only at
spaces and has its own rules for a long word and for trimming. Since U1,
the port's sites that stand for those calls draw OpenTUI's word wrap
instead, which is why six of the port's tests changed. U1b is a port of
wrap-ansi into the framework, so those sites wrap as the original's do.

### Version and notice

`wrap-ansi@10.0.2`, as `../chord/bun.lock` pins it (with `string-width`
8.3.0). The new file `lib/src/text/wrap_ansi.dart` opens as `fzf.dart`
does: one line saying it ports wrap-ansi 10.0.2's `exec` and `wrapWord`
(https://github.com/chalk/wrap-ansi), then the package's MIT notice
verbatim: `Copyright (c) Sindre Sorhus <sindresorhus@gmail.com>
(https://sindresorhus.com)` and the permission and warranty paragraphs.

### API

A sibling of `TextLayout.compute` on `TextLayout`, returning the same
`TextLayout` (glyph rows, `lineSources`, `sourceText`), so selection,
painting and `rewrap` work on it unchanged. One glyph model; a second
break policy, because wrap-ansi's is not OpenTUI's.

```dart
/// Lays [span] out as the wrap-ansi package wraps a string to [columns]:
/// lines break only at a space, `\n` ends a line, and a tab moves to the
/// next multiple of 8 cells. With [hard], no row is wider than [columns]:
/// a word wider is cut. With [trim], the spaces at the start and end of
/// every row are dropped. Without [wordWrap], every row is filled to
/// [columns], cutting words wherever they reach it.
static TextLayout wrapAnsi(
  TextSpan span,
  int columns, {
  Style base = Style.plain,
  bool hard = false,
  bool trim = true,
  bool wordWrap = true,
});
```

The defaults are wrap-ansi's, so a call reads as the original's:
`wrapAnsi(hint, Math.max(1, width), { hard: true, trim: true })` is
`TextLayout.wrapAnsi(TextSpan(hint), math.max(1, width), hard: true)`.
`columns` below 1 is a `RangeError`; every original site clamps to 1
first, and so does every port site. ANSI text arrives as a span through
`parseAnsi`, as the port's sites already do; styles stay on their glyphs,
so wrap-ansi's closing and reopening of codes at row ends needs no port.
Widths are the framework's `graphemeWidth`. wrap-ansi also NFC-normalizes
the text; the port does not, as the framework's other text does not (a
composed and a decomposed cluster are one grapheme of the same width).

### The rules, from the source and the probes

Per hard line (`\n`, `\r\n`), after expanding tabs to 8-cell stops; probes
in [wrap-ansi-cases.txt](evidence/CTUI-57/wrap-ansi-cases.txt) (`ht` is
`hard, trim`, the form every listed site uses):

- Words are the runs between U+0020 spaces. Nothing else breaks: not
  `/`, not NBSP, not between CJK: `ab abc/defghij` at 10 is
  `ab abc/def` / `ghij`; `src/ui/app/App.tsx:12 x` at 8 is `src/ui/a` /
  `pp/App.t` / `sx:12 x`.
- A word that does not fit goes to the next row. With `hard`, a word
  wider than `columns` starts on the current row and is cut at the edge,
  unless starting it on a fresh row takes fewer rows (wrap-ansi's
  `breaksStartingThisLine` against `breaksStartingNextLine`):
  `ab abcdefghijkl` at 10 is `ab abcdefg` / `hijkl`;
  `abcdefgh abcdefghijklmnopqrstuvw` at 10 is `abcdefgh` / `abcdefghij` /
  `klmnopqrst` / `uvw`.
- `trim` drops leading and trailing spaces of every row, the first row
  included: `  indented longword here` at 10 is `indented` / `longword` /
  `here`; a line of only spaces is one empty row.
- Without `trim`, spaces are kept and one space joins words even at a
  row's start: `abcde fghij` at 5 is `abcde` / ` ` / `fghij`.
- Without `wordWrap` (with `hard`, `trim: false`, as settings_row), rows
  are filled and cut: `abcde fghij` at 5 is `abcde` / ` fghi` / `j`.
- Soft (`hard: false`): an overlong word overflows its own row:
  `ab abcdefghijkl` at 10 is `ab` / `abcdefghijkl`.
- An empty line is one empty row.

### wrapLine, the port's

`message.ts`'s `wrapLine` is chord's own, so it lives in the port, in
`example/chord/lib/ui/transcript/message.dart`, built on
`TextLayout.wrapAnsi`:

```dart
/// A line wrapped to [width], its indent kept on its first row: as much
/// of it as leaves a cell for the text, so no row is wider than [width].
List<List<Glyph>> wrapLine(TextSpan line, int width);
```

The indent is the line's leading whitespace, cut from its end until it is
at most `width - 1` cells; the rest of the line, its leading whitespace
dropped, is wrapped with `hard: true, trim: true` to
`max(1, width - indent)`, and the indent's glyphs go before the first
row's. Later rows start at column 0, as the original's do.

### Sites

| Original | Call | The port |
| --- | --- | --- |
| `crash.ts:53` | `hard, trim` | `ui/app/crash.dart:30`, has it |
| `agents.ts:392` agentTable | `hard` (trim by default) | `agents.dart:324`, has it |
| `start_layout.ts:41` | `hard, trim` | `ui/app/start_layout.dart:19`, has it |
| `message.ts:194` wrapLine | `hard, trim`, indent kept | not yet; its uses below |
| `tools.ts:220`, `:507` | wrapLine | `tools/tools.dart:140` headline rows, `:261` summary rows |
| `Tool.tsx:657` | wrapLine | `tools/tool.dart:279` terminal lines |
| `permission.ts:170` | wrapLine | `dialogs/permission.dart:88` `_wrappedLine`, `:96` |
| `permission.ts:231` | wrapLine, diff and gap rows' height | `dialogs/permission.dart:152` (today `keepSpaces`) and `permission_prompt.dart:62` height |
| `spend_table.ts:319` | `hard, trim` | not in the port |
| `background/view.ts:485`, `:1028` | `hard, trim`; wrapLine | not in the port |
| `settings_row.ts:91` | `hard, trim: false, wordWrap: false` | not in the port; the API covers it |
| `picker.ts:52`, `:96` choiceLines | `hard, trim`, hanging title | `pickers/picker.dart:122` title rows, `pickers/pickers.dart:479` hanging choices |
| `header.ts:136` resumed title facts | `hard, trim` | `header/compact.dart:81`, the `Text` of `ResumedHeader` when `wrap` |
| `Pickers.tsx:610` teams directories | `hard, trim`, rows counted | not in the port (no teams picker) |
| `plan.ts:161` noteLines, `PlanBox.tsx:107` | `hard, trim` | not in the port (no plan dialog) |

Other wrapLine uses (`Tool.tsx:507`, `:865`, `proposal.ts`,
`Transcript.tsx:692`, `Teams.tsx`, `RecordedReceipt.tsx`) have no port
screen yet; they take `wrapLine` when they come.

The last four rows were found after the first list; the lead added them
to U2. The rest of the original's pickers stay on U1's rule.

### Tests U1b needs

In `test/text/wrap_ansi_test.dart`: every row of
[wrap-ansi-cases.txt](evidence/CTUI-57/wrap-ansi-cases.txt) exactly, with
its options, except rows whose widths the framework measures differently
from string-width (none of the recorded rows: CJK is width 2 in both),
each left out with a comment if one is; styles stay on their glyphs
across a cut word and across rows (the recorded `\e[31m` row as a span);
`lineSources` across a soft break, a cut and a hard `\n`; a tab expanded
to the next 8-cell stop and kept in the source; `columns: 0` throws. In
the port, `wrapLine` keeps an indent on the first row only, shrinks an
indent wider than `width - 1`, and a row is never wider than `width`; and
each site in the table draws the original's rows for its recorded case,
which brings back the six tests U1 changed. New probes are made the same
way: a throwaway bun script in a temp directory outside both
repositories, importing `../chord/node_modules/wrap-ansi/index.js`.
