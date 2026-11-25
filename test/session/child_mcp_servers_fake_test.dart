// What a child's `session/new` carries of MCP servers, as the original's
// src/session/agents_host.ts gives each child the place's servers (the
// settings files' and `.mcp.json`'s, by the same precedence as main's) and
// chord's own last, held back where its agent takes none: as that agent's
// `mcpServers: false` in the settings or, for the invoked agent alone,
// `--no-mcp-servers` says, as the original's `startupOf` does. Through the
// launch a call to chord builds and launch_connection's own host, on the
// original's fake.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/acp/traffic.dart';
import 'package:chord/cli.dart';
import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart' hide Cleared;
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/launch_connection.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord/ui/start_state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/dev.dart' show shellWord;
import '../fixtures/fake_harness.dart';

/// The servers, by name and command, a `session/new` gave.
typedef _Given = List<(String, Object?)>;

/// A window launched as `chord fake --agent-command <line>` in a work
/// directory with servers in the user's settings and in `.mcp.json`, and
/// the traffic of each agent process it started, in order.
final class _Rig {
  _Rig(this.connection, this.opened);

  final StartConnection connection;
  final List<TrafficRecorder> opened;

  AgentsHost get host => connection.window! as AgentsHost;

  /// The servers each process's `session/new` carried, in start order.
  List<_Given> get given => [
    for (final traffic in opened)
      for (final message in traffic.heard.whereType<ChordTraffic>().map(
        (t) => t.message,
      ))
        if (message['method'] == 'session/new')
          [
            for (final server
                in (message['params'] as Map)['mcpServers'] as List)
              (
                (server as Map)['name'] as String,
                server['command'] ?? server['type'],
              ),
          ],
  ];

  /// Opens a child of [runtime] and waits for it to connect.
  Future<void> child(String runtime) async {
    final answer = await host.open(
      mainKey,
      SpawnArgs(agent: runtime, prompt: 'text', name: 'kid-$runtime'),
      Caller(role: Role.person, key: mainKey, window: host),
    );
    expect(answer, isA<Started>());
    final child = connection.agents.agents.children.last;
    await _until(
      () =>
          connection.fold.stateOf(child.key)?.start.phase ==
          StartPhase.connected,
    );
  }
}

