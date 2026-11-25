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
  group('CTUI-35 tester: original ACP agents methods on fake MCP', () {
    for (final mode in [
      'queued then closed',
      'resource refused',
      'resource accepted',
    ]) {
      test(
        mode,
        () async {
          final runtimes = TestRuntimes(
            fakes: {
              'fake': (
                scenario: null,
                flags: mode == 'resource accepted'
                    ? ['--embedded-context']
                    : <String>[],
              ),
            },
          );
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

          final initialized = await answer(
            ask('initialize', {
              'protocolVersion': 1,
              'clientCapabilities': {'subagents': <String, Object?>{}},
            }),
          );
          expect(
            (((initialized['result'] as Map)['_meta'] as Map)['chord/acp']
                as Map)['extensions'],
            containsPair('agents', 1),
          );
          final opened = await answer(
            ask('session/new', {
              'cwd': runtimes.home.path,
              'mcpServers': <Object?>[],
            }),
          );
          final main = (opened['result'] as Map)['sessionId'] as String;
          await answer(
            ask('session/prompt', {
              'sessionId': main,
              'prompt': [
                {'type': 'text', 'text': 'agenttitled'},
              ],
            }),
          );
          Map<String, Object?>? child() {
            final reports = lines.messages
                .where((m) => m['method'] == 'session/update')
                .map((m) => (m['params'] as Map)['update'])
                .whereType<Map<String, Object?>>()
                .where(
                  (u) =>
                      u['sessionUpdate'] == 'subagent_update' &&
                      (u['_meta'] as Map?)?['chord/agent'] != null,
                );
            return reports.lastOrNull;
          }

          String said(String route) => [
            for (final m in lines.messages)
              if (m['method'] == 'session/update' &&
                  (m['params'] as Map)['sessionId'] == route)
                if (((m['params'] as Map)['update'] as Map)['sessionUpdate'] ==
                    'agent_message_chunk')
                  (((m['params'] as Map)['update'] as Map)['content']
                      as Map)['text'],
          ].join();
          final idle = await _until(() {
            final report = child();
            if (report == null ||
                (report['state'] as Map?)?['state'] != 'idle') {
              return null;
            }
            return said(
                  report['sessionId'] as String,
                ).contains('came in chunks')
                ? report
                : null;
          });
          final route = idle['sessionId'] as String,
              title = idle['title'] as String;
          if (mode == 'queued then closed') {
            final before = said(route).length;
            final first = await answer(
              ask('_chord/agents/send', {
                'sessionId': route,
                'prompt': [
                  {'type': 'text', 'text': 'long'},
                ],
              }),
            );
            expect(first['result'], {'delivery': 'sent'});
            await _until(() => said(route).length > before ? true : null);
            expect(
              (await answer(
                ask('_chord/agents/send', {
                  'sessionId': route,
                  'prompt': [
                    {'type': 'text', 'text': 'text'},
                  ],
                }),
              ))['result'],
              {'delivery': 'queued'},
            );
          } else {
            final resource = {
              'type': 'resource',
              'resource': {'uri': 'custom:child', 'blob': 'opaque'},
              '_meta': {'source': 'client'},
            };
            final result = await answer(
              ask('_chord/agents/send', {
                'sessionId': route,
                'prompt': [
                  {'type': 'text', 'text': 'text'},
                  resource,
                ],
              }),
            );
            if (mode == 'resource accepted') {
              expect(result['result'], {'delivery': 'sent'});
              await _until(
                () =>
                    said(route).contains('Received a resource:') ? true : null,
              );
              final text = await _until(() {
                final match = RegExp(
                  r'Received a resource: ([^\n]*)',
                ).firstMatch(said(route));
                if (match == null) return null;
                try {
                  return jsonDecode(match.group(1)!);
                } on FormatException {
                  return null;
                }
              });
              expect(text, resource);
            } else {
              expect((result['error'] as Map)['code'], -32602);
              expect(
                (result['error'] as Map)['message'],
                contains('does not take embedded resources'),
              );
              expect(said(route), isNot(contains('Received a resource:')));
            }
          }
          expect(
            (await answer(
              ask('_chord/agents/close', {'sessionId': route}),
            ))['result'],
            {
              'closed': [title],
            },
          );
          for (final method in ['_chord/agents/send', '_chord/agents/close']) {
            final result = await answer(
              ask(method, {
                'sessionId': route,
                if (method.endsWith('/send'))
                  'prompt': [
                    {'type': 'text', 'text': 'text'},
                  ],
              }),
            );
            expect((result['error'] as Map)['code'], -32002);
          }
          expect(pids, hasLength(2));
        },
        skip: fakeAgentSkip,
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  });
}
