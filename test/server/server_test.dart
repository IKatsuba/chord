// The original's tests/server/server_test.ts for this task's tools, over
// loopback HTTP: admission and its four refusals, per-token tool lists,
// revoke ending sessions and calls in flight, close, and the owner's G2.
import 'dart:async';
import 'dart:io';

import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart';
import 'package:test/test.dart';

import 'fake_window.dart';
import 'mcp_wire.dart';

/// A refusal's body, as the original's SDK answers one.
Map<String, Object?> refusal(String message) => {
  'jsonrpc': '2.0',
  'error': {'code': -32000, 'message': message},
  'id': null,
};

void main() {
  testerServerTests();
  late ChordServer server;
  late FakeWindow window;
  late Caller person;
  late Caller task;

  setUp(() async {
    server = await serveChord();
    window = FakeWindow();
    person = Caller(role: Role.person, key: 0, window: window);
    task = Caller(role: Role.child, key: 0, task: 't1', window: window);
  });
  tearDown(() => server.close());

  test("a session's entry is chord's server over HTTP with its own bearer "
      'token', () {
    final one = server.admit(person);
    final two = server.admit(person);
    expect(server.url, matches(RegExp(r'^http://127\.0\.0\.1:\d+/mcp$')));
    expect(one.token, isNot(two.token));
    expect(one.server, {
      'type': 'http',
      'name': 'chord',
      'url': server.url,
      'headers': [
        {'name': 'Authorization', 'value': 'Bearer ${one.token}'},
      ],
    });
  });

  test('a request without a token, or with one chord never gave, is '
      'refused', () async {
    for (final token in [null, 'nobody']) {
      final reply = await post(server.url, initialize(), token: token);
      expect(reply.status, 401);
      expect(reply.body, refusal('Unknown token'));
    }
  });

  test('a request in no session that is not initialize is refused', () async {
    final token = server.admit(person).token;
    final reply = await post(server.url, rpc('tools/list'), token: token);
    expect(reply.status, 400);
    expect(reply.body, refusal('No session; initialize first'));
  });

  test('a session not opened is not found', () async {
    final token = server.admit(person).token;
    final reply = await post(
      server.url,
      rpc('tools/list'),
      token: token,
      session: 'no-such-session',
    );
    expect(reply.status, 404);
    expect(reply.body, refusal('Session not found'));
  });

  test("a token cannot speak in another token's session", () async {
    final mine = server.admit(person).token;
    final theirs = server.admit(person).token;
    final opened = await open(server.url, mine);
    final reply = await post(
      server.url,
      rpc('tools/list'),
      token: theirs,
      session: opened.session,
    );
    expect(reply.status, 403);
    expect(reply.body, refusal('Session opened with another token'));
  });

  test(
    'initialize says chord, and that its tool list may change (G2)',
    () async {
      final opened = await open(server.url, server.admit(person).token);
      expect(opened.result['serverInfo'], containsPair('name', 'chord'));
      expect((opened.result['capabilities'] as Map)['tools'], {
        'listChanged': true,
      });
    },
  );

  test("each token lists its role's tools; every schema names draft-07 "
      '(G2)', () async {
    Future<List<Map<String, Object?>>> toolsOfToken(String token) async {
      final opened = await open(server.url, token);
      final result = await call(
        server.url,
        token,
        opened.session,
        'tools/list',
      );
      return [
        for (final tool in result['tools'] as List)
          tool as Map<String, Object?>,
      ];
    }

    final mains = await toolsOfToken(server.admit(person).token);
    final tasks = await toolsOfToken(server.admit(task).token);
    expect(
      [for (final t in mains) t['name']],
      [
        'list_agents',
        'get_budgets',
        'list_sessions',
        'list_teams',
        'spawn_task',
        'open_agent',
        'run_team',
        'propose_team',
        'settings',
        'send_message',
        'close_agent',
        'clear_agent',
        'monitor',
        'stop_monitor',
        'list_monitors',
      ],
    );
    expect([for (final t in tasks) t['name']], ['send_message']);
    for (final tool in [...mains, ...tasks]) {
      final schema = tool['inputSchema'] as Map;
      if (const {
        'list_sessions',
        'list_monitors',
        'list_teams',
      }.contains(tool['name'])) {
        expect(schema, {'type': 'object', 'properties': <String, Object?>{}});
      } else {
        expect(
          schema[r'$schema'],
          'http://json-schema.org/draft-07/schema#',
          reason: '${tool['name']}',
        );
      }
    }
    expect((tasks.single['inputSchema'] as Map)['required'], ['text']);
  });

  test("a task's call is served to its session and answered as the tool "
      'says', () async {
    final token = server.admit(task).token;
    final opened = await open(server.url, token);
    window.told = const Refused('The session that started you has closed');
    final refused = await call(
      server.url,
      token,
      opened.session,
      'tools/call',
      {
        'name': 'send_message',
        'arguments': {'text': 'done'},
      },
    );
    expect(refused['isError'], isTrue);
    expect(refused['content'], [
      {'type': 'text', 'text': 'The session that started you has closed'},
    ]);
    expect(
      window.calls.single.error,
      'The session that started you has closed',
    );

    window.closed = const Ended('scan');
    final childToken = server
        .admit(Caller(role: Role.child, key: 0, agent: 'a1', window: window))
        .token;
    final child = await open(server.url, childToken);
    final ended = await call(
      server.url,
      childToken,
      child.session,
      'tools/call',
      {
        'name': 'close_agent',
        'arguments': {'to': 'scan'},
      },
    );
    expect(ended['isError'], anyOf(isNull, isFalse));
    expect(ended['content'], [
      {'type': 'text', 'text': 'scan has already ended'},
    ]);
    expect(ended['structuredContent'], {'ended': 'scan'});
  });

  test("a tool outside the caller's role is a JSON-RPC error (G1)", () async {
    final token = server.admit(task).token;
    final opened = await open(server.url, token);
    final reply = await post(
      server.url,
      rpc('tools/call', {
        'name': 'close_agent',
        'arguments': {'to': 'x'},
      }),
      token: token,
      session: opened.session,
    );
    expect((reply.body as Map)['error'], {
      'code': -32602,
      'message': "Tool 'close_agent' not found",
    });
  });

  test('a revoked token is refused, its sessions end, and a call in flight '
      'ends with them', () async {
    final token = server.admit(person).token;
    final opened = await open(server.url, token);
    window.clearing = Completer();
    final inFlight = post(
      server.url,
      rpc('tools/call', {
        'name': 'clear_agent',
        'arguments': {'to': 'parser'},
      }),
      token: token,
      session: opened.session,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    server.revoke(token);
    await inFlight.timeout(const Duration(seconds: 5));
    final after = await post(
      server.url,
      rpc('tools/list'),
      token: token,
      session: opened.session,
    );
    expect(after.status, 401);
    // Another token is unaffected.
    final other = server.admit(person).token;
    final again = await open(server.url, other);
    expect(
      (await call(server.url, other, again.session, 'tools/list'))['tools'],
      hasLength(15),
    );
  });

  test('a session the agent closes leaves the map', () async {
    final token = server.admit(person).token;
    final opened = await open(server.url, token);
    final deleted = await post(
      server.url,
      null,
      token: token,
      session: opened.session,
      method: 'DELETE',
    );
    expect(deleted.status, 200);
    final after = await post(
      server.url,
      rpc('tools/list'),
      token: token,
      session: opened.session,
    );
    expect(after.status, 404);
    expect(after.body, refusal('Session not found'));
  });

  test('a closed server listens no more', () async {
    final url = server.url;
    await server.close();
    await expectLater(post(url, initialize()), throwsA(isA<SocketException>()));
  });
}

final class _TesterHeldWindow extends FakeWindow {
  final entered = Completer<void>();
  final answer = Completer<ClearAnswer>();

  @override
  Future<ClearAnswer> clear(Caller caller, String to) {
    if (!entered.isCompleted) entered.complete();
    return answer.future;
  }
}

void testerServerTests() {
  group('tester: MCP session and in-flight isolation', () {
    test(
      'revoke ends every owned session after a tool entered its handler',
      () async {
        final server = await serveChord();
        addTearDown(server.close);
        final window = _TesterHeldWindow();
        final caller = Caller(role: Role.person, key: 17, window: window);
        final token = server.admit(caller).token;
        final first = await open(server.url, token);
        final second = await open(server.url, token);
        final other = server.admit(caller).token;
        final survivor = await open(server.url, other);
        final beforeTools = (await call(
          server.url,
          other,
          survivor.session,
          'tools/list',
        ))['tools'];
        expect(beforeTools, isNotEmpty);
        final running = post(
          server.url,
          rpc('tools/call', {
            'name': 'clear_agent',
            'arguments': {'to': 'parser'},
          }),
          token: token,
          session: first.session,
        );
        await window.entered.future.timeout(const Duration(seconds: 5));
        expect(window.answer.isCompleted, isFalse);
        server.revoke(token);
        await running.timeout(const Duration(seconds: 5));
        for (final session in [first.session, second.session]) {
          final own = await post(
            server.url,
            rpc('tools/list'),
            token: token,
            session: session,
          );
          expect(own.status, 401);
          final removed = await post(
            server.url,
            rpc('tools/list'),
            token: other,
            session: session,
          );
          expect(removed.status, 404);
        }
        expect(
          (await call(
            server.url,
            other,
            survivor.session,
            'tools/list',
          ))['tools'],
          beforeTools,
        );
        window.answer.complete(const Cleared('parser', 'fresh'));
      },
    );

    test(
      'long-lived child has eight tools and schema errors never reach the window',
      () async {
        final server = await serveChord();
        addTearDown(server.close);
        final window = FakeWindow();
        final token = server
            .admit(
              Caller(
                role: Role.child,
                key: 2,
                agent: 'child-id',
                window: window,
              ),
            )
            .token;
        final session = await open(server.url, token);
        final listed = await call(
          server.url,
          token,
          session.session,
          'tools/list',
        );
        expect(
          [for (final tool in listed['tools'] as List) (tool as Map)['name']],
          [
            'list_agents',
            'get_budgets',
            'spawn_task',
            'send_message',
            'close_agent',
            'monitor',
            'stop_monitor',
            'list_monitors',
          ],
        );
        for (final arguments in [
          <String, Object?>{},
          {'text': 7},
        ]) {
          final result = await post(
            server.url,
            rpc('tools/call', {'name': 'send_message', 'arguments': arguments}),
            token: token,
            session: session.session,
          );
          final answer = (result.body as Map)['result'] as Map;
          expect(answer['isError'], isTrue);
          final text = ((answer['content'] as List).single as Map)['text'];
          expect(
            text,
            startsWith("Invalid arguments for tool 'send_message':"),
          );
        }
        expect(window.calls, isEmpty);
      },
    );

    test(
      'deleting one session preserves the same token and its other session',
      () async {
        final server = await serveChord();
        addTearDown(server.close);
        final token = server
            .admit(Caller(role: Role.person, key: 1, window: FakeWindow()))
            .token;
        final first = await open(server.url, token);
        final second = await open(server.url, token);
        final beforeTools = (await call(
          server.url,
          token,
          second.session,
          'tools/list',
        ))['tools'];
        expect(beforeTools, isNotEmpty);
        expect(
          (await post(
            server.url,
            null,
            token: token,
            session: first.session,
            method: 'DELETE',
          )).status,
          200,
        );
        expect(
          (await post(
            server.url,
            rpc('tools/list'),
            token: token,
            session: first.session,
          )).status,
          404,
        );
        expect(
          (await call(
            server.url,
            token,
            second.session,
            'tools/list',
          ))['tools'],
          beforeTools,
        );
        expect((await open(server.url, token)).session, isNot(first.session));
      },
    );
  });
}
