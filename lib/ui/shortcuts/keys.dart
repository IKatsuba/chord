import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import 'bindings.dart';

/// An editorial shortcut row and the real binding spellings it documents.
final class Shortcut {
  const Shortcut(
    this.key,
    this.does,
    this.presses, {
    this.actions = const [],
    this.before,
    this.after,
    this.also,
    this.first = false,
  });
  final String key;
  final String does;
  final List<String> presses;

  /// The actions whose keys [key] names, in its order; a key the
  /// keybindings file binds elsewhere is named as bound. None for a fixed
  /// key.
  final List<String> actions;

  /// Written before the bound keys when [actions] are named as bound.
  final String? before;

  /// An action whose first key, after [before], is named after [actions]'
  /// own as another way to it, `or` between them.
  final String? after;

  /// What also does it, named after the bound keys, and alone when none is.
  final String? also;

  /// Only the first key bound is named.
  final bool first;
}

/// The original's shortcuts, in its display order and wording.
const shortcuts = [
  Shortcut('enter', 'to send', ['enter'], actions: ['chat:submit']),
  Shortcut(
    'tab',
    'to send the oldest queued now',
    ['tab'],
    actions: ['chat:steer'],
  ),
  Shortcut(
    r'shift or \ + enter',
    'for a newline',
    ['shift+enter', 'alt+enter', 'ctrl+enter', 'ctrl+j'],
    actions: ['chat:newline'],
    before: r'\ + ',
    after: 'chat:submit',
    first: true,
  ),
  Shortcut(
    r'ctrl + g',
    r'to edit in $EDITOR',
    ['ctrl+g'],
    actions: ['chat:externalEditor'],
  ),
  Shortcut(
    'ctrl + v',
    'to paste an image',
    ['ctrl+v'],
    actions: ['chat:imagePaste'],
  ),
  Shortcut('alt + ← →', 'to move by word', [
    'alt+left',
    'alt+right',
    'alt+b',
    'alt+f',
  ]),
  Shortcut('cmd + ← →', 'to line start or end', ['super+left', 'super+right']),
  // The three of OpenTUI's own the original's prompt lets its textarea
  // have, beside the readline keys, which go unlisted.
  Shortcut('cmd + a', 'to select all input', ['super+a']),
  Shortcut('cmd + z', 'to undo, with shift to redo', [
    'super+z',
    'shift+super+z',
  ]),
  // ↓ past the newest prompt, on an empty draft, goes into the list of the
  // window's agents while a child is open, and on to the background's
  // summary line; there ↑ ↓ or j k move, enter and esc go back, which the
  // status line names, and in the background view ↑ ↓ or j k move between
  // its rows.
  Shortcut(
    '↑ ↓',
    'for prompts, agents, background',
    ['up', 'down', 'j', 'k', 'esc'],
    actions: ['history:previous', 'history:next'],
  ),
  // One action on the focused row, whichever kind it is, in the list or in
  // the background view: a rebinding moves both.
  Shortcut(
    'x',
    'to close an agent, stop background',
    ['x'],
    actions: ['agents:close'],
  ),
  // Enter on the summary line opens the background view; on a row its
  // details, and in them the call that started it; not rebindable, as a
  // picker's Enter is not.
  Shortcut('enter', 'for background, details, a call', ['enter']),
  Shortcut(
    'ctrl + r',
    'to search prompts',
    ['ctrl+r'],
    actions: ['history:search'],
  ),
  Shortcut(
    'tab enter',
    'to take a match',
    ['tab', 'enter'],
    actions: ['historySearch:accept'],
  ),
  Shortcut(
    'esc',
    'to cancel a search',
    ['esc', 'ctrl+c'],
    actions: ['historySearch:cancel'],
  ),
  Shortcut(
    'pgup pgdn or wheel',
    'to scroll',
    ['pageup', 'pagedown', 'shift+pageup', 'shift+pagedown'],
    actions: ['scroll:pageUp', 'scroll:pageDown'],
    // The wheel scrolls the transcript, which no key binding moves.
    also: 'wheel',
  ),
  Shortcut(
    'shift + ↑ ↓',
    'to scroll a line',
    ['shift+up', 'shift+down'],
    actions: ['scroll:lineUp', 'scroll:lineDown'],
  ),
  Shortcut(
    'home end',
    'for the top and the bottom',
    ['home', 'end', 'shift+home', 'shift+end'],
    actions: ['scroll:top', 'scroll:bottom'],
  ),
  Shortcut(
    'ctrl + c',
    'to copy',
    ['ctrl+c', 'ctrl+shift+c'],
    actions: ['selection:copy'],
    also: 'ctrl + c',
    first: true,
  ),
  // Typing either opens its list; it is the draft's, so no key of the
  // window's answers it, as the original lists it with none.
  Shortcut('/ @ @@', 'for commands, files or agents', []),
  Shortcut(
    '↑ ↓',
    'to pick a completion',
    ['up', 'down'],
    actions: ['autocomplete:previous', 'autocomplete:next'],
  ),
  Shortcut(
    'tab',
    'to complete a command',
    ['tab'],
    actions: ['autocomplete:accept'],
  ),
  Shortcut(
    'tab enter',
    'to add a file or agent',
    ['tab', 'enter'],
    actions: ['autocomplete:accept'],
  ),
  Shortcut(
    'esc',
    'to close completions',
    ['esc'],
    actions: ['autocomplete:dismiss'],
  ),
  Shortcut('!', 'for bash mode', ['!']),
  Shortcut('backspace', 'to leave bash mode', ['backspace', 'shift+backspace']),
  Shortcut(
    'esc',
    'to interrupt or stop a command',
    ['esc'],
    actions: ['chat:cancel'],
  ),
  Shortcut(
    'shift + tab',
    'to cycle modes',
    ['shift+tab'],
    actions: ['chat:cycleMode'],
  ),
  Shortcut(
    'ctrl + o',
    'for verbose output',
    ['ctrl+o'],
    actions: ['app:toggleTranscript'],
  ),
  Shortcut('ctrl + c', 'to clear input', ['ctrl+c']),
  Shortcut('ctrl + d or ctrl + c', 'twice to quit', ['ctrl+d', 'ctrl+c']),
  Shortcut(
    'ctrl + x a',
    'for what waits on you',
    ['ctrl+x a'],
    actions: ['session:attention'],
  ),
  Shortcut(
    'ctrl + x b',
    'to pick a code block',
    ['ctrl+x b'],
    actions: ['codeBlock:pick'],
  ),
  Shortcut(
    'c r',
    'to copy or put in the prompt',
    ['c', 'r'],
    actions: ['codeBlock:copy', 'codeBlock:prompt'],
  ),
  Shortcut('1–9', 'to pick a choice', [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
  ]),
  Shortcut(
    '↑ ↓ j k ← →',
    'to move or change a value',
    ['up', 'down', 'j', 'k', 'left', 'right'],
    actions: ['modelPicker:decreaseEffort', 'modelPicker:increaseEffort'],
    also: '↑ ↓ j k',
  ),
  Shortcut('enter', 'to pick the highlighted choice', ['enter']),
  Shortcut('esc', 'to reject a permission', ['esc'], actions: ['confirm:no']),
  // ← leaves a background detail as esc does.
  Shortcut(
    'esc ←',
    'to leave a picker or shortcuts',
    ['esc', 'left'],
    actions: ['select:cancel', 'help:dismiss'],
  ),
  Shortcut(
    'ctrl + a',
    'to show all directories',
    ['ctrl+a'],
    actions: ['select:toggleScope'],
  ),
  // Forms and questions: their own boxes bind these keys and name them in
  // their hint lines, as the original lists them apart from the window's.
  Shortcut('tab ← → ↑ ↓ space', 'to answer forms', []),
  Shortcut('ctrl + c', 'to stop the turn and its form', ['ctrl+c']),
  // Vim's keys are vim's; the line names the command that turns them on.
  Shortcut('/vim', 'for vim mode', []),
  Shortcut('?', 'for shortcuts', ['?'], actions: ['help:toggle']),
  Shortcut('any key', 'to quit the crash screen', []),
];

