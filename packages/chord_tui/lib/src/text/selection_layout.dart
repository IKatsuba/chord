import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../foundation/selection_source.dart';
import '../foundation/text_editing.dart';
import '../terminal/style.dart';
import '../widgets/theme_data.dart';
import 'diff.dart';
import 'highlight.dart';
import 'layout.dart';
import 'markdown.dart';
import 'markdown_layout.dart';
import 'span.dart';
import 'wrap_ansi.dart';
import 'width.dart';

/// A painted glyph and its optional semantic grapheme origin.
@internal
@immutable
class SelectionGlyph {
  /// Positions a whole glyph in a row without making furniture selectable.
  const SelectionGlyph(this.x, this.glyph, {this.sourceId, this.offset});

  /// Cell column relative to the containing source.
  final int x;

  /// The exact glyph and syntax style used for rendering.
  final Glyph glyph;

  /// Opaque semantic fragment token, or null for furniture.
  final Object? sourceId;

  /// Source grapheme offset, shared by every expanded tab cell.
  final int? offset;
}

/// One rendered row, with source boundaries for blank rows and clamping.
@internal
@immutable
class SelectionRow {
  /// Retains immutable glyph and boundary maps.
  SelectionRow(
    List<SelectionGlyph> glyphs, {
    this.sourceId,
    this.start = 0,
    this.end = 0,
    this.hardBreak,
    this.softBreak = false,
    this.background,
    this.blankLane,
  }) : glyphs = List.unmodifiable(glyphs);

  /// Glyphs in painting order.
  final List<SelectionGlyph> glyphs;

  /// The row's semantic fragment, including a blank code row.
  final Object? sourceId;

  /// First source insertion boundary represented by the row.
  final int start;

  /// Source boundary past its final represented glyph.
  final int end;

  /// A real source newline after this row.
  final int? hardBreak;

  /// Whether wrapping continues on the following row.
  final bool softBreak;

  /// An optional whole-row tint, including nonselectable gutters.
  final Style? background;

  /// The eligible horizontal content lane for a genuine blank LF boundary.
  final (int, int)? blankLane;
}

/// Current copy projection for one semantic fragment, excluding hidden spans.
@internal
@immutable
class SelectionFragmentProjection {
  /// Keeps normalized allowed half-open grapheme intervals.
  SelectionFragmentProjection({
    required this.id,
    required this.text,
    required List<(int, int)> ranges,
    required List<Object> lineage,
    this.separatorBefore = '\n',
    List<int>? unitBoundaries,
  }) : _unitBoundaries = unitBoundaries == null
           ? null
           : List.unmodifiable(unitBoundaries),
       ranges = List.unmodifiable(_merge(ranges)),
       lineage = List.unmodifiable(lineage);

  /// Opaque source-local fragment identity.
  final Object id;

  /// Semantic text before wrapping, or the explicit rendered copy class.
  final String text;

  /// Allowed intervals; clipping and ellipses leave discontinuities.
  final List<(int, int)> ranges;

  /// Surviving parent tokens that authorize reconciliation.
  final List<Object> lineage;

  /// Explicit document separator before this fragment.
  final String separatorBefore;

  final List<int>? _unitBoundaries;
  late final List<int> _boundaries =
      _unitBoundaries ?? _graphemeBoundaries(text);

  /// The fragment's current grapheme length.
  int get length => _boundaries.length - 1;

  /// Extracts selected exposed intervals in copied-byte order, without reparsing.
  String extract(int start, int end) {
    final out = StringBuffer();
    var low = 0, high = ranges.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (ranges[mid].$2 <= start) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (var i = low; i < ranges.length && ranges[i].$1 < end; i++) {
      final (from, to) = ranges[i];
      final a = from > start ? from : start, b = to < end ? to : end;
      if (a < b) out.write(text.substring(_boundaries[a], _boundaries[b]));
    }
    return out.toString();
  }

  /// Uses another separator without mutating this source projection.
  SelectionFragmentProjection separated(String separator) =>
      SelectionFragmentProjection(
        id: id,
        text: text,
        ranges: ranges,
        lineage: lineage,
        separatorBefore: separator,
        unitBoundaries: _unitBoundaries,
      );
}

List<int> _graphemeBoundaries(String text) {
  final boundaries = <int>[0];
  var offset = 0;
  for (final grapheme in text.characters) {
    offset += grapheme.length;
    boundaries.add(offset);
  }
  return boundaries;
}

List<(int, int)> _merge(List<(int, int)> ranges) {
  final sorted = List.of(ranges)..sort((a, b) => a.$1.compareTo(b.$1));
  final result = <(int, int)>[];
  for (final range in sorted) {
    if (range.$1 >= range.$2) continue;
    if (result.isNotEmpty && range.$1 <= result.last.$2) {
      final last = result.removeLast();
      result.add((last.$1, range.$2 > last.$2 ? range.$2 : last.$2));
    } else {
      result.add(range);
    }
  }
  return result;
}

/// One authoritative set of glyph rows, semantic intervals and natural size.
@internal
@immutable
class SelectionLayout {
  /// Freezes rows and fragments independently of subsequent source revisions.
  SelectionLayout({
    required this.width,
    required List<SelectionRow> rows,
    required List<SelectionFragmentProjection> fragments,
    this.textLayout,
    Map<Object, Rect> codeBounds = const {},
    Map<Object, Rect> codeButtons = const {},
    Map<Object, Rect> codeRunButtons = const {},
    List<Rect>? hitRects,
  }) : codeBounds = Map.unmodifiable(codeBounds),
       codeButtons = Map.unmodifiable(codeButtons),
       codeRunButtons = Map.unmodifiable(codeRunButtons),
       hitRects = List.unmodifiable(
         hitRects ?? [Rect(0, 0, width, rows.length)],
       ),
       rows = List.unmodifiable(rows),
       fragments = List.unmodifiable(fragments);

