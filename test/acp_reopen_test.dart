// chord acp's session/load and session/resume in memory: claims, refusals,
// the past ahead of the answer through the gate, and a resume that replays
// nothing.
import 'dart:async';
import 'dart:io';

import 'package:chord/session/place.dart';

import 'package:chord/acp/process.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/sessions.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';

List<Map<String, Object?>> _asked(MemoryAgentProcess agent, String method) => [
  for (final message in agent.stdin.messages)
    if (message['method'] == method && message.containsKey('id')) message,
];

Map<String, Object?> _chunk(String kind, String text) => {
  'sessionUpdate': kind,
  'content': {'type': 'text', 'text': text},
};

SessionRecord _record(
  String id, {
  String agent = 'memory',
  String cwd = '/w',
}) => SessionRecord(
  path: '/state/sessions/$id.jsonl',
  sessionId: id,
  agent: agent,
  cwd: cwd,
  prompt: 'Old',
  lastUsedAt: 0,
);

void main() {
  Map<String, Object?> reopen(String id, {String cwd = '/w'}) => {
    'sessionId': id,
    'cwd': cwd,
    'mcpServers': <Object?>[],
  };

  group('refused', () {
    test('a live id, or one a load is still opening, is already open here', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..init = {
            'protocolVersion': 1,
            'agentCapabilities': {'loadSession': true},
          }
          ..answerReopen = false;
        rig.initialize();
        final live = rig.newSession();
        for (final method in ['session/load', 'session/resume']) {
          expect(rig.answer(rig.request(method, reopen(live)))!['error'], {
            'code': -32602,
            'message': 'Invalid params: Session $live is already open here.',
          });
        }
        final first = rig.request('session/load', reopen('x'));
        expect(rig.answer(first), isNull);
        expect(
          rig.answer(rig.request('session/resume', reopen('x')))!['error'],
          {
            'code': -32602,
            'message': 'Invalid params: Session x is already open here.',
          },
        );
        // Only the first started an agent.
        expect(rig.agents, hasLength(2));
        rig.eof();
      });
    });

    test('a record of another agent, or one in another directory, is '
        '-32602, and no agent starts', () {
      fakeAsync((async) {
        final rig = Rig(
          async,
          records: () async => [
            _record('theirs', agent: 'other'),
            _record('there', cwd: '/elsewhere'),
          ],
        );
        rig.initialize();
        expect(
          rig.answer(rig.request('session/load', reopen('theirs')))!['error'],
          {
            'code': -32602,
            'message':
                'Invalid params: Session theirs belongs to another agent '
                '(other).',
          },
        );
        expect(
          rig.answer(rig.request('session/resume', reopen('there')))!['error'],
          {
            'code': -32602,
            'message': 'Invalid params: Session there is in /elsewhere.',
          },
        );
        expect(rig.agents, isEmpty);
        // The claims are let go: the same ids may be asked again.
        expect(rig.host.reopening, isEmpty);
        rig.eof();
      });
    });

    test('a way out begun while the records are read refuses it: -32603 '
        'chord is closing, no agent started, the claim let go', () {
      fakeAsync((async) {
        final records = Completer<List<SessionRecord>>();
        final rig = Rig(async, records: () => records.future);
        rig.initialize();
        final id = rig.request('session/load', reopen('x'));
        expect(rig.host.reopening, {'x'});
        rig.host.leave(const LeaveEof()).ignore();
        records.complete(const []);
        rig.settle();
        // Whether its answer reaches the client before the way out closes
        // the connection, it is the refusal, and no agent started.
        if (rig.answer(id) case final answer?) {
          expect(answer['error'], {
            'code': -32603,
            'message': 'chord is closing',
          });
        }
        expect(rig.agents, isEmpty);
        expect(rig.host.reopening, isEmpty);
        async.elapse(const Duration(seconds: 20));
      });
    });
  });

  test('a load of an id chord never recorded goes to the agent unchanged; '
      'what it replays goes ahead of the answer, through the gate, with no '
      'state, and the answer names no session', () {
    fakeAsync((async) {
      final rig = Rig(async)
        ..init = {
          'protocolVersion': 1,
          'agentCapabilities': {'loadSession': true},
        }
        ..replay = [
          _chunk('user_message_chunk', 'Hi'),
          _chunk('agent_message_chunk', 'Hello'),
          {'sessionUpdate': 'current_mode_update', 'currentModeId': 'code'},
          {'sessionUpdate': 'notice', 'level': 'info', 'message': 'n'},
        ];
      // No notices declared: the notice is dropped, as live.
      rig.initialize();
      final id = rig.request('session/load', reopen('x'));
      final agent = rig.agents.single;
      expect(_asked(agent, 'session/load').single['params'], {
        'sessionId': 'x',
        'cwd': '/w',
        'mcpServers': <Object?>[],
      });
      final said = [
        for (final m in rig.lines.messages)
          if (m['id'] == id)
            'answer'
          else if (m['method'] == 'session/update')
            ((m['params'] as Map)['update'] as Map)['sessionUpdate']
          else if (m['method'] case final String method)
            method,
      ];
      expect(said.takeWhile((s) => s != 'answer'), [
        'user_message_chunk',
        'agent_message_chunk',
      ]);
      expect(said, contains('answer'));
      for (final n in rig.notified('session/update')) {
        expect(n['sessionId'], 'x');
      }
      final answer = rig.answer(id)!['result'] as Map;
      expect(answer.containsKey('sessionId'), isFalse);
      expect(answer['configOptions'], isA<List<Object?>>());
      expect(rig.host.sessions.keys, ['x']);
      expect(rig.host.reopening, isEmpty);
      // The session is the client's to prompt under the id it asked for.
      final prompt = rig.request('session/prompt', {
        'sessionId': 'x',
        'prompt': [
          {'type': 'text', 'text': 'go'},
        ],
      });
      final asked = _asked(agent, 'session/prompt').single;
      expect((asked['params'] as Map)['sessionId'], 'x');
      agent.send({
        'jsonrpc': '2.0',
        'id': asked['id'],
        'result': {'stopReason': 'end_turn'},
      });
      rig.settle();
      async.elapse(const Duration(seconds: 1));
      rig.settle();
      expect(rig.answer(prompt)!['result'], {'stopReason': 'end_turn'});
      rig.eof();
    });
  });

  test('a resume replays nothing and answers with no session id', () {
    fakeAsync((async) {
      final rig = Rig(async)
        ..init = {
          'protocolVersion': 1,
          'agentCapabilities': {
            'sessionCapabilities': {'resume': <String, Object?>{}},
          },
        }
        ..replay = [_chunk('agent_message_chunk', 'never')];
      rig.initialize();
      final id = rig.request('session/resume', reopen('x'));
      final agent = rig.agents.single;
      expect(_asked(agent, 'session/resume'), hasLength(1));
      expect(_asked(agent, 'session/load'), isEmpty);
      final answer = rig.answer(id)!['result'] as Map;
      expect(answer.containsKey('sessionId'), isFalse);
      expect(
        rig
            .notified('session/update')
            .where(
              (n) => ((n['update'] as Map)['sessionUpdate'] as String).endsWith(
                'message_chunk',
              ),
            ),
        isEmpty,
      );
      expect(rig.host.sessions.keys, ['x']);
      rig.eof();
    });
  });

  test('an agent that refuses the load is the request\'s -32603, the claim '
      'let go', () {
    fakeAsync((async) {
      final rig = Rig(async)..answerReopen = false;
      rig.init = {
        'protocolVersion': 1,
        'agentCapabilities': {'loadSession': true},
      };
      rig.initialize();
      final id = rig.request('session/load', reopen('x'));
      final agent = rig.agents.single;
      agent.send({
        'jsonrpc': '2.0',
        'id': _asked(agent, 'session/load').single['id'],
        'error': {'code': -32002, 'message': 'Resource not found'},
      });
      rig.settle();
      async.elapse(const Duration(seconds: 1));
      rig.settle();
      final error = rig.answer(id)!['error'] as Map;
      expect(error['code'], -32603);
      // The original's step words, as for a refused session/new.
      expect(error['message'], 'it refused session/load: Resource not found');
      expect(rig.host.reopening, isEmpty);
      expect(rig.host.sessions, isEmpty);
      rig.eof();
    });
  });

  test('a \$/cancel_request while the agent loads closes it: -32800, the '
      'claim let go', () {
    fakeAsync((async) {
      final rig = Rig(async)..answerReopen = false;
      rig.init = {
        'protocolVersion': 1,
        'agentCapabilities': {'loadSession': true},
      };
      rig.initialize();
      final id = rig.request('session/load', reopen('x'));
      rig.send({
        'jsonrpc': '2.0',
        'method': r'$/cancel_request',
        'params': {'requestId': id},
      });
      async.elapse(const Duration(seconds: 1));
      rig.settle();
      expect((rig.answer(id)!['error'] as Map)['code'], -32800);
      expect(rig.host.reopening, isEmpty);
      expect(rig.host.sessions, isEmpty);
      rig.eof();
    });
  });

  group('tester U13 reopen admission and flush boundaries', () {
    for (final method in ['session/load', 'session/resume']) {
      for (final stage in ['records', 'place']) {
        for (final reason in <LeaveReason>[
          const LeaveEof(),
          const LeaveCrash(),
          const LeaveSignal(ProcessSignal.sigterm),
        ]) {
          test(
            '$method held at $stage admits nothing on ${reason.runtimeType}',
            () {
              fakeAsync((async) {
                final records = Completer<List<SessionRecord>>();
                final place = Completer<AcpPlace>();
                final rig = Rig(
                  async,
                  records: () =>
                      stage == 'records' ? records.future : Future.value([]),
                  place: (_) => place.future,
                );
                rig.initialize();
                final id = rig.request(method, reopen('held'));
                expect(rig.agents, isEmpty);
                rig.host.leave(reason);
                rig.settle();
                async.elapse(const Duration(seconds: 20));
                rig.settle();
                if (reason is LeaveEof) {
                  expect(rig.answer(id), isNull);
                } else {
                  expect(rig.answer(id)!['error'], {
                    'code': -32603,
                    'message': 'chord is closing',
                  });
                }
                expect(rig.agents, isEmpty);
                records.complete([]);
                place.complete((
                  cwd: '/w',
                  start: const SessionStart(command: 'memory'),
                ));
                rig.settle();
                expect(rig.agents, isEmpty);
                expect(rig.host.sessions, isEmpty);
                expect(rig.host.reopening, isEmpty);
                expect(rig.exits, hasLength(1));
                expect(
                  rig.lines.messages.where(
                    (m) => m['id'] == id && !m.containsKey('method'),
                  ),
                  hasLength(reason is LeaveEof ? 0 : 1),
                );
                expect(async.nonPeriodicTimerCount, 0);
              });
            },
          );
        }
      }

      test('$method holds live updates until its answer flushes', () {
        fakeAsync((async) {
          final rig = Rig(async)
            ..init = {
              'protocolVersion': 1,
              'agentCapabilities': {
                'loadSession': true,
                'sessionCapabilities': {'resume': {}},
              },
            }
            ..replay = [_chunk('agent_message_chunk', 'past')];
          rig.initialize();
          rig.lines.hold = true;
          final id = rig.request(method, reopen('x'));
          final agent = rig.agents.single;
          agent.send({
            'jsonrpc': '2.0',
            'method': 'session/update',
            'params': {
              'sessionId': 'x',
              'update': _chunk('agent_message_chunk', 'live'),
            },
          });
          rig.settle();
          expect(
            rig
                .notified('session/update')
                .where(
                  (m) =>
                      ((m['update'] as Map)['content'] as Map?)?['text'] ==
                      'live',
                ),
            isEmpty,
          );
          rig.lines.release();
          rig.settle();
          final order = [
            for (final m in rig.lines.messages)
              if (m['id'] == id && !m.containsKey('method'))
                'answer'
              else if (m['method'] == 'session/update' &&
                  ((m['params'] as Map)['update'] as Map)['sessionUpdate'] ==
                      'agent_message_chunk')
                ((((m['params'] as Map)['update'] as Map)['content']
                    as Map)['text']),
          ];
          expect(
            order,
            method == 'session/load'
                ? ['past', 'answer', 'live']
                : ['answer', 'live'],
          );
          rig.eof();
          expect(async.nonPeriodicTimerCount, 0);
        });
      });
    }
  });
}
