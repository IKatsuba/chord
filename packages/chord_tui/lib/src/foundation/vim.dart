import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

import '../input/keys.dart';
import 'text_editing.dart' show TextAreaDirection;

/// Which of vim's two modes a field is in.
enum VimMode {
  /// Keys type, as in any field.
  insert,

  /// Keys move, delete and change, as vim's normal mode.
  normal,
}

/// What `p` puts back: the last text deleted or yanked.
@immutable
class VimRegister {
  /// [text], whole lines when [linewise].
  const VimRegister(this.text, {this.linewise = false});

  /// The text; whole lines, each ended by a newline, when [linewise].
  final String text;

  /// Whether `p` puts it as lines below the cursor's.
  final bool linewise;

  @override
  bool operator ==(Object other) =>
      other is VimRegister && other.text == text && other.linewise == linewise;

  @override
  int get hashCode => Object.hash(text, linewise);

  @override
  String toString() =>
      'VimRegister(${[text, if (linewise) 'linewise'].join(', ')})';
}

/// Vim's state beside a field's text: plain data, kept by the caller.
@immutable
class VimState {
  /// A state; insert mode with nothing pending by default.
  const VimState({
    this.mode = VimMode.insert,
    this.pending = const [],
    this.register,
    this.goalColumn,
    this.lastFind,
  });

  /// The mode the field is in.
  final VimMode mode;

  /// A command still being typed, a key each: `2`, `d`.
  final List<String> pending;

  /// What `p` puts back.
  final VimRegister? register;

  /// Where `j` and `k` aim, kept between them.
  final int? goalColumn;

  /// The last `f`, `F`, `t` or `T` and its character, which `;` and `,`
  /// repeat.
  final String? lastFind;

  /// This state with what is given changed; `null`s given as functions
  /// clear.
  VimState copyWith({
    VimMode? mode,
    List<String>? pending,
    VimRegister? register,
    int? Function()? goalColumn,
    String? lastFind,
  }) => VimState(
    mode: mode ?? this.mode,
    pending: pending ?? this.pending,
    register: register ?? this.register,
    goalColumn: goalColumn == null ? this.goalColumn : goalColumn(),
    lastFind: lastFind ?? this.lastFind,
  );

  @override
  bool operator ==(Object other) =>
      other is VimState &&
      other.mode == mode &&
      _sameList(other.pending, pending) &&
      other.register == register &&
      other.goalColumn == goalColumn &&
      other.lastFind == lastFind;

  @override
  int get hashCode => Object.hash(
    mode,
    Object.hashAll(pending),
    register,
    goalColumn,
    lastFind,
  );

  @override
  String toString() =>
      'VimState(${mode.name}, pending: $pending, register: $register)';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The text and where the cursor is, in graphemes, as TextAreaController
/// counts them.
typedef VimValue = ({String text, int cursor});

/// Widens a deletion [start, end) that cuts into an atom to take the whole
/// of it; returns the range unchanged when it cuts into none.
typedef VimAtoms = (int, int) Function(String text, int start, int end);

/// What one key did in normal mode.
@immutable
class VimStep {
  /// A step to [state], [value] when the text or cursor changed.
  const VimStep(
    this.state, {
    this.value,
    this.taken = true,
    this.edge,
    this.undo = false,
  });

  /// Vim's state after the key.
  final VimState state;

  /// The text and cursor after it; null when they are unchanged.
  final VimValue? value;

  /// Whether the key is normal mode's; false leaves it to the caller.
  final bool taken;

  /// `k` on the first line or `j` on the last: the caller walks on.
  final TextAreaDirection? edge;

  /// `u`: the caller undoes.
  final bool undo;

