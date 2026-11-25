/// One noninteractive command in a session directory, with process-group stop.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'platform/process.dart';

/// How a local shell command ended; output has drained before [ShellProcess.ended].
final class ShellEnd {
  const ShellEnd({this.code, this.signal, this.stopped = false, this.error});
  final int? code;
  final String? signal;
  final bool stopped;
  final String? error;
}

/// A shell command whose stop reaches its whole process group.
abstract class ShellProcess {
  /// Ends after the shell and its output, and after a stopped group is reaped.
  Future<ShellEnd> get ended;

  /// Ends as the shell exits, before descendants necessarily release output.
  Future<ShellEnd> get exited => ended;

  /// Stops the command and everything it started; idempotent.
  void stop();

  /// That the shell itself did not start, once that is known: null once
  /// it has, else why not; the reason in full comes as [ended]'s error.
  Future<String?> get failed => Future.value();
}

/// Bash-mode output streams; their text remains raw until context/view shaping.
enum ShellStream { stdout, stderr }

/// How a command runs: bash mode's output pieces, or a monitor's lines.
final class ShellOptions {
  ShellOptions({
    required this.cwd,
    List<String>? shell,
    this.onOutput,
    this.onLine,
    this.reap = false,
    this.launcher = defaultLauncher,
  }) : shell = shell == null ? null : List.unmodifiable(shell) {
    if (this.shell?.isEmpty ?? false) {
      throw ArgumentError.value(shell, 'shell', 'Must name a shell');
    }
  }
  final String cwd;
  final List<String>? shell;
  final void Function(ShellStream stream, String text)? onOutput;

  /// Each line of stdout instead, a monitor's: split on `\n` or `\r\n`, a
  /// lone `\r` kept in its line, the last one handed on without its end once
  /// the command ends, and stderr not read at all.
  final void Function(String line)? onLine;

  /// Whether what the command started goes with it when it ends on its own,
  /// a monitor's: something that let go of the pipes would outlive the
  /// monitor, and chord with it. Bash mode leaves it be.
  final bool reap;

  /// How its shell is started in a group of its own; tests hold it.
  final Launcher launcher;
}

/// The injectable command launch seam used by the plain app coordinator.
typedef RunShell = ShellProcess Function(String command, ShellOptions options);

/// Runs the unchanged script through the user's shell with no interactive stdin.
ShellProcess runShell(String command, ShellOptions options) =>
    _ShellExecution(command, options);

final class _ShellExecution extends ShellProcess {
  _ShellExecution(String command, ShellOptions options) {
    final chosen = Platform.environment['SHELL'];
    final shell =
        options.shell ??
        [chosen == null || chosen.isEmpty ? '/bin/sh' : chosen, '-c'];
    unawaited(_run(command, shell, options));
  }

  final _start = Completer<String?>();
  @override
  Future<String?> get failed => _start.future;
  final _ended = Completer<ShellEnd>(), _exited = Completer<ShellEnd>();
  GroupProcess? _group;
  Timer? _killer;
  var _stopped = false, _terminating = false;
  DateTime? _killedAt;

  @override
  Future<ShellEnd> get ended => _ended.future;
  @override
  Future<ShellEnd> get exited => _exited.future;

  ShellEnd _end(Exit exit) => _stopped
      ? const ShellEnd(stopped: true)
      : ShellEnd(code: exit.code, signal: exit.signal);
  ShellEnd _failed(Object error) =>
      _stopped ? const ShellEnd(stopped: true) : ShellEnd(error: '$error');

