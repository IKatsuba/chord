import 'package:characters/characters.dart';

import '../foundation/text_editing.dart';
import '../terminal/style.dart';
import 'span.dart';

/// One frozen style projection onto an editor's unchanged raw graphemes.
class TextAreaSpanStyles {
  /// Validates exact text and resolves each grapheme's first-unit style.
  TextAreaSpanStyles(this.text, TextSpan span, {Style base = Style.plain}) {
    if (span.toPlainText() != text) {
      throw ArgumentError.value(
        span,
        'textSpanBuilder',
        'The span must contain the exact controller text.',
      );
    }
    final runs = span.flatten(base);
    final graphemes = <({String text, Style style})>[];
    var index = 0, runEnd = runs.isEmpty ? 0 : runs.first.$1.length;
    var offset = 0;
    for (final grapheme in text.characters) {
      while (index + 1 < runs.length && offset >= runEnd) {
        runEnd += runs[++index].$1.length;
      }
      graphemes.add((text: grapheme, style: runs[index].$2));
      offset += grapheme.length;
    }
    _graphemes = List.unmodifiable(graphemes);
  }

  /// Exact normalized controller text, with controls and ANSI retained.
  final String text;
  late final List<({String text, Style style})> _graphemes;

  /// Styles an actual viewport row without wrapping or cleaning its text;
  /// graphemes inside [selection] take [selectionStyle] over their own.
  TextSpan rowSpan(
    TextAreaRow row, {
    TextSelection? selection,
    Style? selectionStyle,
  }) => TextSpan(
    '',
    children: [
      for (var i = row.start; i < row.end; i++)
        TextSpan(
          _graphemes[i].text,
          style: selection != null && i >= selection.start && i < selection.end
              ? _graphemes[i].style.merge(selectionStyle)
              : _graphemes[i].style,
        ),
    ],
  );
}
