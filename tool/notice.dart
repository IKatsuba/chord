// dimcode's one-time notice over the real window, no agent: it opens as
// the window starts, F2 opens it again once answered or closed, F3 puts a
// permission in its place and takes it back. Nothing is recorded: the
// fixture has no config home. --light and --plain as the other fixtures.
import 'dart:async';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/notices.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';

import 'wheel.dart' show wheelPermission;

/// The window with the notice open over [connection]'s transcript.
Widget noticePreview(StartConnection connection) {
  final entries = [
    for (var i = 0; i < 30; i++)
      model.UserEntry('row$i', 'Named transcript row $i'),
  ];
  connection.app.value = AppState(
    start: const StartState(phase: StartPhase.connected),
    transcript: model.Transcript(entries: entries),
  );
  void open() => connection.fold.dispatch(
    const FrontActed(NoticeOpenedAction(dimcodeNotice)),
  );
  void ask() {
    final app = connection.app.value;
    final asking = app.transcript.turn is model.AwaitingPermission;
    connection.app.value = AppState(
      start: app.start,
      notice: app.notice,
      transcript: model.Transcript(
        entries: entries,
        turn: asking
            ? const model.Idle()
            : model.AwaitingPermission(
                'turn',
                DateTime.now().millisecondsSinceEpoch,
                [wheelPermission(fitting: true)],
              ),
      ),
    );
  }

  var opened = false;
  return Builder(
    builder: (context) {
      if (!opened) {
        opened = true;
        context.owner.afterLayout(() => scheduleMicrotask(open));
      }
      return Actions(
        bindings: [
          Binding('ctrl+q', 'Quit fixture', () => exitApp(context)),
          Binding('f2', 'Open the notice again', open),
          Binding('f3', 'Ask a permission, or take it back', ask),
        ],
        child: TranscriptWindow(
          launch: const Launch(
            name: 'dimcode',
            agent: null,
            agentCommand: 'unused',
            version: '0.0.1',
            directory: 'project',
          ),
          connection: connection,
        ),
      );
    },
  );
}

Future<void> main(List<String> args) async {
  final connection = StartConnection(command: 'unused', cwd: '.');
  await runApp(
    noticePreview(connection),
    theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
    environment: {
      ...Platform.environment,
      if (args.contains('--plain')) 'NO_COLOR': '1',
    },
    beforeExit: connection.close,
  );
}