  @override
  String toString() =>
      'VimStep($state, value: $value, taken: $taken, edge: $edge, undo: $undo)';
}

/// The keys normal mode takes, as the original's NORMAL_KEYS, and the
/// arrows and backspace.
const vimNormalKeys = r'hjklwbeWBE0123456789$^xXdcyDCYsSiaIAoOupP~;,fFtTrJ';

const _named = {'left', 'right', 'up', 'down', 'backspace'};

/// The key normal mode would read [event] as, or null: one character, or
/// `left`, `right`, `up`, `down` or `backspace`.
String? vimKeyOf(KeyEvent event) {
  if (event.ctrl || event.alt || event.superKey || event.hyper || event.meta) {
    return null;
  }
  if (_named.contains(event.key) && !event.shift) return event.key;
  // A space is one too: `f ` finds it, though normal mode takes none alone.
  if (event.key == 'space' || event.key == ' ') return ' ';
  // The key itself, as one grapheme, an emoji or a composed letter whole;
  // a named key is a word, and none.
  final key = event.key;
  return key.characters.length == 1 ? key : null;
}

bool _takesCharacter(List<String> pending) =>
    pending.isNotEmpty &&
    'fFtTr'.contains(pending.last) &&
    pending.last.length == 1;

bool _textObject(List<String> pending) {
  final keys = pending.where((k) => !_isDigit(k)).join();
  return RegExp(r'^[dcy][ia]$').hasMatch(keys) && 'ia'.contains(pending.last);
}

bool _isDigit(String key) => key.length == 1 && '0123456789'.contains(key);

/// Whether normal mode takes the next key as the character it is, as after
/// `f`, `t` or `r`, rather than as a key with a meaning of its own.
bool vimTakesCharacter(VimState state) => _takesCharacter(state.pending);

/// Whether normal mode takes [key] next, with what is pending before it.
bool vimTakes(VimState state, String key) =>
    (key.length == 1 && vimNormalKeys.contains(key)) ||
    _named.contains(key) ||
    _takesCharacter(state.pending) ||
    _textObject(state.pending);

/// Esc in insert mode: normal mode, the cursor one back onto the character
/// it was after, as vim leaves it.
VimStep vimEscape(VimState state, VimValue value) {
  final b = _Buffer(value.text);
  final at = value.cursor;
  final cursor = at > b.lineStart(at) ? at - 1 : at;
  return VimStep(
    state.copyWith(
      mode: VimMode.normal,
      pending: const [],
      goalColumn: () => null,
    ),
    value: cursor == at ? null : (text: value.text, cursor: cursor),
  );
}

/// One key in normal mode. [key] is one character, or `left`, `right`,
/// `up`, `down` or `backspace`, as [vimKeyOf] names them.
VimStep vimStep(VimState state, VimValue value, String key, {VimAtoms? atoms}) {
  if (!vimTakes(state, key)) return VimStep(state, taken: false);
  final keys = [...state.pending, _arrow(key)];
  final command = _parse(keys);
  if (command == null) return VimStep(state.copyWith(pending: keys));
  final cleared = state.copyWith(pending: const []);
  if (command is _Invalid) return VimStep(cleared);
  return _Run(cleared, value, atoms).run(command as _Command);
}

String _arrow(String key) => switch (key) {
  'left' || 'backspace' => 'h',
  'right' => 'l',
  'up' => 'k',
  'down' => 'j',
  _ => key,
};

/// A command read whole, or [_Invalid] for one that can be none.
sealed class _Parsed {
  const _Parsed();
}

final class _Invalid extends _Parsed {
  const _Invalid();
}

final class _Command extends _Parsed {
  const _Command(this.count, this.op, this.key, {this.char, this.object});

  /// How many times, 1 when no count was typed.
  final int count;

  /// `d`, `c` or `y` before the motion; null for a command of its own.
  final String? op;

  /// The motion or the command; the operator again for whole lines.
  final String key;

  /// What `f`, `F`, `t`, `T` or `r` takes.
  final String? char;

