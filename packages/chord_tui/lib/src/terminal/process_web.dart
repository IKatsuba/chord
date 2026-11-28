import 'dart:js_interop';

/// Whether this host has a process to exit and a stderr to report on: a
/// page has neither.
const bool hostHasProcess = false;

/// A page has no environment.
Map<String, String> get hostEnvironment => const {};

/// Nothing to settle: the console does not go away.
void settleFailureReports() {}

/// Says one line of a failure on the page's console.
void reportFailure(Object? line) => _consoleError('$line'.toJS);

/// A page has no process to end: the app has already returned.
void exitWith(int code) {}

@JS('console.error')
external void _consoleError(JSString message);
