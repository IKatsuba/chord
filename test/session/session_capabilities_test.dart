// What a session reads of its agent's initialize answer, over an agent in
// memory whose answer the test writes.
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/session/auth_status.dart';
import 'package:chord/session/session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

/// An agent in memory that answers initialize with [init] and opens one
/// session; the session it gives, and the agent.
(Session, MemoryAgentProcess) opened(
  FakeAsync async,
  Map<String, Object?> init,
) {
  late final MemoryAgentProcess process;
  process = MemoryAgentProcess(
    onSignal: (signal) {
      process.exit(
        signal == ProcessSignal.sigterm
            ? const Exit(143, 'SIGTERM')
            : const Exit(137, 'SIGKILL'),
      );
      process.closeStdout();
      process.closeStderr();
    },
  );
  Map<String, Object?> last(String method) =>
      process.stdin.messages.lastWhere((m) => m['method'] == method);
  void answer(Object? id, Map<String, Object?> result) =>
      process.send({'jsonrpc': '2.0', 'id': id, 'result': result});
  Session? session;
  openSession(
    agent: 'memory',
    command: 'memory',
    cwd: '/w',
    open:
        ({
          required command,
          env,
          required cwd,
          required onTraffic,
          required onPermission,
          relay,
          cancellationToken,
        }) => connectAgent(
          process,
          onTraffic: onTraffic,
          onPermission: onPermission,
          relay: relay,
          cancellationToken: cancellationToken,
        ),
  ).then((s) => session = s);
  async.flushMicrotasks();
  answer(last('initialize')['id'], {'protocolVersion': 1, ...init});
  async.flushMicrotasks();
  answer(last('session/new')['id'], {'sessionId': 's1'});
  async.flushMicrotasks();
  return (session!, process);
}

