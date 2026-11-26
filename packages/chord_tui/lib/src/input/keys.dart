import 'package:meta/meta.dart';

import '../foundation/geometry.dart';

/// Something the terminal sent.
sealed class InputEvent {
  const InputEvent();
}

/// Text pasted with bracketed paste: delivered whole, not as keys.
final class PasteEvent extends InputEvent {
  /// A paste of [text].
  const PasteEvent(this.text);

  /// The pasted text, whole.
  final String text;

  @override
  String toString() => 'PasteEvent(${text.length} chars)';
}

/// A terminal's reply to an Operating System Command: `ESC ] code ; data`
/// ended by BEL or `ESC \`. Never a key.
final class OscEvent extends InputEvent {
  /// The reply to OSC [code], carrying [data].
  const OscEvent(this.code, this.data);

  /// The command it answers: 11 for the background colour.
  final int code;

  /// What it says, as `rgb:ffff/ffff/ffff`.
  final String data;

  @override
  String toString() => 'OscEvent($code, $data)';
}

/// A terminal's current kitty keyboard enhancement flags, never a key.
final class KeyboardProtocolEvent extends InputEvent {
  /// A reply to the current-flags query.
  const KeyboardProtocolEvent(this.flags);

  /// The flags reported by the terminal.
  final int flags;

  @override
  String toString() => 'KeyboardProtocolEvent($flags)';
}

/// The kind of a terminal mouse report.
enum MouseEventKind {
  /// One wheel step, without a simultaneous button press.
  wheel,

  /// A button was pressed.
  press,

  /// A button was released at its current position.
  release,

  /// A held button moved to another terminal cell.
  move,

  /// The host cancelled an unfinished captured gesture.
  cancel,
}

/// The ordinary mouse buttons represented by SGR reports.
enum MouseButton {
  /// No button, as for a wheel report.
  none,

  /// The primary button.
  primary,

  /// The middle button.
  middle,

  /// The secondary button.
  secondary,
}

/// One mouse report in zero-based terminal cells, independent of focus.
final class MouseEvent extends InputEvent {
  /// A button report, wheel step or synthetic cancellation at [position].
  const MouseEvent(
    this.kind, {
    required this.position,
    this.button = MouseButton.none,
    this.scrollDelta = Offset.zero,
    this.shift = false,
    this.alt = false,
    this.ctrl = false,
  });

  /// The button, wheel or synthetic cancellation kind.
  final MouseEventKind kind;

  /// Zero-based terminal coordinates, not widget-local coordinates.
  final Offset position;

  /// The pressed, held or released button; none for a wheel.
  final MouseButton button;

  /// Whole-cell wheel steps, with negative y upward and negative x leftward.
  ///
  /// runApp merges adjacent wheel reports from one terminal read into one
  /// report, so a step may be more than one cell; scroll by its size.
  final Offset scrollDelta;

  /// Whether Shift was held.
  final bool shift;

  /// Whether Alt was held.
  final bool alt;

  /// Whether Control was held.
  final bool ctrl;

  @override
  String toString() =>
      'MouseEvent(${kind.name}, $position, ${button.name}, $scrollDelta)';
}

/// One key press.
///
/// [key] is the character for printable keys (`a`, `A`, `?`, `й`) and a
/// name otherwise: `enter`, `tab`, `backspace`, `escape`, `space`, `up`,
/// `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown`, `insert`,
/// `delete`, `f1`…`f12`.
final class KeyEvent extends InputEvent {
  /// A press of [key] with the modifiers held.
  const KeyEvent(
    this.key, {
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.superKey = false,
    this.hyper = false,
    this.meta = false,
    this.baseKey,
    this.typed,
  });

  /// The key: its character when printable, otherwise its name.
  final String key;

  /// Whether Ctrl was held.
  final bool ctrl;

  /// Whether Alt (Option on macOS) was held.
  final bool alt;

  /// Whether Shift was held.
  final bool shift;

