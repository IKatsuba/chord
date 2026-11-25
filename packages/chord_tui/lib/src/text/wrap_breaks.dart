/// Word-wrap break opportunities, as OpenTUI 0.8.4's word wrap finds them
/// (`packages/native/src/utf8.zig`), so text wraps where the original's
/// `<text>` does.
library;

/// What a grapheme does at a word-wrap break, as OpenTUI's word wrap.
enum WrapBreak {
  /// Not a break character.
  none,

  /// A row may end after it, and it is dropped at the break.
  whitespace,

  /// A row may end after it, and it stays at the end of that row.
  punctuation,
}

const _asciiPunctuation = r'-/\.,;:!?()[]{}';

/// The break kind of [grapheme], by its first code point.
WrapBreak wrapBreakOf(String grapheme) {
  if (grapheme.isEmpty) return WrapBreak.none;
  final c = grapheme.runes.first;
  if (c < 0x80) {
    if (c == 0x20 || c == 0x09) return WrapBreak.whitespace;
    return _asciiPunctuation.contains(grapheme[0])
        ? WrapBreak.punctuation
        : WrapBreak.none;
  }
  if (c == 0x00A0 ||
      c == 0x1680 ||
      (c >= 0x2000 && c <= 0x200B) ||
      c == 0x202F ||
      c == 0x205F ||
      c == 0x3000) {
    return WrapBreak.whitespace;
  }
  return switch (c) {
    0x00AD ||
    0x2010 ||
    0x3001 ||
    0x3002 ||
    0xFF01 ||
    0xFF0C ||
    0xFF1A ||
    0xFF1F => WrapBreak.punctuation,
    _ => WrapBreak.none,
  };
}

/// Whether a row may end between [before] and [after] without either
/// being a break character: two CJK graphemes, or CJK beside an ASCII
/// word grapheme.
bool breaksBetween(String before, String after) {
  if (before.isEmpty || after.isEmpty) return false;
  final a = before.runes.first, b = after.runes.first;
  final cjkA = _cjk(a), cjkB = _cjk(b);
  if (cjkA && cjkB) {
    // Sound marks and the middle dot attach to the kana before them.
    return b != 0x3099 && b != 0x309A && b != 0x30A0 && b != 0x30FB;
  }
  return (cjkA && _asciiWord(b)) || (cjkB && _asciiWord(a));
}

bool _asciiWord(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x5F;

bool _cjk(int c) =>
    // Han.
    (c >= 0x3400 && c <= 0x4DBF) ||
    (c >= 0x4E00 && c <= 0x9FFF) ||
    (c >= 0xF900 && c <= 0xFAFF) ||
    (c >= 0x20000 && c <= 0x2A6DF) ||
    (c >= 0x2A700 && c <= 0x2EE5D) ||
    (c >= 0x2F800 && c <= 0x2FA1F) ||
    // Hiragana and Katakana.
    (c >= 0x3040 && c <= 0x30FF) ||
    (c >= 0x31F0 && c <= 0x31FF) ||
    (c >= 0xFF66 && c <= 0xFF9D) ||
    // Hangul.
    (c >= 0x1100 && c <= 0x11FF) ||
    (c >= 0x3130 && c <= 0x318F) ||
    (c >= 0xA960 && c <= 0xA97F) ||
    (c >= 0xAC00 && c <= 0xD7FF);
