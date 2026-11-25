// chord acp hosting a session's children in memory: each long-lived child
// under its own route, its updates held until it is up, its state as it
// changes, its close said last; a child's or a task's asks refused for a
// client that takes no subagents; asks with one id from two sessions kept
// apart.
import 'package:chord/acp/process.dart';
import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';

/// chord's server as the host uses it, keeping who was let in.
final class _Server implements ChordServer {
  final admitted = <String, Caller>{};
  final revoked = <String>[];
  var _tokens = 0;

  @override
  String get url => 'http://127.0.0.1:9/mcp';

  @override
  Admitted admit(Caller caller) {
    final token = 'token-${++_tokens}';
    admitted[token] = caller;
    return (
      token: token,
      server: {
        'type': 'http',
        'name': 'chord',
        'url': url,
        'headers': <Object?>[],
      },
    );
  }

  @override
  void revoke(String token) => revoked.add(token);

  @override
  Future<void> close() async {}

  /// The callers of main sessions, in the order they were let in.
  List<Caller> get mains => [
    for (final caller in admitted.values)
      if (caller.role == Role.person) caller,
  ];
}

Map<String, Object?> _text(String text) => {'type': 'text', 'text': text};

void _update(
  Rig rig,
  MemoryAgentProcess agent,
  String sessionId,
  Map<String, Object?> update,
) {
  agent.send({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {'sessionId': sessionId, 'update': update},
  });
  rig.settle();
}

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

/// The agent's answers to its own requests, by id.
Map<Object?, Map<String, Object?>> _answers(MemoryAgentProcess agent) => {
  for (final message in agent.stdin.messages)
    if (!message.containsKey('method')) message['id']: message,
};

/// The agent's prompts, in order.
List<Map<String, Object?>> _prompts(MemoryAgentProcess agent) => [
  for (final message in agent.stdin.messages)
    if (message['method'] == 'session/prompt') message,
];

/// Answers the agent's last prompt with [stopReason].
void _endTurn(Rig rig, MemoryAgentProcess agent, [String stop = 'end_turn']) {
  agent.send({
    'jsonrpc': '2.0',
    'id': _prompts(agent).last['id'],
    'result': {'stopReason': stop},
  });
  rig.settle();
}

/// Every `subagent_update` chord sent of [child] under [parent].
List<Map<String, Object?>> _reports(Rig rig, String parent, String child) => [
  for (final params in rig.notified('session/update'))
    if (params['sessionId'] == parent)
      if (params['update'] case final Map<String, Object?> update
          when update['sessionUpdate'] == 'subagent_update' &&
              update['sessionId'] == child)
        update,
];

/// The state words of each of [reports].
List<Object?> _states(List<Map<String, Object?>> reports) => [
  for (final report in reports) report['state'],
];

/// What chord sent under [sessionId], other than subagent updates.
List<Map<String, Object?>> _under(Rig rig, String sessionId) => [
  for (final params in rig.notified('session/update'))
    if (params['sessionId'] == sessionId)
      params['update'] as Map<String, Object?>,
];

