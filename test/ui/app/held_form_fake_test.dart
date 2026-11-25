// A form the original fake asks between turns (`leftform`) is held above
// the prompt and folds into the room the window leaves it, as the
// original's does: its working line, the prompt box and the status line
// keep their rows, and the fields give way under `… N more lines`.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/acp/connection.dart' show windowCapabilities;
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
import 'window_fake_test.dart' show launch, until;

void main() {
  group('a form held between turns', skip: fakeAgentSkip, () {
    testWidgets('folds at 80x24 with the status line on the last row', (
      t,
    ) async {
      final directory = Directory.systemTemp.createTempSync('chord-form-');
      final connection = StartConnection(
        command: fakeAgentCommand(null, const []).map(shellWord).join(' '),
        cwd: directory.path,
        agent: 'fake',
        open: fakeOpenerWith(capabilities: windowCapabilities()),
        owner: Owned(),
      )..start();
      addTearDown(() async {
        await connection.close();
        directory.deleteSync(recursive: true);
      });
      await until(
        () => connection.app.value.start.phase == StartPhase.connected,
      );
      await t.pumpWidget(
        TranscriptWindow(launch: launch, connection: connection),
        size: const Size(80, 24),
      );
      await t.type('leftform');
      await t.press('enter');
      await until(
        () =>
            connection.app.value.transcript.turn is model.Idle &&
            connection.app.value.transcript.asking.isNotEmpty,
      );
      await t.pump();
      final lines = t.screen.lines;
      final tags = lines.indexWhere((line) => line.contains('Tags'));
      expect(lines[tags], startsWith('│     Tags           not set'));
      expect(lines[tags + 1], startsWith('│   … 2 more lines'));
      expect(lines.join('\n'), isNot(contains('Accept   Decline')));
      expect(lines[tags + 3], startsWith('│ ctrl+x a to answer'));
      expect(lines[23], startsWith('  ● input · ctrl+x a to answer'));
    });
  });
}
