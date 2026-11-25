import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart';
import 'package:chord/acp_agent.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'acp_rig.dart' show Lines, NoRecording, CountedGroups;

Future<T> _until<T>(T? Function() read) async {
  final limit = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(limit)) {
    if (read() case final value?) return value;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw TimeoutException('ACP targeted reopen did not settle');
}

void main() {
  group('tester: CTUI-176 completed ACP targeted reopen', () {
    late Directory state;
    setUp(() async {
      state = await Directory.systemTemp.createTemp('acp-targeted-tester-');
      final dir = await Directory(recordsDir(state.path)).create();
      var index = 0;
      for (final (agent, at, text) in [
        ('memory', 10, 'older'),
        ('memory', 30, 'selected 界🙂'),
        ('other', 90, 'other agent'),
      ]) {
        await File(p.join(dir.path, '${index++}.jsonl')).writeAsString(
          [
            encodeRecord({
              'type': 'session',
              'version': 1,
              'sessionId': 'shared',
              'agent': agent,
              'cwd': 'project',
              'at': 1,
            }),
            encodeRecord({
              'type': 'prompt',
              'turnId': 't',
              'prompt': text,
              'images': 0,
              'at': at,
            }),
            encodeRecord({
              'type': 'update',
              'turnId': 't',
              'at': at + 1,
              'update': {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'reply $text'},
              },
            }),
          ].join(),
        );
      }
    });
    tearDown(() => state.delete(recursive: true));

    Future<List<Map<String, Object?>>> reopen(
      String method,
      bool targeted,
    ) async {
      final input = StreamController<List<int>>(), sink = Lines();
      final processes = <MemoryAgentProcess>[], timers = <Timer>[];
      final exited = Completer<LeaveExit>();
      var scans = 0, named = 0;
      final host = runAcp(
        input: input.stream,
        sink: sink,
        agent: 'memory',
        version: 'test',
        stateDir: state.path,
        place: (cwd) async =>
            (cwd: cwd, start: const SessionStart(command: 'memory')),
        records: () async {
          scans++;
          if (targeted) throw StateError('ACP by-id reached the full scan');
          return readRecords(state.path);
        },
        recordsWithId: targeted
            ? (id) {
                named++;
                return readRecordsWithId(state.path, id);
              }
            : null,
        recording: (_) => NoRecording(),
        childRecording: (_) => NoRecording(),
        groups: CountedGroups(),
        stderr: (_) {},
        exit: (how) {
          if (!exited.isCompleted) exited.complete(how);
        },
        launch:
            ({
              required command,
              env,
              required cwd,
              required onTraffic,
              required onPermission,
              capabilities,
              onElicitation,
              relay,
              cancellationToken,
            }) async {
              late final MemoryAgentProcess process;
              process = MemoryAgentProcess(
                onSignal: (_) {
                  process.exit();
                  process.closeStdout();
                  process.closeStderr();
                },
              );
              processes.add(process);
              final answered = <Object?>{};
              timers.add(
                Timer.periodic(const Duration(milliseconds: 1), (_) {
                  if (process.stdin.closed) {
                    process.exit();
                    process.closeStdout();
                    process.closeStderr();
                    return;
                  }
                  for (final message in process.stdin.messages) {
                    if (!message.containsKey('method') ||
                        !answered.add(message['id'])) {
                      continue;
                    }
                    final result = switch (message['method']) {
                      'initialize' => {
                        'protocolVersion': 1,
                        'agentCapabilities': {
                          'loadSession': true,
                          'sessionCapabilities': {
                            'resume': <String, Object?>{},
                          },
                        },
                      },
                      'session/load' || 'session/resume' => <String, Object?>{},
                      _ => null,
                    };
                    if (result != null) {
                      process.send({
                        'jsonrpc': '2.0',
                        'id': message['id'],
                        'result': result,
                      });
                    }
                  }
                }),
              );
              return connectAgent(
                process,
                onTraffic: onTraffic,
                onPermission: onPermission,
                capabilities: capabilities,
                onElicitation: onElicitation,
                relay: relay,
                cancellationToken: cancellationToken,
              );
            },
      );
      try {
        void ask(int id, String name, Map<String, Object?> params) => input.add(
          utf8.encode(
            '${jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': name, 'params': params})}\n',
          ),
        );
        Future<Map<String, Object?>> answer(int id) => _until(
          () => sink.messages
              .where((m) => m['id'] == id && !m.containsKey('method'))
              .firstOrNull,
        );
        ask(1, 'initialize', {'protocolVersion': 1});
        expect((await answer(1)).containsKey('error'), isFalse);
        ask(2, method, {
          'sessionId': 'shared',
          'cwd': 'project',
          'mcpServers': <Object?>[],
        });
        final response = await answer(2);
        expect(response.containsKey('error'), isFalse, reason: '$response');
        expect(response['result'], isA<Map>());
        expect(host.sessions.keys, ['shared']);
        expect(host.reopening, isEmpty);
        expect(scans, targeted ? 0 : 1);
        expect(named, targeted ? 1 : 0);
        final text = sink.messages
            .where((m) => m['method'] == 'session/update')
            .map((m) => jsonEncode(m['params']))
            .join('\n');
        if (method == 'session/load') {
          expect(text, contains('selected 界🙂'));
          expect(text, isNot(contains('older')));
          expect(text, isNot(contains('other agent')));
        } else {
          expect(text, isNot(contains('selected 界🙂')));
        }
        final result = [
          for (final message in sink.messages)
            if (message['id'] == 2 || message['method'] == 'session/update')
              message,
        ];
        return result;
      } finally {
        await input.close();
        expect(
          await exited.future.timeout(const Duration(seconds: 10)),
          const LeaveExit.code(0),
        );
        for (final timer in timers) {
          timer.cancel();
        }
        expect(processes.every((p) => p.exited), isTrue);
      }
    }

    test('a record filename collision never redirects ACP agent ids', () async {
      await File(p.join(recordsDir(state.path), 'shared.jsonl')).writeAsString(
        [
          encodeRecord({
            'type': 'session',
            'version': 1,
            'sessionId': 'different-id',
            'agent': 'memory',
            'cwd': 'project',
            'at': 1,
          }),
          encodeRecord({
            'type': 'prompt',
            'turnId': 't',
            'prompt': 'wrong record',
            'images': 0,
            'at': 999,
          }),
        ].join(),
      );
      for (final method in ['session/load', 'session/resume']) {
        expect(await reopen(method, true), await reopen(method, false));
      }
    });

    for (final method in ['session/load', 'session/resume']) {
      test(
        '$method completes with selected past/response equal to full scan',
        () async {
          expect(await reopen(method, true), await reopen(method, false));
        },
      );
    }
  });
}
