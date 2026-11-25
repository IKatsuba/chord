import '../foundation/geometry.dart';
import 'keys.dart';

const _pasteEnd = '\x1b[201~';

/// The longest OSC reply data held before it is taken for typed text.
const _oscMax = 1024;

/// The most digits an OSC code may have; real ones have four at most, and
/// nine keep it an int on every platform.
const _oscCodeDigits = 9;

// A bounded control fragment and decimal fields cannot pin an input stream.
const _csiMax = 128;

/// Turns what the terminal sends into [InputEvent]s.
///
/// Feed it text as it arrives; a sequence split between two reads is kept
/// until the rest comes. A lone escape stays pending until [flush], which
/// the caller runs after a short pause.
class InputParser {
  /// A parser with nothing pending.
  InputParser();

  /// Whether LF is read as enter rather than ctrl+j: for a terminal whose
  /// raw mode still turns Enter's CR into LF, where nothing else sends LF.
  bool linefeedIsEnter = false;

  String _rest = '';
  StringBuffer? _paste;
  bool _discardCsi = false;
  bool _csiTimedOut = false;

  /// Discards fragments and an unfinished paste when input ownership changes.
  void reset() {
    _rest = '';
    _paste = null;
    _discardCsi = false;
    _csiTimedOut = false;
  }

  /// Whether something is waiting for more input or for [flush].
  bool get hasPending => _rest.isNotEmpty || (_discardCsi && !_csiTimedOut);

  /// Whether an OSC reply is half read, so the caller can wait longer than
  /// for a lone escape before [flush] gives it back as keys.
  bool get hasPendingOsc => _paste == null && _rest.startsWith('\x1b]');

  /// Whether a CSI control is fragmented, allowing a reply-length timeout.
  bool get hasPendingCsi => _paste == null && _rest.startsWith('\x1b[');

  /// Parses [data] after what came before, answering the events it completes.
  List<InputEvent> feed(String data) {
    final out = <InputEvent>[];
    var s = _rest + data;
    _rest = '';
    var i = 0;
    while (i < s.length) {
      if (_discardCsi) {
        while (i < s.length &&
            !_isFinal(s.codeUnitAt(i)) &&
            s.codeUnitAt(i) != 0x1b) {
          i++;
        }
        if (i == s.length) return out;
        // A fresh escape starts a new control even after an expired one.
        if (s.codeUnitAt(i) != 0x1b) i++;
        _discardCsi = false;
        _csiTimedOut = false;
        continue;
      }
      final paste = _paste;
      if (paste != null) {
        final end = s.indexOf(_pasteEnd, i);
        if (end < 0) {
          // Keep a possible partial terminator for the next read.
          var keep = 0;
          for (var k = 1; k < _pasteEnd.length && k <= s.length - i; k++) {
            if (_pasteEnd.startsWith(s.substring(s.length - k))) keep = k;
          }
          paste.write(s.substring(i, s.length - keep));
          _rest = s.substring(s.length - keep);
          return out;
        }
        paste.write(s.substring(i, end));
        out.add(
          PasteEvent(
            paste.toString().replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
          ),
        );
        _paste = null;
        i = end + _pasteEnd.length;
        continue;
      }

      final c = s.codeUnitAt(i);
      if (c != 0x1b) {
        final cp = _runeAt(s, i);
        out.add(_single(cp));
        i += cp > 0xffff ? 2 : 1;
        continue;
      }

      if (i + 1 >= s.length) {
        _rest = s.substring(i);
        return out;
      }
      final next = s[i + 1];
      if (next == ']') {
        final end = _osc(s, i, out);
        if (end < 0) {
          _rest = s.substring(i);
          return out;
        }
        i = end;
      } else if (next == '[') {
        var j = i + 2;
        while (j < s.length) {
          final b = s.codeUnitAt(j);
          if (_isFinal(b) || b == 0x1b) break;
          j++;
        }
        if (j < s.length && s.codeUnitAt(j) == 0x1b) {
          i = j;
          continue;
        }
        if (j - i > _csiMax) {
          _discardCsi = j >= s.length;
          i = j < s.length ? j + 1 : j;
          continue;
        }
        if (j >= s.length) {
          _rest = s.substring(i);
          return out;
        }
        // Legacy mouse report: ESC [ M and three bytes. Dropped for now.
        if (s[j] == 'M' && j == i + 2) {
          if (j + 3 >= s.length) {
            _rest = s.substring(i);
            return out;
          }
          i = j + 4;
          continue;
        }
        final params = s.substring(i + 2, j);
        final ev = _csi(params, s[j]);
        if (ev != null) out.add(ev);
        i = j + 1;
      } else if (next == 'O') {
        if (i + 2 >= s.length) {
          _rest = s.substring(i);
          return out;
        }
        final ev = _ss3(s[i + 2]);
        if (ev != null) out.add(ev);
        i += 3;
      } else if (next == '\x1b') {
        out.add(const KeyEvent('escape'));
        i += 1;
      } else {
        final cp = _runeAt(s, i + 1);
        final k = _single(cp);
        if (k is KeyEvent) {
          out.add(KeyEvent(k.key, ctrl: k.ctrl, alt: true, shift: k.shift));
        }
        i += 1 + (cp > 0xffff ? 2 : 1);
      }
    }
    return out;
  }

