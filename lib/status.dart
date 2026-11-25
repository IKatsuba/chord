/// What chord tells the terminal it is doing: one root record of the
/// Program Status Protocol (OSC 7501), from the original's `status.ts`,
/// for every agent of the window at once.
library;

import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart'
    show ProgramState, ProgramStatus, ProgramStatusKind;

import 'notify.dart';
import 'session/waits.dart';
import 'session/window_agents.dart' show WindowAgents, notifiedName;

/// Every report names chord, as a report replaces its record whole.
const _app = 'chord';

/// The most a message may take, in UTF-8 bytes, as the protocol bounds it.
const messageBytes = 2048;

/// The most a title may take, in UTF-8 bytes: 256 once base64-encoded, as
/// it goes on the wire.
const titleBytes = 192;

/// What one wait on the person is, as the protocol's kinds name it.
ProgramStatusKind _kindOf(AskingWait wait) => switch (wait) {
  PermissionAsk() => ProgramStatusKind.permission,
  InputAsk(url: true) => ProgramStatusKind.auth,
  InputAsk() => ProgramStatusKind.question,
};

/// What the record says of an agent's failure.
String _failureMessage(Failure failure, String agent) => switch (failure) {
  Failure.exited => '$agent exited',
  Failure.start => '$agent failed to start',
  Failure.turn => "$agent's turn failed",
};

final _controls = RegExp(r'[\x00-\x1f\x7f-\x9f]');

/// [text] as one line the protocol takes in a field of [limit] UTF-8 bytes:
/// every control character a space, as a notification's text is, and cut
/// on a character's edge, a joined emoji or an accent kept whole.
String statusLine(String text, int limit) {
  final flat = text.replaceAll(_controls, ' ');
  final cut = StringBuffer();
  var bytes = 0;
  for (final character in flat.characters) {
    bytes += utf8.encode(character).length;
    if (bytes > limit) break;
    cut.write(character);
  }
  return cut.toString();
}

/// [text] as the record's message takes it.
String messageLine(String text) => statusLine(text, messageBytes);

/// The protocol's states one agent can be in, the first first: the record
/// takes the first any agent of the window is in.
const _order = [
  ProgramState.blocked,
  ProgramState.error,
  ProgramState.working,
  ProgramState.done,
  ProgramState.idle,
];

/// One agent's state, and since when, which of several in one state is the
/// oldest.
typedef _AgentStatus = ({
  ProgramState state,
  AskingWait? asking,
  Failure? failure,
  num since,
  int key,
});

/// One agent's state: asked something; failed or gone; a turn running; a
/// turn ended that the person has not seen; else idle. A monitor or task
/// running between turns leaves it idle.
_AgentStatus _agentStatus(AgentWait wait, int key) {
  if (wait.asking case final asking?) {
    return (
      state: ProgramState.blocked,
      asking: asking.on,
      failure: null,
      since: asking.since,
      key: key,
    );
  }
  final failure = wait.exited
      ? Failure.exited
      : (failureOf(wait) ?? wait.ended?.failure);
  if (failure != null) {
    return (
      state: ProgramState.error,
      asking: null,
      failure: failure,
      since: wait.unseen?.since ?? wait.stopped ?? 0,
      key: key,
    );
  }
  if (wait.working case final working?) {
    return (
      state: ProgramState.working,
      asking: null,
      failure: null,
      since: working,
      key: key,
    );
  }
  if (wait.unseen?.kind == UnseenKind.replied || wait.ended != null) {
    return (
      state: ProgramState.done,
      asking: null,
      failure: null,
      since: wait.unseen?.since ?? wait.stopped ?? 0,
      key: key,
    );
  }
  return (
    state: ProgramState.idle,
    asking: null,
    failure: null,
    since: 0,
    key: key,
  );
}

/// The root record for every agent of the window: the first state in
/// [_order] any of them is in, and of those in it, the one waiting longest,
/// then main, then the list's order, named as its notification names it.
/// Only blocked, done and error say why, as a notification would. [title]
/// names the main session, as the person knows it; none while it has no
/// name.
ProgramStatus programStatus<C>(WindowAgents<C> agents, {String? title}) {
  final cut = title == null ? '' : statusLine(title, titleBytes);
  final named = cut.trim().isEmpty ? null : cut;
  final all = [
    if (agents.main case final main?) _agentStatus(main.wait, main.key),
    for (final child in agents.children) _agentStatus(child.wait, child.key),
  ];
  final state = _order.firstWhere(
    (each) => all.any((agent) => agent.state == each),
    orElse: () => ProgramState.idle,
  );
  final first =
      (all.where((agent) => agent.state == state).toList()..sort(
            (a, b) => a.since != b.since
                ? a.since.compareTo(b.since)
                : a.key.compareTo(b.key),
          ))
          .firstOrNull;
  if (first == null ||
      state == ProgramState.idle ||
      state == ProgramState.working) {
    return ProgramStatus(state, app: _app, title: named);
  }
  final name = notifiedName(agents, first.key) ?? '';
  final message = first.asking != null
      ? waitMessage(first.asking!, name)
      : first.failure != null
      ? _failureMessage(first.failure!, name)
      : waitMessage(const TurnEnded(), name);
  return ProgramStatus(
    state,
    app: _app,
    title: named,
    kind: first.asking == null ? null : _kindOf(first.asking!),
    message: messageLine(message),
  );
}
