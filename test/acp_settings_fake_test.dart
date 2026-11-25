// chord acp's config, mode, title and account methods on the original's
// fake agent.
@Tags(['fake_agent'])
library;

import 'package:test/test.dart';

import 'acp_client.dart';
import 'fixtures/fake_harness.dart';

List<Object?> _kinds(AcpClient client, String sessionId) => [
  for (final n in client.notified('session/update'))
    if (n['sessionId'] == sessionId) (n['update'] as Map)['sessionUpdate'],
];

void main() {
  final skip = fakeAgentSkip;

  test('set_config_option answers the whole list, moved', () async {
    final client = AcpClient();
    await client.initialize();
    final s = await client.newSession();
    final answered = await client.request('session/set_config_option', {
      'sessionId': s,
      'configId': 'effort',
      'value': 'high',
    });
    final options = (answered['result'] as Map)['configOptions'] as List;
    expect(
      options.firstWhere((o) => (o as Map)['id'] == 'effort'),
      containsPair('currentValue', 'high'),
    );
  }, skip: skip);

  test(
    'a refused set is that request\'s error, and no notice nor line',
    () async {
      final client = AcpClient(flags: ['--refuse-config']);
      await client.initialize({
        'session': {'notices': <String, Object?>{}},
      });
      final s = await client.newSession();
      final answered = await client.request('session/set_config_option', {
        'sessionId': s,
        'configId': 'effort',
        'value': 'high',
      });
      expect(
        (answered['error'] as Map)['message'],
        contains('holds its effort'),
      );
      expect(client.said, isEmpty);
      expect(_kinds(client, s), isNot(contains('notice')));
    },
    skip: skip,
  );

  test('set_mode answers {}, and the change goes as the one shape', () async {
    final client = AcpClient();
    await client.initialize();
    final s = await client.newSession();
    final answered = await client.request('session/set_mode', {
      'sessionId': s,
      'modeId': 'plan',
    });
    expect(answered['result'], <String, Object?>{});
    await client.until(() {
      for (final n in client.notified('session/update')) {
        final update = n['update'] as Map;
        if (update['sessionUpdate'] != 'config_option_update') continue;
        for (final option in update['configOptions'] as List) {
          if ((option as Map)['category'] == 'mode' &&
              option['currentValue'] == 'plan') {
            return true;
          }
        }
      }
      return null;
    });
    expect(_kinds(client, s), isNot(contains('current_mode_update')));
  }, skip: skip);

  test('set_title on a live session keeps the agent\'s answer', () async {
    final client = AcpClient(flags: ['--set-title', 'echo']);
    await client.initialize();
    final s = await client.newSession();
    final answered = await client.request('session/set_title', {
      'sessionId': s,
      'title': '  Fix   the parser ',
    });
    expect(answered['result'], {'title': 'Fix the parser'});
  }, skip: skip);

  test('auth/status is the session\'s account once heard, told once', () async {
    final client = AcpClient(flags: ['--auth-status', 'authenticated']);
    await client.initialize();
    expect((await client.request('auth/status'))['result'], {
      'state': 'unknown',
    });
    await client.newSession();
    final told = await client.until(() {
      final updates = client.notified('auth/status_update');
      return updates.isEmpty ? null : updates;
    });
    expect(told.single['state'], 'authenticated');
    expect(
      ((await client.request('auth/status'))['result'] as Map)['state'],
      'authenticated',
    );
  }, skip: skip);
}