  /// Natural cell width, before the parent's minimum constraints.
  final int width;

  /// Current glyphs and hard/soft break maps.
  final List<SelectionRow> rows;

  /// Semantic document order, independent of paint order.
  final List<SelectionFragmentProjection> fragments;

  /// The shared text layout when this is a single paragraph.
  final TextLayout? textLayout;

  /// Painted subtree hit surfaces, without expanding composite blank bounds.
  final List<Rect> hitRects;

  /// Current code-container bounds keyed by opaque code fragment identity.
  final Map<Object, Rect> codeBounds;

  /// Exact full-word copy controls, keyed by current code fragment identity.
  final Map<Object, Rect> codeButtons;

  /// Exact full-word run controls, keyed by current code fragment identity.
  final Map<Object, Rect> codeRunButtons;

  /// Natural number of rows.
  int get height => rows.length;

  /// Current full copy projection, useful for pure range tests.
  String get selectedText {
    final out = StringBuffer();
    var first = true;
    for (final fragment in fragments) {
      final text = fragment.extract(0, fragment.length);
      if (text.isEmpty) continue;
      if (!first) out.write(fragment.separatorBefore);
      out.write(text);
      first = false;
    }
    return out.toString();
  }
}

/// Shapes current source content without building or retaining a widget tree.
/// For Markdown, [gaps] is told the row of each blank row put between two
/// top-level blocks, in order, so a caller can cut the one layout there.
@internal
SelectionLayout shapeSelectionSource(
  SelectionSource source, {
  required int width,
  ThemeData? theme,
  Style base = Style.plain,
  String? language,
  bool? growing,
  CodeBlockId? selectedCodeBlock,
  List<int>? gaps,
}) {
  final palette = theme ?? ThemeData.plain();
  final geometry = selectionSourceGeometry(source);
  final nodes = selectionSourceNodes(source);
  final root = nodes.singleOrNull;
  return switch (selectionSourceKind(source)) {
    SelectionSourceKind.text => _text(
      selectionSourceSpan(source),
      root!.id,
      [source.id],
      width,
      base: base,
      align: geometry.align,
      softWrap: geometry.softWrap,
      overflow: geometry.overflow,
      maxLines: geometry.maxLines,
    ),
    SelectionSourceKind.code => _code(
      selectionSourceText(source),
      root!.id,
      [source.id],
      width,
      theme: palette,
      base: base,
      language: language,
      growing: growing ?? selectionSourceGrowing(source),
      lineNumbers: geometry.lineNumbers,
      softWrap: geometry.softWrap,
    ),
    SelectionSourceKind.diff => _diff(source, root!.id, width, palette, base),
    SelectionSourceKind.markdown => _MarkdownShape(
      source,
      palette,
      base,
      growing,
      selectedCodeBlock,
    ).blocks(nodes, width, [source.id], spaced: true, gaps: gaps),
    SelectionSourceKind.group => _group(
      source,
      width,
      palette,
      base,
      selectedCodeBlock,
    ),
  };
}

SelectionLayout _text(
  TextSpan span,
  Object id,
  List<Object> lineage,
  int width, {
  Style base = Style.plain,
  TextAlign align = TextAlign.left,
  bool softWrap = true,
  TextOverflow overflow = TextOverflow.clip,
  int? maxLines,
  int tabWidth = 4,
  bool keepSpaces = false,
  bool markdown = false,
}) {
  var layout = TextLayout.compute(
    span,
    base: base,
    maxWidth: width,
    softWrap: markdown ? false : softWrap,
    overflow: overflow,
    maxLines: maxLines,
    tabWidth: tabWidth,
    keepSpaces: keepSpaces,
  );
  if (markdown) layout = layout.rewrap((line) => wrapMarkdownLine(line, width));
  final natural = align == TextAlign.left || width >= unbounded
      ? layout.width
      : width;
  final boxWidth = natural < width ? natural : width;
  final rows = <SelectionRow>[];
  for (final (i, line) in layout.lines.indexed) {
    final x = switch (align) {
      TextAlign.left => 0,
      TextAlign.center => (boxWidth - TextLayout.lineWidth(line)) ~/ 2,
      TextAlign.right => boxWidth - TextLayout.lineWidth(line),
    };
    final row = _row(line, layout.lineSources[i], id, x: x);
    rows.add(
      SelectionRow(
        row.glyphs,
        sourceId: row.sourceId,
        start: row.start,
        end: row.end,
        hardBreak: row.hardBreak,
        softBreak: row.softBreak,
        blankLane: row.start == row.end && row.hardBreak != null
            ? (0, width < unbounded ? width : boxWidth)
            : null,
      ),
    );
  }
  return _projection(
    boxWidth,
    rows,
    layout.sourceText,
    id,
    lineage,
    textLayout: layout,
  );
}

SelectionRow _row(
  List<Glyph> glyphs,
  TextLineSource source,
  Object id, {
  int x = 0,
  int offset = 0,
  Style? background,
}) {
  final cells = <SelectionGlyph>[];
  for (final glyph in glyphs) {
    cells.add(
      SelectionGlyph(
        x,
        glyph,
        sourceId: glyph.sourceOffset == null ? null : id,
        offset: glyph.sourceOffset == null
            ? null
            : glyph.sourceOffset! + offset,
      ),
    );
    x += glyph.width;
  }
  return SelectionRow(
    cells,
    sourceId: id,
    start: source.start + offset,
    end: source.end + offset,
    hardBreak: source.hardBreak == null ? null : source.hardBreak! + offset,
    softBreak: source.softBreak,
    background: background,
  );
}

