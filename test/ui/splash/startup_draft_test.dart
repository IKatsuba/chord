import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../app/window_fake_test.dart' show until;
import 'splash_widget_test.dart' show splashWindow;

void main() {
  group('tester: startup draft ownership', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'hidden Unicode paste survives resize and failed open $size',
        (t) async {
          final opening = Completer<Agent>();
          final c = await splashWindow(t, size, () => opening.future);
          const draft = '界👩‍💻é retained';
          await t.paste(draft);
          expect(t.screen.text, isNot(contains(draft)));
          expect(c.app.value.draft, draft);
          await t.resize(const Size(16, 9));
          await t.resize(size);
          await t.press('enter');
          expect(c.app.value.draft, draft);
          expect(c.app.value.transcript.entries, isEmpty);
          opening.completeError(StateError('late startup failure'));
          await until(() => c.app.value.start.phase == StartPhase.failed);
          await t.pump();
          expect(t.screen.text, contains(draft));
          expect(t.screen.text, contains('late startup failure'));
          expect(c.app.value.draft, draft);
        },
      );

      testWidgets(
        'startup search returns focus and preserves the draft $size',
        (t) async {
          final c = await splashWindow(t, size);
          await t.type('retained');
          await t.press('esc');
          await t.press('ctrl+r');
          await t.press('esc');
          await t.type('!');
          expect(c.app.value.draft, 'retained!');
          expect(t.screen.text, contains('› retained!'));
          expect(t.screen.text, contains('Starting fake…'));
        },
      );

      testWidgets(
        'a burst stays in one draft and removal drops late failure $size',
        (t) async {
          final opening = Completer<Agent>();
          final c = await splashWindow(t, size, () => opening.future);
          for (var i = 0; i < 1000; i++) {
            t.host.handleKey(const KeyEvent('x'));
          }
          await t.pump();
          expect(c.app.value.draft, 'x' * 1000);
          expect(c.app.value.transcript.entries, isEmpty);
          await t.pumpWidget(Text('removed'), size: size);
          opening.completeError(StateError('late removed startup'));
          await until(() => c.app.value.start.phase == StartPhase.failed);
          await t.pump();
          expect(t.screen.text, startsWith('removed'));
          expect(c.app.value.draft, 'x' * 1000);
        },
      );
    }
  });
}
