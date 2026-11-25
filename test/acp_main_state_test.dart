// chord acp's `_chord/session/state` for main in memory, as the original's
// wire has it: main's own form makes it require action until it is
// answered; a child's asks never touch it, and go on the child's route.
import 'package:chord/acp/process.dart';
import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';

/// chord's server as the host uses it, keeping who was let in.
final class _Server implements ChordServer {
  final admitted = <String, Caller>{};
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
  void revoke(String token) {}

  @override
  Future<void> close() async {}

  /// The caller of the one main session.
  Caller get main =>
      admitted.values.singleWhere((caller) => caller.role == Role.person);
}

Map<String, Object?> _text(String text) => {'type': 'text', 'text': text};

Map<String, Object?> _form(Object id, String sessionId) => {
  'jsonrpc': '2.0',
  'id': id,
  'method': 'elicitation/create',
  'params': {
    'sessionId': sessionId,
    'mode': 'form',
    'message': 'Which file?',
    'requestedSchema': {
      'type': 'object',
      'properties': {
        'file': {'type': 'string'},
      },
    },
  },
};

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

/// Answers the agent's last prompt with `end_turn`.
void _endTurn(Rig rig, MemoryAgentProcess agent) {
  agent.send({
    'jsonrpc': '2.0',
    'id': agent.stdin.messages.lastWhere(
      (m) => m['method'] == 'session/prompt',
    )['id'],
    'result': {'stopReason': 'end_turn'},
  });
  rig.settle();
}

/// chord's last request of [method] to the client.
Map<String, Object?> _lastAsk(Rig rig, String method) =>
    rig.lines.messages.lastWhere((m) => m['method'] == method);

/// The client's answer [result] to chord's request [ask].
void _respond(Rig rig, Map<String, Object?> ask, Object? result) =>
    rig.send({'jsonrpc': '2.0', 'id': ask['id'], 'result': result});

/// Every `_chord/session/state` chord sent of [sessionId].
List<Map<String, Object?>> _states(Rig rig, String sessionId) => [
  for (final params in rig.notified('_chord/session/state'))
    if (params['sessionId'] == sessionId) params,
];

const _accepted = {
  'action': 'accept',
  'content': {'file': 'notes.txt'},
};

void main() {
  late Rig rig;

  void up(FakeAsync async, {_Server? server}) {
    rig = Rig(async, server: server);
    rig.init = {
      'protocolVersion': 1,
      'agentCapabilities': {
        'mcpCapabilities': {'http': true},
      },
    };
    rig.initialize({'subagents': <String, Object?>{}});
  }

  group("main's own form", () {
    test('requires action while it waits in a turn, running once answered '
        'and idle once the turn ends', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        rig.request('session/prompt', {
          'sessionId': s,
          'prompt': [_text('pick one')],
        });
        final agent = rig.agents.single;
        agent.send(_form(9, 's1'));
        rig.settle();
        expect(_states(rig, s).last, {
          'sessionId': s,
          'state': 'requires_action',
          'origin': 'client',
        });
        _respond(rig, _lastAsk(rig, 'elicitation/create'), _accepted);
        expect(_answers(agent)[9]?['result'], _accepted);
        expect(_states(rig, s).last, {
          'sessionId': s,
          'state': 'running',
          'origin': 'client',
        });
        _endTurn(rig, agent);
        expect(_states(rig, s), [
          {'sessionId': s, 'state': 'running', 'origin': 'client'},
          {'sessionId': s, 'state': 'requires_action', 'origin': 'client'},
          {'sessionId': s, 'state': 'running', 'origin': 'client'},
          {'sessionId': s, 'state': 'idle'},
        ]);
        rig.eof();
      });
    });

    test('asked between turns requires action with no origin, and is idle '
        'once answered', () {
      fakeAsync((async) {
        up(async);
        final s = rig.newSession();
        final agent = rig.agents.single;
        agent.send(_form(9, 's1'));
        rig.settle();
        expect(_states(rig, s), [
          {'sessionId': s, 'state': 'requires_action'},
        ]);
        _respond(rig, _lastAsk(rig, 'elicitation/create'), _accepted);
        expect(_answers(agent)[9]?['result'], _accepted);
        expect(_states(rig, s), [
          {'sessionId': s, 'state': 'requires_action'},
          {'sessionId': s, 'state': 'idle'},
        ]);
        rig.eof();
      });
    });
  });

  test("a child's permission and form never change main's state; they "
      "require action on the child's own route", () {
    fakeAsync((async) {
      final server = _Server();
      up(async, server: server);
      final s = rig.newSession();
      rig.request('session/prompt', {
        'sessionId': s,
        'prompt': [_text('split it')],
      });
      final caller = server.main;
      late final OpenAnswer opened;
      caller.window
          .open(
            caller.key,
            const SpawnArgs(agent: 'memory', prompt: 'go', name: 'parser'),
            caller,
          )
          .then((answer) => opened = answer);
      rig.settle();
      final route = '$s/${(opened as Started).id}';
      final child = rig.agents[1];

      child.send(_permission(1, 's2'));
      rig.settle();
      final permission = _lastAsk(rig, 'session/request_permission');
      expect((permission['params'] as Map)['sessionId'], route);
      child.send(_form(2, 's2'));
      rig.settle();
      final form = _lastAsk(rig, 'elicitation/create');
      expect((form['params'] as Map)['sessionId'], route);

      final reports = [
        for (final params in rig.notified('session/update'))
          if (params['update'] case {
            'sessionUpdate': 'subagent_update',
            'sessionId': final String id,
            'state': final Object? state,
          } when params['sessionId'] == s && id == route)
            state,
      ];
      expect(reports.last, {'state': 'requires_action'});

      _respond(rig, permission, {
        'outcome': {'outcome': 'selected', 'optionId': 'allow'},
      });
      _respond(rig, form, _accepted);
      expect(_answers(child)[2]?['result'], _accepted);
      _endTurn(rig, child);
      _endTurn(rig, rig.agents.first);

      // Main's own turn alone, its child's asks nowhere in it.
      expect(_states(rig, s), [
        {'sessionId': s, 'state': 'running', 'origin': 'client'},
        {'sessionId': s, 'state': 'idle'},
      ]);
      expect(_states(rig, route), isEmpty);
      rig.eof();
    });
  });
}