  /// `i` or `a` before a text object's [key].
  final String? object;
}

/// [keys] read as a command, null while it is still being typed.
_Parsed? _parse(List<String> keys) {
  var at = 0;
  int? count(int from) {
    if (from >= keys.length || !_isDigit(keys[from]) || keys[from] == '0') {
      return null;
    }
    var n = 0;
    while (at < keys.length && _isDigit(keys[at])) {
      n = n * 10 + int.parse(keys[at]);
      at++;
    }
    return n;
  }

  final first = count(at) ?? 1;
  if (at >= keys.length) return null;
  final key = keys[at++];
  if ('dcy'.contains(key)) {
    final second = count(at) ?? 1;
    if (at >= keys.length) return null;
    final motion = keys[at++];
    final times = first * second;
    if (motion == key) {
      return at == keys.length ? _Command(times, key, key) : const _Invalid();
    }
    if ('ia'.contains(motion)) {
      if (at >= keys.length) return null;
      final object = keys[at++];
      return 'wW'.contains(object) && at == keys.length
          ? _Command(times, key, object, object: motion)
          : const _Invalid();
    }
    if ('fFtT'.contains(motion)) {
      if (at >= keys.length) return null;
      return _Command(times, key, motion, char: keys[at]);
    }
    return 'hjklwbeWBE0^\$;,'.contains(motion)
        ? _Command(times, key, motion)
        : const _Invalid();
  }
  if ('fFtTr'.contains(key)) {
    if (at >= keys.length) return null;
    return _Command(first, null, key, char: keys[at]);
  }
  return 'ia'.contains(key) && at < keys.length
      ? const _Invalid()
      : _Command(first, null, key);
}

/// A text by graphemes, with its lines.
final class _Buffer {
  _Buffer(this.text) : g = text.characters.toList();
  final String text;
  final List<String> g;

  int get length => g.length;

  int lineStart(int at) {
    var i = at.clamp(0, g.length);
    while (i > 0 && g[i - 1] != '\n') {
      i--;
    }
    return i;
  }

  int lineEnd(int at) {
    var i = at.clamp(0, g.length);
    while (i < g.length && g[i] != '\n') {
      i++;
    }
    return i;
  }

  int lineOf(int at) {
    var line = 0;
    for (var i = 0; i < at && i < g.length; i++) {
      if (g[i] == '\n') line++;
    }
    return line;
  }

  int get lineCount => g.where((c) => c == '\n').length + 1;

  int startOfLine(int line) {
    var at = 0;
    for (var n = 0; n < line; n++) {
      at = lineEnd(at) + 1;
    }
    return at;
  }

  /// Where normal mode stands on [at]'s line: on a character, not past one.
  int stand(int at) {
    final start = lineStart(at), end = lineEnd(at);
    return end == start ? start : at.clamp(start, end - 1);
  }

  int firstNonBlank(int at) {
    final start = lineStart(at), end = lineEnd(at);
    var i = start;
    while (i < end && (g[i] == ' ' || g[i] == '\t')) {
      i++;
    }
    return i == end ? stand(i) : i;
  }

  String slice(int start, int end) => g.sublist(start, end).join();

  bool blank(int i) => g[i] == ' ' || g[i] == '\t' || g[i] == '\n';

  /// 0 for blanks, 1 for a word's characters, 2 for other marks; [big]
  /// counts every non-blank as one class.
  int kind(int i, bool big) {
    if (blank(i)) return 0;
    if (big) return 1;
    return RegExp(r'^[\p{L}\p{N}_]', unicode: true).hasMatch(g[i]) ? 1 : 2;
  }

  /// The start of the next word after [at]; [length] past the last.
  int nextWord(int at, bool big) {
    var i = at;
    if (i >= g.length) return g.length;
    final kind = this.kind(i, big);
    if (kind != 0) {
      while (i < g.length && this.kind(i, big) == kind) {
        i++;
      }
    }
    while (i < g.length && blank(i)) {
      // An empty line is a word of its own.
      if (g[i] == '\n' && i + 1 < g.length && g[i + 1] == '\n' && i >= at) {
        return i + 1;
      }
      i++;
    }
    return i;
  }

