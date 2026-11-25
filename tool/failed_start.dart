import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';

/// Agent-free failed-start prompt and empty-resume surface.
Widget failedStartPreview(StartConnection connection, List<String> args) {
  connection.app.value = AppState(
    start: StartState(
      phase: StartPhase.failed,
      reason: args.contains('--tall')
          ? [
              for (var i = 1; i <= 120; i++)
                'Failure detail line $i 界😀 ${'wrapped words ' * 6}',
            ].join(' ')
          : 'The scripted session could not start. Its original failure words remain in the transcript and wrap to the available width.',
    ),
  );
  return Builder(
    builder: (context) => Actions(
      bindings: [Binding('ctrl+q', 'Quit fixture', () => exitApp(context))],
      child: TranscriptWindow(
        launch: const Launch(
          name: 'fake',
          agent: null,
          agentCommand: 'unused',
          version: '0.0.1',
          directory: 'fixture-project',
        ),
        connection: connection,
        readSessionRecords: ({cancellationToken}) async => [],
      ),
    ),
  );
}

Future<void> main(List<String> args) async {
  final connection = StartConnection(command: 'unused', cwd: '.');
  await runApp(
    failedStartPreview(connection, args),
    beforeExit: connection.close,
    theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
    environment: {
      ...Platform.environment,
      if (args.contains('--plain')) 'NO_COLOR': '1',
    },
  );
}
