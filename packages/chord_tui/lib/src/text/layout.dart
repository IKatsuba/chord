import 'package:characters/characters.dart';

import '../foundation/geometry.dart';
import '../terminal/style.dart';
import 'span.dart';
import 'width.dart';
import 'wrap_ansi.dart';
import 'wrap_breaks.dart';

/// One grapheme cluster placed on a line.
class Glyph {
  /// A grapheme [text] of [width] cells drawn with [style].
  const Glyph(this.text, this.width, this.style, {this.sourceOffset});

  /// The flattened source grapheme offset, or null for synthesized glyphs.
  final int? sourceOffset;

  /// The grapheme cluster.
  final String text;

  /// How many cells it takes.
  final int width;

  /// How it is drawn.
  final Style style;

  /// Whether it is a space or a tab, where a line may break.
  bool get isSpace => text == ' ' || text == '\t';
}

/// Where a line sits across its width.
enum TextAlign {
  /// Against the left edge.
  left,

  /// Centred, any odd cell on the right.
  center,

  /// Against the right edge.
  right,
}

/// What happens to text past the edge of its room.
enum TextOverflow {
  /// Cells past the edge are not drawn.
  clip,

  /// The last visible cell becomes `…`.
  ellipsis,

  /// Retains both ends around ASCII `...`, with complete graphemes.
  middle,
}

/// Source boundaries and break provenance for one visual text row.
class TextLineSource {
  /// Describes grapheme offsets, with an optional real newline after the row.
  const TextLineSource(
    this.start,
    this.end, {
    this.hardBreak,
    this.softBreak = false,
  });

  /// First source boundary in the row, including an empty source line.
  final int start;

  /// Source boundary past the row's glyphs before visual clipping.
  final int end;

  /// Source offset of a real line break following this row.
  final int? hardBreak;

  /// Whether wrapping, rather than a source newline, continues this row.
  final bool softBreak;
}

/// Text broken into lines that fit a width.
class TextLayout {
  TextLayout._(this.lines, this.width, this.sourceText, this.lineSources);

  /// The lines, each a run of placed glyphs.
  final List<List<Glyph>> lines;

  /// Plain source segmented across style boundaries, before soft wrapping.
  final String sourceText;

  /// Source and break provenance parallel to [lines].
  final List<TextLineSource> lineSources;

  /// The width of the widest line, in cells.
  final int width;

  /// How many lines there are.
  int get height => lines.length;

  /// The cells [line] takes.
  static int lineWidth(List<Glyph> line) {
    var w = 0;
    for (final g in line) {
      w += g.width;
    }
    return w;
  }

  /// Lays [span] out in [maxWidth] cells, wrapping as `Text.softWrap`
  /// says. With [keepSpaces], wrapping breaks only at spaces and drops
  /// none: spaces that do not fit start the next line, as code
  /// needs, where a space is part of what is shown.
  static TextLayout compute(
    TextSpan span, {
    Style base = Style.plain,
    int maxWidth = unbounded,
    bool softWrap = true,
    bool keepSpaces = false,
    TextOverflow overflow = TextOverflow.clip,
    int? maxLines,
    int tabWidth = 4,
  }) {
    RangeError.checkNotNegative(tabWidth, 'tabWidth');
    final (sourceText, paragraphs, starts, ends) = _hardLines(
      span,
      base,
      tabWidth,
    );

    final lines = <List<Glyph>>[];
    final lineSources = <TextLineSource>[];
    for (final (i, p) in paragraphs.indexed) {
      final wrapped =
          !softWrap || maxWidth >= unbounded || lineWidth(p) <= maxWidth
          ? [p]
          : _wrap(p, maxWidth, keepSpaces: keepSpaces);
      for (final (j, line) in wrapped.indexed) {
        lines.add(line);
        lineSources.add(
          TextLineSource(
            line.isEmpty ? starts[i] : line.first.sourceOffset!,
            line.isEmpty ? starts[i] : line.last.sourceOffset! + 1,
            hardBreak: j == wrapped.length - 1 && i < paragraphs.length - 1
                ? ends[i]
                : null,
            softBreak: j < wrapped.length - 1,
          ),
        );
      }
    }

    var truncatedByLines = false;
    if (maxLines != null && lines.length > maxLines) {
      lines.removeRange(maxLines, lines.length);
      lineSources.removeRange(maxLines, lineSources.length);
      truncatedByLines = true;
    }
    if (overflow == TextOverflow.ellipsis && maxWidth < unbounded) {
      for (var i = 0; i < lines.length; i++) {
        final last = i == lines.length - 1;
        if (lineWidth(lines[i]) > maxWidth || (last && truncatedByLines)) {
          lines[i] = _ellipsize(lines[i], maxWidth);
        }
      }
    }

    if (overflow == TextOverflow.middle && maxWidth < unbounded) {
      for (var i = 0; i < lines.length; i++) {
        if (lineWidth(lines[i]) > maxWidth) {
          lines[i] = _middle(lines[i], maxWidth, base);
        }
      }
    }

    var width = 0;
    for (final l in lines) {
      final w = lineWidth(l);
      if (w > width) width = w;
    }
    return TextLayout._(
      lines,
      width,
      sourceText,
      List.unmodifiable(lineSources),
    );
  }