  /// The last character of the word ending after [at].
  int wordEnd(int at, bool big) {
    var i = at + 1;
    while (i < g.length && blank(i)) {
      i++;
    }
    if (i >= g.length) return g.isEmpty ? 0 : g.length - 1;
    final kind = this.kind(i, big);
    while (i + 1 < g.length && this.kind(i + 1, big) == kind) {
      i++;
    }
    return i;
  }

  /// The start of the word before [at].
  int wordStart(int at, bool big) {
    var i = at - 1;
    while (i > 0 && blank(i)) {
      i--;
    }
    if (i <= 0) return 0;
    final kind = this.kind(i, big);
    while (i > 0 && this.kind(i - 1, big) == kind) {
      i--;
    }
    return i;
  }
}

final class _Run {
  _Run(this.state, this.value, this.atoms)
    : b = _Buffer(value.text),
      at = value.cursor.clamp(0, value.text.characters.length);
  final VimState state;
  final VimValue value;
  final VimAtoms? atoms;
  final _Buffer b;
  final int at;

  VimStep moved(int cursor, {int? goal}) => VimStep(
    state.copyWith(goalColumn: () => goal),
    value: cursor == at ? null : (text: value.text, cursor: cursor),
  );

  VimStep edited(
    String text,
    int cursor, {
    VimRegister? register,
    VimMode mode = VimMode.normal,
  }) => VimStep(
    state.copyWith(mode: mode, register: register, goalColumn: () => null),
    value: (text: text, cursor: cursor),
  );

  VimStep run(_Command c) {
    if (c.op != null) return operate(c);
    switch (c.key) {
      case 'u':
        return VimStep(state, undo: true);
      case 'x':
        return operate(_Command(c.count, 'd', 'l'));
      case 'X':
        return operate(_Command(c.count, 'd', 'h'));
      case 'D':
        return operate(_Command(1, 'd', r'$'));
      case 'C':
        return operate(_Command(1, 'c', r'$'));
      case 'Y':
        return operate(_Command(c.count, 'y', 'y'));
      case 's':
        return operate(_Command(c.count, 'c', 'l'));
      case 'S':
        return operate(_Command(c.count, 'c', 'c'));
      case 'i':
        return insert(at);
      case 'a':
        return insert(b.lineEnd(at) == b.lineStart(at) ? at : at + 1);
      case 'I':
        return insert(_firstNonBlankOrEnd(at));
      case 'A':
        return insert(b.lineEnd(at));
      case 'o':
        final end = b.lineEnd(at);
        return edited(
          '${b.slice(0, end)}\n${b.slice(end, b.length)}',
          end + 1,
          mode: VimMode.insert,
        );
      case 'O':
        final start = b.lineStart(at);
        return edited(
          '${b.slice(0, start)}\n${b.slice(start, b.length)}',
          start,
          mode: VimMode.insert,
        );
      case 'p' || 'P':
        return put(c.key == 'p', c.count);
      case '~':
        return toggleCase(c.count);
      case 'r':
        return replace(c.count, c.char!);
      case 'J':
        return join(c.count);
    }
    final target = motion(c.key, c.count, c.char);
    if (target == null) return VimStep(state);
    if (target.edge != null) return VimStep(state, edge: target.edge);
    final step = moved(b.stand(target.at), goal: target.goal);
    final found = _found;
    return found == null
        ? step
        : VimStep(step.state.copyWith(lastFind: found), value: step.value);
  }

  int _firstNonBlankOrEnd(int at) {
    final start = b.lineStart(at), end = b.lineEnd(at);
    var i = start;
    while (i < end && (b.g[i] == ' ' || b.g[i] == '\t')) {
      i++;
    }
    return i;
  }

