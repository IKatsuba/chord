/// Compiled integration fixture: the production session/window with a copier
/// that records an attempt and deliberately ignores cancellation/completion.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/platform/group_exec.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == groupExecFlag) groupExec(args);
  if (args.length != 2) {
    throw ArgumentError('Expected fake command and journal');
  }
  final journal = File(args[1]);
  final terminal = StdioTerminal();
  final connection = StartConnection(
    command: args[0],
    cwd: Directory.current.path,
    agent: 'fake',
  )..start();
  await runApp(
    TranscriptWindow(
      launch: const Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: 'project',
      ),
      connection: connection,
      terminal: terminal,
      copy: (text, token) {
        journal.writeAsStringSync(
          '${jsonEncode({'text': text, 'cancelled': token.isCancelled})}\n',
          mode: FileMode.append,
        );
        return Completer<copy.CopyResult>().future;
      },
    ),
    terminal: terminal,
    beforeExit: () async {
      await leave();
      await terminal.close();
    },
  );
}
