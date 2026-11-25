// The relay on CTUI-12's connection, as CTUI-15 amends it: every message
// either way turned before the tap and the routing, failing open. With no
// relay the connection is CTUI-12's, which connection_test.dart holds.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/acp/schema.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

/// A relay whose two sides the test gives, recording what it heard.
class _Relay implements Relay {
  _Relay({this.agent, this.chord});

  final List<Map<String, Object?>> Function(Map<String, Object?>)? agent;
  final List<Map<String, Object?>> Function(Map<String, Object?>)? chord;
  final heardFromAgent = <Map<String, Object?>>[];
  final heardFromChord = <Map<String, Object?>>[];

  @override
  List<Map<String, Object?>> fromAgent(Map<String, Object?> message) {
    heardFromAgent.add(message);
    return agent?.call(message) ?? [message];
  }

  @override
  List<Map<String, Object?>> fromChord(Map<String, Object?> message) {
    heardFromChord.add(message);
    return chord?.call(message) ?? [message];
  }
}

/// An agent in memory, connected through [relay], and what crossed.
class _Harness {
  _Harness(this.relay, {this.onChord}) {
    process = MemoryAgentProcess(
      onSignal: (_) {
        process.exit(const Exit(143, 'SIGTERM'));
        process.closeStdout();
        process.closeStderr();
      },
    );
  }

  final _Relay relay;

  /// Hears each message chord's tap hears, after it is recorded.
  final void Function(Map<String, Object?> message)? onChord;
  late final MemoryAgentProcess process;
  final traffic = <Traffic>[];
  final asked = <RequestPermissionRequest>[];
  final answers = <Completer<RequestPermissionResponse>>[];

  List<Map<String, Object?>> get written => process.stdin.messages;

  /// Connects and answers `initialize`, under fake time.
  Agent open(FakeAsync async) {
    Agent? agent;
    connectAgent(
      process,
      onTraffic: (t) {
        traffic.add(t);
        if (t case ChordTraffic(:final message)) onChord?.call(message);
      },
      onPermission: (request, CancellationToken _) {
        asked.add(request);
        final answer = Completer<RequestPermissionResponse>();
        answers.add(answer);
        return answer.future;
      },
      relay: relay,
    ).then((a) => agent = a);
    async.flushMicrotasks();
    process.send({
      'jsonrpc': '2.0',
      'id': written.single['id'],
      'result': {'protocolVersion': 1},
    });
    async.flushMicrotasks();
    return agent!;
  }

  List<Map<String, Object?>> get fromAgent => [
    for (final t in traffic)
      if (t case AgentTraffic(:final message)) message,
  ];

  List<Map<String, Object?>> get fromChord => [
    for (final t in traffic)
      if (t case ChordTraffic(:final message)) message,
  ];

  void close(FakeAsync async, Agent agent) {
    agent.close();
    async.elapse(const Duration(seconds: 5));
  }
}

Map<String, Object?> _update(String text) => {
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {
    'sessionId': 's1',
    'update': {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': text},
    },
  },
};

