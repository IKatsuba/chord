// Tool calls that name a subagent (CHD-629): `{type: "session"}` content
// referring to a child announced before, and to one never announced, as
// the original's scenarios/links.ts.
import '../turn.dart';
import 'agents.dart';

/// The grandchild `subagentgrandlinked` announces, then refers to.
const grandchildTitle = 'Lint the parser';

/// The child `subagentlinked` announces, then refers to.
const linkedTitle = 'Watch the build';

/// A reference to session [sessionId], as a call's content carries it.
Map<String, Object?> _reference(String sessionId) => {
  'type': 'session',
  'sessionId': sessionId,
};

Map<String, Object?> _stopped() => {
  'type': 'content',
  'content': {'type': 'text', 'text': 'Stopped.'},
};

Update _running(String sessionId, String title) => {
  'sessionUpdate': 'subagent_update',
  'sessionId': sessionId,
  'title': title,
  'capabilities': <String, Object?>{},
  'state': {'state': 'running'},
};

final Map<String, Play> links = {
  // A child announced, then calls about it.
  'subagentlinked': (turn) async {
    final child = turn.callId('child');
    await turn.send(_running(child, linkedTitle));
    final stop = turn.callId('stop');
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': stop,
      'title': 'TaskStop',
      'kind': 'other',
      'status': 'in_progress',
      'content': [_reference(child)],
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': stop,
      'status': 'completed',
      'content': [_stopped(), _reference(child), _reference(child)],
    });
    final send = turn.callId('send');
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': send,
      'title': 'SendMessage',
      'kind': 'other',
      'status': 'pending',
      'content': [_reference(child)],
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': send,
      'status': 'failed',
      'content': [_reference(child)],
    });
    await turn.say(['Stopped the build watcher.']);
    return 'end_turn';
  },

  // A child that announces a child of its own; then a call of the
  // parent's about the grandchild, running until the gate is released.
  'subagentgrandlinked': (turn) async {
    final child = Turn(turn.client, turn.callId('child'), turn.signal);
    final grandchild = turn.callId('grandchild');
    await turn.send(_running(child.sessionId, linkedTitle));
    await child.send(_running(grandchild, grandchildTitle));
    final stop = turn.callId('stop');
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': stop,
      'title': 'TaskStop',
      'kind': 'other',
      'status': 'in_progress',
      'content': [_reference(grandchild)],
    });
    await gateOpened(turn, gateRelease);
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': stop,
      'status': 'completed',
      'content': [_stopped(), _reference(grandchild)],
    });
    return 'end_turn';
  },

  // A reference to a session never announced names nothing.
  'subagentstranger': (turn) async {
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': turn.callId('stop'),
      'title': 'TaskStop',
      'kind': 'other',
      'status': 'completed',
      'content': [_stopped(), _reference('never-announced')],
    });
    return 'end_turn';
  },
};
