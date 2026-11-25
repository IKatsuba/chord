import 'dart:async';
import 'dart:io';
import 'package:chord/acp/process.dart';
import 'package:chord/agents.dart';
import 'package:chord/cli.dart';
import 'package:chord/platform/group_exec.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/platform/signals.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == groupExecFlag) groupExec(args);
  final scenario = args.single;
  final before = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
  final terminal = StdioTerminal();
  final resource = await spawnAgent(
    command: const ['sh', '-c', 'trap "" TERM; while :; do sleep 1; done'],
    cwd: Directory.current.path,
  );
  owned.closeOnForcedExit(() async {
    await resource.stop(
      const StopBounds(
        exit: Duration(milliseconds: 100),
        term: Duration(milliseconds: 100),
        kill: Duration(seconds: 2),
      ),
    );
    stdout.writeln('OWNED_CLOSED');
  });
  stdout.writeln('OWNED_PID=${resource.pid}');
  await stdout.flush();
  dieBySignal(() async {
    stdout.writeln('OWNER_LEAVING');
    await stdout.flush();
    await leave(giveBack: terminal.leave);
    await terminal.close();
    final after = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
    if (before != after) throw StateError('Termios changed');
    stdout.writeln('OWNER_EXACT=true');
    await stdout.flush();
  });
  if (scenario == 'startup') {
    await selectStartupAgent(
      agents: const [
        ListedAgent(
          name: 'fixture',
          title: 'Fixture',
          start: 'unused',
          from: AgentRunner.cli,
        ),
      ],
      version: '0.0.1',
      directory: 'project',
      terminal: terminal,
      handleSignals: false,
    );
  } else {
    final connection = StartConnection(command: 'unused', cwd: '.');
    connection.app.value = const AppState(
      start: StartState(phase: StartPhase.connected),
    );
    await runApp(
      Actions(
        bindings: [
          Binding('ctrl+g', 'Scripted child', () async {
            await terminal.suspend(() async {
              final child = await Process.start('/bin/sh', [
                '-c',
                r'''printf 'PORT_CHILD_READY\n'; IFS= read -r line; printf 'PORT_CHILD_GOT=%s\n' "$line"''',
              ], mode: ProcessStartMode.inheritStdio);
              if (await child.exitCode != 0) throw StateError('Child failed');
            });
          }),
        ],
        child: TranscriptWindow(
          launch: const Launch(
            name: 'fixture',
            agent: null,
            agentCommand: 'unused',
            version: '0.0.1',
            directory: 'project',
          ),
          connection: connection,
        ),
      ),
      terminal: terminal,
      handleSignals: false,
      exitProcess: false,
      beforeExit: () async {
        await connection.close();
        await leave();
        await terminal.close();
      },
    );
  }
  await Completer<void>().future;
}