Map<String, Object?> _permission(Object id, {String? title}) => {
  'jsonrpc': '2.0',
  'id': id,
  'method': 'session/request_permission',
  'params': {
    'sessionId': 's1',
    'toolCall': {'toolCallId': 'write-3', 'title': ?title},
    'options': [
      {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
    ],
  },
};

String _text(Map<String, Object?> message) =>
    (((message['params'] as Map)['update'] as Map)['content'] as Map)['text']
        as String;

void main() {
  group('from the agent', () {
    test('each message the relay makes is tapped, in its order', () {
      fakeAsync((async) {
        final h = _Harness(
          _Relay(
            agent: (m) => m['method'] == 'session/update'
                ? [_update('${_text(m)} 1'), _update('${_text(m)} 2')]
                : [m],
          ),
        );
        final agent = h.open(async);

        h.process.send(_update('a'));
        h.process.send(_update('b'));
        async.flushMicrotasks();

        expect(
          [
            for (final m in h.fromAgent)
              if (m['method'] == 'session/update') _text(m),
          ],
          ['a 1', 'a 2', 'b 1', 'b 2'],
        );
        expect(h.relay.heardFromAgent.map((m) => m['method']).nonNulls, [
          'session/update',
          'session/update',
        ]);
        h.close(async, agent);
      });
    });

    test(
      'a message the relay makes nothing of is neither tapped nor routed',
      () {
        fakeAsync((async) {
          final h = _Harness(
            _Relay(agent: (m) => m['method'] == null ? [m] : const []),
          );
          final agent = h.open(async);

          h.process.send(_update('gone'));
          h.process.send(_permission(9, title: 'Write notes.txt'));
          async.flushMicrotasks();

          expect(h.fromAgent.where((m) => m['method'] != null), isEmpty);
          expect(h.asked, isEmpty);
          h.close(async, agent);
        });
      },
    );

    test(
      "the permission handler sees the relay's request, its title filled",
      () {
        fakeAsync((async) {
          final h = _Harness(
            _Relay(
              agent: (m) {
                if (m['method'] != 'session/request_permission') return [m];
                final params = m['params'] as Map<String, Object?>;
                final call = params['toolCall'] as Map<String, Object?>;
                return [
                  {
                    ...m,
                    'params': {
                      ...params,
                      'toolCall': {...call, 'title': 'Write notes.txt'},
                    },
                  },
                ];
              },
            ),
          );
          final agent = h.open(async);

          h.process.send(_permission(9));
          async.flushMicrotasks();

          expect(h.asked.single.toolCall.title, 'Write notes.txt');
          expect(
            ((h.fromAgent.last['params'] as Map)['toolCall'] as Map)['title'],
            'Write notes.txt',
          );
          h.close(async, agent);
        });
      },
    );

    test('a relay that throws passes the raw message on, tapped and routed, '
        'and the next is relayed', () {
      fakeAsync((async) {
        var calls = 0;
        final h = _Harness(
          _Relay(
            agent: (m) {
              // The first is initialize's answer, which must still route.
              if (calls++ < 2) throw StateError('enricher fault');
              return [_update('relayed')];
            },
          ),
        );
        final agent = h.open(async);

        h.process.send(_update('raw'));
        h.process.send(_update('next'));
        async.flushMicrotasks();

        expect(agent.init.protocolVersion, 1);
        expect(
          [
            for (final m in h.fromAgent)
              if (m['method'] == 'session/update') _text(m),
          ],
          ['raw', 'relayed'],
        );
        h.close(async, agent);
      });
    });
  });

  group('from chord', () {
    test('the relay hears each message before its bytes, and what it makes '
        'is written and tapped', () {
      fakeAsync((async) {
        final h = _Harness(
          _Relay(
            chord: (m) => [
              {...m, '_relayed': true},
            ],
          ),
        );
        final agent = h.open(async);

        agent.cancel('s1');
        async.flushMicrotasks();

        expect(h.relay.heardFromChord.map((m) => m['method']), [
          'initialize',
          'session/cancel',
        ]);
        expect(h.relay.heardFromChord.first.containsKey('_relayed'), isFalse);
        expect(h.written.map((m) => m['_relayed']), [true, true]);
        expect(h.fromChord.map((m) => m['_relayed']), [true, true]);
        h.close(async, agent);
      });
    });

    test("a permission's answer goes through the relay, so it knows what it "
        'answers', () {
      fakeAsync((async) {
        final h = _Harness(_Relay());
        final agent = h.open(async);

        h.process.send(_permission(9, title: 'Write notes.txt'));
        async.flushMicrotasks();
        h.answers.single.complete(RequestPermissionResponse.selected('allow'));
        async.flushMicrotasks();

        final answer = h.relay.heardFromChord.last;
        expect(answer['id'], 9);
        expect(answer['result'], {
          'outcome': {'outcome': 'selected', 'optionId': 'allow'},
        });
        h.close(async, agent);
      });
    });

    test(
      'a relay that throws passes the raw message on, written and tapped',
      () {
        fakeAsync((async) {
          final h = _Harness(
            _Relay(chord: (m) => throw StateError('enricher fault')),
          );
          final agent = h.open(async);

          agent.cancel('s1');
          async.flushMicrotasks();

          expect(h.written.map((m) => m['method']), [
            'initialize',
            'session/cancel',
          ]);
          expect(h.fromChord.map((m) => m['method']), [
            'initialize',
            'session/cancel',
          ]);
          h.close(async, agent);
        });
      },
    );

    group('a subscriber that writes or closes on one of several messages', () {
      List<Map<String, Object?>> twice(Map<String, Object?> m) =>
          m['method'] == 'session/cancel'
          ? [
              {...m, 'part': 1},
              {...m, 'part': 2},
            ]
          : [m];

      test('a close it calls on the first leaves the second out, on the wire '
          'as in the tap', () {
        fakeAsync((async) {
          late Agent agent;
          final h = _Harness(
            _Relay(chord: twice),
            onChord: (m) {
              if (m['part'] == 1) agent.close();
            },
          );
          agent = h.open(async);

          agent.cancel('s1');
          async.elapse(const Duration(seconds: 3));

          expect(h.written.last['part'], 1);
          expect(h.fromChord.last['part'], 1);
          expect(h.process.stdin.closedAt, h.process.stdin.bytes.length);
          expect(h.process.stdin.addsAfterClose, 0);
        });
      });

      test('a message it writes on the first goes between the two, on the '
          'wire as in the tap', () {
        fakeAsync((async) {
          late Agent agent;
          var cancelled = false;
          final h = _Harness(
            _Relay(chord: twice),
            onChord: (m) {
              if (m['part'] == 1 && !cancelled) {
                cancelled = true;
                agent.cancel('s2');
              }
            },
          );
          agent = h.open(async);

          agent.cancel('s1');
          async.flushMicrotasks();

          List<String> said(List<Map<String, Object?>> messages) => [
            for (final m in messages.skip(1))
              '${(m['params'] as Map)['sessionId']} ${m['part']}',
          ];
          expect(said(h.written), ['s1 1', 's2 1', 's2 2', 's1 2']);
          expect(said(h.fromChord), said(h.written));
          h.close(async, agent);
        });
      });
    });

    test("a framing reply is the wire's own: written, never relayed", () {
      fakeAsync((async) {
        final h = _Harness(_Relay());
        final agent = h.open(async);

        h.process.writeStdout(utf8.encode('not json\n'));
        async.flushMicrotasks();

        expect(h.written.last['error'], containsPair('code', -32700));
        expect(h.relay.heardFromChord.map((m) => m['method']), ['initialize']);
        expect(h.relay.heardFromAgent, hasLength(1));
        h.close(async, agent);
      });
    });
  });

  test('openAgent passes its relay on to the connection', () async {
    final relay = _Relay();
    final dir = await Directory.systemTemp.createTemp('chord-relay-');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/agent.dart')
      ..writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';
void main() {
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    final message = jsonDecode(line) as Map;
    if (message['method'] == 'initialize') {
      stdout.writeln(jsonEncode({
        'jsonrpc': '2.0', 'id': message['id'], 'result': {'protocolVersion': 1},
      }));
    }
  });
}
''');
    final agent = await openAgent(
      command: [Platform.resolvedExecutable, script.path],
      cwd: dir.path,
      onTraffic: (_) {},
      onPermission: (_, _) async => RequestPermissionResponse.cancelled(),
      relay: relay,
    );
    await agent.close();

    expect(relay.heardFromChord.first['method'], 'initialize');
    expect(relay.heardFromAgent.first['result'], {'protocolVersion': 1});
  });

  group('tester: relay routing and admission', () {
    test('expanded permission requests route independently in relay order', () {
      fakeAsync((async) {
        final h = _Harness(
          _Relay(
            agent: (m) => m['method'] == 'session/request_permission'
                ? [
                    _permission(41, title: 'First'),
                    _permission(42, title: 'Second'),
                  ]
                : [m],
          ),
        );
        final agent = h.open(async);
        h.process.send(_permission(9));
        async.flushMicrotasks();
        expect(h.asked.map((r) => r.toolCall.title), ['First', 'Second']);
        h.answers[1].complete(RequestPermissionResponse.selected('allow'));
        h.answers[0].complete(RequestPermissionResponse.cancelled());
        async.flushMicrotasks();
        final replies = h.written
            .where((m) => m.containsKey('result'))
            .toList();
        expect(replies.map((m) => m['id']), [42, 41]);
        expect(replies.last['result'], {
          'outcome': {'outcome': 'cancelled'},
        });
        h.close(async, agent);
      });
    });

    test('an outbound message dropped by the relay leaves no tap or bytes', () {
      fakeAsync((async) {
        var drop = true;
        final h = _Harness(
          _Relay(
            chord: (m) {
              if (m['method'] == 'session/cancel' && drop) return [];
              return [m];
            },
          ),
        );
        final agent = h.open(async);
        agent.cancel('s1');
        async.flushMicrotasks();
        expect(h.relay.heardFromChord, hasLength(2));
        expect(h.written, hasLength(1));
        expect(h.fromChord, hasLength(1));
        drop = false;
        agent.cancel('s2');
        async.flushMicrotasks();
        expect(h.written.last['params'], {'sessionId': 's2'});
        expect(h.fromChord.last, h.written.last);
        h.close(async, agent);
      });
    });

    test(
      'an outbound fault fails open once and later messages still transform',
      () {
        fakeAsync((async) {
          var fail = true;
          final h = _Harness(
            _Relay(
              chord: (m) {
                if (m['method'] != 'session/cancel') return [m];
                if (fail) {
                  fail = false;
                  throw StateError('one message');
                }
                return [
                  {...m, 'enriched': true},
                ];
              },
            ),
          );
          final agent = h.open(async);
          agent.cancel('s1');
          agent.cancel('s2');
          async.flushMicrotasks();
          expect(h.written[1].containsKey('enriched'), isFalse);
          expect(h.written[2]['enriched'], isTrue);
          expect(h.fromChord, h.written);
          h.close(async, agent);
        });
      },
    );
  });
}