SelectionLayout _projection(
  int width,
  List<SelectionRow> rows,
  String text,
  Object id,
  List<Object> lineage, {
  TextLayout? textLayout,
  List<(int, int)> dropped = const [],
}) {
  final ranges = <(int, int)>[...dropped];
  final chars = text.characters.toList();
  for (final (i, row) in rows.indexed) {
    final visible = row.glyphs
        .where(
          (cell) =>
              cell.sourceId == id &&
              cell.offset != null &&
              cell.x >= 0 &&
              cell.x + cell.glyph.width <= width &&
              cell.glyph.width > 0,
        )
        .toList();
    for (final cell in visible) {
      ranges.add((cell.offset!, cell.offset! + 1));
    }
    if (i + 1 >= rows.length) continue;
    if (row.hardBreak case final at?) ranges.add((at, at + 1));
    if (row.softBreak && visible.isNotEmpty) {
      final next = rows[i + 1].glyphs.where(
        (cell) =>
            cell.sourceId == id &&
            cell.offset != null &&
            cell.x >= 0 &&
            cell.x + cell.glyph.width <= width,
      );
      if (next.isEmpty) continue;
      final start = visible.last.offset! + 1, end = next.first.offset!;
      if (start <= end &&
          end <= chars.length &&
          chars.sublist(start, end).every((g) => g == ' ' || g == '\t')) {
        ranges.add((start, end));
      }
    }
  }
  return SelectionLayout(
    width: width,
    rows: rows,
    textLayout: textLayout,
    fragments: [
      SelectionFragmentProjection(
        id: id,
        text: text,
        ranges: ranges,
        lineage: lineage,
      ),
    ],
  );
}

SelectionLayout _code(
  String text,
  Object id,
  List<Object> lineage,
  int width, {
  required ThemeData theme,
  required Style base,
  String? language,
  bool growing = false,
  bool lineNumbers = false,
  bool softWrap = true,
  bool charWrap = false,
}) {
  final lines = highlightLines(
    text,
    language,
    theme.code?.terminal,
    growing: growing,
  );
  final gutter = lineNumbers ? '${lines.length}'.length + 1 : 0;
  final mark = softWrap && !charWrap ? 2 : 0;
  final fixed = gutter + mark;
  final codeWidth = !softWrap || width >= unbounded
      ? unbounded
      : (width - fixed).clamp(0, unbounded);
  var layout = TextLayout.compute(
    TextSpan(
      '',
      children: [
        for (final (i, line) in lines.indexed) ...[
          if (i > 0) const TextSpan('\n'),
          line,
        ],
      ],
    ),
    base: base,
    maxWidth: charWrap ? unbounded : codeWidth,
    softWrap: softWrap && !charWrap,
    keepSpaces: true,
    tabWidth: 2,
  );
  if (charWrap && codeWidth < unbounded) {
    layout = layout.rewrap((line) => _charWrap(line, codeWidth));
  }
  final rows = <SelectionRow>[];
  var widest = 0, number = 0;
  for (final (i, glyphs) in layout.lines.indexed) {
    final first = i == 0 || !layout.lineSources[i - 1].softBreak;
    if (first) number++;
    final row = _row(glyphs, layout.lineSources[i], id, x: fixed);
    final decoration = base.merge(theme.dim);
    rows.add(
      SelectionRow(
        [
          if (first && lineNumbers)
            ..._glyphs('$number'.padLeft(gutter - 1), decoration),
          if (!first && mark > 0)
            SelectionGlyph(gutter, Glyph('↪', 1, decoration)),
          ...row.glyphs,
        ],
        sourceId: id,
        start: row.start,
        end: row.end,
        hardBreak: row.hardBreak,
        softBreak: row.softBreak,
        blankLane: row.start == row.end && row.hardBreak != null
            ? (fixed, width < unbounded ? width : fixed)
            : null,
      ),
    );
    final used = fixed + TextLayout.lineWidth(glyphs);
    if (used > widest) widest = used;
  }
  return _projection(
    width < unbounded ? width : widest,
    rows,
    layout.sourceText,
    id,
    lineage,
  );
}

/// [line] cut into rows of [room] cells by grapheme, as OpenTUI's
/// `wrapMode='char'` cuts: nothing dropped, a wide grapheme that does not
/// fit moved whole to the next row.
List<List<Glyph>> _charWrap(List<Glyph> line, int room) {
  final rows = <List<Glyph>>[[]];
  var used = 0;
  for (final glyph in line) {
    if (used > 0 && used + glyph.width > room) {
      rows.add([]);
      used = 0;
    }
    rows.last.add(glyph);
    used += glyph.width;
  }
  return rows;
}

List<SelectionGlyph> _glyphs(String text, Style style, {int x = 0}) {
  final cells = <SelectionGlyph>[];
  for (final glyph in TextLayout.compute(
    TextSpan(text),
    base: style,
    softWrap: false,
  ).lines.first) {
    cells.add(SelectionGlyph(x, glyph));
    x += glyph.width;
  }
  return cells;
}

