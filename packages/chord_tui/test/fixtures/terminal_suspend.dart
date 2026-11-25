import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

class ProbeTerminal extends StdioTerminal {
  ProbeTerminal({super.environment, super.editorLauncher});
  final writes = <String>[];
  Object? acquireFailure;
  Object? releaseFailure;
  @override
  void write(String data) {
    writes.add(data);
    if (data.contains('?1049h') && acquireFailure != null) {
      final error = acquireFailure!;
      acquireFailure = null;
      throw error;
    }
    if (data.contains('?2004l') && releaseFailure != null) {
      final error = releaseFailure!;
      releaseFailure = null;
      throw error;
    }
    super.write(data);
  }
}

Future<void> main(List<String> args) async {
  final scenario = args.single;
  if (scenario == 'actual_editor') {
    await actualEditor();
    return;
  }
  final before = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
  var launched = false;
  final launchFailure = StateError('launch failed');
  final env = switch (scenario) {
    'editor_fallback' => <String, String>{'VISUAL': ' ', 'EDITOR': ' nano '},
    'vi_fallback' => <String, String>{},
    'explicit' => <String, String>{'VISUAL': 'visual', 'SHELL': 'custom-shell'},
    _ => <String, String>{
      'VISUAL': ' code --wait ',
      'EDITOR': 'nano',
      'SHELL': '/bin/sh',
    },
  };
  final selected = switch (scenario) {
    'editor_fallback' => 'nano',
    'vi_fallback' => 'vi',
    'explicit' => 'explicit --wait',
    _ => 'code --wait',
  };
  final terminal = ProbeTerminal(
    environment: env,
    editorLauncher:
        (
          executable,
          arguments, {
          workingDirectory,
          required environment,
          required mode,
        }) async {
          launched = true;
          check(executable == (env['SHELL'] ?? '/bin/sh'), 'shell precedence');
          check(
            arguments.join('|') ==
                '-c|$selected "\$1"|editor|file \$(do-not-run).md',
            'separate file argument',
          );
          check(workingDirectory == '.', 'working directory');
          check(
            environment.length == env.length &&
                env.entries.every((e) => environment[e.key] == e.value),
            'environment',
          );
          check(mode == ProcessStartMode.inheritStdio, 'inherited stdio');
          if (scenario == 'launch_failure') throw launchFailure;
          return 23;
        },
  );
  final states = <TerminalState>[];
  final errors = <Object>[];
  final sub = terminal.states.listen(
    states.add,
    onError: (Object error) => errors.add(error),
  );
  try {
    var outside = false;
    try {
      await terminal.suspend(() async {});
    } on StateError {
      outside = true;
    }
    check(outside && terminal.writes.isEmpty, 'inactive suspension');
    terminal.enter();
    terminal.enter();
    check(states.length == 1, 'idempotent enter');
    switch (scenario) {
      case 'normal':
      case 'editor_fallback':
      case 'vi_fallback':
      case 'explicit':
        final code = await terminal.runEditor(
          'file \$(do-not-run).md',
          workingDirectory: '.',
          command: scenario == 'explicit' ? selected : null,
        );
        check(code == 23 && launched, 'nonzero editor exit');
      case 'launch_failure':
        Object? failure;
        try {
          await terminal.runEditor(
            'file \$(do-not-run).md',
            workingDirectory: '.',
          );
        } catch (error) {
          failure = error;
        }
        check(identical(failure, launchFailure), 'spawn failure identity');
        check(
          states.last == TerminalState.active,
          'restored after spawn failure',
        );
      case 'callback_failure':
        final original = StateError('callback failed');
        Object? failure;
        try {
          await terminal.suspend(() async {
            throw original;
          });
        } catch (error) {
          failure = error;
        }
        check(identical(failure, original), 'callback failure identity');
        check(
          states.last == TerminalState.active,
          'restored after callback failure',
        );
      case 'overlap':
        final release = Completer<void>();
        final started = Completer<void>();
        final operation = terminal.suspend(() async {
          started.complete();
          var rejected = false;
          try {
            await terminal.suspend(() async {});
          } on StateError {
            rejected = true;
          }
          check(rejected, 'nested suspension');
          await release.future;
        });
        await started.future;
        var rejected = false;
        try {
          await terminal.suspend(() async {});
        } on StateError {
          rejected = true;
        }
        check(rejected, 'overlapping suspension');
        release.complete();
        await operation;
      case 'leave_race':
        final leaving = terminal.leave();
        check(
          states.last == TerminalState.inactive,
          'leave publishes before await',
        );
        check(
          identical(terminal.leave(), leaving),
          'concurrent leave shares completion',
        );
        var called = false;
        var rejected = false;
        try {
          await terminal.suspend(() async {
            called = true;
          });
        } on StateError {
          rejected = true;
        }
        check(rejected && !called, 'same-turn leave then suspend');
        await leaving;
        check(
          states.where((s) => s == TerminalState.active).length == 1,
          'no race reentry',
        );
      case 'leave':
      case 'close':
        final release = Completer<void>();
        final started = Completer<void>();
        final operation = terminal.suspend(() async {
          started.complete();
          await release.future;
        });
        await started.future;
        var ended = false;
        final leaving =
            (scenario == 'close' ? terminal.close() : terminal.leave()).then((
              _,
            ) {
              ended = true;
            });
        await Future<void>.delayed(Duration.zero);
        check(!ended, 'leave must wait for child');
        release.complete();
        await operation;
        await leaving;
        check(
          states.where((s) => s == TerminalState.active).length == 1,
          'late reactivation',
        );
      case 'restore_failure':
        final original = StateError('callback failed');
        final restore = StateError('restore failed');
        Object? failure;
        try {
          await terminal.suspend(() async {
            terminal.acquireFailure = restore;
            throw original;
          });
        } catch (error) {
          failure = error;
        }
        final causes = (failure as dynamic).causes as List;
        check(
          identical(causes[0].$1, original) && identical(causes[1].$1, restore),
          'both failure causes',
        );
        check(causes.every((dynamic c) => c.$2 is StackTrace), 'both stacks');
        check(
          '$failure'.contains('callback failed') &&
              '$failure'.contains('restore failed'),
          'failure text',
        );
        check(errors.single == restore, 'restoration reports to live run');
      case 'release_failure':
        final release = StateError('release failed');
        terminal.releaseFailure = release;
        var called = false;
        Object? failure;
        try {
          await terminal.suspend(() async {
            called = true;
          });
        } catch (error) {
          failure = error;
        }
        check(
          !called && identical(failure, release),
          'callback needs released terminal',
        );
        check(
          states.last == TerminalState.active,
          'restored after release error',
        );
    }
    if (scenario != 'close') {
      await terminal.leave();
      await terminal.leave();
    }
  } finally {
    await sub.cancel();
    await terminal.close();
  }
  final after = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
  check(before == after, 'exact terminal restoration');
  stdout.writeln('SUSPEND_PASS=$scenario');
}

Future<void> actualEditor() async {
  final dir = Directory.systemTemp.createTempSync('terminal-editor-');
  final checkFile = File('${dir.path}/received');
  final path = '${dir.path}/file \$(do-not-run).md';
  final before = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
  final terminal = StdioTerminal(
    environment: {
      'CHECK': checkFile.path,
      'EDITOR': r'''/bin/sh -c 'printf "%s" "$1" > "$CHECK"' editor''',
    },
  );
  try {
    terminal.enter();
    final code = await terminal.runEditor(path);
    check(code == 0, 'scripted editor exit');
    check(
      checkFile.readAsStringSync() == path,
      'shell file argument injection',
    );
    await terminal.leave();
    final after = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
    check(before == after, 'actual editor termios');
  } finally {
    await terminal.close();
    dir.deleteSync(recursive: true);
  }
  stdout.writeln('SUSPEND_PASS=actual_editor');
}
