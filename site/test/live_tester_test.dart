import 'package:chord_site/live/permission.dart';
import 'package:chord_site/live/plan.dart';
import 'package:chord_site/live/prompt.dart';
import 'package:chord_site/live/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Widget _room(Widget child) => Focus(autofocus: true, child: child);

void main() {
  group('CHD-638 tester: live fixture lifecycle', () {
    for (final key in ['1', 'esc', 'ctrl+c']) {
      testWidgets('start $key never asks its containing app to exit', (
        t,
      ) async {
        await t.pumpWidget(_room(const LiveStart()), size: const Size(80, 24));
        await t.press(key);
        expect(
          t.exitRequested,
          isFalse,
          reason: 'the live fixture must not terminate the site',
        );
      });
    }

    for (final size in [
      const Size(120, 40),
      const Size(80, 24),
      const Size(54, 56),
    ]) {
      testWidgets(
        'prompt draft survives resize and only latest submission stays at $size',
        (t) async {
          await t.pumpWidget(_room(const LivePrompt()), size: size);
          await t.paste('界👩‍💻e\u0301\nsecond line');
          await t.resize(const Size(50, 12));
          expect(t.screen, shows('界👩‍💻e\u0301'));
          await t.press('enter');
          expect(t.screen.lines.first, '界👩‍💻e\u0301');
          await t.type('next');
          await t.press('enter');
          expect(t.screen.lines.first, 'next');
          expect(t.screen, isNot(shows('second line')));
          expect(t.exitRequested, isFalse);
        },
      );
    }

    testWidgets('permission answers reset selection across repeated asks', (
      t,
    ) async {
      await t.pumpWidget(
        _room(const LivePermission()),
        size: const Size(54, 20),
      );
      await t.press('2');
      expect(t.screen, shows('Always allowed'));
      await t.press('r');
      await t.pump();
      await t.press('enter');
      expect(t.screen.lines.first, startsWith('Allowed once'));
      await t.press('r');
      await t.pump();
      await t.press('esc');
      expect(t.screen.lines.first, startsWith('Rejected'));
      expect(t.exitRequested, isFalse);
    });

    testWidgets(
      'plan toggle keeps the draft and removal stops live widget work',
      (t) async {
        await t.pumpWidget(_room(const LivePlan()), size: const Size(80, 24));
        await t.type('draft');
        for (var i = 0; i < 1000; i++) {
          t.host.handleKey(KeyCombo.parse('ctrl+t').toEvent());
        }
        await t.pump();
        expect(t.screen, shows('draft'));
        expect(t.screen, shows('Working…'));
        await t.pumpWidget(Text('removed'));
        await t.pump(const Duration(milliseconds: 300));
        expect(t.screen.text, 'removed');
        expect(t.exitRequested, isFalse);
      },
    );
  });
}
