<!-- Draft only. Not filed, not published. Target: github.com/dart-lang/tools, package:markdown. -->

# [markdown] Paragraph AST keeps each line's leading whitespace; only HtmlRenderer strips it

## Summary

`ParagraphSyntax.parse` builds the paragraph's inline content with `childLines.join('\n').trimRight()` (`lib/src/block_syntaxes/paragraph_syntax.dart:46`, markdown 7.3.1). The right end is trimmed, but the leading whitespace of the first line and of every continuation line stays in the content handed to the inline parser, so it ends up in the AST's `Text` nodes.

CommonMark 0.30 §4.8 (Paragraphs; same text and numbering in 0.31.2) says: "The paragraph's raw content is formed by concatenating the lines and removing initial and final whitespace." Examples 222 (`  aaa\n bbb`) and 223 (paragraphs), and example 636 (hard line breaks, `foo  \n     bar`, with the rule "Leading spaces at the beginning of the next line are ignored"), show that this whitespace is not part of the content.

`markdownToHtml` output is correct only because `HtmlRenderer.visitText` calls `trimLeft()` on each line of a text node that follows a `p`, `li` or `br` (`lib/src/html_renderer.dart:118-121`). Code that walks the AST from `Document.parse` (terminal renderers, custom renderers, editors) gets the whitespace and draws it. There is no option to change this.

## Reproduction

```dart
import 'package:markdown/markdown.dart';

String show(Node n) => n is Text
    ? '"${n.text.replaceAll('\n', r'\n')}"'
    : n is Element
        ? '${n.tag}(${(n.children ?? []).map(show).join(', ')})'
        : '$n';

void main() {
  for (final s in [' Late work 1.', ' **b** x', 'a  \n   b', 'aaa\n   bbb', '- i\n\n   x']) {
    final nodes = Document().parse(s);
    print('${s.replaceAll('\n', r'\n')} => ${nodes.map(show).join(' ')}'
        '   html: ${HtmlRenderer().render(nodes).replaceAll('\n', r'\n')}');
  }
}
```

Output with markdown 7.3.1:

```text
 Late work 1. => p(" Late work 1.")   html: <p>Late work 1.</p>
 **b** x => p(" ", strong("b"), " x")   html: <p><strong>b</strong> x</p>
a  \n   b => p("a", br(), "   b")   html: <p>a<br />\nb</p>
aaa\n   bbb => p("aaa\n   bbb")   html: <p>aaa\nbbb</p>
- i\n\n   x => ul(li(p("i"), p(" x")))   html: <ul>\n<li>\n<p>i</p>\n<p>x</p>\n</li>\n</ul>
```

## Expected

The AST should already match the HTML:

```text
 Late work 1. => p("Late work 1.")
 **b** x => p(strong("b"), " x")
a  \n   b => p("a", br(), "b")
aaa\n   bbb => p("aaa\nbbb")
- i\n\n   x => ul(li(p("i"), p("x")))
```

Indented and fenced code blocks are not affected. They keep their indentation in both the AST and the HTML, and that is correct.

## Suggested fix

In `ParagraphSyntax.parse`, strip leading spaces and tabs from each child line before joining (for example `childLines.map((l) => l.trimLeft())`, or a `[ \t]` only trim so that other Unicode whitespace stays). Once the AST is clean, the per-line `trimLeft()` in `HtmlRenderer.visitText` is no longer needed for paragraphs. It could stay as a no-op, or be removed in a follow-up once nothing else depends on it.

## Environment

- package:markdown 7.3.1
- Dart 3, any platform; the behaviour is in pure Dart parsing code.
