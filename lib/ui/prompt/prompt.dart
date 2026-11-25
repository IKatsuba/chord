import 'package:chord_tui/chord_tui.dart';
import 'package:characters/characters.dart';

import '../shortcuts/bindings.dart';

/// The prompt's share of the window, leaving room for the transcript.
int promptRows(int windowRows) => (windowRows ~/ 3).clamp(3, 10);

/// The prompt start, or an arrow where scrolling hides rows.
String gutterMark(TextAreaRow row, List<TextAreaRow> shown) {
  if (row.line == 0 && row.piece == 0) return '›';
  if (shown.every((other) => !_before(other, row))) return '↑';
  if (!row.last && shown.every((other) => !_before(row, other))) return '↓';
  return '';
}

bool _before(TextAreaRow a, TextAreaRow b) =>
    a.line < b.line || (a.line == b.line && a.piece < b.piece);

/// A draft cursor in the framework controller's grapheme offsets.
// The original's line/UTF-16 pair is a JS unit; native offsets avoid a mapping.
typedef Cursor = int;

/// The empty draft's cursor.
const startCursor = 0;

/// The controller offset at the end of a draft.
Cursor endOf(String text) => text.characters.length;

/// A backslash immediately before Enter becomes a newline instead of sending.
({String text, Cursor cursor})? continued(String text, Cursor cursor) {
  final chars = text.characters.toList();
  if (cursor <= 0 || cursor > chars.length || chars[cursor - 1] != '\\') {
    return null;
  }
  chars[cursor - 1] = '\n';
  return (text: chars.join(), cursor: cursor);
}

/// The keys the text area acts on itself, by their hint names, and the
/// action each is when it is one of chord's, as the original's TEXTAREA:
/// it sends, breaks the line, and hands ↑ and ↓ at its edges to history.
const _textarea = <String, String?>{
  'enter': 'chat:submit',
  'ctrl+j': 'chat:newline',
  'ctrl+enter': 'chat:newline',
  'shift+enter': 'chat:newline',
  'alt+enter': 'chat:newline',
  'up': 'history:previous',
  'down': 'history:next',
  'left': null,
  'right': null,
  'alt+b': null,
  'alt+f': null,
  'alt+left': null,
  'alt+right': null,
  'cmd+left': null,
  'cmd+right': null,
  'ctrl+a': null,
  'ctrl+e': null,
  'ctrl+w': null,
  'ctrl+u': null,
  'ctrl+k': null,
  'backspace': null,
  'delete': null,
  'alt+backspace': null,
  'ctrl+z': null,
  'ctrl+y': null,
};

/// The text area's keys the original's prompt never lets it have, as the
/// framework spells them: all but its TEXTAREA list and the three cmd keys
/// its `textareaTakes` lets through as printable text with neither ctrl
/// nor alt (select all, undo, redo). Every other key is the window's.
final Set<String> textareaKeysNotReached = {
  for (final keys in TextArea.editingKeys.keys)
    if (!_textareaKeys.contains(keys) &&
        !const {'super+a', 'super+z', 'shift+super+z'}.contains(keys))
      keys,
};

final _textareaKeys = {
  for (final name in _textarea.keys) frameworkKeys(parseSequence(name).value!),
};

/// The contexts whose keys the box hears while it has them.
const _box = [KeyContext.chat, ...always];

/// [keys] as the framework spells them.
String frameworkKeys(Sequence keys) => keys.map((k) => '${k.combo}').join(' ');

/// The text area's keys turned off for [keymap], as the framework spells
/// them: its send and line break on a key no longer bound to them, which
/// the prompt then does itself, any of its editing keys a binding gives to
/// the window, so the key does one thing, and any that begins one of
/// [chords], the ones that would run now. ↑ and ↓ otherwise always move
/// between lines.
Set<String> textareaKeysOff(
  Keybindings keymap, [
  List<Chord> chords = const [],
]) => {
  for (final MapEntry(key: name, value: action) in _textarea.entries)
    if (!_kept(keymap, chords, name, action))
      frameworkKeys(parseSequence(name).value!),
};

bool _kept(
  Keybindings keymap,
  List<Chord> chords,
  String name,
  String? action,
) {
  final combo = parseSequence(name).value!.single.combo;
  if (chords.any((c) => c.length > 1 && c.combos.first == combo)) {
    return false;
  }
  if (action == 'history:previous' || action == 'history:next') return true;
  final bindings = [
    for (final b in keymap.bindings)
      if (_box.contains(b.context) &&
          b.keys.length == 1 &&
          sequenceHint(b.keys) == name)
        b,
  ];
  return action == null
      ? bindings.isEmpty
      : bindings.any((b) => b.action == action);
}

/// The keys [action] is bound to that the text area does not do itself:
/// the prompt binds those.
List<String> promptKeys(Keybindings keymap, String action, Set<String> off) => [
  for (final keys in keysOf(keymap, action))
    if (keys.length != 1 ||
        _textarea[sequenceHint(keys)] != action ||
        off.contains(frameworkKeys(keys)))
      frameworkKeys(keys),
];
