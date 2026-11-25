// A task that ends before its agent withdraws its asks can answer none of
// them: the parent withdraws them as it lets the task go, whichever came
// first, so no box stays on screen that nothing can answer.
import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

/// A task of [parent]'s on a scripted session of its own.
final class _Task {
  _Task(Scripted parent, this.id) {
    agent = TaskAgent(
      TaskStart(id: id, name: id, runtime: 'scripted', prompt: 'job'),
      parent.conversation.taskParent(id),
      () => 7,
    );
    own.conversation.listen(agent.heard);
    parent.conversation.adopt(agent, own.conversation);
  }

  final String id;
  final own = Scripted();
  late final TaskAgent agent;
}

Transcript _folded(Scripted scripted) => [
  for (final event in scripted.events)
    if (event is Transcribed) event.action,
].fold(const Transcript(), reduceTranscript);

Map<String, Object?> _form(Scripted task, String message) => {
  'sessionId': task.session.id,
  'mode': 'form',
  'message': message,
  'requestedSchema': {'type': 'object', 'properties': <String, Object?>{}},
};

void main() {
  test("a task stopped before its agent withdraws its form: the parent's "
      'box goes with the task, the other task keeps its own', () async {
    final parent = Scripted();
    parent.conversation.start();
    await pumpEventQueue();
    parent.conversation.send('go');
    await pumpEventQueue();
    final a = _Task(parent, 'task-a');
    final b = _Task(parent, 'task-b');
    await pumpEventQueue();
    final withdrawn = CancellationToken();
    a.own.session.elicitations
        .handler(_form(a.own, 'Form A'), withdrawn)
        .ignore();
    b.own.session.elicitations
        .handler(_form(b.own, 'Form B'), CancellationToken())
        .ignore();
    await pumpEventQueue();
    expect(_folded(parent).asking.map((wait) => wait.message), [
      'Form A',
      'Form B',
    ]);

    // Stopped by an agent; its turn ends before its agent withdraws.
    a.agent.cancel(const TaskStop.agent('main'));
    a.own.session.turns.single.answer(const TurnAnswered('cancelled'));
    await pumpEventQueue();
    expect(a.agent.running, isFalse);
    withdrawn.cancel();
    await pumpEventQueue();

    expect(_folded(parent).asking.map((wait) => wait.message), ['Form B']);
  });
}
