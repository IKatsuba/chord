/// npm `yaml` 2.9.1's `stringify` with its default options, for what chord
/// writes: maps with string keys, lists, and strings. The original writes
/// team files with it; no Dart writer writes the same bytes (see
/// `docs/decisions.md`), and people read and edit team files, so its
/// plain scalars, quoting, block scalars and folding at 80 columns are kept.
///
/// Ported from `dist/stringify/{stringify,stringifyCollection,stringifyPair,
/// stringifyString,foldFlowLines,stringifyDocument}.js` with the paths
/// comments, anchors, tags, flow collections and other scalar types take
/// left out. Lengths and indices are UTF-16 code units, as JavaScript's.
library;

const _lineWidth = 80;
const _minContentWidth = 20;
const _doubleQuotedMinMultiLineLength = 40;
const _indentStep = '  ';

/// [value] as npm `yaml`'s `stringify(value)` writes it: a map's keys in
/// their order, a list's items, strings; anything else is an
/// [ArgumentError].
String yamlStringify(Object value) => '${_node(value, _Context(''))}\n';

final class _Context {
  _Context(this.indent, {this.implicitKey = false});

  final String indent;
  final bool implicitKey;
  int? indentAtStart;
  bool forceBlockIndent = false;
}

String _node(Object? value, _Context ctx) => switch (value) {
  String() => _string(value, ctx),
  Map() => _map(value, ctx),
  List() => _seq(value, ctx),
  _ => throw ArgumentError.value(value, 'value', 'not a map, list or string'),
};

String _map(Map<Object?, Object?> map, _Context ctx) {
  final lines = [
    for (final MapEntry(:key, :value) in map.entries)
      _pair('$key', value, _Context(ctx.indent)),
  ];
  return _block(lines, ctx.indent, '{}', '');
}

String _seq(List<Object?> list, _Context ctx) {
  final itemIndent = '${ctx.indent}  ';
  final lines = [for (final item in list) _node(item, _Context(itemIndent))];
  return _block(lines, ctx.indent, '[]', '- ');
}

// stringifyBlockCollection, with nothing before or after an item.
String _block(List<String> lines, String indent, String empty, String prefix) {
  if (lines.isEmpty) return empty;
  final out = StringBuffer('$prefix${lines.first}');
  for (final line in lines.skip(1)) {
    out.write('\n$indent$prefix$line');
  }
  return out.toString();
}

// stringifyPair for a string key with no comment, out of flow.
String _pair(String key, Object? value, _Context parent) {
  final indent = parent.indent;
  final ctx = _Context('$indent$_indentStep', implicitKey: true);
  var str = '${_string(key, ctx)}:';
  final valueCtx = _Context(ctx.indent);
  if (value is String) valueCtx.indentAtStart = str.length + 1;
  final valueStr = _node(value, valueCtx);
  var ws = ' ';
  if (value is Map || value is List) {
    final flow = (value is Map ? value.isEmpty : (value as List).isEmpty);
    if (valueStr.contains('\n') || !flow) ws = '\n${ctx.indent}';
  } else if (valueStr.isEmpty || valueStr[0] == '\n') {
    ws = '';
  }
  return '$str$ws$valueStr';
}

// stringifyString for a string with no type of its own: PLAIN, or double
// quotes for control characters and lone surrogates.
String _string(String value, _Context ctx) => _forcesDouble.hasMatch(value)
    ? _doubleQuoted(value, ctx)
    : _plain(value, ctx);

final _forcesDouble = RegExp(
  r'[\x00-\x08\x0b-\x1f\x7f-\x9f\u{D800}-\u{DFFF}]',
  unicode: true,
);

// Also lines starting with %, as YAML 1.1 reads them as a new document.
bool _containsDocumentMarker(String str) =>
    RegExp(r'^(%|---|\.\.\.)', multiLine: true).hasMatch(str);

bool _lineLengthOverLimit(String str, int lineWidth, int indentLength) {
  final limit = lineWidth - indentLength;
  final strLen = str.length;
  if (strLen <= limit) return false;
  for (var i = 0, start = 0; i < strLen; ++i) {
    if (str[i] == '\n') {
      if (i - start > limit) return true;
      start = i + 1;
      if (strLen - start <= limit) return false;
    }
  }
  return true;
}

