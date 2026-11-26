import 'package:chord_site/pages/install.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

void main() {
  group('CHD-638 tester: install feedback lifetime', () {
    testWidgets('a second copy restarts its feedback interval', (t) async {
      final host = FakeHost('/install');
      addTearDown(host.popped.close);
      await t.pumpWidget(Site(host: host), size: const Size(120, 40));
      await t.press('c');
      await t.pump(const Duration(milliseconds: 1200));
      await t.press('c');
      await t.pump(const Duration(milliseconds: 1100));
      expect(t.screen, shows('copied'));
      expect(t.terminal.copied, [
        installWays.first.command,
        installWays.first.command,
      ]);
      await t.pump(const Duration(milliseconds: 1000));
      expect(t.screen, shows('copy c'));
      expect(t.screen, isNot(shows('copied')));
    });

    testWidgets('leaving with feedback live cancels the timer and history', (
      t,
    ) async {
      final host = FakeHost('/install');
      addTearDown(host.popped.close);
      await t.pumpWidget(Site(host: host), size: const Size(80, 24));
      await t.press('c');
      expect(t.screen, shows('copied'));
      await t.pumpWidget(Text('removed'));
      expect(host.popped.hasListener, isFalse);
      await t.pump(const Duration(milliseconds: 2100));
      expect(t.screen.text, 'removed');
      expect(t.terminal.copied, [installWays.first.command]);
    });

    for (final size in [
      const Size(171, 50),
      const Size(120, 40),
      const Size(80, 24),
      const Size(54, 56),
    ]) {
      testWidgets('a burst leaves one visible copy target at $size', (t) async {
        final host = FakeHost('/install');
        addTearDown(host.popped.close);
        await t.pumpWidget(Site(host: host), size: size);
        for (var i = 0; i < 500; i++) {
          t.host.handleKey(const KeyEvent('right'));
          t.host.handleKey(const KeyEvent('down'));
        }
        await t.pump();
        expect(
          t.screen.lines.where((line) => line.contains('copy c')).single,
          contains('shell'),
        );
        await t.press('c');
        expect(t.terminal.copied, [thenCommand]);
        expect(t.screen, shows('copied'));
      });
    }
  });
}
