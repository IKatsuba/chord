// The original's transcript/permissions.ts for a box of questions: the tool
// call it came out of is marked asked from when the box opens, kept so as
// updates merge, and a form with no questions, or a box out of no call,
// marks nothing; a box whose wait ran out is recorded timed out.
import 'package:chord/session/questions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

const _questions = Questions(QuestionsAgent.claude, [
  Question(
    id: 'question_0',
    text: 'Which?',
    options: [QuestionOption(value: 'a', title: 'A')],
    multiSelect: false,
    required: false,
  ),
]);

FormWait _box({
  String? toolCallId = 'ask',
  Questions? questions = _questions,
}) => FormWait(
  'e1',
  'Which?',
  schema: const {'type': 'object', 'properties': <String, Object?>{}},
  questions: questions,
  toolCallId: toolCallId,
);

final _call = update('t1', {
  'sessionUpdate': 'tool_call',
  'toolCallId': 'ask',
  'title': 'Which?',
  'kind': 'other',
  'status': 'pending',
});

ToolCall _callIn(Transcript state) =>
    state.entries.whereType<ToolEntry>().single.call;

void main() {
  test('the call a box of questions came out of reads as asked from when '
      'the box opens, through its updates and once answered', () {
    final opened = fold([
      const PromptAction('t1', 'askclaude', 0),
      _call,
      ElicitationRequestedAction('t1', _box()),
    ]);
    expect(_callIn(opened).asked, isTrue);
    final updated = fold([
      update('t1', {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'ask',
        'status': 'in_progress',
      }),
    ], opened);
    expect(_callIn(updated).asked, isTrue);
    expect(_callIn(updated).status, 'in_progress');
    final answered = fold([
      const ElicitationSettledAction(
        't1',
        'e1',
        ElicitationAccepted({'question_0': 'a'}),
      ),
    ], updated);
    expect(_callIn(answered).asked, isTrue);
    expect(answered.entries.last, isA<ElicitationEntry>());
  });

  test('a form with no questions, or a box out of no call, marks no '
      'call', () {
    for (final wait in [_box(questions: null), _box(toolCallId: null)]) {
      final state = fold([
        const PromptAction('t1', 'askclaude', 0),
        _call,
        ElicitationRequestedAction('t1', wait),
      ]);
      expect(_callIn(state).asked, isFalse);
    }
  });

  test('a box withdrawn as its wait ran out is recorded timed out, and the '
      'answer reads back as such', () {
    final state = fold([
      const PromptAction('t1', 'askcodexwait', 0),
      ElicitationRequestedAction('t1', _box(toolCallId: null)),
      const ElicitationSettledAction('t1', 'e1', ElicitationTimedOut()),
    ]);
    expect(
      state.entries.whereType<ElicitationEntry>().single.outcome,
      ElicitationOutcome.timedOut,
    );
    expect(elicitationAnswerJson(const ElicitationTimedOut()), {
      'type': 'timed_out',
    });
    expect(
      elicitationAnswerFrom({'type': 'timed_out'}),
      isA<ElicitationTimedOut>(),
    );
  });
}
