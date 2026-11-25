// Bang-mode preview: every command uses deterministic injected output, never a shell.
import 'dart:async';
import 'dart:io';
import 'package:chord/cli.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/shell.dart';
import 'package:chord/ui/app/selection.dart' show CopyResult;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';

class _RecordedShell extends ShellProcess {
  _RecordedShell(String command, ShellOptions options) {
    scheduleMicrotask(() {
      if (_done.isCompleted) return;
      if (command == 'hold') {
        options.onOutput?.call(ShellStream.stdout, 'ready\n');
      } else if (command == 'empty') {
        _done.complete(const ShellEnd(code: 0));
      } else if (command == 'failed') {
        _done.complete(const ShellEnd(error: 'recording shell did not start'));
      } else {
        options.onOutput?.call(
          ShellStream.stdout,
          '${List.generate(12, (i) => 'line ${(i + 1).toString().padLeft(2, '0')}').join('\n')}\n',
        );
        options.onOutput?.call(ShellStream.stderr, 'warning\n');
        _done.complete(const ShellEnd(code: 3));
      }
    });
  }
  final _done = Completer<ShellEnd>();
  @override
  Future<ShellEnd> get ended => _done.future;
  @override
  void stop() {
    if (!_done.isCompleted) _done.complete(const ShellEnd(stopped: true));
  }
}

/// Real prompt/window wiring with recording output and no agent or child process.
Widget bashPreview(StartConnection connection, {bool code = false}) {
  connection.app.value = AppState(
    start: const StartState(
      phase: StartPhase.connected,
      sessionId: 'bash-fixture',
    ),
    transcript: code
        ? model.Transcript(
            entries: appended([], [
              model.AssistantEntry(
                'code',
                TextRun.empty.plus(r'''```sh
$ printf first
$ printf second
```

```ts
not runnable
```

> ```bash
> $ quoted script
> ```
'''),
              ),
            ]),
          )
        : model.Transcript.empty,
  );
  return TranscriptWindow(
    launch: const Launch(
      name: 'fixture',
      agent: null,
      agentCommand: 'unused',
      version: '0.0.1',
      directory: 'project',
    ),
    connection: connection,
    runShell: (command, options) => _RecordedShell(command, options),
    copy: (_, _) => const CopyResult.sent(),
  );
}

Future<void> main(List<String> args) async {
  final owner = Owned();
  final connection = StartConnection(command: 'unused', cwd: '.', owner: owner);
  await runApp(
    bashPreview(connection, code: args.contains('--code')),
    theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
    environment: {
      ...Platform.environment,
      if (args.contains('--plain')) 'NO_COLOR': '1',
    },
    beforeExit: () async {
      await connection.close();
      await leave(from: owner);
    },
  );
}
