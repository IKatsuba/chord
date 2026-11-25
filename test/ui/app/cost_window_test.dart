// /cost and /context in the real window on the original's fake agent.
@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

Future<void> _command(WidgetTester t, String command) async {
  await t.type(command);
  await t.pump();
  await t.press('enter');
  await t.pump();
}

void main() {
  group('tester: CTUI-29 report command dispatch and reset', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'completion dispatches local reports and clear discards their prior spend at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await fixture.sent(t, c, 'hello');
          await t.type('/cos');
          await t.press('tab');
          expect(c.app.value.draft, '/cost ');
          await t.press('enter');
          await t.pump();
          expect(t.screen, shows('Total cost:'));
          final users = c.app.value.transcript.entries
              .whereType<model.UserEntry>()
              .length;
          await _command(t, '/context');
          expect(
            c.app.value.transcript.entries.whereType<model.UserEntry>(),
            hasLength(users),
          );
          await _command(t, '/clear');
          await fixture.until(
            () =>
                c.app.value.start.phase == StartPhase.connected &&
                c.app.value.spent == null &&
                c.app.value.transcript.entries.isEmpty,
          );
          await _command(t, '/cost');
          expect(t.screen, shows('fake has not reported what this session'));
          expect(
            c.app.value.transcript.entries.whereType<model.ReportEntry>().map(
              (entry) => entry.command,
            ),
            ['cost'],
          );
          expect(
            c.app.value.transcript.entries.whereType<model.UserEntry>(),
            isEmpty,
          );
        },
        skip: fakeAgentSkip,
      );
    }
  });
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('/cost and /context report the session at $size', (t) async {
      final c = await fixture.connected(t, size);
      await _command(t, '/cost');
      expect(t.screen, shows('fake has not reported what this session'));
      await fixture.sent(t, c, 'hello');
      await _command(t, '/cost');
      expect(t.screen, shows('Total cost:'));
      expect(t.screen, shows('Tokens in:'));
      expect(t.screen, shows('Session time:'));
      await _command(t, '/context');
      expect(t.screen, shows('Used:'));
      expect(t.screen, shows('Free:'));
      final reports = c.app.value.transcript.entries
          .whereType<model.ReportEntry>()
          .map((e) => e.command);
      expect(reports, ['cost', 'cost', 'context']);
      expect(
        c.app.value.transcript.entries.whereType<model.UserEntry>(),
        hasLength(1),
      );
    }, skip: fakeAgentSkip);
  }
}