SelectionLayout _diff(
  SelectionSource source,
  Object id,
  int width,
  ThemeData theme,
  Style base,
) {
  final view = selectionSourceDiff(source),
      geometry = selectionSourceGeometry(source);
  final gutter = view.numberWidth + 3;
  final codeWidth = _diffRoom(
    view,
    width,
    geometry.diffWrap,
    geometry.diffCodeInsetRight,
  );
  final rows = <SelectionRow>[];
  final selected = view.rows.whereType<DiffLine>().toList();
  final text = selected.map((row) => stripAnsi(row.text)).join('\n');
  final highlighted = <(int, bool), List<TextSpan>>{};
  final language = geometry.title == null
      ? null
      : pathLanguage(geometry.title!);
  var offset = 0, seen = 0, widest = 0;
  final dropped = <(int, int)>[];
  for (final row in view.rows) {
    if (row is DiffGap) {
      rows.add(
        SelectionRow(
          _glyphs('…', base.merge(theme.dim), x: view.numberWidth + 1),
        ),
      );
      continue;
    }
    final line = row as DiffLine;
    final changed = line.kind != DiffKind.context;
    final added = line.kind == DiffKind.added;
    final tint = theme.diff.tint;
    final sign = changed
        ? added
              ? theme.diff.added
              : theme.diff.removed
        : Style.plain;
    final own = !changed
        ? Style.plain
        : tint == null
        ? sign
        : (added ? tint.added : tint.removed).merge(tint.text);
    final onTint = changed && tint != null;
    final syntax = highlighted[(line.source, onTint)] ??= highlightLines(
      view.model.sources[line.source],
      language,
      onTint ? theme.code?.tint : theme.code?.terminal,
    );
    final span = changed && tint == null
        ? TextSpan(line.text)
        : line.line < syntax.length
        ? syntax[line.line]
        : TextSpan(line.text);
    final layout = _diffCode(
      span,
      base.merge(own),
      codeWidth,
      geometry.diffWrap,
    );
    // The wrap drops spaces (an indent cut short, a break, a trimmed end)
    // that copying must still give back, as the line is whole in source.
    final drawn = {
      for (final glyphs in layout.lines)
        for (final glyph in glyphs) ?glyph.sourceOffset,
    };
    for (final (at, glyph) in layout.sourceText.characters.indexed) {
      if (!drawn.contains(at) && glyph.trim().isEmpty) {
        dropped.add((offset + at, offset + at + 1));
      }
    }
    for (final (j, glyphs) in layout.lines.indexed) {
      final info = layout.lineSources[j];
      final mapped = _row(
        glyphs,
        TextLineSource(
          info.start,
          info.end,
          softBreak: info.softBreak,
          hardBreak: j == layout.lines.length - 1 && seen < selected.length - 1
              ? layout.sourceText.characters.length
              : null,
        ),
        id,
        x: gutter,
        offset: offset,
      );
      rows.add(
        SelectionRow(
          [
            if (j == 0) ...[
              ..._glyphs(
                '${line.number}'.padLeft(view.numberWidth),
                base.merge(theme.dim),
              ),
              ..._glyphs(
                changed
                    ? added
                          ? '+'
                          : '-'
                    : ' ',
                base.merge(own).merge(sign),
                x: view.numberWidth + 1,
              ),
            ],
            ...mapped.glyphs,
          ],
          sourceId: id,
          start: mapped.start,
          end: mapped.end,
          hardBreak: mapped.hardBreak,
          softBreak: mapped.softBreak,
          background: own.bg == null ? null : Style(bg: own.bg),
        ),
      );
      final used = gutter + TextLayout.lineWidth(glyphs);
      if (used > widest) widest = used;
    }
    seen++;
    offset += layout.sourceText.characters.length + 1;
  }
  var result = _projection(width < unbounded ? width : widest, rows, text, id, [
    source.id,
  ], dropped: dropped);
  if (geometry.showTitle && geometry.title != null) {
    final title = _text(
      TextSpan(geometry.title!),
      Object(),
      [],
      width,
      base: base.merge(theme.dim),
    );
    result = SelectionLayout(
      width: title.width > result.width ? title.width : result.width,
      rows: [
        ...title.rows.map(
          (row) => SelectionRow([
            for (final cell in row.glyphs) SelectionGlyph(cell.x, cell.glyph),
          ]),
        ),
        ...result.rows,
      ],
      fragments: result.fragments,
      hitRects: [
        ...title.hitRects,
        for (final rect in result.hitRects)
          Rect(rect.left, rect.top + title.height, rect.width, rect.height),
      ],
    );
  }
  return result;
}

/// The rows [view] takes at [width] with no title, as its diff source
/// shapes them: a gap one row, a line as many as its code wraps to.
@internal
int measureDiffView(
  DiffView view,
  int width,
  DiffWrap wrap, [
  int codeInsetRight = 0,
]) {
  final room = _diffRoom(view, width, wrap, codeInsetRight);
  var rows = 0;
  for (final row in view.rows) {
    rows += switch (row) {
      DiffGap() => 1,
      DiffLine(:final text) => _diffCode(
        TextSpan(text),
        Style.plain,
        room,
        wrap,
      ).lines.length,
    };
  }
  return rows;
}

/// The cells a diff line's code has beside its number and sign: at least
/// one in the original's wrap.
int _diffRoom(DiffView view, int width, DiffWrap wrap, int insetRight) {
  if (width >= unbounded) return unbounded;
  final room = width - view.numberWidth - 3 - insetRight;
  return switch (wrap) {
    DiffWrap.keepSpaces => room.clamp(0, unbounded),
    DiffWrap.wrapAnsi => room < 1 ? 1 : room,
  };
}

/// One diff line's code laid out to [room] cells, its tabs two spaces.
TextLayout _diffCode(TextSpan span, Style base, int room, DiffWrap wrap) {
  if (wrap == DiffWrap.keepSpaces || room >= unbounded) {
    return TextLayout.compute(
      span,
      base: base,
      maxWidth: room,
      keepSpaces: true,
      tabWidth: 2,
    );
  }
  return TextLayout.compute(
    span,
    base: base,
    softWrap: false,
    tabWidth: 2,
  ).rewrap((line) => _wrapLine(line, room));
}

/// The original's `wrapLine`: the indent kept on the first row, as much of
/// it as leaves a cell for code, and the rest wrapped by wrap-ansi with
/// `hard` and `trim` to the room the indent leaves.
List<List<Glyph>> _wrapLine(List<Glyph> line, int room) {
  bool blank(Glyph g) => g.text.runes.every(
    (c) => c != 0x85 && String.fromCharCode(c).trim().isEmpty,
  );
  var lead = 0;
  while (lead < line.length && blank(line[lead])) {
    lead++;
  }
  final indent = line.sublist(0, lead);
  while (indent.isNotEmpty && TextLayout.lineWidth(indent) > room - 1) {
    indent.removeLast();
  }
  final left = room - TextLayout.lineWidth(indent);
  final rows = wrapAnsiLine(
    line.sublist(lead),
    left < 1 ? 1 : left,
    hard: true,
    trim: true,
  );
  return [
    [...indent, ...rows.first],
    ...rows.skip(1),
  ];
}

