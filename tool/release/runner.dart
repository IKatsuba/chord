/// Where a release runs and what it reaches outside itself, as the
/// original's `scripts/dev/release/lib.ts`: every external command (dart,
/// file, tar, codesign, notarytool, npm, gh, git) goes through one
/// [ReleaseRunner], so a test runs a release against a recording one.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Why a release stops, said as it dies with it.
final class ReleaseError implements Exception {
  /// A release stopped, saying [message].
  const ReleaseError(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

/// Stops the release, saying [message].
Never die(String message) => throw ReleaseError(message);

/// A command's exit status and output, its output as text; [status] is
/// null when it did not run or ended by a signal.
final class Ran {
  /// A command that ended with [status] and wrote [stdout] and [stderr].
  const Ran(this.status, {this.stdout = '', this.stderr = ''});

  /// The exit status, or null.
  final int? status;

  /// What it wrote to stdout; empty for a loud run.
  final String stdout;

  /// What it wrote to stderr, or why it could not run; empty for a loud run.
  final String stderr;
}

/// Runs a release's external commands and waits for each.
abstract interface class ReleaseRunner {
  /// Runs [command] with [args] in the release's root and environment, or
  /// in [cwd] with [env] laid over it. A [loud] run shares the terminal's
  /// stdio, as a build's output is shown; a quiet one captures its output.
  Future<Ran> run(
    String command,
    List<String> args, {
    bool loud = false,
    String? cwd,
    Map<String, String> env = const {},
  });

  /// Starts [command] with [args] as [run] would, its stdio piped, for a
  /// conversation with it such as `chord acp`'s.
  Future<Started> start(
    String command,
    List<String> args, {
    String? cwd,
    Map<String, String> env = const {},
  });
}

/// A started command: its output line by line, its input, its end.
abstract interface class Started {
  /// What it writes to stdout, one line at a time.
  Stream<String> get lines;

  /// What it has written to stderr so far.
  String get stderr;

  /// Writes [line] and a newline to its stdin.
  void write(String line);

  /// Closes its stdin, as EOF.
  Future<void> close();

  /// Its exit status; null when it ended by a signal.
  Future<int?> get exitCode;

  /// Kills it at once.
  void kill();
}

/// The runner that starts real processes, in [root] with exactly [env].
final class ProcessReleaseRunner implements ReleaseRunner {
  /// A runner in [root] whose commands see [env] alone, PATH included.
  const ProcessReleaseRunner({required this.root, required this.env});

  /// The repository's root, every command's working directory.
  final String root;

  /// The environment every command runs in.
  final Map<String, String> env;

  String _cwd(String? cwd) => cwd == null ? root : p.join(root, cwd);

  @override
  Future<Ran> run(
    String command,
    List<String> args, {
    bool loud = false,
    String? cwd,
    Map<String, String> env = const {},
  }) async {
    final environment = {...this.env, ...env};
    try {
      if (loud) {
        final process = await Process.start(
          command,
          args,
          workingDirectory: _cwd(cwd),
          environment: environment,
          includeParentEnvironment: false,
          mode: ProcessStartMode.inheritStdio,
        );
        return Ran(_status(await process.exitCode));
      }
      final ran = await Process.run(
        command,
        args,
        workingDirectory: _cwd(cwd),
        environment: environment,
        includeParentEnvironment: false,
      );
      return Ran(
        _status(ran.exitCode),
        stdout: ran.stdout as String,
        stderr: ran.stderr as String,
      );
    } on ProcessException catch (error) {
      return Ran(null, stderr: error.message);
    }
  }

  @override
  Future<Started> start(
    String command,
    List<String> args, {
    String? cwd,
    Map<String, String> env = const {},
  }) async => _Started(
    await Process.start(
      command,
      args,
      workingDirectory: _cwd(cwd),
      environment: {...this.env, ...env},
      includeParentEnvironment: false,
    ),
  );

  // Dart reports death by a signal as a negative exit code; the original's
  // spawnSync answers null.
  static int? _status(int code) => code < 0 ? null : code;
}

final class _Started implements Started {
  _Started(this._process)
    : lines = _process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream() {
    _process.stderr.transform(utf8.decoder).listen(_stderr.write);
  }

  final Process _process;
  final _stderr = StringBuffer();

  @override
  final Stream<String> lines;

  @override
  String get stderr => _stderr.toString();

  @override
  void write(String line) => _process.stdin.writeln(line);

  @override
  Future<void> close() => _process.stdin.close();

  @override
  Future<int?> get exitCode =>
      _process.exitCode.then(ProcessReleaseRunner._status);

  @override
  void kill() => _process.kill(ProcessSignal.sigkill);
}

/// [text] without its trailing newlines, as a command's answer is said.
String said(String text) => text.replaceFirst(RegExp(r'\n+$'), '');
