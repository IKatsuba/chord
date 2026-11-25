import 'package:chord/acp/process.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';

Map<String, Object?> _options(String current) => {
  'configOptions': [
    {
      'id': 'permission',
      'name': 'Permission',
      'type': 'select',
      'currentValue': current,
      'options': [
        for (final value in ['read-only', 'full-access'])
          {'value': value, 'name': value},
      ],
    },
  ],
};

void _move(MemoryAgentProcess agent, String id, String value) => agent.send({
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {
    'sessionId': id,
    'update': {'sessionUpdate': 'config_option_update', ..._options(value)},
  },
});

List<Map<String, Object?>> _notices(Rig rig) => [
  for (final params in rig.notified('session/update'))
    if ((params['update'] as Map)['sessionUpdate'] == 'notice') params,
];

Rig _up(FakeAsync async) {
  final rig = Rig(async, agent: 'dimcode');
  rig.newAnswer = _options('read-only');
  rig.initialize({
    'session': {'notices': <String, Object?>{}},
  });
  return rig;
}

void main() {
  group('tester CTUI-101: ACP notice session isolation', () {
    test(
      'another session id on an agent process cannot trigger its notice',
      () {
        fakeAsync((async) {
          final rig = _up(async);
          final first = rig.newSession();
          final second = rig.newSession();
          _move(rig.agents.first, 's2', 'full-access');
          rig.settle();
          expect(_notices(rig), isEmpty);
          _move(rig.agents.first, 's1', 'full-access');
          rig.settle();
          expect(_notices(rig).map((n) => n['sessionId']), [first]);
          _move(rig.agents.last, 's2', 'full-access');
          rig.settle();
          expect(_notices(rig).map((n) => n['sessionId']), [first, second]);
          rig.eof();
          expect(rig.agents.every((a) => a.exited), isTrue);
        });
      },
    );

    test('a burst of option changes stays once per independent entry', () {
      fakeAsync((async) {
        final rig = _up(async);
        final ids = [rig.newSession(), rig.newSession()];
        for (var i = 0; i < 1000; i++) {
          for (var agent = 0; agent < 2; agent++) {
            _move(
              rig.agents[agent],
              's${agent + 1}',
              i.isEven ? 'full-access' : 'read-only',
            );
          }
        }
        rig.settle();
        expect(_notices(rig).map((n) => n['sessionId']), ids);
        expect(
          rig.said.where((s) => s.contains('dimcode may start')),
          hasLength(2),
        );
        rig.eof();
      });
    });

    test('a hanging prompt can be cancelled without losing a later notice', () {
      fakeAsync((async) {
        final rig = _up(async);
        final id = rig.newSession();
        rig.request('session/prompt', {
          'sessionId': id,
          'prompt': [
            {'type': 'text', 'text': 'hang'},
          ],
        });
        rig.send({
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': id},
        });
        _move(rig.agents.single, 's1', 'full-access');
        rig.settle();
        expect(_notices(rig).map((n) => n['sessionId']), [id]);
        rig.eof();
        expect(rig.agents.single.exited, isTrue);
      });
    });
  });
}
