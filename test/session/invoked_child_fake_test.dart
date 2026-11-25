// chord started as the dev runner's `--fake` starts it, `chord fake
// --agent-command <bun main.ts>`, through the launch a call to chord builds
// and launch_connection's own host and server: the original's fake then
// opens children of `fake` as its src/main.tsx offers them, by
// open_agent, by `/new` and by the fake's `agentsquiet`.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart' hide Cleared;
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/launch_connection.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord/ui/start_state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/dev.dart' show shellWord;
import '../fixtures/fake_harness.dart';

/// Main and its host as a window on `fake --agent-command` has them, and
/// every command an agent was started on.
final class _Rig {
  _Rig(this.connection, this.started);

  final StartConnection connection;
  final List<Object> started;

  AgentsHost get host => connection.window! as AgentsHost;

  Caller get person => Caller(role: Role.person, key: mainKey, window: host);
}

Future<_Rig> _launched() async {
  final root = Directory.systemTemp.createTempSync('chord-invoked-child-');
  final home = p.join(root.path, 'home');
  final work = p.join(root.path, 'work');
  Directory(work).createSync(recursive: true);
  final argv = fakeAgentCommand();
  final line = argv.map(shellWord).join(' ');
  final outcome = await runCli(
    ['fake', '--agent-command', line],
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
    // The fake's children default to codex, which must never start.
    'CHORD_FAKE_CHILD_RUNTIME': 'fake',
  };
  final started = <Object>[];
  final pids = <int>[];
  final opener = fakeSessionOpener(pids.add);
  final server = await serveChord();
  final connection = startLaunchConnection(
    outcome.launch!,
    cwd: work,
    stateDirectory: () => p.join(root.path, 'state'),
    server: server,
    owner: Owned(),
    // Only the --agent-command line starts, and as the fake's argv: any
    // other command, a real agent's above all, is refused before a process.
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
          started.add(command);
          if (command != line) {
            throw StateError('not the --agent-command line: $command');
          }
          return opener(
            command: argv,
            env: {...?env, ...isolated},
            cwd: cwd,
            onTraffic: onTraffic,
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
  return _Rig(connection, started);
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('until');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  _testerInvokedChildren();
  final skip = fakeAgentSkip;

  test('open_agent on fake starts a child on the --agent-command, listed '
      'first among the runtimes', () async {
    final rig = await _launched();
    expect(rig.host.runtimes().first, 'fake');
    final answer = await rig.host.open(
      mainKey,
      const SpawnArgs(agent: 'fake', prompt: 'text', name: 'parser'),
      rig.person,
    );
    expect(answer, isA<Started>());
    final child = rig.connection.agents.agents.children.single;
    expect((child.name, child.runtime), ('parser', 'fake'));
    await _until(
      () =>
          rig.connection.fold.stateOf(child.key)?.start.phase ==
          StartPhase.connected,
    );
    // Main and the child, each on the one line.
    expect(rig.started.length, greaterThanOrEqualTo(2));
    expect(rig.started.toSet(), hasLength(1));
  }, skip: skip);

  test("/new with no agent opens one on main's own", () async {
    final rig = await _launched();
    final shown = <int>[];
    final answer = await rig.host.newTyped('', show: shown.add);
    expect(answer, isA<Started>());
    final child = rig.connection.agents.agents.children.single;
    expect(shown, [child.key]);
    expect(child.runtime, 'fake');
  }, skip: skip);

  test("the fake's agentsquiet opens parser and docs on fake", () async {
    final rig = await _launched();
    expect(rig.connection.conversation.send('agentsquiet'), isTrue);
    await _until(
      () =>
          rig.connection.agents.agents.children.length == 2 &&
          rig.connection.agents.agents.children.every(
            (child) =>
                (rig.connection.fold
                            .stateOf(child.key)
                            ?.transcript
                            .entries
                            .whereType<UserEntry>() ??
                        const <UserEntry>[])
                    .isNotEmpty,
          ),
    );
    expect(
      [
        for (final child in rig.connection.agents.agents.children)
          (child.name, child.runtime),
      ],
      [('parser', 'fake'), ('docs', 'fake')],
    );
  }, skip: skip);
}

void _testerInvokedChildren() {
  group('CTUI-35 tester: invoked child launch isolation', () {
    test(
      'two concurrent children use only the exact invoked line; another runtime starts nothing',
      () async {
        final rig = await _launched();
        final before = rig.started.length;
        final refused = await rig.host.open(
          mainKey,
          const SpawnArgs(agent: 'not-a-runtime', prompt: 'go'),
          rig.person,
        );
        expect(refused, isA<Refused>());
        expect(rig.started, hasLength(before));
        final answers = await Future.wait([
          for (final name in ['parser', 'docs'])
            rig.host.open(
              mainKey,
              SpawnArgs(agent: 'fake', prompt: 'text', name: name),
              rig.person,
            ),
        ]);
        expect(answers.every((answer) => answer is Started), isTrue);
        await _until(
          () => rig.connection.agents.agents.children.every(
            (child) =>
                rig.connection.fold.stateOf(child.key)?.start.phase ==
                StartPhase.connected,
          ),
        );
        expect(
          rig.connection.agents.agents.children.map((child) => child.name),
          ['parser', 'docs'],
        );
        expect(rig.started.toSet(), hasLength(1));
        expect(rig.started.length, before + 2);
        rig.host.close(rig.person, 'parser');
        await _until(() => rig.connection.agents.agents.children.length == 1);
        expect(rig.connection.agents.agents.children.single.name, 'docs');
        expect(
          rig.connection.fold.stateOf(mainKey)!.start.phase,
          StartPhase.connected,
        );
      },
      skip: fakeAgentSkip,
    );
  });
}