// JavaScript's JSON.stringify of a string.
String _json(String value) {
  final out = StringBuffer('"');
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    switch (c) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        final lead = c >= 0xd800 && c <= 0xdbff;
        final trail = c >= 0xdc00 && c <= 0xdfff;
        final paired = lead
            ? i + 1 < value.length &&
                  (value.codeUnitAt(i + 1) & 0xfc00) == 0xdc00
            : trail && i > 0 && (value.codeUnitAt(i - 1) & 0xfc00) == 0xd800;
        if (c < 0x20 || ((lead || trail) && !paired)) {
          out.write(r'\u' + c.toRadixString(16).padLeft(4, '0'));
        } else {
          out.writeCharCode(c);
        }
    }
  }
  out.write('"');
  return out.toString();
}

// JavaScript's `s.slice(start, end)`: a negative index counts from the end.
String _slice(String s, int start, int end) {
  int at(int i) =>
      i < 0 ? (s.length + i).clamp(0, s.length) : i.clamp(0, s.length);
  final from = at(start), to = at(end);
  return from < to ? s.substring(from, to) : '';
}

// `s[i]` in JavaScript: '' past either end.
String _at(String s, int i) => i >= 0 && i < s.length ? s[i] : '';

String _doubleQuoted(String value, _Context ctx) {
  final json = _json(value);
  final implicitKey = ctx.implicitKey;
  final indent = ctx.indent.isNotEmpty
      ? ctx.indent
      : (_containsDocumentMarker(value) ? '  ' : '');
  final str = StringBuffer();
  var start = 0;
  for (var i = 0, ch = _at(json, i); ch.isNotEmpty; ch = _at(json, ++i)) {
    if (ch == ' ' && _at(json, i + 1) == r'\' && _at(json, i + 2) == 'n') {
      // A space before a newline is escaped so folding keeps it.
      str.write('${json.substring(start, i)}\\ ');
      i += 1;
      start = i;
      ch = r'\';
    }
    if (ch == r'\') {
      switch (_at(json, i + 1)) {
        case 'u':
          str.write(json.substring(start, i));
          final code = json.substring(i + 2, i + 6);
          switch (code) {
            case '0000':
              str.write(r'\0');
            case '0007':
              str.write(r'\a');
            case '000b':
              str.write(r'\v');
            case '001b':
              str.write(r'\e');
            case '0085':
              str.write(r'\N');
            case '00a0':
              str.write(r'\_');
            case '2028':
              str.write(r'\L');
            case '2029':
              str.write(r'\P');
            default:
              if (code.startsWith('00')) {
                str.write('\\x${code.substring(2)}');
              } else {
                str.write(json.substring(i, i + 6));
              }
          }
          i += 5;
          start = i + 1;
        case 'n':
          if (implicitKey ||
              _at(json, i + 2) == '"' ||
              json.length < _doubleQuotedMinMultiLineLength) {
            i += 1;
          } else {
            // Folding eats the first newline.
            str.write('${json.substring(start, i)}\n\n');
            while (_at(json, i + 2) == r'\' &&
                _at(json, i + 3) == 'n' &&
                _at(json, i + 4) != '"') {
              str.write('\n');
              i += 2;
            }
            str.write(indent);
            // A space after a newline is escaped so folding keeps it.
            if (_at(json, i + 2) == ' ') str.write(r'\');
            i += 1;
            start = i + 1;
          }
        default:
          i += 1;
      }
    }
  }
  final out = start != 0 ? '$str${json.substring(start)}' : json;
  return implicitKey
      ? out
      : _foldFlowLines(out, indent, _Fold.quoted, ctx.indentAtStart);
}

String _singleQuoted(String value, _Context ctx) {
  if ((ctx.implicitKey && value.contains('\n')) ||
      RegExp(r'[ \t]\n|\n[ \t]').hasMatch(value)) {
    return _doubleQuoted(value, ctx);
  }
  final indent = ctx.indent.isNotEmpty
      ? ctx.indent
      : (_containsDocumentMarker(value) ? '  ' : '');
  final res =
      "'${value.replaceAll("'", "''").replaceAllMapped(RegExp(r'\n+'), (m) => '${m[0]}\n$indent')}'";
  return ctx.implicitKey
      ? res
      : _foldFlowLines(res, indent, _Fold.flow, ctx.indentAtStart);
}

// quotedString with singleQuote null: single quotes only for a string with
// double quotes and no single ones.
String _quoted(String value, _Context ctx) =>
    value.contains('"') && !value.contains("'")
    ? _singleQuoted(value, ctx)
    : _doubleQuoted(value, ctx);

final _blockEndNewlines = RegExp(r'(^|(?<!\n))\n+(?!\n|$)');

String _blockString(String value, _Context ctx) {
  // A block cannot end in whitespace unless its last line is not empty.
  if (RegExp(r'\n[\t ]+$').hasMatch(value)) return _quoted(value, ctx);
  final indent = ctx.indent.isNotEmpty
      ? ctx.indent
      : (ctx.forceBlockIndent || _containsDocumentMarker(value) ? '  ' : '');
  final literal = !_lineLengthOverLimit(value, _lineWidth, indent.length);
  if (value.isEmpty) return literal ? '|\n' : '>\n';
  // Chomping, from the whitespace at the end.
  String chomp;
  var endStart = value.length;
  for (; endStart > 0; --endStart) {
    final ch = value[endStart - 1];
    if (ch != '\n' && ch != '\t' && ch != ' ') break;
  }
  var end = value.substring(endStart);
  final endNlPos = end.indexOf('\n');
  if (endNlPos == -1) {
    chomp = '-';
  } else if (value == end || endNlPos != end.length - 1) {
    chomp = '+';
  } else {
    chomp = '';
  }
  if (end.isNotEmpty) {
    value = value.substring(0, value.length - end.length);
    if (end.endsWith('\n')) end = end.substring(0, end.length - 1);
    end = end.replaceAllMapped(_blockEndNewlines, (m) => '${m[0]}$indent');
  }
  // The indentation indicator, from the whitespace at the start.
  var startWithSpace = false;
  var startEnd = 0;
  var startNlPos = -1;
  for (; startEnd < value.length; ++startEnd) {
    final ch = value[startEnd];
    if (ch == ' ') {
      startWithSpace = true;
    } else if (ch == '\n') {
      startNlPos = startEnd;
    } else {
      break;
    }
  }
  var start = value.substring(
    0,
    startNlPos < startEnd ? startNlPos + 1 : startEnd,
  );
  if (start.isNotEmpty) {
    value = value.substring(start.length);
    start = start.replaceAllMapped(RegExp(r'\n+'), (m) => '${m[0]}$indent');
  }
  final indentSize = indent.isNotEmpty ? '2' : '1';
  final header = '${startWithSpace ? indentSize : ''}$chomp';
  if (!literal) {
    final foldedValue = value
        .replaceAllMapped(RegExp(r'\n+'), (m) => '\n${m[0]}')
        // More-indented lines are not folded.
        .replaceAllMapped(
          RegExp(r'(?:^|\n)([\t ].*)(?:([\n\t ]*)\n(?![\n\t ]))?'),
          (m) => '${m[1] ?? ''}${m[2] ?? ''}',
        )
        .replaceAllMapped(RegExp(r'\n+'), (m) => '${m[0]}$indent');
    var literalFallback = false;
    final body = _foldFlowLines(
      '$start$foldedValue$end',
      indent,
      _Fold.block,
      indent.length,
      onOverflow: () => literalFallback = true,
    );
    if (!literalFallback) return '>$header\n$indent$body';
  }
  value = value.replaceAllMapped(RegExp(r'\n+'), (m) => '${m[0]}$indent');
  return '|$header\n$indent$start$value$end';
}

// The core schema's tags other than str whose test a plain scalar would
// match: null, bool, int, float.
final _otherTags = [
  RegExp(r'^(?:~|[Nn]ull|NULL)?$'),
  RegExp(r'^(?:[Tt]rue|TRUE|[Ff]alse|FALSE)$'),
  RegExp(r'^0o[0-7]+$'),
  RegExp(r'^[-+]?[0-9]+$'),
  RegExp(r'^0x[0-9a-fA-F]+$'),
  RegExp(r'^(?:[-+]?\.(?:inf|Inf|INF)|\.nan|\.NaN|\.NAN)$'),
  RegExp(r'^[-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)[eE][-+]?[0-9]+$'),
  RegExp(r'^[-+]?(?:\.[0-9]+|[0-9]+\.[0-9]*)$'),
];

final _notPlain = RegExp(
  r'''^[\n\t ,[\]{}#&*!|>'"%@`]|^[?-]$|^[?-][ \t]|[\n:][ \t]|[ \t]\n|[\n\t ]#|[\n\t :]$''',
);

String _plain(String value, _Context ctx) {
  final implicitKey = ctx.implicitKey;
  final indent = ctx.indent;
  if (implicitKey && value.contains('\n')) return _quoted(value, ctx);
  if (_notPlain.hasMatch(value)) {
    return implicitKey || !value.contains('\n')
        ? _quoted(value, ctx)
        : _blockString(value, ctx);
  }
  // Where allowed, a multi-line string prefers a block.
  if (!implicitKey && value.contains('\n')) return _blockString(value, ctx);
  if (_containsDocumentMarker(value)) {
    if (indent.isEmpty) {
      ctx.forceBlockIndent = true;
      return _blockString(value, ctx);
    } else if (implicitKey && indent == _indentStep) {
      return _quoted(value, ctx);
    }
  }
  final str = value.replaceAllMapped(RegExp(r'\n+'), (m) => '${m[0]}\n$indent');
  // A plain scalar another tag would read, as 42 or true, is quoted.
  if (_otherTags.any((test) => test.hasMatch(str))) {
    return _quoted(value, ctx);
  }
  return implicitKey
      ? str
      : _foldFlowLines(str, indent, _Fold.flow, ctx.indentAtStart);
}

enum _Fold { flow, block, quoted }

// foldFlowLines: lines kept to 80 columns where they can be, split only at
// a space between non-spaces unless quoted; each new line starts with
// [indent].
String _foldFlowLines(
  String text,
  String indent,
  _Fold mode,
  int? indentAtStart, {
  void Function()? onOverflow,
}) {
  const lineWidth = _lineWidth;
  const minContentWidth = _minContentWidth;
  final endStep = 1 + minContentWidth > 1 + lineWidth - indent.length
      ? 1 + minContentWidth
      : 1 + lineWidth - indent.length;
  if (text.length <= endStep) return text;
  final folds = <int>[];
  final escapedFolds = <int>{};
  var end = lineWidth - indent.length;
  if (indentAtStart != null) {
    if (indentAtStart >
        lineWidth - (minContentWidth > 2 ? minContentWidth : 2)) {
      folds.add(0);
    } else {
      end = lineWidth - indentAtStart;
    }
  }
  int? split;
  var prev = '';
  var overflow = false;
  var i = -1;
  var escStart = -1;
  var escEnd = -1;
  if (mode == _Fold.block) {
    i = _consumeMoreIndentedLines(text, i, indent.length);
    if (i != -1) end = i + endStep;
  }
  for (var ch = _at(text, i += 1); ch.isNotEmpty; ch = _at(text, i += 1)) {
    if (mode == _Fold.quoted && ch == r'\') {
      escStart = i;
      switch (_at(text, i + 1)) {
        case 'x':
          i += 3;
        case 'u':
          i += 5;
        case 'U':
          i += 9;
        default:
          i += 1;
      }
      escEnd = i;
    }
    if (ch == '\n') {
      if (mode == _Fold.block) {
        i = _consumeMoreIndentedLines(text, i, indent.length);
      }
      end = i + indent.length + endStep;
      split = null;
    } else {
      if (ch == ' ' &&
          prev.isNotEmpty &&
          prev != ' ' &&
          prev != '\n' &&
          prev != '\t') {
        // A space between non-spaces can become a newline and the indent.
        final next = _at(text, i + 1);
        if (next.isNotEmpty && next != ' ' && next != '\n' && next != '\t') {
          split = i;
        }
      }
      if (i >= end) {
        if (split != null && split != 0) {
          folds.add(split);
          end = split + endStep;
          split = null;
        } else if (mode == _Fold.quoted) {
          // Whitespace collected at the end may stretch past the width.
          while (prev == ' ' || prev == '\t') {
            prev = ch;
            ch = _at(text, i += 1);
            overflow = true;
          }
          // A newline escape, without breaking the escape before it.
          final j = i > escEnd + 1 ? i - 2 : escStart - 1;
          // Out when the width is shorter than an escape.
          if (escapedFolds.contains(j)) return text;
          folds.add(j);
          escapedFolds.add(j);
          end = j + endStep;
          split = null;
        } else {
          overflow = true;
        }
      }
    }
    prev = ch;
  }
  if (overflow) onOverflow?.call();
  if (folds.isEmpty) return text;
  var res = _slice(text, 0, folds[0]);
  for (var k = 0; k < folds.length; ++k) {
    final fold = folds[k];
    final next = k + 1 < folds.length ? folds[k + 1] : 0;
    final foldEnd = next != 0 ? next : text.length;
    if (fold == 0) {
      res = '\n$indent${_slice(text, 0, foldEnd)}';
    } else {
      if (mode == _Fold.quoted && escapedFolds.contains(fold)) {
        res += '${_at(text, fold)}\\';
      }
      res += '\n$indent${_slice(text, fold + 1, foldEnd)}';
    }
  }
  return res;
}

// Presumes i + 1 starts a line; the index of the last newline of the
// more-indented lines from there.
int _consumeMoreIndentedLines(String text, int i, int indent) {
  var end = i;
  var start = i + 1;
  var ch = _at(text, start);
  while (ch == ' ' || ch == '\t') {
    if (i < start + indent) {
      ch = _at(text, ++i);
    } else {
      do {
        ch = _at(text, ++i);
      } while (ch.isNotEmpty && ch != '\n');
      end = i;
      start = i + 1;
      ch = _at(text, start);
    }
  }
  return end;
}
