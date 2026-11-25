import 'package:meta/meta.dart';

import '../terminal/style.dart';

/// A run of text with a style, and optional children that inherit it.
@immutable
class TextSpan {
  /// A run of [text] in [style], with [children] after it.
  const TextSpan(this.text, {this.style, this.children = const []});

  /// The run's own text.
  final String text;

  /// The style the run and its children start from; inherited when null.
  final Style? style;

  /// The runs after this one, inheriting its style.
  final List<TextSpan> children;

  /// The runs of this tree, in order, each with its resolved style.
  List<(String, Style)> flatten([Style parent = Style.plain]) {
    final out = <(String, Style)>[];
    void walk(TextSpan s, Style inherited) {
      final st = inherited.merge(s.style);
      if (s.text.isNotEmpty) out.add((s.text, st));
      for (final c in s.children) {
        walk(c, st);
      }
    }

    walk(this, parent);
    return out;
  }

  /// The text of the whole tree, without styles.
  String toPlainText() => flatten().map((r) => r.$1).join();

  @override
  bool operator ==(Object other) {
    if (other is! TextSpan ||
        other.text != text ||
        other.style != style ||
        other.children.length != children.length) {
      return false;
    }
    for (var i = 0; i < children.length; i++) {
      if (other.children[i] != children[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(text, style, Object.hashAll(children));
}
