// The window declares notices and draws them, on the original's fake agent
// (tests/fixtures/fake_agent/scenarios/notices.ts), which sends a notice
// only to a client that declared `session.notices`.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/acp/connection.dart' show windowCapabilities;
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/start.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/dev.dart' show shellWord;
import '../../fixtures/fake_harness.dart';
import '../app/window_fake_test.dart' show launch, sent, until;

void main() {
  group('notices in the window', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('a notice is its own line between the reply blocks at '
          '$size', (t) async {
        final directory = Directory.systemTemp.createTempSync('chord-notice-');
        final connection = StartConnection(
          command: fakeAgentCommand().map(shellWord).join(' '),
          cwd: directory.path,
          agent: 'fake',
          open: fakeOpenerWith(capabilities: windowCapabilities()),
          owner: Owned(),
        )..start();
        addTearDown(() async {
          await connection.close();
          directory.deleteSync(recursive: true);
        });
        await t.pumpWidget(
          StartWindow(launch: launch, connection: connection),
          size: size,
        );
        await until(
          () => connection.app.value.start.phase == StartPhase.connected,
        );
        await sent(t, connection, 'notice');
        final entries = connection.app.value.transcript.entries;
        expect(
          entries.whereType<model.NoticeEntry>().single.title,
          'Fast mode turned off',
        );
        final text = t.screen.text;
        expect(text, contains('⏺ Fast mode turned off'));
        expect(text, contains('  Rate limit for fast mode reached'));
        // Sent as a notice, not as the reply's blockquote.
        expect(text, isNot(contains('**Fast mode')));
        expect(text, contains('Done.'));
      });
    }
  });
}
