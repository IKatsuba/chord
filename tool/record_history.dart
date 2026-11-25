// Owned replay and record-failure window; only the original fake can run.
import 'dart:io';
import 'dart:async';

import 'package:chord/cli.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/sessions.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:path/path.dart' as p;

import '../test/fixtures/fake.dart';
import 'dev.dart' show shellWord;

/// A short supported past shared by the live fixture and headless checks.
List<Map<String, Object?>> savedRecordFixture(String cwd) => [
  {
    'type': 'session',
    'version': 1,
    'sessionId': '11111111-1111-4111-8111-111111111111',
    'agent': 'fake',
    'cwd': cwd,
    'at': 1,
  },
  {
    'type': 'prompt',
    'turnId': 'saved',
    'prompt': 'Inspect the saved notes',
    'images': 0,
    'at': 2.25,
  },
  {
    'type': 'update',
    'turnId': 'saved',
    'update': {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'The saved notes are ready.'},
    },
  },
  {
    'type': 'result',
    'turnId': 'saved',
    'result': {'status': 'completed', 'stopReason': 'end_turn'},
  },
];

/// The actual fake override is retained in cross-directory reopen commands.
Launch recordHistoryLaunch(StartConnection connection) => Launch(
  name: 'fake',
  agent: null,
  agentCommand: connection.command is List<String>
      ? (connection.command as List<String>).map(shellWord).join(' ')
      : connection.command as String,
  version: '0.0.1',
  directory: 'project',
);

/// Draws the actual connected window without seeding or changing its state.
Widget recordHistoryPreview(
  StartConnection connection, {
  ReadResumeRecords readSessionRecords = readResumeRecords,
}) => Builder(
  builder: (context) => Actions(
    bindings: [Binding('ctrl+q', 'Quit fixture', () => exitApp(context))],
    child: TranscriptWindow(
      launch: recordHistoryLaunch(connection),
      connection: connection,
      readSessionRecords: readSessionRecords,
    ),
  ),
);

Future<void> main(List<String> args) async {
  final command = fakeAgentCommand('text');
  final root = await Directory.systemTemp.createTemp('chord-record-history-');
  final owner = Owned();
  Timer? background;
  Future<void> cleanup() async {
    background?.cancel();
    try {
      await leave(from: owner);
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  }

  late StartConnection connection;
  try {
    final record = File(p.join(root.path, 'saved.jsonl'));
    await record.writeAsString(
      [
        ...savedRecordFixture(root.path),
        if (args.contains('--omitted'))
          <String, Object?>{
            'type': 'future_history',
            'text': 'deferred content',
          },
      ].map(encodeRecord).join(),
    );
    final records = Directory(recordsDir(root.path));
    await records.create();
    Future<void> seed(String id, String title, String cwd, int number) async {
      final now = DateTime.now().millisecondsSinceEpoch - number * 60000;
      await File(p.join(records.path, 'earlier-$number.jsonl')).writeAsString(
        [
          for (final entry in savedRecordFixture(cwd))
            switch (entry['type']) {
              'session' => {...entry, 'sessionId': id, 'at': now},
              'prompt' => {
                ...entry,
                'prompt': 'Earlier saved request $number',
                'at': now,
              },
              _ => entry,
            },
          {'type': 'renamed', 'title': title, 'at': now},
        ].map(encodeRecord).join(),
      );
    }

    if (!args.contains('--remote-only')) {
      for (var i = 0; i < (args.contains('--many') ? 24 : 2); i++) {
        await seed(
          '22222222-2222-4222-8222-${(i + 1).toString().padLeft(12, '0')}',
          'Earlier local notes $i',
          root.path,
          i,
        );
      }
    }
    await seed(
      '33333333-3333-4333-8333-333333333333',
      'Earlier remote notes',
      p.join(root.path, 'another project'),
      100,
    );
    final recording = FileRecording(
      root.path,
      failed: (message) => connection.conversation.recordingFailed(message),
      append: args.contains('--warning')
          ? (path, lines) async =>
                throw StateError('fixture record write failed')
          : null,
    );
    connection = StartConnection(
      command: command,
      cwd: root.path,
      agent: 'fake',
      owner: owner,
      recording: recording,
      resume: Resume(
        sessionId: '11111111-1111-4111-8111-111111111111',
        cwd: root.path,
        record: record.path,
        prompt: 'Inspect the saved notes',
        lastUsedAt: DateTime.now().millisecondsSinceEpoch - 86400000,
        title: args.contains('--title')
            ? List.filled(8, 'Saved agent title 界😀').join(' ')
            : null,
      ),
    )..start();
    var startedBackground = false, queuedBackground = false;
    Object? backgroundOpening;
    if (args.contains('--ask-while-picking') ||
        args.contains('--stream-while-picking') ||
        args.contains('--queue-return')) {
      connection.app.addListener(() {
        final picker = connection.app.value.resumePicker;
        if (!startedBackground && picker != null) {
          startedBackground = true;
          backgroundOpening = picker.opening;
          background = Timer(const Duration(seconds: 1), () {
            if (!connection.app.value.closing &&
                identical(
                  connection.app.value.resumePicker?.opening,
                  backgroundOpening,
                )) {
              connection.conversation.send(
                args.contains('--queue-return')
                    ? 'mainbetween'
                    : args.contains('--ask-while-picking')
                    ? 'permission'
                    : 'slow',
              );
            }
          });
        }
        final turn = connection.app.value.transcript.turn;
        if (args.contains('--queue-return') &&
            !queuedBackground &&
            picker != null &&
            identical(picker.opening, backgroundOpening) &&
            turn is model.AwaitingPermission &&
            turn.between) {
          queuedBackground = true;
          connection.conversation.send('queued request one');
          connection.conversation.send('queued request two');
        }
      });
    }
    await runApp(
      recordHistoryPreview(
        connection,
        readSessionRecords: ({cancellationToken}) =>
            readRecords(root.path, cancellationToken: cancellationToken),
      ),
      theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
      environment: {
        ...Platform.environment,
        if (args.contains('--plain')) 'NO_COLOR': '1',
      },
      beforeExit: () async {
        try {
          await connection.close();
        } finally {
          await cleanup();
        }
      },
    );
  } finally {
    await cleanup();
  }
}