  VimStep insert(int cursor) => VimStep(
    state.copyWith(mode: VimMode.insert, goalColumn: () => null),
    value: cursor == at ? null : (text: value.text, cursor: cursor),
  );

  /// Where [key] moves the cursor [count] times, and the goal column it
  /// keeps; null when it cannot be carried out.
  ({int at, int? goal, TextAreaDirection? edge, bool inclusive, bool lines})?
  motion(String key, int count, String? char) {
    final start = b.lineStart(at), end = b.lineEnd(at);
    final column = at - start;
    switch (key) {
      case 'h':
        return (
          at: (at - count).clamp(start, end),
          goal: null,
          edge: null,
          inclusive: false,
          lines: false,
        );
      case 'l':
        return (
          at: (at + count).clamp(start, end),
          goal: null,
          edge: null,
          inclusive: false,
          lines: false,
        );
      case 'j' || 'k':
        final line = b.lineOf(at);
        final down = key == 'j';
        final last = b.lineCount - 1;
        if ((down && line == last) || (!down && line == 0)) {
          return (
            at: at,
            goal: null,
            edge: down ? TextAreaDirection.down : TextAreaDirection.up,
            inclusive: false,
            lines: true,
          );
        }
        final to = (down ? line + count : line - count).clamp(0, last);
        final goal = state.goalColumn ?? column;
        final s = b.startOfLine(to), e = b.lineEnd(s);
        final x = e == s ? s : (s + goal).clamp(s, e - 1);
        return (at: x, goal: goal, edge: null, inclusive: false, lines: true);
      case 'w' || 'W':
        var i = at;
        for (var n = 0; n < count; n++) {
          i = b.nextWord(i, key == 'W');
        }
        return (at: i, goal: null, edge: null, inclusive: false, lines: false);
      case 'e' || 'E':
        var i = at;
        for (var n = 0; n < count; n++) {
          i = b.wordEnd(i, key == 'E');
        }
        return (at: i, goal: null, edge: null, inclusive: true, lines: false);
      case 'b' || 'B':
        var i = at;
        for (var n = 0; n < count; n++) {
          i = b.wordStart(i, key == 'B');
        }
        return (at: i, goal: null, edge: null, inclusive: false, lines: false);
      case '0':
        return (
          at: start,
          goal: null,
          edge: null,
          inclusive: false,
          lines: false,
        );
      case '^':
        return (
          at: b.firstNonBlank(at),
          goal: null,
          edge: null,
          inclusive: false,
          lines: false,
        );
      case r'$':
        return (
          at: end == start ? start : end - 1,
          goal: 1 << 30,
          edge: null,
          inclusive: true,
          lines: false,
        );
      case 'f' || 'F' || 't' || 'T':
        return find(key, char!, count);
      case ';' || ',':
        final last = state.lastFind;
        if (last == null) return null;
        var kind = last[0];
        if (key == ',') {
          kind = switch (kind) {
            'f' => 'F',
            'F' => 'f',
            't' => 'T',
            _ => 't',
          };
        }
        return find(kind, last.substring(1), count, remember: false);
    }
    return null;
  }

  ({int at, int? goal, TextAreaDirection? edge, bool inclusive, bool lines})?
  find(String kind, String char, int count, {bool remember = true}) {
    final start = b.lineStart(at), end = b.lineEnd(at);
    final forward = kind == 'f' || kind == 't';
    var i = at;
    for (var n = 0; n < count; n++) {
      var j = forward ? i + 1 : i - 1;
      // A t repeated by ; or , stands before the same character: it looks
      // past it. A first t finds the one beside it.
      if (!remember && kind == 't' && n == 0 && j + 1 < end && b.g[j] == char) {
        j++;
      }
      if (!remember &&
          kind == 'T' &&
          n == 0 &&
          j - 1 >= start &&
          b.g[j] == char) {
        j--;
      }
      while (j >= start && j < end && b.g[j] != char) {
        j += forward ? 1 : -1;
      }
      if (j < start || j >= end) return null;
      i = j;
    }
    if (kind == 't') i--;
    if (kind == 'T') i++;
    _found = remember ? '$kind$char' : null;
    return (at: i, goal: null, edge: null, inclusive: forward, lines: false);
  }

