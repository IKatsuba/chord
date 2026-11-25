// chord acp relays an agent's plan to its client as an ordinary permission,
// from the original's tests/acp_agent_test.ts "a plan ask", on the
// original's fake agent.
@Tags(['fake_agent'])
library;

import 'package:test/test.dart';

import 'acp_client.dart';
import 'fixtures/fake_harness.dart';

Map<String, Object?> _prompt(String sessionId, String text) => {
  'sessionId': sessionId,
  'prompt': [
    {'type': 'text', 'text': text},
  ],
};

Map<String, Object?> _selected(String optionId) => {
  'outcome': {'outcome': 'selected', 'optionId': optionId},
};

/// What the agent said in [sessionId], its message chunks joined.
String _said(AcpClient client, String sessionId) => [
  for (final message in client.lines.messages)
    if (message['method'] == 'session/update' &&
        (message['params'] as Map)['sessionId'] == sessionId &&
        ((message['params'] as Map)['update'] as Map)['sessionUpdate'] ==
            'agent_message_chunk')
      (((message['params'] as Map)['update'] as Map)['content'] as Map)['text'],
].join();

Future<Map<String, Object?>> _asked(AcpClient client) => client.until(() {
  for (final message in client.lines.messages) {
    if (message['method'] == 'session/request_permission') return message;
  }
  return null;
});

void main() {
  final skip = fakeAgentSkip;

  group('a plan ask', () {
    for (final (scenario, choice, heard) in [
      ('cursorplan', 'accepted', 'accepted'),
      ('cursorplan', 'kept', 'rejected'),
      ('grokplan', 'accepted', 'approved'),
      ('grokplan', 'left', 'abandoned'),
    ]) {
      test('$scenario: $choice reaches the agent in its own words', () async {
        final client = AcpClient();
        await client.initialize();
        final s = await client.newSession();
        final running = client.ask('session/prompt', _prompt(s, scenario));
        final ask = await _asked(client);
        final params = ask['params'] as Map;
        expect(params['sessionId'], s);
        expect(
          (params['options'] as List).first,
          equals({
            'optionId': 'accepted',
            'name': 'Yes, accept the plan',
            'kind': 'allow_once',
          }),
        );
        expect(
          (params['options'] as List).any(
            (o) => (o as Map)['optionId'] == 'left',
          ),
          scenario == 'grokplan',
        );
        client.send({
          'jsonrpc': '2.0',
          'id': ask['id'],
          'result': _selected(choice),
        });
        await client.answer(running);
        expect(_said(client, s), contains('Plan answer:'));
        expect(_said(client, s).toLowerCase(), contains(heard));
      });
    }

    for (final (name, answer) in [
      (
        'a cancel',
        {
          'outcome': {'outcome': 'cancelled'},
        },
      ),
      ('an unknown id', _selected('yes-please')),
      ("cursor's left, which it is not offered", _selected('left')),
    ]) {
      test('$name is never a yes', () async {
        final client = AcpClient();
        await client.initialize();
        final s = await client.newSession();
        final running = client.ask('session/prompt', _prompt(s, 'cursorplan'));
        final ask = await _asked(client);
        client.send({'jsonrpc': '2.0', 'id': ask['id'], 'result': answer});
        await client.answer(running);
        expect(
          _said(client, s),
          contains('Plan answer: {"outcome":"cancelled"}'),
        );
      });
    }

    test('an error is never a yes', () async {
      final client = AcpClient();
      await client.initialize();
      final s = await client.newSession();
      final running = client.ask('session/prompt', _prompt(s, 'cursorplan'));
      final ask = await _asked(client);
      client.send({
        'jsonrpc': '2.0',
        'id': ask['id'],
        'error': {'code': -32603, 'message': 'no'},
      });
      await client.answer(running);
      expect(
        _said(client, s),
        contains('Plan answer: {"outcome":"cancelled"}'),
      );
    });
  }, skip: skip);

  group('tester: relayed plan cancellation ownership', skip: fakeAgentSkip, () {
    for (final scenario in ['cursorplan', 'grokplan']) {
      test(
        '$scenario cancellation withdraws the client ask and ignores a late yes',
        () async {
          final client = AcpClient();
          await client.initialize();
          final session = await client.newSession();
          final running = client.ask(
            'session/prompt',
            _prompt(session, scenario),
          );
          final ask = await _asked(client);
          client.send({
            'jsonrpc': '2.0',
            'method': 'session/cancel',
            'params': {'sessionId': session},
          });
          await client.until(
            () =>
                client
                    .notified(r'$/cancel_request')
                    .any((p) => p['requestId'] == ask['id'])
                ? true
                : null,
          );
          await client.answer(running);
          client.send({
            'jsonrpc': '2.0',
            'id': ask['id'],
            'result': _selected('accepted'),
          });
          await client.request('session/prompt', _prompt(session, 'planheard'));
          expect(
            _said(client, session),
            contains('Plan answer: {"outcome":"cancelled"}'),
          );
          expect(
            _said(client, session),
            isNot(contains('"outcome":"approved"')),
          );
          expect(
            _said(client, session),
            isNot(contains('"outcome":"accepted"')),
          );
        },
      );
    }

    test('closing one session never settles the other session plan', () async {
      final client = AcpClient();
      await client.initialize();
      final first = await client.newSession(),
          second = await client.newSession();
      final a = client.ask('session/prompt', _prompt(first, 'cursorplan'));
      final b = client.ask('session/prompt', _prompt(second, 'grokplan'));
      final asks = await client.until(() {
        final all = client.lines.messages
            .where((m) => m['method'] == 'session/request_permission')
            .toList();
        return all.length == 2 ? all : null;
      });
      final askA = asks.singleWhere(
        (m) => (m['params'] as Map)['sessionId'] == first,
      );
      final askB = asks.singleWhere(
        (m) => (m['params'] as Map)['sessionId'] == second,
      );
      expect(askA['id'], isNot(askB['id']));
      await client.request('session/close', {'sessionId': first});
      expect(client.notified(r'$/cancel_request'), [
        {'requestId': askA['id']},
      ]);
      client.send({
        'jsonrpc': '2.0',
        'id': askA['id'],
        'result': _selected('accepted'),
      });
      client.send({
        'jsonrpc': '2.0',
        'id': askB['id'],
        'result': _selected('kept'),
      });
      await client.answer(a);
      await client.answer(b);
      expect(
        _said(client, second),
        contains('Plan answer: {"outcome":"revise"}'),
      );
      expect(client.notified(r'$/cancel_request'), [
        {'requestId': askA['id']},
      ]);
    });
  });
}
