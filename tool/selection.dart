import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';

/// Records adapter calls without accessing the host clipboard.
class SelectionRecorder {
  SelectionRecorder({this.failure = false, this.timeout = false, this.record});

  final bool failure;
  final bool timeout;
  final void Function(Map<String, Object?>)? record;
  final attempts = <String>[];
  final writes = <String>[];

  FutureOr<copy.CopyResult> call(String text, CancellationToken token) {
    attempts.add(text);
    record?.call({
      'event': 'attempt',
      'text': text,
      'cancelled': token.isCancelled,
    });
    if (timeout) {
      return Completer<copy.CopyResult>().future;
    }
    if (token.isCancelled) return const copy.CopyResult.failed('cancelled');
    if (failure) {
      return const copy.CopyResult.failed('recording clipboard refused');
    }
    writes.add(text);
    record?.call({'event': 'write', 'text': text});
    return const copy.CopyResult.sent();
  }
}

/// Seeds a real window with stable domain occurrences, without an agent.
Widget selectionPreview(
  StartConnection connection,
  List<String> args,
  SelectionRecorder recorder,
) {
  connection.app.value = AppState(
    start: const StartState(
      phase: StartPhase.connected,
      sessionId: 'selection-fixture',
    ),
    transcript: model.Transcript(
      entries: appended([], [
        const model.UserEntry('request', 'Select these request words'),
        model.AssistantEntry(
          'reply',
          TextRun.empty.plus(
            args.contains('--pick')
                ? 'Select these reply words.\n\n```ts\n\tcopy body\n\ntail\n```\n\n> ```console\n> quoted body\n> ```\n\n```dart\nopen body'
                : 'Reply **words** and a link [label](https://example.test).\n\n```dart\nprint("complete block");\n```\n\nLast reply paragraph.',
          ),
        ),
        if (args.contains('--many'))
          for (var i = 0; i < 100; i++)
            model.UserEntry('history$i', 'History row $i'),
        const model.UserEntry('next', 'Next eligible request'),
      ]),
    ),
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
    copyOnSelect: !args.contains('--manual'),
    copy: recorder.call,
  );
}

Future<void> main(List<String> args) async {
  final journal = File('build/ctui48_selection_record.jsonl');
  journal.parent.createSync(recursive: true);
  journal.writeAsStringSync('');
  final recorder = SelectionRecorder(
    failure: args.contains('--failure'),
    timeout: args.contains('--timeout'),
    record: (event) => journal.writeAsStringSync(
      '${jsonEncode(event)}\n',
      mode: FileMode.append,
    ),
  );
  final connection = StartConnection(command: 'unused', cwd: '.');
  await runApp(
    selectionPreview(connection, args, recorder),
    beforeExit: connection.close,
    theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
    environment: {
      ...Platform.environment,
      if (args.contains('--plain')) 'NO_COLOR': '1',
    },
  );
}
