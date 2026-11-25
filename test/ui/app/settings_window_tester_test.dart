@Tags(['fake_agent'])
library;

import 'package:chord/session/models.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

void main() {
  group('tester setting window lifecycle', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'highlight survives narrow resize before acceptance at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          final promptFocus = t.focusManager.primaryFocus;
          await t.type('/model');
          await t.press('enter');
          await t.pump();
          await t.press('down');
          expect(c.app.value.transcript.entries, isEmpty);
          for (final next in [const Size(40, 24), const Size(80, 24), size]) {
            await t.resize(next);
            expect(t.screen, shows('Select model'));
            expect(t.screen, shows('Fake Small'));
            expect(c.app.value.transcript.entries, isEmpty);
          }
          await t.press('enter');
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.NotedEntry>()
                .any((e) => e.text == 'Switched to Fake Small'),
          );
          await t.pump();
          expect(
            modelsFrom(
              c.app.value.agent.configOptions,
              c.app.value.agent.models,
            )?.current,
            'fake-small',
          );
          expect(t.focusManager.primaryFocus, same(promptFocus));
          expect(
            c.app.value.transcript.entries.whereType<model.NotedEntry>(),
            hasLength(1),
          );
          expect(
            c.app.value.transcript.entries.whereType<model.UserEntry>(),
            isEmpty,
          );
        },
      );
    }

    testWidgets(
      'same-chunk effort and model movement retain the pending effort',
      (t) async {
        await fixture.connected(t, const Size(120, 40));
        await t.type('/model');
        await t.press('enter');
        await t.pump();
        t.host.handleKey(const KeyEvent('right'));
        t.host.handleKey(const KeyEvent('down'));
        await t.pump();
        expect(t.screen, shows('High effort •'));
        expect(t.screen, shows('asked for'));
      },
    );

    testWidgets('independent fake sessions retain their own open settings', (
      t,
    ) async {
      final other = WidgetTester();
      addTearDown(other.dispose);
      final first = await fixture.connected(t, const Size(120, 40));
      final second = await fixture.connected(other, const Size(80, 24));
      await t.type('/model');
      await t.press('enter');
      await t.pump();
      await other.type('/config');
      await other.press('enter');
      await other.pump();
      expect(other.screen, shows('Settings'));
      await t.press('down enter');
      await fixture.until(
        () => first.app.value.transcript.entries
            .whereType<model.NotedEntry>()
            .any((e) => e.text == 'Switched to Fake Small'),
      );
      await other.pump();
      expect(other.screen, shows('Settings'));
      expect(second.app.value.transcript.entries, isEmpty);
      expect(
        modelsFrom(
          second.app.value.agent.configOptions,
          second.app.value.agent.models,
        )?.current,
        'fake-large',
      );
      await t.press('ctrl+d');
      await other.press('enter');
      expect(other.screen, shows('Set Effort'));
      await other.press('esc esc');
      await other.type('independent draft');
      expect(second.app.value.draft, 'independent draft');
    });
  });
}
