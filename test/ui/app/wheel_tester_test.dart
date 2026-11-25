@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'wheel_window_test.dart' show wheel;
import 'window_fake_test.dart' as fixture;

void main() {
  group(
    'tester: wheel across cancelled and misbehaving fake sessions',
    skip: fakeAgentSkip,
    () {
      for (final size in [const Size(120, 40), const Size(80, 24)]) {
        testWidgets(
          'cancelled turn and late second session keep wheel/drafts isolated at $size',
          (t) async {
            final other = WidgetTester();
            addTearDown(other.dispose);
            final first = await fixture.connected(
              t,
              size,
              flags: ['--step-ms', '1'],
            );
            final second = await fixture.connected(
              other,
              size,
              flags: ['--step-ms', '1'],
            );
            await fixture.sent(t, first, 'long');
            await t.type('slow');
            await t.press('enter');
            await fixture.until(
              () => first.app.value.transcript.entries
                  .whereType<model.AssistantEntry>()
                  .any((e) => e.text.text.startsWith('Working')),
            );
            await t.press('esc');
            await fixture.until(
              () => first.app.value.transcript.entries
                  .whereType<model.CancelledEntry>()
                  .isNotEmpty,
            );
            await t.type('draft 界👩‍💻e\u0301');
            await fixture.sent(other, second, 'late');
            await fixture.until(
              () => second.app.value.transcript.entries
                  .whereType<model.AssistantEntry>()
                  .any((e) => e.text.text.contains('Late, after the answer.')),
            );
            await other.type('other draft');
            await other.pump();
            final otherScreen = other.screen.buffer.lines;
            final otherState = second.app.value;
            final before = first.app.value.scroll.offset;
            final cursor = first.app.value.cursor;
            final focus = t.focusManager.primaryFocus;
            await t.mouse(wheel(0, 0));
            expect(first.app.value.scroll.offset, before - 1);
            expect(first.app.value.draft, 'draft 界👩‍💻e\u0301');
            expect(first.app.value.cursor, cursor);
            expect(t.focusManager.primaryFocus, same(focus));
            expect(second.app.value, same(otherState));
            await other.pump();
            expect(other.screen.buffer.lines, otherScreen);
            await first.close();
            final closed = first.app.value;
            t.host.handleMouse(wheel(0, 0));
            expect(first.app.value, same(closed));
          },
        );
        for (final scenario in ['ignorescancel', 'crash']) {
          testWidgets(
            '$scenario leaves transcript wheelable without draft edits at $size',
            (t) async {
              final c = await fixture.connected(
                t,
                size,
                flags: ['--step-ms', '1'],
              );
              await fixture.sent(t, c, 'long');
              if (scenario == 'crash') {
                await fixture.sent(t, c, scenario);
                expect(
                  c.app.value.transcript.entries.whereType<model.ErrorEntry>(),
                  isNotEmpty,
                );
              } else {
                await t.type(scenario);
                await t.press('enter');
                await fixture.until(
                  () => c.app.value.transcript.entries
                      .whereType<model.AssistantEntry>()
                      .any((e) => e.text.text.contains('Holding on.')),
                );
                await t.press('esc');
              }
              await t.type('unsent 界e\u0301');
              final before = c.app.value.scroll.offset;
              final cursor = c.app.value.cursor;
              await t.mouse(wheel(0, 0));
              expect(c.app.value.scroll.offset, before - 1);
              expect(c.app.value.draft, 'unsent 界e\u0301');
              expect(c.app.value.cursor, cursor);
              await c.close();
            },
          );
        }
      }
    },
  );
}
