@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

void main() {
  group('reported status and working window', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'reported facts update and ignored cancel stays interrupting at $size',
        (t) async {
          final connection = await fixture.connected(t, size);
          expect(
            t.screen,
            shows('Fake Large with a 1M context window · medium effort'),
          );
          expect(t.screen, isNot(shows('context used')));
          await fixture.sent(t, connection, 'text');
          expect(t.screen.lines.last, contains('? for shortcuts'));
          // The hint shortens facts as in u11-original-text-80x24.txt.
          expect(
            t.screen.lines.last,
            endsWith(
              size.width == 80
                  ? 'Fake Large with a 1M context window · medium · 1% used'
                  : 'Fake Large with a 1M context window · medium effort · 1% context used',
            ),
          );
          await t.type('ignorescancel');
          await t.press('enter');
          await fixture.until(
            () =>
                connection.app.value.transcript.entries
                    .whereType<model.AssistantEntry>()
                    .length ==
                2,
          );
          await t.pump();
          expect(t.screen, shows('››› Working… ('));
          expect(t.screen, shows('esc to interrupt'));
          await t.press('esc');
          expect(t.screen, shows('››› Interrupting… ('));
          expect(t.screen, isNot(shows('esc to interrupt')));
          expect(connection.app.value.transcript.turn, isA<model.Cancelling>());
        },
      );
      testWidgets('permission wait changes the working label at $size', (
        t,
      ) async {
        final connection = await fixture.connected(t, size);
        await t.type('permission');
        await t.press('enter');
        await fixture.until(
          () =>
              connection.app.value.transcript.turn is model.AwaitingPermission,
        );
        await t.pump();
        expect(t.screen, shows('››› Waiting for permission… ('));
        expect(t.screen, isNot(shows('esc to interrupt')));
        final turn =
            connection.app.value.transcript.turn as model.AwaitingPermission;
        connection.conversation.reject(turn.permissions.first.id);
        await fixture.until(
          () => connection.app.value.transcript.turn is model.Idle,
        );
        await t.pump();
        expect(t.screen, isNot(shows('Waiting for permission…')));
      });
    }
  });
  group('tester U11 live window ordering', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'working plan queue prompt and status remain ordered at $size',
        (t) async {
          final connection = await fixture.connected(
            t,
            size,
            flags: ['--step-ms', '100'],
          );
          await t.type('plan');
          await t.press('enter');
          await fixture.until(
            () => connection.app.value.transcript.plan.isNotEmpty,
          );
          await t.type('queued message');
          await t.press('enter');
          await t.type('current draft');
          final lines = t.screen.lines;
          final working = lines.indexWhere((line) => line.contains('Working…'));
          final plan = lines.indexWhere(
            (line) => line.contains('☒ Read the code'),
          );
          final queue = lines.indexWhere(
            (line) => line.contains(' › queued message'),
          );
          final prompt = lines.indexWhere((line) => line.startsWith('╭'));
          expect(working, greaterThanOrEqualTo(0));
          expect(plan, greaterThan(working));
          expect(queue, greaterThan(plan));
          expect(prompt, greaterThan(queue));
          expect(lines.last, contains('Fake Large'));
          await t.press('esc');
          await fixture.until(
            () => connection.app.value.transcript.turn is model.Idle,
          );
          await t.pump();
          expect(t.screen, isNot(shows('Working…')));
          expect(t.screen, shows('Plan · 1 of 3 done'));
          expect(t.screen, shows('│ › queued message'));
          expect(t.screen, shows('│   current draft'));
        },
      );
    }
    testWidgets(
      'agent crash removes working while preserving reported status',
      (t) async {
        final connection = await fixture.connected(t, const Size(80, 24));
        await fixture.sent(t, connection, 'crash');
        expect(t.screen, shows('The agent exited'));
        expect(t.screen, isNot(shows('Working…')));
        expect(t.screen, shows('Fake Large'));
      },
    );
  });
}
