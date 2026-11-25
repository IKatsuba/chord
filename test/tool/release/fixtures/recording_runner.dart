import 'dart:async';

import '../../../../tool/release/runner.dart';

/// One command a [RecordingRunner] was asked to run or start.
typedef Call = ({
  List<String> argv,
  bool loud,
  String? cwd,
  Map<String, String> env,
});

/// A runner that runs nothing: it records each command and answers what
/// [answer] says, or status 0 with no output; a started command is what
/// [starter] gives.
final class RecordingRunner implements ReleaseRunner {
  /// A runner answering through [answer] and [starter].
  RecordingRunner([this.answer, this.starter, this.answerIn]);

  /// The answer to an argv; null answers status 0.
  final Ran? Function(List<String> argv)? answer;

  /// The command started for an argv.
  final Started Function(List<String> argv)? starter;

  /// The answer to an argv run in a folder, asked before [answer].
  final Ran? Function(List<String> argv, String? cwd)? answerIn;

  /// Every command asked, in order.
  final List<Call> calls = [];

  /// Every argv asked, in order.
  List<List<String>> get argvs => [for (final call in calls) call.argv];

  @override
  Future<Ran> run(
    String command,
    List<String> args, {
    bool loud = false,
    String? cwd,
    Map<String, String> env = const {},
  }) async {
    final argv = [command, ...args];
    calls.add((argv: argv, loud: loud, cwd: cwd, env: env));
    return answerIn?.call(argv, cwd) ?? answer?.call(argv) ?? const Ran(0);
  }

  @override
  Future<Started> start(
    String command,
    List<String> args, {
    String? cwd,
    Map<String, String> env = const {},
  }) async {
    final argv = [command, ...args];
    calls.add((argv: argv, loud: false, cwd: cwd, env: env));
    final make = starter ?? (throw StateError('nothing starts $argv'));
    return make(argv);
  }
}

/// A started command that answers each line written to it with what
/// [reply] gives, and ends with [status] once its input is closed. Faults
/// for cleanup tests: [writeError] thrown by a write, [closeError] by the
/// close, [linesError] put on its output at the first write, and
/// [killDelay] before a kill ends it.
final class ScriptedStarted implements Started {
  /// A command replying through [reply], ending with [status] at EOF.
  ScriptedStarted(
    this.reply, {
    this.status = 0,
    this.stderr = '',
    this.writeError,
    this.closeError,
    this.linesError,
    this.killDelay = Duration.zero,
  });

  /// The lines it writes for a line written to it.
  final List<String> Function(String line) reply;

  /// Its exit status once its input closes; null never ends it.
  final int? status;

  @override
  final String stderr;

  /// What a write throws, if anything.
  final Object? writeError;

  /// What closing its input throws, if anything.
  final Object? closeError;

  /// The error its output carries from the first write, if any.
  final Object? linesError;

  /// How long a kill takes to end it.
  final Duration killDelay;

  final _lines = StreamController<String>.broadcast(sync: true);
  final _exit = Completer<int?>();

  /// Every line written to it, in order.
  final List<String> written = [];

  /// Whether it was killed.
  bool killed = false;

  /// Whether it has ended, by EOF or a kill.
  bool get ended => _exit.isCompleted;

  /// Whether something still listens to its output.
  bool get heard => _lines.hasListener;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  void write(String line) {
    if (writeError case final error?) throw error;
    written.add(line);
    // Answered after the caller has gone on listening, as a process would.
    scheduleMicrotask(() {
      if (linesError case final error? when written.length == 1) {
        _lines.addError(error);
        return;
      }
      reply(line).forEach(_lines.add);
    });
  }

  @override
  Future<void> close() async {
    if (closeError case final error?) throw error;
    if (status != null && !_exit.isCompleted) _exit.complete(status);
  }

  @override
  Future<int?> get exitCode => _exit.future;

  @override
  void kill() {
    killed = true;
    Future<void>.delayed(killDelay, () {
      if (!_exit.isCompleted) _exit.complete(null);
    });
  }
}
