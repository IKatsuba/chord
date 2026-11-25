// Which key does what: every action chord lets a person rebind, its default
// keys, and the keybindings file that changes them, as the original's
// src/ui/shortcuts/bindings.ts. The file has Claude Code's shape
// (`{ "bindings": [{ "context", "bindings": { key: action } }] }`) and its
// names for the actions it shares, so a block copied from
// `~/.claude/keybindings.json` means the same here. What comes out is a
// framework KeymapData; the framework matches the presses.
import 'dart:convert';

import 'package:chord_tui/chord_tui.dart';

/// Where an action applies, by Claude Code's names for its contexts, and
/// chord's `Agents`, `Selection` and `CodeBlock`, which it has not.
enum KeyContext {
  global('Global'),
  chat('Chat'),
  autocomplete('Autocomplete'),
  confirmation('Confirmation'),
  help('Help'),
  historySearch('HistorySearch'),
  select('Select'),
  modelPicker('ModelPicker'),
  scroll('Scroll'),
  agents('Agents'),
  selection('Selection'),
  codeBlock('CodeBlock');

  const KeyContext(this.name);

  /// As the file writes it.
  final String name;

  static KeyContext? named(String name) =>
      values.where((c) => c.name == name).firstOrNull;
}

/// An action's context and its keys with no file, as the file spells them.
final class ActionSpec {
  const ActionSpec(this.context, this.keys);
  final KeyContext context;
  final List<String> keys;
}

/// Every action a key can be bound to, by Claude Code's name where Claude
/// Code has the action, and chord's for those it binds no name to. The
/// defaults are chord's keys as they were before there was a file.
const Map<String, ActionSpec> actions = {
  'app:toggleTranscript': ActionSpec(KeyContext.global, ['ctrl+o']),
  'history:search': ActionSpec(KeyContext.global, ['ctrl+r']),
  // A leader and a letter, as tmux's prefix and Emacs's ctrl+x.
  'session:attention': ActionSpec(KeyContext.global, ['ctrl+x a']),
  'chat:submit': ActionSpec(KeyContext.chat, ['enter']),
  'chat:newline': ActionSpec(KeyContext.chat, [
    'shift+enter',
    'alt+enter',
    'ctrl+j',
    'ctrl+enter',
  ]),
  // The oldest queued message into the running turn.
  'chat:steer': ActionSpec(KeyContext.chat, ['tab']),
  'chat:cancel': ActionSpec(KeyContext.chat, ['escape']),
  'chat:cycleMode': ActionSpec(KeyContext.chat, ['shift+tab']),
  'chat:externalEditor': ActionSpec(KeyContext.chat, ['ctrl+g']),
  'chat:imagePaste': ActionSpec(KeyContext.chat, ['ctrl+v']),
  'history:previous': ActionSpec(KeyContext.chat, ['up']),
  'history:next': ActionSpec(KeyContext.chat, ['down']),
  'help:toggle': ActionSpec(KeyContext.chat, ['?']),
  'autocomplete:accept': ActionSpec(KeyContext.autocomplete, ['tab']),
  'autocomplete:dismiss': ActionSpec(KeyContext.autocomplete, ['escape']),
  'autocomplete:previous': ActionSpec(KeyContext.autocomplete, ['up']),
  'autocomplete:next': ActionSpec(KeyContext.autocomplete, ['down']),
  'confirm:no': ActionSpec(KeyContext.confirmation, ['escape']),
  'help:dismiss': ActionSpec(KeyContext.help, ['escape']),
  'historySearch:next': ActionSpec(KeyContext.historySearch, ['ctrl+r']),
  'historySearch:accept': ActionSpec(KeyContext.historySearch, [
    'tab',
    'enter',
  ]),
  'historySearch:cancel': ActionSpec(KeyContext.historySearch, ['escape']),
  'agents:close': ActionSpec(KeyContext.agents, ['x']),
  'codeBlock:pick': ActionSpec(KeyContext.global, ['ctrl+x b']),
  'codeBlock:copy': ActionSpec(KeyContext.codeBlock, ['c']),
  'codeBlock:prompt': ActionSpec(KeyContext.codeBlock, ['r']),
  'codeBlock:previous': ActionSpec(KeyContext.codeBlock, ['up']),
  'codeBlock:next': ActionSpec(KeyContext.codeBlock, ['down']),
  'codeBlock:cancel': ActionSpec(KeyContext.codeBlock, ['escape']),
  'select:cancel': ActionSpec(KeyContext.select, ['escape']),
  'select:toggleScope': ActionSpec(KeyContext.select, ['ctrl+a']),
  'modelPicker:decreaseEffort': ActionSpec(KeyContext.modelPicker, ['left']),
  'modelPicker:increaseEffort': ActionSpec(KeyContext.modelPicker, ['right']),
  // Terminal.app keeps pgup, pgdn, home and end for its own scrollback and
  // passes them on only with shift held.
  'scroll:pageUp': ActionSpec(KeyContext.scroll, ['pageup', 'shift+pageup']),
  'scroll:pageDown': ActionSpec(KeyContext.scroll, [
    'pagedown',
    'shift+pagedown',
  ]),
  'scroll:lineUp': ActionSpec(KeyContext.scroll, ['shift+up']),
  'scroll:lineDown': ActionSpec(KeyContext.scroll, ['shift+down']),
  'scroll:top': ActionSpec(KeyContext.scroll, ['home', 'shift+home']),
  'scroll:bottom': ActionSpec(KeyContext.scroll, ['end', 'shift+end']),
  // Live only while a selection is shown; without kitty's protocol it
  // arrives as ctrl+c, which copies a selection shown anyway.
  'selection:copy': ActionSpec(KeyContext.selection, ['ctrl+shift+c']),
};

