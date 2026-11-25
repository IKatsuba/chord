import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'wheel_window_test.dart' show seed;
import 'window_fake_test.dart' show launch;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'same-batch command typing and current room converge within two passes $size',
      (t) async {
        final connection = seed();
        addTearDown(connection.close);
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: connection),
          size: size,
        );
        await t.pump();
        var typed = '';
        for (final character in '/sta'.split('')) {
          final before = t.inputLayoutPasses;
          final handled = t.host.handleKey(KeyEvent(character));
          expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
          expect(
            handled,
            isTrue,
            reason: 'current command character $character',
          );
          typed += character;
          expect(connection.app.value.draft, typed);
        }
        await t.pump();
        expect(t.screen, shows('Show the agent, model'));
        await t.resize(const Size(80, 5));
        final narrowPass = t.inputLayoutPasses;
        expect(t.host.handleKey(const KeyEvent('tab')), isTrue);
        expect(t.inputLayoutPasses - narrowPass, lessThanOrEqualTo(2));
        expect(connection.app.value.draft, '/sta');
        await t.pump();
        expect(t.screen, shows('not enough space'));
        await t.resize(size);
        expect(t.screen, shows('Show the agent, model'));
        final restoredPass = t.inputLayoutPasses;
        expect(t.host.handleKey(const KeyEvent('tab')), isTrue);
        expect(t.inputLayoutPasses - restoredPass, lessThanOrEqualTo(2));
        expect(connection.app.value.draft, '/status ');
        await t.pump();
        expect(t.screen, isNot(shows('not enough space')));
      },
    );
  }
}