void main() {
  _testerAcpChildLifetimes();
  late Rig rig;
  late _Server server;

  void up(FakeAsync async, {bool subagents = true}) {
    server = _Server();
    rig = Rig(async, server: server);
    // Agents that take chord's server over HTTP, as the real ones do.
    rig.init = {
      'protocolVersion': 1,
      'agentCapabilities': {
        'mcpCapabilities': {'http': true},
      },
    };
    rig.initialize({if (subagents) 'subagents': <String, Object?>{}});
  }

  /// Main [caller] opens a child named [name] of the startup agent, with
  /// [prompt] as its first turn; chord's id for it.
  String open(Caller caller, String name, {String prompt = 'go'}) {
    late final OpenAnswer answer;
    caller.window
        .open(
          caller.key,
          SpawnArgs(agent: 'memory', prompt: prompt, name: name),
          caller,
        )
        .then((answered) => answer = answered);
    rig.settle();
    return (answer as Started).id;
  }

  /// [caller] starts a task of the startup agent; its id.
  String spawn(Caller caller, String name) {
    late final SpawnAnswer answer;
    caller.window
        .spawn(caller, SpawnArgs(agent: 'memory', prompt: 'look', name: name))
        .then((answered) => answer = answered);
    rig.settle();
    return (answer as Started).id;
  }

  group('a long-lived child', () {
    test('goes up under <main>/<id>: its update on its own route, its state '
        'running, waiting on the client, running and idle with its stop '
        'reason, each said once', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final id = open(server.mains.single, 'parser');
        final route = '$main/$id';
        final child = rig.agents[1];
        expect(_prompts(child), hasLength(1));

        _update(rig, child, 's2', {
          'sessionUpdate': 'agent_message_chunk',
          'content': _text('reading'),
        });
        // Its first turn, main's message, goes up ahead of what it says.
        expect(_under(rig, route), [
          {
            'sessionUpdate': 'user_message_chunk',
            'content': _text('go'),
            '_meta': {
              'chord/from': {'name': 'main', 'reachable': true},
            },
          },
          {'sessionUpdate': 'agent_message_chunk', 'content': _text('reading')},
        ]);

        child.send(_permission(1, 's2'));
        rig.settle();
        final asked = rig.lines.messages.lastWhere(
          (m) => m['method'] == 'session/request_permission',
        );
        expect((asked['params'] as Map)['sessionId'], route);
        // Main waits on nothing: the ask is the child's.
        expect(
          rig.notified('_chord/session/state').map((s) => s['state']),
          isNot(contains('requires_action')),
        );
        rig.send({
          'jsonrpc': '2.0',
          'id': asked['id'],
          'result': {
            'outcome': {'outcome': 'selected', 'optionId': 'allow'},
          },
        });
        expect(_answers(child)[1]?['result'], {
          'outcome': {'outcome': 'selected', 'optionId': 'allow'},
        });
        _endTurn(rig, child);

        final reports = _reports(rig, main, route);
        expect(_states(reports), [
          {'state': 'idle'},
          {'state': 'running'},
          {'state': 'requires_action'},
          {'state': 'running'},
          {'state': 'idle', 'stopReason': 'end_turn'},
        ]);
        expect(reports.last['title'], 'parser');
        expect(reports.last['capabilities'], {'cancel': <String, Object?>{}});
        expect(reports.last['_meta'], {
          'chord/agent': {'runtime': 'memory'},
        });
        rig.eof();
      });
    });

    test('what it says before it is up is held, then goes in order', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        rig.answerNew = false;
        final caller = server.mains.single;
        caller.window
            .open(
              caller.key,
              const SpawnArgs(agent: 'memory', prompt: 'go', name: 'parser'),
              caller,
            )
            .ignore();
        rig.settle();
        final child = rig.agents[1];
        for (final word in ['one', 'two', 'three']) {
          _update(rig, child, 's2', {
            'sessionUpdate': 'agent_message_chunk',
            'content': _text(word),
          });
        }
        final reports = rig
            .notified('session/update')
            .where((p) => p['sessionId'] == main)
            // Main also gets chord's commands; the route is the child's.
            .where(_routeReport)
            .toList();
        final route =
            (reports.single['update'] as Map<String, Object?>)['sessionId']
                as String;
        expect(_under(rig, route), isEmpty);

        final asked = child.stdin.messages.lastWhere(
          (m) => m['method'] == 'session/new',
        );
        child.send({
          'jsonrpc': '2.0',
          'id': asked['id'],
          'result': {'sessionId': 's2'},
        });
        rig.settle();
        expect(
          [
            for (final update in _under(rig, route))
              if (update['sessionUpdate'] == 'agent_message_chunk')
                (update['content'] as Map)['text'],
          ],
          ['one', 'two', 'three'],
        );
        rig.eof();
      });
    });

    test('a clear resets its route: the last stop reason goes, and the fresh '
        'session goes up under the same id', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final caller = server.mains.single;
        final id = open(caller, 'parser');
        final route = '$main/$id';
        _endTurn(rig, rig.agents[1]);
        expect(_states(_reports(rig, main, route)).last, {
          'state': 'idle',
          'stopReason': 'end_turn',
        });

        caller.window.clear(caller, 'parser').ignore();
        rig.settle();
        expect(_states(_reports(rig, main, route)).last, {'state': 'idle'});

        // The fresh session, the third the agents opened, goes up under the
        // same route.
        final fresh = rig.agents.last;
        final chunks = _under(rig, route).length;
        _update(rig, fresh, 's3', {
          'sessionUpdate': 'agent_message_chunk',
          'content': _text('fresh'),
        });
        expect(_under(rig, route), hasLength(chunks + 1));
        expect((_under(rig, route).last['content'] as Map)['text'], 'fresh');
        rig.eof();
      });
    });

    test('a close says it last, closed and with nothing left to cancel, and '
        'its route goes', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final caller = server.mains.single;
        final id = open(caller, 'parser');
        final route = '$main/$id';
        expect(caller.window.close(caller, 'parser'), isA<Closed>());
        rig.settle();
        final last = _reports(rig, main, route).last;
        expect(last['_meta'], {
          'chord/agent': {'runtime': 'memory', 'closed': true},
        });
        expect(last.containsKey('capabilities'), isFalse);
        final told = _reports(rig, main, route).length;
        // Nothing of it goes up once it is closed.
        _update(rig, rig.agents[1], 's2', {
          'sessionUpdate': 'agent_message_chunk',
          'content': _text('late'),
        });
        expect(_reports(rig, main, route), hasLength(told));
        expect(
          _under(
            rig,
            route,
          ).where((u) => u['sessionUpdate'] == 'agent_message_chunk'),
          isEmpty,
        );
        rig.eof();
      });
    });

    test('one whose agent exits is said gone, its state unknown', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final id = open(server.mains.single, 'parser');
        rig.agents[1]
          ..exit(const Exit(1))
          ..closeStdout()
          ..closeStderr();
        rig.settle();
        final last = _reports(rig, main, '$main/$id').last;
        expect(last['state'], {'state': 'unknown'});
        expect((last['_meta'] as Map)['chord/agent'], {
          'runtime': 'memory',
          'gone': 'exited',
        });
        rig.eof();
      });
    });

    test('closing main says each child closed', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final caller = server.mains.single;
        final id = open(caller, 'parser');
        rig.request('session/close', {'sessionId': main});
        final last = _reports(rig, main, '$main/$id').last;
        expect((last['_meta'] as Map)['chord/agent'], {
          'runtime': 'memory',
          'closed': true,
        });
        rig.eof();
      });
    });

    test('its message to main goes up saying who sent it', () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final caller = server.mains.single;
        final id = open(caller, 'parser');
        final child = server.admitted.values.singleWhere(
          (each) => each.agent == id,
        );
        child.window.message(child, 'found it', () {});
        rig.settle();
        final said = _under(
          rig,
          main,
        ).lastWhere((u) => u['sessionUpdate'] == 'user_message_chunk');
        expect((said['_meta'] as Map)['chord/from'], {
          'name': 'parser',
          'runtime': 'memory',
          'reachable': true,
        });
        rig.eof();
      });
    });
  });

  group('a client that takes no subagents', () {
    test(
      'hears nothing of a child, and its permission is rejected and said',
      () {
        fakeAsync((async) {
          up(async, subagents: false);
          final main = rig.newSession();
          open(server.mains.single, 'parser');
          final child = rig.agents[1];
          _update(rig, child, 's2', {
            'sessionUpdate': 'agent_message_chunk',
            'content': _text('reading'),
          });
          expect(
            rig.notified('session/update').where((p) => p['sessionId'] != main),
            isEmpty,
          );
          expect(
            _under(
              rig,
              main,
            ).where((u) => u['sessionUpdate'] == 'subagent_update'),
            isEmpty,
          );
          child.send(_permission(1, 's2'));
          rig.settle();
          expect(
            rig.lines.messages.where(
              (m) => m['method'] == 'session/request_permission',
            ),
            isEmpty,
          );
          expect(_answers(child)[1]?['result'], {
            'outcome': {'outcome': 'selected', 'optionId': 'deny'},
          });
          expect(
            rig.said,
            contains(
              "chord: refused a subagent's permission: the client takes no "
              'subagents',
            ),
          );
          rig.eof();
        });
      },
    );

    test("a child's form is cancelled and said", () {
      fakeAsync((async) {
        up(async, subagents: false);
        rig.newSession();
        open(server.mains.single, 'parser');
        final child = rig.agents[1];
        child.send({
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'elicitation/create',
          'params': {
            'sessionId': 's2',
            'mode': 'form',
            'message': 'Which?',
            'requestedSchema': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
          },
        });
        rig.settle();
        expect(
          rig.lines.messages.where((m) => m['method'] == 'elicitation/create'),
          isEmpty,
        );
        expect(_answers(child)[4]?['result'], {'action': 'cancel'});
        expect(
          rig.said,
          contains(
            "chord: refused a subagent's form: the client takes no subagents",
          ),
        );
        rig.eof();
      });
    });

    test("a child's plan is answered cancelled and said", () {
      fakeAsync((async) {
        up(async, subagents: false);
        rig.newSession();
        open(server.mains.single, 'parser');
        final child = rig.agents[1];
        _update(rig, child, 's2', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'plan-1',
          'title': 'Plan',
          'status': 'pending',
        });
        child.send({
          'jsonrpc': '2.0',
          'id': 5,
          'method': 'cursor/create_plan',
          'params': {
            'sessionId': 's2',
            'toolCallId': 'plan-1',
            'plan': 'Read, then write.',
            'todos': <Object?>[],
          },
        });
        rig.settle();
        expect(
          rig.lines.messages.where(
            (m) => m['method'] == 'session/request_permission',
          ),
          isEmpty,
        );
        expect(_answers(child)[5]?['result'], {'outcome': 'cancelled'});
        expect(
          rig.said,
          contains(
            "chord: refused a subagent's plan: the client takes no subagents",
          ),
        );
        rig.eof();
      });
    });

    test("a task's permission is rejected and said", () {
      fakeAsync((async) {
        up(async, subagents: false);
        final main = rig.newSession();
        final caller = server.mains.single;
        rig.request('session/prompt', {
          'sessionId': main,
          'prompt': [_text('split it')],
        });
        spawn(caller, 'scan');
        final task = rig.agents[1];
        task.send(_permission(2, 's2'));
        rig.settle();
        expect(
          rig.lines.messages.where(
            (m) => m['method'] == 'session/request_permission',
          ),
          isEmpty,
        );
        expect(_answers(task)[2]?['result'], {
          'outcome': {'outcome': 'selected', 'optionId': 'deny'},
        });
        expect(
          rig.said,
          contains(
            "chord: refused a subagent's permission: the client takes no "
            'subagents',
          ),
        );
        rig.eof();
      });
    });
  });

  group('a client that takes subagents', () {
    test("a child's plan goes to it under the child's route", () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final id = open(server.mains.single, 'parser');
        final child = rig.agents[1];
        _update(rig, child, 's2', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'plan-1',
          'title': 'Plan',
          'status': 'pending',
        });
        child.send({
          'jsonrpc': '2.0',
          'id': 5,
          'method': 'cursor/create_plan',
          'params': {
            'sessionId': 's2',
            'toolCallId': 'plan-1',
            'plan': 'Read, then write.',
            'todos': <Object?>[],
          },
        });
        rig.settle();
        final asked = rig.lines.messages.lastWhere(
          (m) => m['method'] == 'session/request_permission',
        );
        expect((asked['params'] as Map)['sessionId'], '$main/$id');
        expect(_states(_reports(rig, main, '$main/$id')).last, {
          'state': 'requires_action',
        });
        expect(rig.said, isNot(contains(contains('refused'))));
        rig.eof();
      });
    });

    test("a task's permission goes to it under the task's id", () {
      fakeAsync((async) {
        up(async);
        final main = rig.newSession();
        final caller = server.mains.single;
        rig.request('session/prompt', {
          'sessionId': main,
          'prompt': [_text('split it')],
        });
        final id = spawn(caller, 'scan');
        final task = rig.agents[1];
        task.send(_permission(2, 's2'));
        rig.settle();
        final asked = rig.lines.messages.lastWhere(
          (m) => m['method'] == 'session/request_permission',
        );
        expect((asked['params'] as Map)['sessionId'], '$main/$id');
        rig.send({
          'jsonrpc': '2.0',
          'id': asked['id'],
          'result': {
            'outcome': {'outcome': 'selected', 'optionId': 'deny'},
          },
        });
        expect(_answers(task)[2]?['result'], {
          'outcome': {'outcome': 'selected', 'optionId': 'deny'},
        });
        rig.eof();
      });
    });
  });

  test('two sessions whose children ask with one id are asked and answered '
      'apart', () {
    fakeAsync((async) {
      up(async);
      final first = rig.newSession();
      final second = rig.newSession();
      final [a, b] = server.mains;
      final idA = open(a, 'docs');
      final idB = open(b, 'docs');
      final childA = rig.agents[2];
      final childB = rig.agents[3];
      childA.send(_permission(1, 's3'));
      childB.send(_permission(1, 's4'));
      rig.settle();
      final asks = rig.lines.messages
          .where((m) => m['method'] == 'session/request_permission')
          .toList();
      expect(asks, hasLength(2));
      expect(asks[0]['id'], isNot(asks[1]['id']));
      final askOfA = asks.singleWhere(
        (m) => (m['params'] as Map)['sessionId'] == '$first/$idA',
      );
      final askOfB = asks.singleWhere(
        (m) => (m['params'] as Map)['sessionId'] == '$second/$idB',
      );
      rig.send({
        'jsonrpc': '2.0',
        'id': askOfB['id'],
        'result': {
          'outcome': {'outcome': 'selected', 'optionId': 'deny'},
        },
      });
      expect(_answers(childA), isNot(contains(1)));
      expect(_answers(childB)[1]?['result'], {
        'outcome': {'outcome': 'selected', 'optionId': 'deny'},
      });
      expect(_states(_reports(rig, first, '$first/$idA')).last, {
        'state': 'requires_action',
      });
      rig.send({
        'jsonrpc': '2.0',
        'id': askOfA['id'],
        'result': {
          'outcome': {'outcome': 'selected', 'optionId': 'allow'},
        },
      });
      expect(_answers(childA)[1]?['result'], {
        'outcome': {'outcome': 'selected', 'optionId': 'allow'},
      });
      expect(_answers(childB)[1]?['result'], {
        'outcome': {'outcome': 'selected', 'optionId': 'deny'},
      });
      rig.eof();
    });
  });
}

