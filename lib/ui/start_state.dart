/// What the interim window knows of the agent `--agent-command` starts, and
/// how each fact about it changes that: plain Dart, no widget, no process.
library;

import '../session/sign_in.dart' show SignIn;
import '../session/start_failure.dart' show StartFailure;

/// Where the window's one opening attempt stands.
enum StartPhase {
  /// No `--agent-command`: nothing starts and no status is drawn.
  idle,

  /// Spawning, `initialize` and `session/new`.
  starting,

  /// `session/new` answered.
  connected,

  /// The opening failed before a session was connected.
  failed,

  /// The connected agent's exit was seen.
  gone,
}

/// The window's agent, as the window draws it.
final class StartState {
  /// A state in [phase]; the rest as each phase leaves it.
  const StartState({
    this.phase = StartPhase.idle,
    this.sessionId,
    this.agentName,
    this.agentVersion,
    this.reason,
    this.stderrLines = const [],
    this.stderrCut = 0,
    this.signIn,
    this.failure,
  });

  /// No agent to start.
  static const idle = StartState();

  final StartPhase phase;

  /// The connected session's id; kept once gone.
  final String? sessionId;

  /// What the agent called itself at `initialize`, when it did.
  final String? agentName;

  /// Its version, when it said one.
  final String? agentVersion;

  /// Why it failed or went.
  final String? reason;

  /// The end of its stderr, as the client keeps it, possibly empty.
  final List<String> stderrLines;

  /// How many non-empty stderr lines came before [stderrLines].
  final int stderrCut;

  /// The login the agent needs, when that is why it did not start.
  final SignIn? signIn;

  /// Why it did not start, as chord knows it.
  final StartFailure? failure;
}

/// Something that happened to the window's agent.
sealed class StartEvent {
  const StartEvent();
}

/// The window asked for its agent.
final class StartRequested extends StartEvent {
  /// The one opening attempt begins.
  const StartRequested();
}

/// `session/new` answered [sessionId], the agent having called itself
/// [agentName] at [agentVersion].
final class SessionOpened extends StartEvent {
  /// A session opened.
  const SessionOpened(this.sessionId, {this.agentName, this.agentVersion});

  final String sessionId;
  final String? agentName;
  final String? agentVersion;
}

/// The opening failed for [reason], the agent's stderr ending in [lines].
final class StartFailed extends StartEvent {
  /// A failed opening.
  const StartFailed(
    this.reason, {
    this.lines = const [],
    this.cut = 0,
    this.signIn,
    this.failure,
  });

  final String reason;
  final List<String> lines;
  final int cut;
  final SignIn? signIn;
  final StartFailure? failure;
}

/// The connected agent's exit was seen, said as [reason], its stderr
/// ending in [lines].
final class AgentExited extends StartEvent {
  /// The agent went.
  const AgentExited(this.reason, {this.lines = const [], this.cut = 0});

  final String reason;
  final List<String> lines;
  final int cut;
}

/// [state] after [event]. Only idle → starting, starting → connected or
/// failed, and connected → gone move; anything else, late or twice, leaves
/// [state] as it is, so nothing revives a failed or gone window.
StartState reduceStart(StartState state, StartEvent event) =>
    switch ((state.phase, event)) {
      (StartPhase.idle, StartRequested()) => const StartState(
        phase: StartPhase.starting,
      ),
      (
        StartPhase.starting,
        SessionOpened(:final sessionId, :final agentName, :final agentVersion),
      )
          when sessionId.isNotEmpty =>
        StartState(
          phase: StartPhase.connected,
          sessionId: sessionId,
          agentName: _present(agentName),
          agentVersion: _present(agentVersion),
        ),
      (
        StartPhase.starting,
        StartFailed(
          :final reason,
          :final lines,
          :final cut,
          :final signIn,
          :final failure,
        ),
      ) =>
        StartState(
          phase: StartPhase.failed,
          reason: reason,
          stderrLines: List.unmodifiable(lines),
          stderrCut: cut,
          signIn: signIn,
          failure: failure,
        ),
      (
        StartPhase.connected,
        AgentExited(:final reason, :final lines, :final cut),
      ) =>
        StartState(
          phase: StartPhase.gone,
          sessionId: state.sessionId,
          agentName: state.agentName,
          agentVersion: state.agentVersion,
          reason: reason,
          stderrLines: List.unmodifiable(lines),
          stderrCut: cut,
        ),
      _ => state,
    };

String? _present(String? value) =>
    value == null || value.isEmpty ? null : value;

/// The line before the end of the agent's stderr, as the original's.
const stderrHeading = 'The end of its stderr:';

/// How many lines of the tail were left out, as the original says it.
String cutLine(int cut) => '… +$cut ${cut == 1 ? 'line' : 'lines'}';

/// The status row for [state], the agent called [agent]; null when idle.
String? statusLine(StartState state, String agent) => switch (state.phase) {
  StartPhase.idle => null,
  StartPhase.starting => 'Starting $agent…',
  StartPhase.connected => 'Connected',
  StartPhase.failed => '$agent did not start: ${state.reason}',
  StartPhase.gone => state.reason,
};

/// The rows under the quit hint: the end of the agent's stderr, with what
/// was cut, as the original's start failure shows it; none without it.
List<String> detailLines(StartState state) => state.stderrLines.isEmpty
    ? const []
    : [
        stderrHeading,
        if (state.stderrCut > 0) '  ${cutLine(state.stderrCut)}',
        for (final line in state.stderrLines) '  $line',
      ];

/// [text] as one row of plain text: every control character, an escape
/// sequence's or a newline, shown as U+FFFD instead of reaching the
/// terminal.
String printable(String text) =>
    text.replaceAll(RegExp('[\u0000-\u001f\u007f-\u009f]'), '�');
