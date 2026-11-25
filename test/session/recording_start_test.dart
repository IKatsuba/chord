import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/launch_connection.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/start_state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'reopen_session_test.dart' as memory;

const launch = Launch(
  name: 'memory',
  agent: null,
  agentCommand: 'memory',
  version: 'fixture',
  directory: 'fixture-project',
);

Future<void> until(StartConnection connection, bool Function() matches) {
  if (matches()) return Future.value();
  final done = Completer<void>();
  void changed() {
    if (matches() && !done.isCompleted) done.complete();
  }

  connection.app.addListener(changed);
  return done.future
      .timeout(const Duration(seconds: 5))
      .whenComplete(() => connection.app.removeListener(changed));
}

Future<void> connected(StartConnection connection) => until(
  connection,
  () => connection.app.value.start.phase == StartPhase.connected,
);
Future<void> idle(StartConnection connection) =>
    until(connection, () => connection.app.value.transcript.turn is Idle);

void main() {
  for (final transition in [
    'connected-resume',
    'connected-clear',
    'gone-resume',
  ]) {
    test(
      'public state observer $transition cannot publish retired facts',
      () async {
        final dir = await memory.directory();
        final first = memory.Memory();
        final replacement = memory.Memory()..hang = true;
        final release = Completer<void>();
        var opens = 0, replaced = false;
        late StartConnection connection;
        connection = StartConnection(
          command: 'memory',
          cwd: dir.path,
          open:
              ({
                required command,
                env,
                required cwd,
                required onTraffic,
                required onPermission,
                relay,
                cancellationToken,
              }) async {
                final transport = opens++ == 0 ? first : replacement;
                if (identical(transport, replacement) &&
                    transition == 'connected-clear') {
                  await release.future;
                }
                return transport.open(
                  command: command,
                  env: env,
                  cwd: cwd,
                  onTraffic: onTraffic,
                  onPermission: onPermission,
                  relay: relay,
                  cancellationToken: cancellationToken,
                );
              },
        );
        addTearDown(() async {
          if (!release.isCompleted) release.complete();
          await connection.close();
        });
        connection.state.addListener(() {
          final target = transition == 'gone-resume'
              ? StartPhase.gone
              : StartPhase.connected;
          if (!replaced && connection.state.value.phase == target) {
            replaced = true;
            if (transition == 'connected-clear') {
              connection.conversation.clear().ignore();
            } else {
              connection.conversation
                  .resume(Resume(sessionId: 'replacement', cwd: dir.path))
                  .ignore();
            }
            expect(connection.app.value.start.phase, StartPhase.starting);
          }
        });
        connection.start();
        if (transition == 'gone-resume') {
          await connected(connection);
          first.process.exit();
          first.process.closeStdout();
          first.process.closeStderr();
        }
        await until(connection, () => replaced);
        await Future<void>.delayed(Duration.zero);
        expect(connection.app.value.start.phase, StartPhase.starting);
        expect(connection.app.value.start.sessionId, isNull);
        if (!release.isCompleted) release.complete();
        await connection.close();
      },
    );
  }
  test(
    'same-opening nested warning keeps valid connection publication',
    () async {
      final transport = memory.Memory();
      final connection = StartConnection(
        command: 'memory',
        cwd: '.',
        open: transport.open,
      );
      addTearDown(connection.close);
      connection.state.addListener(() {
        if (connection.state.value.phase == StartPhase.connected) {
          connection.conversation.recordingFailed('nested warning');
        }
      });
      connection.start();
      await connected(connection);
      expect(
        connection.app.value.transcript.entries
            .whereType<WarningEntry>()
            .single
            .message,
        'nested warning',
      );
      expect(connection.app.value.start.sessionId, 'literal/id');
    },
  );
  test(
    'public initial-state observer close starts no process or stale app',
    () async {
      var opens = 0;
      final transport = memory.Memory();
      final connection = StartConnection(
        command: 'memory',
        cwd: '.',
        open:
            ({
              required command,
              env,
              required cwd,
              required onTraffic,
              required onPermission,
              relay,
              cancellationToken,
            }) {
              opens++;
              return transport.open(
                command: command,
                env: env,
                cwd: cwd,
                onTraffic: onTraffic,
                onPermission: onPermission,
                relay: relay,
                cancellationToken: cancellationToken,
              );
            },
      );
      connection.state.addListener(() {
        if (connection.state.value.phase == StartPhase.starting) {
          connection.close().ignore();
        }
      });
      connection.start();
      await connection.close();
      expect(opens, 0);
      expect(connection.app.value.closing, isTrue);
    },
  );

  test(
    'clear cancels selected preparation before process start and cannot publish its past later',
    () async {
      final dir = await memory.directory();
      final file = File(p.join(dir.path, 'record.jsonl'));
      final text = encodeRecord({
        'type': 'prompt',
        'turnId': 'saved',
        'prompt': 'OLD PAST',
        'images': 0,
        'at': 1,
      });
      await file.writeAsString(text);
      final transport = memory.Memory();
      var opens = 0;
      final connection = StartConnection(
        command: 'memory',
        cwd: dir.path,
        agent: 'memory',
        resume: Resume(
          sessionId: 'literal/id',
          cwd: dir.path,
          record: file.path,
        ),
        open:
            ({
              required command,
              env,
              required cwd,
              required onTraffic,
              required onPermission,
              relay,
              cancellationToken,
            }) {
              opens++;
              return transport.open(
                command: command,
                env: env,
                cwd: cwd,
                onTraffic: onTraffic,
                onPermission: onPermission,
                relay: relay,
                cancellationToken: cancellationToken,
              );
            },
      );
      addTearDown(connection.close);
      connection.start();
      await connection.conversation.clear();
      await connected(connection);
      expect(opens, 1);
      expect(connection.app.value.resumed, isNull);
      expect(connection.app.value.transcript.entries, isEmpty);
      expect(await file.readAsString(), text);
      await connection.close();
    },
  );

  test(
    'production factory keeps looking-only new sessions absent then saves actual work',
    () async {
      final dir = await memory.directory();
      final transport = memory.Memory();
      final connection = startLaunchConnection(
        launch,
        cwd: dir.path,
        open: transport.open,
        stateDirectory: () => dir.path,
      );
      addTearDown(connection.close);
      await connected(connection);
      final recorder = connection.recording as FileRecording;
      final path = recorder.path!;
      expect(await Directory(recordsDir(dir.path)).exists(), isFalse);
      expect(connection.conversation.resumable, isNull);
      connection.conversation.send('actual prompt');
      await idle(connection);
      await connection.close();
      final lines = parseRecord(await File(path).readAsString());
      expect(lines.whereType<Map>().map((e) => e['type']), [
        'session',
        'opened',
        'state',
        'prompt',
        'result',
      ]);
      expect(connection.conversation.resumable, (
        agent: 'memory',
        sessionId: 'literal/id',
      ));
      expect(transport.process.exited, isTrue);
    },
  );

  test(
    'known record history and omission remain absent from appended live bytes',
    () async {
      final dir = await memory.directory();
      final file = File(p.join(dir.path, 'record.jsonl'));
      final prefix = utf8.encode(
        '${encodeRecord({'type': 'prompt', 'turnId': 'saved', 'at': 1.25, 'prompt': 'PAST', 'images': 0})}${encodeRecord({'type': 'future', 'meaningful': true})}',
      );
      await file.writeAsBytes(prefix);
      final transport = memory.Memory();
      final recorder = FileRecording(dir.path, failed: fail);
      final connection = startLaunchConnection(
        launch,
        cwd: 'invocation-directory',
        open: transport.open,
        recording: recorder,
        resume: Resume(
          sessionId: 'literal/id',
          cwd: dir.path,
          record: file.path,
        ),
      );
      addTearDown(connection.close);
      await connected(connection);
      expect(connection.cwd, dir.path);
      expect(transport.openedCwd, dir.path);
      expect(connection.app.value.omittedHistory, isTrue);
      expect(await file.readAsBytes(), prefix);
      connection.conversation.send('LIVE');
      await idle(connection);
      await connection.close();
      final bytes = await file.readAsBytes();
      expect(bytes.sublist(0, prefix.length), prefix);
      final appended = utf8.decode(bytes.sublist(prefix.length));
      expect(parseRecord(appended).whereType<Map>().map((e) => e['type']), [
        'opened',
        'state',
        'prompt',
        'result',
      ]);
      expect(appended, isNot(contains('PAST')));
      expect(appended, isNot(contains('Some saved history')));
      expect(appended, isNot(contains('HistoryReplayed')));
    },
  );

  test(
    'owner close joins the admitted drain after transport shutdown',
    () async {
      final dir = await memory.directory();
      final transport = memory.Memory();
      final entered = Completer<void>(), release = Completer<void>();
      final recorder = FileRecording(
        dir.path,
        failed: fail,
        uuid: () => 'fixture',
        append: (path, text) async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          await Directory(p.dirname(path)).create(recursive: true);
          await File(path).writeAsString(text, mode: FileMode.append);
        },
      );
      final connection = startLaunchConnection(
        launch,
        cwd: dir.path,
        open: transport.open,
        recording: recorder,
      );
      addTearDown(connection.close);
      await connected(connection);
      connection.conversation.send('admitted');
      await entered.future;
      var done = false;
      final closing = connection.close().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      release.complete();
      await closing;
      expect(transport.process.exited, isTrue);
      expect(
        await File(p.join(recordsDir(dir.path), 'fixture.jsonl')).exists(),
        isTrue,
      );
      await dir.delete(recursive: true);
      await connection.close();
      expect(await dir.exists(), isFalse);
    },
  );

  test(
    'store lookup failure warns once but leaves actual ACP work resumable',
    () async {
      final dir = await memory.directory();
      final transport = memory.Memory();
      final connection = startLaunchConnection(
        launch,
        cwd: dir.path,
        open: transport.open,
        stateDirectory: () =>
            throw StateError('HOME or XDG_STATE_HOME required'),
      );
      addTearDown(connection.close);
      await connected(connection);
      expect(
        connection.app.value.transcript.entries.whereType<WarningEntry>(),
        hasLength(1),
      );
      connection.conversation.send('still sends');
      await idle(connection);
      await connection.close();
      expect(
        connection.app.value.transcript.entries.whereType<WarningEntry>(),
        hasLength(1),
      );
      expect(connection.conversation.resumable, (
        agent: 'memory',
        sessionId: 'literal/id',
      ));
      expect(await Directory(recordsDir(dir.path)).exists(), isFalse);
    },
  );
}
