// A sign-in in the window, opened with what the agent says of its account
// (CHD-629): a prompt refused for want of a login mid-session, drawn as the
// original's Transcript.tsx 153-161, and a start refused for one, both
// under SignIn.tsx's block.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/dev.dart' show shellWord;
import '../../fixtures/fake_harness.dart';
import 'resume_window_test.dart' show launch;
import 'window_fake_test.dart' as fixture;

const _wayOn =
    "chord does not sign agents in. Sign in with fake's own CLI in a "
    'terminal, or set its API key where it offers one.';

void main() {
  group('CTUI-160: a sign-in opens with the account', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('a prompt refused mid-session at $size', (t) async {
        final c = await fixture.connected(
          t,
          size,
          flags: [
            '--auth-required',
            'prompt',
            '--auth-status',
            'authenticated',
          ],
        );
        await fixture.until(() => c.app.value.start.sessionId != null);
        await t.type('hello');
        await t.press('enter');
        await fixture.until(
          () => c.app.value.transcript.entries
              .whereType<model.ErrorEntry>()
              .isNotEmpty,
        );
        await t.pump();
        final text = t.screen.lines.map((line) => line.trimRight()).join('\n');
        expect(
          t.screen,
          shows('fake needs a sign-in: Authentication required'),
        );
        expect(
          text.replaceAll(RegExp(r'\s+'), ' '),
          contains(
            '⎿ fake reports Claude Max · name@example.com · Example Org. '
            '${_wayOn.replaceAll(RegExp(r'\s+'), ' ')}',
          ),
        );
        expect(t.screen, isNot(shows('fake offers')));
      });

      testWidgets('a start refused with no account signed in at $size', (
        t,
      ) async {
        final directory = Directory.systemTemp.createTempSync(
          'chord-sign-in-start-',
        );
        final pids = <int>[];
        final connection = StartConnection(
          command: fakeAgentCommand(null, [
            '--auth-required',
            'methods',
            '--auth-status',
            'unauthenticated',
          ]).map(shellWord).join(' '),
          cwd: directory.path,
          env: {'XDG_STATE_HOME': directory.path},
          agent: 'fake',
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
        await fixture.until(
          () => connection.app.value.start.phase == StartPhase.failed,
        );
        await t.pump();
        expect(
          t.screen,
          shows('⎿  fake reports that no account is signed in.'),
        );
        final account = t.screen.lines.indexWhere(
          (line) => line.contains('no account is signed in'),
        );
        final offers = t.screen.lines.indexWhere(
          (line) => line.contains('fake offers these sign-ins:'),
        );
        expect(offers, account + 1);
        expect(t.screen.lines[offers], isNot(contains('⎿')));
      });
    }
  });
}
