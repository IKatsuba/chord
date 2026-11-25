import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart'
    show AgentInput, AgentProcess, MemoryAgentProcess;
import 'package:chord/acp/schema.dart';
import 'package:chord/version.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

/// An agent in memory, the connection over it, and what crossed.
class Harness {
  Harness({
    this.onPermission,
    void Function(Traffic)? onTraffic,
    bool exitOnTerm = true,
  }) {
    process = MemoryAgentProcess(
      onSignal: (signal) {
        if (!exitOnTerm) return;
        process.exit(
          signal == ProcessSignal.sigterm
              ? const Exit(143, 'SIGTERM')
              : const Exit(137, 'SIGKILL'),
        );
        process.closeStdout();
        process.closeStderr();
      },
    );
    this.onTraffic = onTraffic ?? traffic.add;
  }

  late final MemoryAgentProcess process;
  final traffic = <Traffic>[];
  late final void Function(Traffic) onTraffic;
  PermissionHandler? onPermission;
  final asked = <(RequestPermissionRequest, CancellationToken)>[];
  final permissionAnswers = <Completer<RequestPermissionResponse>>[];

  Future<RequestPermissionResponse> _permission(
    RequestPermissionRequest request,
    CancellationToken token,
  ) {
    asked.add((request, token));
    final answer = Completer<RequestPermissionResponse>();
    permissionAnswers.add(answer);
    return answer.future;
  }

  /// What chord wrote, one message per line.
  List<Map<String, Object?>> get written => process.stdin.messages;

  /// The last request chord wrote for [method].
  Map<String, Object?> lastRequest(String method) =>
      written.lastWhere((m) => m['method'] == method);

  void answer(Object? id, Map<String, Object?> result) =>
      process.send({'jsonrpc': '2.0', 'id': id, 'result': result});

  Future<Agent> connect({
    CancellationToken? token,
    StopBounds stop = const StopBounds(),
  }) => connectAgent(
    process,
    onTraffic: onTraffic,
    onPermission: onPermission ?? _permission,
    cancellationToken: token,
    stop: stop,
  );

  /// Connects and answers `initialize`, under fake time.
  Agent open(FakeAsync async, {Map<String, Object?>? init}) {
    Agent? agent;
    connect().then((a) => agent = a);
    async.flushMicrotasks();
    answer(
      lastRequest('initialize')['id'],
      init ??
          {
            'protocolVersion': 1,
            'agentInfo': {'name': 'fake', 'version': '1'},
          },
    );
    async.flushMicrotasks();
    return agent!;
  }

  List<String> get trafficKinds => [
    for (final t in traffic)
      switch (t) {
        AgentTraffic(:final message) =>
          'agent ${((message['params'] as Map?)?['update'] as Map?)?['sessionUpdate'] ?? message['method'] ?? (message.containsKey('result') ? 'result' : 'error')}',
        ChordTraffic(:final message) =>
          'chord ${message['method'] ?? (message.containsKey('result') ? 'result' : 'error')}',
        StderrTraffic(:final text) => 'stderr $text',
      },
  ];
}

Map<String, Object?> update(String sessionId, Map<String, Object?> update) => {
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {'sessionId': sessionId, 'update': update},
};

