import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/record_history.dart';

void main() {
  test(
    'fixture cross-directory recipe retains the actual fake override',
    () async {
      final argv = StartConnection(
        command: ['bun', 'original path/main.ts', '--scenario', 'text'],
        cwd: '.',
      );
      final literal = StartConnection(
        command: 'bun "original path/main.ts" --scenario text',
        cwd: '.',
      );
      try {
        expect(
          recordHistoryLaunch(argv).agentCommand,
          "bun 'original path/main.ts' --scenario text",
        );
        expect(recordHistoryLaunch(literal).agentCommand, literal.command);
      } finally {
        await argv.close();
        await literal.close();
      }
    },
  );

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('saved history and record warning remain visible $size', (
      t,
    ) async {
      final connection = StartConnection(command: 'unused', cwd: '.');
      addTearDown(connection.close);
      final history = recordActions(savedRecordFixture('.'));
      connection.app.value = reduceApp(
        const AppState(start: StartState(phase: StartPhase.connected)),
        HistoryReplayed(history.actions, state: AgentState.empty),
      );
      await t.pumpWidget(recordHistoryPreview(connection), size: size);
      expect(t.screen, shows('Inspect the saved notes'));
      expect(t.screen, shows('The saved notes are ready.'));
      connection.app.value = reduceApp(
        connection.app.value,
        const Transcribed(
          WarnedAction('record', 'Could not keep this record: fixture failure'),
        ),
      );
      await t.pump();
      expect(t.screen, shows('Could not keep this record: fixture failure'));
      expect(t.screen, shows('The saved notes are ready.'));
    });
  }
}
