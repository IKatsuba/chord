@Tags(['fake_agent'])
library;

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;
import 'permission_fake_test.dart' show ask;
import 'wheel_window_test.dart' show wheel;

void main() {
  group('wheel through the original fake', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'completed long moves one physical row and preserves Unicode draft at $size',
        (t) async {
          final c = await fixture.connected(t, size, flags: ['--step-ms', '1']);
          await fixture.sent(t, c, 'long');
          await t.type('unsubmitted 界🙂e\u0301');
          await t.press('left');
          final draft = c.app.value.draft;
          final cursor = c.app.value.cursor;
          final focus = t.focusManager.primaryFocus;
          final bottom = c.app.value.scroll.offset;
          expect(bottom, greaterThan(20));
          for (final at in [
            Offset.zero,
            const Offset(2, 5),
            Offset(2, size.height - 2),
            Offset(size.width - 1, size.height - 1),
          ]) {
            await t.mouse(wheel(at.x, at.y));
            expect(c.app.value.scroll.offset, bottom - 1);
            expect(c.app.value.scroll.following, isFalse);
            await t.mouse(wheel(at.x, at.y, 1));
            expect(c.app.value.scroll.offset, bottom);
            expect(c.app.value.scroll.following, isTrue);
          }
          expect(c.app.value.draft, draft);
          expect(c.app.value.cursor, cursor);
          expect(t.focusManager.primaryFocus, same(focus));
          await t.press('up down');
          expect(c.app.value.scroll.offset, bottom);
        },
      );
      for (final scenario in ['permission', 'bigask']) {
        testWidgets('$scenario body fits or consumes one step at $size', (
          t,
        ) async {
          final c = await fixture.connected(t, size, flags: ['--step-ms', '1']);
          await fixture.sent(t, c, 'long');
          await ask(t, c, scenario);
          final fitting = scenario == 'permission';
          expect(c.app.value.requestOverflows, !fitting);
          await t.press('down');
          expect(t.screen.text, contains('❯ 2.'));
          final focus = t.focusManager.primaryFocus;
          final before = c.app.value.scroll.offset;
          final body = fitting
              ? t.screen.lines.lastIndexWhere((line) => line.contains('notes'))
              : t.screen.lines.indexWhere(
                  (line) => line.contains('path: docs/release.md'),
                );
          expect(body, greaterThanOrEqualTo(0));
          await t.mouse(wheel(size.width - 5, body, fitting ? -1 : 1));
          expect(c.app.value.scroll.offset, fitting ? before - 1 : before);
          if (!fitting) expect(t.screen, shows('1 line above'));
          expect(t.focusManager.primaryFocus, same(focus));
          expect(t.screen.text, contains('❯ 2.'));
          await t.press('esc');
        });
      }
    }
  });
}
