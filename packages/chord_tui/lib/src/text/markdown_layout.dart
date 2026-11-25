import '../terminal/style.dart';
import '../widgets/theme_data.dart';
import 'layout.dart';
import 'markdown.dart';
import 'span.dart';
import 'width.dart';
import 'wrap_breaks.dart';

/// Inline display content, including the visible link address suffix.
TextSpan markdownSpans(List<MdInline> inlines, ThemeData theme) => TextSpan(
  '',
  children: [for (final inline in inlines) ..._inlineSpans(inline, theme)],
);

List<TextSpan> _inlineSpans(MdInline inline, ThemeData theme) =>
    switch (inline) {
      MdText(:final text) => [TextSpan(text)],
      MdStyled(:final kind, :final children) => [
        TextSpan(
          '',
          style: switch (kind) {
            MdEmphasis.strong => Style.bold,
            MdEmphasis.emphasis => Style.italic,
            MdEmphasis.strikethrough => Style.strikethrough,
          },
          children: [
            for (final child in children) ..._inlineSpans(child, theme),
          ],
        ),
      ],
      MdCodeSpan(:final code) => [TextSpan(code, style: theme.inlineCode)],
      MdLink(:final url, :final children) => _linkSpans(url, children, theme),
      MdImage() => const [],
      MdBreak() => const [TextSpan('\n')],
    };

List<TextSpan> _linkSpans(
  String url,
  List<MdInline> children,
  ThemeData theme,
) {
  final label = children.isEmpty
      ? [TextSpan(url)]
      : [for (final child in children) ..._inlineSpans(child, theme)];
  if (url.startsWith('mailto:')) return label;
  final text = TextSpan('', children: label).toPlainText();
  return [
    TextSpan('', style: theme.link.merge(Style.underline), children: label),
    if (url.isNotEmpty && text != url) TextSpan(' ($url)', style: theme.dim),
  ];
}

/// Whether [block] draws anything: a paragraph of only images does not.
bool markdownBlockVisible(MdBlock block) => switch (block) {
  MdParagraph(:final inlines) ||
  MdHeading(:final inlines) => inlines.any(_inlineShows),
  MdQuote(:final blocks) => blocks.any(markdownBlockVisible),
  _ => true,
};

bool _inlineShows(MdInline inline) => switch (inline) {
  MdText(:final text) => text.isNotEmpty,
  MdStyled(:final children) => children.any(_inlineShows),
  MdImage() => false,
  _ => true,
};

// Paragraphs break where OpenTUI's word wrap does; markdansi's tables
// instead carry short orphan phrases across whitespace boundaries.
final _orphanTail = RegExp(
  r'\b(?:(?:with|in|on|of|to|for)\s+(?:a|an|the)|a|an|the|to|of|with|and|or|in|on|for)$',
  caseSensitive: false,
);

/// [source] broken into rows of [width] cells, as Markdown paragraphs break.
List<List<Glyph>> wrapMarkdownLine(
  List<Glyph> source,
  int width, {
  bool table = false,
}) {
  if (width <= 0) return [[]];
  if (TextLayout.lineWidth(source) <= width) return [source];
  bool white(Glyph glyph) =>
      table ? glyph.isSpace : wrapBreakOf(glyph.text) == WrapBreak.whitespace;
  final tokens = <List<Glyph>>[];
  var token = <Glyph>[];
  for (final glyph in source) {
    if (token.isNotEmpty &&
        (white(token.last) != white(glyph) ||
            (!table && breaksBetween(token.last.text, glyph.text)))) {
      tokens.add(token);
      token = [];
    }
    token.add(glyph);
    if (!table && wrapBreakOf(glyph.text) == WrapBreak.punctuation) {
      tokens.add(token);
      token = [];
    }
  }
  if (token.isNotEmpty) tokens.add(token);
  final lines = <List<Glyph>>[];
  var current = <Glyph>[];
  var used = 0;
  List<Glyph> trimmed(List<Glyph> line) {
    var end = line.length;
    while (end > 0 && white(line[end - 1])) {
      end--;
    }
    return line.sublist(0, end);
  }

  void push() {
    lines.add(trimmed(current));
    current = [];
    used = 0;
  }

  for (final token in tokens) {
    final space = white(token.first);
    final tokenWidth = TextLayout.lineWidth(token);
    if (!space && current.isNotEmpty && used + tokenWidth > width) {
      var tailStart = current.length;
      if (table && white(current.last)) {
        final text = trimmed(current).map((g) => g.text).join();
        final match = _orphanTail.firstMatch(text);
        if (match != null) {
          var offset = 0;
          for (var i = 0; i < current.length; i++) {
            if (offset == match.start) {
              tailStart = i;
              break;
            }
            offset += current[i].text.length;
          }
        }
      }
      final head = trimmed(current.sublist(0, tailStart));
      if (tailStart < current.length && head.isNotEmpty) {
        lines.add(head);
        current = current.sublist(tailStart);
        used = TextLayout.lineWidth(current);
      } else {
        push();
      }
    }
    if (table || used + tokenWidth <= width) {
      current.addAll(token);
      used += tokenWidth;
    } else if (!space) {
      // Keep the existing hard-wrap fallback for an unbreakable word.
      for (final glyph in token) {
        if (used + glyph.width > width) push();
        current.add(glyph);
        used += glyph.width;
      }
    } else if (current.isNotEmpty) {
      push();
    }
  }
  if (current.isNotEmpty || lines.isEmpty) push();
  return lines;
}

