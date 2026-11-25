// chord acp's turns and asks in memory: prompts and their queue, every way
// a client cancels, permissions and forms relayed, the session state and
// steering.
import 'package:chord/acp/process.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';
import 'fixtures/questions.dart';

Map<String, Object?> _text(String text) => {'type': 'text', 'text': text};

Map<String, Object?> _chunk(String text) => {
  'sessionUpdate': 'agent_message_chunk',
  'content': _text(text),
};

/// The agent's requests of [method], in order.
List<Map<String, Object?>> _asked(MemoryAgentProcess agent, String method) => [
  for (final message in agent.stdin.messages)
    if (message['method'] == method && message.containsKey('id')) message,
];

/// The agent's notifications of [method].
List<Map<String, Object?>> _told(MemoryAgentProcess agent, String method) => [
  for (final message in agent.stdin.messages)
    if (message['method'] == method && !message.containsKey('id')) message,
];

/// The agent's answers to its own requests, by id.
Map<Object?, Map<String, Object?>> _answers(MemoryAgentProcess agent) => {
  for (final message in agent.stdin.messages)
    if (!message.containsKey('method')) message['id']: message,
};

void _reply(Rig rig, MemoryAgentProcess agent, Object? id, Object? result) {
  agent.send({'jsonrpc': '2.0', 'id': id, 'result': result});
  rig.settle();
}

void _update(Rig rig, MemoryAgentProcess agent, Map<String, Object?> update) {
  agent.send({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {
      'sessionId': 's${rig.agents.indexOf(agent) + 1}',
      'update': update,
    },
  });
  rig.settle();
}

int _prompt(Rig rig, String sessionId, String text) =>
    rig.request('session/prompt', {
      'sessionId': sessionId,
      'prompt': [_text(text)],
    });

void _cancelRequest(Rig rig, int id) => rig.send({
  'jsonrpc': '2.0',
  'method': r'$/cancel_request',
  'params': {'requestId': id},
});

