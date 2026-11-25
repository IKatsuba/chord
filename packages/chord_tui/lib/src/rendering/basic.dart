import '../foundation/geometry.dart';
import '../foundation/selection_source.dart';
import '../terminal/buffer.dart';
import '../terminal/style.dart';
import '../text/layout.dart';
import '../text/span.dart';
import '../text/selection_layout.dart';
import 'box.dart';
import 'paint_coverage.dart';

/// Insets its child by [padding], taking the padding into its own size.
class RenderPadding extends RenderBox with RenderWithChild {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderPadding);

  /// A box inset by [padding].
  RenderPadding(this.padding);

  /// The cells kept free on each side of the child.
  EdgeInsets padding;

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.constrain(Size(padding.horizontal, padding.vertical));
      return;
    }
    c.layout(constraints.deflate(padding));
    c.offset = Offset(padding.left, padding.top);
    size = Size(
      c.size.width + padding.horizontal,
      c.size.height + padding.vertical,
    );
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    paintChildren(canvas, origin);
  }
}

/// Adds its own constraints on top of the parent's: `SizedBox`, `ConstrainedBox`.
class RenderConstrainedBox extends RenderProxyBox {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderConstrainedBox);

  /// A box that also applies [additional].
  RenderConstrainedBox(this.additional);

  /// The constraints enforced within the parent's.
  BoxConstraints additional;

  @override
  void performLayout() {
    final c = additional.enforce(constraints);
    final ch = child;
    if (ch == null) {
      size = c.constrain(
        Size(
          c.hasBoundedWidth ? c.minWidth : 0,
          c.hasBoundedHeight ? c.minHeight : 0,
        ),
      );
      return;
    }
    ch.layout(c);
    ch.offset = Offset.zero;
    size = ch.size;
  }
}

/// Where a child sits in a larger box: `-1` is start, `0` centre, `1` end.
class Alignment {
  /// An alignment at [x] across and [y] down, each from `-1` to `1`.
  const Alignment(this.x, this.y);

  /// Across: `-1` is the left edge, `1` the right.
  final double x;

  /// Down: `-1` is the top edge, `1` the bottom.
  final double y;

  /// The top left corner.
  static const topLeft = Alignment(-1, -1);

  /// The middle of the top edge.
  static const topCenter = Alignment(0, -1);

  /// The top right corner.
  static const topRight = Alignment(1, -1);

  /// The middle of the left edge.
  static const centerLeft = Alignment(-1, 0);

  /// The centre.
  static const center = Alignment(0, 0);

  /// The middle of the right edge.
  static const centerRight = Alignment(1, 0);

  /// The bottom left corner.
  static const bottomLeft = Alignment(-1, 1);

  /// The middle of the bottom edge.
  static const bottomCenter = Alignment(0, 1);

  /// The bottom right corner.
  static const bottomRight = Alignment(1, 1);

  /// The child's offset when [free] cells are left around it, in whole cells.
  Offset along(Size free) => Offset(
    ((free.width) * (x + 1) / 2).floor(),
    ((free.height) * (y + 1) / 2).floor(),
  );

  @override
  bool operator ==(Object other) =>
      other is Alignment && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// Places its child within itself by [alignment], optionally sizing itself
/// to a multiple of the child.
class RenderAlign extends RenderBox with RenderWithChild {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderAlign);

  /// A box placing its child at [alignment].
  RenderAlign(this.alignment, {this.widthFactor, this.heightFactor});

  /// Where the child sits.
  Alignment alignment;

  /// The width as a multiple of the child's; null fills the bounded width.
  double? widthFactor;

  /// The height as a multiple of the child's; null fills the bounded height.
  double? heightFactor;

  @override
  void performLayout() {
    final c = child;
    final shrinkW = widthFactor != null || !constraints.hasBoundedWidth;
    final shrinkH = heightFactor != null || !constraints.hasBoundedHeight;
    if (c == null) {
      size = constraints.constrain(
        Size(
          shrinkW ? 0 : constraints.maxWidth,
          shrinkH ? 0 : constraints.maxHeight,
        ),
      );
      return;
    }
    c.layout(constraints.loosen());
    size = constraints.constrain(
      Size(
        shrinkW
            ? (c.size.width * (widthFactor ?? 1)).round()
            : constraints.maxWidth,
        shrinkH
            ? (c.size.height * (heightFactor ?? 1)).round()
            : constraints.maxHeight,
      ),
    );
    c.offset = alignment.along(
      Size(size.width - c.size.width, size.height - c.size.height),
    );
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    paintChildren(canvas, origin);
  }
}