/// The row, counted from [source]'s first at [width], where the part of it
/// whose id [where] accepts starts, its group's slots stacked as they are
/// drawn: a part's own place inside the whole, for a scroll to put it on
/// top. Null where no part matches.
int? selectionSourceRowOf(
  SelectionSource source, {
  required int width,
  required bool Function(Object id) where,
}) {
  if (where(source.id)) return 0;
  if (selectionSourceKind(source) != SelectionSourceKind.group) return null;
  var above = 0;
  for (final slot in selectionSourceSlots(source)) {
    final inner = width >= unbounded
        ? unbounded
        : (width - slot.insetLeft - slot.insetRight).clamp(0, unbounded);
    final found = selectionSourceRowOf(slot.source, width: inner, where: where);
    if (found != null) return above + found;
    above += shapeSelectionSource(slot.source, width: inner).height;
  }
  return null;
}

SelectionLayout _group(
  SelectionSource source,
  int width,
  ThemeData theme,
  Style base,
  CodeBlockId? selectedCodeBlock,
) {
  final layouts = <SelectionLayout>[];
  final separators = <String>[];
  for (final slot in selectionSourceSlots(source)) {
    final inner = width >= unbounded
        ? unbounded
        : (width - slot.insetLeft - slot.insetRight).clamp(0, unbounded);
    final shaped = shapeSelectionSource(
      slot.source,
      width: inner,
      theme: theme,
      base: base,
      selectedCodeBlock: selectedCodeBlock,
    );
    layouts.add(
      _inset(
        slot.selectable ? shaped : _withoutSelection(shaped),
        slot.insetLeft,
        slot.insetRight,
      ),
    );
    separators.add(slot.separatorBefore);
  }
  final result = _join(layouts, separators: separators);
  return SelectionLayout(
    width: result.width,
    rows: result.rows,
    hitRects: result.hitRects,
    codeBounds: result.codeBounds,
    codeButtons: result.codeButtons,
    codeRunButtons: result.codeRunButtons,
    fragments: [
      for (final fragment in result.fragments)
        SelectionFragmentProjection(
          id: fragment.id,
          text: fragment.text,
          ranges: fragment.ranges,
          lineage: [
            selectionSourceNodes(source).single.id,
            ...fragment.lineage,
          ],
          separatorBefore: fragment.separatorBefore,
        ),
    ],
  );
}

SelectionLayout _withoutSelection(SelectionLayout layout) => SelectionLayout(
  width: layout.width,
  rows: [
    for (final row in layout.rows)
      SelectionRow([
        for (final cell in row.glyphs) SelectionGlyph(cell.x, cell.glyph),
      ], background: row.background),
  ],
  fragments: const [],
  hitRects: const [],
);

SelectionLayout _inset(SelectionLayout child, int left, int right) =>
    SelectionLayout(
      width: left + child.width + right,
      hitRects: [
        for (final rect in child.hitRects)
          Rect(rect.left + left, rect.top, rect.width, rect.height),
      ],
      fragments: child.fragments,
      codeBounds: {
        for (final entry in child.codeBounds.entries)
          entry.key: Rect(
            entry.value.left + left,
            entry.value.top,
            entry.value.width,
            entry.value.height,
          ),
      },
      codeButtons: {
        for (final entry in child.codeButtons.entries)
          entry.key: Rect(
            entry.value.left + left,
            entry.value.top,
            entry.value.width,
            entry.value.height,
          ),
      },
      codeRunButtons: {
        for (final entry in child.codeRunButtons.entries)
          entry.key: Rect(
            entry.value.left + left,
            entry.value.top,
            entry.value.width,
            entry.value.height,
          ),
      },
      rows: [
        for (final row in child.rows)
          SelectionRow(
            [
              for (final cell in row.glyphs)
                SelectionGlyph(
                  cell.x + left,
                  cell.glyph,
                  sourceId: cell.sourceId,
                  offset: cell.offset,
                ),
            ],
            sourceId: row.sourceId,
            start: row.start,
            end: row.end,
            hardBreak: row.hardBreak,
            softBreak: row.softBreak,
            background: row.background,
            blankLane: row.blankLane == null
                ? null
                : (row.blankLane!.$1 + left, row.blankLane!.$2 + left),
          ),
      ],
    );

SelectionLayout _join(
  List<SelectionLayout> children, {
  List<String>? separators,
}) {
  final rows = <SelectionRow>[], fragments = <SelectionFragmentProjection>[];
  var width = 0;
  final hitRects = <Rect>[];
  final codeBounds = <Object, Rect>{};
  final codeButtons = <Object, Rect>{};
  final codeRunButtons = <Object, Rect>{};
  for (final (i, child) in children.indexed) {
    for (final rect in child.hitRects) {
      hitRects.add(
        Rect(rect.left, rect.top + rows.length, rect.width, rect.height),
      );
    }
    for (final entry in child.codeBounds.entries) {
      codeBounds[entry.key] = Rect(
        entry.value.left,
        entry.value.top + rows.length,
        entry.value.width,
        entry.value.height,
      );
    }
    for (final entry in child.codeButtons.entries) {
      codeButtons[entry.key] = Rect(
        entry.value.left,
        entry.value.top + rows.length,
        entry.value.width,
        entry.value.height,
      );
    }
    for (final entry in child.codeRunButtons.entries) {
      codeRunButtons[entry.key] = Rect(
        entry.value.left,
        entry.value.top + rows.length,
        entry.value.width,
        entry.value.height,
      );
    }
    if (child.width > width) width = child.width;
    rows.addAll(child.rows);
    fragments.addAll([
      for (final (j, fragment) in child.fragments.indexed)
        j == 0
            ? fragment.separated(
                fragments.isEmpty ? '' : separators?[i] ?? '\n',
              )
            : fragment,
    ]);
  }
  return SelectionLayout(
    width: width,
    rows: rows,
    fragments: fragments,
    hitRects: hitRects,
    codeBounds: codeBounds,
    codeButtons: codeButtons,
    codeRunButtons: codeRunButtons,
  );
}

