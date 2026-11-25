// chord acp's set_config_option, set_mode, set_title and auth/status in
// memory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/acp/process.dart';
import 'package:chord/acp_agent.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/sessions.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';

List<Map<String, Object?>> _asked(MemoryAgentProcess agent, String method) => [
  for (final message in agent.stdin.messages)
    if (message['method'] == method && message.containsKey('id')) message,
];

const _effort = {
  'id': 'effort',
  'name': 'Effort',
  'type': 'select',
  'currentValue': 'low',
  'options': [
    {'value': 'low', 'name': 'Low'},
    {'value': 'high', 'name': 'High'},
  ],
};

Map<String, Object?> _effortAt(String value) => {
  ..._effort,
  'currentValue': value,
};

void main() {
  group('session/set_config_option', () {
    test('sets the option, answers every option after it, and the client is '
        'not told the same list again', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..newAnswer = {
            'configOptions': [_effort],
          };
        rig.initialize();
        final s = rig.newSession();
        final id = rig.request('session/set_config_option', {
          'sessionId': s,
          'configId': 'effort',
          'value': 'high',
        });
        final agent = rig.agents.single;
        final asked = _asked(agent, 'session/set_config_option').single;
        expect(asked['params'], {
          'sessionId': 's1',
          'configId': 'effort',
          'value': 'high',
        });
        agent.send({
          'jsonrpc': '2.0',
          'id': asked['id'],
          'result': {
            'configOptions': [_effortAt('high')],
          },
        });
        rig.settle();
        expect(rig.answer(id)!['result'], {
          'configOptions': [
            {
              'type': 'select',
              'id': 'effort',
              'name': 'Effort',
              'currentValue': 'high',
              'options': [
                {'value': 'low', 'name': 'Low'},
                {'value': 'high', 'name': 'High'},
              ],
            },
          ],
        });
        // Nothing tells the client again, after its answer, of the list the
        // answer carried.
        final after = rig.lines.messages
            .skipWhile((m) => m['id'] != id)
            .skip(1)
            .where(
              (m) =>
                  m['method'] == 'session/update' &&
                  ((m['params'] as Map)['update'] as Map)['sessionUpdate'] ==
                      'config_option_update',
            );
        expect(after, isEmpty);
        rig.eof();
      });
    });

    test('a boolean, or an option none offers, is -32602', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..newAnswer = {
            'configOptions': [_effort],
          };
        rig.initialize();
        final s = rig.newSession();
        for (final (params, configId) in [
          ({'configId': 'effort', 'type': 'boolean', 'value': true}, 'effort'),
          ({'configId': 'nothing', 'value': 'x'}, 'nothing'),
        ]) {
          final id = rig.request('session/set_config_option', {
            'sessionId': s,
            ...params,
          });
          expect(rig.answer(id)!['error'], {
            'code': -32602,
            'message': 'Invalid params: No option $configId takes that value.',
          });
        }
        rig.eof();
      });
    });

    test('an agent\'s refusal is that request\'s error, unchanged, and no '
        'notice', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..newAnswer = {
            'configOptions': [_effort],
          };
        rig.initialize({
          'session': {'notices': <String, Object?>{}},
        });
        final s = rig.newSession();
        final id = rig.request('session/set_config_option', {
          'sessionId': s,
          'configId': 'effort',
          'value': 'high',
        });
        final agent = rig.agents.single;
        agent.send({
          'jsonrpc': '2.0',
          'id': _asked(agent, 'session/set_config_option').single['id'],
          'error': {
            'code': -32602,
            'message': 'Invalid params',
            'data': {'reason': 'locked'},
          },
        });
        rig.settle();
        expect(rig.answer(id)!['error'], {
          'code': -32602,
          'message': 'Invalid params',
          'data': {'reason': 'locked'},
        });
        expect(
          rig
              .notified('session/update')
              .where((n) => (n['update'] as Map)['sessionUpdate'] == 'notice'),
          isEmpty,
        );
        rig.eof();
      });
    });
  });

  test('session/set_mode answers {} and the change goes as '
      'config_option_update, never current_mode_update', () {
    fakeAsync((async) {
      final rig = Rig(async)
        ..newAnswer = {
          'modes': {
            'currentModeId': 'ask',
            'availableModes': [
              {'id': 'ask', 'name': 'Ask'},
              {'id': 'code', 'name': 'Code'},
            ],
          },
        };
      rig.initialize();
      final s = rig.newSession();
      final id = rig.request('session/set_mode', {
        'sessionId': s,
        'modeId': 'code',
      });
      final agent = rig.agents.single;
      agent
        ..send({
          'jsonrpc': '2.0',
          'method': 'session/update',
          'params': {
            'sessionId': 's1',
            'update': {
              'sessionUpdate': 'current_mode_update',
              'currentModeId': 'code',
            },
          },
        })
        ..send({
          'jsonrpc': '2.0',
          'id': _asked(agent, 'session/set_mode').single['id'],
          'result': <String, Object?>{},
        });
      rig.settle();
      expect(rig.answer(id)!['result'], <String, Object?>{});
      final kinds = [
        for (final n in rig.notified('session/update'))
          (n['update'] as Map)['sessionUpdate'],
      ];
      expect(kinds, contains('config_option_update'));
      expect(kinds, isNot(contains('current_mode_update')));
      rig.eof();
    });
  });

  group('session/set_title', () {
    test('a live session is renamed, the agent\'s answer kept where it takes '
        'titles', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..init = {
            'protocolVersion': 1,
            'agentCapabilities': {
              'sessionCapabilities': {'title': <String, Object?>{}},
            },
          };
        rig.initialize();
        final s = rig.newSession();
        final id = rig.request('session/set_title', {
          'sessionId': s,
          'title': '  Fix   the parser ',
        });
        final agent = rig.agents.single;
        final asked = _asked(agent, 'session/set_title').single;
        expect((asked['params'] as Map)['title'], 'Fix the parser');
        agent.send({
          'jsonrpc': '2.0',
          'id': asked['id'],
          'result': {'title': 'Fix the parser (agent)'},
        });
        rig.settle();
        expect(rig.answer(id)!['result'], {'title': 'Fix the parser (agent)'});
        rig.eof();
      });
    });

    test('an agent that takes none keeps it in chord; an empty title is '
        '-32602, an unknown session -32002', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.initialize();
        final s = rig.newSession();
        expect(
          rig.answer(
            rig.request('session/set_title', {'sessionId': s, 'title': 'Mine'}),
          )!['result'],
          {'title': 'Mine'},
        );
        expect(
          rig.answer(
            rig.request('session/set_title', {'sessionId': s, 'title': '  '}),
          )!['error'],
          {'code': -32602, 'message': 'Invalid params: The title is empty.'},
        );
        expect(
          (rig.answer(
                rig.request('session/set_title', {
                  'sessionId': 'nobody',
                  'title': 'x',
                }),
              )!['error']
              as Map)['code'],
          -32002,
        );
        rig.eof();
      });
    });

    test(
      'a listed session not loaded gets a pending rename in its record',
      () async {
        final dir = Directory.systemTemp.createTempSync('chord-title-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final record = '${dir.path}/one.jsonl';
        File(record).writeAsStringSync('');
        final input = StreamController<List<int>>();
        final lines = Lines();
        runAcp(
          input: input.stream,
          sink: lines,
          agent: 'memory',
          version: '9.9.9',
          place: anyPlace,
          stateDir: dir.path,
          stderr: (_) {},
          exit: (_) {},
          records: () async => [
            SessionRecord(
              path: record,
              sessionId: 'one',
              agent: 'memory',
              cwd: '/w',
              prompt: 'Old',
              lastUsedAt: 0,
            ),
          ],
          recording: (_) => NoRecording(),
        );
        void send(Map<String, Object?> message) =>
            input.add(utf8.encode('${jsonEncode(message)}\n'));
        send({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': 1},
        });
        send({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'session/set_title',
          'params': {'sessionId': 'one', 'title': 'Later'},
        });
        Map<String, Object?>? answer() =>
            lines.messages.where((m) => m['id'] == 2).firstOrNull;
        for (var i = 0; i < 200 && answer() == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(answer()?['result'], {'title': 'Later'});
        await input.close();
        final line = jsonDecode(File(record).readAsLinesSync().single) as Map;
        expect(line['type'], 'renamed');
        expect(line['title'], 'Later');
        expect(line['pending'], isTrue);
        expect(
          recordActions([line.cast<String, Object?>()]).pendingRename,
          'Later',
        );
      },
    );
  });

  group('auth/status', () {
    const signedIn = {
      'state': 'authenticated',
      'accounts': [
        {'label': 'Claude Max', 'active': true},
      ],
    };

    test('is the oldest live session\'s: unknown while it has heard none, '
        'even if a newer has, until it closes; each change told once', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..initOf = (n) => n == 1
              ? {
                  'protocolVersion': 1,
                  'agentCapabilities': {
                    'auth': {'status': <String, Object?>{}},
                  },
                }
              : null;
        rig.initialize();
        final oldest = rig.newSession();
        rig.newSession();
        final newer = rig.agents[1];
        newer.send({
          'jsonrpc': '2.0',
          'id': _asked(newer, 'auth/status').single['id'],
          'result': signedIn,
        });
        rig.settle();
        expect(rig.answer(rig.request('auth/status'))!['result'], {
          'state': 'unknown',
        });
        expect(rig.notified('auth/status_update'), isEmpty);
        rig.request('session/close', {'sessionId': oldest});
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        expect(rig.answer(rig.request('auth/status'))!['result'], signedIn);
        expect(rig.notified('auth/status_update'), [signedIn]);
        // The same value again, keys in another order, is no news.
        newer.send({
          'jsonrpc': '2.0',
          'method': 'auth/status_update',
          'params': {
            'accounts': [
              {'active': true, 'label': 'Claude Max'},
            ],
            'state': 'authenticated',
          },
        });
        rig.settle();
        expect(rig.notified('auth/status_update'), hasLength(1));
        rig.eof();
      });
    });
  });
  group('tester U12 settings and account boundaries', () {
    test('late retired account replies cannot replace the next source', () {
      fakeAsync((async) {
        final rig = Rig(async)
          ..init = {
            'protocolVersion': 1,
            'agentCapabilities': {
              'auth': {'status': {}},
            },
          };
        rig.initialize();
        final first = rig.newSession();
        rig.newSession();
        final old = rig.agents.first;
        final current = rig.agents.last;
        final oldAsk = _asked(old, 'auth/status').single['id'];
        current.send({
          'jsonrpc': '2.0',
          'method': 'auth/status_update',
          'params': {
            'state': 'authenticated',
            'accounts': [
              {'label': 'second'},
            ],
          },
        });
        rig.settle();
        expect(rig.answer(rig.request('auth/status'))!['result'], {
          'state': 'unknown',
        });
        rig.request('session/close', {'sessionId': first});
        rig.settle();
        old.send({
          'jsonrpc': '2.0',
          'id': oldAsk,
          'result': {
            'state': 'authenticated',
            'accounts': [
              {'label': 'retired'},
            ],
          },
        });
        rig.settle();
        expect(rig.answer(rig.request('auth/status'))!['result'], {
          'state': 'authenticated',
          'accounts': [
            {'label': 'second'},
          ],
        });
        expect(rig.notified('auth/status_update'), [
          {
            'state': 'authenticated',
            'accounts': [
              {'label': 'second'},
            ],
          },
        ]);
        async.elapse(const Duration(seconds: 2));
        rig.settle();
        rig.eof();
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test(
      'repeated deep-equal pushes are suppressed and losing all sources is unknown',
      () {
        fakeAsync((async) {
          final rig = Rig(async);
          rig.initialize();
          final session = rig.newSession();
          final process = rig.agents.single;
          for (var i = 0; i < 1000; i++) {
            process.send({
              'jsonrpc': '2.0',
              'method': 'auth/status_update',
              'params': i.isEven
                  ? {
                      'state': 'authenticated',
                      '_meta': {
                        'a': [1, null],
                        'b': true,
                      },
                    }
                  : {
                      '_meta': {
                        'b': true,
                        'a': [1, null],
                      },
                      'state': 'authenticated',
                    },
            });
          }
          rig.settle();
          expect(rig.notified('auth/status_update'), hasLength(1));
          rig.request('session/close', {'sessionId': session});
          async.elapse(const Duration(seconds: 2));
          rig.settle();
          expect(rig.answer(rig.request('auth/status'))!['result'], {
            'state': 'unknown',
          });
          expect(rig.notified('auth/status_update').last, {'state': 'unknown'});
          rig.eof();
        });
      },
    );

    test(
      'equal agent session ids keep independent config answers and aliases',
      () {
        fakeAsync((async) {
          final rig = Rig(async)
            ..newAnswer = {
              'configOptions': [_effort],
            }
            ..sessionId = (_) => 'same';
          rig.initialize();
          final first = rig.newSession();
          final second = rig.newSession();
          final one = rig.request('session/set_config_option', {
            'sessionId': first,
            'configId': 'effort',
            'value': 'high',
          });
          final two = rig.request('session/set_config_option', {
            'sessionId': second,
            'configId': 'effort',
            'value': 'high',
          });
          rig.agents[1].send({
            'jsonrpc': '2.0',
            'id': _asked(
              rig.agents[1],
              'session/set_config_option',
            ).single['id'],
            'result': {
              'configOptions': [_effortAt('high')],
            },
          });
          rig.settle();
          expect(rig.answer(one), isNull);
          expect(rig.answer(two)!['result'], contains('configOptions'));
          rig.agents[0].send({
            'jsonrpc': '2.0',
            'id': _asked(
              rig.agents[0],
              'session/set_config_option',
            ).single['id'],
            'error': {
              'code': -32602,
              'message': 'first refused',
              'data': {'sessionId': 'same'},
            },
          });
          rig.settle();
          expect(rig.answer(one)!['error'], {
            'code': -32602,
            'message': 'first refused',
            'data': {'sessionId': 'same'},
          });
          expect(
            rig
                .host
                .sessions[second]!
                .state
                .configOptions
                .single['currentValue'],
            'high',
          );
          expect(
            rig
                .host
                .sessions[first]!
                .state
                .configOptions
                .single['currentValue'],
            'low',
          );
          rig.eof();
        });
      },
    );

    test(
      'empty titles reach no agent and successful agent title is preserved',
      () {
        fakeAsync((async) {
          final rig = Rig(async)
            ..init = {
              'protocolVersion': 1,
              'agentCapabilities': {
                'sessionCapabilities': {'title': {}},
              },
            };
          rig.initialize();
          final session = rig.newSession();
          final process = rig.agents.single;
          final empty = rig.request('session/set_title', {
            'sessionId': session,
            'title': ' \n\t ',
          });
          expect((rig.answer(empty)!['error'] as Map)['code'], -32602);
          expect(_asked(process, 'session/set_title'), isEmpty);
          final title = rig.request('session/set_title', {
            'sessionId': session,
            'title': '  界👩‍💻e\u0301\n words ',
          });
          final ask = _asked(process, 'session/set_title').single;
          expect((ask['params'] as Map)['title'], '界👩‍💻e\u0301 words');
          process.send({
            'jsonrpc': '2.0',
            'id': ask['id'],
            'result': {'title': 'Agent chosen'},
          });
          rig.settle();
          expect(rig.answer(title)!['result'], {'title': 'Agent chosen'});
          rig.eof();
        });
      },
    );
  });
}
