import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester CTUI-163: row binding ownership', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'row keys survive focus, burst updates and tiny resizes $size',
        (t) async {
          final c = TextAreaController(text: '界👩‍💻éabcdef ' * 30);
          final inside = FocusNode(), outside = FocusNode();
          addTearDown(c.dispose);
          addTearDown(inside.dispose);
          addTearDown(outside.dispose);
          await t.pumpWidget(
            Column(
              children: [
                TextArea(controller: c, focusNode: inside, maxHeight: 5),
                Focus(focusNode: outside, child: Text('outside')),
              ],
            ),
            size: size,
          );
          inside.requestFocus();
          await t.pump();
          final row = c.lastLayout!.rows[1];
          c.cursor = row.start + 1;
          await t.pump();
          await t.press('super+left');
          expect(c.cursor, row.start);
          await t.press('super+right');
          expect(c.cursor, row.end - 1);
          final at = c.cursor;
          outside.requestFocus();
          await t.pump();
          await t.press('super+left');
          expect(c.cursor, at);
          inside.requestFocus();
          await t.pump();
          for (var i = 0; i < 1000; i++) {
            c.text = '界👩‍💻é\x1b[31m update $i ' * 20;
          }
          await t.pump();
          final fresh = c.lastLayout!.rows[1];
          c.cursor = fresh.start + 1;
          await t.pump();
          await t.press('super+left');
          expect(c.cursor, fresh.start);
          for (final tiny in [const Size(1, 1), Size.zero]) {
            await t.resize(tiny);
            c.cursor = 0;
            await t.pump();
            await t.press('super+left');
            expect(c.cursor, 0);
            await t.press('super+right');
            expect(c.cursor, tiny == Size.zero ? c.length : 0);
          }
          await t.resize(size);
          await t.press('ctrl+a');
          expect(c.cursor, 0);
          await t.press('ctrl+e');
          expect(c.cursor, c.length);
        },
      );

      testWidgets(
        'row keys respect delegation and a live timer after removal $size',
        (t) async {
          final c = TextAreaController(text: 'abcdef' * 30)..cursor = 3;
          final delegated = <String>[];
          await t.pumpWidget(
            Actions(
              bindings: [
                Binding(
                  'super+left',
                  'Owner left',
                  () => delegated.add('left'),
                ),
                Binding(
                  'super+right',
                  'Owner right',
                  () => delegated.add('right'),
                ),
              ],
              child: TextArea(
                controller: c,
                autofocus: true,
                unhandledKeys: const {'super+left', 'super+right'},
              ),
            ),
            size: size,
          );
          await t.press('super+left super+right');
          expect(c.cursor, 3);
          expect(delegated, ['left', 'right']);
          final timer = Timer.periodic(
            const Duration(milliseconds: 1),
            (_) => c.text = 'late 界👩‍💻é',
          );
          try {
            await t.pumpWidget(const SizedBox(), size: size);
            await t.pump(const Duration(milliseconds: 5));
          } finally {
            timer.cancel();
            c.dispose();
          }
        },
      );
    }
  });
}
