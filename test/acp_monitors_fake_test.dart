// `chord acp`'s monitors on the fake, as the original's
// tests/acp_extensions_test.ts has them: `monitors: 1` in initialize's
// extensions, `_chord/monitors/changed` with each session's running and
// ended monitors whole, and `_chord/monitors/stop` stopping a session's own
// monitor as its agent's stop_monitor does, a refusal -32002.
@Tags(['fake_agent'])
library;

import 'package:chord/server/server.dart' show serveChord;
import 'package:test/test.dart';

import 'acp_client.dart';
import 'fixtures/fake_harness.dart';

void main() {
  final skip = fakeAgentSkip;

  test("a session's monitors are told as they change, and stopped by "
      'request', () async {
    final server = await serveChord();
    addTearDown(server.close);
    final client = AcpClient(server: server);
    await client.initialize();
    final sessionId = await client.newSession();
    final prompt = client.ask('session/prompt', {
      'sessionId': sessionId,
      'prompt': [
        {'type': 'text', 'text': 'monitors'},
      ],
    });
    List<Map<String, Object?>> changed() => [
      for (final params in client.notified('_chord/monitors/changed'))
        if (params['sessionId'] == sessionId) params,
    ];
    await client.until(
      () => changed().any((c) => (c['running'] as List).length == 2)
          ? true
          : null,
    );
    await client.answer(prompt);
    final running = (changed().last['running'] as List).cast<Map>();
    expect([for (final m in running) m['id']], ['m1', 'm2']);
    expect(running.last, {
      'id': 'm2',
      'description': 'CI run 4812',
      'command': 'sleep 600',
      'startedAt': isA<int>(),
      'timeoutMs': 600000,
      'events': 0,
    });

    final stopped = await client.request('_chord/monitors/stop', {
      'sessionId': sessionId,
      'id': 'm2',
    });
    expect(stopped['result'], {
      'id': 'm2',
      'description': 'CI run 4812',
      'events': 0,
      'ran_ms': isA<int>(),
    });
    await client.until(
      () => (changed().last['ended'] as List).isNotEmpty ? true : null,
    );
    final ended = (changed().last['ended'] as List).single as Map;
    expect(ended['id'], 'm2');
    expect(ended['end'], {'kind': 'stopped'});
    expect(ended['endedAt'], isA<int>());
    expect(
      [for (final m in changed().last['running'] as List) m['id']],
      ['m1'],
    );

    final again = await client.request('_chord/monitors/stop', {
      'sessionId': sessionId,
      'id': 'm2',
    });
    expect(again['error'], {
      'code': -32002,
      'message': 'm2 already ended: stopped',
    });
    final unknown = await client.request('_chord/monitors/stop', {
      'sessionId': 'nobody',
      'id': 'm1',
    });
    expect(unknown['error'], {
      'code': -32002,
      'message': 'Resource not found',
      'data': {'sessionId': 'nobody'},
    });

    // Its close stops the rest, with no news to a client that closed it.
    final told = changed().length;
    await client.request('session/close', {'sessionId': sessionId});
    expect(changed(), hasLength(told));
  }, skip: skip);

  test("a child's monitors are told under its own session, and stopping its "
      "m1 leaves main's m1 running", () async {
    final server = await serveChord();
    addTearDown(server.close);
    final client = AcpClient(server: server, children: true);
    await client.initialize({'subagents': <String, Object?>{}});
    final main = await client.newSession();
    final prompt = client.ask('session/prompt', {
      'sessionId': main,
      'prompt': [
        {'type': 'text', 'text': 'monitorchild'},
      ],
    });
    List<Map<String, Object?>> changed(String sessionId) => [
      for (final params in client.notified('_chord/monitors/changed'))
        if (params['sessionId'] == sessionId) params,
    ];
    // The child's route, as its monitors are told under it.
    final child = await client.until(() {
      for (final params in client.notified('_chord/monitors/changed')) {
        final id = params['sessionId'] as String;
        if (id != main) return id;
      }
      return null;
    });
    expect(child, startsWith('$main/'));
    await client.until(
      () => changed(main).isNotEmpty && changed(child).isNotEmpty ? true : null,
    );
    await client.answer(prompt);
    Map running(String sessionId) =>
        (changed(sessionId).last['running'] as List).single as Map;
    expect(
      [running(main)['id'], running(main)['description']],
      ['m1', 'dev server errors'],
    );
    expect(
      [running(child)['id'], running(child)['description']],
      ['m1', 'parser tests'],
    );

    final stopped = await client.request('_chord/monitors/stop', {
      'sessionId': child,
      'id': 'm1',
    });
    expect((stopped['result'] as Map)['description'], 'parser tests');
    await client.until(
      () => (changed(child).last['running'] as List).isEmpty ? true : null,
    );
    // Main's m1 is its own, still running, and nothing of the child's
    // was told under main.
    expect(running(main)['description'], 'dev server errors');
    expect(
      {
        for (final c in changed(main))
          for (final m in [...c['running'] as List, ...c['ended'] as List])
            (m as Map)['description'],
      },
      {'dev server errors'},
    );
  }, skip: skip);

  group('CTUI-36 tester: ACP monitor owner isolation', () {
    test(
      'two sessions with m1 keep stops and invalid calls separate',
      () async {
        final server = await serveChord();
        addTearDown(server.close);
        final client = AcpClient(server: server);
        await client.initialize();
        final a = await client.newSession(), b = await client.newSession();
        List<Map<String, Object?>> changed(String id) => [
          for (final p in client.notified('_chord/monitors/changed'))
            if (p['sessionId'] == id) p,
        ];
        for (final id in [a, b]) {
          final prompt = client.ask('session/prompt', {
            'sessionId': id,
            'prompt': [
              {'type': 'text', 'text': 'monitors'},
            ],
          });
          await client.until(
            () =>
                changed(id).isNotEmpty &&
                    (changed(id).last['running'] as List).length == 2
                ? true
                : null,
          );
          await client.answer(prompt);
        }
        final invalid = await client.request('_chord/monitors/stop', {
          'sessionId': a,
          'id': null,
        });
        expect((invalid['error'] as Map)['code'], -32602);
        expect((changed(a).last['running'] as List).length, 2);
        final stopped = await client.request('_chord/monitors/stop', {
          'sessionId': a,
          'id': 'm1',
        });
        expect((stopped['result'] as Map)['id'], 'm1');
        await client.until(
          () => (changed(a).last['running'] as List).length == 1 ? true : null,
        );
        expect(
          [
            for (final m in changed(b).last['running'] as List)
              (m as Map)['id'],
          ],
          ['m1', 'm2'],
        );
        await client.request('session/close', {'sessionId': a});
        final late = await client.request('_chord/monitors/stop', {
          'sessionId': a,
          'id': 'm2',
        });
        expect((late['error'] as Map)['code'], -32002);
        expect((late['error'] as Map)['message'], 'Resource not found');
        final other = await client.request('_chord/monitors/stop', {
          'sessionId': b,
          'id': 'm1',
        });
        expect((other['result'] as Map)['id'], 'm1');
      },
      skip: skip,
    );
  });
}
