import 'package:highlighting/highlighting.dart' as hl;
import 'package:highlighting/languages/all.dart' as hl;

import '../terminal/style.dart';
import '../widgets/theme_data.dart';
import 'span.dart';

/// The grammar a code fence's label names, by its first word; null when the
/// label is missing or names no language the highlighter knows.
String? fenceLanguage(String? label) {
  final words = (label ?? '').trim().split(RegExp(r'\s+'));
  return _resolve(words.first.toLowerCase());
}

/// The grammar a file's extension names, or its whole name for one like
/// `Makefile`; null when the highlighter knows neither.
String? pathLanguage(String path) {
  final base = path.split(RegExp(r'[\\/]')).last.toLowerCase();
  final dot = base.lastIndexOf('.');
  // As node's extname: a leading dot alone (`.bashrc`) is no extension.
  final extension = dot > 0 ? base.substring(dot + 1) : '';
  return _resolve(extension) ?? _resolve(base);
}

/// [source]'s lines styled as [language] in [tones]: one span tree per line,
/// without line breaks, so each line can be drawn alone. Plain lines when
/// the language is null or unknown, or [tones] is null.
///
/// With [growing], [source] is taken to be a text still being appended to,
/// as a streamed code block is: only what follows the last complete line
/// highlighted before is highlighted, so a chunk costs the same however
/// long the text has grown. A token that would reach back over a line
/// break can then colour an earlier line differently from highlighting
/// the whole; once the text stops growing, a call without [growing]
/// highlights it whole.
List<TextSpan> highlightLines(
  String source,
  String? language,
  Tones? tones, {
  bool growing = false,
}) {
  final id = language == null ? null : _resolve(language.toLowerCase());
  if (id == null || tones == null) {
    return List.unmodifiable([
      for (final line in source.split('\n')) TextSpan(line),
    ]);
  }
  if (growing) return _streamed(source, id, tones);
  final key = (source, id, tones);
  final known = _highlighted[key];
  if (known != null) return known;

  final lines = highlightWhole(source, id, tones);
  if (_highlighted.length >= _remembered) {
    _highlighted.remove(_highlighted.keys.first);
  }
  return _highlighted[key] = lines;
}

/// [source] as grammar [id] in [tones], highlighted whole and remembered
/// nowhere: what [highlightLines] gives once a source stops growing. Not
/// exported; the tests compare against it.
List<TextSpan> highlightWhole(String source, String id, Tones tones) =>
    _split(_runs(hl.highlight.parse(source, languageId: id), tones));

/// The texts highlighted last: a screen draws again on every tick, and an
/// edit's diff colours both whole files, so the same text is not
/// highlighted twice while it stays in view.
final _highlighted = <(String, String, Tones), List<TextSpan>>{};

/// Enough for every block on a screen, few enough that memory stays small.
const _remembered = 64;

/// A source highlighted up to the end of its last complete line: its
/// lines, and the grammar's mode stack where that prefix ends.
class _Stream {
  _Stream(this.id, this.tones);

  final String id;
  final Tones tones;
  String prefix = '';
  List<TextSpan> lines = const [];
  hl.Mode? top;
}

/// The sources highlighted last, by prefix: a streamed reply grows one
/// code block chunk by chunk, and highlighting the whole block again on
/// every chunk costs more the longer it grows.
final _streams = <_Stream>[];

/// Enough for the blocks that grow on one screen at once.
const _streamsRemembered = 8;

/// [source]'s lines as [id] in [tones], highlighting only what follows the
/// longest complete-line prefix remembered: the new complete lines from the
/// mode stack the prefix ended in, then the trailing partial line from the
/// mode stack after them, which is not remembered since it may still grow.
List<TextSpan> _streamed(String source, String id, Tones tones) {
  final cut = source.lastIndexOf('\n') + 1;
  _Stream? stream;
  for (final known in _streams) {
    if (known.id == id &&
        known.tones == tones &&
        known.prefix.length <= cut &&
        (stream == null || known.prefix.length > stream.prefix.length) &&
        source.startsWith(known.prefix)) {
      stream = known;
    }
  }
  if (stream == null) {
    stream = _Stream(id, tones);
    if (_streams.length >= _streamsRemembered) _streams.removeAt(0);
  } else {
    _streams.remove(stream);
  }
  _streams.add(stream);

  if (cut > stream.prefix.length) {
    final result = _continue(
      stream,
      source.substring(stream.prefix.length, cut),
    );
    if (result == null) {
      _streams.remove(stream);
      return highlightWhole(source, id, tones);
    }
    final added = _split(_runs(result, tones));
    stream
      ..prefix = source.substring(0, cut)
      ..lines = [...stream.lines, ...added.take(added.length - 1)]
      ..top = result.top;
  }
  final tail = cut == source.length
      ? null
      : _continue(stream, source.substring(cut));
  if (cut < source.length && tail == null) {
    return highlightWhole(source, id, tones);
  }
  return List.unmodifiable([
    ...stream.lines,
    tail == null
        ? const TextSpan('', children: [])
        : _split(_runs(tail, tones)).single,
  ]);
}