void _testerAcpChildLifetimes() {
  group('CTUI-35 tester: ACP child launch lifetimes', () {
    (_Server, Rig, String, Caller) start(FakeAsync async) {
      final server = _Server();
      final active = Rig(async, server: server);
      active.init = {
        'protocolVersion': 1,
        'agentCapabilities': {
          'mcpCapabilities': {'http': true},
        },
      };
      active.initialize({'subagents': <String, Object?>{}});
      final main = active.newSession();
      return (server, active, main, server.mains.single);
    }

    test(
      'a late client answer after clear cannot settle a fresh same-id child ask',
      () {
        fakeAsync((async) {
          final (_, rig, main, caller) = start(async);
          late OpenAnswer opened;
          caller.window
              .open(
                caller.key,
                const SpawnArgs(agent: 'memory', prompt: 'go', name: 'parser'),
                caller,
              )
              .then((value) => opened = value);
          rig.settle();
          final route = '$main/${(opened as Started).id}';
          final old = rig.agents[1];
          old.send(_permission(1, 's2'));
          rig.settle();
          final oldAsk = rig.lines.messages.lastWhere(
            (m) => m['method'] == 'session/request_permission',
          );
          caller.window.clear(caller, 'parser').ignore();
          rig.settle();
          final fresh = rig.agents.last;
          fresh.send(_permission(1, 's3'));
          rig.settle();
          final freshAsk = rig.lines.messages.lastWhere(
            (m) => m['method'] == 'session/request_permission',
          );
          expect(freshAsk['id'], isNot(oldAsk['id']));
          rig.send({
            'jsonrpc': '2.0',
            'id': oldAsk['id'],
            'result': {
              'outcome': {'outcome': 'selected', 'optionId': 'allow'},
            },
          });
          expect(_answers(fresh), isNot(contains(1)));
          expect(_states(_reports(rig, main, route)).last, {
            'state': 'requires_action',
          });
          rig.send({
            'jsonrpc': '2.0',
            'id': freshAsk['id'],
            'result': {
              'outcome': {'outcome': 'selected', 'optionId': 'deny'},
            },
          });
          expect(_answers(fresh)[1]?['result'], {
            'outcome': {'outcome': 'selected', 'optionId': 'deny'},
          });
          expect(_states(_reports(rig, main, route)).last, {'state': 'idle'});
          rig.eof();
        });
      },
    );

    test(
      'closing a hanging start drops a thousand held updates and ignores its late answer',
      () {
        fakeAsync((async) {
          final (_, rig, main, caller) = start(async);
          rig.answerNew = false;
          caller.window
              .open(
                caller.key,
                const SpawnArgs(agent: 'memory', prompt: 'go', name: 'parser'),
                caller,
              )
              .ignore();
          rig.settle();
          final child = rig.agents[1];
          final route =
              (rig
                          .notified('session/update')
                          .where(_routeReport)
                          .single['update']
                      as Map)['sessionId']
                  as String;
          for (var i = 0; i < 1000; i++) {
            child.send({
              'jsonrpc': '2.0',
              'method': 'session/update',
              'params': {
                'sessionId': 's2',
                'update': {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': _text('界🙂e\u0301 $i'),
                },
              },
            });
          }
          rig.settle();
          expect(_under(rig, route), isEmpty);
          final pending = child.stdin.messages.singleWhere(
            (m) => m['method'] == 'session/new',
          );
          expect(caller.window.close(caller, 'parser'), isA<Closed>());
          rig.settle();
          final reports = _reports(rig, main, route);
          expect(
            (reports.last['_meta'] as Map)['chord/agent'],
            containsPair('closed', true),
          );
          child.send({
            'jsonrpc': '2.0',
            'id': pending['id'],
            'result': {'sessionId': 's2'},
          });
          rig.settle();
          expect(_under(rig, route), isEmpty);
          expect(_reports(rig, main, route), reports);
          rig.eof();
        });
      },
    );
  });
}

/// A report of a child's route, leaving out main's commands update, which
/// chord sends once main is up.
bool _routeReport(Map<String, Object?> params) =>
    (params['update'] as Map)['sessionUpdate'] == 'subagent_update';