/// One key press: a key and the modifiers held with it.
final class Keystroke {
  const Keystroke(
    this.key, {
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.cmd = false,
  });

  /// A character, lower case for a letter, or a named key such as `enter`.
  final String key;
  final bool ctrl;

  /// alt, option and meta: the one key a terminal reports for all three.
  final bool alt;
  final bool shift;

  /// cmd, super or win, which only a terminal speaking kitty's protocol
  /// sends.
  final bool cmd;

  /// As the framework matches it.
  KeyCombo get combo => KeyCombo.normalized(
    key,
    ctrl: ctrl,
    alt: alt,
    shift: shift,
    superKey: cmd,
  );

  @override
  bool operator ==(Object other) =>
      other is Keystroke &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.alt == alt &&
      other.shift == shift &&
      other.cmd == cmd;

  @override
  int get hashCode => Object.hash(key, ctrl, alt, shift, cmd);

  @override
  String toString() => _hintName(this);
}

/// Keys pressed one after another; a chord is more than one.
typedef Sequence = List<Keystroke>;

/// A key sequence bound to an action in a context.
final class KeyBinding {
  const KeyBinding(this.context, this.keys, this.action);
  final KeyContext context;
  final Sequence keys;
  final String action;

  @override
  bool operator ==(Object other) =>
      other is KeyBinding &&
      other.context == context &&
      other.action == action &&
      _equal(other.keys, keys);

  @override
  int get hashCode => Object.hash(context, action, Object.hashAll(keys));

  @override
  String toString() => '${context.name} ${sequenceHint(keys)}: $action';
}

/// Every binding, in the order they were bound.
final class Keybindings {
  const Keybindings(this.bindings);
  final List<KeyBinding> bindings;

  /// The keys of each action the file changed, for the framework to move
  /// bindings by id; an action left as it was is not named.
  KeymapData get data => KeymapData({
    for (final action in actions.keys)
      if (!isDefault(this, action))
        action: [
          for (final keys in keysOf(this, action))
            Chord([for (final k in keys) k.combo]),
        ],
  });

  @override
  bool operator ==(Object other) =>
      other is Keybindings &&
      other.bindings.length == bindings.length &&
      [
        for (var i = 0; i < bindings.length; i++)
          other.bindings[i] == bindings[i],
      ].every((same) => same);

  @override
  int get hashCode => Object.hashAll(bindings);
}

/// The named keys, by every name the file may give them.
const _named = {
  'escape': 'escape',
  'esc': 'escape',
  'enter': 'enter',
  'return': 'enter',
  'tab': 'tab',
  'space': 'space',
  'backspace': 'backspace',
  'delete': 'delete',
  'up': 'up',
  'down': 'down',
  'left': 'left',
  'right': 'right',
  'pageup': 'pageup',
  'pagedown': 'pagedown',
  'home': 'home',
  'end': 'end',
};

const _modifiers = {
  'ctrl': 'ctrl',
  'control': 'ctrl',
  'alt': 'alt',
  'opt': 'alt',
  'option': 'alt',
  'meta': 'alt',
  'shift': 'shift',
  'cmd': 'cmd',
  'command': 'cmd',
  'super': 'cmd',
  'win': 'cmd',
};

