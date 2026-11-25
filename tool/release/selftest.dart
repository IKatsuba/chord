/// A built chord's self-test on the fake agent, as the original's
/// `scripts/dev/release/selftest.ts`: --version says pubspec.yaml's
/// version, -p answers, `chord acp` answers a prompt and a permission on
/// stdio and goes at EOF, and the window opens and answers a prompt in a
/// tmux of its own, on temporary state and config directories. [arch]
/// `x86_64` runs it all under `arch -x86_64` (Rosetta). The original's
/// clipboard and library-load checks have no counterpart: a Dart binary
/// embeds no native library.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/platform/signals.dart';
import 'package:path/path.dart' as p;

import 'runner.dart';

/// How long the acp step waits for its answer.
const acpAnswerLimit = Duration(seconds: 30);

/// How long the acp step waits for chord to leave at EOF.
const acpExitLimit = Duration(seconds: 20);

/// Self-tests [binary] (absolute) at [version], driving [fake], the fake
/// agent's command line. [sleep] waits between screen reads; [socket]
/// names this run's tmux server. A signal while it runs removes its tmux
/// server, its `chord acp` and scratch directory, then ends the run by that
/// signal ([watch] and [raise] are a test's way in). [acpAnswer] and
/// [acpExit] bound the acp step.
Future<void> selftest(
  ReleaseRunner runner, {
  required String binary,
  required String version,
  required String fake,
  required String socket,
  required Future<void> Function(Duration) sleep,
  required void Function(String line) report,
  String? arch,
  Stream<ProcessSignal> Function(ProcessSignal signal)? watch,
  void Function(ProcessSignal signal) raise = raiseSignal,
  Duration acpAnswer = acpAnswerLimit,
  Duration acpExit = acpExitLimit,
}) async {
  if (!File(binary).existsSync()) die('no binary at $binary');
  if ((await runner.run('sh', ['-c', 'command -v tmux'])).status != 0) {
    die('the self-test needs tmux');
  }
  final scratch = Directory.systemTemp.createTempSync('chord-selftest-');
  final project = p.join(scratch.path, 'project');
  final env = {
    'XDG_STATE_HOME': p.join(scratch.path, 'state'),
    'XDG_CONFIG_HOME': p.join(scratch.path, 'config'),
  };
  List<String> argv(List<String> args) => [
    if (arch != null) ...['arch', '-$arch'],
    binary,
    ...args,
  ];
  Future<({int? status, String said})> chord(
    List<String> args, {
    String? cwd,
  }) async {
    final [command, ...rest] = argv(args);
    final ran = await runner.run(command, rest, cwd: cwd, env: env);
    return (status: ran.status, said: said(ran.stdout + ran.stderr));
  }

  Future<Ran> tmux(List<String> args) =>
      runner.run('tmux', ['-L', socket, ...args], env: env);
  Future<String> screen() async {
    final captured = await tmux(['capture-pane', '-t', 'selftest', '-p']);
    return captured.status == 0 ? said(captured.stdout) : '';
  }

  String stderr() {
    final file = File(p.join(scratch.path, 'stderr'));
    return file.existsSync() ? said(file.readAsStringSync()) : '';
  }

  Future<void> waitFor(String text) async {
    for (var attempt = 0; attempt < 60; attempt++) {
      if ((await screen()).contains(text)) return;
      await sleep(const Duration(milliseconds: 500));
    }
    die(
      "$binary's window never showed \"$text\"; stderr: ${stderr()} "
      'screen:\n${await screen()}',
    );
  }

  // The tmux server and the scratch directory are this run's: gone however
  // it ends, a signal included, which then ends the run by itself.
  var cleaned = false;
  Started? acp;
  Future<void> cleanUp() async {
    if (cleaned) return;
    cleaned = true;
    if (acp case final child?) await endChild(child, acpExit);
    await tmux(['kill-server']);
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  }

  final off = dieBySignal(cleanUp, watch: watch, raise: raise);
  try {
    for (final dir in ['project', 'state', 'config']) {
      Directory(p.join(scratch.path, dir)).createSync();
    }
    final shown = await chord(['--version']);
    if (shown.status != 0) die('$binary --version failed: ${shown.said}');
    if (!shown.said.contains(version)) {
      die('$binary --version said ${shown.said}, not $version');
    }

    final printed = await chord([
      'fake',
      '--agent-command',
      fake,
      '-p',
      'text',
    ], cwd: project);
    if (printed.status != 0) die('$binary -p failed: ${printed.said}');
    if (!printed.said.contains('Hello, world.')) {
      die('$binary -p answered: ${printed.said}');
    }

    await acpStep(
      runner,
      argv(['acp', 'fake', '--agent-command', fake]),
      (binary: binary, cwd: project, env: env),
      answerLimit: acpAnswer,
      exitLimit: acpExit,
      own: (child) => acp = child,
    );

    await tmux([
      'new-session',
      '-d',
      '-s',
      'selftest',
      '-x',
      '100',
      '-y',
      '30',
      '-c',
      project,
      '${arch == null ? '' : 'arch -$arch '}\'$binary\' fake --agent-command '
          '"$fake" 2>\'${p.join(scratch.path, 'stderr')}\'; sleep 60',
    ]);
    await waitFor('for shortcuts');
    await tmux(['send-keys', '-t', 'selftest', 'text', 'Enter']);
    await waitFor('Hello, world.');
    report('self-tested $binary${arch == null ? '' : ' under $arch'}');
  } finally {
    off();
    await cleanUp();
  }
}

