// A generic agent review hold, including headless denial despite allow-all,
// as the original's scenarios/review_permissions.ts.
import '../turn.dart';

Future<String> _reviewed(Turn turn, String outcome) async {
  final toolCall = {
    'toolCallId': turn.callId('review'),
    'title': 'Run a reviewed action',
    'kind': 'execute',
    'status': 'pending',
  };
  await turn.send({'sessionUpdate': 'tool_call', ...toolCall});

  final response = await turn.client.request('session/request_permission', {
    'sessionId': turn.sessionId,
    'toolCall': toolCall,
    'options': [
      {'optionId': 'allow', 'name': 'Allow once', 'kind': 'allow_once'},
      {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
    ],
    '_meta': {
      'chord/permission': {
        'review': {
          'outcome': outcome,
          'reason': outcome == 'caution'
              ? 'Fixture safety review: caution.'
              : outcome == 'incomplete'
              ? 'The proposed action exceeded the review input limit.'
              : 'the reviewer did not answer in 30 s',
        },
        'deadlineAt': DateTime.now().millisecondsSinceEpoch + 300000,
      },
    },
  }, cancellation: turn.signal);
  final answered = (response['outcome'] as Map?) ?? const {};
  final answer = answered['outcome'] == 'selected'
      ? (answered['optionId'] == null ? 'undefined' : '${answered['optionId']}')
      : 'cancelled';
  await turn.say(['Review permission: $answer.']);
  return 'end_turn';
}

final Map<String, Play> reviewPermissions = {
  'reviewpermission': (turn) => _reviewed(turn, 'caution'),
  'reviewincomplete': (turn) => _reviewed(turn, 'incomplete'),
  'reviewfailed': (turn) => _reviewed(turn, 'failed'),
};