const _maxColumn = 40;
const _minColumn = 4;

/// The existing Markdown grid and fallback, shared by both shaping paths.
List<List<Glyph>> layoutMarkdownTable({
  required int maxWidth,
  required List<TextSpan> header,
  required List<List<TextSpan>> rows,
  required List<MdAlign> aligns,
  required Style base,
  required Style border,
}) {
  final all = [header, ...rows];
  var columns = 0;
  for (final row in all) {
    if (row.length > columns) columns = row.length;
  }
  if (columns == 0) return const [];
  TextSpan cell(List<TextSpan> row, int i) =>
      i < row.length ? row[i] : const TextSpan('');

  final widths = List.filled(columns, 1);
  for (final row in all) {
    for (var i = 0; i < columns; i++) {
      final w = TextLayout.compute(cell(row, i), base: base).width + 2;
      final capped = w > _maxColumn ? _maxColumn : w;
      if (capped > widths[i]) widths[i] = capped;
    }
  }
  // The widest column gives way, a cell at a time, until the grid fits,
  // by chord's renderer's count: it takes each column's width as two
  // cells wider than it is drawn, so a grid gives way a little early.
  var over = widths.fold(3 * columns + 1, (a, b) => a + b) - maxWidth;
  while (over > 0) {
    var i = 0;
    for (var j = 1; j < columns; j++) {
      if (widths[j] > widths[i]) i = j;
    }
    if (widths[i] <= _minColumn) break;
    widths[i]--;
    over--;
  }
  for (var i = 0; i < columns; i++) {
    if (widths[i] < _minColumn) widths[i] = _minColumn;
  }

  // Cells wrap in their columns, unless a word is longer than its
  // column: then every cell is one line, cut with an ellipsis.
  var truncate = false;
  for (final row in all) {
    for (var i = 0; i < columns && !truncate; i++) {
      truncate = _longestWord(cell(row, i)) > widths[i] - 2;
    }
  }

  // An orphan phrase can overflow even when its individual words fit.
  // The original checks the wrapped table before choosing its fallback.
  if (!truncate) {
    for (final row in all) {
      for (var i = 0; i < columns && !truncate; i++) {
        final wrapped = [
          for (final line in TextLayout.compute(
            cell(row, i),
            softWrap: false,
          ).lines)
            ...wrapMarkdownLine(line, widths[i] - 2, table: true),
        ];
        truncate = wrapped.any(
          (line) => TextLayout.lineWidth(line) > widths[i] - 2,
        );
      }
    }
  }

  final lines = <List<Glyph>>[];
  List<Glyph> rule(String left, String middle, String right) => [
    Glyph(left, 1, border),
    for (var i = 0; i < columns; i++) ...[
      if (i > 0) Glyph(middle, 1, border),
      for (var k = 0; k < widths[i]; k++) Glyph('─', 1, border),
    ],
    Glyph(right, 1, border),
  ];
  void addRow(List<TextSpan> row, Style style) {
    final cells = [
      for (var i = 0; i < columns; i++)
        if (truncate)
          TextLayout.compute(
            cell(row, i),
            base: base.merge(style),
            maxWidth: widths[i] - 2,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ).lines
        else
          [
            for (final line in TextLayout.compute(
              cell(row, i),
              base: base.merge(style),
              softWrap: false,
            ).lines)
              ...wrapMarkdownLine(line, widths[i] - 2, table: true),
          ],
    ];
    var height = 1;
    for (final c in cells) {
      if (c.length > height) height = c.length;
    }
    for (var y = 0; y < height; y++) {
      final line = <Glyph>[Glyph('│', 1, border)];
      for (var i = 0; i < columns; i++) {
        final content = y < cells[i].length ? cells[i][y] : const <Glyph>[];
        final free = widths[i] - 2 - TextLayout.lineWidth(content);
        final left = switch (i < aligns.length ? aligns[i] : MdAlign.none) {
          MdAlign.right => free,
          MdAlign.center => free ~/ 2,
          _ => 0,
        };
        line
          ..addAll(_spaces(1 + left, base.merge(style)))
          ..addAll(content)
          ..addAll(_spaces(free - left + 1, base.merge(style)))
          ..add(Glyph('│', 1, border));
      }
      lines.add(line);
    }
  }

  lines.add(rule('┌', '┬', '┐'));
  addRow(header, Style.bold);
  lines.add(rule('├', '┼', '┤'));
  for (final row in rows) {
    addRow(row, Style.plain);
  }
  lines.add(rule('└', '┴', '┘'));
  return lines;
}

List<Glyph> _spaces(int n, Style style) => [
  for (var i = 0; i < n; i++) Glyph(' ', 1, style),
];

/// The widest run of non-space cells in [span].
int _longestWord(TextSpan span) {
  var longest = 0;
  for (final word in span.toPlainText().split(RegExp(r'\s+'))) {
    final w = cellWidth(word);
    if (w > longest) longest = w;
  }
  return longest;
}
