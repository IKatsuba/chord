// dimcode's notice under chord acp: once per session entry, on stderr and
// as a relayed `notice` update, for main or any of its children (the
// original's src/acp_agent.ts:743-769 and tests/acp_agent_test.ts).
import 'package:chord/acp/process.dart';
import 'package:chord/notices.dart';
import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';

/// chord's server as the host uses it, keeping who was let in.
final class _Server implements ChordServer {
  final admitted = <Caller>[];

  @override
  String get url => 'http://127.0.0.1:9/mcp';

  @override
  Admitted admit(Caller caller) {
    admitted.add(caller);
    return (
      token: 'token-${admitted.length}',
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

  Caller get main => admitted.firstWhere((c) => c.role == Role.person);
}

Map<String, Object?> _options(String current) => {
  'configOptions': [
    {
      'id': 'permission',
      'name': 'Permission',
      'type': 'select',
      'currentValue': current,
      'options': [
        for (final v in ['read-only', 'workspace-write', 'full-access'])
          {'value': v, 'name': v},
      ],
    },
  ],
};

const _notice = {
  'sessionUpdate': 'notice',
  'severity': 'warning',
  'title': 'dimcode can start other agents',
};

/// The notices chord sent under [sessionId].
List<Map<String, Object?>> _notices(Rig rig, String sessionId) => [
  for (final params in rig.notified('session/update'))
    if (params['sessionId'] == sessionId)
      if (params['update'] case final Map<String, Object?> update
          when update['sessionUpdate'] == 'notice')
        update,
];

/// The stderr lines that are the notice's paragraphs.
List<String> _said(Rig rig) => [
  for (final line in rig.said)
    if (line.contains('dimcode may start') || line.contains('externalAgents'))
      line,
];

void _move(Rig rig, MemoryAgentProcess agent, String sessionId, String at) {
  agent.send({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {
      'sessionId': sessionId,
      'update': {'sessionUpdate': 'config_option_update', ..._options(at)},
    },
  });
  rig.settle();
}

void main() {
  late Rig rig;
  late _Server server;

  void up(
    FakeAsync async, {
    String agent = 'dimcode',
    String at = 'read-only',
    bool notices = true,
  }) {
    server = _Server();
    rig = Rig(async, server: server, agent: agent);
    rig.init = {
      'protocolVersion': 1,
      'agentCapabilities': {
        'mcpCapabilities': {'http': true},
      },
    };
    rig.newAnswer = _options(at);
    rig.initialize({
      'subagents': <String, Object?>{},
      if (notices) 'session': {'notices': <String, Object?>{}},
    });
  }

  test('at risk from the start: stderr and one notice, after the answer', () {
    fakeAsync((async) {
      up(async, at: 'full-access');
      final main = rig.newSession();

      expect(_said(rig), [
        for (final paragraph in dimcodeWords.paragraphs) 'chord: $paragraph',
      ]);
      expect(_notices(rig, main), [
        {..._notice, 'description': dimcodeWords.paragraphs.join('\n\n')},
      ]);
      // Nothing of the session goes before the client has its id.
      final messages = rig.lines.messages;
      final answered = messages.indexWhere(
        (m) =>
            !m.containsKey('method') &&
            m['result'] is Map &&
            (m['result'] as Map)['sessionId'] == main,
      );
      final noticed = messages.indexWhere(
        (m) =>
            m['method'] == 'session/update' &&
            ((m['params'] as Map)['update'] as Map)['sessionUpdate'] ==
                'notice',
      );
      expect(answered, lessThan(noticed));
      rig.eof();
    });
  });

  test('moved out of read-only it is said then, and once however it moves', () {
    fakeAsync((async) {
      up(async);
      final main = rig.newSession();
      expect(_notices(rig, main), isEmpty);

      _move(rig, rig.agents.single, 's1', 'workspace-write');
      _move(rig, rig.agents.single, 's1', 'read-only');
      _move(rig, rig.agents.single, 's1', 'full-access');

      expect(_notices(rig, main), hasLength(1));
      expect(_said(rig), hasLength(2));
      rig.eof();
    });
  });

  test('another agent at full-access says nothing of it', () {
    fakeAsync((async) {
      up(async, agent: 'memory', at: 'full-access');
      final main = rig.newSession();

      expect(_notices(rig, main), isEmpty);
      expect(_said(rig), isEmpty);
      rig.eof();
    });
  });

  test('a child at risk says it under main, once for the session', () {
    fakeAsync((async) {
      up(async);
      final main = rig.newSession();
      expect(_notices(rig, main), isEmpty);

      // The children's sessions come up at full-access.
      rig.newAnswer = _options('full-access');
      final caller = server.main;
      caller.window.open(
        caller.key,
        const SpawnArgs(agent: 'dimcode', prompt: 'go', name: 'parser'),
        caller,
      );
      rig.settle();
      caller.window.spawn(
        caller,
        const SpawnArgs(agent: 'dimcode', prompt: 'look', name: 'scout'),
      );
      rig.settle();

      expect(rig.agents, hasLength(3));
      expect(_notices(rig, main), hasLength(1));
      expect(_said(rig), hasLength(2));
      rig.eof();
    });
  });

  test('a task moved out of read-only says it too', () {
    fakeAsync((async) {
      up(async);
      final main = rig.newSession();
      final caller = server.main;
      caller.window.spawn(
        caller,
        const SpawnArgs(agent: 'dimcode', prompt: 'look', name: 'scout'),
      );
      rig.settle();
      expect(_notices(rig, main), isEmpty);

      _move(rig, rig.agents[1], 's2', 'full-access');

      expect(_notices(rig, main), hasLength(1));
      rig.eof();
    });
  });

  test('a client that takes no notices still has stderr', () {
    fakeAsync((async) {
      up(async, at: 'full-access', notices: false);
      final main = rig.newSession();

      expect(_notices(rig, main), isEmpty);
      expect(_said(rig), hasLength(2));
      rig.eof();
    });
  });

  test('each session entry says it of its own', () {
    fakeAsync((async) {
      up(async, at: 'full-access');
      final first = rig.newSession();
      final second = rig.newSession();

      expect(_notices(rig, first), hasLength(1));
      expect(_notices(rig, second), hasLength(1));
      expect(_said(rig), hasLength(4));
      rig.eof();
    });
  });
}