class _MarkdownShape {
  _MarkdownShape(
    this.source,
    this.theme,
    this.base,
    this.growing,
    this.selectedCodeBlock,
  );
  final CodeBlockId? selectedCodeBlock;
  final bool? growing;
  final SelectionSource source;
  final ThemeData theme;
  final Style base;

  SelectionLayout blocks(
    List<SelectionSourceNode> nodes,
    int width,
    List<Object> lineage, {
    bool spaced = false,
    bool quoted = false,
    Style? textBase,
    List<int>? gaps,
  }) {
    final visible = nodes
        .where(
          (node) => node.block == null || markdownBlockVisible(node.block!),
        )
        .toList();
    final layouts = <SelectionLayout>[];
    for (final (i, node) in visible.indexed) {
      if (i > 0 && spaced) {
        gaps?.add(layouts.fold(0, (rows, layout) => rows + layout.rows.length));
        final gap = (visible[i - 1].id, node.id, 'gap');
        layouts.add(
          SelectionLayout(
            width: 0,
            rows: [SelectionRow(const [])],
            fragments: [
              SelectionFragmentProjection(
                id: gap,
                text: ' ',
                ranges: const [(0, 1)],
                lineage: lineage,
              ),
            ],
          ),
        );
      }
      layouts.add(
        block(node, width, lineage, quoted: quoted, textBase: textBase ?? base),
      );
    }
    return _join(layouts);
  }