  /// Resolves what is pending: a lone escape becomes the escape key.
  /// An expired CSI retains no bytes; a late tail is consumed through its
  /// final byte, or a fresh escape starts a new control. An unfinished paste
  /// remains pending until its terminator or [reset].
  List<InputEvent> flush() {
    if (_paste != null) return const [];
    if (_discardCsi) {
      _csiTimedOut = true;
      return const [];
    }
    final r = _rest;
    _rest = '';
    if (r == '\x1b') return const [KeyEvent('escape')];
    if (r.startsWith('\x1b[')) {
      // Retain no bytes or timer, but swallow a late control tail through its
      // final byte rather than inventing text from a fragmented reply.
      _discardCsi = true;
      _csiTimedOut = true;
      return const [];
    }
    if (r.startsWith('\x1b]')) {
      final out = <InputEvent>[_altBracket];
      _typed(r, 2, r.length, out);
      return out;
    }
    if (r.isEmpty) return const [];
    return feed(r.substring(1))..insert(0, const KeyEvent('escape'));
  }

  static const _altBracket = KeyEvent(']', alt: true);

  /// Reads the OSC reply at [start] (`ESC ]`) into [out] and returns where
  /// parsing goes on, or -1 when the reply is not complete yet. What is not a
  /// reply gives its keys back: alt+], then what followed as typed text.
  int _osc(String s, int start, List<InputEvent> out) {
    final codeStart = start + 2;
    var j = codeStart;
    while (j < s.length && _isDigit(s.codeUnitAt(j))) {
      if (j - codeStart == _oscCodeDigits) return _broken(s, start, j, out);
      j++;
    }
    if (j >= s.length) return -1;
    if (j == codeStart || s[j] != ';') return _broken(s, start, j, out);
    final dataStart = j + 1;
    for (j = dataStart; j < s.length; j++) {
      final c = s.codeUnitAt(j);
      if (c == 0x07) return _reply(s, codeStart, dataStart, j, j + 1, out);
      if (c == 0x1b) {
        if (j + 1 >= s.length) return -1;
        if (s[j + 1] != '\\') return _broken(s, start, j, out);
        return _reply(s, codeStart, dataStart, j, j + 2, out);
      }
      if (c < 0x20 || c == 0x7f || j - dataStart == _oscMax) {
        return _broken(s, start, j, out);
      }
    }
    return -1;
  }

  int _reply(
    String s,
    int codeStart,
    int dataStart,
    int dataEnd,
    int next,
    List<InputEvent> out,
  ) {
    final code = int.parse(s.substring(codeStart, dataStart - 1));
    out.add(OscEvent(code, s.substring(dataStart, dataEnd)));
    return next;
  }

  int _broken(String s, int start, int at, List<InputEvent> out) {
    out.add(_altBracket);
    _typed(s, start + 2, at, out);
    return at;
  }

  /// [s] from [from] to [to] as keys typed one by one.
  void _typed(String s, int from, int to, List<InputEvent> out) {
    var i = from;
    while (i < to) {
      final cp = _runeAt(s, i);
      out.add(_single(cp));
      i += cp > 0xffff ? 2 : 1;
    }
  }