/// [text] highlighted from where [stream]'s prefix ended; null when the
/// grammar failed on it, which the package reports by leaving no mode stack.
hl.Result? _continue(_Stream stream, String text) {
  // The package marks its continuation entry internal, but it is the one
  // way to resume a grammar where an earlier text ended.
  // ignore: invalid_use_of_internal_member
  final result = hl.highlight.highlight(
    stream.id,
    text,
    true,
    continuation: stream.top,
  );
  return result.top == null ? null : result;
}

/// Every grammar's name and alias to its id. The package's grammars are
/// a superset of chord's (emphasize's common set), and no alias is claimed
/// by two of them, so each name means what it means in chord.
final Map<String, String> _names = {
  for (final MapEntry(key: id, value: language) in hl.builtinLanguages.entries)
    for (final name in [id, ...language.aliases]) name.toLowerCase(): id,
};

String? _resolve(String name) => name.isEmpty ? null : _names[name];

/// A sheet key: a class, or a class inside another (`meta keyword`).
typedef _Rule = (List<String> path, Style Function(Tones) style);

/// chord's sheet (highlight.ts), in its order: where two keys match one
/// token, the later wins, as emphasize applies them.
final List<_Rule> _sheet = [
  for (final (key, style) in <(String, Style Function(Tones))>[
    ('keyword', (t) => t.keyword),
    ('selector-tag', (t) => t.keyword),
    ('meta keyword', (t) => t.keyword),
    ('string', (t) => t.string),
    ('regexp', (t) => t.string),
    ('meta meta-string', (t) => t.string),
    ('char', (t) => t.string),
    ('number', (t) => t.number),
    ('literal', (t) => t.number),
    ('comment', (t) => t.comment),
    ('quote', (t) => t.comment),
    ('doctag', (t) => t.comment),
    ('title', (t) => t.title),
    ('section', (t) => t.title),
    ('selector-id', (t) => t.title),
    ('selector-class', (t) => t.title),
    ('type', (t) => t.type),
    ('built_in', (t) => t.type),
    ('class title', (t) => t.type),
    ('name', (t) => t.name),
    ('attr', (t) => t.name),
    ('attribute', (t) => t.name),
    ('variable', (t) => t.name),
    ('template-variable', (t) => t.name),
    ('property', (t) => t.name),
    ('meta', (t) => t.meta),
    ('symbol', (t) => t.meta),
    ('bullet', (t) => t.meta),
    ('link', (t) => t.meta),
    ('selector-attr', (t) => t.meta),
    ('selector-pseudo', (t) => t.meta),
    ('emphasis', (_) => Style.italic),
    ('strong', (_) => Style.bold),
  ])
    (key.split(' '), style),
];

/// The highlighted tree as runs of text, each with its resolved style.
///
/// Walks as emphasize's `visit`: a node takes the last one-word rule its
/// class matches, and hands its children the rest, with the rules that
/// start with its class shortened by that word. A style nests inside its
/// parent's, so the inner colour wins and attributes add up.
List<(String, Style)> _runs(hl.Result result, Tones tones) {
  final runs = <(String, Style)>[];
  void visit(hl.Node node, List<_Rule> sheet, Style outer) {
    final value = node.value;
    if (value != null) {
      if (value.isNotEmpty) runs.add((value, outer));
      return;
    }
    // A scope `title.class` is classes `title` and `class_`; only the
    // first can match a rule.
    final name = node.className?.split('.').first;
    Style? own;
    final scoped = <_Rule>[];
    for (final rule in sheet) {
      final (path, style) = rule;
      if (path.first != name) {
        scoped.add(rule);
      } else if (path.length == 1) {
        own = style(tones);
      } else {
        scoped.add((path.sublist(1), style));
      }
    }
    final style = outer.merge(own);
    for (final child in node.children) {
      visit(child, scoped, style);
    }
  }

  for (final node in result.nodes ?? const <hl.Node>[]) {
    visit(node, _sheet, Style.plain);
  }
  return runs;
}

/// The runs cut at each line break into one span per line; a run's style
/// is carried onto every line it spans.
List<TextSpan> _split(List<(String, Style)> runs) {
  final lines = <TextSpan>[];
  var line = <TextSpan>[];
  void add(String text, Style style) {
    if (text.isEmpty) return;
    final own = style == Style.plain ? null : style;
    // Runs of one style join, so a line is cut the same way whether it was
    // highlighted whole or resumed: the package splits plain text where
    // its scan happened to stop.
    if (line.isNotEmpty && line.last.style == own) {
      line.last = TextSpan(line.last.text + text, style: own);
    } else {
      line.add(TextSpan(text, style: own));
    }
  }

  for (final (text, style) in runs) {
    final parts = text.split('\n');
    add(parts.first, style);
    for (final part in parts.skip(1)) {
      lines.add(TextSpan('', children: List.unmodifiable(line)));
      line = <TextSpan>[];
      add(part, style);
    }
  }
  lines.add(TextSpan('', children: List.unmodifiable(line)));
  return List.unmodifiable(lines);
}
