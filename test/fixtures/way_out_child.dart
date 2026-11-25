// chord's way out with agents it owns, for renderer_test.dart: starts two
// agents in groups of their own, `sleep` that ignores SIGTERM, one owned
// (closed through its stop ladder) and one not (left to killAll), prints
// `ready <owned pid> <unowned pid>`, then waits for a signal, or with
// `crash` fails uncaught. With `term-starting` it sends itself SIGTERM
// while its first agent is still starting.
import 'dart:async';
import 'dart:io';

import 'package:chord/acp/process.dart';
import 'package:chord/platform/group_exec.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/platform/signals.dart';
import 'package:chord/ui/app/renderer.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == groupExecFlag) groupExec(args);
  final [how] = args;
  // A signal can come while an agent is starting, its process forked but
  // not yet registered for killAll: the way out waits for every start
  // under way, and no other begins once it has (CTUI-90).
  final starting = <Future<void>>[];
  var stopping = false;
  Future<void> leaving() async {
    stopping = true;
    await Future.wait(starting);
    await leave(giveBack: () async => stdout.writeln('gave back'));
  }

  await runZonedGuarded(() async {
    const stubborn = ['sh', '-c', 'trap "" TERM; while :; do sleep 1; done'];
    // Handled before any agent starts: a test that stops this child early
    // with SIGTERM gets every group it started killed (CTUI-90).
    dieBySignal(leaving);
    // Each group is named once it has started, for a test that must reap
    // it should SIGTERM not end this child.
    Future<AgentProcess> start() async {
      if (stopping) await Completer<void>().future;
      final agent = spawnAgent(
        command: stubborn,
        cwd: Directory.systemTemp.path,
      );
      starting.add(agent.then((_) {}, onError: (_) {}));
      if (how == 'term-starting') Process.killPid(pid, ProcessSignal.sigterm);
      final group = await agent;
      stdout.writeln('agent ${group.pid}');
      await stdout.flush();
      return group;
    }

    final ownedAgent = await start();
    final unowned = await start();
    owned.closeOnForcedExit(
      () => ownedAgent
          .stop(
            const StopBounds(
              exit: Duration(milliseconds: 100),
              term: Duration(milliseconds: 100),
              kill: Duration(seconds: 2),
            ),
          )
          .then((_) => stdout.writeln('closed')),
    );
    stdout.writeln('ready ${ownedAgent.pid} ${unowned.pid}');
    await stdout.flush();
    if (how == 'crash') {
      Timer.run(() => throw StateError('chord failed'));
    }
    // Kept alive until a signal or the crash ends it.
    await Completer<void>().future;
  }, (error, stack) => crash(error, stack, leaving));
}
