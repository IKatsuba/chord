import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: TextArea controller across State swaps', () {
    for (final size in [
      const Size(0, 0),
      const Size(1, 1),
      const Size(80, 24),
      const Size(120, 40),
    ]) {
      testWidgets('edits, undo and live updates survive swaps at $size', (
        t,
      ) async {
        final c = TextAreaController(text: '界👩‍💻e\u0301');
        final position = ValueNotifier(0);
        final changes = <(int, String)>[];
        final events = StreamController<String>.broadcast(sync: true);
        final subscription = events.stream.listen(c.insert);
        try {
          await t.pumpWidget(
            ListenableBuilder(
              listenable: position,
              builder: (context) {
                final at = position.value;
                return Column(
                  children: [
                    for (var i = 0; i < at; i++) Text('before $i'),
                    TextArea(
                      controller: c,
                      autofocus: true,
                      onChanged: (text) => changes.add((at, text)),
                    ),
                    for (var i = at; i < 3; i++) Text('after $i'),
                  ],
                );
              },
            ),
            size: size,
          );
          for (final at in [2, 0, 1, 3, 0]) {
            position.value = at;
            await t.pump();
            final before = c.text;
            changes.clear();
            await t.type('x');
            expect(c.text, '${before}x');
            expect(changes, [(at, '${before}x')]);
            await t.press('ctrl+z');
            expect(c.text, before);
            await t.press('ctrl+y');
            expect(c.text, '${before}x');
          }
          changes.clear();
          for (var i = 0; i < 1000; i++) {
            events.add('x');
          }
          await t.pump();
          expect(changes, hasLength(1000));
          expect(changes.every((change) => change.$1 == 0), isTrue);
          await t.resize(const Size(80, 24));
          await t.press('ctrl+a');
          expect(t.screen.lines.first, startsWith('界👩‍💻e\u0301'));
          await t.type('y');
          expect(c.text, startsWith('y界👩‍💻e\u0301'));
          c.cursor = c.length;
          await t.pumpWidget(Text('removed'));
          final count = changes.length;
          events.add('late');
          await t.pump();
          expect(changes, hasLength(count));
          expect(t.screen.lines.first, 'removed');
          await t.pumpWidget(TextArea(controller: c, autofocus: true));
          await t.press('ctrl+e');
          await t.type('z');
          expect(c.text, endsWith('latez'));
        } finally {
          t.dispose();
          await subscription.cancel();
          await events.close();
          position.dispose();
          c.dispose();
        }
      });
    }
  });
}