/// Lays out and paints styled text, and holds its selection source.
class RenderParagraph extends RenderBox {
  /// A paragraph of [text].
  RenderParagraph(
    this.text, {
    this.selectionSource,
    this.style = Style.plain,
    this.align = TextAlign.left,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.maxLines,
  });

  /// The text, with its styles.
  TextSpan text;

  /// An explicit provider snapshot; null keeps automatic source ownership.
  SelectionSource? selectionSource;
  final Object _sourceId = Object();
  int _sourceRevision = 0;
  (TextSpan, TextAlign, bool, TextOverflow, int?)? _sourceInputs;
  SelectionSource? _automaticSource;
  SelectionLayout? _projection;
  (SelectionSource, Style, int)? _projectionKey;

  /// The current shared glyph and source maps, independent of viewport clipping.
  SelectionLayout get selectionLayout => _projection!;

  /// The exact current semantic snapshot for this paragraph.
  SelectionSource get effectiveSelectionSource =>
      selectionSource ?? _automaticSource!;

  /// The style under the text's own spans.
  Style style;

  /// How each row is aligned.
  TextAlign align;

  /// Whether lines wrap at the width.
  bool softWrap;

  /// What happens to text that does not fit.
  TextOverflow overflow;

  /// The most rows shown; null for no limit.
  int? maxLines;

  TextLayout? _layout;

  /// The rows of the last layout.
  TextLayout get textLayout => _layout!;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    var source = selectionSource;
    if (source == null) {
      final inputs = (text, align, softWrap, overflow, maxLines);
      if (_sourceInputs != inputs) {
        _automaticSource = SelectionSource.text(
          id: _sourceId,
          revision: _sourceRevision++,
          text: text,
          align: align,
          softWrap: softWrap,
          overflow: overflow,
          maxLines: maxLines,
          previous: _automaticSource,
        );
        _sourceInputs = inputs;
      }
      source = _automaticSource!;
    }
    final key = (source, style, constraints.maxWidth);
    if (_projectionKey != key) {
      _projection = shapeSelectionSource(
        source,
        width: constraints.maxWidth,
        base: style,
      );
      _projectionKey = key;
    }
    _layout = selectionLayout.textLayout!;
    size = Size(selectionLayout.width, selectionLayout.height);
  }

  @override
  PaintCoverage describePaintCoverage(Rect localClip) {
    final clip = localClip.intersect(Rect.fromOffsetSize(Offset.zero, size));
    return PaintCoverage(
      declaredFor: RenderParagraph,
      beforeChildren: [
        for (final (y, row) in selectionLayout.rows.indexed)
          for (final cell in row.glyphs)
            ?glyphCoverage(cell.x, y, cell.glyph.width, clip),
      ],
    );
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    final l = _layout;
    if (l == null) return;
    final c = canvas.clipped(Rect.fromOffsetSize(origin, size));
    // Only the lines inside the clip: a long reply cut to a few rows stays
    // cheap to paint.
    final first = c.clip.top - origin.y;
    final last = c.clip.bottom - origin.y;
    final end = last < l.lines.length ? last : l.lines.length;
    for (var y = first > 0 ? first : 0; y < end; y++) {
      final line = l.lines[y];
      final w = TextLayout.lineWidth(line);
      var x = switch (align) {
        TextAlign.left => 0,
        TextAlign.center => (size.width - w) ~/ 2,
        TextAlign.right => size.width - w,
      };
      for (final g in line) {
        if (origin.x + x >= c.clip.right) break;
        c.put(
          origin.x + x,
          origin.y + y,
          g.text,
          g.width,
          selectionGlyphStyle?.call(x, y, g.width, g.style) ?? g.style,
        );
        x += g.width;
      }
    }
  }
}

/// The characters a border is drawn with.
class BorderChars {
  /// A border drawn with these characters, corners and edges.
  const BorderChars(
    this.topLeft,
    this.top,
    this.topRight,
    this.left,
    this.right,
    this.bottomLeft,
    this.bottom,
    this.bottomRight,
  );

  /// The character for each corner and edge.
  final String topLeft,
      top,
      topRight,
      left,
      right,
      bottomLeft,
      bottom,
      bottomRight;

  /// Thin lines with square corners.
  static const single = BorderChars('┌', '─', '┐', '│', '│', '└', '─', '┘');

  /// Thin lines with rounded corners.
  static const rounded = BorderChars('╭', '─', '╮', '│', '│', '╰', '─', '╯');

  /// Double lines.
  static const double = BorderChars('╔', '═', '╗', '║', '║', '╚', '═', '╝');

  /// Thick lines.
  static const heavy = BorderChars('┏', '━', '┓', '┃', '┃', '┗', '━', '┛');

