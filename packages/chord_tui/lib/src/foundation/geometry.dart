import 'package:meta/meta.dart';

/// A length that stands for "no limit" in [BoxConstraints].
///
/// Terminal layout works in whole cells, so every length is an [int].
const int unbounded = 1 << 30;

/// A width and a height, in cells.
@immutable
class Size {
  /// A size [width] cells wide and [height] rows tall.
  const Size(this.width, this.height);

  /// No cells at all.
  static const zero = Size(0, 0);

  /// The number of columns.
  final int width;

  /// The number of rows.
  final int height;

  /// Whether it covers no cell.
  bool get isEmpty => width <= 0 || height <= 0;

  @override
  bool operator ==(Object other) =>
      other is Size && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'Size($width, $height)';
}

/// A position in cells: [x] columns right, [y] rows down.
@immutable
class Offset {
  /// The position [x] columns right and [y] rows down.
  const Offset(this.x, this.y);

  /// The origin, the top left cell.
  static const zero = Offset(0, 0);

  /// The column, from the left.
  final int x;

  /// The row, from the top.
  final int y;

  /// The two positions added, column by column and row by row.
  Offset operator +(Offset other) => Offset(x + other.x, y + other.y);

  /// This position less [other], column by column and row by row.
  Offset operator -(Offset other) => Offset(x - other.x, y - other.y);

  @override
  bool operator ==(Object other) =>
      other is Offset && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Offset($x, $y)';
}

/// A rectangle of cells: its top left corner and its size.
@immutable
class Rect {
  /// The rectangle at column [left] and row [top], [width] by [height].
  const Rect(this.left, this.top, this.width, this.height);

  /// The rectangle at [o] with size [s].
  factory Rect.fromOffsetSize(Offset o, Size s) =>
      Rect(o.x, o.y, s.width, s.height);

  /// The empty rectangle at the origin.
  static const zero = Rect(0, 0, 0, 0);

  /// The first column it covers.
  final int left;

  /// The first row it covers.
  final int top;

  /// How many columns it covers.
  final int width;

  /// How many rows it covers.
  final int height;

  /// The column just past its right edge.
  int get right => left + width;

  /// The row just below its bottom edge.
  int get bottom => top + height;

  /// Whether it covers no cell.
  bool get isEmpty => width <= 0 || height <= 0;

  /// Whether the cell at column [x], row [y] lies inside it.
  bool contains(int x, int y) =>
      x >= left && x < right && y >= top && y < bottom;

  /// The cells this rectangle shares with [o]; empty, at their meeting point, when none.
  Rect intersect(Rect o) {
    final l = left > o.left ? left : o.left;
    final t = top > o.top ? top : o.top;
    final r = right < o.right ? right : o.right;
    final b = bottom < o.bottom ? bottom : o.bottom;
    if (r <= l || b <= t) return Rect(l, t, 0, 0);
    return Rect(l, t, r - l, b - t);
  }

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'Rect($left, $top, $width, $height)';
}

