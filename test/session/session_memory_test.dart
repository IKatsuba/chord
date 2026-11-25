// A session over an agent in memory, its bytes exact, for what no scenario
// of the fake agent plays: updates before the session's answer or for
// another session, an exit between turns, requests around a cancel, and a
// failed prompt's code.
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permissions.dart';
import 'package:chord/session/models.dart';
import 'package:chord/session/modes.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/start_failure.dart' as startup;
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

/// An agent in memory, opened as a session's agent.
final class _Memory {
  _Memory() {
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
  }

  late final MemoryAgentProcess process;
  final traffic = <Traffic>[];

  List<Map<String, Object?>> get written => process.stdin.messages;

  Map<String, Object?> last(String method) =>
      written.lastWhere((m) => m['method'] == method);

  void answer(Object? id, Map<String, Object?> result) =>
      process.send({'jsonrpc': '2.0', 'id': id, 'result': result});

  void update(String sessionId, Map<String, Object?> update) => process.send({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {'sessionId': sessionId, 'update': update},
  });

  SessionOpener get open =>
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
      );

  /// Opens the session, under fake time; [early] runs before `session/new`
  /// is answered.
  Session openIn(
    FakeAsync async, {
    void Function()? early,
    Map<String, Object?>? answerJson,
  }) {
    Session? session;
    openSession(
      agent: 'memory',
      command: 'memory',
      cwd: '/w',
      open: open,
      onTraffic: traffic.add,
    ).then((s) => session = s);
    async.flushMicrotasks();
    answer(last('initialize')['id'], {'protocolVersion': 1});
    async.flushMicrotasks();
    early?.call();
    async.flushMicrotasks();
    answer(
      last('session/new')['id'],
      answerJson ??
          {
            'sessionId': 's1',
            'configOptions': [
              {
                'id': 'mode',
                'type': 'select',
                'category': 'mode',
                'currentValue': 'default',
              },
            ],
          },
    );
    async.flushMicrotasks();
    return session!;
  }

  void close(FakeAsync async, Session session) {
    session.close();
    async.elapse(const Duration(seconds: 5));
  }
}

Map<String, Object?> _say(String text) => {
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
};

String _text(acp.SessionUpdate update) =>
    (update.toJson()['content'] as Map)['text'] as String;