/// `chord acp` started as [argv], driven as a client: a prompt, its
/// permission, then EOF, the answer bounded by [answerLimit] and the exit
/// by [exitLimit]. [own] is told of the child while it runs, so a signal's
/// cleanup can end it too. However the step ends, its listener is cancelled
/// and a child that did not leave cleanly is killed and reaped.
Future<void> acpStep(
  ReleaseRunner runner,
  List<String> argv,
  ({String binary, String cwd, Map<String, String> env}) at, {
  Duration answerLimit = acpAnswerLimit,
  Duration exitLimit = acpExitLimit,
  void Function(Started? child)? own,
}) async {
  final [command, ...args] = argv;
  final binary = at.binary;
  final child = await runner.start(command, args, cwd: at.cwd, env: at.env);
  own?.call(child);
  StreamSubscription<String>? listening;
  var left = false;
  try {
    var asked = false;
    final answered = Completer<void>();
    void fail(String why) {
      if (!answered.isCompleted) answered.completeError(ReleaseError(why));
    }

    void write(Map<String, Object?> message) {
      try {
        child.write(jsonEncode({'jsonrpc': '2.0', ...message}));
      } catch (error) {
        fail('$binary acp could not be written to: $error');
      }
    }

    void heard(String part) {
      final Object? line;
      try {
        line = jsonDecode(part);
      } on FormatException {
        return fail('$binary acp wrote a line that is not JSON: $part');
      }
      if (line is! Map) {
        return fail('$binary acp wrote a line that is not JSON: $part');
      }
      // A request ahead of `initialize`'s answer is refused.
      if (line['id'] == 1) {
        write({
          'id': 2,
          'method': 'session/new',
          'params': {'cwd': at.cwd, 'mcpServers': <Object>[]},
        });
      }
      if (line case {'id': 2, 'result': {'sessionId': final id}}) {
        write({
          'id': 3,
          'method': 'session/prompt',
          'params': {
            'sessionId': id,
            'prompt': [
              {'type': 'text', 'text': 'permission'},
            ],
          },
        });
      }
      if (line['method'] == 'session/request_permission') {
        asked = true;
        write({
          'id': line['id'],
          'result': {
            'outcome': {'outcome': 'selected', 'optionId': 'allow'},
          },
        });
      }
      if (line['id'] == 3 && line['method'] == null) {
        if (asked && line['result'] != null) {
          if (!answered.isCompleted) answered.complete();
        } else {
          fail("$binary acp's prompt answered: $part");
        }
      }
    }

    listening = child.lines.listen(
      heard,
      onError: (Object error) =>
          fail("$binary acp's output could not be read: $error"),
    );
    unawaited(
      child.exitCode.then(
        (_) => fail('$binary acp exited early; stderr: ${child.stderr}'),
        onError: (Object error) => fail('$binary acp failed: $error'),
      ),
    );
    write({
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': 1,
        'clientCapabilities': <String, Object>{},
      },
    });
    await answered.future.timeout(
      answerLimit,
      onTimeout: () =>
          die('$binary acp never answered; stderr: ${child.stderr}'),
    );
    try {
      await child.close();
    } catch (error) {
      die('$binary acp could not be sent EOF: $error');
    }
    final code = await child.exitCode.timeout(exitLimit, onTimeout: () => -1);
    if (code != 0) {
      die(
        '$binary acp did not leave cleanly at EOF ($code); stderr: '
        '${child.stderr}',
      );
    }
    left = true;
  } finally {
    await listening?.cancel();
    if (!left) await endChild(child, exitLimit);
    own?.call(null);
  }
}

/// Kills [child] and waits up to [limit] for it to be reaped.
Future<void> endChild(Started child, Duration limit) async {
  child.kill();
  await child.exitCode
      .then<int?>((code) => code, onError: (_) => null)
      .timeout(limit, onTimeout: () => null);
}