  /// The find a motion just made, for `;` and `,` to repeat.
  String? _found;

  VimStep operate(_Command c) {
    final op = c.op!;
    if (c.key == op || c.key == 'j' || c.key == 'k') {
      final line = b.lineOf(at);
      final last = b.lineCount - 1;
      int first, final_;
      if (c.key == op) {
        first = line;
        final_ = (line + c.count - 1).clamp(0, last);
      } else if (c.key == 'j') {
        if (line == last) return VimStep(state);
        first = line;
        final_ = (line + c.count).clamp(0, last);
      } else {
        if (line == 0) return VimStep(state);
        first = (line - c.count).clamp(0, last);
        final_ = line;
      }
      return lines(op, first, final_);
    }
    if (c.object != null) {
      final range = object(c.object!, c.key == 'W');
      if (range == null) return VimStep(state);
      return chars(op, range.$1, range.$2, keepCursor: true);
    }
    // cw changes to the end of the word, as ce, on a word.
    var key = c.key;
    if (op == 'c' &&
        (key == 'w' || key == 'W') &&
        at < b.length &&
        !b.blank(at)) {
      key = key == 'w' ? 'e' : 'E';
    }
    final target = motion(key, c.count, c.char);
    if (target == null || target.edge != null) return VimStep(state);
    var from = at, to = target.at;
    if (to < from) (from, to) = (to, from);
    if (target.inclusive) to++;
    // dw stops at the end of its line rather than take the break.
    if ((key == 'w' || key == 'W') && to > b.lineEnd(at)) {
      to = b.lineEnd(at);
    }
    to = to.clamp(0, b.length);
    if (to <= from) return VimStep(state);
    final step = chars(op, from, to);
    final found = _found;
    return found == null
        ? step
        : VimStep(step.state.copyWith(lastFind: found), value: step.value);
  }

  /// The word, or WORD, under the cursor: `i` the run alone, `a` with the
  /// blanks after it, or before it when none follow.
  (int, int)? object(String around, bool big) {
    if (b.length == 0) return null;
    final start = b.lineStart(at), end = b.lineEnd(at);
    if (at >= end) return null;
    final kind = b.kind(at, big);
    var from = at, to = at + 1;
    while (from > start && b.kind(from - 1, big) == kind) {
      from--;
    }
    while (to < end && b.kind(to, big) == kind) {
      to++;
    }
    if (around == 'a') {
      var after = to;
      while (after < end && b.kind(after, big) == 0) {
        after++;
      }
      if (after > to) {
        to = after;
      } else {
        while (from > start && b.kind(from - 1, big) == 0) {
          from--;
        }
      }
    }
    return (from, to);
  }

  VimStep chars(String op, int from, int to, {bool keepCursor = false}) {
    final (start, end) = atoms?.call(value.text, from, to) ?? (from, to);
    final register = VimRegister(b.slice(start, end));
    if (op == 'y') {
      return VimStep(
        state.copyWith(register: register, goalColumn: () => null),
        value: start < at && !keepCursor
            ? (text: value.text, cursor: start)
            : null,
      );
    }
    final text = b.slice(0, start) + b.slice(end, b.length);
    if (op == 'c') {
      return edited(text, start, register: register, mode: VimMode.insert);
    }
    return edited(text, _Buffer(text).stand(start), register: register);
  }

  /// [from, to) widened by the atoms, and whether they widened it.
  (int, int, bool) widened(int from, int to) {
    final (start, end) = atoms?.call(value.text, from, to) ?? (from, to);
    return (start, end, start != from || end != to);
  }

