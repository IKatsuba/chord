// chord acp's turns and asks on the original's fake agent: a whole turn,
// permissions relayed, a failing and a dying agent, an ignored cancel and
// a queue withdrawn.
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

void main() {
  final skip = fakeAgentSkip;
  subagentStops();

  test('a whole turn: its words, then its answer', () async {
    final client = AcpClient();
    await client.initialize();
    final s = await client.newSession();
    final id = client.ask('session/prompt', _prompt(s, 'text'));
    final answered = await client.answer(id);
    expect((answered['result'] as Map)['stopReason'], 'end_turn');
    final said = [
      for (final message in client.lines.messages)
        if (message['id'] == id)
          'answer'
        else if (message['method'] == 'session/update' &&
            ((message['params'] as Map)['update'] as Map)['sessionUpdate'] ==
                'agent_message_chunk')
          'chunk',
    ];
    expect(said.last, 'answer');
    expect(said, contains('chunk'));
    expect(client.notified('_chord/session/state').first, {
      'sessionId': s,
      'state': 'running',
      'origin': 'client',
    });
    expect(client.notified('_chord/session/state').last, {
      'sessionId': s,
      'state': 'idle',
    });
  }, skip: skip);

  test(
    'a permission goes to the client under its id, and its choice back',
    () async {
      final client = AcpClient();
      await client.initialize();
      final s = await client.newSession();
      final id = client.ask('session/prompt', _prompt(s, 'permission'));
      final asked = await client.until(() {
        for (final message in client.lines.messages) {
          if (message['method'] == 'session/request_permission') return message;
        }
        return null;
      });
      expect((asked['params'] as Map)['sessionId'], s);
      client.send({
        'jsonrpc': '2.0',
        'id': asked['id'],
        'result': {
          'outcome': {'outcome': 'selected', 'optionId': 'allow'},
        },
      });
      final answered = await client.answer(id);
      expect((answered['result'] as Map)['stopReason'], 'end_turn');
    },
    skip: skip,
  );

  test('a reviewed permission keeps its chord/permission meta', () async {
    final client = AcpClient();
    await client.initialize();
    final s = await client.newSession();
    client.ask('session/prompt', _prompt(s, 'reviewpermission'));
    final asked = await client.until(() {
      for (final message in client.lines.messages) {
        if (message['method'] == 'session/request_permission') return message;
      }
      return null;
    });
    expect(
      ((asked['params'] as Map)['_meta'] as Map?)?['chord/permission'],
      isNotNull,
    );
  }, skip: skip);

  test('a turn that fails is -32603; one whose agent dies too, with its '
      'last words', () async {
    final client = AcpClient();
    await client.initialize();
    final s = await client.newSession();
    final failed = await client.request('session/prompt', _prompt(s, 'error'));
    expect(failed['error'], {
      'code': -32603,
      'message': 'The fake agent failed on purpose.',
    });
    final crashed = await client.request('session/prompt', _prompt(s, 'crash'));
    final error = crashed['error'] as Map;
    expect(error['code'], -32603);
    expect(error['message'], contains('out of memory'));
    await client.until(() => client.host.sessions.isEmpty ? true : null);
  }, skip: skip);

  test('an agent that ignores a cancel keeps its prompt open until '
      'session/close answers it cancelled; one queued behind it is '
      'withdrawn at once', () async {
    final client = AcpClient();
    await client.initialize();
    final s = await client.newSession();
    final running = client.ask('session/prompt', _prompt(s, 'ignorescancel'));
    final queued = client.ask('session/prompt', _prompt(s, 'text'));
    // Once it says it holds on, the turn is past its first step, which a
    // cancel would still end, as the original's does.
    await client.until(
      () =>
          client.lines.messages.any(
            (message) => '${message['params']}'.contains('Holding on.'),
          )
          ? true
          : null,
    );
    client.send({
      'jsonrpc': '2.0',
      'method': 'session/cancel',
      'params': {'sessionId': s},
    });
    expect((await client.answer(queued))['result'], {
      'stopReason': 'cancelled',
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      client.lines.messages.where(
        (m) => m['id'] == running && !m.containsKey('method'),
      ),
      isEmpty,
    );
    await client.request('session/close', {'sessionId': s});
    expect((await client.answer(running))['result'], {
      'stopReason': 'cancelled',
    });
  }, skip: skip);
  group('tester U11 independent fake sessions', () {
    test(
      'an ignored cancel and close cannot stop another session completing and reusing',
      () async {
        final client = AcpClient();
        await client.initialize();
        final first = await client.newSession();
        final second = await client.newSession();
        final held = client.ask(
          'session/prompt',
          _prompt(first, 'ignorescancel'),
        );
        await client.until(
          () =>
              client
                  .notified('session/update')
                  .any((m) => m['sessionId'] == first)
              ? true
              : null,
        );
        client.send({
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': first},
        });
        final completed = await client.request(
          'session/prompt',
          _prompt(second, 'text'),
        );
        expect((completed['result'] as Map)['stopReason'], 'end_turn');
        await client.request('session/close', {'sessionId': first});
        expect(
          ((await client.answer(held))['result'] as Map)['stopReason'],
          'cancelled',
        );
        final again = await client.request(
          'session/prompt',
          _prompt(second, 'text'),
        );
        expect((again['result'] as Map)['stopReason'], 'end_turn');
      },
      skip: skip,
    );
  });
}

/// Served cancels of an agent's own subagent, on the fake.
void subagentStops() {
  test("a client's cancel of a subagent's session stops it alone, its "
      "parent's turn going on", () async {
    final client = AcpClient();
    await client.initialize({'subagents': <String, Object?>{}});
    final s = await client.newSession();
    final id = client.ask('session/prompt', _prompt(s, 'codexsubagentstop'));
    List<Map<String, Object?>> subagentUpdates() => [
      for (final message in client.lines.messages)
        if (message['method'] == 'session/update')
          if ((message['params'] as Map)['update'] case final Map update
              when update['sessionUpdate'] == 'subagent_update')
            update.cast<String, Object?>(),
    ];
    final child = await client.until(() {
      for (final update in subagentUpdates()) {
        if ((update['capabilities'] as Map?)?['cancel'] != null) {
          return update['sessionId'] as String;
        }
      }
      return null;
    });
    expect(child, isNot(s));
    client.send({
      'jsonrpc': '2.0',
      'method': 'session/cancel',
      'params': {'sessionId': child},
    });
    final answered = await client.answer(id);
    expect((answered['result'] as Map)['stopReason'], 'end_turn');
    expect(
      subagentUpdates().where(
        (update) =>
            update['sessionId'] == child &&
            (update['state'] as Map?)?['stopReason'] == 'cancelled',
      ),
      hasLength(1),
    );
  }, skip: fakeAgentSkip);
}