  /// The Super modifier, called Command on macOS.
  final bool superKey;

  /// The Hyper modifier, distinct from Super and Meta.
  final bool hyper;

  /// The Meta modifier, distinct from Alt.
  final bool meta;

  /// The key in this press's place on the US PC-101 layout, as a terminal
  /// speaking kitty's keyboard protocol names it: `x` for `ctrl+ч`. Null
  /// when the terminal named none, or named a control code or one of the
  /// protocol's private-use functional keys.
  final String? baseKey;

  /// The press as it was typed, when this event is a reading of it on
  /// another layout; null for a press as the terminal sent it.
  final KeyEvent? typed;

  /// The press as made on the US layout, with these modifiers: a letter
  /// keeps shift, any other key with shift becomes what US PC-101 types
  /// there with shift, the shift spent. Null when [baseKey] is null or
  /// reads as this very press.
  KeyEvent? get onBaseLayout {
    final base = baseKey;
    if (base == null) return null;
    final shifted = shift && base.toLowerCase() == base.toUpperCase()
        ? _usShifted[base]
        : null;
    final reading = KeyEvent(
      shifted ?? base,
      ctrl: ctrl,
      alt: alt,
      shift: shifted == null && shift,
      superKey: superKey,
      hyper: hyper,
      meta: meta,
      typed: this,
    );
    return reading.combo == combo ? null : reading;
  }

  /// The text this key types, or null when it types nothing; a reading on
  /// another layout never types.
  String? get char {
    if (typed != null) return null;
    if (ctrl || alt || superKey || hyper || meta) return null;
    if (key == 'space') return ' ';
    return key.runes.length == 1 ? key : null;
  }

  /// The press as a [KeyCombo], to match against bindings.
  KeyCombo get combo => KeyCombo.normalized(
    key,
    ctrl: ctrl,
    alt: alt,
    shift: shift,
    superKey: superKey,
    hyper: hyper,
    meta: meta,
  );

  @override
  String toString() =>
      'KeyEvent($combo${baseKey == null ? '' : ' base $baseKey'})';
}

/// What US PC-101 types with shift in each unshifted key's place.
const _usShifted = {
  '`': '~',
  '1': '!',
  '2': '@',
  '3': '#',
  '4': r'$',
  '5': '%',
  '6': '^',
  '7': '&',
  '8': '*',
  '9': '(',
  '0': ')',
  '-': '_',
  '=': '+',
  '[': '{',
  ']': '}',
  r'\': '|',
  ';': ':',
  "'": '"',
  ',': '<',
  '.': '>',
  '/': '?',
};

const _aliases = {
  'esc': 'escape',
  'return': 'enter',
  'cr': 'enter',
  'del': 'delete',
  'ins': 'insert',
  'pgup': 'pageup',
  'pgdn': 'pagedown',
  'bs': 'backspace',
  ' ': 'space',
  'control': 'ctrl',
  'option': 'alt',
  'cmd': 'super',
  'command': 'super',
};

/// A key with its modifiers, as written in a binding: `ctrl+o`, `shift+tab`.
@immutable
class KeyCombo {
  const KeyCombo._(
    this.key,
    this.ctrl,
    this.alt,
    this.shift,
    this.superKey,
    this.hyper,
    this.meta,
  );

