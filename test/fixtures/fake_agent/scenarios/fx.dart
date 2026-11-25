// Synthetic fx ordering, independent of any model's language validation,
// as the original's scenarios/fx.ts.
import '../rpc.dart';
import '../turn.dart';

const fxErrorNotice =
    'The model response used a different language than your request, and fx '
    'could not accept it. Retry or name the response language explicitly.';

Map<String, Object?> _text(String text) => {
  'type': 'content',
  'content': {'type': 'text', 'text': text},
};

Future<void> _shell(Turn turn, int number) async {
  final toolCallId = turn.callId('shell');
  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': 'Running',
    'kind': 'execute',
    'status': 'pending',
    'rawInput': {'command': 'echo fixture-$number'},
  });
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'in_progress',
  });
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'in_progress',
    'content': [_text('Fixture output.')],
  });
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'completed',
    'content': [
      _text('{"session_id":null,"state":"completed","output_delta":"Fixture'),
    ],
  });
}

final Map<String, Play> fx = {
  'fxerror': (turn) async {
    await _shell(turn, 1);
    for (var number = 1; number <= 5; number++) {
      final toolCallId = turn.callId('search');
      await turn.send({
        'sessionUpdate': 'tool_call',
        'toolCallId': toolCallId,
        'title': 'Searching',
        'kind': 'search',
        'status': 'pending',
        'rawInput': {
          'path': 'fixture-skills-$number',
          'pattern': 'agent-browser',
        },
      });
      await turn.send({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': toolCallId,
        'status': 'in_progress',
      });
      await turn.send({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': toolCallId,
        'status': 'completed',
        'content': [_text('[grep] no matches for agent-browser')],
      });
    }
    await _shell(turn, 2);
    await turn.say([fxErrorNotice]);
    throw RequestError(-32603, 'ResponseLanguageMismatch');
  },
};