Map<String, Object?> _permission(Object id) => {
  'jsonrpc': '2.0',
  'id': id,
  'method': 'session/request_permission',
  'params': {
    'sessionId': 's1',
    'toolCall': {'toolCallId': 'write-3', 'title': 'Write notes.txt'},
    'options': [
      {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
      {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
    ],
  },
};

void main() {
  test('legacy model ACK updates the current model without an update', () {
    fakeAsync((async) {
      final m = _Memory();
      final session = m.openIn(
        async,
        answerJson: {
          'sessionId': 's1',
          'models': {
            'currentModelId': 'old',
            'availableModels': [
              {'modelId': 'old', 'name': 'Old'},
              {'modelId': 'new', 'name': 'New'},
            ],
          },
          'modes': {
            'currentModeId': 'default',
            'availableModes': [
              {'id': 'default', 'name': 'Default'},
              {'id': 'plan', 'name': 'Plan'},
            ],
          },
        },
      );
      session.setModel('new');
      async.flushMicrotasks();
      expect(m.last('session/set_model')['params'], {
        'sessionId': 's1',
        'modelId': 'new',
      });
      m.answer(m.last('session/set_model')['id'], {});
      async.flushMicrotasks();
      expect(
        modelsFrom(session.state.configOptions, session.state.models)?.current,
        'new',
      );
      session.setMode('plan');
      async.flushMicrotasks();
      expect(m.last('session/set_mode')['params'], {
        'sessionId': 's1',
        'modeId': 'plan',
      });
      m.answer(m.last('session/set_mode')['id'], {});
      async.flushMicrotasks();
      expect(
        modesFrom(session.state.configOptions, session.state.modes)?.current,
        'plan',
      );
      m.close(async, session);
    });
  });

  test('config acknowledgement preserves raw metadata and agent numbers', () {
    fakeAsync((async) {
      final m = _Memory();
      final session = m.openIn(async);
      session.setOption('effort', 'high');
      async.flushMicrotasks();
      expect(m.last('session/set_config_option')['params'], {
        'sessionId': 's1',
        'configId': 'effort',
        'value': 'high',
      });
      m.answer(m.last('session/set_config_option')['id'], {
        'configOptions': [
          {
            'id': 'effort',
            'type': 'select',
            'currentValue': 'high',
            '_meta': {'agentNumber': 1.5},
          },
        ],
      });
      async.flushMicrotasks();
      expect(session.state.configOptions.single['_meta'], {'agentNumber': 1.5});
      m.close(async, session);
    });
  });

  test('an update before session/new answers reaches the first subscriber, '
      "and a mode in it overrides the answer's", () {
    fakeAsync((async) {
      final m = _Memory();
      final session = m.openIn(
        async,
        early: () {
          m.update('s1', _say('early'));
          m.update('s1', {
            'sessionUpdate': 'current_mode_update',
            'currentModeId': 'plan',
          });
        },
      );
      final heard = <String>[];

      session.subscribe((u) => heard.add(u.kind));

      expect(heard, ['agent_message_chunk', 'current_mode_update']);
      expect(session.id, 's1');
      expect(session.state.configOptions.single['currentValue'], 'plan');
      m.close(async, session);
    });
  });

  test("the agent's env carries chord's own over the registry's", () {
    fakeAsync((async) {
      Map<String, String>? given;
      final m = _Memory();
      Session? session;

      openSession(
        agent: 'memory',
        command: 'memory',
        env: {'FROM_REGISTRY': '1'},
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
            }) {
              given = env;
              return m.open(
                command: command,
                cwd: cwd,
                onTraffic: onTraffic,
                onPermission: onPermission,
                relay: relay,
              );
            },
      ).then((s) => session = s);
      async.flushMicrotasks();
      m.answer(m.last('initialize')['id'], {'protocolVersion': 1});
      async.flushMicrotasks();
      m.answer(m.last('session/new')['id'], {'sessionId': 's1'});
      async.flushMicrotasks();

      expect(given, {'FROM_REGISTRY': '1', ...agentEnv(Platform.environment)});
      expect(m.last('session/new')['params'], {
        'cwd': '/w',
        'mcpServers': <Object?>[],
      });
      m.close(async, session!);
    });
  });

  test('an update for another session is dropped', () {
    fakeAsync((async) {
      final m = _Memory();
      final session = m.openIn(async);
      final heard = <String>[];

      session.subscribe((u) => heard.add(_text(u)));
      m.update('s2', _say('not ours'));
      m.update('s1', _say('ours'));
      async.flushMicrotasks();

      expect(heard, ['ours']);
      // The hook beside the ingress still hears every crossing.
      expect(
        m.traffic.whereType<AgentTraffic>().where(
          (t) => t.message['method'] == 'session/update',
        ),
        hasLength(2),
      );
      m.close(async, session);
    });
  });

  test("a prompt's answer gives its stop reason, and a JSON-RPC error its "
      'message and code', () {
    fakeAsync((async) {
      final m = _Memory();
      final session = m.openIn(async);
      final results = <TurnResult>[];

      session.prompt('one').result.then(results.add);
      async.flushMicrotasks();
      expect(m.last('session/prompt')['params'], {
        'sessionId': 's1',
        'prompt': [
          {'type': 'text', 'text': 'one'},
        ],
      });
      m.answer(m.last('session/prompt')['id'], {'stopReason': 'max_tokens'});
      async.flushMicrotasks();

      session.prompt('two').result.then(results.add);
      async.flushMicrotasks();
      m.process.send({
        'jsonrpc': '2.0',
        'id': m.last('session/prompt')['id'],
        'error': {'code': -32603, 'message': 'Internal error'},
      });
      async.flushMicrotasks();

      expect((results[0] as TurnAnswered).stopReason, 'max_tokens');
      expect(
        [(results[1] as TurnFailed).message, (results[1] as TurnFailed).code],
        ['Internal error', -32603],
      );
      m.close(async, session);
    });
  });

  test('an answer with no stop reason, or one that is no string, fails the '
      'turn, and the next turn is answered', () {
    fakeAsync((async) {
      final m = _Memory();
      final session = m.openIn(async);
      final results = <TurnResult>[];

      for (final answer in <Map<String, Object?>>[
        {},
        {'stopReason': 7},
        {'stopReason': 'end_turn'},
      ]) {
        session.prompt('p').result.then(results.add);
        async.flushMicrotasks();
        m.answer(m.last('session/prompt')['id'], answer);
        async.flushMicrotasks();
      }

      expect(
        [for (final r in results) r.runtimeType],
        [TurnFailed, TurnFailed, TurnAnswered],
      );
      expect(
        (results[0] as TurnFailed).message,
        'The agent answered session/prompt with {}.',
      );
      expect(
        (results[1] as TurnFailed).message,
        'The agent answered session/prompt with {stopReason: 7}.',
      );
      m.close(async, session);
    });
  });

  test('a session/new answer with no session id fails the open and stops '
      'the agent', () {
    for (final answer in <Map<String, Object?>>[
      {},
      {'sessionId': 7},
    ]) {
      fakeAsync((async) {
        final m = _Memory();
        Object? failed;

        openSession(
          agent: 'memory',
          command: 'memory',
          cwd: '/w',
          open: m.open,
        ).then(
          (_) {},
          onError: (Object error) {
            failed = error;
          },
        );
        async.flushMicrotasks();
        m.answer(m.last('initialize')['id'], {'protocolVersion': 1});
        async.flushMicrotasks();
        m.answer(m.last('session/new')['id'], answer);
        async.elapse(const Duration(seconds: 5));

        expect(
          failed,
          isA<startup.StartFailed>()
              .having(
                (error) => error.failure.step,
                'failed startup step',
                startup.StartStep.newSession,
              )
              .having(
                (error) => error.cause,
                'original cause',
                isA<TypeError>(),
              ),
          reason: '$answer',
        );
        expect(m.process.stdin.ended, isTrue);
        expect(m.process.exited, isTrue);
      });
    }
  });

  test('an exit between turns settles exited and gone, and the next prompt '
      'fails with the last words', () {
    fakeAsync((async) {
      final m = _Memory();
      final session = m.openIn(async);
      var exited = false;

      session.exited.then((_) => exited = true);
      m.process.writeStderr('bye\n');
      m.process.closeStderr();
      m.process.closeStdout();
      m.process.exit(const Exit(1));
      async.elapse(const Duration(seconds: 1));

      expect(exited, isTrue);
      expect(session.gone(), 'bye');

      TurnResult? result;

      session.prompt('again').result.then((r) => result = r);
      async.elapse(const Duration(seconds: 1));

      expect((result as TurnFailed).message, 'The agent exited: bye');
      m.close(async, session);
    });
  });

  test('with a permission waiting, a cancel sends session/cancel, then '
      'answers it cancelled, and withdraws it', () {
    fakeAsync((async) {
      final m = _Memory();
      final session = m.openIn(async);
      final asked = <PendingPermission>[];

      session.permissions.subscribe(asked.add);
      session.prompt('p').result.ignore();
      async.flushMicrotasks();
      m.process.send(_permission(7));
      async.flushMicrotasks();

      expect(asked, hasLength(1));
      expect(waitFor(asked.single).title, 'Write notes.txt');

      session.cancel();
      async.flushMicrotasks();

      // ACP's order: the cancel, then the answers to what was asked.
      final tail = m.written
          .skipWhile((w) => w['method'] != 'session/cancel')
          .toList();

      expect(tail.first['params'], {'sessionId': 's1'});
      expect(tail[1]['id'], 7);
      expect(tail[1]['result'], {
        'outcome': {'outcome': 'cancelled'},
      });
      expect(asked.single.withdrawn.isCancelled, isTrue);
      expect(session.permissions.pending(), isEmpty);
      m.close(async, session);
    });
  });

  test('a request after session/cancel went still reaches the person, and '
      'is answered as they say', () {
    fakeAsync((async) {
      final m = _Memory();
      final session = m.openIn(async);
      final asked = <PendingPermission>[];

      session.permissions.subscribe(asked.add);
      session.prompt('p').result.ignore();
      async.flushMicrotasks();
      session.cancel();
      async.flushMicrotasks();
      m.process.send(_permission(8));
      async.flushMicrotasks();

      expect(asked, hasLength(1));
      asked.single.reject();
      async.flushMicrotasks();

      expect(m.written.lastWhere((w) => w['id'] == 8)['result'], {
        'outcome': {'outcome': 'selected', 'optionId': 'deny'},
      });
      m.close(async, session);
    });
  });

  test('closing withdraws what waits on the person, answered cancelled', () {
    fakeAsync((async) {
      final m = _Memory();
      final session = m.openIn(async);
      final asked = <PendingPermission>[];

      session.permissions.subscribe(asked.add);
      m.process.send(_permission(9));
      async.flushMicrotasks();
      m.close(async, session);

      expect(asked.single.withdrawn.isCancelled, isTrue);
      expect(m.written.lastWhere((w) => w['id'] == 9)['result'], {
        'outcome': {'outcome': 'cancelled'},
      });
      // A second close is the first.
      expect(identical(session.close(), session.close()), isTrue);
    });
  });

  group('tester: session lifecycle boundaries', () {
    test('repeated cancel keeps the prompt waiting for the agent answer', () {
      fakeAsync((async) {
        final m = _Memory();
        final session = m.openIn(async);
        TurnResult? result;
        final turn = session.prompt('界 e\u0301 👩‍💻\x1b[31m');
        turn.result.then((r) => result = r);
        async.flushMicrotasks();
        final requestId = m.last('session/prompt')['id'];
        turn.cancel();
        session.cancel();
        async.flushMicrotasks();
        expect(result, isNull);
        expect(
          m.written.where((w) => w['method'] == 'session/cancel'),
          hasLength(2),
        );
        m.update('s1', _say('late after cancel'));
        m.answer(requestId, {'stopReason': 'cancelled'});
        async.flushMicrotasks();
        expect((result as TurnAnswered).cancelled, isTrue);
        final heard = <String>[];
        session.subscribe((u) => heard.add(_text(u)));
        expect(heard, ['late after cancel']);
        final next = session.prompt('next');
        expect(next.id, isNot(turn.id));
        next.result.then((r) => result = r);
        async.flushMicrotasks();
        m.answer(m.last('session/prompt')['id'], {'stopReason': 'future_stop'});
        async.flushMicrotasks();
        expect((result as TurnAnswered).stopReason, 'future_stop');
        m.close(async, session);
      });
    });

    test('after close a prompt fails without new bytes or update delivery', () {
      fakeAsync((async) {
        final m = _Memory();
        final session = m.openIn(async);
        final heard = <String>[];
        session.subscribe((u) => heard.add(_text(u)));
        m.close(async, session);
        final written = m.written.length;
        TurnResult? result;
        session.prompt('after close').result.then((r) => result = r);
        async.flushMicrotasks();
        expect(result, isA<TurnFailed>());
        expect(m.written, hasLength(written));
        expect(m.process.stdin.addsAfterClose, 0);
        expect(heard, isEmpty);
        expect(session.permissions.pending(), isEmpty);
        expect(identical(session.close(), session.close()), isTrue);
      });
    });
  });
}