  /// [key] with an upper-case letter turned into `shift` + the lower one.
  factory KeyCombo.normalized(
    String key, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool superKey = false,
    bool hyper = false,
    bool meta = false,
  }) {
    var k = _aliases[key] ?? key;
    if (k.runes.length == 1) {
      final lower = k.toLowerCase();
      if (lower != k) {
        k = lower;
        // A terminal cannot tell ctrl+O from ctrl+o, so with ctrl the
        // case of a letter means nothing.
        if (!ctrl) shift = true;
      }
    } else {
      k = k.toLowerCase();
      k = _aliases[k] ?? k;
    }
    return KeyCombo._(k, ctrl, alt, shift, superKey, hyper, meta);
  }

  /// Parses `ctrl+o`, `alt+shift+up`, `G`, `?`, `ctrl++`.
  factory KeyCombo.parse(String text) {
    final s = text.trim();
    if (s.isEmpty) throw FormatException('Empty key', text);
    String key;
    List<String> mods;
    if (s == '+') {
      key = '+';
      mods = const [];
    } else if (s.endsWith('++')) {
      key = '+';
      mods = s.substring(0, s.length - 2).split('+');
    } else {
      final parts = s.split('+');
      key = parts.removeLast();
      mods = parts;
    }
    var ctrl = false, alt = false, shift = false;
    var superKey = false, hyper = false, meta = false;
    for (final m in mods) {
      switch (_aliases[m.toLowerCase()] ?? m.toLowerCase()) {
        case 'ctrl':
          ctrl = true;
        case 'alt':
          alt = true;
        case 'shift':
          shift = true;
        case 'super':
          superKey = true;
        case 'hyper':
          hyper = true;
        case 'meta':
          meta = true;
        default:
          throw FormatException('Unknown modifier "$m"', text);
      }
    }
    return KeyCombo.normalized(
      key,
      ctrl: ctrl,
      alt: alt,
      shift: shift,
      superKey: superKey,
      hyper: hyper,
      meta: meta,
    );
  }

  /// The key: its character when printable, otherwise its name.
  final String key;

  /// Whether Ctrl is part of the combo.
  final bool ctrl;

  /// Whether Alt (Option on macOS) is part of the combo.
  final bool alt;

  /// Whether Shift is part of the combo.
  final bool shift;

  /// The Super modifier, called Command on macOS.
  final bool superKey;

  /// The Hyper modifier, distinct from Super and Meta.
  final bool hyper;

  /// The Meta modifier, distinct from Alt.
  final bool meta;

  /// The event a terminal sends for this combo.
  KeyEvent toEvent() {
    final k =
        shift && key.runes.length == 1 && key.toUpperCase() != key && !ctrl
        ? key.toUpperCase()
        : key;
    final s = k != key ? false : shift;
    return KeyEvent(
      k,
      ctrl: ctrl,
      alt: alt,
      shift: s,
      superKey: superKey,
      hyper: hyper,
      meta: meta,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KeyCombo &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.alt == alt &&
      other.shift == shift &&
      other.superKey == superKey &&
      other.hyper == hyper &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(key, ctrl, alt, shift, superKey, hyper, meta);

  @override
  String toString() => [
    if (ctrl) 'ctrl',
    if (alt) 'alt',
    if (shift) 'shift',
    if (superKey) 'super',
    if (hyper) 'hyper',
    if (meta) 'meta',
    key,
  ].join('+');
}

/// A sequence of combos pressed one after another: `ctrl+x a`.
@immutable
class Chord {
  /// A chord of [combos], pressed in order.
  const Chord(this.combos);

  /// Parses combos separated by spaces, such as `ctrl+x a`.
  factory Chord.parse(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      throw FormatException('Empty chord', text);
    }
    return Chord(
      List<KeyCombo>.unmodifiable([for (final p in parts) KeyCombo.parse(p)]),
    );
  }

  /// The combos, in the order they are pressed.
  final List<KeyCombo> combos;

  /// How many combos the chord takes.
  int get length => combos.length;

  /// Whether this chord begins with [prefix] and is longer than it.
  bool startsWith(List<KeyCombo> prefix) {
    if (prefix.length >= combos.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (combos[i] != prefix[i]) return false;
    }
    return true;
  }

  /// Whether [seq] is exactly this chord.
  bool matches(List<KeyCombo> seq) {
    if (seq.length != combos.length) return false;
    for (var i = 0; i < seq.length; i++) {
      if (combos[i] != seq[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) => other is Chord && matches(other.combos);

  @override
  int get hashCode => Object.hashAll(combos);

  @override
  String toString() => combos.join(' ');
}