/// Space around the four sides of a box, in cells.
@immutable
class EdgeInsets {
  /// Insets given side by side; a side left out is zero.
  const EdgeInsets.only({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  /// The same inset [v] on every side.
  const EdgeInsets.all(int v) : left = v, top = v, right = v, bottom = v;

  /// [horizontal] on the left and right, [vertical] on the top and bottom.
  const EdgeInsets.symmetric({int horizontal = 0, int vertical = 0})
    : left = horizontal,
      right = horizontal,
      top = vertical,
      bottom = vertical;

  /// No inset on any side.
  static const zero = EdgeInsets.all(0);

  /// Columns on the left.
  final int left;

  /// Rows on the top.
  final int top;

  /// Columns on the right.
  final int right;

  /// Rows on the bottom.
  final int bottom;

  /// The columns taken on the left and right together.
  int get horizontal => left + right;

  /// The rows taken on the top and bottom together.
  int get vertical => top + bottom;

  @override
  bool operator ==(Object other) =>
      other is EdgeInsets &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Constraints going down: the range of sizes a box may take, in cells.
@immutable
class BoxConstraints {
  /// Constraints between the given bounds; any bound left out is open.
  const BoxConstraints({
    this.minWidth = 0,
    this.maxWidth = unbounded,
    this.minHeight = 0,
    this.maxHeight = unbounded,
  });

  /// Constraints that admit [s] alone.
  BoxConstraints.tight(Size s)
    : minWidth = s.width,
      maxWidth = s.width,
      minHeight = s.height,
      maxHeight = s.height;

  /// Constraints that admit any size up to [s].
  BoxConstraints.loose(Size s)
    : minWidth = 0,
      maxWidth = s.width,
      minHeight = 0,
      maxHeight = s.height;

  /// Constraints fixing [width] and [height] where given, open where not.
  const BoxConstraints.tightFor({int? width, int? height})
    : minWidth = width ?? 0,
      maxWidth = width ?? unbounded,
      minHeight = height ?? 0,
      maxHeight = height ?? unbounded;

  /// The narrowest a box may be.
  final int minWidth;

  /// The widest a box may be; [unbounded] for no limit.
  final int maxWidth;

  /// The shortest a box may be.
  final int minHeight;

  /// The tallest a box may be; [unbounded] for no limit.
  final int maxHeight;

  /// Whether the width has a limit.
  bool get hasBoundedWidth => maxWidth < unbounded;

  /// Whether the height has a limit.
  bool get hasBoundedHeight => maxHeight < unbounded;

  /// Whether exactly one size is admitted.
  bool get isTight => minWidth == maxWidth && minHeight == maxHeight;

  /// The smallest size admitted.
  Size get smallest => Size(minWidth, minHeight);

  /// The biggest size admitted.
  Size get biggest => Size(maxWidth, maxHeight);

  /// [s] brought within these constraints.
  Size constrain(Size s) => Size(
    _clamp(s.width, minWidth, maxWidth),
    _clamp(s.height, minHeight, maxHeight),
  );

  /// These constraints with their minimums dropped to zero.
  BoxConstraints loosen() =>
      BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight);

  /// These constraints less the room [e] takes, never below zero.
  BoxConstraints deflate(EdgeInsets e) {
    int sub(int v, int d) =>
        v >= unbounded ? unbounded : (v - d < 0 ? 0 : v - d);
    final minW = sub(minWidth, e.horizontal);
    final minH = sub(minHeight, e.vertical);
    return BoxConstraints(
      minWidth: minW,
      maxWidth: _maxOf(minW, sub(maxWidth, e.horizontal)),
      minHeight: minH,
      maxHeight: _maxOf(minH, sub(maxHeight, e.vertical)),
    );
  }

  /// These constraints, narrowed to fit inside [outer].
  BoxConstraints enforce(BoxConstraints outer) => BoxConstraints(
    minWidth: _clamp(minWidth, outer.minWidth, outer.maxWidth),
    maxWidth: _clamp(maxWidth, outer.minWidth, outer.maxWidth),
    minHeight: _clamp(minHeight, outer.minHeight, outer.maxHeight),
    maxHeight: _clamp(maxHeight, outer.minHeight, outer.maxHeight),
  );

  @override
  bool operator ==(Object other) =>
      other is BoxConstraints &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth &&
      other.minHeight == minHeight &&
      other.maxHeight == maxHeight;

  @override
  int get hashCode => Object.hash(minWidth, maxWidth, minHeight, maxHeight);

  @override
  String toString() {
    String f(int v) => v >= unbounded ? '∞' : '$v';
    return 'BoxConstraints(w: ${f(minWidth)}..${f(maxWidth)}, '
        'h: ${f(minHeight)}..${f(maxHeight)})';
  }
}

int _maxOf(int a, int b) => a > b ? a : b;
