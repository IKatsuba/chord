@TestOn('posix')
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/platform/process.dart';
import 'package:chord/server/tools.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/shell.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'conversation_fake.dart';

// A launcher held before setsid, using the production shell and group path.
final class _HeldLauncher {
  _HeldLauncher(this.directory);
  final Directory directory;
  int? pid;
  String? identity;
  String get gate => p.join(directory.path, 'release');
  String get pidFile => p.join(directory.path, 'launcher.pid');
  String get childFile => p.join(directory.path, 'child.pid');

  static String? processIdentity(int pid) {
    final result = Process.runSync('ps', ['-p', '$pid', '-o', 'lstart=']);
    final start = '${result.stdout}'.trim();
    return result.exitCode == 0 && start.isNotEmpty ? start : null;
  }

  bool get alive => pid != null && processIdentity(pid!) == identity;

  List<String> launcher(String nonce, String path) => [
    '/bin/sh',
    '-c',
    r'echo $$ > "$1.tmp"; mv "$1.tmp" "$1"; '
        r'while [ ! -e "$0" ]; do sleep 0.02; done; shift; exec "$@"',
    gate,
    pidFile,
    ...defaultLauncher(nonce, path),
  ];

  ShellProcess run(String command, String cwd, void Function(String) onLine) =>
      runShell(
        command,
        ShellOptions(cwd: cwd, onLine: onLine, reap: true, launcher: launcher),
      );

  Future<void> started() async {
    final file = File(pidFile);
    await _until(file.existsSync);
    pid = int.parse(file.readAsStringSync().trim());
    identity = processIdentity(pid!);
    expect(identity, isNotNull);
  }

  void release() => File(gate).writeAsStringSync('go');

  void clean() {
    // Revalidate the recorded identity; never signal a reused pid.
    if (alive) Process.killPid(pid!, ProcessSignal.sigkill);
  }
}

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('condition did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('CTUI-156 tester: startup ownership', () {
    late Directory temp;
    final launchers = <_HeldLauncher>[];
    final conversations = <Conversation>[];
    final sessions = <ScriptedSession>[];
    final events = <ConversationEvent>[];

    setUp(() {
      temp = Directory.systemTemp.createTempSync('chord-monitor-start-tester-');
    });

    tearDown(() async {
      for (final launcher in launchers) {
        launcher.clean();
      }
      for (final conversation in conversations) {
        await conversation.close().timeout(const Duration(seconds: 10));
      }
      launchers.clear();
      conversations.clear();
      sessions.clear();
      events.clear();
      temp.deleteSync(recursive: true);
    });

    Future<Conversation> connected() async {
      final conversation = Conversation(({
        required onTraffic,
        required cancellationToken,
      }) {
        final session = ScriptedSession();
        sessions.add(session);
        return Future.value(session);
      });
      conversations.add(conversation);
      final up = Completer<void>();
      conversation.listen((event) {
        events.add(event);
        if (event is Connected && !up.isCompleted) up.complete();
      });
      conversation.start();
      await up.future.timeout(const Duration(seconds: 5));
      return conversation;
    }

    (_HeldLauncher, Future<MonitorAnswer>) start(Conversation conversation) {
      final directory = Directory(p.join(temp.path, '${launchers.length}'))
        ..createSync();
      final held = _HeldLauncher(directory);
      launchers.add(held);
      final answer = conversation.startMonitor(
        (
          command: 'echo \$\$ > "${held.childFile}"; exec sleep 600',
          description: 'held',
          timeoutMs: null,
        ),
        temp.path,
        run: held.run,
      );
      return (held, answer);
    }

    void silent(Conversation conversation) {
      expect(conversation.monitors, isEmpty);
      expect(conversation.endedMonitors, isEmpty);
      expect(
        events.whereType<Transcribed>().where(
          (e) =>
              e.action is PromptAction &&
              (e.action as PromptAction).from?.monitor != null,
        ),
        isEmpty,
      );
    }

    test(
      'clear stops two held launchers without closing the fresh session',
      () async {
        final conversation = await connected();
        final (first, firstAnswer) = start(conversation);
        final (second, secondAnswer) = start(conversation);
        await Future.wait([first.started(), second.started()]);
        await conversation.clear().timeout(const Duration(seconds: 10));
        for (final answer in [firstAnswer, secondAnswer]) {
          expect(
            await answer.timeout(const Duration(seconds: 10)),
            isA<Refused>(),
          );
        }
        expect(first.alive, isFalse);
        expect(second.alive, isFalse);
        expect(conversation.monitorsHeld, 0);
        silent(conversation);

        final (fresh, freshAnswer) = start(conversation);
        await fresh.started();
        fresh.release();
        final result = await freshAnswer.timeout(const Duration(seconds: 10));
        expect(result, isA<StartedMonitor>());
        expect((result as StartedMonitor).id, 'm1');
        await conversation.close().timeout(const Duration(seconds: 10));
        expect(fresh.alive, isFalse);
      },
    );

    test(
      'stop during startup refuses without consuming the eventual monitor',
      () async {
        final conversation = await connected();
        final (held, answer) = start(conversation);
        await held.started();
        expect(
          (conversation.stopMonitor('m1') as Refused).error,
          'No running monitor m1 of yours; list_monitors names them',
        );
        expect(held.alive, isTrue);
        held.release();
        expect(
          await answer.timeout(const Duration(seconds: 10)),
          isA<StartedMonitor>(),
        );
        expect(conversation.stopMonitor('m1'), isA<StoppedMonitor>());
        await conversation.close().timeout(const Duration(seconds: 10));
        expect(held.alive, isFalse);
      },
    );

    test(
      'closing one session leaves the other held launcher owned and alive',
      () async {
        final first = await connected();
        final second = await connected();
        final (a, answerA) = start(first);
        final (b, answerB) = start(second);
        await Future.wait([a.started(), b.started()]);
        await first.close().timeout(const Duration(seconds: 10));
        expect(await answerA, isA<Refused>());
        expect(a.alive, isFalse);
        expect(b.alive, isTrue);
        expect(second.monitorsHeld, 1);
        await second.close().timeout(const Duration(seconds: 10));
        expect(await answerB, isA<Refused>());
        expect(b.alive, isFalse);
        silent(first);
        silent(second);
      },
    );

    test(
      'an exiting agent stops its held launcher without a monitor turn',
      () async {
        final conversation = await connected();
        final (held, answer) = start(conversation);
        await held.started();
        sessions.single.exit();
        expect(
          await answer.timeout(const Duration(seconds: 10)),
          isA<Refused>(),
        );
        await _until(() => !held.alive);
        silent(conversation);
      },
    );
  });
}
