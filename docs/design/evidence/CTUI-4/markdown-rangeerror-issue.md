# Draft: upstream issue for package:markdown

A draft for the owner to file at dart-lang/tools (package `markdown`). Not
filed; filing it is the owner's call.

---

**Title:** RangeError when a link reference definition ends right after `<`

**Package:** markdown 7.3.1 (latest at the time of writing), Dart 3.13.5.

**What happens:** parsing text whose link reference definition ends
directly after an opening `<` destination throws, instead of reading the
lines as a paragraph.

```dart
import 'package:markdown/markdown.dart';

void main() {
  for (final source in ['[a]: <', '[a]:\n  <', 'x\n\n[a]:\n<']) {
    markdownToHtml(source); // throws
  }
}
```

```text
RangeError (length): Invalid value: Not in inclusive range 0..5: 6
#0 ... LinkParser._parseBracketedDestination
```

It also throws in a list item (`- [a]: <`), in a block quote
(`> [a]: <`) and when a paragraph follows (`[a]: <\n\npara`). `[a]: <b`,
`[a]: < ` and `[a]: <\nb` parse without error.

**Expected:** per CommonMark, an unclosed `<` destination makes no
definition, so the lines are a paragraph: `<p>[a]: &lt;</p>`.

**Why it matters:** an app that renders streamed text (a model's reply
arriving in chunks) parses every prefix, so any reply that writes a
definition like `[a]: <https://…>` crashes when a chunk ends after the `<`.

**Cause, as far as we read it:** `_parseBracketedDestination` advances past
the end of the input when the `<` is the last character of the definition's
text, without checking the bound.
