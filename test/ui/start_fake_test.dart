// The interim window's connection against the original's fake agent: the
// command `--agent-command` gives started, the session opened, a failed
// start and an exit drawn, and the agent closed.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/start.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../tool/dev.dart' show shellWord;
import '../fixtures/fake.dart';

const tracebackError =
    "ImportError: cannot import name 'AuthMethod' from 'acp.schema'";

bool alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// A started connection, the pids it started, and its directory.
typedef Run = ({StartConnection connection, List<int> pids, String cwd});

/// A connection on the fake with [flags], or on [command], closed and its
/// agent checked gone in tearDown.
Run started({List<String> flags = const [], List<String>? command}) {
  final cwd = Directory.systemTemp.createTempSync('chord-start-').path;
  final pids = <int>[];
  Future<Agent> open({
    required Object command,
    Map<String, String>? env,
    required String cwd,
    required void Function(Traffic traffic) onTraffic,
    required PermissionHandler onPermission,
    Relay? relay,
    CancellationToken? cancellationToken,
  }) async {
    final agent = await openAgent(
      command: command,
      cwd: cwd,
      onTraffic: onTraffic,
      onPermission: onPermission,
      cancellationToken: cancellationToken,
      // The original's test bounds: the fake ignores stdin and SIGTERM
      // only when it hangs.
      stop: const StopBounds(
        exit: Duration(milliseconds: 100),
        term: Duration(milliseconds: 300),
      ),
    );
    pids.add(agent.pid);
    return agent;
  }

  final connection = StartConnection(
    command: (command ?? fakeAgentCommand(null, flags))
        .map(shellWord)
        .join(' '),
    cwd: cwd,
    open: open,
    owner: Owned(),
  )..start();
  addTearDown(() async {
    await connection.close();
    expect(pids.where(alive), isEmpty, reason: 'the agent is still running');
    Directory(cwd).deleteSync(recursive: true);
  });
  return (connection: connection, pids: pids, cwd: cwd);
}

/// Until the connection's phase is [phase], or ten seconds pass.
Future<StartState> reaches(StartConnection connection, StartPhase phase) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (connection.state.value.phase != phase) {
    if (DateTime.now().isAfter(deadline)) {
      fail('still ${connection.state.value.phase}, never $phase');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return connection.state.value;
}

void main() {
  group('the window on the fake agent', skip: fakeAgent.reason, () {
    test(
      'opens a session in its directory and keeps the agent\'s name',
      () async {
        final run = started();
        final state = await reaches(run.connection, StartPhase.connected);
        expect(state.sessionId, isNotEmpty);
        expect(state.agentName, 'chord-fake-agent');
        expect(state.agentVersion, '0.0.0');
      },
    );

    test('a start that fails shows the end of its stderr', () async {
      final run = started(flags: ['--start-fails', 'traceback']);
      final state = await reaches(run.connection, StartPhase.failed);
      expect(
        state.reason,
        'it exited with code 1 before answering initialize.',
      );
      expect(state.stderrLines.last, tracebackError);
      expect(
        statusLine(state, 'fake'),
        'fake did not start: it exited with code 1 before answering initialize.',
      );
    });

    test('an agent that serves no session fails with its words, and is '
        'closed', () async {
      final run = started(flags: ['--start-fails', 'notacp']);
      final state = await reaches(run.connection, StartPhase.failed);
      expect(
        state.reason,
        'it does not serve ACP sessions: not an ACP agent, or not at this version.',
      );
      expect(run.pids, hasLength(1));
      // Closed without waiting for the window's own close.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (alive(run.pids.single) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(alive(run.pids.single), isFalse);
    });

    test('an agent that goes after connecting is gone', () async {
      final run = started();
      await reaches(run.connection, StartPhase.connected);
      Process.killPid(-run.pids.single, ProcessSignal.sigkill);
      final state = await reaches(run.connection, StartPhase.gone);
      expect(state.reason, 'The agent exited.');
      expect(state.sessionId, isNotEmpty);
    });

    test('close ends the agent, and draws no gone', () async {
      final run = started();
      await reaches(run.connection, StartPhase.connected);
      await run.connection.close();
      expect(alive(run.pids.single), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(run.connection.state.value.phase, StartPhase.connected);
    });

    test(
      'close during a start that never answers gives it up and stops it',
      () async {
        final run = started(flags: ['--hang', 'start']);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(run.connection.state.value.phase, StartPhase.starting);
        await run.connection.close();
        expect(run.connection.state.value.phase, StartPhase.starting);
      },
    );

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('at ${size.width}x${size.height}, starting until the gate '
          'opens, then connected', (t) async {
        final gate =
            '${Directory.systemTemp.createTempSync('chord-gate-').path}'
            '/open';
        addTearDown(() => File(gate).parent.deleteSync(recursive: true));
        final run = started(command: gatedCommand(gate, fakeAgentCommand()));
        const launch = Launch(
          name: 'fake',
          agent: null,
          agentCommand: 'fake',
          version: '0.0.1',
          directory: '/workspace/demo',
        );
        await t.pumpWidget(
          StartWindow(launch: launch, state: run.connection.state),
          size: size,
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await t.pump();
        expect(t.screen.lines.take(3), [
          ' chord v0.0.1 · fake · /workspace/demo',
          ' Starting fake…',
          ' ctrl+c or ctrl+d to quit',
        ]);
        File(gate).createSync();
        await reaches(run.connection, StartPhase.connected);
        await t.pump();
        expect(t.screen.lines[1], ' Connected');
        expect(t.screen.lines.skip(3).every((line) => line.isEmpty), isTrue);
      });
    }
  });

  group('tester independent window connections', skip: fakeAgent.reason, () {
    test(
      'closing one of two connected windows leaves the other live',
      () async {
        final first = started();
        final second = started();
        final states = await Future.wait([
          reaches(first.connection, StartPhase.connected),
          reaches(second.connection, StartPhase.connected),
        ]);
        expect(first.pids.single, isNot(second.pids.single));
        expect(states[0].sessionId, isNot(states[1].sessionId));
        await first.connection.close();
        expect(alive(first.pids.single), isFalse);
        expect(alive(second.pids.single), isTrue);
        expect(second.connection.state.value.phase, StartPhase.connected);
        await second.connection.close();
        expect(alive(second.pids.single), isFalse);
      },
    );
  });
}
