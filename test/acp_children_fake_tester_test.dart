@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp_agent.dart';
import 'package:chord/server/server.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/place.dart';
import 'package:test/test.dart';

import 'acp_rig.dart' show Lines;
import 'fixtures/fake_harness.dart';
import 'fixtures/runtimes.dart';

Future<T> _until<T>(T? Function() read) async {
  final limit = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(limit)) {
    if (read() case final value?) return value;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('ACP child condition was not observed');
}

void main() {
  group('CTUI-35 tester: original ACP child wire scenarios', () {
    for (final subagents in [true, false]) {
      test(
        'agentsquiet through real fake MCP with subagents=$subagents',
        () async {
          final runtimes = TestRuntimes();
          addTearDown(runtimes.dispose);
          final runtimesCommand = runtimes.commandOf('fake');
          final server = await serveChord();
          addTearDown(server.close);
          final input = StreamController<List<int>>(), lines = Lines();
          final exited = Completer<LeaveExit>();
          final errors = <String>[], pids = <int>[];
          runAcp(
            input: input.stream,
            sink: lines,
            agent: 'fake',
            version: 'test',
            place: (cwd) async =>
                (cwd: cwd, start: SessionStart(command: runtimesCommand)),
            children: (_) async => (
              runtimes: runtimes.names,
              startOf: (name) {
                if (name != 'fake') throw NotATestRuntime(name);
                return SessionStart(command: runtimesCommand);
              },
            ),
            stateDir: '${runtimes.home.path}/state',
            server: server,
            stderr: errors.add,
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
                  if (!identical(command, runtimesCommand)) {
                    throw StateError(
                      'Only the catalog-issued fake command may launch',
                    );
                  }
                  final agent = await openAgent(
                    command: command,
                    env: runtimes.env,
                    cwd: cwd,
                    onTraffic: onTraffic,
                    onPermission: onPermission,
                    capabilities: capabilities,
                    onElicitation: onElicitation,
                    relay: relay,
                    cancellationToken: cancellationToken,
                    stop: fakeStopBounds,
                  );
                  pids.add(agent.pid);
                  return agent;
                },
          );
          addTearDown(() async {
            if (!input.isClosed) await input.close();
            expect(
              await exited.future.timeout(const Duration(seconds: 30)),
              const LeaveExit.code(0),
            );
            for (final pid in pids) {
              expect(
                Process.runSync('kill', ['-0', '$pid']).exitCode,
                isNot(0),
                reason: 'fake $pid remains',
              );
            }
          });
          var serial = 0;
          void send(Map<String, Object?> message) =>
              input.add(utf8.encode('${jsonEncode(message)}\n'));
          Future<Map<String, Object?>> answer(int id) => _until(
            () => lines.messages
                .where((m) => m['id'] == id && !m.containsKey('method'))
                .firstOrNull,
          );
          int ask(String method, Map<String, Object?> params) {
            final id = ++serial;
            send({
              'jsonrpc': '2.0',
              'id': id,
              'method': method,
              'params': params,
            });
            return id;
          }

          await answer(
            ask('initialize', {
              'protocolVersion': 1,
              'clientCapabilities': {
                if (subagents) 'subagents': <String, Object?>{},
              },
            }),
          );
          final opened = await answer(
            ask('session/new', {
              'cwd': runtimes.home.path,
              'mcpServers': <Object?>[],
            }),
          );
          final main = (opened['result'] as Map)['sessionId'] as String;
          final turn = ask('session/prompt', {
            'sessionId': main,
            'prompt': [
              {'type': 'text', 'text': 'agentsquiet'},
            ],
          });
          if (subagents) {
            final permission = await _until(
              () => lines.messages
                  .where((m) => m['method'] == 'session/request_permission')
                  .firstOrNull,
            );
            final params = permission['params'] as Map;
            final route = params['sessionId'] as String;
            expect(route, startsWith('$main/'));
            await _until(
              () =>
                  lines.messages.any(
                    (m) =>
                        m['method'] == 'session/update' &&
                        (m['params'] as Map)['sessionId'] == main &&
                        ((m['params'] as Map)['update'] as Map)['sessionId'] ==
                            route &&
                        ((((m['params'] as Map)['update'] as Map)['state']
                                as Map?)?['state']) ==
                            'requires_action',
                  )
                  ? true
                  : null,
            );
            final option = (params['options'] as List).cast<Map>().firstWhere(
              (o) => o['kind'] == 'allow_once',
            );
            send({
              'jsonrpc': '2.0',
              'id': permission['id'],
              'result': {
                'outcome': {
                  'outcome': 'selected',
                  'optionId': option['optionId'],
                },
              },
            });
            await answer(turn);
            await _until(
              () =>
                  lines.messages.any(
                    (m) =>
                        m['method'] == 'session/update' &&
                        (m['params'] as Map)['sessionId'] == route &&
                        ((m['params'] as Map)['update']
                                as Map)['sessionUpdate'] ==
                            'agent_message_chunk',
                  )
                  ? true
                  : null,
            );
            expect(
              lines.messages
                  .where((m) => m['method'] == '_chord/session/state')
                  .map((m) => (m['params'] as Map)['state']),
              isNot(contains('requires_action')),
            );
          } else {
            await answer(turn);
            await _until(
              () =>
                  errors.any(
                    (line) => line.contains("refused a subagent's permission"),
                  )
                  ? true
                  : null,
            );
            expect(
              lines.messages.any(
                (m) => m['method'] == 'session/request_permission',
              ),
              isFalse,
            );
            expect(
              lines.messages
                  .where((m) => m['method'] == 'session/update')
                  .every((m) => (m['params'] as Map)['sessionId'] == main),
              isTrue,
            );
          }
          expect(pids, hasLength(3));
        },
        skip: fakeAgentSkip,
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  });
}
