// A saved session's plans by id read back as the window drew them live:
// a markdown plan's reply rewritten in place, a file plan's reply, a list
// by id, and a `plan_removed` taking the one it names.
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

Map<String, Object?> _update(Map<String, Object?> update) => {
  'type': 'update',
  'turnId': 't1',
  'update': update,
};

Map<String, Object?> _plan(Map<String, Object?> plan) =>
    _update({'sessionUpdate': 'plan_update', 'plan': plan});

Transcript _replayed(List<Map<String, Object?>> lines) {
  final past = PreparedHistory.fromJson(
    recordActions([
      {
        'type': 'prompt',
        'turnId': 't1',
        'at': 0,
        'prompt': 'plan',
        'images': 0,
      },
      ...lines,
    ]).toJson(),
  );
  return past.actions.fold(Transcript.empty, reduceTranscript);
}

void main() {
  test('plans by id survive replay: rewritten in place, removed by id', () {
    final state = _replayed([
      _plan({'type': 'markdown', 'planId': 'm', 'content': '1. Read'}),
      _plan({'type': 'file', 'planId': 'f', 'uri': 'file:///plan.md'}),
      _plan({
        'type': 'markdown',
        'planId': 'm',
        'content': '1. Read\n2. Write',
      }),
      _plan({
        'type': 'items',
        'planId': 'p',
        'entries': [
          {'content': 'Read', 'priority': 'high', 'status': 'pending'},
        ],
      }),
      _update({'sessionUpdate': 'plan_removed', 'planId': 'f'}),
    ]);
    expect(
      [
        for (final entry in state.entries)
          if (entry is AssistantEntry) (entry.planId, entry.text.text),
      ],
      [('m', '1. Read\n2. Write')],
    );
    expect(state.planId, 'p');
    expect([for (final step in state.plan) step.content], ['Read']);
  });
}
