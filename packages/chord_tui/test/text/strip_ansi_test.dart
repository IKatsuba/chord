// strip-ansi 7.2.0's own cases, under its MIT license retained in width.dart.
import 'dart:convert';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart';
import 'package:test/test.dart';

void main() {
  final cases =
      jsonDecode(File('test/text/fixtures/strip_ansi.json').readAsStringSync())
          as List;
  for (final c in cases) {
    test(c['name'] as String, () {
      expect(stripAnsi(c['input'] as String), c['expected']);
    });
  }
  for (final terminator in ['\x07', '\x1b\\', '\u009c']) {
    test(
      'OSC links stop at their first terminator ${terminator.codeUnits}',
      () {
        final linked =
            '\x1b]8;;https://example.com$terminator'
            'visible\x1b]8;;$terminator';
        expect(stripAnsi(linked), 'visible');
        expect(
          stripAnsi('\x1b]0;broken \x1b[31mvisible\x1b]8;;url$terminator'),
          ';broken visible',
        );
      },
    );
  }
  test('colon SGR and incomplete controls follow original pattern', () {
    expect(stripAnsi('\x1b[38:2::12:34:56mred\x1b[0m'), 'red');
    expect(stripAnsi('before\x1b['), 'before\x1b[');
    expect(stripAnsi('before\x1b`after'), 'before\x1b`after');
  });
  test('C1-only OSC retains original strip-ansi fast-path semantics', () {
    const osc = '\u009d0;title\x07';
    expect(stripAnsi(osc), osc);
    expect(stripAnsi('\u009b0m$osc'), '');
  });
  for (final width in [120, 80, 3]) {
    test('C1 CSI shares width layout and selection offsets $width', () {
      const text = 'e\u009b31m\u0301界\u009b0mZ';
      expect(stripAnsi(text), 'e\u0301界Z');
      expect(cellWidth(text), 4);
      final layout = TextLayout.compute(const TextSpan(text), maxWidth: width);
      expect(
        layout.lines.expand((line) => line).map((g) => g.text).join(),
        'e\u0301界Z',
      );
      expect(layout.lines.expand((line) => line).map((g) => g.sourceOffset), [
        0,
        1,
        2,
      ]);
      final source = SelectionSource.text(
        id: 'text',
        revision: 0,
        text: const TextSpan(text),
      );
      expect(
        shapeSelectionSource(source, width: width).selectedText,
        'e\u0301界Z',
      );
    });
  }
}
