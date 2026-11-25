// CTUI-156: a monitor whose launcher has not reached `setsid` yet when its
// session closes or clears. The stop must reach the launcher then, and the
// close settle only once neither it nor the command is left.
@TestOn('posix')
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/platform/process.dart';
import 'package:chord/server/tools.dart' show Refused;
import 'package:chord/session/conversation.dart';
import 'package:chord/shell.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'conversation_fake.dart';

bool _running(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

void main() {
  late Directory temp;
  late String gate, launcherPid, childPid;
  final recorded = <int>[];

  setUp(() {
    temp = Directory.systemTemp.createTempSync('chord-monitor-start-');
    gate = p.join(temp.path, 'gate');
    launcherPid = p.join(temp.path, 'launcher.pid');
    childPid = p.join(temp.path, 'child.pid');
  });

  tearDown(() {
    // Only what this test started, by the pids it wrote down, a failed
    // test's included.
    for (final path in [launcherPid, childPid]) {
      final file = File(path);
      if (file.existsSync()) recorded.add(int.parse(file.readAsStringSync()));
    }
    for (final pid in recorded) {
      if (_running(pid)) Process.killPid(pid, ProcessSignal.sigkill);
    }
    recorded.clear();
    temp.deleteSync(recursive: true);
  });

  // Holds the launcher before it runs at all, so before its `setsid`, until
  // the gate file exists; it writes its pid first.
  List<String> held(String nonce, String path) => [
    '/bin/sh',
    '-c',
    r'echo $$ > "$0.pid.tmp" && mv "$0.pid.tmp" "$1"; '
        r'while [ ! -e "$0" ]; do sleep 0.02; done; shift; exec "$@"',
    gate,
    launcherPid,
    ...defaultLauncher(nonce, path),
  ];

  ShellProcess run(String command, String cwd, void Function(String) onLine) =>
      runShell(
        command,
        ShellOptions(cwd: cwd, onLine: onLine, reap: true, launcher: held),
      );

  Future<Conversation> connected() async {
    final conversation = Conversation(
      ({required onTraffic, required cancellationToken}) =>
          Future.value(ScriptedSession()),
    );
    final up = Completer<void>();
    conversation.listen((event) {
      if (event is Connected && !up.isCompleted) up.complete();
    });
    conversation.start();
    await up.future.timeout(const Duration(seconds: 5));
    return conversation;
  }

  Future<int> launcherStarted() async {
    final file = File(launcherPid);
    for (var i = 0; i < 250 && !file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final pid = int.parse(file.readAsStringSync().trim());
    recorded.add(pid);
    return pid;
  }

  Future<void> leavesNothing(
    Future<void> Function(Conversation conversation) leave,
  ) async {
    final conversation = await connected();
    final answer = conversation.startMonitor(
      (
        command: 'echo \$\$ > "$childPid"; exec sleep 600',
        description: 'held',
        timeoutMs: null,
      ),
      temp.path,
      run: run,
    );
    final launcher = await launcherStarted();
    expect(_running(launcher), isTrue);

    await leave(conversation).timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail(
        'the close did not settle while the launcher was held before '
        'setsid; launcher ${_running(launcher) ? 'still running' : 'gone'}',
      ),
    );
    expect(_running(launcher), isFalse, reason: 'the launcher survived');
    final child = File(childPid);
    if (child.existsSync()) {
      final pid = int.parse(child.readAsStringSync().trim());
      recorded.add(pid);
      expect(_running(pid), isFalse, reason: 'the command survived');
    }
    expect(await answer, isA<Refused>());
  }

  test('a close while the launcher is before setsid stops it, and settles '
      'once nothing is left', () async {
    await leavesNothing((conversation) => conversation.close());
  });

  test('a close before the launcher is even spawned stops it once it is, '
      'and settles once nothing is left', () async {
    final conversation = await connected();
    final answer = conversation.startMonitor(
      (
        command: 'echo \$\$ > "$childPid"; exec sleep 600',
        description: 'held',
        timeoutMs: null,
      ),
      temp.path,
      run: run,
    );
    // In the same event, so Process.start has not returned yet.
    await conversation.close().timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('the close did not settle'),
    );
    expect(await answer, isA<Refused>());
    for (final path in [launcherPid, childPid]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final pid = int.parse(file.readAsStringSync().trim());
      recorded.add(pid);
      expect(_running(pid), isFalse, reason: '$path survived');
    }
  });

  test('a clear while the launcher is before setsid stops it, and the '
      'close after settles once nothing is left', () async {
    await leavesNothing((conversation) {
      conversation.clear().ignore();
      return conversation.close();
    });
  });
}