  Future<void> _run(
    String command,
    List<String> shell,
    ShellOptions options,
  ) async {
    ShellEnd end;
    try {
      final program = shell.first;
      final group = _group = await spawnGroup(
        program,
        [...shell.skip(1), command],
        cwd: options.cwd,
        launcher: options.launcher,
      );
      // Its group exists, or the launcher says why the exec failed.
      group.started.then(
        (_) => _started(null),
        onError: (Object _) => _started('$program did not start'),
      );
      final onLine = options.onLine;
      final output = onLine == null
          ? Future.wait([
              _pipe(group.stdout, ShellStream.stdout, options),
              _pipe(group.stderr, ShellStream.stderr, options),
            ])
          : Future.wait([
              _lines(group.stdout, onLine),
              group.stderr.drain<void>(),
            ]);
      final exit = group.exit.then(
        _end,
        // A monitor's end says what its exec's failure means, as the
        // launcher's 127 or 126 does; bash mode keeps the error alone.
        onError: (Object error) => switch (error) {
          CannotStart(:final code?) when options.reap && !_stopped => ShellEnd(
            code: code,
            error: '$error',
          ),
          _ => _failed(error),
        },
      );
      unawaited(
        exit.then((value) {
          if (!_exited.isCompleted) _exited.complete(value);
        }),
      );
      unawaited(group.stdin.close().catchError((Object _) {}));
      if (_stopped) _terminate();
      if (options.reap) {
        // It ends when its shell does, with that shell's code, though what
        // it started still holds stdout: that goes with the group, and the
        // output is read to its end after.
        end = await exit;
        _terminate();
        await _groupGone(group);
        await output.catchError((Object _) => <void>[]);
      } else {
        final values = await Future.wait<Object?>([output, exit]);
        end = values.last as ShellEnd;
      }
    } catch (error) {
      if (_group == null) _started('${shell.first} did not start');
      end = _failed(error);
    }
    try {
      // Output failure must not cancel an already requested group escalation.
      final group = _group;
      if (_stopped && group != null) {
        _terminate();
        await _groupGone(group);
        end = const ShellEnd(stopped: true);
      }
    } finally {
      _killer?.cancel();
    }
    _started(null);
    if (!_exited.isCompleted) _exited.complete(end);
    _ended.complete(end);
  }

  Future<void> _pipe(
    Stream<List<int>> bytes,
    ShellStream stream,
    ShellOptions options,
  ) async {
    await for (final text in bytes.transform(
      const Utf8Decoder(allowMalformed: true),
    )) {
      options.onOutput?.call(stream, text);
    }
  }

  void _started(String? why) {
    if (!_start.isCompleted) _start.complete(why);
  }

  /// Stdout as lines: split on `\n` or `\r\n`, a lone `\r` kept, the
  /// last unended one handed on once stdout closes.
  Future<void> _lines(
    Stream<List<int>> bytes,
    void Function(String line) onLine,
  ) async {
    final pending = StringBuffer();
    await for (final text in bytes.transform(
      const Utf8Decoder(allowMalformed: true),
    )) {
      var from = 0;
      for (
        var at = text.indexOf('\n');
        at >= 0;
        at = text.indexOf('\n', from)
      ) {
        pending.write(text.substring(from, at));
        final line = pending.toString();
        pending.clear();
        onLine(line.endsWith('\r') ? line.substring(0, line.length - 1) : line);
        from = at + 1;
      }
      pending.write(text.substring(from));
    }
    if (pending.isNotEmpty) onLine(pending.toString());
  }

  void _terminate() {
    final group = _group;
    if (_terminating || group == null) return;
    _terminating = true;
    if (group.signal(ProcessSignal.sigterm)) {
      _killer = Timer(const Duration(seconds: 2), () {
        _killedAt = DateTime.now();
        group.signal(ProcessSignal.sigkill);
      });
    } else {
      _killedAt = DateTime.now();
    }
  }

  Future<void> _groupGone(GroupProcess group) async {
    while (group.alive() &&
        (_killedAt == null ||
            DateTime.now().isBefore(
              _killedAt!.add(const Duration(seconds: 5)),
            ))) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  @override
  void stop() {
    if (_stopped || _ended.isCompleted) return;
    _stopped = true;
    _terminate();
  }
}
