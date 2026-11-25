// Codex Guardian reviews, with codex-acp v2.2.2's structured verdicts, as
// the original's scenarios/guardian.ts.
import '../turn.dart';
import 'agents.dart';

const _verdicts = ['approved', 'denied', 'timedOut', 'aborted'];

Map<String, Object?> _event(String status) => {
  'action': {
    'type': 'command',
    'source': 'unifiedExec',
    'command': 'printf ready',
  },
  'review': {
    'status': status,
    'riskLevel': 'low',
    'userAuthorization': 'high',
    'rationale': 'A scripted Guardian review.',
  },
};

List<Object?> _content(String status) => [
  {
    'type': 'content',
    'content': {
      'type': 'text',
      'text':
          'Status: $status\nAction: exec printf ready\nRisk: low\n'
          'Authorization: high\nRationale: A scripted Guardian review.',
    },
  },
];

Future<String> _guardian(Turn turn, bool gated) async {
  final ids = <String, String>{};
  for (final status in [..._verdicts, 'inProgress', 'unstructured']) {
    final toolCallId = 'guardian_assessment:${turn.callId(status)}';
    ids[status] = toolCallId;
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': toolCallId,
      'title': 'Guardian Review',
      'kind': 'think',
      'status': 'in_progress',
      if (status != 'unstructured') 'rawInput': _event('inProgress'),
      'content': _content('In progress'),
    });
  }
  await turn.say(['Guardian reviews opened.']);
  if (gated) await gateOpened(turn, gateRelease);

  const words = {
    'approved': 'Approved',
    'denied': 'Denied',
    'timedOut': 'Timed out',
    'aborted': 'Aborted',
  };
  for (final status in _verdicts) {
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': ids[status],
      'status': status == 'approved' ? 'completed' : 'failed',
      'rawInput': null,
      'rawOutput': _event(status),
      'content': _content(words[status]!),
    });
  }
  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': 'guardian_assessment:${turn.callId('already-approved')}',
    'title': 'Guardian Review',
    'kind': 'think',
    'status': 'completed',
    'rawInput': _event('approved'),
    'content': _content('Approved'),
  });
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': ids['unstructured'],
    'status': 'completed',
    'content': _content('Approved'),
  });
  await turn.say(['Guardian reviews finished.']);
  return 'end_turn';
}

final Map<String, Play> guardian = {
  'guardian': (turn) => _guardian(turn, false),
  'guardiangated': (turn) => _guardian(turn, true),
};