/// The panel's entries for [keymap], as the original's shortcuts(): each as
/// listed while its actions keep their default keys, named by the keys
/// bound to them otherwise, and gone when none is.
List<Shortcut> shortcutsFor([Keybindings? keymap]) {
  final map = keymap ?? defaultKeymap;
  return [for (final shortcut in shortcuts) ...?_shortcut(map, shortcut)];
}

List<Shortcut>? _shortcut(Keybindings keymap, Shortcut shortcut) {
  final actions = shortcut.actions;
  if (actions.isEmpty ||
      [...actions, ?shortcut.after].every((a) => isDefault(keymap, a))) {
    return [shortcut];
  }
  Shortcut named(String key) => Shortcut(
    key,
    shortcut.does,
    shortcut.presses,
    actions: actions,
    before: shortcut.before,
    after: shortcut.after,
    also: shortcut.also,
    first: shortcut.first,
  );
  final names = <String>[];
  for (final action in actions) {
    // Two keys an action at most, so a line still fits a column.
    for (final keys in keysOf(keymap, action).take(shortcut.first ? 1 : 2)) {
      final name = sequencePanel(keys);
      if (!names.contains(name)) names.add(name);
    }
  }
  final key = names.join(' ');
  if (shortcut.also case final also?) {
    return [named(key.isEmpty ? also : '$key or $also')];
  }
  if (shortcut.after case final after?) {
    final then = keysOf(keymap, after).map(sequencePanel).firstOrNull;
    final keys = [
      if (key.isNotEmpty) key,
      if (then != null) '${shortcut.before ?? ''}$then',
    ];
    return keys.isEmpty ? null : [named(keys.join(' or '))];
  }
  if (key.isEmpty) return null;
  if (shortcut.before == null) return [named(key)];
  // One key after the prefix, as `\ + enter ctrl + s` would read as two.
  final first = keysOf(keymap, actions.first).map(sequencePanel).first;
  return [named('${shortcut.before}$first')];
}