  SelectionLayout block(
    SelectionSourceNode node,
    int width,
    List<Object> lineage, {
    bool quoted = false,
    required Style textBase,
  }) {
    final parents = [...lineage, node.id];
    final block = node.block;
    switch (block) {
      case MdParagraph(:final inlines):
        return _text(
          markdownSpans(inlines, theme),
          node.id,
          lineage,
          width,
          base: textBase.merge(theme.text),
          markdown: true,
        );
      case MdHeading(:final level, :final inlines):
        return _text(
          markdownSpans(inlines, theme),
          node.id,
          lineage,
          width,
          base: textBase
              .merge(theme.text)
              .merge(
                level == 1
                    ? const Style(bold: true, underline: true)
                    : Style.bold,
              ),
          markdown: true,
        );
      case MdDefinition(:final source):
        return _text(
          TextSpan(source),
          node.id,
          lineage,
          width,
          base: textBase.merge(theme.text),
          markdown: true,
        );
      case MdRule():
        return SelectionLayout(
          width: width < 40 ? width : 40,
          rows: [SelectionRow(_glyphs('—' * 40, textBase.merge(theme.dim)))],
          fragments: const [],
        );
      case MdCode(:final code, :final language, :final complete):
        var widest = 0;
        for (final line in code.split('\n')) {
          final used = cellWidth(line.replaceAll('\t', '  '));
          if (used > widest) widest = used;
        }
        // The original's box: a border and a cell of padding each side, and
        // a label shown only where it fits between rules (markdown.ts codeOf).
        final labelled = language == null || language.isEmpty
            ? 0
            : cellWidth(language) + 6;
        final geometry = selectionSourceGeometry(source);
        final labelCells = language == null || language.isEmpty
            ? 0
            : cellWidth(language) + 3;
        final copyMinimum = labelCells + 10;
        final runMinimum = labelCells + 9;
        final bothMinimum = labelCells + 16;
        final eligible = complete && !quoted;
        final wantsCopy = geometry.copyCodeBlocks && eligible;
        final wantsRun =
            geometry.runCodeBlockLanguages.contains(language) && eligible;
        final copy = wantsCopy && width >= copyMinimum;
        // The application retains keyboard access when narrower frames hide controls.
        final run = wantsRun && width >= (wantsCopy ? bothMinimum : runMinimum);
        final minimum = copy && run
            ? bothMinimum
            : copy
            ? copyMinimum
            : run
            ? runMinimum
            : 0;
        var wanted = widest + 4 > labelled ? widest + 4 : labelled;
        if (wanted < minimum) wanted = minimum;
        final frameWidth = width < wanted ? width : wanted;
        final picked =
            complete &&
            selectedCodeBlock?.sourceId == source.id &&
            selectionCodeFragment(selectedCodeBlock!) == node.id;
        final frameStyle = picked ? theme.accent : theme.border;
        final child = _code(
          code,
          node.id,
          lineage,
          frameWidth > 4 ? frameWidth - 4 : 0,
          theme: theme,
          base: base.merge(theme.text),
          language: fenceLanguage(language),
          charWrap: true,
          growing:
              (growing ?? selectionSourceGrowing(source)) &&
              identical(node, selectionSourceNodes(source).lastOrNull),
        );
        final height = child.height + 2;
        final rows = <SelectionRow>[];
        if (frameWidth >= 2) {
          rows.add(
            SelectionRow(_glyphs('┌${'─' * (frameWidth - 2)}┐', frameStyle)),
          );
          if (language != null &&
              language.isNotEmpty &&
              frameWidth >= labelled) {
            rows[0] = SelectionRow([
              ...rows[0].glyphs,
              ..._glyphs(' $language ', frameStyle, x: 2),
            ]);
          }
          if (copy) {
            rows[0] = SelectionRow([
              ...rows[0].glyphs,
              ..._glyphs(
                '[copy]',
                picked
                    ? theme.accent.merge(Style.bold)
                    : base.merge(theme.text),
                x: frameWidth - 8 - (run ? 6 : 0),
              ),
            ]);
          }
          if (run) {
            rows[0] = SelectionRow([
              ...rows[0].glyphs,
              ..._glyphs(
                '[run]',
                picked
                    ? theme.accent.merge(Style.bold)
                    : base.merge(theme.text),
                x: frameWidth - 7,
              ),
            ]);
          }
          for (final row in child.rows) {
            rows.add(
              SelectionRow(
                [
                  ..._glyphs('│', frameStyle),
                  for (final cell in row.glyphs)
                    SelectionGlyph(
                      cell.x + 2,
                      cell.glyph,
                      sourceId: cell.sourceId,
                      offset: cell.offset,
                    ),
                  ..._glyphs('│', frameStyle, x: frameWidth - 1),
                ],
                sourceId: row.sourceId,
                start: row.start,
                end: row.end,
                hardBreak: row.hardBreak,
                softBreak: row.softBreak,
                blankLane: row.blankLane == null
                    ? null
                    : (row.blankLane!.$1 + 2, row.blankLane!.$2 + 2),
              ),
            );
          }
          rows.add(
            SelectionRow(_glyphs('└${'─' * (frameWidth - 2)}┘', frameStyle)),
          );
        } else {
          rows.addAll([
            for (var i = 0; i < height; i++) SelectionRow(const []),
          ]);
        }
        final layout = SelectionLayout(
          width: frameWidth,
          rows: rows,
          fragments: frameWidth < 2 ? const [] : child.fragments,
          codeBounds: {node.id: Rect(0, 0, frameWidth, height)},
          codeButtons: {
            if (copy) node.id: Rect(frameWidth - 8 - (run ? 6 : 0), 0, 6, 1),
          },
          codeRunButtons: {if (run) node.id: Rect(frameWidth - 7, 0, 5, 1)},
        );
        return quoted ? _rendered(layout, node.id, lineage, width) : layout;
      case MdQuote() when !selectionSourceGeometry(source).quoteBars:
        return blocks(node.children, width, parents, textBase: textBase);
      case MdQuote():
        final inset = 2;
        final child = blocks(
          node.children,
          width >= unbounded ? unbounded : (width - inset).clamp(0, unbounded),
          parents,
          quoted: true,
          textBase: textBase.merge(theme.dim.merge(Style.italic)),
        );
        final prefixed = _prefix(child, '│ ', '│ ', theme.dim, width);
        return SelectionLayout(
          width: prefixed.width,
          rows: prefixed.rows,
          fragments: prefixed.fragments,
          hitRects: prefixed.hitRects,
          codeBounds: {
            for (final id in child.codeBounds.keys)
              id: Rect(0, 0, prefixed.width, prefixed.height),
          },
        );
      case MdList(:final ordered, :final start, :final loose, :final items):
        final children = <SelectionLayout>[];
        for (final (i, item) in items.indexed) {
          final marker = switch (item.checked) {
            true => '[x] ',
            false => '[ ] ',
            null => ordered ? '${start + i}. ' : '- ',
          };
          final itemNode = node.children[i];
          final child = blocks(
            itemNode.children,
            width >= unbounded
                ? unbounded
                : (width - cellWidth(marker)).clamp(0, unbounded),
            [...parents, itemNode.id],
            spaced: loose,
            quoted: quoted,
            textBase: textBase,
          );
          if (i > 0 && loose) {
            final gap = (node.children[i - 1].id, itemNode.id, 'gap');
            children.add(
              SelectionLayout(
                width: 0,
                rows: [SelectionRow(const [])],
                fragments: [
                  SelectionFragmentProjection(
                    id: gap,
                    text: ' ',
                    ranges: const [(0, 1)],
                    lineage: parents,
                  ),
                ],
              ),
            );
          }
          children.add(
            _prefix(child, marker, ' ' * cellWidth(marker), theme.dim, width),
          );
        }
        final layout = _join(children);
        return quoted ? _rendered(layout, node.id, lineage, width) : layout;
      case MdTable(:final header, :final rows, :final aligns):
        final lines = layoutMarkdownTable(
          maxWidth: width,
          header: [for (final cell in header) markdownSpans(cell, theme)],
          rows: [
            for (final row in rows)
              [for (final cell in row) markdownSpans(cell, theme)],
          ],
          aligns: aligns,
          base: textBase.merge(theme.text),
          border: theme.dim,
        );
        var widest = 0;
        for (final line in lines) {
          final used = TextLayout.lineWidth(line);
          if (used > widest) widest = used;
        }
        final layout = SelectionLayout(
          width: widest < width ? widest : width,
          rows: [
            for (final line in lines)
              SelectionRow([
                for (final cell in _row(
                  line,
                  const TextLineSource(0, 0),
                  Object(),
                ).glyphs)
                  SelectionGlyph(cell.x, cell.glyph),
              ]),
          ],
          fragments: const [],
        );
        return _rendered(layout, node.id, lineage, width);
      case null:
        return blocks(
          node.children,
          width,
          parents,
          quoted: quoted,
          textBase: textBase,
        );
    }
  }
}

