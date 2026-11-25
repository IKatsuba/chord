@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'permission_fake_test.dart' as permission;
import 'window_fake_test.dart' as fixture;

void main() {
  group(
    'tester: permission window lifetime through original fake',
    skip: fakeAgentSkip,
    () {
      for (final size in [const Size(80, 24), const Size(120, 40)]) {
        testWidgets(
          'cancel withdraws permission and ignores stale answer at $size',
          (t) async {
            final connection = await fixture.connected(t, size);
            final turn = await permission.ask(t, connection, 'permission');
            final request = turn.permissions.single.id;
            connection.conversation.interrupt();
            await permission.idle(t, connection);
            expect(t.screen, isNot(shows('Do you want to proceed?')));
            expect(
              connection.app.value.transcript.entries
                  .whereType<model.CancelledEntry>(),
              hasLength(1),
            );
            final before = connection.app.value.transcript.entries.length;
            connection.conversation.choose(request, 'allow');
            await t.pump();
            expect(connection.app.value.transcript.entries, hasLength(before));
            await fixture.sent(t, connection, 'text');
            expect(t.screen, shows('Hello, world.'));
          },
        );

        testWidgets(
          'agent exit withdraws pending prompt and leaves quit reachable at $size',
          (t) async {
            late int pid;
            final connection = await fixture.connected(
              t,
              size,
              onPid: (value) => pid = value,
            );
            await permission.ask(t, connection, 'permission');
            Process.killPid(-pid, ProcessSignal.sigkill);
            await fixture.until(
              () => connection.app.value.start.phase == StartPhase.gone,
            );
            await t.pump();
            expect(t.screen, isNot(shows('Do you want to proceed?')));
            expect(
              connection.app.value.transcript.turn,
              isNot(isA<model.AwaitingPermission>()),
            );
            expect(
              connection.app.value.transcript.entries
                  .whereType<model.ErrorEntry>(),
              isNotEmpty,
            );
            await t.press('ctrl+d');
            expect(t.exitRequested, isTrue);
          },
        );
      }

      testWidgets('two concurrent sessions answer only their own request', (
        t,
      ) async {
        final other = WidgetTester();
        try {
          final first = await fixture.connected(t, const Size(80, 24));
          final second = await fixture.connected(other, const Size(120, 40));
          await permission.ask(t, first, 'twins');
          await permission.ask(other, second, 'permission');
          await t.press('down enter');
          await permission.idle(t, first);
          expect(t.screen, shows('Permission: allow-here.'));
          expect(
            second.app.value.transcript.turn,
            isA<model.AwaitingPermission>(),
          );
          await other.press('esc');
          await permission.idle(other, second);
          expect(other.screen, shows('Permission: deny.'));
          expect(
            first.app.value.transcript.entries
                .whereType<model.PermissionEntry>()
                .single
                .option
                ?.optionId,
            'allow-here',
          );
          expect(
            second.app.value.transcript.entries
                .whereType<model.PermissionEntry>()
                .single
                .option,
            isNull,
          );
        } finally {
          other.dispose();
        }
      });
    },
  );
}