/// Keys no binding may take, as in Claude Code: ctrl+c and ctrl+d stop and
/// quit, and the rest reach a program as Enter, Esc, Tab and Backspace.
const _reserved = ['ctrl+c', 'ctrl+d', 'ctrl+m', 'ctrl+[', 'ctrl+i', 'ctrl+h'];

/// A keystroke as the file reads, or why it is none.
typedef Parsed<T> = ({T? value, String? problem});

/// One keystroke as the file writes it, `ctrl+shift+p`, or why it is none.
Parsed<Keystroke> parseKeystroke(String text) {
  final lower = text.toLowerCase();
  // A trailing `+` is the plus key itself: `ctrl++`.
  final parts = lower.endsWith('++')
      ? [...lower.substring(0, lower.length - 2).split('+'), '+']
      : lower.split('+');
  final name = parts.removeLast();
  var ctrl = false, alt = false, shift = false, cmd = false;
  for (final part in parts) {
    switch (_modifiers[part]) {
      case 'ctrl':
        ctrl = true;
      case 'alt':
        alt = true;
      case 'shift':
        shift = true;
      case 'cmd':
        cmd = true;
      default:
        return (value: null, problem: '"$part" is not a modifier');
    }
  }
  if (name == 'wheelup' || name == 'wheeldown') {
    return (
      value: null,
      problem: 'the wheel always scrolls the transcript and cannot be bound',
    );
  }
  final key = _named[name] ?? (name.runes.length == 1 ? name : null);
  if (key == null) return (value: null, problem: '"$name" is not a key');
  return (
    value: Keystroke(key, ctrl: ctrl, alt: alt, shift: shift, cmd: cmd),
    problem: null,
  );
}

/// A key sequence as the file writes it, `ctrl+x ctrl+e`, or why it is
/// none.
Parsed<Sequence> parseSequence(String text) {
  final keys = <Keystroke>[];
  for (final stroke in text.trim().split(RegExp(r'\s+'))) {
    if (stroke.isEmpty) return (value: null, problem: 'no key');
    final parsed = parseKeystroke(stroke);
    if (parsed.value == null) return (value: null, problem: parsed.problem);
    keys.add(parsed.value!);
  }
  return (value: keys, problem: null);
}

String _hintName(Keystroke k) => [
  if (k.ctrl) 'ctrl',
  if (k.alt) 'alt',
  if (k.shift) 'shift',
  if (k.cmd) 'cmd',
  k.key == 'escape' ? 'esc' : k.key,
].join('+');

/// The keys as the panel names them, in Claude Code's spelling.
const _panelKeys = {
  'escape': 'esc',
  'up': '↑',
  'down': '↓',
  'left': '←',
  'right': '→',
  'pageup': 'pgup',
  'pagedown': 'pgdn',
};

String _panelName(Keystroke k) => [
  if (k.ctrl) 'ctrl',
  if (k.alt) 'alt',
  if (k.shift) 'shift',
  if (k.cmd) 'cmd',
  _panelKeys[k.key] ?? k.key,
].join(' + ');

/// A sequence as a hint or the status line names it: `ctrl+x ctrl+e`.
String sequenceHint(Sequence keys) => keys.map(_hintName).join(' ');

/// A sequence as the shortcuts panel names it: `ctrl + x ctrl + e`.
String sequencePanel(Sequence keys) => keys.map(_panelName).join(' ');

bool _startsWith(Sequence keys, Sequence start) {
  if (start.length > keys.length) return false;
  for (var i = 0; i < start.length; i++) {
    if (keys[i] != start[i]) return false;
  }
  return true;
}

bool _equal(Sequence a, Sequence b) =>
    a.length == b.length && _startsWith(a, b);

Sequence _sequenceOf(String text) {
  final parsed = parseSequence(text);
  if (parsed.value == null) throw ArgumentError('"$text": ${parsed.problem}');
  return parsed.value!;
}

/// The keys chord binds with no file.
final Keybindings defaultKeymap = Keybindings(
  List.unmodifiable([
    for (final MapEntry(key: action, value: spec) in actions.entries)
      for (final key in spec.keys)
        KeyBinding(spec.context, _sequenceOf(key), action),
  ]),
);

/// Whether [pressed] is one of [action]'s sequences.
bool bound(Keybindings keymap, String action, Sequence? pressed) =>
    pressed != null &&
    keymap.bindings.any((b) => b.action == action && _equal(b.keys, pressed));