SelectionLayout _prefix(
  SelectionLayout child,
  String first,
  String rest,
  Style style,
  int width,
) {
  final rows = child.rows.isEmpty ? [SelectionRow(const [])] : child.rows;
  final inset = cellWidth(first);
  return SelectionLayout(
    width: width < unbounded ? width : inset + child.width,
    hitRects: [
      Rect(0, 0, inset, rows.length),
      for (final rect in child.hitRects)
        Rect(rect.left + inset, rect.top, rect.width, rect.height),
    ],
    fragments: child.fragments,
    codeBounds: {
      for (final entry in child.codeBounds.entries)
        entry.key: Rect(
          entry.value.left + inset,
          entry.value.top,
          entry.value.width,
          entry.value.height,
        ),
    },
    codeButtons: {
      for (final entry in child.codeButtons.entries)
        entry.key: Rect(
          entry.value.left + inset,
          entry.value.top,
          entry.value.width,
          entry.value.height,
        ),
    },
    codeRunButtons: {
      for (final entry in child.codeRunButtons.entries)
        entry.key: Rect(
          entry.value.left + inset,
          entry.value.top,
          entry.value.width,
          entry.value.height,
        ),
    },
    rows: [
      for (final (i, row) in rows.indexed)
        SelectionRow(
          [
            ..._glyphs(i == 0 ? first : rest, style),
            for (final cell in row.glyphs)
              SelectionGlyph(
                cell.x + inset,
                cell.glyph,
                sourceId: cell.sourceId,
                offset: cell.offset,
              ),
          ],
          sourceId: row.sourceId,
          start: row.start,
          end: row.end,
          hardBreak: row.hardBreak,
          softBreak: row.softBreak,
          background: row.background,
          blankLane: row.blankLane == null
              ? null
              : (row.blankLane!.$1 + inset, row.blankLane!.$2 + inset),
        ),
    ],
  );
}

SelectionLayout _rendered(
  SelectionLayout layout,
  Object id,
  List<Object> lineage,
  int width,
) {
  final rows = <SelectionRow>[];
  final text = StringBuffer();
  var offset = 0;
  for (final (i, row) in layout.rows.indexed) {
    if (i > 0) {
      text.write('\n');
      offset++;
    }
    final start = offset;
    final cells = <SelectionGlyph>[];
    // Later glyphs, such as a code label over its border, win at each cell.
    final exposed = <int, SelectionGlyph>{};
    for (final cell in row.glyphs) {
      if (cell.x < 0 || cell.x + cell.glyph.width > width) continue;
      exposed[cell.x] = cell;
    }
    var x = 0;
    final positions = exposed.keys.toList()..sort();
    for (final at in positions) {
      if (at < x) continue;
      while (x < at) {
        final glyph = Glyph(' ', 1, Style.plain);
        cells.add(SelectionGlyph(x++, glyph, sourceId: id, offset: offset++));
        text.write(' ');
      }
      final glyph = exposed[at]!.glyph;
      cells.add(SelectionGlyph(x, glyph, sourceId: id, offset: offset++));
      text.write(glyph.text);
      x += glyph.width;
    }
    rows.add(
      SelectionRow(
        cells,
        sourceId: id,
        start: start,
        end: offset,
        hardBreak: i < layout.rows.length - 1 ? offset : null,
        background: row.background,
      ),
    );
  }
  final projected = _projection(
    layout.width,
    rows,
    text.toString(),
    id,
    lineage,
  );
  return SelectionLayout(
    width: projected.width,
    rows: projected.rows,
    fragments: projected.fragments,
    hitRects: layout.hitRects,
    codeBounds: layout.codeBounds,
    codeButtons: layout.codeButtons,
    codeRunButtons: layout.codeRunButtons,
  );
}

/// Maps the editor's existing controller layout without a second caret model.
@internal
SelectionLayout shapeTextAreaSelection({
  required Object id,
  required String text,
  required TextAreaLayout layout,
  Style base = Style.plain,
}) {
  final rows = <SelectionRow>[];
  final chars = text.characters.toList();
  final copy = StringBuffer();
  final boundaries = <int>[0];
  final ranges = <(int, int)>[];
  var codeUnits = 0;
  int append(String unit) {
    final offset = boundaries.length - 1;
    copy.write(unit);
    codeUnits += unit.length;
    boundaries.add(codeUnits);
    return offset;
  }

  for (var i = 0; i < layout.rows.length; i++) {
    final row = layout.rows[i];
    final continuesLine =
        i + 1 < layout.rows.length && layout.rows[i + 1].line == row.line;
    final shaped = TextLayout.compute(
      TextSpan(row.text),
      base: base,
      softWrap: false,
    );
    final sourceUnits = shaped.sourceText.characters.toList();
    final offsets = <int, int>{};
    final cells = <SelectionGlyph>[];
    final start = boundaries.length - 1;
    var x = 0;
    for (final glyph in shaped.lines.single) {
      final sourceOffset = glyph.sourceOffset;
      if (sourceOffset != null && glyph.width > 0) {
        // Copy offsets belong to actual displayed graphemes, never raw caret
        // offsets. Multiple expanded tab cells still name one source unit.
        final offset = offsets.putIfAbsent(
          sourceOffset,
          () => append(sourceUnits[sourceOffset]),
        );
        cells.add(SelectionGlyph(x, glyph, sourceId: id, offset: offset));
        if (x >= 0 && x + glyph.width <= layout.width) {
          ranges.add((offset, offset + 1));
        }
      }
      x += glyph.width;
    }
    final end = boundaries.length - 1;
    // Exact-width lines have an empty caret continuation at the same raw
    // boundary. Only the final visual piece owns that logical line's LF.
    final hardBreak =
        !continuesLine && row.end < chars.length && chars[row.end] == '\n';
    int? newline;
    if (hardBreak) {
      newline = append('\n');
      ranges.add((newline, newline + 1));
    }
    rows.add(
      SelectionRow(
        cells,
        sourceId: id,
        start: start,
        end: end,
        hardBreak: newline,
        softBreak: continuesLine,
        blankLane: start == end && newline != null ? (0, layout.width) : null,
      ),
    );
  }
  // Controller rows can keep regional indicators on separate soft rows even
  // though removing an intervening escape makes their copied string one flag.
  // Preserve those drawn grapheme units explicitly; the editor is untouched.
  return SelectionLayout(
    width: layout.width,
    rows: rows,
    fragments: [
      SelectionFragmentProjection(
        id: id,
        text: copy.toString(),
        ranges: ranges,
        lineage: [id],
        unitBoundaries: boundaries,
      ),
    ],
  );
}