/// One shortcut as the panel prints it.
String shortcutLine(Shortcut shortcut) => '${shortcut.key} ${shortcut.does}';

/// The panel's left indent and its gap between columns.
const panelPadding = 2;
const panelGap = 3;

/// Cuts entries into columns read top to bottom, then left to right.
List<List<T>> inColumns<T>(List<T> list, int count) {
  final height = (list.length / math.max(1, count)).ceil();
  if (height == 0) return [];
  return [
    for (var start = 0; start < list.length; start += height)
      list.sublist(start, math.min(start + height, list.length)),
  ];
}

int _width(List<String> lines) =>
    lines.fold(0, (width, line) => math.max(width, cellWidth(line)));

/// Physical panel rows, padded by terminal cells and separated by three spaces.
List<String> panelRows(List<String> lines, int count) {
  final columns = inColumns(lines, count);
  final widths = columns.map(_width).toList();
  return [
    for (var row = 0; row < (columns.firstOrNull?.length ?? 0); row++)
      [
        for (var col = 0; col < columns.length; col++)
          if (row < columns[col].length)
            '${columns[col][row]}${' ' * (widths[col] - cellWidth(columns[col][row]))}',
      ].join(' ' * panelGap).trimRight(),
  ];
}

/// The most complete columns that fit, up to three, or one if none fits.
int columnCount(List<String> lines, int width, [int most = 3]) {
  for (var count = most; count > 1; count--) {
    final columns = inColumns(lines, count);
    final needed =
        panelPadding +
        panelGap * (columns.length - 1) +
        columns.fold(0, (sum, column) => sum + _width(column));
    if (needed <= width) return columns.length;
  }
  return 1;
}