/// Every sequence [action] is bound to, in the order they were bound.
List<Sequence> keysOf(Keybindings keymap, String action) => [
  for (final b in keymap.bindings)
    if (b.action == action) b.keys,
];

/// Whether [action] has exactly its default keys.
bool isDefault(Keybindings keymap, String action) {
  final now = keysOf(keymap, action);
  final before = keysOf(defaultKeymap, action);
  if (now.length != before.length) return false;
  for (var i = 0; i < now.length; i++) {
    if (!_equal(now[i], before[i])) return false;
  }
  return true;
}

/// [action]'s first key as a hint names it; none when it has no key.
String? hintKey(Keybindings keymap, String action) {
  final keys = keysOf(keymap, action);
  return keys.isEmpty ? null : sequenceHint(keys.first);
}

/// The contexts heard wherever another is, and before it: the window's keys
/// and the transcript's scrolling, which even a form leaves alone.
const always = [KeyContext.global, KeyContext.scroll];

/// Whether a binding in one context can be pressed while one in another is
/// and neither gives way.
bool _overlap(KeyContext a, KeyContext b) =>
    a == b || always.contains(a) || always.contains(b);

/// The actions that went with tabs: a file that still binds one is told
/// so, not that it names nothing.
final _removed = [
  'session:new',
  'session:next',
  'session:previous',
  for (var n = 1; n <= 9; n++) 'session:goto$n',
  'session:list',
  'session:close',
];

/// Reads a keybindings file's text over the defaults. Each binding in it
/// replaces whatever its key did in its context, as in Claude Code, and
/// `null` takes the key away. A binding that is wrong is a problem and is
/// left out, and the rest of the file still counts; text that is not such
/// a file counts for nothing.
({Keybindings keymap, List<String> problems}) readKeybindings(String text) {
  final Object? input;
  try {
    input = jsonDecode(text);
  } on FormatException catch (error) {
    return (
      keymap: defaultKeymap,
      problems: ['not valid JSON (${error.message}); the file is ignored'],
    );
  }
  final blocks = input is Map ? input['bindings'] : null;
  if (blocks is! List) {
    return (
      keymap: defaultKeymap,
      problems: ['has no "bindings" list; the file is ignored'],
    );
  }

  final problems = <String>[];
  var bindings = [...defaultKeymap.bindings];
  final fromFile = Set<KeyBinding>.identity();

  for (final block in blocks) {
    final rawContext = block is Map ? block['context'] : null;
    final map = block is Map ? block['bindings'] : null;
    final context = rawContext is String ? KeyContext.named(rawContext) : null;
    if (context == null) {
      problems.add(
        rawContext is String
            ? 'unknown context "$rawContext", ignored'
            : 'a block with no "context", ignored',
      );
      continue;
    }
    if (map is! Map) {
      problems.add('${context.name}: "bindings" is not an object, ignored');
      continue;
    }

    for (final MapEntry(key: written, value: action) in map.entries) {
      final parsed = parseSequence(written as String);
      if (parsed.value == null) {
        problems.add('"$written": ${parsed.problem}, ignored');
        continue;
      }
      final keys = parsed.value!;
      final name = sequenceHint(keys);

      if (keys.length == 1 && _reserved.contains(name)) {
        problems.add('$name cannot be rebound, ignored');
        continue;
      }
      if (action != null && action is! String) {
        problems.add('$name: the action is not a name or null, ignored');
        continue;
      }
      if (action != null && _removed.contains(action)) {
        problems.add('$action went with tabs: chord runs one session, ignored');
        continue;
      }
      final spec = actions[action];
      if (action != null && spec == null) {
        problems.add('unknown action "$action", ignored');
        continue;
      }
      if (spec != null && spec.context != context) {
        problems.add(
          '$action belongs in ${spec.context.name}, not ${context.name}; '
          'ignored',
        );
        continue;
      }

      // Two keys the file spells apart that are one key, or one key in two
      // blocks: the first holds.
      final twice = bindings
          .where(
            (b) =>
                fromFile.contains(b) &&
                b.context == context &&
                _equal(b.keys, keys) &&
                b.action != action,
          )
          .firstOrNull;
      if (twice != null) {
        problems.add(
          '$name is bound twice in ${context.name}; ${twice.action} kept',
        );
        continue;
      }

      // A key bound again to the action it has keeps its place.
      if (bindings.any(
        (b) =>
            b.context == context && _equal(b.keys, keys) && b.action == action,
      )) {
        continue;
      }

      final kept = [
        for (final b in bindings)
          if (b.context != context || !_equal(b.keys, keys)) b,
      ];
      if (action == null) {
        bindings = kept;
        continue;
      }

      // A key given a new action in its own context keeps the place the old
      // one had, beside the other contexts' keys, as the defaults have it.
      final replaces = kept.length < bindings.length;
      final clash = replaces
          ? null
          : kept
                .where(
                  (b) =>
                      _overlap(b.context, context) &&
                      b.action != action &&
                      (_startsWith(b.keys, keys) || _startsWith(keys, b.keys)),
                )
                .firstOrNull;
      if (clash != null) {
        problems.add(
          _equal(clash.keys, keys)
              ? '$name already bound to ${clash.action}, not to $action'
              : '$name overlaps ${sequenceHint(clash.keys)} '
                    '(${clash.action}), not bound to $action',
        );
        continue;
      }

      final binding = KeyBinding(context, keys, action as String);
      fromFile.add(binding);
      bindings = [...kept, binding];
    }
  }

  return (keymap: Keybindings(bindings), problems: problems);
}