  /// The flattened source, its glyphs by source line and each line's
  /// start and end offsets; a null [tabWidth] keeps each tab one glyph.
  static (String, List<List<Glyph>>, List<int>, List<int>) _hardLines(
    TextSpan span,
    Style base,
    int? tabWidth,
  ) {
    final runs = _plainStyledRuns(span, base);
    final sourceText = runs.map((run) => run.$1).join();
    final paragraphs = <List<Glyph>>[[]];
    final starts = [0], ends = <int>[];
    var sourceOffset = 0,
        codeUnits = 0,
        runIndex = 0,
        runEnd = runs.isEmpty ? 0 : runs.first.$1.length;
    for (final g in sourceText.characters) {
      while (runIndex + 1 < runs.length && codeUnits >= runEnd) {
        runIndex++;
        runEnd += runs[runIndex].$1.length;
      }
      final style = runs[runIndex].$2;
      codeUnits += g.length;
      final at = sourceOffset++;
      if (g == '\n' || g == '\r\n') {
        ends.add(at);
        starts.add(sourceOffset);
        paragraphs.add([]);
        continue;
      }
      if (g == '\t' && tabWidth == null) {
        paragraphs.last.add(Glyph(g, 0, style, sourceOffset: at));
        continue;
      }
      if (g == '\t') {
        for (var i = 0; i < tabWidth!; i++) {
          paragraphs.last.add(Glyph(' ', 1, style, sourceOffset: at));
        }
        continue;
      }
      final w = graphemeWidth(g);
      if (w == 0 && g.runes.first < 0x20) continue;
      paragraphs.last.add(Glyph(g, w, style, sourceOffset: at));
    }
    ends.add(sourceOffset);
    return (sourceText, paragraphs, starts, ends);
  }

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
  }) {
    if (columns < 1) throw RangeError.range(columns, 1, null, 'columns');
    final (sourceText, paragraphs, starts, ends) = _hardLines(span, base, null);
    final rows = <List<Glyph>>[];
    final sources = <TextLineSource>[];
    var widest = 0;
    for (final (i, p) in paragraphs.indexed) {
      final wrapped = wrapAnsiLine(
        p,
        columns,
        hard: hard,
        trim: trim,
        wordWrap: wordWrap,
      );
      for (final (j, row) in wrapped.indexed) {
        rows.add(row);
        sources.add(
          TextLineSource(
            row.isEmpty ? starts[i] : row.first.sourceOffset!,
            row.isEmpty ? starts[i] : row.last.sourceOffset! + 1,
            hardBreak: j == wrapped.length - 1 && i < paragraphs.length - 1
                ? ends[i]
                : null,
            softBreak: j < wrapped.length - 1,
          ),
        );
        final used = lineWidth(row);
        if (used > widest) widest = used;
      }
    }
    return TextLayout._(rows, widest, sourceText, List.unmodifiable(sources));
  }

  /// Rewraps hard source lines while retaining their glyph and break maps.
  TextLayout rewrap(List<List<Glyph>> Function(List<Glyph>) wrap) {
    final rows = <List<Glyph>>[];
    final sources = <TextLineSource>[];
    var widest = 0;
    for (final (i, line) in lines.indexed) {
      final wrapped = wrap(line);
      for (final (j, row) in wrapped.indexed) {
        rows.add(row);
        final original = lineSources[i];
        sources.add(
          TextLineSource(
            row.isEmpty ? original.start : row.first.sourceOffset!,
            row.isEmpty ? original.start : row.last.sourceOffset! + 1,
            softBreak: j < wrapped.length - 1,
            hardBreak: j == wrapped.length - 1 ? original.hardBreak : null,
          ),
        );
        final used = lineWidth(row);
        if (used > widest) widest = used;
      }
    }
    return TextLayout._(rows, widest, sourceText, List.unmodifiable(sources));
  }

  static List<List<Glyph>> _wrap(
    List<Glyph> p,
    int maxWidth, {
    bool keepSpaces = false,
  }) {
    if (maxWidth <= 0) return [[]];
    // Code keeps its spaces and breaks at them only; text breaks where
    // OpenTUI's word wrap does.
    bool white(Glyph g) =>
        keepSpaces ? g.isSpace : wrapBreakOf(g.text) == WrapBreak.whitespace;
    final out = <List<Glyph>>[];
    var line = <Glyph>[];
    var lineW = 0;

    void push() {
      while (!keepSpaces && line.isNotEmpty && white(line.last)) {
        lineW -= line.removeLast().width;
      }
      out.add(line);
      line = [];
      lineW = 0;
    }

    var i = 0;
    while (i < p.length) {
      if (white(p[i])) {
        if (lineW + p[i].width <= maxWidth) {
          line.add(p[i]);
          lineW += p[i].width;
        } else {
          push();
          if (keepSpaces) continue;
          // The whole run where the row ends goes, as OpenTUI drops it.
          while (i + 1 < p.length && white(p[i + 1])) {
            i++;
          }
        }
        i++;
        continue;
      }
      var j = i;
      var wordW = 0;
      while (j < p.length && !white(p[j])) {
        wordW += p[j].width;
        j++;
        if (keepSpaces || j == p.length) continue;
        if (wrapBreakOf(p[j - 1].text) == WrapBreak.punctuation ||
            breaksBetween(p[j - 1].text, p[j].text)) {
          break;
        }
      }
      if (lineW + wordW <= maxWidth) {
        line.addAll(p.sublist(i, j));
        lineW += wordW;
      } else if (wordW <= maxWidth) {
        push();
        line.addAll(p.sublist(i, j));
        lineW = wordW;
      } else {
        // A word longer than the line is broken where it runs out; text
        // starts it on a row of its own first, as OpenTUI does.
        if (!keepSpaces && line.isNotEmpty) push();
        for (var k = i; k < j; k++) {
          if (line.isNotEmpty && lineW + p[k].width > maxWidth) push();
          line.add(p[k]);
          lineW += p[k].width;
        }
      }
      i = j;
    }
    if (line.isNotEmpty || out.isEmpty) push();
    return out;
  }

  static List<Glyph> _middle(List<Glyph> line, int width, Style base) {
    if (width < 4) return [];
    final headBudget = (width - 3) ~/ 2;
    final tailBudget = width - 3 - headBudget;
    final head = <Glyph>[], tail = <Glyph>[];
    var used = 0;
    for (final glyph in line) {
      if (used + glyph.width > headBudget) break;
      head.add(glyph);
      used += glyph.width;
    }
    used = 0;
    for (final glyph in line.reversed) {
      if (used + glyph.width > tailBudget) break;
      tail.add(glyph);
      used += glyph.width;
    }
    return [
      ...head,
      for (var i = 0; i < 3; i++) Glyph('.', 1, base),
      ...tail.reversed,
    ];
  }

  static List<Glyph> _ellipsize(List<Glyph> line, int maxWidth) {
    if (maxWidth <= 0) return [];
    final out = <Glyph>[];
    var w = 0;
    for (final g in line) {
      if (w + g.width > maxWidth - 1) break;
      out.add(g);
      w += g.width;
    }
    while (out.isNotEmpty && out.last.isSpace) {
      out.removeLast();
    }
    final style = line.isEmpty
        ? Style.plain
        : (out.isEmpty ? line.first.style : out.last.style);
    out.add(Glyph('…', 1, style));
    return out;
  }
}

List<(String, Style)> _plainStyledRuns(TextSpan span, Style base) {
  final runs = span.flatten(base);
  final text = runs.map((run) => run.$1).join();
  final masks = ansiEscapeRanges(text).toList();
  if (masks.isEmpty) return runs;
  final clean = <(String, Style)>[];
  var runStart = 0, maskIndex = 0;
  for (final (part, style) in runs) {
    final runEnd = runStart + part.length;
    var cursor = runStart;
    final visible = StringBuffer();
    while (maskIndex < masks.length && masks[maskIndex].$2 <= runStart) {
      maskIndex++;
    }
    var current = maskIndex;
    while (current < masks.length && masks[current].$1 < runEnd) {
      final (from, to) = masks[current];
      if (cursor < from) {
        visible.write(text.substring(cursor, from < runEnd ? from : runEnd));
      }
      if (to > cursor) cursor = to;
      current++;
    }
    if (cursor < runEnd) visible.write(text.substring(cursor, runEnd));
    if (visible.isNotEmpty) clean.add((visible.toString(), style));
    runStart = runEnd;
  }
  return clean;
}
