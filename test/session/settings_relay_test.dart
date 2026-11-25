import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:test/test.dart';
import 'settings_test.dart' show select, value;

void main() {
  for (final config in [false, true]) {
    for (final reported in [false, true]) {
      test('empty mode ACK config=$config reported=$reported', () {
        final relay = enricherRelay(m1Enrichers);
        relay.fromChord({'id': 1, 'method': 'session/new', 'params': {}});
        final options = [
          select('permissions', 'mode', [
            value('default'),
            value('plan'),
          ], current: 'default'),
        ];
        relay.fromAgent({
          'id': 1,
          'result': {
            'sessionId': 's',
            if (config) 'configOptions': options,
            'modes': {
              'currentModeId': 'default',
              'availableModes': [
                {'id': 'default', 'name': 'Default'},
                {'id': 'plan', 'name': 'Plan'},
              ],
            },
          },
        });
        relay.fromChord({
          'id': 2,
          'method': config ? 'session/set_config_option' : 'session/set_mode',
          'params': {
            'sessionId': 's',
            if (config) ...{
              'configId': 'permissions',
              'value': 'plan',
            } else
              'modeId': 'plan',
          },
        });
        if (reported) {
          relay.fromAgent({
            'method': 'session/update',
            'params': {
              'sessionId': 's',
              'update': {
                'sessionUpdate': 'current_mode_update',
                'currentModeId': 'default',
              },
            },
          });
        }
        final answer = relay.fromAgent({'id': 2, 'result': {}});
        if (reported) {
          expect(answer, [
            {'id': 2, 'result': {}},
          ]);
        } else if (config) {
          final result = answer.single['result'] as Map;
          expect(
            (result['configOptions'] as List).single['currentValue'],
            'plan',
          );
          expect((result['_meta'] as Map)[filledKey], ['configOptions']);
        } else {
          expect(answer, hasLength(2));
          final update = (answer.first['params'] as Map)['update'] as Map;
          expect(update['currentModeId'], 'plan');
          expect((update['_meta'] as Map)[filledKey], ['currentModeId']);
        }
      });
    }
  }
  test('mode read-back preserves refused and nonempty agent answers', () {
    final wire = Wire(
      asked: {
        '2': const Asked('session/set_mode', {
          'sessionId': 's',
          'modeId': 'plan',
        }),
      },
    );
    final refused = <String, Object?>{
      'id': 2,
      'error': {'code': -1, 'message': 'no'},
    };
    expect(modeReadBack(refused, wire).single, same(refused));
  });
}
