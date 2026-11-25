@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/agents.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/launch_connection.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

import '../tool/dev.dart' show shellWord;
import 'fixtures/fake_harness.dart';

Future<void> until(StartConnection connection, bool Function() matches) async {
  if (matches()) return;
  final done = Completer<void>();
  void changed() {
    if (matches() && !done.isCompleted) done.complete();
  }

  connection.app.addListener(changed);
  try {
    await done.future.timeout(const Duration(seconds: 20));
  } finally {
    connection.app.removeListener(changed);
  }
}

void main() {
  group(
    'tester CTUI-45: launch helper with misbehaving agents',
    skip: fakeAgentSkip,
    () {
      Future<StartConnection> launch({
        List<String> flags = const [],
        TrafficRecorder? traffic,
      }) async {
        final directory = Directory.systemTemp.createTempSync(
          'chord-cli-tester-',
        );
        final catalog = findAgent('codex')!;
        final fake = KnownAgent(
          name: catalog.name,
          title: catalog.title,
          start: AgentStart(fakeAgentCommand(null, flags), const {
            'FIXTURE_START': 'catalog',
          }),
          runner: catalog.runner,
          install: catalog.install,
        );
        final outcome = await runCli(
          ['codex'],
          stdout: StringBuffer(),
          stderr: StringBuffer(),
          cwd: directory.path,
          home: null,
          lookup: (_) async => 'found',
          find: (_) => fake,
        );
        expect(outcome.code, 0);
        final pids = <int>[];
        final connection = startLaunchConnection(
          outcome.launch!,
          cwd: directory.path,
          stateDirectory: () => directory.path,
          open:
              ({
                required command,
                env,
                required cwd,
                required onTraffic,
                required onPermission,
                relay,
                cancellationToken,
              }) => fakeSessionOpener(pids.add)(
                command: command,
                env: env,
                cwd: cwd,
                onTraffic: (event) {
                  traffic?.add(event);
                  onTraffic(event);
                },
                onPermission: onPermission,
                relay: relay,
                cancellationToken: cancellationToken,
              ),
          owner: Owned(),
        );
        addTearDown(() async {
          await connection.close();
          expect(pids, hasLength(1));
          for (final pid in pids) {
            expect(
              Process.runSync('kill', ['-0', '$pid']).exitCode,
              isNot(0),
              reason: 'the launch helper must close its fake',
            );
          }
          directory.deleteSync(recursive: true);
        });
        await until(
          connection,
          () => connection.app.value.start.phase == StartPhase.connected,
        );
        return connection;
      }

      test(
        'cancelling one simultaneous launch leaves the other able to reply',
        () async {
          final connections = await Future.wait([launch(), launch()]);
          final slow = connections[0];
          final normal = connections[1];
          expect(slow.conversation.send('slow'), isTrue);
          await until(
            slow,
            () => slow.app.value.transcript.entries.length >= 2,
          );
          slow.conversation.interrupt();
          expect(normal.conversation.send('text'), isTrue);
          await until(
            slow,
            () =>
                slow.app.value.transcript.turn is Idle &&
                slow.app.value.transcript.entries.any(
                  (entry) => entry is CancelledEntry,
                ),
          );
          await until(
            normal,
            () =>
                normal.app.value.transcript.turn is Idle &&
                normal.app.value.transcript.entries
                    .whereType<AssistantEntry>()
                    .isNotEmpty,
          );
          expect(
            normal.app.value.transcript.entries
                .whereType<AssistantEntry>()
                .single
                .text
                .toString(),
            'Hello, world. This reply came in chunks.',
          );
          await slow.close();
          expect(normal.app.value.start.phase, StartPhase.connected);
        },
      );

      test('late reply remains in its turn before the queued prompt', () async {
        final connection = await launch();
        connection.conversation.send('late');
        connection.conversation.send('text');
        await until(
          connection,
          () =>
              connection.app.value.transcript.turn is Idle &&
              connection.app.value.transcript.entries
                      .whereType<AssistantEntry>()
                      .length ==
                  2,
        );
        final replies = connection.app.value.transcript.entries
            .whereType<AssistantEntry>()
            .toList();
        expect(replies[0].text.toString(), 'Answered. Late, after the answer.');
        expect(
          replies[1].text.toString(),
          'Hello, world. This reply came in chunks.',
        );
      });

      test(
        'agent exit during a prompt marks the launched connection gone',
        () async {
          final connection = await launch();
          connection.conversation.send('crash');
          await until(
            connection,
            () => connection.app.value.start.phase == StartPhase.gone,
          );
          expect(
            connection.app.value.start.stderrLines,
            contains(
              'fatal: out of memory reading tests/parse/fixtures/huge.json',
            ),
          );
          expect(
            connection.app.value.transcript.entries.whereType<ErrorEntry>(),
            isNotEmpty,
          );
        },
      );

      test('hung turn is stopped by closing its launched connection', () async {
        final traffic = TrafficRecorder();
        final connection = await launch(
          flags: ['--hang', 'turn'],
          traffic: traffic,
        );
        connection.conversation.send('text');
        await traffic
            .next(
              (event) =>
                  event is ChordTraffic &&
                  event.message['method'] == 'session/prompt',
            )
            .timeout(const Duration(seconds: 10));
        await connection.close().timeout(const Duration(seconds: 10));
      });
    },
  );

  group(
    'tester: CTUI-34 configured launches under failure',
    skip: fakeAgentSkip,
    () {
      Future<(StartConnection, TrafficRecorder)> configured({
        String name = 'files',
        List<String> flags = const [],
        bool none = false,
      }) async {
        final root = Directory.systemTemp.createTempSync('chord-mcp-launch-');
        File('${root.path}/.mcp.json').writeAsStringSync(
          jsonEncode({
            'mcpServers': {
              name: {'command': 'serve-$name'},
            },
          }),
        );
        final outcome = await runCli(
          [
            'fake',
            '--agent-command',
            fakeAgentCommand(null, flags).map(shellWord).join(' '),
            if (none) '--no-mcp-servers',
          ],
          stdout: StringBuffer(),
          stderr: StringBuffer(),
          cwd: root.path,
          home: null,
        );
        expect(outcome.code, 0);
        final traffic = TrafficRecorder();
        final pids = <int>[];
        final connection = startLaunchConnection(
          outcome.launch!,
          cwd: root.path,
          stateDirectory: () => '${root.path}/state',
          open:
              ({
                required command,
                env,
                required cwd,
                required onTraffic,
                required onPermission,
                relay,
                cancellationToken,
              }) => fakeSessionOpener(pids.add)(
                command: command,
                env: env,
                cwd: cwd,
                onTraffic: (event) {
                  traffic.add(event);
                  onTraffic(event);
                },
                onPermission: onPermission,
                relay: relay,
                cancellationToken: cancellationToken,
              ),
        );
        addTearDown(() async {
          await connection.close();
          expect(pids, hasLength(1));
          expect(
            pids.where(
              (pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0,
            ),
            isEmpty,
          );
          root.deleteSync(recursive: true);
        });
        await until(
          connection,
          () => connection.app.value.start.phase == StartPhase.connected,
        );
        return (connection, traffic);
      }

      List<AssistantEntry> replies(StartConnection c) =>
          c.app.value.transcript.entries.whereType<AssistantEntry>().toList();

      Future<Object?> received(StartConnection c) async {
        final before = replies(c).length;
        expect(c.conversation.send('mcp'), isTrue);
        await until(
          c,
          () =>
              c.app.value.transcript.turn is Idle &&
              replies(c).length == before + 1,
        );
        return jsonDecode(
          replies(
            c,
          ).last.text.toString().replaceAll(RegExp(r'^```json\n|\n```$'), ''),
        );
      }

      test(
        'cancellation and a flag in one launch leave another server list intact',
        () async {
          final (first, _) = await configured(name: 'blocked', none: true);
          final (second, _) = await configured(name: 'allowed');
          expect(
            first.app.value.transcript.entries
                .whereType<WarningEntry>()
                .single
                .message,
            '--no-mcp-servers held back 1 MCP server from fake: blocked. /mcp lists it.',
          );
          expect(
            second.app.value.transcript.entries.whereType<WarningEntry>(),
            isEmpty,
          );
          first.conversation.send('slow');
          await until(first, () => replies(first).isNotEmpty);
          first.conversation.interrupt();
          await until(first, () => first.app.value.transcript.turn is Idle);
          expect(
            first.app.value.transcript.entries.whereType<CancelledEntry>(),
            isNotEmpty,
          );
          final results = await Future.wait([
            received(first),
            received(second),
          ]);
          expect(results[0], isEmpty);
          expect(results[1], [
            {
              'name': 'allowed',
              'command': 'serve-allowed',
              'args': [],
              'env': [],
            },
          ]);
        },
      );

      test('late output stays before the queued server-list reply', () async {
        final (connection, _) = await configured();
        connection.conversation.send('late');
        connection.conversation.send('mcp');
        await until(
          connection,
          () =>
              connection.app.value.transcript.turn is Idle &&
              replies(connection).length == 2,
        );
        expect(
          replies(connection).first.text.toString(),
          'Answered. Late, after the answer.',
        );
        expect(
          jsonDecode(
            replies(
              connection,
            ).last.text.toString().replaceAll(RegExp(r'^```json\n|\n```$'), ''),
          ),
          [
            {'name': 'files', 'command': 'serve-files', 'args': [], 'env': []},
          ],
        );
      });

      test(
        'a configured agent exit leaves a simultaneous launch usable',
        () async {
          final (first, _) = await configured(name: 'crashing');
          final (second, _) = await configured(name: 'surviving');
          first.conversation.send('crash');
          await until(
            first,
            () => first.app.value.start.phase == StartPhase.gone,
          );
          expect(
            first.app.value.transcript.entries.whereType<ErrorEntry>(),
            isNotEmpty,
          );
          expect(await received(second), [
            {
              'name': 'surviving',
              'command': 'serve-surviving',
              'args': [],
              'env': [],
            },
          ]);
        },
      );

      test(
        'a configured agent hanging in a turn is stopped by close',
        () async {
          final (connection, traffic) = await configured(
            flags: ['--hang', 'turn'],
          );
          connection.conversation.send('text');
          await traffic
              .next(
                (event) =>
                    event is ChordTraffic &&
                    event.message['method'] == 'session/prompt',
              )
              .timeout(const Duration(seconds: 10));
          await connection.close().timeout(const Duration(seconds: 10));
        },
      );
    },
  );

  for (final route in ['named', 'picked', 'override']) {
    test(
      '$route launch connects and answers through the CLI start helper',
      () async {
        final directory = Directory.systemTemp.createTempSync('chord-cli-');
        final pids = <int>[];
        addTearDown(() => directory.deleteSync(recursive: true));
        final catalog = findAgent('codex')!;
        final command = fakeAgentCommand(null, ['--step-ms', '0']);
        final fake = KnownAgent(
          name: catalog.name,
          title: catalog.title,
          start: AgentStart(
            route == 'override' ? ['must-not-start'] : command,
            const {'AUGMENT_DISABLE_AUTO_UPDATE': '1'},
          ),
          runner: catalog.runner,
          install: catalog.install,
        );
        final outcome = await runCli(
          [
            if (route != 'picked') 'codex',
            if (route == 'override') ...[
              '--agent-command',
              command.map(shellWord).join(' '),
            ],
          ],
          stdout: StringBuffer(),
          stderr: StringBuffer(),
          cwd: directory.path,
          home: null,
          stdinTTY: true,
          stdoutTTY: true,
          lookup: (_) async => 'found',
          find: (name) => name == fake.name ? fake : null,
          pickAgent:
              ({
                required agents,
                required version,
                required directory,
                required preferred,
                required offered,
              }) async => 'codex',
        );
        expect(outcome.code, 0);
        final connection = startLaunchConnection(
          outcome.launch!,
          cwd: directory.path,
          stateDirectory: () => directory.path,
          open: fakeSessionOpener(pids.add),
          owner: Owned(),
        );
        addTearDown(() async {
          await connection.close();
          expect(pids, hasLength(1));
          expect(
            pids.where(
              (pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0,
            ),
            isEmpty,
          );
        });
        await until(
          connection,
          () => connection.app.value.start.phase == StartPhase.connected,
        );
        expect(connection.conversation.send('text'), isTrue);
        await until(connection, () {
          final transcript = connection.app.value.transcript;
          return transcript.turn is Idle &&
              transcript.entries.whereType<AssistantEntry>().isNotEmpty;
        });
        final replies = connection.app.value.transcript.entries
            .whereType<AssistantEntry>();
        expect(
          replies.single.text.toString(),
          'Hello, world. This reply came in chunks.',
        );
      },
      skip: fakeAgentSkip,
    );
  }
}
