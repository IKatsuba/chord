// The panel, the leader line and the hints name the keys the keybindings
// file binds, from the original's tests/ui/shortcuts/bindings_test.ts.
import 'dart:convert';

import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/header/compact.dart' show helpRow;
import 'package:chord/ui/shortcuts/bindings.dart';
import 'package:chord/ui/shortcuts/keys.dart';
import 'package:chord/ui/status/status.dart';
import 'package:chord/ui/transcript/tools/tools.dart' show foldedLine;
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

Keybindings read(List<Object?> blocks) =>
    readKeybindings(jsonEncode({'bindings': blocks})).keymap;

Keybindings chat(Map<String, Object?> bindings) => read([
  {'context': 'Chat', 'bindings': bindings},
]);

List<String> lines([Keybindings? keymap]) =>
    shortcutsFor(keymap).map(shortcutLine).toList();

void main() {
  test('with no file the panel is the table it was, line for line', () {
    expect(lines(), shortcuts.map(shortcutLine).toList());
    expect(lines(defaultKeymap), shortcuts.map(shortcutLine).toList());
  });

  test('the panel names rebound keys, and drops a line with none', () {
    final shown = lines(
      chat({'ctrl+v': null, 'ctrl+t': 'help:toggle', '?': null}),
    );
    expect(shown, contains('ctrl + t for shortcuts'));
    expect(shown.any((line) => line.contains('to paste an image')), isFalse);
    expect(shown, contains('enter to send'));
    expect(lines(chat({'!': 'help:toggle'})), contains('? ! for shortcuts'));
  });

  test('the scroll line names the wheel after the page keys, and alone with '
      'none', () {
    List<String> scroll(Map<String, Object?> bindings) => lines(
      read([
        {'context': 'Scroll', 'bindings': bindings},
      ]),
    );
    expect(lines(), contains('pgup pgdn or wheel to scroll'));
    expect(
      scroll({'pageup': null, 'shift+pageup': null, 'ctrl+b': 'scroll:pageUp'}),
      contains('ctrl + b pgdn shift + pgdn or wheel to scroll'),
    );
    expect(
      scroll({
        'pageup': null,
        'shift+pageup': null,
        'pagedown': null,
        'shift+pagedown': null,
      }),
      contains('wheel to scroll'),
    );
  });

  test('the newline line names the newline keys, then the backslash before '
      'the key that sends', () {
    expect(lines(), contains(r'shift or \ + enter for a newline'));
    expect(
      lines(chat({'enter': null, 'ctrl+s': 'chat:submit'})),
      contains(r'shift + enter or \ + ctrl + s for a newline'),
    );
    // Two keys send; the line names the first, not both after one backslash.
    expect(
      lines(chat({'ctrl+s': 'chat:submit'})),
      contains(r'shift + enter or \ + enter for a newline'),
    );
    // Nothing sends, so the backslash reads as no newline.
    final unsent = lines(chat({'enter': null}));
    expect(unsent, contains('shift + enter for a newline'));
    expect(unsent.any((line) => line.contains(r'\ +')), isFalse);
  });

  group('the merged newline entry follows the actions there are', () {
    const noNewlines = {
      'shift+enter': null,
      'alt+enter': null,
      'ctrl+j': null,
      'ctrl+enter': null,
    };
    List<String> newline(Map<String, Object?> bindings) => [
      for (final line in lines(chat(bindings)))
        if (line.endsWith('for a newline')) line,
    ];

    test('rebinding both names each once, newline then submit', () {
      expect(
        newline({
          ...noNewlines,
          'enter': 'chat:newline',
          'ctrl+s': 'chat:submit',
        }),
        [r'enter or \ + ctrl + s for a newline'],
      );
    });

    test('with no direct newline the backslash route stands alone', () {
      expect(newline(noNewlines), [r'\ + enter for a newline']);
    });

    test('with both routes unbound no newline entry remains', () {
      expect(newline({...noNewlines, 'enter': null}), isEmpty);
    });
  });

  test('session:attention bound elsewhere is named as bound, and unbound '
      'has no line', () {
    final moved = lines(
      read([
        {
          'context': 'Global',
          'bindings': {'ctrl+n': 'session:attention'},
        },
      ]),
    );
    expect(moved.any((line) => line.contains('ctrl + n')), isTrue);
    expect(moved.any((line) => line.endsWith('for what waits on you')), isTrue);
    final off = lines(
      read([
        {
          'context': 'Global',
          'bindings': {'ctrl+x a': null},
        },
      ]),
    );
    expect(off.any((line) => line.contains('waits on you')), isFalse);
  });

  test('hints name the bound key, and say none when nothing is bound', () {
    const turn = Working('t1', 0);
    expect(
      workingLine(turn, 1000, cancelKey: 'ctrl+q')?.detail,
      '1s · ctrl+q to interrupt',
    );
    expect(workingLine(turn, 1000, cancelKey: null)?.detail, '1s');
    expect(foldedLine(3, 'ctrl+t'), '… +3 lines (ctrl+t to expand)');
    expect(foldedLine(1, null), '… +1 line');
    expect(helpRow('?'), '? for shortcuts · /help');
    expect(helpRow(null), '/help');
  });

  test('the leader line follows the file', () {
    Binding bound(String keys, String id) => Binding(keys, id, () {}, id: id);
    final held = [KeyCombo.parse('ctrl+x')];
    final view = leaderLine(held, [
      bound('ctrl+x t', 'codeBlock:pick'),
      bound('ctrl+x e', 'chat:imagePaste'),
    ], 116);
    expect(view.items.map((item) => '${item.keys} ${item.words}'), [
      't a code block',
      'e paste an image',
      'esc never mind',
    ]);
  });
}