  static bool _isFinal(int c) => c >= 0x40 && c <= 0x7e;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  int _runeAt(String s, int i) {
    final c = s.codeUnitAt(i);
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
      final d = s.codeUnitAt(i + 1);
      return 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00);
    }
    return c;
  }

  InputEvent _single(int c) {
    switch (c) {
      case 0x0d:
        return const KeyEvent('enter');
      // A raw terminal sends CR for Enter; LF is what ctrl+j sends, which
      // OpenTUI names linefeed and binds to a new line, apart from Enter.
      case 0x0a:
        return linefeedIsEnter
            ? const KeyEvent('enter')
            : const KeyEvent('j', ctrl: true);
      case 0x09:
        return const KeyEvent('tab');
      case 0x7f || 0x08:
        return const KeyEvent('backspace');
      case 0x1b:
        return const KeyEvent('escape');
      case 0x00:
        return const KeyEvent('space', ctrl: true);
      case 0x20:
        return const KeyEvent('space');
      case >= 0x01 && <= 0x1a:
        return KeyEvent(String.fromCharCode(c + 0x60), ctrl: true);
      case >= 0x1c && <= 0x1f:
        return KeyEvent(String.fromCharCode(c + 0x40), ctrl: true);
    }
    return KeyEvent(String.fromCharCode(c));
  }

  static const _tilde = {
    1: 'home',
    7: 'home',
    2: 'insert',
    3: 'delete',
    4: 'end',
    8: 'end',
    5: 'pageup',
    6: 'pagedown',
    11: 'f1',
    12: 'f2',
    13: 'f3',
    14: 'f4',
    15: 'f5',
    17: 'f6',
    18: 'f7',
    19: 'f8',
    20: 'f9',
    21: 'f10',
    23: 'f11',
    24: 'f12',
  };

  static const _letters = {
    'A': 'up',
    'B': 'down',
    'C': 'right',
    'D': 'left',
    'H': 'home',
    'F': 'end',
    'P': 'f1',
    'Q': 'f2',
    'R': 'f3',
    'S': 'f4',
  };

  KeyEvent _withMods(String key, int? m, [String? baseKey]) {
    final bits = (m ?? 1) - 1;
    return KeyEvent(
      key,
      baseKey: baseKey,
      shift: bits & 1 != 0,
      alt: bits & 2 != 0,
      ctrl: bits & 4 != 0,
      superKey: bits & 8 != 0,
      hyper: bits & 16 != 0,
      meta: bits & 32 != 0,
    );
  }

  static int? _integer(String text) =>
      text.isEmpty || text.length > 9 || !text.codeUnits.every(_isDigit)
      ? null
      : int.tryParse(text);

  static bool _scalar(int value) =>
      value >= 0 && value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff);

  static const _functional = {
    57344: 'escape',
    57345: 'enter',
    57346: 'tab',
    57347: 'backspace',
    57348: 'insert',
    57349: 'delete',
    57350: 'left',
    57351: 'right',
    57352: 'up',
    57353: 'down',
    57354: 'pageup',
    57355: 'pagedown',
    57356: 'home',
    57357: 'end',
    57414: 'enter',
    57417: 'left',
    57418: 'right',
    57419: 'up',
    57420: 'down',
    57421: 'pageup',
    57422: 'pagedown',
    57423: 'home',
    57424: 'end',
    57425: 'insert',
    57426: 'delete',
  };

  String? _keyName(int code) {
    final known = _functional[code];
    if (known != null) return known;
    if (code >= 57364 && code <= 57375) return 'f${code - 57363}';
    return switch (code) {
      13 => 'enter',
      9 => 'tab',
      27 => 'escape',
      127 => 'backspace',
      32 => 'space',
      _
          when !_scalar(code) ||
              code < 32 ||
              (code >= 0x7f && code <= 0x9f) ||
              (code >= 57344 && code <= 63743) =>
        null,
      _ => String.fromCharCode(code),
    };
  }

  /// kitty's base-layout key, lower-cased as a letter's case is shift's;
  /// none for a control code or a private-use functional key.
  static String? _base(String field) {
    final code = _integer(field);
    if (code == null ||
        code <= 0x20 ||
        (code >= 0x7f && code <= 0x9f) ||
        (code >= 57344 && code <= 63743)) {
      return null;
    }
    return String.fromCharCode(code).toLowerCase();
  }

  InputEvent? _csi(String params, String fin) {
    if (params.startsWith('<') && (fin == 'M' || fin == 'm')) {
      return _mouse(params.substring(1), fin);
    }
    if (params == '200' && fin == '~') {
      _paste = StringBuffer();
      return null;
    }
    if (fin == 'u' && params.startsWith('?')) {
      final flags = _integer(params.substring(1));
      return flags == null ? null : KeyboardProtocolEvent(flags);
    }
    if (!RegExp(r'^[0-9:;]*$').hasMatch(params)) return null;
    final fields = params.split(';');
    if (fields.length > 3) return null;
    final keyParts = fields.first.split(':');
    if (keyParts.length > 3) return null;
    for (final alternate in keyParts.skip(1)) {
      if (alternate.isNotEmpty) {
        final code = _integer(alternate);
        if (code == null || !_scalar(code)) return null;
      }
    }
    final code = _integer(keyParts.first);
    if (keyParts.first.isNotEmpty && code == null) return null;
    final modifiers = fields.length > 1 ? fields[1].split(':') : <String>[];
    if (modifiers.length > 2) return null;
    final mod = modifiers.isEmpty || modifiers.first.isEmpty
        ? 1
        : _integer(modifiers.first);
    if (mod == null || mod < 1 || mod > 256) return null;
    final type = modifiers.length < 2 || modifiers[1].isEmpty
        ? 1
        : _integer(modifiers[1]);
    if (type != 1 && type != 2 && type != 3) return null;
    if (fields.length == 3 && fields[2].isNotEmpty) {
      for (final text in fields[2].split(':')) {
        final value = _integer(text);
        if (value == null || !_scalar(value)) return null;
      }
    }
    if (type == 3) return null;
    switch (fin) {
      case 'Z':
        return const KeyEvent('tab', shift: true);
      case '~':
        final name = _tilde[code];
        return name == null ? null : _withMods(name, mod);
      case 'u':
        if (code == null) return null;
        final name = _keyName(code);
        return name == null
            ? null
            : _withMods(
                name,
                mod,
                keyParts.length > 2 ? _base(keyParts[2]) : null,
              );
      default:
        final name = _letters[fin];
        if (name == null) return null;
        // `1;5A` and the rare `5A` both mean ctrl+up.
        return _withMods(
          name,
          fields.length > 1 ? mod : (code != null && code > 1 ? code : null),
        );
    }
  }

  MouseEvent? _mouse(String params, String fin) {
    final fields = params.split(';');
    if (fields.length != 3) return null;
    final button = _integer(fields[0]);
    final x = _integer(fields[1]), y = _integer(fields[2]);
    if (button == null ||
        button > 127 ||
        x == null ||
        y == null ||
        x <= 0 ||
        y <= 0) {
      return null;
    }
    final low = button & 3;
    final wheel = button & 64 != 0;
    final motion = button & 32 != 0;
    if ((wheel && (fin != 'M' || motion)) ||
        (!wheel && low == 3) ||
        (motion && fin != 'M')) {
      return null;
    }
    return MouseEvent(
      wheel
          ? MouseEventKind.wheel
          : motion
          ? MouseEventKind.move
          : fin == 'm'
          ? MouseEventKind.release
          : MouseEventKind.press,
      position: Offset(x - 1, y - 1),
      button: wheel
          ? MouseButton.none
          : [
              MouseButton.primary,
              MouseButton.middle,
              MouseButton.secondary,
            ][low],
      scrollDelta: wheel
          ? const [
              Offset(0, -1),
              Offset(0, 1),
              Offset(-1, 0),
              Offset(1, 0),
            ][low]
          : Offset.zero,
      shift: button & 4 != 0,
      alt: button & 8 != 0,
      ctrl: button & 16 != 0,
    );
  }

  InputEvent? _ss3(String fin) {
    final name = _letters[fin];
    return name == null ? null : KeyEvent(name);
  }
}
