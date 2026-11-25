import 'package:chord/ui/shortcuts/keys.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  test('catalog is the original\'s editorial order and wording', () {
    expect(shortcuts.map(shortcutLine), [
      'enter to send',
      'tab to send the oldest queued now',
      r'shift or \ + enter for a newline',
      r'ctrl + g to edit in $EDITOR',
      'ctrl + v to paste an image',
      'alt + ← → to move by word',
      'cmd + ← → to line start or end',
      'cmd + a to select all input',
      'cmd + z to undo, with shift to redo',
      '↑ ↓ for prompts, agents, background',
      'x to close an agent, stop background',
      'enter for background, details, a call',
      'ctrl + r to search prompts',
      'tab enter to take a match',
      'esc to cancel a search',
      'pgup pgdn or wheel to scroll',
      'shift + ↑ ↓ to scroll a line',
      'home end for the top and the bottom',
      'ctrl + c to copy',
      '/ @ @@ for commands, files or agents',
      '↑ ↓ to pick a completion',
      'tab to complete a command',
      'tab enter to add a file or agent',
      'esc to close completions',
      '! for bash mode',
      'backspace to leave bash mode',
      'esc to interrupt or stop a command',
      'shift + tab to cycle modes',
      'ctrl + o for verbose output',
      'ctrl + c to clear input',
      'ctrl + d or ctrl + c twice to quit',
      'ctrl + x a for what waits on you',
      'ctrl + x b to pick a code block',
      'c r to copy or put in the prompt',
      '1–9 to pick a choice',
      '↑ ↓ j k ← → to move or change a value',
      'enter to pick the highlighted choice',
      'esc to reject a permission',
      'esc ← to leave a picker or shortcuts',
      'ctrl + a to show all directories',
      'tab ← → ↑ ↓ space to answer forms',
      'ctrl + c to stop the turn and its form',
      '/vim for vim mode',
      '? for shortcuts',
      'any key to quit the crash screen',
    ]);
    for (final shortcut in shortcuts) {
      for (final press in shortcut.presses) {
        expect(Chord.parse(press).length, greaterThan(0));
      }
    }
    // The rows no key of the window's answers: typed, the boxes' own,
    // vim's, and the crash screen's. The form and question boxes bind
    // their keys themselves and vim decides its own, so those keys are
    // tested where they are bound, not by the panel's app-binding check.
    expect(
      shortcuts.where((shortcut) => shortcut.presses.isEmpty).map((s) => s.key),
      ['/ @ @@', 'tab ← → ↑ ↓ space', '/vim', 'any key'],
    );
  });
  test('columns are read down before across and tolerate zero count', () {
    expect(inColumns([1, 2, 3, 4, 5], 2), [
      [1, 2, 3],
      [4, 5],
    ]);
    expect(inColumns([1, 2], 8), [
      [1],
      [2],
    ]);
    expect(inColumns([1, 2], 0), [
      [1, 2],
    ]);
    expect(inColumns<int>([], 3), isEmpty);
  });
  test('panel rows pad terminal cells, not UTF-16 units', () {
    expect(panelRows(['界', 'e\u0301', 'last'], 2), ['界   last', 'e\u0301']);
    expect(panelRows(['one', 'two', 'three'], 1), ['one', 'two', 'three']);
    expect(panelRows([], 3), isEmpty);
  });
  test('column thresholds include only left padding and actual gaps', () {
    const lines = ['aaaa', 'bb', 'ccc', 'd', 'ee', 'f'];
    expect(columnCount(lines, 17), 3);
    expect(columnCount(lines, 16), 2);
    expect(columnCount(lines, 10), 1);
    expect(columnCount(lines, 0), 1);
    expect(columnCount(['界', '界'], 9), 2);
    expect(columnCount(['界', '界'], 8), 1);
    expect(columnCount([], 80), 0);
  });
  for (final width in [80, 120]) {
    test('the complete M1 catalog fits columns at $width', () {
      final lines = shortcuts.map(shortcutLine).toList();
      final count = columnCount(lines, width);
      expect(count, inInclusiveRange(1, 3));
      for (final row in panelRows(lines, count)) {
        expect(cellWidth(row) + panelPadding, lessThanOrEqualTo(width));
      }
      if (count < 3) {
        expect(
          panelRows(
            lines,
            count + 1,
          ).any((row) => cellWidth(row) + panelPadding > width),
          isTrue,
        );
      }
    });
  }

  group('tester: pure shortcut geometry edges', () {
    test('Unicode and ANSI cells determine the exact two-column threshold', () {
      const lines = ['界🙂', 'e\u0301', '\x1b[31mR\x1b[0m', 'tail'];
      expect(columnCount(lines, 13, 2), 2);
      expect(columnCount(lines, 12, 2), 1);
      expect(panelRows(lines, 2), [
        '界🙂   \x1b[31mR\x1b[0m',
        'e\u0301      tail',
      ]);
      expect(panelRows(lines, 2).map(cellWidth), [8, 11]);
    });

    test(
      'every column count retains source order without exposing source lists',
      () {
        final source = List.generate(19, (index) => 'entry $index');
        final before = List.of(source);
        for (var count = -1; count <= 25; count++) {
          final columns = inColumns(source, count);
          expect(columns.expand((column) => column), before);
          columns.first.clear();
          expect(source, before);
        }
      },
    );

    test('empty and one-cell rooms choose a safe single-column fallback', () {
      expect(panelRows(const [], 0), isEmpty);
      expect(inColumns(const ['界🙂e\u0301'], 0), [
        ['界🙂e\u0301'],
      ]);
      for (final width in [-1, 0, 1]) {
        expect(columnCount(const ['界🙂e\u0301'], width), 1);
        expect(panelRows(const ['界🙂e\u0301'], 1), ['界🙂e\u0301']);
      }
    });
  });
}
