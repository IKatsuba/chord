import '../terminal/style.dart';
import 'span.dart';

final _seq = RegExp(
  r'\x1b\[([0-9;]*)m|\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)',
);

/// Turns text with SGR escape sequences, such as tool output, into spans.
///
/// Sequences other than SGR are dropped.
TextSpan parseAnsi(String input, {Style base = Style.plain}) {
  final spans = <TextSpan>[];
  var style = base;
  var last = 0;
  for (final m in _seq.allMatches(input)) {
    if (m.start > last) {
      spans.add(TextSpan(input.substring(last, m.start), style: style));
    }
    last = m.end;
    final params = m.group(1);
    if (params == null) continue;
    style = _apply(style, base, params);
  }
  if (last < input.length) {
    spans.add(TextSpan(input.substring(last), style: style));
  }
  return TextSpan('', children: spans);
}

Style _apply(Style s, Style base, String params) {
  final p = params.isEmpty
      ? [0]
      : params.split(';').map((e) => int.tryParse(e) ?? 0).toList();
  Color? fg = s.fg, bg = s.bg;
  var bold = s.isBold, dim = s.isDim, italic = s.isItalic;
  var underline = s.isUnderline,
      inverse = s.isInverse,
      strike = s.isStrikethrough;
  for (var i = 0; i < p.length; i++) {
    final c = p[i];
    switch (c) {
      case 0:
        fg = base.fg;
        bg = base.bg;
        bold = base.isBold;
        dim = base.isDim;
        italic = base.isItalic;
        underline = base.isUnderline;
        inverse = base.isInverse;
        strike = base.isStrikethrough;
      case 1:
        bold = true;
      case 2:
        dim = true;
      case 3:
        italic = true;
      case 4:
        underline = true;
      case 7:
        inverse = true;
      case 9:
        strike = true;
      case 22:
        bold = false;
        dim = false;
      case 23:
        italic = false;
      case 24:
        underline = false;
      case 27:
        inverse = false;
      case 29:
        strike = false;
      case >= 30 && <= 37:
        fg = IndexedColor(c - 30);
      case 39:
        fg = base.fg;
      case >= 40 && <= 47:
        bg = IndexedColor(c - 40);
      case 49:
        bg = base.bg;
      case >= 90 && <= 97:
        fg = IndexedColor(c - 90 + 8);
      case >= 100 && <= 107:
        bg = IndexedColor(c - 100 + 8);
      case 38 || 48:
        Color? color;
        if (i + 2 < p.length && p[i + 1] == 5) {
          color = IndexedColor(p[i + 2].clamp(0, 255));
          i += 2;
        } else if (i + 4 < p.length && p[i + 1] == 2) {
          color = RgbColor(p[i + 2], p[i + 3], p[i + 4]);
          i += 4;
        }
        if (c == 38) {
          fg = color;
        } else {
          bg = color;
        }
    }
  }
  return Style(
    fg: fg,
    bg: bg,
    bold: bold,
    dim: dim,
    italic: italic,
    underline: underline,
    inverse: inverse,
    strikethrough: strike,
  );
}
