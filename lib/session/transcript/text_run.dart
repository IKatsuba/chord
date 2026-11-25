/// A reply's or a thought's text as it grows chunk by chunk.
///
/// The original appends with `last.text + chunk`, which JavaScript's ropes
/// make cheap and Dart's strings make quadratic; so the text is kept in one
/// buffer that every later snapshot shares.
library;

/// Text appended chunk by chunk; each snapshot is immutable and shares the
/// buffer.
final class TextRun {
  TextRun._(this._buffer, this.length);

  /// No text, the start of every run.
  static final empty = TextRun._(StringBuffer(), 0);

  final StringBuffer _buffer;

  /// How many UTF-16 code units the text holds.
  final int length;

  String? _text;

  /// This text with [more] after it. Appends in place when this is the
  /// buffer's latest snapshot; otherwise copies its own prefix first.
  TextRun plus(String more) {
    if (more.isEmpty) {
      return this;
    }

    // An empty run starts a buffer of its own, so [empty]'s never holds a
    // reply.
    final latest = length > 0 && _buffer.length == length;
    final buffer = latest ? _buffer : (StringBuffer()..write(text));

    buffer.write(more);

    return TextRun._(buffer, length + more.length);
  }

  /// The text, joined once per snapshot and cached.
  String get text {
    final cached = _text;

    if (cached != null) {
      return cached;
    }

    final all = _buffer.toString();

    return _text = all.length == length ? all : all.substring(0, length);
  }

  @override
  String toString() => text;
}
