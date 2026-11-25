# CTUI-5: Code and highlighting

A read-only code widget and pure highlighting module, shared by Markdown
and Diff. References: `../chord/src/ui/transcript/highlight.ts`,
`../chord/src/ui/transcript/Reply.tsx`, and CTUI-3's existing theme roles.
The public API does not expose a highlighting package or ANSI strings.

## Call site and API

```dart
Code(source, language: 'dart');
Code(source, language: pathLanguage('lib/app.dart'), lineNumbers: true);
Code(source, language: 'dart', softWrap: false);
final lines = highlightLines(source, fenceLanguage('DART example'),
    Theme.of(context).code?.terminal);
Text.rich(lines.first);

class Code extends StatefulWidget {
  const Code(this.source, {
    super.key,
    this.language,
    this.lineNumbers = false,
    this.softWrap = true,
  });
  final String source;
  final String? language;
  final bool lineNumbers;
  final bool softWrap;
}

String? fenceLanguage(String? label);
String? pathLanguage(String path);
List<TextSpan> highlightLines(String source, String? language, Tones? tones);
```

Code has no border, label, padding, focus or bindings. Markdown adds the
box; a tool adds its heading. Code takes its parent's width and its
content's height; an ancestor handles scrolling and folding through the
existing list and Actions APIs.

fenceLanguage trims and lowercases the first whitespace-delimited word,
returning it only if a registered grammar or alias knows it. Missing and
unknown labels return null. pathLanguage tries the lowercase extension,
then the lowercase basename, splitting both slash styles. No match returns
null. The target is the original's common highlight.js languages and
aliases. Report package coverage gaps; do not invent automatic detection.

highlightLines returns an unmodifiable list of independently styled
TextSpan trees, one per source line without newline characters. Joining
their plain text with `\n` reproduces source, including empty leading,
interior and trailing lines. Empty source gives one empty line. Highlight
the whole source before splitting so multiline comments and strings retain
grammar state. Null/unknown language or null tones returns plain spans;
null tones also disables syntax weight and slant.

Map grammar classes as highlight.ts's sheet does:

| Classes | Tones field |
| --- | --- |
| keyword, selector-tag, meta keyword | keyword |
| string, regexp, meta meta-string, char | string |
| number, literal | number |
| comment, quote, doctag | comment |
| title, section, selector-id, selector-class | title |
| type, built_in, class title | type |
| name, attr, attribute, variable, template-variable, property | name |
| meta, symbol, bullet, link, selector-attr, selector-pseudo | meta |

Emphasis and strong retain italic and bold when highlighting is enabled.
Unknown classes inherit their enclosing style. Cache at most 64 completed
results, insertion-order eviction, by source, resolved language and Tones
value. A hit returns the cached result. Width and numbering never invalidate
highlighting; tone changes do. Developer reports the maintained packages
tried and AOT/grammar results independently of this API.

## Layout and states

Merge inherited text style with theme.text, then token styles. theme.code
null means no syntax colour. Numbers and wrap marks use theme.dim. Tabs
occupy two spaces, as chord's diff does; source and highlighting results
remain unchanged. Optional line numbers start at 1 and align right to the
final logical line's digit width, followed by one space. Only the first
visual row gets a number.

softWrap defaults true, following Text's parameter name. Preserve source
spaces and wrap by cells without splitting graphemes, breaking long tokens
when necessary. Reserve a two-cell continuation prefix in the code column
on every row: two spaces on the first, `↪ ` thereafter. The number gutter
is blank on continuation rows. The marker is decoration, never source.
softWrap false removes that prefix and clips logical lines at the edge.

Zero width draws nothing. When too narrow for gutters, clip decorations to
the constraint; never paint beyond it. A wide grapheme that cannot fit is
clipped whole by the framework's text rules. Empty source is a blank row
(number 1 if requested). Unknown language has identical plain geometry.
Focus has no effect; height overflow is content for an ancestor to scroll.
There are no actions or new shortcuts-panel entries.

## Text sketches

Layout sketches, not captures. Remaining viewport rows are blank. This
source fits at 120 columns and wraps at 80; numbers and markers are dim,
code uses theme.code.terminal.

120x40:

```text
1   void main() {
2     print('A long message about terminal cells, 日本語, and keeping every grapheme together on screen.');
3   }
```

80x24, same source (the exact break follows cell measurement):

```text
1   void main() {
2     print('A long message about terminal cells, 日本語, and keeping every
  ↪ grapheme together on screen.');
3   }
```

Without numbers only the continuation prefix remains. A Markdown box
reserves border and padding before passing Code its width.

## Differences and checks

Code's marked wrapping is CTUI-5's requirement. main approved wrapping in
Markdown too: chord clips code boxes, leaving long code unreadable by
keyboard. softWrap false remains available. Copy/run buttons and picking
are the port's job in CTUI-16 and are outside this framework slice.

Check aliases and paths, unknown language, token classes, multiline tokens,
lossless splitting, cache hit/eviction and theme changes. Widget checks at
120x40 and 80x24 cover numbers, empty lines, whitespace, wide graphemes,
very narrow constraints, plain/dark/light themes and softWrap false.
Developer supplies a runnable visual fixture at handover; designer looks
only at handed-over units and captures before reviewer sees them.
