import 'package:chord_site/screens.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

void main() {
  group('CHD-638 tester: live fixture state across stacking', () {
    for (final size in const [Size(205, 56), Size(55, 52)]) {
      testWidgets('draft, permission, checklist and start answer retain their '
          'own state across every layout from $size', (t) async {
        final host = FakeHost('/chord');
        addTearDown(host.popped.close);
        await t.pumpWidget(Site(host: host), size: size);
        await t.press('p');
        await t.type('界🙂e\u0301 draft');
        var suffix = '';
        for (final next in const [
          Size(138, 40),
          Size(139, 40),
          Size(55, 52),
          Size(205, 56),
        ]) {
          await t.resize(next);
          await t.type('x');
          suffix += 'x';
          expect(t.screen, shows('界🙂e\u0301 draft$suffix'));
        }
        await t.press('esc');
        await t.press('a');
        await t.press('2');
        expect(t.screen, shows('Always allowed'));
        await t.press('ctrl+q');
        await t.press('l');
        await t.type('plan draft');
        await t.press('ctrl+t');
        expect(t.screen, isNot(shows('Working…')));
        await t.press('esc');
        await t.press('s');
        await t.press('2');
        expect(t.screen, shows('Picked codex'));
        await t.press('ctrl+q');
        await t.resize(const Size(55, 52));
        await t.press('p');
        expect(t.screen, shows('界🙂e\u0301 draft$suffix'));
        await t.press('esc');
        await t.press('a');
        expect(t.screen, shows('Always allowed'));
        await t.press('ctrl+q');
        await t.press('l');
        expect(t.screen, shows('plan draft'));
        expect(t.screen, isNot(shows('Working…')));
        await t.press('esc');
        await t.press('s');
        expect(t.screen, shows('Picked codex'));
        await t.press('r');
        await t.press('esc');
        expect(t.screen, shows('Canceled'));
        await t.press('ctrl+q');
        expect(host.pushed, isEmpty);
        expect(host.opened, isEmpty);
        expect(t.exitRequested, isFalse);
      });
    }
  });

  group('CHD-638 tester: flow index boundaries', () {
    for (final size in const [Size(80, 24), Size(55, 52)]) {
      testWidgets('1000 Tabs skip an empty index and leave page keys intact '
          'at $size', (t) async {
        final host = FakeHost('/chord');
        addTearDown(host.popped.close);
        await t.pumpWidget(Site(host: host), size: size);
        for (var i = 0; i < 1000; i++) {
          t.host.handleKey(const KeyEvent('tab'));
        }
        await t.pump();
        await t.pump();
        expect(
          t.screen.lines.last,
          contains(size.width < 60 ? 'escape up' : 'p/a/l/s try'),
          reason:
              'primary: ${t.focusManager.primaryFocus}; '
              'effective: ${t.focusManager.effectiveFocus}',
        );
        await t.press('p');
        await t.type('probe');
        expect(t.screen, shows('probe'));
        await t.press('esc');
        await t.press('end');
        expect(t.screen, shows('No screens were recorded.'));
        expect(t.screen, isNot(shows('⏎ PLAY')));
        expect(host.pushed, isEmpty);
        expect(t.exitRequested, isFalse);
      });

      testWidgets('1000 selections reveal the final flow and Enter opens '
          'the visible row at $size', (t) async {
        final host = FakeHost('/chord');
        addTearDown(host.popped.close);
        await t.pumpWidget(
          Site(
            host: host,
            recordings: screenCaptions.keys.toList(),
            lengths: const {'start': Duration.zero},
          ),
          size: size,
        );
        for (var i = 0; i < 5; i++) {
          await t.press('tab');
        }
        for (var i = 0; i < 1000; i++) {
          t.host.handleKey(const KeyEvent('down'));
        }
        await t.pump();
        await t.pump();
        expect(
          t.screen,
          shows('⏎ PLAY'),
          reason:
              'primary: ${t.focusManager.primaryFocus}; '
              'effective: ${t.focusManager.effectiveFocus}',
        );
        expect(
          t.screen.lines.firstWhere((line) => line.contains('⏎ PLAY')),
          contains('10  FORK'),
        );
        await t.press('enter');
        expect(host.pushed, ['/chord/fork']);
        expect(t.exitRequested, isFalse);
      });
    }
  });
}
