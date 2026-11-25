@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/dev.dart' show shellWord;
import '../../fixtures/fake_harness.dart';
import 'resume_window_test.dart' show launch;
import 'window_fake_test.dart' show until;

void main() {
  group('failed-start original fake', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('session/new refusal leaves client resume available $size', (
        t,
      ) async {
        final directory = Directory.systemTemp.createTempSync(
          'chord-failed-start-',
        );
        final pids = <int>[];
        final connection = StartConnection(
          command: fakeAgentCommand(null, [
            '--start-fails',
            'alias',
          ]).map(shellWord).join(' '),
          cwd: directory.path,
          env: {'XDG_STATE_HOME': directory.path},
          agent: 'memory',
          owner: Owned(),
          open: fakeSessionOpener(pids.add),
        )..start();
        addTearDown(() async {
          await connection.close();
          expect(
            pids.where(
              (pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0,
            ),
            isEmpty,
          );
          directory.deleteSync(recursive: true);
        });
        await t.pumpWidget(
          TranscriptWindow(
            launch: launch,
            connection: connection,
            readSessionRecords: ({cancellationToken}) async => [],
          ),
          size: size,
        );
        await until(
          () => connection.app.value.start.phase == StartPhase.failed,
        );
        await t.pump();
        expect(
          t.screen,
          shows('memory did not start: it refused session/new:'),
        );
        expect(t.screen, shows('agentAlias'));
        await t.type('unsent draft');
        await t.press('enter');
        expect(connection.app.value.draft, 'unsent draft');
        expect(connection.app.value.transcript.entries, isEmpty);
        expect(connection.app.value.queue, isEmpty);
        await t.press('ctrl+c');
        await t.type('/resume');
        await t.press('enter');
        await t.pump();
        expect(t.screen, shows('No earlier memory session to resume'));
        expect(connection.app.value.draft, isEmpty);
      });
    }
  });
}
