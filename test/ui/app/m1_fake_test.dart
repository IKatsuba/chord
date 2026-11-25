@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

void main() {
  group('M1 journey through the original fake', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('reply, edit, permission, cancel, failure and quit at $size', (
        t,
      ) async {
        late int pid;
        final connection = await fixture.connected(
          t,
          size,
          flags: ['--step-ms', '100'],
          onPid: (value) => pid = value,
        );
        await t.press('? esc');
        await fixture.sent(t, connection, 'text');
        expect(t.screen, shows('Hello, world.'));
        await fixture.sent(t, connection, 'edit');
        expect(
          connection.app.value.transcript.entries.whereType<model.ToolEntry>(),
          isNotEmpty,
        );
        expect(t.screen, shows('2 additions and 1 removal'));
        await t.type('permission');
        await t.press('enter');
        await fixture.until(
          () =>
              connection.app.value.transcript.turn is model.AwaitingPermission,
        );
        await t.pump();
        expect(t.screen, shows('Write notes.txt'));
        await t.press('? esc 1');
        await fixture.until(
          () => connection.app.value.transcript.turn is model.Idle,
        );
        await t.pump();
        expect(
          connection.app.value.transcript.entries
              .whereType<model.PermissionEntry>()
              .single
              .option
              ?.optionId,
          'allow',
        );
        expect(t.screen, shows('Permission: allow.'));
        final replies = connection.app.value.transcript.entries
            .whereType<model.AssistantEntry>()
            .length;
        await t.type('slow');
        await t.press('enter');
        await fixture.until(
          () =>
              connection.app.value.transcript.entries
                  .whereType<model.AssistantEntry>()
                  .length >
              replies,
        );
        await t.press('esc');
        await fixture.until(
          () => connection.app.value.transcript.turn is model.Idle,
        );
        await t.pump();
        expect(
          connection.app.value.transcript.entries
              .whereType<model.CancelledEntry>(),
          hasLength(1),
        );
        expect(t.screen, shows('Interrupted by user'));
        await fixture.sent(t, connection, 'error');
        expect(
          connection.app.value.transcript.entries
              .whereType<model.ErrorEntry>()
              .single
              .message,
          'The fake agent failed on purpose.',
        );
        expect(t.screen, shows('⏺ The fake agent failed on purpose.'));
        expect(
          connection.app.value.transcript.entries
              .whereType<model.UserEntry>()
              .map((entry) => entry.text),
          ['text', 'edit', 'permission', 'slow', 'error'],
        );
        await t.press('ctrl+c');
        expect(t.exitRequested, isFalse);
        expect(t.screen.lines.last, '  Press ctrl+c again to quit');
        await t.press('ctrl+c');
        expect(t.exitRequested, isTrue);
        // The headless host requests exit; its owner performs the CLI's close.
        t.dispose();
        await connection.close();
        await fixture.until(
          () => Process.runSync('ps', ['-A', '-o', 'pgid=']).stdout
              .toString()
              .split('\n')
              .every((group) => group.trim() != '$pid'),
        );
      });
    }
  });

  group('tester: integrated M1 session isolation', skip: fakeAgentSkip, () {
    testWidgets(
      'help, ignored cancellation and late replies remain independent between windows',
      (t) async {
        final other = WidgetTester();
        addTearDown(other.dispose);
        final pids = <int>[];
        final first = await fixture.connected(
          t,
          const Size(80, 24),
          onPid: pids.add,
        );
        final second = await fixture.connected(
          other,
          const Size(40, 12),
          flags: ['--step-ms', '100'],
          onPid: pids.add,
        );
        await t.type('ignorescancel');
        await t.press('enter');
        await fixture.until(
          () => first.app.value.transcript.entries
              .whereType<model.AssistantEntry>()
              .isNotEmpty,
        );
        await t.type('first queue');
        await t.press('enter');
        expect(first.app.value.queue, hasLength(1));
        await fixture.sent(other, second, 'late');
        await other.type('second draft?');
        expect(second.app.value.shortcuts.help, isFalse);
        await t.press('? esc');
        expect(first.app.value.shortcuts.help, isFalse);
        expect(
          first.app.value.transcript.entries.whereType<model.CancelledEntry>(),
          isEmpty,
        );
        await t.press('esc');
        expect(first.app.value.queue, isEmpty);
        expect(first.app.value.draft, 'first queue');
        await t.press('esc');
        expect(first.app.value.draft, 'first queue');
        await fixture.until(
          () => second.app.value.transcript.entries
              .whereType<model.AssistantEntry>()
              .any(
                (entry) => entry.text.text.contains('Late, after the answer.'),
              ),
        );
        await other.pump();
        expect(second.app.value.draft, 'second draft?');
        expect(second.app.value.queue, isEmpty);
        expect(second.app.value.transcript.turn, isA<model.Idle>());
        expect(
          first.app.value.transcript.entries.whereType<model.UserEntry>(),
          hasLength(1),
        );
        expect(
          second.app.value.transcript.entries.whereType<model.UserEntry>(),
          hasLength(1),
        );
        await t.press('ctrl+c ctrl+d');
        expect(t.exitRequested, isTrue);
        expect(other.exitRequested, isFalse);
        await other.press('ctrl+d');
        expect(other.exitRequested, isFalse);
        await other.press('ctrl+c ctrl+d');
        expect(other.exitRequested, isTrue);
        t.dispose();
        other.dispose();
        await first.close();
        await second.close();
        await fixture.until(() {
          final groups = Process.runSync('ps', ['-A', '-o', 'pgid=']).stdout
              .toString()
              .split('\n')
              .map((line) => int.tryParse(line.trim()))
              .toSet();
          return pids.every((pid) => !groups.contains(pid));
        });
      },
    );
  });
}
