import 'package:meta/meta.dart';

/// A terminal colour: one of the 256 indexed colours, or 24-bit RGB.
@immutable
sealed class Color {
  const Color();

  /// SGR parameters that set this colour as the foreground.
  String get fgCode;

  /// SGR parameters that set this colour as the background.
  String get bgCode;
}

/// One of the terminal's 256 indexed colours.
final class IndexedColor extends Color {
  /// The colour at [index], from 0 to 255.
  const IndexedColor(this.index) : assert(index >= 0 && index < 256);

  /// The colour's place in the terminal's palette.
  final int index;

  @override
  String get fgCode => index < 8
      ? '${30 + index}'
      : index < 16
      ? '${90 + index - 8}'
      : '38;5;$index';

  @override
  String get bgCode => index < 8
      ? '${40 + index}'
      : index < 16
      ? '${100 + index - 8}'
      : '48;5;$index';

  @override
  bool operator ==(Object other) =>
      other is IndexedColor && other.index == index;

  @override
  int get hashCode => index;

  @override
  String toString() => 'IndexedColor($index)';
}

/// A 24-bit colour.
final class RgbColor extends Color {
  /// The colour of red [r], green [g] and blue [b], each 0 to 255.
  const RgbColor(this.r, this.g, this.b);

  /// Parses `#rrggbb`.
  factory RgbColor.hex(String hex) {
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    final v = int.parse(h, radix: 16);
    return RgbColor((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff);
  }

  /// The red channel, 0 to 255.
  final int r;

  /// The green channel, 0 to 255.
  final int g;

  /// The blue channel, 0 to 255.
  final int b;

  @override
  String get fgCode => '38;2;$r;$g;$b';

  @override
  String get bgCode => '48;2;$r;$g;$b';

  @override
  bool operator ==(Object other) =>
      other is RgbColor && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => 'RgbColor($r, $g, $b)';
}

/// The 16 colours every terminal has; their exact look follows the theme.
abstract final class Colors {
  Colors._();

  /// Black.
  static const black = IndexedColor(0);

  /// Red.
  static const red = IndexedColor(1);

  /// Green.
  static const green = IndexedColor(2);

  /// Yellow.
  static const yellow = IndexedColor(3);

  /// Blue.
  static const blue = IndexedColor(4);

  /// Magenta.
  static const magenta = IndexedColor(5);

  /// Cyan.
  static const cyan = IndexedColor(6);

  /// White.
  static const white = IndexedColor(7);

  /// Gray, the bright black.
  static const gray = IndexedColor(8);

  /// Bright red.
  static const brightRed = IndexedColor(9);

  /// Bright green.
  static const brightGreen = IndexedColor(10);

  /// Bright yellow.
  static const brightYellow = IndexedColor(11);

  /// Bright blue.
  static const brightBlue = IndexedColor(12);

  /// Bright magenta.
  static const brightMagenta = IndexedColor(13);

  /// Bright cyan.
  static const brightCyan = IndexedColor(14);

  /// Bright white.
  static const brightWhite = IndexedColor(15);
}

const _bold = 1;
const _dim = 2;
const _italic = 4;
const _underline = 8;
const _inverse = 16;
const _strike = 32;

/// How a cell is drawn: colours and attributes.
@immutable
class Style {
  /// A style with colours [fg] and [bg] and the attributes set.
  const Style({
    this.fg,
    this.bg,
    bool bold = false,
    bool dim = false,
    bool italic = false,
    bool underline = false,
    bool inverse = false,
    bool strikethrough = false,
  }) : _attrs =
           (bold ? _bold : 0) |
           (dim ? _dim : 0) |
           (italic ? _italic : 0) |
           (underline ? _underline : 0) |
           (inverse ? _inverse : 0) |
           (strikethrough ? _strike : 0);

  const Style._(this.fg, this.bg, this._attrs);

  /// No colour and no attribute: the terminal's default.
  static const plain = Style();

  /// Bold, alone.
  static const bold = Style(bold: true);

  /// Dim, alone.
  static const dim = Style(dim: true);

  /// Italic, alone.
  static const italic = Style(italic: true);

  /// Underlined, alone.
  static const underline = Style(underline: true);

  /// Foreground and background swapped, alone.
  static const inverse = Style(inverse: true);

  /// Struck through, alone.
  static const strikethrough = Style(strikethrough: true);

  /// The foreground colour; the terminal's default when null.
  final Color? fg;

  /// The background colour; the terminal's default when null.
  final Color? bg;
  final int _attrs;

  /// Whether the text is bold.
  bool get isBold => _attrs & _bold != 0;

  /// Whether the text is dim.
  bool get isDim => _attrs & _dim != 0;

  /// Whether the text is italic.
  bool get isItalic => _attrs & _italic != 0;

  /// Whether the text is underlined.
  bool get isUnderline => _attrs & _underline != 0;

  /// Whether foreground and background are swapped.
  bool get isInverse => _attrs & _inverse != 0;

  /// Whether the text is struck through.
  bool get isStrikethrough => _attrs & _strike != 0;

  /// [other] drawn over this: its colours win where set, attributes add up.
  Style merge(Style? other) {
    if (other == null) return this;
    return Style._(other.fg ?? fg, other.bg ?? bg, _attrs | other._attrs);
  }

  /// This style with [fg] or [bg] replaced where given.
  Style copyWith({Color? fg, Color? bg}) =>
      Style._(fg ?? this.fg, bg ?? this.bg, _attrs);

  /// The full SGR escape that resets and then applies this style.
  String get sgr {
    final p = <String>['0'];
    if (isBold) p.add('1');
    if (isDim) p.add('2');
    if (isItalic) p.add('3');
    if (isUnderline) p.add('4');
    if (isInverse) p.add('7');
    if (isStrikethrough) p.add('9');
    if (fg != null) p.add(fg!.fgCode);
    if (bg != null) p.add(bg!.bgCode);
    return '\x1b[${p.join(';')}m';
  }

  @override
  bool operator ==(Object other) =>
      other is Style &&
      other._attrs == _attrs &&
      other.fg == fg &&
      other.bg == bg;

  @override
  int get hashCode => Object.hash(fg, bg, _attrs);

  @override
  String toString() => 'Style(fg: $fg, bg: $bg, attrs: $_attrs)';
}
