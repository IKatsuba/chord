import 'dart:io';

/// Whether this host has a process to exit and a stderr to report on: the
/// native one does.
const bool hostHasProcess = true;

/// The process's environment.
Map<String, String> get hostEnvironment => Platform.environment;

/// Keeps a stderr that has gone away from failing later on its done future:
/// that failure has nowhere to be said, and must not take the place of the
/// signal or the exit code an app leaves by.
void settleFailureReports() => stderr.done.ignore();

/// Says one line of a failure on stderr, unless stderr is already closed.
void reportFailure(Object? line) {
  try {
    stderr.writeln(line);
  } catch (_) {
    // stderr closed by an earlier failure.
  }
}

/// Ends the process with [code].
void exitWith(int code) => exit(code);
