/// Structural startup facts and their original user-facing words.
library;

import '../acp/connection.dart';
import 'sessions.dart';
import 'sign_in.dart' show SignInNeeded;

/// The supported protocol step whose opening did not complete.
enum StartStep {
  initialize('initialize'),
  newSession('session/new'),
  loadSession('session/load'),
  resumeSession('session/resume'),
  forkSession('session/fork');

  const StartStep(this.method);
  final String method;
}

/// Facts captured at failure, before cleanup can change process state.
final class StartFailure {
  const StartFailure({
    required this.step,
    this.exit,
    this.closed = false,
    this.code,
    this.said,
    this.stderr,
    this.pinned,
  });

  final StartStep step;
  final Exit? exit;
  final bool closed;
  final num? code;
  final String? said;
  final Tail? stderr;

  /// The registry's `package@version` npx or uvx ran, when chord ran one.
  final String? pinned;
}

/// An opening error retaining its original message, cause and step facts.
final class StartFailed implements Exception {
  const StartFailed(this.failure, {required this.message, required this.cause});
  final StartFailure failure;
  final String message;
  final Object cause;

  @override
  String toString() => message;
}

/// Captures only protocol/process facts, never inferring them from words.
StartFailed startFailed(Object error, StartStep step, {String? pinned}) {
  final message = startMessage(error);
  final gone = error is AgentGone ? error : null;
  return StartFailed(
    StartFailure(
      step: step,
      exit: gone?.exit,
      closed: gone != null && gone.exit == null,
      code: error is RpcException ? error.code : null,
      said: error is RpcException ? error.message : null,
      stderr: gone?.stderr,
      pinned: pinned,
    ),
    message: message,
    cause: error,
  );
}

/// The structural failure beneath the existing resume ownership wrapper.
StartFailure? startFailureOf(Object error) {
  final seen = Set<Object>.identity();
  Object? each = error;
  while (each != null && seen.add(each)) {
    switch (each) {
      case StartFailed(:final failure):
        return failure;
      case SignInNeeded(:final cause):
        each = cause;
      case ResumeError(:final cause):
        each = cause;
      default:
        return null;
    }
  }
  return null;
}

/// Original error words, including the existing resume-id context.
String startMessage(Object error) => switch (error) {
  StartFailed(:final message) => message,
  SignInNeeded(:final cause) => cause.message,
  ResumeError(:final message) => message,
  AgentGone(:final message) => message,
  RpcException(:final message) => message,
  FormatException(:final message) => message,
  _ => '$error',
};

/// Startup headline words using the original structural precedence.
String stepWords(String message, StartFailure? failure) {
  if (failure == null) return message;
  final step = failure.step.method;
  if (failure.closed) {
    return 'it closed its connection before answering $step.';
  }
  final exit = failure.exit;
  if (exit != null) {
    return exit.signal == null
        ? 'it exited with code ${exit.code} before answering $step.'
        : 'it was stopped by ${exit.signal} before answering $step.';
  }
  final code = failure.code;
  if (code == null || code == -32000) return message;
  if (code == -32601 && failure.step != StartStep.initialize) {
    return 'it does not serve ACP sessions: not an ACP agent, or not at this version.';
  }
  return 'it refused $step: ${failure.said ?? message}';
}

/// Projects only a startup error; other error paths keep their own words.
String startupWords(Object error) =>
    stepWords(startMessage(error), startFailureOf(error));

/// What chord says of the version it ran.
String pinLine(String pinned) =>
    'chord ran $pinned, the version this chord pins.';

/// The line before the end of the agent's stderr.
const stderrHeading = 'The end of its stderr:';

/// How many lines of the tail were left out, before it.
String cutLine(int cut) => '… +$cut ${cut == 1 ? 'line' : 'lines'}';

/// What setting zeroclaw's default agent takes, said to the person.
const _zeroclawDefault =
    '[acp] default_agent = "<alias>" in ZeroClaw\'s config, or start it '
    'with zeroclaw acp --agent <alias>.';

/// The way on chord knows for [agent]'s failure: zeroclaw's, which refuses
/// a session -32602 for want of an agent alias with several and no
/// default; none for any other.
String? wayOnFor(String agent, StartFailure? failure) =>
    agent == 'zeroclaw' &&
        failure?.code == -32602 &&
        failure!.step != StartStep.initialize
    ? 'Set a default agent: $_zeroclawDefault'
    : null;

/// The block under the headline as plain lines, in order: the pin, the
/// end of stderr with what was cut, and the way on; none when it has
/// nothing.
List<String> failureLines(String agent, StartFailure? failure) {
  final stderr = failure?.stderr;
  final way = wayOnFor(agent, failure);
  return [
    if (failure?.pinned case final pinned?) pinLine(pinned),
    if (stderr != null) ...[
      stderrHeading,
      if (stderr.cut > 0) '  ${cutLine(stderr.cut)}',
      for (final line in stderr.lines) '  $line',
    ],
    ?way,
  ];
}

/// What chord tells a parent of its child's failed start beside its step's
/// words, each a sentence of its own: the pin, the last line on stderr,
/// and the way on.
String failureNote(String agent, StartFailure? failure) {
  final last = failure?.stderr?.lines.lastOrNull?.trim();
  return [
    if (failure?.pinned case final pinned?) pinLine(pinned),
    if (last != null) 'Its stderr ended: "$last".',
    if (wayOnFor(agent, failure) != null)
      'The person sets a default agent: $_zeroclawDefault',
  ].map((sentence) => ' $sentence').join();
}

/// [words] ending a sentence: a stop added unless one ends it.
String sentence(String words) =>
    RegExp(r'[.!?]$').hasMatch(words) ? words : '$words.';