/// What the status line says of a file's problems: how many, then the
/// first. The count leads so a narrow window cuts only detail; the
/// transcript and stderr list them all.
String? keybindingsNotice(String file, List<String> problems) {
  if (problems.isEmpty) return null;
  return problems.length == 1
      ? '$file: ${problems.first}'
      : '$file: ${problems.length} problems · ${problems.first}';
}

// The "Russian – PC" layout's characters and the US key in each one's
// place, from convert-layout 0.11.1's `ru` table (ru.toEn), which the
// original uses. convert-layout is Copyright 2015 Andrey Sitnik, under the
// MIT License. No maintained Dart package carries it; see
// docs/decisions.md.
const _russianPc = {
  'Ё': '~', 'А': 'F', 'Б': '<', 'В': 'D', 'Г': 'U', 'Д': 'L', 'Е': 'T', //
  'Ж': ':', 'З': 'P', 'И': 'B', 'Й': 'Q', 'К': 'R', 'Л': 'K', 'М': 'V', //
  'Н': 'Y', 'О': 'J', 'П': 'G', 'Р': 'H', 'С': 'C', 'Т': 'N', 'У': 'E', //
  'Ф': 'A', 'Х': '{', 'Ц': 'W', 'Ч': 'X', 'Ш': 'I', 'Щ': 'O', 'Ъ': '}', //
  'Ы': 'S', 'Ь': 'M', 'Э': '"', 'Ю': '>', 'Я': 'Z', //
  'а': 'f', 'б': ',', 'в': 'd', 'г': 'u', 'д': 'l', 'е': 't', 'ж': ';', //
  'з': 'p', 'и': 'b', 'й': 'q', 'к': 'r', 'л': 'k', 'м': 'v', 'н': 'y', //
  'о': 'j', 'п': 'g', 'р': 'h', 'с': 'c', 'т': 'n', 'у': 'e', 'ф': 'a', //
  'х': '[', 'ц': 'w', 'ч': 'x', 'ш': 'i', 'щ': 'o', 'ъ': ']', 'ы': 's', //
  'ь': 'm', 'э': "'", 'ю': '.', 'я': 'z', 'ё': '`', '№': '#', //
};

/// Where Apple's "Russian" layout puts a character somewhere other than
/// "Russian – PC" does. Apple's keeps `/` and `?` on the US key, so of the
/// characters a US layout cannot type only ё moves: onto the backslash
/// key, not the backquote.
const _appleRussian = {'ё': r'\', 'Ё': '|'};

/// The US characters a press would have typed in the same place, had the
/// layout been US rather than Russian; none for a character a US layout
/// types itself. Those are left alone because a press cannot say which
/// layout it came from: `,` is where `?` is on "Russian – PC", and
/// translating it would open the panel for a US layout's first comma.
/// Russian – PC's first, then Apple's where it differs. The window's
/// [KeyLayoutFallback].
List<String> layoutKeys(String typed) {
  if (typed.runes.length != 1 || typed.runes.first < 0x80) return const [];
  final keys = <String>[];
  for (final key in [_russianPc[typed], _appleRussian[typed]]) {
    if (key != null && key != typed && !keys.contains(key)) keys.add(key);
  }
  return keys;
}
