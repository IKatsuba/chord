/// JavaScript's `String.prototype.trim`, which the original's words go
/// through: Dart's `trim` also drops U+0085, which JavaScript keeps, and a
/// literal name may hold it. Dart's `\s` is JavaScript's.
library;

final _ends = RegExp(r'^\s+|\s+$');

/// [text] without JavaScript's whitespace at either end.
String jsTrim(String text) => text.replaceAll(_ends, '');