  /// Plain ASCII: `+`, `-` and `|`.
  static const ascii = BorderChars('+', '-', '+', '|', '|', '+', '-', '+');
}

/// A box's border: its characters and style.
class Border {
  /// A border of [chars] in [style].
  const Border({this.chars = BorderChars.single, this.style});

  /// Thin lines with square corners.
  static const single = Border();

  /// Thin lines with rounded corners.
  static const rounded = Border(chars: BorderChars.rounded);

  /// Double lines.
  static const double = Border(chars: BorderChars.double);

  /// Thick lines.
  static const heavy = Border(chars: BorderChars.heavy);

  /// Plain ASCII.
  static const ascii = Border(chars: BorderChars.ascii);

  /// The characters it is drawn with.
  final BorderChars chars;

  /// The border's style; null is the theme's border role, which
  /// `DecoratedBox` fills in.
  final Style? style;

  /// The same border in [style].
  Border withStyle(Style style) => Border(chars: chars, style: style);

  @override
  bool operator ==(Object other) =>
      other is Border && other.chars == chars && other.style == style;

  @override
  int get hashCode => Object.hash(chars, style);
}

/// A background, a border and a title around a child.
class RenderDecoratedBox extends RenderBox with RenderWithChild {
  /// A box with an optional [border], [title] and [background].
  RenderDecoratedBox({this.border, this.title, this.background});

  /// The border around the child; null for none.
  Border? border;

  /// The title set into the top border; null for none.
  String? title;

  /// The style filling the box; null leaves the cells as they are.
  Style? background;

  int get _inset => border == null ? 0 : 1;

  @override
  void visitPaintChildren(Offset origin, Rect clip, PaintChildVisitor visitor) {
    final visible = clip.intersect(Rect.fromOffsetSize(origin, size));
    visitChildren((child) => visitor(child, origin + child.offset, visible));
  }

  @override
  bool hitTestSelf(Offset position) => background != null || border != null;

  @override
  void performLayout() {
    final i = _inset;
    final c = child;
    final pad = EdgeInsets.all(i);
    if (c == null) {
      size = constraints.constrain(
        Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : 2 * i,
          constraints.hasBoundedHeight ? constraints.maxHeight : 2 * i,
        ),
      );
      return;
    }
    c.layout(constraints.deflate(pad));
    c.offset = Offset(i, i);
    size = Size(c.size.width + 2 * i, c.size.height + 2 * i);
  }

  @override
  PaintCoverage describePaintCoverage(Rect localClip) {
    final bounds = Rect.fromOffsetSize(Offset.zero, size);
    final rectangles = <Rect>[];
    if (background != null) rectangles.add(bounds.intersect(localClip));
    if (border != null && size.width >= 2 && size.height >= 2) {
      rectangles.addAll([
        Rect(0, 0, size.width, 1).intersect(localClip),
        Rect(0, size.height - 1, size.width, 1).intersect(localClip),
        Rect(0, 1, 1, size.height - 2).intersect(localClip),
        Rect(size.width - 1, 1, 1, size.height - 2).intersect(localClip),
      ]);
    }
    return PaintCoverage(
      declaredFor: RenderDecoratedBox,
      beforeChildren: rectangles.where((r) => !r.isEmpty).toList(),
    );
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    final r = Rect.fromOffsetSize(origin, size);
    final bg = background;
    if (bg != null) canvas.fill(r, bg);
    final b = border;
    if (b != null && size.width >= 2 && size.height >= 2) {
      final ch = b.chars;
      final st = b.style ?? Style.plain;
      final x0 = r.left, y0 = r.top, x1 = r.right - 1, y1 = r.bottom - 1;
      canvas.put(x0, y0, ch.topLeft, 1, st);
      canvas.put(x1, y0, ch.topRight, 1, st);
      canvas.put(x0, y1, ch.bottomLeft, 1, st);
      canvas.put(x1, y1, ch.bottomRight, 1, st);
      for (var x = x0 + 1; x < x1; x++) {
        canvas.put(x, y0, ch.top, 1, st);
        canvas.put(x, y1, ch.bottom, 1, st);
      }
      for (var y = y0 + 1; y < y1; y++) {
        canvas.put(x0, y, ch.left, 1, st);
        canvas.put(x1, y, ch.right, 1, st);
      }
      final t = title;
      if (t != null && t.isNotEmpty && size.width > 4) {
        final inner = canvas.clipped(Rect(x0 + 1, y0, size.width - 2, 1));
        inner.drawText(x0 + 1, y0, ' $t ', st.merge(Style.bold));
      }
    }
    paintChildren(canvas, origin);
  }
}