void main() {
  group('titles', () {
    for (final (title, takes) in <(Object?, bool)>[
      (<String, Object?>{}, true),
      (
        {
          '_meta': {'x': 1},
        },
        true,
      ),
      (true, true),
      ('yes', true),
      (<Object?>[], true),
      (null, false),
      (false, false),
      (0, false),
      ('', false),
    ]) {
      test('a title marker of $title ${takes ? 'is' : 'is not'} one, as the '
          'original reads it: JavaScript\'s truthiness', () {
        fakeAsync((async) {
          final (session, _) = opened(async, {
            'agentCapabilities': {
              'sessionCapabilities': {'title': title},
            },
          });
          expect(session.takesTitles(), takes);
          session.close();
          async.elapse(const Duration(seconds: 7));
        });
      });
    }

    for (final init in <Map<String, Object?>>[
      {},
      {'agentCapabilities': <String, Object?>{}},
      {'agentCapabilities': 3},
      {
        'agentCapabilities': {'sessionCapabilities': 'title'},
      },
    ]) {
      test('$init takes no title', () {
        fakeAsync((async) {
          final (session, _) = opened(async, init);
          expect(session.takesTitles(), isFalse);
          session.close();
          async.elapse(const Duration(seconds: 7));
        });
      });
    }
  });

  group('the account', () {
    const advertised = {
      'agentCapabilities': {
        'auth': {'status': <String, Object?>{}},
      },
    };
    const signedIn = {'state': 'authenticated'};
    const apiKey = {
      'state': 'authenticated',
      'accounts': [
        {'label': 'Anthropic API key'},
      ],
    };
    Iterable<Map<String, Object?>> asks(MemoryAgentProcess process) =>
        process.stdin.messages.where((m) => m['method'] == 'auth/status');
    void push(MemoryAgentProcess process, Map<String, Object?> status) =>
        process.send({
          'jsonrpc': '2.0',
          'method': 'auth/status_update',
          'params': status,
        });

    test('an agent that advertises auth.status is asked beside session/new, '
        'and its answer heard', () {
      fakeAsync((async) {
        final (session, process) = opened(async, advertised);
        expect(session.account, isA<AccountPending>());
        final heard = <AccountState>[];
        session.subscribeAccount(heard.add);
        process.send({
          'jsonrpc': '2.0',
          'id': asks(process).single['id'],
          'result': signedIn,
        });
        async.flushMicrotasks();
        expect((session.account as AccountHeard).status, signedIn);
        expect(heard, hasLength(1));
        push(process, apiKey);
        async.flushMicrotasks();
        expect((session.account as AccountHeard).status, apiKey);
        expect(heard, hasLength(2));
        session.close();
        async.elapse(const Duration(seconds: 7));
      });
    });

    test('a push heard before the answer wins over it', () {
      fakeAsync((async) {
        final (session, process) = opened(async, advertised);
        push(process, apiKey);
        async.flushMicrotasks();
        process.send({
          'jsonrpc': '2.0',
          'id': asks(process).single['id'],
          'result': signedIn,
        });
        async.flushMicrotasks();
        expect((session.account as AccountHeard).status, apiKey);
        session.close();
        async.elapse(const Duration(seconds: 7));
      });
    });

    test('a failed ask is failed until a push', () {
      fakeAsync((async) {
        final (session, process) = opened(async, advertised);
        process.send({
          'jsonrpc': '2.0',
          'id': asks(process).single['id'],
          'error': {'code': -32603, 'message': 'cannot tell'},
        });
        async.flushMicrotasks();
        expect(session.account, isA<AccountFailed>());
        push(process, signedIn);
        async.flushMicrotasks();
        expect((session.account as AccountHeard).status, signedIn);
        session.close();
        async.elapse(const Duration(seconds: 7));
      });
    });

    for (final status in <Object?>[true, 'yes', <Object?>[]]) {
      test('a status marker of $status is truthy, so it is asked', () {
        fakeAsync((async) {
          final (session, process) = opened(async, {
            'agentCapabilities': {
              'auth': {'status': status},
            },
          });
          expect(asks(process), hasLength(1));
          expect(session.account, isA<AccountPending>());
          session.close();
          async.elapse(const Duration(seconds: 7));
        });
      });
    }

    for (final status in <Object?>[null, false, 0, '']) {
      test('a status marker of $status asks nothing, though pushes are '
          'heard', () {
        fakeAsync((async) {
          final (session, process) = opened(async, {
            'agentCapabilities': {
              'auth': {'status': status},
            },
          });
          expect(asks(process), isEmpty);
          expect(session.account, isA<AccountNone>());
          push(process, signedIn);
          async.flushMicrotasks();
          expect((session.account as AccountHeard).status, signedIn);
          session.close();
          async.elapse(const Duration(seconds: 7));
        });
      });
    }
  });
  group('tester U7 account boundaries', () {
    const advertised = {
      'agentCapabilities': {
        'auth': {'status': <String, Object?>{}},
      },
    };
    void push(MemoryAgentProcess process, Map<String, Object?> status) =>
        process.send({
          'jsonrpc': '2.0',
          'method': 'auth/status_update',
          'params': status,
        });
    Object? askedId(MemoryAgentProcess process) => process.stdin.messages
        .lastWhere((m) => m['method'] == 'auth/status')['id'];

    test(
      'a thousand pushes win over a late failed ask without altering the last status',
      () {
        fakeAsync((async) {
          final (session, process) = opened(async, advertised);
          final heard = <AccountState>[];
          final stop = session.subscribeAccount(heard.add);
          for (var i = 0; i < 1000; i++) {
            push(process, {
              'state': 'authenticated',
              '_meta': {'sequence': i},
            });
          }
          async.flushMicrotasks();
          expect(heard, hasLength(1000));
          final last = session.account;
          process.send({
            'jsonrpc': '2.0',
            'id': askedId(process),
            'error': {'code': -32603, 'message': 'late refusal'},
          });
          async.flushMicrotasks();
          expect(identical(session.account, last), isTrue);
          expect(heard, hasLength(1000));
          expect((session.account as AccountHeard).status['_meta'], {
            'sequence': 999,
          });
          stop();
          session.close();
          async.elapse(const Duration(seconds: 7));
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'unsubscribe and closing one pending session leave another account live',
      () {
        fakeAsync((async) {
          final (first, firstProcess) = opened(async, advertised);
          final (second, secondProcess) = opened(async, advertised);
          final heard = <AccountState>[];
          final stop = first.subscribeAccount(heard.add);
          stop();
          stop();
          first.close();
          async.elapse(const Duration(seconds: 7));
          expect(heard, isEmpty);
          expect(second.account, isA<AccountPending>());
          push(secondProcess, {
            'state': 'authenticated',
            'accounts': [
              {'label': 'second'},
            ],
          });
          async.flushMicrotasks();
          expect((second.account as AccountHeard).status['accounts'], [
            {'label': 'second'},
          ]);
          secondProcess.send({
            'jsonrpc': '2.0',
            'id': askedId(secondProcess),
            'result': {'state': 'unauthenticated'},
          });
          async.flushMicrotasks();
          expect(
            (second.account as AccountHeard).status['state'],
            'authenticated',
          );
          expect(firstProcess.signals, isNotEmpty);
          second.close();
          async.elapse(const Duration(seconds: 7));
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'a push before initialize is heard even without an advertised account',
      () {
        fakeAsync((async) {
          late MemoryAgentProcess process;
          process = MemoryAgentProcess(
            onSignal: (_) {
              process.exit(const Exit(143, 'SIGTERM'));
              process.closeStdout();
              process.closeStderr();
            },
          );
          Session? session;
          openSession(
            agent: 'memory',
            command: 'memory',
            cwd: '/w',
            open:
                ({
                  required command,
                  env,
                  required cwd,
                  required onTraffic,
                  required onPermission,
                  relay,
                  cancellationToken,
                }) => connectAgent(
                  process,
                  onTraffic: onTraffic,
                  onPermission: onPermission,
                  relay: relay,
                  cancellationToken: cancellationToken,
                ),
          ).then((value) => session = value);
          async.flushMicrotasks();
          push(process, {
            'state': 'authenticated',
            'accounts': [
              {'label': 'early'},
            ],
          });
          final init = process.stdin.messages.lastWhere(
            (m) => m['method'] == 'initialize',
          );
          process.send({
            'jsonrpc': '2.0',
            'id': init['id'],
            'result': {'protocolVersion': 1},
          });
          async.flushMicrotasks();
          final opening = process.stdin.messages.lastWhere(
            (m) => m['method'] == 'session/new',
          );
          process.send({
            'jsonrpc': '2.0',
            'id': opening['id'],
            'result': {'sessionId': 's1'},
          });
          async.flushMicrotasks();
          expect((session!.account as AccountHeard).status['accounts'], [
            {'label': 'early'},
          ]);
          expect(
            process.stdin.messages.where((m) => m['method'] == 'auth/status'),
            isEmpty,
          );
          session!.close();
          async.elapse(const Duration(seconds: 7));
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );
  });
}
