// get_budgets through the host: a window that reads none answers none, and
// the original fake's `resources` scenario reads the fixture providers
// through chord's own server over HTTP, never an installed provider.
@Tags(['fake_agent'])
library;

import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/platform/resources.dart';
import 'package:chord/server/server.dart' show serveChord;
import 'package:chord/server/tools.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/budgets.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/resource_access.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import '../fixtures/runtimes.dart';
import '../server/mcp_wire.dart';
import 'agents_host_test.dart' show until;

/// Main on the fake with chord's own server and [resources], as the window
/// has them.
Future<(StartConnection, AgentsHost)> _served(ReadLimits? resources) async {
  final server = await serveChord();
  final runtimes = TestRuntimes();
  final connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: runtimes.home.path,
    agent: 'fake',
    open: runtimes.opener,
  );
  final host = AgentsHost(
    runtimeNames: const ['fake'],
    startupOf: (runtime) => runtime == 'fake'
        ? SessionStart(command: runtimes.commandOf('fake'))
        : null,
    openChildSession: connection.openChild,
    agents: connection.agents,
    opened: (key) => connection.fold.dispatch(AgentOpened(key)),
    closed: (key, front) => connection.fold.dispatch(SessionClosed(key, front)),
    server: server,
    resources: resources,
  );
  connection
    ..server = server
    ..window = host
    ..start();
  addTearDown(() async {
    await connection.close();
    await server.close();
    runtimes.dispose();
  });
  await until(
    () => connection.fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return (connection, host);
}

/// An official reader that fails the test if anything reaches it.
final class _Never implements ResourceCollectors {
  @override
  Future<ResourceExecutable> resolve(
    String provider,
    String cwd,
    bool customCommand,
    CancellationToken cancelled,
  ) => throw TestFailure('an official reader was resolved: $provider');

  @override
  Future<Never> read(
    String provider,
    String path,
    String cwd,
    CancellationToken cancelled,
  ) => throw TestFailure('an official reader was read: $provider');
}

void main() {
  group('CTUI-37 tester: hosted budget cancellation', () {
    test(
      'MCP cancellation reaches its hosted read and leaves the session usable',
      () async {
        final entered = Completer<CancellationToken>();
        final (_, host) = await _served((agents, place, cancelled) {
          entered.complete(cancelled);
          return Completer<({String readAt, List<ProviderLimits> providers})>()
              .future
              .asCancellable(cancelled);
        });
        final server = await serveChord();
        addTearDown(server.close);
        final token = server
            .admit(Caller(role: Role.person, key: mainKey, window: host))
            .token;
        final session = await open(server.url, token);
        final request = rpc('tools/call', {
          'name': 'get_budgets',
          'arguments': <String, Object?>{},
        });
        final running = post(
          server.url,
          request,
          token: token,
          session: session.session,
        );
        final cancelled = await entered.future.timeout(
          const Duration(seconds: 5),
        );
        await post(
          server.url,
          {
            'jsonrpc': '2.0',
            'method': 'notifications/cancelled',
            'params': {
              'requestId': request['id'],
              'reason': 'tester cancelled',
            },
          },
          token: token,
          session: session.session,
        );
        // MCP cancellation intentionally gives the cancelled request no reply.
        running.ignore();
        await until(() => cancelled.isCancelled);
        expect(cancelled.isCancelled, isTrue);
        expect(
          (await call(
            server.url,
            token,
            session.session,
            'tools/list',
          ))['tools'],
          isNotEmpty,
        );
      },
      skip: fakeAgentSkip,
    );
  });

  setUp(() {
    final before = officialCollectors;
    officialCollectors = _Never();
    addTearDown(() => officialCollectors = before);
  });

  test('a host given no readers reads none, resolving nothing', () async {
    final (_, host) = await _served(null);
    expect(
      host.budgets(
        Caller(role: Role.person, key: mainKey, window: host),
        null,
        CancellationToken(),
      ),
      isNull,
    );
  }, skip: fakeAgentSkip);

  test("the fake's resources reads the fixture providers over HTTP, drawn "
      'as Resources', () async {
    final (connection, _) = await _served(
      createResources(const FixtureCollectors('partial')).read,
    );
    expect(connection.conversation.send('resources'), isTrue);
    ToolCall? budgets() {
      for (final entry
          in connection.fold.stateOf(mainKey)?.transcript.entries ??
              const <Entry>[]) {
        if (entry is ToolEntry &&
            entry.call.chord?.tool == ChordTool.getBudgets &&
            entry.call.chord?.answer != null) {
          return entry.call;
        }
      }
      return null;
    }

    await until(() => budgets() != null);
    final answer = budgets()!.chord!.answer! as Map<String, Object?>;
    final providers = answer['providers']! as List;
    expect(
      [for (final p in providers) (p as Map)['agent']],
      ['claude', 'codex'],
    );
    expect(
      [for (final w in (providers.first as Map)['windows'] as List) w['name']],
      ['five_hour', 'seven_day'],
    );
  }, skip: fakeAgentSkip);
}