Map<String, Object?> _permission(Object id, String sessionId) => {
  'jsonrpc': '2.0',
  'id': id,
  'method': 'session/request_permission',
  'params': {
    'sessionId': sessionId,
    'toolCall': {'toolCallId': 'write-1', 'title': 'Write notes.txt'},
    'options': [
      {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
      {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
    ],
  },
};

void main() {
  late Rig rig;

  void up(FakeAsync async, {Map<String, Object?>? init}) {
    rig = Rig(async);
    if (init != null) rig.init = init;
    rig.initialize({
      'session': {'notices': <String, Object?>{}},
    });
  }

  void done(FakeAsync async) {
    rig.eof();
  }

  group('CTUI-68 tester: enriched ACP question relay', () {
    test(
      'every adapter keeps its schema and metadata and receives the client answer',
      () {
        for (final (form, name) in [
          (claudeQuestionsForm, 'claude'),
          (claudeQuestionForm, 'claude'),
          (codexQuestionsForm, 'codex'),
          (droidQuestionsForm, 'droid'),
          (opencodeQuestionsForm, 'opencode'),
          (dimcodeQuestionsForm, 'dimcode'),
        ]) {
          fakeAsync((async) {
            up(async);
            final session = rig.newSession();
            final agent = rig.agents.single;
            agent.send({
              'jsonrpc': '2.0',
              'id': 10,
              'method': 'elicitation/create',
              'params': {...form, 'sessionId': 's1'},
            });
            rig.settle();
            final request = rig.lines.messages.lastWhere(
              (m) => m['method'] == 'elicitation/create',
            );
            final params = request['params']! as Map<String, Object?>;
            expect(params['sessionId'], session);
            expect(params['message'], form['message']);
            expect(params['requestedSchema'], form['requestedSchema']);
            final meta = params['_meta']! as Map;
            expect((meta['chord/questions'] as Map)['agent'], name);
            for (final entry in (form['_meta'] as Map? ?? {}).entries) {
              expect(meta[entry.key], entry.value);
            }
            const content = {'answer': '界🙂e\u0301', 'token': 'fake-secret'};
            rig.send({
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': {'action': 'accept', 'content': content},
            });
            expect(_answers(agent)[10]?['result'], {
              'action': 'accept',
              'content': content,
            });
            done(async);
          });
        }
      },
    );

    test(
      'two sessions with the same upstream id cancel and answer independently',
      () {
        fakeAsync((async) {
          up(async);
          final first = rig.newSession();
          final second = rig.newSession();
          _prompt(rig, first, 'ask');
          _prompt(rig, second, 'ask');
          for (var index = 0; index < 2; index++) {
            rig.agents[index].send({
              'jsonrpc': '2.0',
              'id': 10,
              'method': 'elicitation/create',
              'params': {...codexQuestionsForm, 'sessionId': 's${index + 1}'},
            });
            rig.settle();
          }
          final requests = rig.lines.messages
              .where((m) => m['method'] == 'elicitation/create')
              .toList();
          expect(requests, hasLength(2));
          expect(requests[0]['id'], isNot(requests[1]['id']));
          rig.send({
            'jsonrpc': '2.0',
            'method': 'session/cancel',
            'params': {'sessionId': first},
          });
          expect(_answers(rig.agents[0])[10]?['result'], {'action': 'cancel'});
          expect(_answers(rig.agents[1])[10], isNull);
          rig.send({
            'jsonrpc': '2.0',
            'id': requests[0]['id'],
            'result': {
              'action': 'accept',
              'content': {'next_note': 'stale'},
            },
          });
          expect(_answers(rig.agents[1])[10], isNull);
          rig.send({
            'jsonrpc': '2.0',
            'id': requests[1]['id'],
            'result': {'action': 'decline'},
          });
          expect(_answers(rig.agents[0])[10]?['result'], {'action': 'cancel'});
          expect(_answers(rig.agents[1])[10]?['result'], {'action': 'decline'});
          done(async);
        });
      },
    );
  });

  group('a prompt', () {
    test('its updates go before its answer, which carries the stop reason '
        'and usage', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        final id = _prompt(rig, s, 'hi');
        final agent = rig.agents.single;
        final asked = _asked(agent, 'session/prompt').single;
        expect((asked['params'] as Map)['prompt'], [_text('hi')]);
        _update(rig, agent, _chunk('Hello'));
        _reply(rig, agent, asked['id'], {
          'stopReason': 'end_turn',
          'usage': {'inputTokens': 3, 'outputTokens': 1, 'totalTokens': 4},
        });
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        final order = [
          for (final m in rig.lines.messages)
            if (m['id'] == id)
              'answer'
            else if (m['method'] == 'session/update' &&
                (m['params'] as Map)['update']['sessionUpdate'] !=
                    'available_commands_update')
              'update',
        ];
        expect(order, ['update', 'answer']);
        expect(rig.answer(id)!['result'], {
          'stopReason': 'end_turn',
          'usage': {'inputTokens': 3, 'outputTokens': 1, 'totalTokens': 4},
        });
        done(async);
      });
    });

    test('a failed turn is -32603 in its words', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        final id = _prompt(rig, s, 'hi');
        final agent = rig.agents.single;
        agent.send({
          'jsonrpc': '2.0',
          'id': _asked(agent, 'session/prompt').single['id'],
          'error': {'code': -32603, 'message': 'The model is gone.'},
        });
        rig.settle();
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        expect(rig.answer(id)!['error'], {
          'code': -32603,
          'message': 'The model is gone.',
        });
        done(async);
      });
    });

    test(
      'to no session -32002; an image to an agent that takes none -32602',
      () {
        fakeAsync((async) {
          up(async);
          final s = rig.newSession();
          expect(rig.answer(_prompt(rig, 'nobody', 'hi'))!['error'], {
            'code': -32002,
            'message': 'Resource not found',
            'data': {'sessionId': 'nobody'},
          });
          final id = rig.request('session/prompt', {
            'sessionId': s,
            'prompt': [
              {'type': 'image', 'data': 'AAAA', 'mimeType': 'image/png'},
            ],
          });
          expect(rig.answer(id)!['error'], {
            'code': -32602,
            'message': 'Invalid params: memory does not take images',
          });
          expect(_asked(rig.agents.single, 'session/prompt'), isEmpty);
          done(async);
        });
      },
    );
  });

  group('cancelling', () {
    test('session/cancel interrupts the turn and answers every queued prompt '
        'cancelled; the running one answers when the agent does', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        final running = _prompt(rig, s, 'one');
        final queued = _prompt(rig, s, 'two');
        final agent = rig.agents.single;
        expect(_asked(agent, 'session/prompt'), hasLength(1));
        rig.send({
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': s},
        });
        expect(rig.answer(queued)!['result'], {'stopReason': 'cancelled'});
        expect(rig.answer(running), isNull);
        expect(_told(agent, 'session/cancel'), hasLength(1));
        _reply(rig, agent, _asked(agent, 'session/prompt').single['id'], {
          'stopReason': 'cancelled',
        });
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        expect(rig.answer(running)!['result'], {'stopReason': 'cancelled'});
        expect(_asked(agent, 'session/prompt'), hasLength(1));
        done(async);
      });
    });

    test('\$/cancel_request on a queued prompt takes it alone out of the '
        'queue', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        final running = _prompt(rig, s, 'one');
        final first = _prompt(rig, s, 'two');
        final second = _prompt(rig, s, 'three');
        _cancelRequest(rig, first);
        expect(rig.answer(first)!['result'], {'stopReason': 'cancelled'});
        expect(rig.answer(second), isNull);
        final agent = rig.agents.single;
        expect(_told(agent, 'session/cancel'), isEmpty);
        _reply(rig, agent, _asked(agent, 'session/prompt').single['id'], {
          'stopReason': 'end_turn',
        });
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        expect(rig.answer(running)!['result'], {'stopReason': 'end_turn'});
        final prompts = _asked(agent, 'session/prompt');
        expect(((prompts.last['params'] as Map)['prompt'] as List).single, {
          'type': 'text',
          'text': 'three',
        });
        done(async);
      });
    });

    test('\$/cancel_request on the running prompt cancels that turn, which '
        'answers when the agent does', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        final running = _prompt(rig, s, 'one');
        _cancelRequest(rig, running);
        final agent = rig.agents.single;
        expect(_told(agent, 'session/cancel'), hasLength(1));
        _reply(rig, agent, _asked(agent, 'session/prompt').single['id'], {
          'stopReason': 'cancelled',
        });
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        expect(rig.answer(running)!['result'], {'stopReason': 'cancelled'});
        done(async);
      });
    });

    test('an agent that ignores a cancel leaves the prompt open until '
        'session/close answers it cancelled', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        final running = _prompt(rig, s, 'one');
        rig.send({
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': s},
        });
        async.elapse(const Duration(seconds: 60));
        rig.settle();
        expect(rig.answer(running), isNull);
        rig.request('session/close', {'sessionId': s});
        expect(rig.answer(running)!['result'], {'stopReason': 'cancelled'});
        done(async);
      });
    });

    test('an agent gone mid-turn: the running prompt fails, a queued one '
        'is -32002', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        final running = _prompt(rig, s, 'one');
        final queued = _prompt(rig, s, 'two');
        final agent = rig.agents.single;
        agent
          ..writeStderr('fatal: out of memory\n')
          ..exit(const Exit(1))
          ..closeStdout()
          ..closeStderr();
        rig.settle();
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        expect(rig.answer(queued)!['error'], {
          'code': -32002,
          'message': 'Resource not found',
          'data': {'sessionId': s},
        });
        final error = rig.answer(running)!['error'] as Map;
        expect(error['code'], -32603);
        expect(error['message'], contains('fatal: out of memory'));
        expect(rig.host.sessions, isEmpty);
        done(async);
      });
    });
  });

  group('permissions', () {
    test('relayed under the client\'s id, the chosen option going back', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        _prompt(rig, s, 'write');
        final agent = rig.agents.single;
        agent.send(_permission(77, 's1'));
        rig.settle();
        final asked = rig.lines.messages.lastWhere(
          (m) => m['method'] == 'session/request_permission',
        );
        expect((asked['params'] as Map)['sessionId'], s);
        expect(
          rig.notified('_chord/session/state').last['state'],
          'requires_action',
        );
        rig.send({
          'jsonrpc': '2.0',
          'id': asked['id'],
          'result': {
            'outcome': {'outcome': 'selected', 'optionId': 'allow'},
          },
        });
        expect(_answers(agent)[77]?['result'], {
          'outcome': {'outcome': 'selected', 'optionId': 'allow'},
        });
        expect(rig.notified('_chord/session/state').last, {
          'sessionId': s,
          'state': 'running',
          'origin': 'client',
        });
        done(async);
      });
    });

    test('two sessions asking their first: one answered, the other closed '
        'and withdrawn; late answers touch neither', () {
      fakeAsync((async) {
        up(async);
        final a = rig.newSession();
        final b = rig.newSession();
        _prompt(rig, a, 'write');
        _prompt(rig, b, 'write');
        final [first, second] = rig.agents;
        first.send(_permission(1, 's1'));
        second.send(_permission(1, 's2'));
        rig.settle();
        final asks = rig.lines.messages
            .where((m) => m['method'] == 'session/request_permission')
            .toList();
        expect(asks, hasLength(2));
        final askOfA = asks.firstWhere(
          (m) => (m['params'] as Map)['sessionId'] == a,
        );
        final askOfB = asks.firstWhere(
          (m) => (m['params'] as Map)['sessionId'] == b,
        );
        rig.request('session/close', {'sessionId': b});
        expect(rig.notified(r'$/cancel_request'), [
          {'requestId': askOfB['id']},
        ]);
        rig.send({
          'jsonrpc': '2.0',
          'id': askOfA['id'],
          'result': {
            'outcome': {'outcome': 'selected', 'optionId': 'deny'},
          },
        });
        rig.send({
          'jsonrpc': '2.0',
          'id': askOfB['id'],
          'result': {
            'outcome': {'outcome': 'selected', 'optionId': 'allow'},
          },
        });
        expect(_answers(first)[1]?['result'], {
          'outcome': {'outcome': 'selected', 'optionId': 'deny'},
        });
        expect(_answers(second)[1]?['result'], {
          'outcome': {'outcome': 'cancelled'},
        });
        done(async);
      });
    });

    test('a client\'s error is a refusal, said on stderr', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        _prompt(rig, s, 'write');
        final agent = rig.agents.single;
        agent.send(_permission(5, 's1'));
        rig.settle();
        final asked = rig.lines.messages.lastWhere(
          (m) => m['method'] == 'session/request_permission',
        );
        rig.send({
          'jsonrpc': '2.0',
          'id': asked['id'],
          'error': {'code': -32603, 'message': 'no screen'},
        });
        async.elapse(const Duration(milliseconds: 10));
        rig.settle();
        expect(
          rig.said,
          contains(
            'chord: the client answered session/request_permission with an '
            'error: no screen',
          ),
        );
        // A refusal takes the request's own reject option, as Esc does.
        expect(_answers(agent)[5]?['result'], {
          'outcome': {'outcome': 'selected', 'optionId': 'deny'},
        });
        done(async);
      });
    });

    test('one naming a session the agent never announced is refused', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        _prompt(rig, s, 'write');
        final agent = rig.agents.single;
        agent.send(_permission(6, 'elsewhere'));
        rig.settle();
        expect(
          rig.lines.messages.where(
            (m) => m['method'] == 'session/request_permission',
          ),
          isEmpty,
        );
        expect(
          rig.said,
          contains(
            'chord: refused a permission for a session it does not know',
          ),
        );
        done(async);
      });
    });
  });

  group('forms and links', () {
    Map<String, Object?> form(Object id, {String? sessionId = 's1'}) => {
      'jsonrpc': '2.0',
      'id': id,
      'method': 'elicitation/create',
      'params': {
        'sessionId': ?sessionId,
        'mode': 'form',
        'message': 'Your name?',
        'requestedSchema': {'type': 'object'},
      },
    };

    test('a session\'s form goes to the client raw, its answer back', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        final agent = rig.agents.single;
        agent.send(form(9));
        rig.settle();
        final asked = rig.lines.messages.lastWhere(
          (m) => m['method'] == 'elicitation/create',
        );
        expect(asked['params'], {
          'sessionId': s,
          'mode': 'form',
          'message': 'Your name?',
          'requestedSchema': {'type': 'object'},
        });
        expect(
          rig.notified('_chord/session/state').last['state'],
          'requires_action',
        );
        rig.send({
          'jsonrpc': '2.0',
          'id': asked['id'],
          'result': {
            'action': 'accept',
            'content': {'name': 'Ada'},
          },
        });
        expect(_answers(agent)[9]?['result'], {
          'action': 'accept',
          'content': {'name': 'Ada'},
        });
        expect(rig.notified('_chord/session/state').last['state'], 'idle');
        done(async);
      });
    });

    test("an adapter's question form goes to the client with the questions "
        "chord read in it under _meta, the form as the agent sent it", () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        final agent = rig.agents.single;
        agent.send({
          'jsonrpc': '2.0',
          'id': 10,
          'method': 'elicitation/create',
          'params': {'sessionId': 's1', ...opencodeQuestionsForm},
        });
        rig.settle();
        final asked = rig.lines.messages.lastWhere(
          (m) => m['method'] == 'elicitation/create',
        );
        final params = asked['params']! as Map<String, Object?>;
        expect(params['sessionId'], s);
        expect(
          params['requestedSchema'],
          opencodeQuestionsForm['requestedSchema'],
        );
        expect(
          ((params['_meta']! as Map)['chord/questions'] as Map)['agent'],
          'opencode',
        );
        done(async);
      });
    });

    test('a mode ACP lacks is cancelled without asking the client', () {
      fakeAsync((async) {
        up(async);
        rig.newSession();
        final agent = rig.agents.single;
        agent.send({
          'jsonrpc': '2.0',
          'id': 13,
          'method': 'elicitation/create',
          'params': {'sessionId': 's1', 'mode': 'future', 'message': '?'},
        });
        rig.settle();
        expect(_answers(agent)[13]?['result'], {'action': 'cancel'});
        expect(
          rig.lines.messages.where((m) => m['method'] == 'elicitation/create'),
          isEmpty,
        );
        done(async);
      });
    });

    test('a request-scoped one is cancelled; one an answer ACP lacks is '
        'cancel', () {
      fakeAsync((async) {
        up(async);
        rig.newSession();
        final agent = rig.agents.single;
        agent.send(form(10, sessionId: null));
        rig.settle();
        expect(_answers(agent)[10]?['result'], {'action': 'cancel'});
        agent.send(form(11));
        rig.settle();
        final asked = rig.lines.messages.lastWhere(
          (m) => m['method'] == 'elicitation/create',
        );
        rig.send({
          'jsonrpc': '2.0',
          'id': asked['id'],
          'result': {'action': 'maybe'},
        });
        expect(_answers(agent)[11]?['result'], {'action': 'cancel'});
        done(async);
      });
    });

    test('session/cancel withdraws it from the client; a late '
        'elicitation/complete is passed on', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        _prompt(rig, s, 'go');
        final agent = rig.agents.single;
        agent.send(form(12));
        rig.settle();
        final asked = rig.lines.messages.lastWhere(
          (m) => m['method'] == 'elicitation/create',
        );
        rig.send({
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': s},
        });
        expect(rig.notified(r'$/cancel_request'), [
          {'requestId': asked['id']},
        ]);
        expect(_answers(agent)[12]?['result'], {'action': 'cancel'});
        agent.send({
          'jsonrpc': '2.0',
          'method': 'elicitation/complete',
          'params': {'elicitationId': 'e1'},
        });
        rig.settle();
        expect(rig.notified('elicitation/complete'), [
          {'elicitationId': 'e1'},
        ]);
        done(async);
      });
    });
  });

  group('the order of an ask and the state it causes', () {
    List<Object?> order(Rig rig) => [
      for (final m in rig.lines.messages)
        if (m['method'] case final String method
            when method != 'session/update')
          method == '_chord/session/state'
              ? 'state ${(m['params'] as Map)['state']}'
              : method,
    ];

    test('a permission goes before the requires_action it causes', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        _prompt(rig, s, 'write');
        rig.agents.single.send(_permission(3, 's1'));
        rig.settle();
        final seen = order(rig);
        expect(seen.sublist(seen.indexOf('session/request_permission')), [
          'session/request_permission',
          'state requires_action',
        ]);
        done(async);
      });
    });

    test('a form goes before the requires_action it causes', () {
      fakeAsync((async) {
        up(async);
        rig.newSession();
        rig.agents.single.send({
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'elicitation/create',
          'params': {
            'sessionId': 's1',
            'mode': 'form',
            'message': 'Name?',
            'requestedSchema': {'type': 'object'},
          },
        });
        rig.settle();
        final seen = order(rig);
        expect(seen.sublist(seen.indexOf('elicitation/create')), [
          'elicitation/create',
          'state requires_action',
        ]);
        done(async);
      });
    });

    // As the original: session/cancel is the interrupt alone, and an
    // agent's ask goes only with the cancel of the turn it came in.
    test('session/cancel between turns leaves a permission and a form open: '
        'nothing withdrawn, no \$/cancel_request', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        final agent = rig.agents.single;
        agent
          ..send(_permission(21, 's1'))
          ..send({
            'jsonrpc': '2.0',
            'id': 8,
            'method': 'elicitation/create',
            'params': {
              'sessionId': 's1',
              'mode': 'form',
              'message': 'Name?',
              'requestedSchema': {'type': 'object'},
            },
          });
        rig.settle();
        final permission = rig.lines.messages.lastWhere(
          (m) => m['method'] == 'session/request_permission',
        );
        final form = rig.lines.messages.lastWhere(
          (m) => m['method'] == 'elicitation/create',
        );
        rig.send({
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': s},
        });
        expect(rig.notified(r'$/cancel_request'), isEmpty);
        expect(_answers(agent), isEmpty);
        expect(_told(agent, 'session/cancel'), isEmpty);
        expect(
          rig.notified('_chord/session/state').last['state'],
          'requires_action',
        );
        // Both still the client's to answer.
        rig
          ..send({
            'jsonrpc': '2.0',
            'id': permission['id'],
            'result': {
              'outcome': {'outcome': 'selected', 'optionId': 'allow'},
            },
          })
          ..send({
            'jsonrpc': '2.0',
            'id': form['id'],
            'result': {
              'action': 'accept',
              'content': {'name': 'Ada'},
            },
          });
        expect(_answers(agent)[21]?['result'], {
          'outcome': {'outcome': 'selected', 'optionId': 'allow'},
        });
        expect(_answers(agent)[8]?['result'], {
          'action': 'accept',
          'content': {'name': 'Ada'},
        });
        expect(rig.notified('_chord/session/state').last, {
          'sessionId': s,
          'state': 'idle',
        });
        done(async);
      });
    });

    test('session/cancel during a turn withdraws its permission: the agent '
        'hears cancelled, the client a \$/cancel_request, and a late answer '
        'touches nothing', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        _prompt(rig, s, 'write');
        final agent = rig.agents.single;
        agent.send(_permission(21, 's1'));
        rig.settle();
        final asked = rig.lines.messages.lastWhere(
          (m) => m['method'] == 'session/request_permission',
        );
        rig.send({
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': s},
        });
        expect(rig.notified(r'$/cancel_request'), [
          {'requestId': asked['id']},
        ]);
        expect(_answers(agent)[21]?['result'], {
          'outcome': {'outcome': 'cancelled'},
        });
        expect(_told(agent, 'session/cancel'), hasLength(1));
        rig.send({
          'jsonrpc': '2.0',
          'id': asked['id'],
          'result': {
            'outcome': {'outcome': 'selected', 'optionId': 'allow'},
          },
        });
        expect([
          for (final m in agent.stdin.messages)
            if (m['id'] == 21) m,
        ], hasLength(1));
        done(async);
      });
    });
  });

  group('what an ask leaves behind', () {
    test('the way out releases asks still waiting on the client, withdrawn '
        'ones too', () {
      fakeAsync((async) {
        up(async);
        final a = rig.newSession();
        final b = rig.newSession();
        _prompt(rig, a, 'write');
        _prompt(rig, b, 'write');
        rig.agents[0].send(_permission(1, 's1'));
        rig.agents[1].send(_permission(1, 's2'));
        rig.settle();
        rig.request('session/close', {'sessionId': b});
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        // b's ask is withdrawn, not answered: it waits still, as a.
        expect(rig.host.asking, 2);
        rig.eof();
        expect(rig.host.asking, 0);
      });
    });
  });

  group('what a prompt leaves behind', () {
    test('nothing waits on the connection once each prompt is answered, '
        'withdrawn, cancelled or closed', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        expect(rig.host.watchingClose, isFalse);
        _prompt(rig, s, 'one');
        final queued = _prompt(rig, s, 'two');
        _prompt(rig, s, 'three');
        expect(rig.host.watchingClose, isTrue);
        _cancelRequest(rig, queued);
        rig.send({
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': s},
        });
        final agent = rig.agents.single;
        _reply(rig, agent, _asked(agent, 'session/prompt').single['id'], {
          'stopReason': 'cancelled',
        });
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        expect(rig.host.watchingClose, isFalse);
        _prompt(rig, s, 'four');
        expect(rig.host.watchingClose, isTrue);
        rig.request('session/close', {'sessionId': s});
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        expect(rig.host.watchingClose, isFalse);
        done(async);
      });
    });
  });

  group('the session state', () {
    test('running by the client\'s prompt, idle after, nothing after a '
        'close', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        expect(rig.notified('_chord/session/state'), isEmpty);
        _prompt(rig, s, 'hi');
        final agent = rig.agents.single;
        _reply(rig, agent, _asked(agent, 'session/prompt').single['id'], {
          'stopReason': 'end_turn',
        });
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        expect(rig.notified('_chord/session/state'), [
          {'sessionId': s, 'state': 'running', 'origin': 'client'},
          {'sessionId': s, 'state': 'idle'},
        ]);
        _prompt(rig, s, 'again');
        rig.request('session/close', {'sessionId': s});
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        expect(rig.notified('_chord/session/state').last, {
          'sessionId': s,
          'state': 'running',
          'origin': 'client',
        });
        done(async);
      });
    });
  });

  group('steering', () {
    const steering = {
      'protocolVersion': 1,
      '_meta': {
        'steering': {'supported': true},
      },
    };

    test('into a running turn it is sent, and its words are not told back', () {
      fakeAsync((async) {
        up(async, init: steering);
        final s = rig.newSession();
        _prompt(rig, s, 'one');
        final id = rig.request('_chord/session/steer', {
          'sessionId': s,
          'prompt': [_text('also this')],
        });
        expect(rig.answer(id)!['result'], {'delivery': 'sent'});
        final agent = rig.agents.single;
        expect(_asked(agent, '_session/steering'), hasLength(1));
        done(async);
      });
    });

    test('with nothing running it is queued, and runs as the client\'s own '
        'turn, answering nothing', () {
      fakeAsync((async) {
        up(async, init: steering);
        final s = rig.newSession();
        final id = rig.request('_chord/session/steer', {
          'sessionId': s,
          'prompt': [_text('do this')],
        });
        expect(rig.answer(id)!['result'], {'delivery': 'queued'});
        final agent = rig.agents.single;
        expect(_asked(agent, 'session/prompt'), hasLength(1));
        expect(rig.notified('_chord/session/state').last, {
          'sessionId': s,
          'state': 'running',
          'origin': 'client',
        });
        expect(
          rig
              .notified('session/update')
              .where(
                (n) =>
                    (n['update'] as Map)['sessionUpdate'] ==
                    'user_message_chunk',
              ),
          isEmpty,
        );
        done(async);
      });
    });

    test('an agent without steering keeps it queued, its own entry, behind '
        'the running turn', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        _prompt(rig, s, 'one');
        _prompt(rig, s, 'ahead');
        final id = rig.request('_chord/session/steer', {
          'sessionId': s,
          'prompt': [_text('mine')],
        });
        expect(rig.answer(id)!['result'], {'delivery': 'queued'});
        expect(_asked(rig.agents.single, '_session/steering'), isEmpty);
        done(async);
      });
    });

    test('to no session it is -32002', () {
      fakeAsync((async) {
        up(async);
        final id = rig.request('_chord/session/steer', {
          'sessionId': 'nobody',
          'prompt': [_text('x')],
        });
        expect((rig.answer(id)!['error'] as Map)['code'], -32002);
        done(async);
      });
    });
  });
  group('tester U11 prompt and ask boundaries', () {
    test(
      'a thousand queued prompts cancel once and release the closing watcher',
      () {
        fakeAsync((async) {
          up(async);
          final session = rig.newSession();
          final running = _prompt(rig, session, 'running');
          final queued = [
            for (var i = 0; i < 1000; i++) _prompt(rig, session, 'queued $i'),
          ];
          rig.send({
            'jsonrpc': '2.0',
            'method': 'session/cancel',
            'params': {'sessionId': session},
          });
          for (final id in queued) {
            expect(rig.answer(id)!['result'], {'stopReason': 'cancelled'});
          }
          final agent = rig.agents.single;
          expect(_asked(agent, 'session/prompt'), hasLength(1));
          _reply(rig, agent, _asked(agent, 'session/prompt').single['id'], {
            'stopReason': 'cancelled',
          });
          async.elapse(const Duration(seconds: 2));
          rig.settle();
          expect(rig.answer(running)!['result'], {'stopReason': 'cancelled'});
          for (final id in [running, ...queued]) {
            expect(
              rig.lines.messages.where(
                (m) => m['id'] == id && !m.containsKey('method'),
              ),
              hasLength(1),
            );
          }
          expect(rig.host.watchingClose, isFalse);
          done(async);
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'withdrawing a form leaves a concurrent permission requiring action',
      () {
        fakeAsync((async) {
          up(async);
          final session = rig.newSession();
          _prompt(rig, session, 'working');
          final agent = rig.agents.single;
          agent.send(_permission(41, 's1'));
          agent.send({
            'jsonrpc': '2.0',
            'id': 42,
            'method': 'elicitation/create',
            'params': {
              'sessionId': 's1',
              'mode': 'form',
              'message': 'Name?',
              'requestedSchema': {'type': 'object'},
            },
          });
          rig.settle();
          final form = rig.lines.messages.lastWhere(
            (m) => m['method'] == 'elicitation/create',
          );
          final permission = rig.lines.messages.lastWhere(
            (m) => m['method'] == 'session/request_permission',
          );
          agent.send({
            'jsonrpc': '2.0',
            'method': r'$/cancel_request',
            'params': {'requestId': 42},
          });
          rig.settle();
          expect(_answers(agent)[42]!['result'], {'action': 'cancel'});
          expect(_answers(agent).containsKey(41), isFalse);
          expect(rig.notified(r'$/cancel_request'), [
            {'requestId': form['id']},
          ]);
          expect(
            rig.notified('_chord/session/state').last['state'],
            'requires_action',
          );
          rig.send({
            'jsonrpc': '2.0',
            'id': permission['id'],
            'result': {
              'outcome': {'outcome': 'selected', 'optionId': 'allow'},
            },
          });
          expect(_answers(agent)[41]!['result'], {
            'outcome': {'outcome': 'selected', 'optionId': 'allow'},
          });
          expect(rig.notified('_chord/session/state').last, {
            'sessionId': session,
            'state': 'running',
            'origin': 'client',
          });
          rig.send({
            'jsonrpc': '2.0',
            'id': form['id'],
            'result': {'action': 'accept'},
          });
          expect(
            agent.stdin.messages.where(
              (m) => m['id'] == 42 && !m.containsKey('method'),
            ),
            hasLength(1),
          );
          done(async);
        });
      },
    );

    test(
      'closing one running session answers its queue without stopping another',
      () {
        fakeAsync((async) {
          up(async);
          final first = rig.newSession();
          final second = rig.newSession();
          final running = _prompt(rig, first, 'first');
          final queued = _prompt(rig, first, 'queued');
          final other = _prompt(rig, second, 'second');
          rig.request('session/close', {'sessionId': first});
          async.elapse(const Duration(seconds: 2));
          rig.settle();
          expect(rig.answer(running)!['result'], {'stopReason': 'cancelled'});
          expect(rig.answer(queued)!['result'], {'stopReason': 'cancelled'});
          expect(rig.answer(other), isNull);
          expect(rig.agents.last.stdin.closed, isFalse);
          final agent = rig.agents.last;
          _reply(rig, agent, _asked(agent, 'session/prompt').single['id'], {
            'stopReason': 'end_turn',
          });
          async.elapse(const Duration(seconds: 2));
          rig.settle();
          expect(rig.answer(other)!['result'], {'stopReason': 'end_turn'});
          expect(rig.host.sessions.keys, [second]);
          done(async);
        });
      },
    );
  });
  group('tester U11b held form and idle cancel boundaries', () {
    for (final closes in [false, true]) {
      test(
        'a form held behind the new answer ${closes ? 'is cancelled on close' : 'survives idle cancel and accepts a later answer'}',
        () {
          fakeAsync((async) {
            final rig = Rig(async);
            rig.initialize();
            rig.lines.hold = true;
            final session = rig.newSession();
            final agent = rig.agents.single;
            agent.send({
              'jsonrpc': '2.0',
              'id': 77,
              'method': 'elicitation/create',
              'params': {
                'sessionId': 's1',
                'mode': 'form',
                'message': 'Name?',
                'requestedSchema': {'type': 'object'},
              },
            });
            rig.settle();
            expect(
              rig.lines.messages.where(
                (m) => m['method'] == 'elicitation/create',
              ),
              isEmpty,
            );
            if (closes) {
              rig.request('session/close', {'sessionId': session});
            } else {
              rig.send({
                'jsonrpc': '2.0',
                'method': 'session/cancel',
                'params': {'sessionId': session},
              });
            }
            rig.lines.release();
            rig.settle();
            final asked = rig.lines.messages
                .where((m) => m['method'] == 'elicitation/create')
                .toList();
            if (closes) {
              expect(asked, isEmpty);
              expect(_answers(agent)[77]!['result'], {'action': 'cancel'});
            } else {
              expect(asked, hasLength(1));
              expect(_answers(agent).containsKey(77), isFalse);
              expect(rig.notified(r'$/cancel_request'), isEmpty);
              rig.send({
                'jsonrpc': '2.0',
                'id': asked.single['id'],
                'result': {
                  'action': 'accept',
                  'content': {'name': 'Ada'},
                },
              });
              expect(_answers(agent)[77]!['result'], {
                'action': 'accept',
                'content': {'name': 'Ada'},
              });
            }
            rig.eof();
            expect(async.nonPeriodicTimerCount, 0);
          });
        },
      );
    }
  });
}
