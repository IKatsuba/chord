// While a chord waits for its next key the prompt shows no terminal cursor,
// as the original's box gives up its keys meanwhile; it comes back when the
// chord ends or its wait runs out.
import 'package:chord/cli.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart' show selectionConnection;

Future<void> _window(WidgetTester t, Size size) async {
  final c = selectionConnection(const []);
  addTearDown(c.close);
  await t.pumpWidget(
    TranscriptWindow(
      launch: const Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '.',
      ),
      connection: c,
    ),
    size: size,
  );
  await t.pump();
}

void main() {
  group('tester: CTUI-78 pending prompt cursor lifecycle', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'Esc cancels waiting and resize cannot reveal cursor at $size',
        (t) async {
          await _window(t, size);
          await t.type('界🙂e\u0301');
          final shown = t.screen.buffer.cursor;
          await t.press('ctrl+x');
          expect(t.focusManager.pendingChord, isNotEmpty);
          expect(t.screen.buffer.cursor, isNull);
          await t.resize(const Size(1, 1));
          await t.resize(Size.zero);
          await t.resize(size);
          expect(t.screen.buffer.cursor, isNull);
          await t.press('esc');
          expect(t.focusManager.pendingChord, isEmpty);
          expect(t.screen.buffer.cursor, shown);
          await t.type('z');
          expect(t.screen.buffer.cursor, shown! + const Offset(1, 0));
        },
      );

      testWidgets(
        'timeout after focus leaves restores only focused cursor $size',
        (t) async {
          await _window(t, size);
          await t.type('draft');
          final shown = t.screen.buffer.cursor;
          final node = t.focusManager.primaryFocus!;
          await t.press('ctrl+x');
          node.unfocus();
          await t.pump();
          await t.pump(const Duration(seconds: 4));
          expect(t.screen.buffer.cursor, isNull);
          node.requestFocus();
          await t.pump();
          expect(t.focusManager.pendingChord, isEmpty);
          expect(t.screen.buffer.cursor, shown);
        },
      );

      testWidgets(
        'removing pending prompt releases listener before timer $size',
        (t) async {
          final c = selectionConnection(const []);
          final present = ValueNotifier(true);
          addTearDown(c.close);
          addTearDown(present.dispose);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: present,
              builder: (_) => present.value
                  ? TranscriptWindow(
                      launch: const Launch(
                        name: 'fake',
                        agent: null,
                        agentCommand: 'fake',
                        version: '0.0.1',
                        directory: '.',
                      ),
                      connection: c,
                    )
                  : const SizedBox(),
            ),
            size: size,
          );
          await t.pump();
          await t.type('draft');
          await t.press('ctrl+x');
          expect(t.screen.buffer.cursor, isNull);
          present.value = false;
          await t.pump();
          await t.pump(const Duration(seconds: 4));
          expect(t.screen.buffer.cursor, isNull);
          expect(t.screen.text, isEmpty);
          present.value = true;
          await t.pump();
          await t.type('z');
          expect(t.screen.buffer.cursor, isNotNull);
          expect(t.focusManager.pendingChord, isEmpty);
        },
      );
    }
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the cursor hides while ctrl+x waits and comes back when the '
        'chord ends, at $size', (t) async {
      await _window(t, size);
      await t.type('hi');
      await t.pump();
      final shown = t.screen.buffer.cursor;
      expect(shown, isNotNull);

      await t.press('ctrl+x');
      await t.pump();
      expect(t.screen.buffer.cursor, isNull);
      await t.press('a');
      await t.pump();
      expect(t.screen.text, contains('Nothing waits on you'));
      expect(t.screen.buffer.cursor, shown);

      await t.press('ctrl+x');
      await t.pump();
      expect(t.screen.buffer.cursor, isNull);
      await t.pump(const Duration(seconds: 4));
      expect(t.screen.buffer.cursor, shown);
    });
  }
}