  VimStep lines(String op, int first, int last) {
    final start = b.startOfLine(first);
    final end = b.lineEnd(b.startOfLine(last));
    final lines = VimRegister('${b.slice(start, end)}\n', linewise: true);
    if (op == 'y') {
      return VimStep(state.copyWith(register: lines, goalColumn: () => null));
    }
    // What goes: the lines, the last lines with the break before them, not
    // one after; an atom reaching past them goes whole with them.
    final (int, int) removed = op == 'c'
        ? (start, end)
        : end == b.length && first > 0
        ? (start - 1, end)
        : end == b.length
        ? (start, end)
        : (start, end + 1);
    final (from, to, wide) = widened(removed.$1, removed.$2);
    final register = wide ? VimRegister(b.slice(from, to)) : lines;
    final text = b.slice(0, from) + b.slice(to, b.length);
    if (op == 'c') {
      return edited(text, from, register: register, mode: VimMode.insert);
    }
    final after = _Buffer(text);
    final line = first.clamp(0, after.lineCount - 1);
    return edited(
      text,
      after.firstNonBlank(after.startOfLine(line)),
      register: register,
    );
  }

  VimStep put(bool after, int count) {
    final register = state.register;
    if (register == null) return VimStep(state);
    final times = register.text * count;
    if (register.linewise) {
      final String text;
      final int first;
      if (after) {
        final end = b.lineEnd(at);
        if (end == b.length) {
          text = '${b.slice(0, end)}\n${times.substring(0, times.length - 1)}';
        } else {
          text = b.slice(0, end + 1) + times + b.slice(end + 1, b.length);
        }
        first = end + 1;
      } else {
        first = b.lineStart(at);
        text = b.slice(0, first) + times + b.slice(first, b.length);
      }
      return edited(text, _Buffer(text).firstNonBlank(first));
    }
    final put = times.characters.length;
    final where = after && b.lineEnd(at) > at ? at + 1 : at;
    final text = b.slice(0, where) + times + b.slice(where, b.length);
    return edited(text, where + put - 1);
  }

  VimStep toggleCase(int count) {
    final end = b.lineEnd(at);
    if (at >= end) return VimStep(state);
    final to = (at + count).clamp(at, end);
    final toggled = [
      for (final c in b.g.sublist(at, to))
        c.toUpperCase() == c ? c.toLowerCase() : c.toUpperCase(),
    ].join();
    final text = b.slice(0, at) + toggled + b.slice(to, b.length);
    return edited(text, _Buffer(text).stand(to));
  }

  /// `r`: [count] graphemes from the cursor become [char], one grapheme
  /// each, an emoji or a combined letter whole.
  VimStep replace(int count, String char) {
    final end = b.lineEnd(at);
    if (char.characters.length != 1 || char == '\n' || at + count > end) {
      return VimStep(state);
    }
    final text = b.slice(0, at) + char * count + b.slice(at + count, b.length);
    return edited(text, at + count - 1);
  }

  VimStep join(int count) {
    var text = value.text;
    var cursor = at;
    final joins = count < 2 ? 1 : count - 1;
    for (var n = 0; n < joins; n++) {
      final buffer = _Buffer(text);
      final end = buffer.lineEnd(cursor);
      if (end == buffer.length) break;
      var next = end + 1;
      while (next < buffer.length &&
          (buffer.g[next] == ' ' || buffer.g[next] == '\t')) {
        next++;
      }
      // What the join takes, the break and the next line's indent, goes as
      // a deletion does: an atom it cuts into goes whole.
      final (cut, kept) = atoms?.call(text, end, next) ?? (end, next);
      final rest = buffer.slice(kept, buffer.length);
      final space =
          rest.isEmpty || rest.startsWith('\n') || cut == buffer.lineStart(cut)
          ? ''
          : ' ';
      text = buffer.slice(0, cut) + space + rest;
      cursor = cut;
    }
    if (text == value.text) return VimStep(state);
    return edited(text, _Buffer(text).stand(cursor));
  }
}