Map<String, Object?> permission(Object? id, String sessionId) => {
  'jsonrpc': '2.0',
  'id': id,
  'method': 'session/request_permission',
  'params': {
    'sessionId': sessionId,
    'toolCall': {'toolCallId': 'write-3', 'title': 'Write notes.txt'},
    'options': [
      {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
    ],
  },
};

const cancelledOutcome = {
  'outcome': {'outcome': 'cancelled'},
};

void main() {
  test('M0 and M1 declare no capability', () {
    expect(clientCapabilities().toJson(), isEmpty);
  });

  group('initialize', () {
    test('says protocol 1, nothing declared, and chord\'s name and version; '
        'the whole answer is kept', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(
          async,
          init: {
            'protocolVersion': 2,
            'agentCapabilities': {'loadSession': true},
            '_meta': {
              'steering': {'supported': true},
            },
          },
        );
        expect(h.written.first, {
          'jsonrpc': '2.0',
          'method': 'initialize',
          'id': 0,
          'params': {
            'protocolVersion': 1,
            'clientCapabilities': <String, Object?>{},
            'clientInfo': {'name': 'chord', 'version': version},
          },
        });
        expect(agent.init.protocolVersion, 2);
        expect(agent.init.agentCapabilities!.loadSession, isTrue);
        expect(agent.init.meta, {
          'steering': {'supported': true},
        });
        expect(agent.pid, h.process.pid);
        expect(agent.gone(), isNull);
      });
    });

    test('a refusal (-32022) fails the start with its message, the agent '
        'stopped', () {
      fakeAsync((async) {
        final h = Harness();
        Object? error;
        h.connect().then(
          (_) {},
          onError: (Object e) {
            error = e;
          },
        );
        async.flushMicrotasks();
        h.process.send({
          'jsonrpc': '2.0',
          'id': 0,
          'error': {
            'code': -32022,
            'message': 'Unsupported protocol version',
            'data': {
              'requested': 1,
              'supported': [2],
            },
          },
        });
        async.elapse(const Duration(seconds: 3));
        expect(
          error,
          isA<RpcException>()
              .having((e) => e.code, 'code', -32022)
              .having(
                (e) => e.message,
                'message',
                'Unsupported protocol version',
              ),
        );
        expect(h.process.stdin.ended, isTrue);
        expect(h.process.signals.first, ProcessSignal.sigterm);
      });
    });

    test('an agent whose stdout ends before answering fails the start with '
        'its last words', () {
      fakeAsync((async) {
        final h = Harness();
        Object? error;
        h.connect().then(
          (_) {},
          onError: (Object e) {
            error = e;
          },
        );
        async.flushMicrotasks();
        h.process
          ..writeStderr('Traceback\nImportError: acp\n')
          ..exit(const Exit(1))
          ..closeStderr()
          ..closeStdout();
        async.elapse(const Duration(seconds: 3));
        expect(
          error,
          isA<AgentGone>()
              .having(
                (e) => e.message,
                'message',
                'The agent exited: Traceback\nImportError: acp',
              )
              .having((e) => e.exit, 'exit', const Exit(1))
              .having(
                (e) => e.stderr,
                'stderr',
                const Tail(['Traceback', 'ImportError: acp'], 0),
              ),
        );
      });
    });

    test('a start whose program could not be executed fails with cannot '
        'start', () {
      fakeAsync((async) {
        late final MemoryAgentProcess process;
        final status = Completer<Exit>();
        process = MemoryAgentProcess();
        Object? error;
        connectAgent(
          _FailedExec(process, status.future),
          onTraffic: (_) {},
          onPermission: (_, _) => Completer<RequestPermissionResponse>().future,
        ).then(
          (_) {},
          onError: (Object e) {
            error = e;
          },
        );
        async.flushMicrotasks();
        status.completeError(
          const CannotStart('agent', 'No such file or directory'),
        );
        process
          ..closeStderr()
          ..closeStdout();
        async.elapse(const Duration(seconds: 3));
        expect(
          error.toString(),
          'cannot start agent: No such file or directory',
        );
      });
    });

    test('a token cancelled during initialize gives up, the agent stopped', () {
      fakeAsync((async) {
        final h = Harness();
        final token = CancellationToken();
        Object? error;
        h
            .connect(token: token)
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        token.cancel();
        async.elapse(const Duration(seconds: 3));
        expect(error, isA<CancelledException>());
        expect(h.process.stdin.ended, isTrue);
      });
    });

    test('a start never answered stays pending: no timeout', () {
      fakeAsync((async) {
        final h = Harness();
        var settled = false;
        h.connect().whenComplete(() => settled = true).ignore();
        async.elapse(const Duration(hours: 1));
        expect(settled, isFalse);
      });
    });
  });

  group('one ingress', () {
    test('an update sent before a reply reaches the traffic before the '
        'reply\'s future completes', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        var trafficAtAnswer = 0;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .then((_) => trafficAtAnswer = h.traffic.length);
        async.flushMicrotasks();
        final id = h.lastRequest('session/new')['id'];
        h.process.writeStdout(
          utf8.encode(
            '${jsonEncode(update('s', {'sessionUpdate': 'available_commands_update', 'availableCommands': []}))}\n'
            '${jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'sessionId': 's'},
            })}\n',
          ),
        );
        async.flushMicrotasks();
        expect(h.trafficKinds.sublist(h.trafficKinds.length - 3), [
          'chord session/new',
          'agent available_commands_update',
          'agent result',
        ]);
        expect(trafficAtAnswer, h.traffic.length);
      });
    });

    test('unknown kinds and notifications reach the traffic raw; a reply '
        'after the caller gave up is tapped and dropped', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        final token = CancellationToken();
        Object? error;
        agent
            .newSession(
              NewSessionRequest(cwd: '/w', mcpServers: const []),
              cancellationToken: token,
            )
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        token.cancel();
        async.flushMicrotasks();
        expect(error, isA<CancelledException>());
        h.process.send(
          update('s', {'sessionUpdate': 'future_update', 'detail': 1}),
        );
        h.process.send({
          'jsonrpc': '2.0',
          'method': '_fake/notice',
          'params': {'text': 'x'},
        });
        h.answer(h.lastRequest('session/new')['id'], {'sessionId': 's'});
        async.flushMicrotasks();
        expect(h.trafficKinds.sublist(h.trafficKinds.length - 3), [
          'agent future_update',
          'agent _fake/notice',
          'agent result',
        ]);
        expect(
          (h.traffic[h.traffic.length - 3] as AgentTraffic).message,
          update('s', {'sessionUpdate': 'future_update', 'detail': 1}),
        );
      });
    });

    test('a subscriber that throws is dropped, and routing goes on', () {
      fakeAsync((async) {
        var heard = 0;
        final h = Harness(
          onTraffic: (_) {
            heard++;
            throw StateError('reducer bug');
          },
        );
        final agent = h.open(async);
        NewSessionResponse? opened;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .then((r) => opened = r);
        async.flushMicrotasks();
        h.answer(h.lastRequest('session/new')['id'], {'sessionId': 's'});
        async.flushMicrotasks();
        expect(opened!.sessionId, 's');
        expect(heard, 4);
      });
    });

    test('stderr is not traffic of connectAgent\'s, and framing replies '
        'never reach the traffic', () {
      fakeAsync((async) {
        final h = Harness();
        h.open(async);
        final before = h.traffic.length;
        h.process.writeStdout(utf8.encode('not json\n[1]\n7\n'));
        async.flushMicrotasks();
        expect(h.traffic.length, before);
        expect(
          h.written
              .sublist(h.written.length - 3)
              .map((m) => (m['error'] as Map)['code']),
          [-32700, -32600, -32600],
        );
      });
    });
  });

  group('the writer', () {
    test('the tap\'s order is the bytes\' order, and nothing touches stdin '
        'while a flush is pending', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        h.process.stdin.hold = true;
        for (var i = 0; i < 3; i++) {
          agent
              .newSession(NewSessionRequest(cwd: '/$i', mcpServers: const []))
              .ignore();
        }
        agent.cancel('s');
        async.flushMicrotasks();
        h.process.stdin.release();
        async.flushMicrotasks();
        expect(h.process.stdin.addsWhileFlushing, 0);
        final tapped = [
          for (final t in h.traffic)
            if (t is ChordTraffic) t.message,
        ];
        expect(jsonEncode(h.written), jsonEncode(tapped));
      });
    });

    test('a pipe that fails fails the waiting requests as the agent gone, '
        'with nothing unhandled', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        Object? error;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        h.process.stdin.fail(const SocketException('Broken pipe'));
        async.elapse(const Duration(seconds: 1));
        expect(error, isA<AgentGone>());
        expect(agent.gone(), isNotNull);
      });
    });

    test('a request whose token is already cancelled is never sent', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        final before = h.written.length;
        Object? error;
        agent
            .prompt(
              PromptRequest(sessionId: 's', prompt: [ContentBlock.text('hi')]),
              cancellationToken: CancellationToken()..cancel(),
            )
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        expect(error, isA<CancelledException>());
        expect(h.written.length, before);
      });
    });
  });

  group('cancel and prompts', () {
    test('a prompt settles with the agent\'s own answer', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        PromptResponse? answer;
        agent
            .prompt(
              PromptRequest(sessionId: 's', prompt: [ContentBlock.text('hi')]),
            )
            .then((r) => answer = r);
        async.flushMicrotasks();
        h.answer(h.lastRequest('session/prompt')['id'], {
          'stopReason': 'cancelled',
        });
        async.flushMicrotasks();
        expect(answer!.stopReason, StopReason.cancelled);
      });
    });

    test('cancel queues session/cancel, then answers the session\'s '
        'waiting requests, and settles once queued', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        h.process.send(permission(5, 's'));
        h.process.send(permission(6, 'other'));
        async.flushMicrotasks();
        expect(h.asked, hasLength(2));
        h.process.stdin.hold = true;
        var queued = false;
        agent.cancel('s').then((_) => queued = true);
        async.flushMicrotasks();
        expect(queued, isTrue);
        expect(h.asked[0].$2.isCancelled, isTrue);
        expect(h.asked[1].$2.isCancelled, isFalse);
        // Queued behind the held flush, and settled all the same.
        expect(h.written.last['method'], 'session/cancel');
        h.process.stdin.release();
        async.flushMicrotasks();
        // ACP's order: the cancel, then the answers to what was asked.
        expect(h.written.sublist(h.written.length - 2), [
          {
            'jsonrpc': '2.0',
            'method': 'session/cancel',
            'params': {'sessionId': 's'},
          },
          {'jsonrpc': '2.0', 'id': 5, 'result': cancelledOutcome},
        ]);
      });
    });

    test('cancelling a prompt\'s token sends cancel and ends the wait with '
        'the token\'s exception; the answer is tapped and dropped', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        final token = CancellationToken();
        Object? error;
        agent
            .prompt(
              PromptRequest(sessionId: 's', prompt: [ContentBlock.text('hi')]),
              cancellationToken: token,
            )
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        token.cancel();
        async.flushMicrotasks();
        expect(error, isA<CancelledException>());
        expect(h.lastRequest('session/cancel')['params'], {'sessionId': 's'});
        h.answer(h.lastRequest('session/prompt')['id'], {
          'stopReason': 'cancelled',
        });
        async.flushMicrotasks();
        expect(h.trafficKinds.last, 'agent result');
      });
    });

    test('a prompt whose agent ignores cancel waits until close, which fails '
        'it as the agent gone', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        Object? error;
        agent
            .prompt(
              PromptRequest(sessionId: 's', prompt: [ContentBlock.text('hi')]),
            )
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        agent.cancel('s');
        async.elapse(const Duration(hours: 1));
        expect(error, isNull);
        agent.close();
        async.elapse(const Duration(seconds: 5));
        expect(error, isA<AgentGone>());
      });
    });

    test('cancel after close fails as the agent gone', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        agent.close();
        Object? error;
        agent
            .cancel('s')
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.elapse(const Duration(seconds: 5));
        expect(error, isA<AgentGone>());
      });
    });
  });

  group('the close barrier', () {
    test('a permission request and close in one turn: exactly one cancelled '
        'answer, ahead of stdin\'s end', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        h.process.send(permission(5, 's'));
        async.flushMicrotasks();
        agent.close();
        h.permissionAnswers.single.complete(
          RequestPermissionResponse.selected('allow'),
        );
        async.elapse(const Duration(seconds: 5));
        final answers = h.written.where((m) => m['id'] == 5).toList();
        expect(answers, [
          {'jsonrpc': '2.0', 'id': 5, 'result': cancelledOutcome},
        ]);
        expect(h.process.stdin.closedAt, h.process.stdin.bytes.length);
        expect(h.process.stdin.addsAfterClose, 0);
      });
    });

    test('a permission answer whose flush is pending when close comes still '
        'goes out ahead of the end', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        h.process.stdin.hold = true;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .ignore();
        async.flushMicrotasks();
        expect(h.process.stdin.flushing, isTrue);
        h.process.send(permission(5, 's'));
        async.flushMicrotasks();
        agent.close();
        async.elapse(const Duration(milliseconds: 500));
        expect(h.process.stdin.closed, isFalse);
        h.process.stdin.release();
        async.elapse(const Duration(seconds: 5));
        expect(h.written.last, {
          'jsonrpc': '2.0',
          'id': 5,
          'result': cancelledOutcome,
        });
        expect(h.process.stdin.closedAt, h.process.stdin.bytes.length);
        expect(h.process.stdin.addsAfterClose, 0);
        expect(h.process.stdin.addsWhileFlushing, 0);
      });
    });

    test('cancel then close: one answer and one session/cancel before the '
        'end', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        h.process.send(permission(5, 's'));
        async.flushMicrotasks();
        agent.cancel('s');
        agent.close();
        async.elapse(const Duration(seconds: 5));
        expect(h.written.where((m) => m['id'] == 5), hasLength(1));
        expect(
          h.written.where((m) => m['method'] == 'session/cancel'),
          hasLength(1),
        );
        expect(h.process.stdin.closedAt, h.process.stdin.bytes.length);
      });
    });

    test('a stdin that never drains: close still ends within the ladder, '
        'with nothing thrown', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        h.process.stdin.hold = true;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .ignore();
        async.flushMicrotasks();
        var closed = false;
        Object? error;
        agent.close().then(
          (_) => closed = true,
          onError: (Object e) {
            error = e;
          },
        );
        async.elapse(const Duration(seconds: 3, milliseconds: 100));
        expect(closed, isTrue);
        expect(error, isNull);
        expect(h.process.signals.first, ProcessSignal.sigterm);
        expect(h.process.stdin.closed, isFalse);
      });
    });

    test('a ladder that fails throws AgentExitError, and still fails the '
        'waiting requests and stops routing', () {
      fakeAsync((async) {
        final h = Harness(exitOnTerm: false);
        final agent = h.open(async);
        Object? pending;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .then(
              (_) {},
              onError: (Object e) {
                pending = e;
              },
            );
        Object? closeError;
        agent.close().then(
          (_) {},
          onError: (Object e) {
            closeError = e;
          },
        );
        async.elapse(const Duration(seconds: 8));
        expect(closeError, isA<AgentExitError>());
        expect(pending, isA<AgentGone>());
        final asked = h.asked.length;
        h.process.send(permission(9, 's'));
        async.flushMicrotasks();
        expect(h.asked.length, asked);
      });
    });

    test('close is idempotent', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        expect(identical(agent.close(), agent.close()), isTrue);
        async.elapse(const Duration(seconds: 5));
        expect(
          h.process.signals.where((s) => s == ProcessSignal.sigterm),
          hasLength(1),
        );
      });
    });
  });

  group('exit, stdout\'s end and stderr\'s end, in every order', () {
    Object? pendingError(
      FakeAsync async,
      Harness h,
      Agent agent,
      void Function() events,
    ) {
      Object? error;
      agent
          .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      async.flushMicrotasks();
      events();
      return error;
    }

    test('exit, stdout, stderr: the exit and the tail are attached', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        Object? error;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        h.process
          ..writeStderr('panic: boom\n')
          ..exit(const Exit(2));
        async.flushMicrotasks();
        expect(agent.gone(), isNull, reason: 'the exit alone ends nothing');
        h.process.closeStdout();
        async.flushMicrotasks();
        expect(agent.gone(), 'panic: boom');
        h.process.closeStderr();
        async.elapse(const Duration(milliseconds: 1));
        expect(
          error,
          isA<AgentGone>()
              .having(
                (e) => e.message,
                'message',
                'The agent exited: panic: boom',
              )
              .having((e) => e.exit, 'exit', const Exit(2)),
        );
      });
    });

    test('stdout, stderr, then an exit later than 500 ms: not attached', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        Object? error;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        h.process
          ..closeStdout()
          ..closeStderr();
        async.elapse(const Duration(milliseconds: 499));
        expect(error, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(
          error,
          isA<AgentGone>()
              .having((e) => e.message, 'message', 'The agent exited.')
              .having((e) => e.exit, 'exit', isNull),
        );
        expect(agent.gone(), '');
      });
    });

    test('stderr, exit, stdout held open: nothing fails until close kills '
        'and stdout ends', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        final error = pendingError(async, h, agent, () {
          h.process
            ..closeStderr()
            ..exit(const Exit(0));
        });
        Object? later;
        agent
            .newSession(NewSessionRequest(cwd: '/x', mcpServers: const []))
            .then(
              (_) {},
              onError: (Object e) {
                later = e;
              },
            );
        async.elapse(const Duration(hours: 1));
        expect(error, isNull);
        expect(later, isNull);
        expect(agent.gone(), isNull);
        agent.close();
        async.elapse(const Duration(seconds: 3));
        expect(later, isA<AgentGone>());
      });
    });

    test('stdout\'s end with the process alive: gone at once, the error at '
        'the 500 ms settle, no exit', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        Object? error;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        h.process.writeStderr('bye');
        h.process.closeStdout();
        async.flushMicrotasks();
        expect(agent.gone(), 'bye');
        async.elapse(const Duration(milliseconds: 999));
        expect(error, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(
          error,
          isA<AgentGone>()
              .having((e) => e.message, 'message', 'The agent exited: bye')
              .having((e) => e.exit, 'exit', isNull),
        );
      });
    });

    test('messages read before stdout\'s end are routed first', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        NewSessionResponse? opened;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .then((r) => opened = r);
        async.flushMicrotasks();
        final id = h.lastRequest('session/new')['id'];
        h.process.writeStdout(
          utf8.encode(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'sessionId': 's'},
            }),
          ),
        );
        h.process.closeStdout();
        async.elapse(const Duration(seconds: 2));
        expect(opened!.sessionId, 's');
      });
    });

    test('exited settles at the exit and its last words, and fails '
        'nothing', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        Exit? exit;
        agent.exited.then((e) => exit = e);
        h.process
          ..writeStderr('last\n')
          ..exit(const Exit(0));
        async.elapse(const Duration(milliseconds: 499));
        expect(exit, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(exit, const Exit(0));
        expect(agent.gone(), isNull);
        h.process.closeStdout();
        async.flushMicrotasks();
        expect(agent.gone(), 'last');
      });
    });

    test('a line past 32 MiB fails the connection', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        Object? error;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        h.process.writeStdout(List.filled(32 * 1024 * 1024 + 1, 0x20));
        async.elapse(const Duration(seconds: 1));
        expect(agent.gone(), isNotNull);
        expect(error, isA<AgentGone>());
      });
    });
  });

  group('answers that are not objects', () {
    for (final result in <Object?>[null, <Object?>[], 5, 'x']) {
      test('initialize answered with $result fails the start, the agent '
          'stopped, with nothing unhandled', () {
        fakeAsync((async) {
          final h = Harness();
          Object? error;
          h.connect().then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
          async.flushMicrotasks();
          h.process.send({'jsonrpc': '2.0', 'id': 0, 'result': result});
          async.elapse(const Duration(seconds: 3));
          expect(
            error,
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'The agent answered initialize with $result.',
            ),
          );
          expect(h.process.stdin.ended, isTrue);
          expect(h.process.signals, isNotEmpty);
        });
      });
    }

    test('session/new answered with an array fails that request alone', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        Object? error;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        h.process.send({
          'jsonrpc': '2.0',
          'id': h.lastRequest('session/new')['id'],
          'result': [1],
        });
        async.flushMicrotasks();
        expect(error, isA<FormatException>());
        expect(agent.gone(), isNull);
      });
    });
  });

  group('a token cancelled while the last words are awaited', () {
    for (final pending in [true, false]) {
      test(
        pending
            ? 'ends an ask pending at stdout\'s end at once'
            : 'ends an ask made after stdout\'s end at once',
        () {
          fakeAsync((async) {
            final h = Harness();
            final agent = h.open(async);
            final token = CancellationToken();
            Object? error;
            Duration? at;
            void ask() => agent
                .newSession(
                  NewSessionRequest(cwd: '/w', mcpServers: const []),
                  cancellationToken: token,
                )
                .then(
                  (_) {},
                  onError: (Object e) {
                    error = e;
                    at = async.elapsed;
                  },
                );
            if (pending) ask();
            async.flushMicrotasks();
            // stderr and the exit stay open: the last words wait 500 ms.
            h.process.closeStdout();
            async.flushMicrotasks();
            if (!pending) ask();
            final start = async.elapsed;
            async.elapse(const Duration(milliseconds: 100));
            expect(error, isNull);
            token.cancel();
            async.flushMicrotasks();
            expect(error, isA<CancelledException>());
            expect(at! - start, const Duration(milliseconds: 100));
            async.elapse(const Duration(seconds: 2));
            expect(error, isA<CancelledException>());
            expect(token.hasCancellables, isFalse);
          });
        },
      );
    }
  });

  group('the connection\'s end is terminal', () {
    for (final (name, end, stdoutOpen)
        in <(String, void Function(Harness), bool)>[
          ('stdout\'s end', (h) => h.process.closeStdout(), false),
          (
            'stdin\'s pipe failing',
            (h) => h.process.stdin.fail(const SocketException('Broken pipe')),
            true,
          ),
        ]) {
      test('$name withdraws a waiting permission, drops the bridge\'s late '
          'answer, and refuses cancel', () {
        fakeAsync((async) {
          final h = Harness();
          final agent = h.open(async);
          h.process.send(permission(5, 's'));
          async.flushMicrotasks();
          final before = h.process.stdin.bytes.length;
          end(h);
          async.flushMicrotasks();
          expect(h.asked.single.$2.isCancelled, isTrue);
          h.permissionAnswers.single.complete(
            RequestPermissionResponse.selected('allow'),
          );
          Object? cancelError;
          agent
              .cancel('s')
              .then(
                (_) {},
                onError: (Object e) {
                  cancelError = e;
                },
              );
          // A pipe that failed leaves stdout open; what comes is not routed.
          if (stdoutOpen) {
            h.process.send(permission(6, 's'));
          }
          async.elapse(const Duration(seconds: 1));
          expect(h.process.stdin.bytes.length, before);
          expect(cancelError, isA<AgentGone>());
          expect(h.asked, hasLength(1), reason: 'nothing more is routed');
        });
      });
    }
  });

  test('an ask leaves no listener behind on its token, answered, failed or '
      'cancelled', () {
    fakeAsync((async) {
      final h = Harness();
      final agent = h.open(async);
      final token = CancellationToken();
      for (var i = 0; i < 3; i++) {
        agent
            .newSession(
              NewSessionRequest(cwd: '/$i', mcpServers: const []),
              cancellationToken: token,
            )
            .ignore();
        async.flushMicrotasks();
        final id = h.lastRequest('session/new')['id'];
        if (i == 1) {
          h.process.send({
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': -32603, 'message': 'no'},
          });
        } else {
          h.answer(id, {'sessionId': 's$i'});
        }
        async.flushMicrotasks();
        expect(token.hasCancellables, isFalse, reason: 'after ask $i');
      }
      agent
          .prompt(
            PromptRequest(sessionId: 's', prompt: [ContentBlock.text('hi')]),
            cancellationToken: token,
          )
          .ignore();
      async.flushMicrotasks();
      h.answer(h.lastRequest('session/prompt')['id'], {
        'stopReason': 'end_turn',
      });
      async.flushMicrotasks();
      expect(token.hasCancellables, isFalse);
      final other = CancellationToken();
      agent
          .newSession(
            NewSessionRequest(cwd: '/x', mcpServers: const []),
            cancellationToken: other,
          )
          .ignore();
      async.flushMicrotasks();
      other.cancel();
      async.flushMicrotasks();
      expect(other.hasCancellables, isFalse);
    });
  });

  group('a subscriber that writes or closes while it hears chord', () {
    test('a cancel it sends goes on the wire after the message it heard, '
        'as in the tap', () {
      fakeAsync((async) {
        late Agent agent;
        var opened = false;
        final tapped = <Map<String, Object?>>[];
        final h = Harness(
          onTraffic: (traffic) {
            if (traffic is! ChordTraffic) return;
            tapped.add(traffic.message);
            if (opened && traffic.message['method'] == 'session/new') {
              agent.cancel('s');
            }
          },
        );
        agent = h.open(async);
        opened = true;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .ignore();
        async.flushMicrotasks();
        expect(
          [for (final m in h.written.skip(1)) m['method']],
          ['session/new', 'session/cancel'],
        );
        expect(jsonEncode(h.written), jsonEncode(tapped));
      });
    });

    test('a close it calls lets the message it heard out first, and nothing '
        'after', () {
      fakeAsync((async) {
        late Agent agent;
        var opened = false;
        final h = Harness(
          onTraffic: (traffic) {
            if (opened &&
                traffic is ChordTraffic &&
                traffic.message['method'] == 'session/new') {
              agent.close();
            }
          },
        );
        agent = h.open(async);
        opened = true;
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .ignore();
        agent.cancel('s').ignore();
        async.elapse(const Duration(seconds: 3));
        expect(h.written.last['method'], 'session/new');
        expect(h.process.stdin.closedAt, h.process.stdin.bytes.length);
        expect(h.process.stdin.addsAfterClose, 0);
      });
    });
  });

  group('the in-memory cases no scenario plays', () {
    test('a permission withdrawn by \$/cancel_request: the bridge\'s token '
        'is cancelled and one cancelled answer goes out', () {
      fakeAsync((async) {
        final h = Harness();
        h.open(async);
        h.process.send(permission(5, 's'));
        async.flushMicrotasks();
        h.process.send({
          'jsonrpc': '2.0',
          'method': r'$/cancel_request',
          'params': {'requestId': 5},
        });
        async.flushMicrotasks();
        expect(h.asked.single.$2.isCancelled, isTrue);
        h.permissionAnswers.single.complete(
          RequestPermissionResponse.selected('allow'),
        );
        async.flushMicrotasks();
        expect(h.written.where((m) => m['id'] == 5), [
          {'jsonrpc': '2.0', 'id': 5, 'result': cancelledOutcome},
        ]);
      });
    });

    test('an update before session/new answers reaches the traffic first', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        agent
            .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
            .ignore();
        async.flushMicrotasks();
        h.process.send(
          update('s', {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'early'},
          }),
        );
        h.answer(h.lastRequest('session/new')['id'], {'sessionId': 's'});
        async.flushMicrotasks();
        expect(h.trafficKinds.sublist(h.trafficKinds.length - 2), [
          'agent agent_message_chunk',
          'agent result',
        ]);
      });
    });

    test('stdout closed without an exit fails waiting requests', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        Object? error;
        agent
            .prompt(
              PromptRequest(sessionId: 's', prompt: [ContentBlock.text('hi')]),
            )
            .then(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        h.process.closeStdout();
        async.elapse(const Duration(seconds: 1));
        expect(error, isA<AgentGone>());
        expect(h.process.exited, isFalse);
      });
    });
  });

  group('openAgent with a real child', () {
    const bounds = StopBounds(
      exit: Duration(milliseconds: 100),
      term: Duration(milliseconds: 300),
      kill: Duration(milliseconds: 2000),
    );

    Future<Agent> open(
      Object command, {
      CancellationToken? token,
      List<Traffic>? heard,
    }) => openAgent(
      command: command,
      cwd: Directory.systemTemp.path,
      onTraffic: heard?.add ?? (_) {},
      onPermission: (_, _) => Completer<RequestPermissionResponse>().future,
      cancellationToken: token,
      stop: bounds,
    );

    test('a program that is not an agent fails the open with its exit and '
        'last words, its stderr in the traffic', () async {
      final heard = <Traffic>[];
      await expectLater(
        open(['sh', '-c', 'echo "not an agent" >&2; exit 3'], heard: heard),
        throwsA(
          isA<AgentGone>()
              .having(
                (e) => e.message,
                'message',
                'The agent exited: not an agent',
              )
              .having((e) => e.exit, 'exit', const Exit(3)),
        ),
      );
      expect(
        heard.whereType<StderrTraffic>().map((t) => t.text).join(),
        'not an agent\n',
      );
      expect(
        heard.whereType<ChordTraffic>().single.message['method'],
        'initialize',
      );
    });

    test(
      'a missing program, a refused command line, a cancelled token',
      () async {
        await expectLater(
          open('chord-no-such-agent --acp'),
          throwsA(isA<CannotStart>()),
        );
        await expectLater(open('a && b'), throwsFormatException);
        await expectLater(
          open('sh', token: CancellationToken()..cancel()),
          throwsA(isA<CancelledException>()),
        );
      },
    );
  });

  group('tester: connection lifecycle boundaries', () {
    test('every stdout stderr exit permutation preserves the final error', () {
      for (final order in [
        ['stdout', 'stderr', 'exit'],
        ['stdout', 'exit', 'stderr'],
        ['stderr', 'stdout', 'exit'],
        ['stderr', 'exit', 'stdout'],
        ['exit', 'stdout', 'stderr'],
        ['exit', 'stderr', 'stdout'],
      ]) {
        fakeAsync((async) {
          final h = Harness();
          final agent = h.open(async);
          h.process.writeStderr('界👩‍💻e\u0301\n');
          Object? error;
          var settlements = 0;
          agent
              .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
              .then(
                (_) {
                  settlements++;
                },
                onError: (Object e) {
                  error = e;
                  settlements++;
                },
              );
          async.flushMicrotasks();
          for (final event in order) {
            switch (event) {
              case 'stdout':
                h.process.closeStdout();
              case 'stderr':
                h.process.closeStderr();
              case 'exit':
                h.process.exit(const Exit(2));
            }
            async.elapse(const Duration(milliseconds: 100));
          }
          async.elapse(const Duration(seconds: 2));
          expect(
            error,
            isA<AgentGone>()
                .having(
                  (e) => e.message,
                  'message',
                  'The agent exited: 界👩‍💻e\u0301',
                )
                .having((e) => e.exit, 'exit', const Exit(2)),
            reason: '$order',
          );
          expect(settlements, 1, reason: '$order');
          expect(agent.gone(), '界👩‍💻e\u0301');
        });
      }
    });

    test(
      'concurrent session prompts retain independent cancellation and results',
      () {
        fakeAsync((async) {
          final h = Harness();
          final agent = h.open(async);
          final token = CancellationToken();
          Object? firstError;
          PromptResponse? second;
          agent
              .prompt(
                PromptRequest(
                  sessionId: 'first',
                  prompt: [ContentBlock.text('one')],
                ),
                cancellationToken: token,
              )
              .then(
                (_) {},
                onError: (Object e) {
                  firstError = e;
                },
              );
          agent
              .prompt(
                PromptRequest(
                  sessionId: 'second',
                  prompt: [ContentBlock.text('two')],
                ),
              )
              .then((value) {
                second = value;
              });
          async.flushMicrotasks();
          final requests = h.written
              .where((m) => m['method'] == 'session/prompt')
              .toList();
          token.cancel();
          async.flushMicrotasks();
          h.answer(requests[0]['id'], {'stopReason': 'end_turn'});
          h.answer(requests[1]['id'], {'stopReason': 'future_reason'});
          async.flushMicrotasks();
          expect(firstError, isA<CancelledException>());
          expect(second!.stopReason, 'future_reason');
          expect(
            h.written
                .where((m) => m['method'] == 'session/cancel')
                .single['params'],
            {'sessionId': 'first'},
          );
          expect(token.hasCancellables, isFalse);
        });
      },
    );

    test(
      'a thousand early updates precede the reply despite throwing subscribers',
      () {
        fakeAsync((async) {
          final heard = <Traffic>[];
          final h = Harness(
            onTraffic: (traffic) {
              heard.add(traffic);
              if (heard.length % 7 == 0) throw StateError('subscriber');
            },
          );
          final agent = h.open(async);
          var updatesAtAnswer = -1;
          agent
              .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
              .then((_) {
                updatesAtAnswer = heard
                    .whereType<AgentTraffic>()
                    .where((t) => t.message['method'] == 'session/update')
                    .length;
              });
          async.flushMicrotasks();
          final messages = [
            for (var i = 0; i < 1000; i++)
              update('s', {
                'sessionUpdate': 'future_update',
                'index': i,
                'content': {'type': 'text', 'text': '界👩‍💻e\u0301\u001b[31m'},
              }),
            {
              'jsonrpc': '2.0',
              'id': h.lastRequest('session/new')['id'],
              'result': {'sessionId': 's'},
            },
          ];
          h.process.writeStdout(
            utf8.encode('${messages.map(jsonEncode).join('\n')}\n'),
          );
          async.flushMicrotasks();
          expect(updatesAtAnswer, 1000);
          final updates = heard
              .whereType<AgentTraffic>()
              .where((t) => t.message['method'] == 'session/update')
              .toList();
          expect([
            for (final t in updates)
              ((t.message['params'] as Map)['update'] as Map)['index'],
          ], List.generate(1000, (i) => i));
        });
      },
    );

    test(
      'cancel then close drains both sessions fallbacks behind a held flush',
      () {
        fakeAsync((async) {
          final h = Harness();
          final agent = h.open(async);
          h.process.stdin.hold = true;
          agent
              .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
              .ignore();
          async.flushMicrotasks();
          h.process.send(permission(10, 'first'));
          h.process.send(permission(11, 'second'));
          async.flushMicrotasks();
          agent.cancel('first');
          final closing = agent.close();
          expect(identical(closing, agent.close()), isTrue);
          expect(h.asked.every((request) => request.$2.isCancelled), isTrue);
          for (final answer in h.permissionAnswers) {
            answer.complete(RequestPermissionResponse.selected('allow'));
          }
          h.process.stdin.release();
          async.elapse(const Duration(seconds: 5));
          expect(h.written.sublist(2), [
            {
              'jsonrpc': '2.0',
              'method': 'session/cancel',
              'params': {'sessionId': 'first'},
            },
            {'jsonrpc': '2.0', 'id': 10, 'result': cancelledOutcome},
            {'jsonrpc': '2.0', 'id': 11, 'result': cancelledOutcome},
          ]);
          expect(h.process.stdin.closedAt, h.process.stdin.bytes.length);
          expect(h.process.stdin.addsWhileFlushing, 0);
          expect(h.process.stdin.addsAfterClose, 0);
        });
      },
    );

    test('a synchronous sink flush failure terminally fails the writer', () {
      final input = _TesterFailingFlush();
      var failures = 0;
      final writer = Writer(input, TrafficTap((_) {}), () {
        failures++;
      });
      expect(() => writer.enqueue({'method': 'x'}), returnsNormally);
      expect(writer.failed, isTrue);
      expect(writer.open, isFalse);
      expect(failures, 1);
      expect(writer.enqueue({'method': 'late'}), isFalse);
    });

    test('a synchronous sink add failure terminally fails the writer', () {
      final input = _TesterFailingAdd();
      var failures = 0;
      final writer = Writer(input, TrafficTap((_) {}), () {
        failures++;
      });
      expect(() => writer.enqueue({'method': 'x'}), returnsNormally);
      expect(writer.failed, isTrue);
      expect(writer.open, isFalse);
      expect(failures, 1);
      expect(writer.enqueue({'method': 'late'}), isFalse);
    });
  });
}

/// A process whose launcher said ok and whose exec then failed.
class _FailedExec implements AgentProcess {
  _FailedExec(this._process, this.status);

  final MemoryAgentProcess _process;

  @override
  final Future<Exit> status;

  @override
  int get pid => _process.pid;
  @override
  AgentInput get stdin => _process.stdin;
  @override
  Stream<List<int>> get stdout => _process.stdout;
  @override
  String stderrTail() => _process.stderrTail();
  @override
  Tail stderrEnd() => _process.stderrEnd();
  @override
  Future<String> lastWords() => _process.lastWords();
  @override
  Future<void> stop([StopBounds bounds = const StopBounds()]) async {
    _process.stdin.end();
  }
}

class _TesterFailingAdd implements AgentInput {
  final _done = Completer<void>();

  @override
  void add(List<int> bytes) => throw const SocketException('Broken pipe');

  @override
  Future<void> flush() async {}

  @override
  void end() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

class _TesterFailingFlush extends _TesterFailingAdd {
  @override
  void add(List<int> bytes) {}

  @override
  Future<void> flush() => throw const SocketException('Broken pipe');
}
