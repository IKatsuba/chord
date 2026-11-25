import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';

/// The startup splash over a start that never ends, no agent: the slow
/// hint after five seconds, esc for the window, ctrl+c armed, ctrl+q quits.
Future<void> main(List<String> args) async {
  final connection = StartConnection(command: 'unused', cwd: '.')
    ..app.value = const AppState(start: StartState(phase: StartPhase.starting));
  await runApp(
    Builder(
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
          splash: true,
          readSessionRecords: ({cancellationToken}) async => [],
        ),
      ),
    ),
    beforeExit: connection.close,
    theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
    environment: {
      ...Platform.environment,
      if (args.contains('--plain')) 'NO_COLOR': '1',
    },
  );
}
