@Tags(['fake_agent'])
library;

import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

bool _said(StartConnection connection, String text) => connection
    .app
    .value
    .transcript
    .entries
    .whereType<model.AssistantEntry>()
    .any((entry) => entry.text.text.contains(text));

Future<void> _send(
  WidgetTester t,
  StartConnection connection,
  String text,
  int users,
) async {
  await t.type(text);
  await t.press('enter');
  await fixture.until(
    () =>
        connection.app.value.transcript.entries
                .whereType<model.UserEntry>()
                .length ==
            users &&
        connection.app.value.transcript.turn is model.Idle,
  );
  await t.pump();
}

void main() {
  group('tester U7 fake window lifecycle', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'blank Enter and idle Esc preserve an unused window at $size',
        (t) async {
          final connection = await fixture.connected(t, size);
          await t.type('   ');
          await t.press('enter');
          await t.press('esc');
          expect(connection.app.value.transcript.entries, isEmpty);
          expect(connection.app.value.transcript.turn, isA<model.Idle>());
          expect(t.screen, isNot(shows('Interrupted')));
          await t.press('ctrl+d');
          expect(t.exitRequested, isFalse);
          await t.press('ctrl+c');
          expect(t.exitRequested, isFalse);
          await t.press('ctrl+d');
          expect(t.exitRequested, isTrue);
        },
      );

      testWidgets(
        'late chunks stay with the old reply before the next send at $size',
        (t) async {
          final connection = await fixture.connected(
            t,
            size,
            flags: ['--step-ms', '20'],
          );
          await _send(t, connection, 'late', 1);
          await fixture.until(
            () => _said(connection, 'Late, after the answer.'),
          );
          await t.pump();
          expect(t.screen, shows('Answered. Late, after the answer.'));
          await _send(t, connection, 'text', 2);
          final replies = connection.app.value.transcript.entries
              .whereType<model.AssistantEntry>()
              .toList();
          expect(replies.first.text.text, 'Answered. Late, after the answer.');
          expect(replies.last.text.text, contains('Hello, world.'));
          expect(replies.last.turnId, isNot(replies.first.turnId));
          expect(t.screen, shows('Hello, world.'));
        },
      );

      testWidgets('cancelled partial reply survives the next Enter at $size', (
        t,
      ) async {
        final connection = await fixture.connected(t, size);
        await t.type('slow');
        await t.press('enter');
        await fixture.until(
          () => connection.app.value.transcript.entries
              .whereType<model.AssistantEntry>()
              .isNotEmpty,
        );
        await t.press('esc');
        await fixture.until(
          () => connection.app.value.transcript.entries
              .whereType<model.CancelledEntry>()
              .isNotEmpty,
        );
        final partial = connection.app.value.transcript.entries
            .whereType<model.AssistantEntry>()
            .first
            .text
            .text;
        await _send(t, connection, 'text', 2);
        expect(
          connection.app.value.transcript.entries
              .whereType<model.CancelledEntry>(),
          hasLength(1),
        );
        expect(
          connection.app.value.transcript.entries
              .whereType<model.AssistantEntry>()
              .first
              .text
              .text,
          partial,
        );
        expect(t.screen, shows('Hello, world.'));
      });
    }

    testWidgets('swapping two live connections isolates old stream updates', (
      t,
    ) async {
      final first = await fixture.connected(t, const Size(120, 40));
      final second = await fixture.connected(t, const Size(120, 40));
      final selected = ValueNotifier(first);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: selected,
          builder: (_) =>
              StartWindow(launch: fixture.launch, connection: selected.value),
        ),
        size: const Size(120, 40),
      );
      await t.type('slow');
      await t.press('enter');
      await fixture.until(
        () => first.app.value.transcript.entries
            .whereType<model.AssistantEntry>()
            .isNotEmpty,
      );
      selected.value = second;
      await t.pump();
      expect(t.screen, isNot(shows('› slow')));
      await _send(t, second, 'text', 1);
      expect(
        second.app.value.transcript.entries
            .whereType<model.UserEntry>()
            .single
            .text,
        'text',
      );
      expect(
        first.app.value.transcript.entries
            .whereType<model.UserEntry>()
            .single
            .text,
        'slow',
      );
      first.conversation.interrupt();
      await fixture.until(() => first.app.value.transcript.turn is model.Idle);
      await t.pump();
      expect(t.screen, shows('Hello, world.'));
      expect(t.screen, isNot(shows('Interrupted by user')));
      expect(t.screen, isNot(shows('new output')));
      await t.pumpWidget(Text('removed'));
      selected.dispose();
    });

    testWidgets('removing a window closes an agent that ignores cancellation', (
      t,
    ) async {
      final connection = await fixture.connected(t, const Size(80, 24));
      await t.type('ignorescancel');
      await t.press('enter');
      await fixture.until(() => _said(connection, 'Holding on.'));
      await t.press('esc');
      expect(connection.app.value.transcript.turn, isA<model.Cancelling>());
      await t.pumpWidget(Text('removed'));
      await connection.close().timeout(const Duration(seconds: 5));
      await t.pump();
      expect(t.screen.text, 'removed');
      expect(connection.close(), same(connection.close()));
    });
  });
}