Future<_Rig> _launched({
  List<String> flags = const [],
  Map<String, Object?> other = const {},
}) async {
  final root = Directory.systemTemp.createTempSync('chord-child-mcp-');
  final home = p.join(root.path, 'home');
  final work = p.join(root.path, 'work');
  Directory(work).createSync(recursive: true);
  final argv = fakeAgentCommand();
  final line = argv.map(shellWord).join(' ');
  File(p.join(home, '.config', 'chord', 'settings.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'mcpServers': {
          'shared': {'command': 'user-shared'},
          'mine': {'command': 'user-mine'},
        },
        'agents': {
          // A second runtime on the same fake, as the settings name it.
          'other': {'command': line, ...other},
        },
      }),
    );
  File(p.join(work, '.mcp.json')).writeAsStringSync(
    jsonEncode({
      'mcpServers': {
        'shared': {'command': 'project-shared'},
        'project': {'command': 'project-own'},
      },
    }),
  );
  final outcome = await runCli(
    ['fake', '--agent-command', line, ...flags],
    stdout: StringBuffer(),
    stderr: StringBuffer(),
    cwd: work,
    home: home,
    environment: {'HOME': home},
    lookup: (command) async => '/bin/$command',
    readSessionRecords: () async => const [],
  );
  expect(outcome.code, 0);
  final isolated = {
    'HOME': home,
    'XDG_CONFIG_HOME': p.join(home, 'config'),
    'XDG_STATE_HOME': p.join(home, 'state'),
    'XDG_CACHE_HOME': p.join(home, 'cache'),
    'PATH': Platform.environment['PATH'] ?? '',
    'CHORD_FAKE_CHILD_RUNTIME': 'fake',
  };
  final opened = <TrafficRecorder>[];
  final pids = <int>[];
  final opener = fakeSessionOpener(pids.add);
  final server = await serveChord();
  final connection = startLaunchConnection(
    outcome.launch!,
    cwd: work,
    stateDirectory: () => p.join(root.path, 'state'),
    server: server,
    owner: Owned(),
    // Only the fake's line starts: a real agent never does.
    open:
        ({
          required command,
          env,
          required cwd,
          required onTraffic,
          required onPermission,
          relay,
          cancellationToken,
        }) {
          if (command != line) {
            throw StateError('not the fake line: $command');
          }
          final traffic = TrafficRecorder();
          opened.add(traffic);
          return opener(
            command: argv,
            env: {...?env, ...isolated},
            cwd: cwd,
            onTraffic: (event) {
              traffic.add(event);
              onTraffic(event);
            },
            onPermission: onPermission,
            relay: relay,
            cancellationToken: cancellationToken,
          );
        },
  );
  addTearDown(() async {
    await connection.close();
    await server.close();
    for (final pid in pids) {
      expect(
        Process.runSync('kill', ['-0', '$pid']).exitCode,
        isNot(0),
        reason: 'every fake is gone with the window',
      );
    }
    root.deleteSync(recursive: true);
  });
  await _until(
    () => connection.fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return _Rig(connection, opened);
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('until');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// The user's and the project's servers, `.mcp.json` over the user's
/// settings for `shared`, which keeps its first place.
const _users = [
  ('shared', 'project-shared'),
  ('mine', 'user-mine'),
  ('project', 'project-own'),
];

/// chord's own server, as the given list ends with it.
const _chord = ('chord', 'http');

void main() {
  _testerChildMcpRestarts();
  final skip = fakeAgentSkip;

  test("a child's session/new carries the directory's servers, chord's "
      'last, as main does', () async {
    final rig = await _launched();
    await rig.child('fake');
    await rig.child('other');
    expect(rig.given, [
      [..._users, _chord],
      [..._users, _chord],
      [..._users, _chord],
    ]);
  }, skip: skip);

  test("a runtime the settings set to mcpServers false is given none, "
      "chord's included, as main still is", () async {
    final rig = await _launched(other: {'mcpServers': false});
    await rig.child('other');
    await rig.child('fake');
    expect(rig.given, [
      [..._users, _chord],
      <(String, Object?)>[],
      [..._users, _chord],
    ]);
  }, skip: skip);

  test('--no-mcp-servers holds every server back from a child of the '
      'invoked agent, not from one of another runtime', () async {
    final rig = await _launched(flags: ['--no-mcp-servers']);
    await rig.child('fake');
    await rig.child('other');
    expect(rig.given, [
      <(String, Object?)>[],
      <(String, Object?)>[],
      [..._users, _chord],
    ]);
  }, skip: skip);
}

void _testerChildMcpRestarts() {
  group('CTUI-35 tester: child MCP across launches', () {
    test(
      'clear retains directory servers but renews chord admission',
      () async {
        final rig = await _launched();
        await rig.child('fake');
        final child = rig.connection.agents.agents.children.single;
        await rig.host.clearByPerson(child.key);
        await _until(
          () =>
              rig.given.length == 3 &&
              rig.connection.fold.stateOf(child.key)?.start.phase ==
                  StartPhase.connected,
        );
        expect(rig.given, List.filled(3, [..._users, _chord]));
        final launches = [
          for (final traffic in rig.opened)
            for (final event in traffic.heard.whereType<ChordTraffic>())
              if (event.message['method'] == 'session/new')
                ((event.message['params'] as Map)['mcpServers'] as List),
        ];
        expect(launches[2].take(3), launches[1].take(3));
        expect(
          (launches[2].last as Map)['headers'],
          isNot((launches[1].last as Map)['headers']),
        );
      },
      skip: fakeAgentSkip,
    );

    test(
      'no-MCP survives invoked-child clear without suppressing other runtime',
      () async {
        final rig = await _launched(flags: ['--no-mcp-servers']);
        await rig.child('fake');
        final child = rig.connection.agents.agents.children.single;
        await rig.host.clearByPerson(child.key);
        await _until(
          () =>
              rig.given.length == 3 &&
              rig.connection.fold.stateOf(child.key)?.start.phase ==
                  StartPhase.connected,
        );
        await rig.child('other');
        expect(rig.given, [
          <(String, Object?)>[],
          <(String, Object?)>[],
          <(String, Object?)>[],
          [..._users, _chord],
        ]);
      },
      skip: fakeAgentSkip,
    );
  });
}
