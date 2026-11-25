import 'dart:async';
import 'dart:io';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/terminal.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/mentions.dart';
import 'package:chord/ui/prompt/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord/cli.dart';

const _launch = Launch(
  name: 'fixture',
  agent: null,
  agentCommand: 'unused',
  version: '0.0.1',
  directory: 'project',
);

/// Deterministic current-directory names; no filesystem walk or agent.
const mentionPreviewFiles = [
  'notes.md',
  'source.dart',
  'space name.txt',
  'src/alpha.dart',
  'src/beta.dart',
  'src/delta.dart',
  'src/epsilon.dart',
  'src/gamma.dart',
  'src/long directory/a literal filename that exceeds the small completion row.dart',
  'tests/a_test.dart',
  'tests/b_test.dart',
  'tests/c_test.dart',
];

/// The actual production window with staged injected candidates and history.
Widget mentionsPreview(
  StartConnection connection, {
  bool agents = false,
  bool large = false,
  MatchMentions? match,
}) {
  connection.app.value = AppState(
    start: const StartState(
      phase: StartPhase.connected,
      sessionId: 'mention-fixture',
    ),
    transcript: model.Transcript(
      entries: appended([], [
        for (var i = 0; i < 80; i++)
          model.AssistantEntry(
            'history$i',
            TextRun.empty.plus('Transcript record $i'),
          ),
      ]),
    ),
  );
  return TranscriptWindow(
    launch: _launch,
    connection: connection,
    recipients: agents
        ? const [
            MentionRecipient('parser', color: Colors.cyan),
            MentionRecipient('docs', color: Colors.blue),
            MentionRecipient('bugfix', color: Colors.green),
            MentionRecipient('bugfix 2', color: Colors.magenta),
            MentionRecipient('main', color: Colors.red),
          ]
        : const [],
    walkFiles: (cwd, {cancellationToken}) async => large
        ? [
            for (var i = 0; i < 100; i++)
              'source/file_${i.toString().padLeft(3, '0')}.dart',
          ]
        : mentionPreviewFiles,
    matchMentions: match,
  );
}

class _SlowMatch {
  final _finder = MentionMatcher();
  Timer? _timer;
  Completer<List<String>?>? _pending;
  Future<List<String>?> match(List<String> names, String query) {
    _timer?.cancel();
    if (_pending?.isCompleted == false) _pending!.complete(null);
    final done = Completer<List<String>?>();
    _pending = done;
    _timer = Timer(const Duration(milliseconds: 350), () async {
      _timer = null;
      final found = await _finder.match(names, query);
      if (!done.isCompleted) done.complete(found);
    });
    return done.future;
  }

  void dispose() {
    _timer?.cancel();
    _finder.dispose();
    if (_pending?.isCompleted == false) _pending!.complete(null);
  }
}

Future<void> main(List<String> args) async {
  final owner = Owned();
  final connection = StartConnection(command: 'unused', cwd: '.', owner: owner);
  final slow = args.contains('--slow') ? _SlowMatch() : null;
  await runApp(
    mentionsPreview(
      connection,
      agents: args.contains('--agents'),
      large: args.contains('--many'),
      match: slow?.match,
    ),
    theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
    environment: {
      ...Platform.environment,
      if (args.contains('--plain')) 'NO_COLOR': '1',
    },
    beforeExit: () async {
      slow?.dispose();
      await connection.close();
      await leave(from: owner);
    },
  );
}
