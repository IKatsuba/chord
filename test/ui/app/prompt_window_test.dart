@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

void main() {
  group('prompt window', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('history, multiline submission and draft clear at $size', (
        t,
      ) async {
        final connection = await fixture.connected(t, size);
        await fixture.sent(t, connection, 'text');
        await t.type('draft');
        await t.press('up');
        expect(t.screen, shows('│ › text'));
        await t.press('down');
        expect(t.screen, shows('│ › draft'));
        await t.press('ctrl+c');
        expect(t.exitRequested, isFalse);
        expect(t.screen, isNot(shows('draft')));
        await t.type('one');
        await t.press('shift+enter');
        await t.type('two');
        await t.press('enter');
        await fixture.until(
          () =>
              connection.app.value.transcript.entries
                      .whereType<model.UserEntry>()
                      .length ==
                  2 &&
              connection.app.value.transcript.turn is model.Idle,
        );
        expect(
          connection.app.value.transcript.entries
              .whereType<model.UserEntry>()
              .last
              .text,
          'one\ntwo',
        );
        await t.press('up');
        expect(t.screen, shows('│ › one'));
        await t.press('ctrl+c');
        await t.press('up');
        expect(t.screen, shows('│ › text'));
        await t.press('ctrl+c');
        await t.press('down');
        expect(t.screen, shows('│ › one'));
        await t.press('ctrl+c ctrl+c');
        expect(t.exitRequested, isFalse);
        await t.press('ctrl+c');
        expect(t.exitRequested, isTrue);
      });

      testWidgets(
        'Esc restores queued prompts ahead of the current draft at $size',
        (t) async {
          final connection = await fixture.connected(
            t,
            size,
            flags: ['--step-ms', '100'],
          );
          await t.type('slow');
          await t.press('enter');
          await fixture.until(
            () => connection.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .isNotEmpty,
          );
          await t.type('queued first');
          await t.press('shift+enter');
          await t.type('second line');
          await t.press('enter');
          await t.type('queued second');
          await t.press('enter');
          expect(connection.app.value.queue, hasLength(2));
          expect(t.screen, shows(' › queued first …'));
          await t.type('draft');
          await t.press('esc');
          await fixture.until(
            () => connection.app.value.transcript.entries
                .whereType<model.CancelledEntry>()
                .isNotEmpty,
          );
          await t.pump();
          expect(connection.app.value.queue, isEmpty);
          expect(t.screen, shows('│ › queued first'));
          expect(t.screen, shows('│   second line'));
          expect(t.screen, shows('│   queued second'));
          expect(t.screen, shows('│   draft'));
          expect(
            connection.app.value.transcript.entries
                .whereType<model.UserEntry>(),
            hasLength(1),
          );
          await t.press('ctrl+c');
          expect(t.exitRequested, isFalse);
        },
      );
    }
  });
  group('tester U7 prompt lifecycle with the fake', skip: fakeAgentSkip, () {
    testWidgets('late answer updates leave the unsent draft untouched', (
      t,
    ) async {
      final connection = await fixture.connected(
        t,
        const Size(80, 24),
        flags: ['--step-ms', '100'],
      );
      await fixture.sent(t, connection, 'late');
      await t.type('unsent draft');
      await fixture.until(
        () => connection.app.value.transcript.entries
            .whereType<model.AssistantEntry>()
            .any((e) => e.text.text.contains('Late, after the answer.')),
      );
      await t.pump();
      expect(t.screen, shows('│ › unsent draft'));
      expect(
        connection.app.value.transcript.entries
            .whereType<model.UserEntry>()
            .single
            .text,
        'late',
      );
      await t.press('up');
      expect(t.screen, shows('│ › late'));
      await t.press('down');
      expect(t.screen, shows('│ › unsent draft'));
    });

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'ignored cancel restores queue once and repeat Esc keeps draft at $size',
        (t) async {
          final connection = await fixture.connected(t, size);
          await t.type('ignorescancel');
          await t.press('enter');
          await fixture.until(
            () => connection.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .isNotEmpty,
          );
          await t.type('queued');
          await t.press('enter');
          await t.type('draft');
          await t.press('esc');
          expect(connection.app.value.queue, isEmpty);
          expect(connection.app.value.transcript.turn, isA<model.Cancelling>());
          expect(t.screen, shows('│ › queued'));
          expect(t.screen, shows('│   draft'));
          await t.press('esc');
          expect(t.screen, shows('│ › queued'));
          expect(t.screen, shows('│   draft'));
          expect(
            connection.app.value.transcript.entries
                .whereType<model.UserEntry>(),
            hasLength(1),
          );
          await t.press('ctrl+c');
          expect(t.exitRequested, isFalse);
          await t.press('ctrl+z');
          expect(t.screen, isNot(shows('│ › queued')));
          await t.press('ctrl+d');
          expect(t.exitRequested, isTrue);
        },
      );

      testWidgets(
        'crashed agent still records accepted sends and history at $size',
        (t) async {
          final connection = await fixture.connected(t, size);
          await fixture.sent(t, connection, 'crash');
          expect(
            connection.app.value.transcript.entries
                .whereType<model.ErrorEntry>(),
            isNotEmpty,
          );
          await t.type('after exit');
          await t.press('enter');
          await fixture.until(
            () =>
                connection.app.value.transcript.entries
                        .whereType<model.UserEntry>()
                        .length ==
                    2 &&
                connection.app.value.transcript.turn is model.Idle,
          );
          await t.pump();
          await t.press('up');
          expect(t.screen, shows('│ › after exit'));
          await t.press('up');
          expect(t.screen, shows('│ › crash'));
        },
      );

      testWidgets(
        'empty submissions stay draft and accepted text is trimmed at $size',
        (t) async {
          final connection = await fixture.connected(t, size);
          await t.type('   ');
          await t.press('enter');
          expect(connection.app.value.transcript.entries, isEmpty);
          expect(connection.app.value.draft, '   ');
          await t.press('ctrl+c');
          await t.type('  text  ');
          await t.press('enter');
          await fixture.until(
            () =>
                connection.app.value.transcript.turn is model.Idle &&
                connection.app.value.transcript.entries.isNotEmpty,
          );
          expect(
            connection.app.value.transcript.entries
                .whereType<model.UserEntry>()
                .single
                .text,
            'text',
          );
          await t.press('up');
          expect(connection.app.value.draft, 'text');
          expect(t.screen, shows('│ › text'));
        },
      );
    }

    testWidgets('two windows keep queued drafts and cancellation separate', (
      t,
    ) async {
      final first = await fixture.connected(t, const Size(80, 24));
      final other = WidgetTester();
      addTearDown(other.dispose);
      final second = await fixture.connected(other, const Size(40, 12));
      await t.type('ignorescancel');
      await t.press('enter');
      await fixture.until(
        () => first.app.value.transcript.entries
            .whereType<model.AssistantEntry>()
            .isNotEmpty,
      );
      await t.type('first queue');
      await t.press('enter');
      await fixture.sent(other, second, 'text');
      await other.type('second draft');
      await t.press('esc');
      expect(t.screen, shows('│ › first queue'));
      expect(other.screen, shows('│ › second draft'));
      expect(second.app.value.queue, isEmpty);
      expect(second.app.value.transcript.turn, isA<model.Idle>());
      expect(
        second.app.value.transcript.entries
            .whereType<model.UserEntry>()
            .single
            .text,
        'text',
      );
    });
  });
}
