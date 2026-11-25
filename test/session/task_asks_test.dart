// Task agents in their parent's conversation, on scripted sessions, as the
// original's conversation.ts adopts them: two tasks and the parent asking
// at once, each answer reaching only its asker, a closed task's ask
// withdrawn, a late answer to it ignored; Esc stopping the turn's tasks
// with no report, the aside going ahead of the person's next prompt; an
// ask between turns holding the queue until the task ends.
import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/tasks.dart';
import 'package:chord/session/elicitations.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

/// A task of [parent]'s on a scripted session of its own.
final class _Task {
  _Task(Scripted parent, this.id, String name) {
    agent = TaskAgent(
      TaskStart(id: id, name: name, runtime: 'scripted', prompt: 'job'),
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

/// [scripted]'s transcript, as the window folds its events.
Transcript _folded(Scripted scripted) => [
  for (final event in scripted.events)
    if (event is Transcribed) event.action,
].fold(const Transcript(), reduceTranscript);

List<PermissionWait> _asks(Scripted scripted) =>
    switch (_folded(scripted).turn) {
      AwaitingPermission(:final permissions) => permissions,
      _ => const [],
    };

String _optionOf(acp.RequestPermissionResponse response) =>
    '${response.toJson()['outcome']}';

void main() {
  _testerTaskForms();
  _testerWithdrawalOrderings();
  test('two tasks and the parent ask at once: three asks, distinct ids; an '
      'answer reaches its asker only; a closed task withdraws its own; a '
      'late answer to it changes nothing', () async {
    final parent = Scripted();
    parent.conversation.start();
    await pumpEventQueue();
    parent.conversation.send('go');
    await pumpEventQueue();
    final a = _Task(parent, 'task-a', 'Fix it');
    final b = _Task(parent, 'task-b', 'Test it');
    await pumpEventQueue();
    // Each task's job went as its first turn.
    expect(a.own.session.turns.single.text, 'job');
    expect(b.own.session.turns.single.text, 'job');

    final answers = <String, String>{};
    a.own.session.ask().then((r) => answers['a'] = _optionOf(r)).ignore();
    final bWithdrawn = CancellationToken();
    b.own.session
        .ask(token: bWithdrawn)
        .then((r) => answers['b'] = _optionOf(r))
        .ignore();
    parent.session.ask().then((r) => answers['main'] = _optionOf(r)).ignore();
    await pumpEventQueue();

    final asks = _asks(parent);
    expect(asks, hasLength(3));
    expect({for (final ask in asks) ask.id}, hasLength(3));
    final byAsker = {for (final ask in asks) ask.subagentId: ask.id};
    expect(byAsker.keys, unorderedEquals(['task-a', 'task-b', null]));

    // Answering task a's reaches task a alone.
    parent.conversation.choose(byAsker['task-a']!, 'allow');
    await pumpEventQueue();
    expect(answers, {'a': '{outcome: selected, optionId: allow}'});
    expect(
      _asks(parent).map((ask) => ask.subagentId),
      unorderedEquals(['task-b', null]),
    );

    // Closing task b, as close_agent does: its turn is stopped, and its
    // agent withdraws its ask as it cancels.
    b.agent.cancel(const TaskStop.agent('main'));
    expect(b.own.session.cancels, 1);
    bWithdrawn.cancel();
    b.own.session.turns.single.answer(const TurnAnswered('cancelled'));
    await pumpEventQueue();
    expect(b.agent.running, isFalse);
    expect(_asks(parent).map((ask) => ask.subagentId), [null]);
    expect(parent.conversation.tasks.map((task) => task.id), ['task-a']);
    expect(parent.conversation.endedTasks, {'task-b': 'Test it'});

    // A late answer to task b's ask goes nowhere.
    final before = parent.events.length;
    parent.conversation.choose(byAsker['task-b']!, 'allow');
    await pumpEventQueue();
    expect(parent.events.length, before);
    expect(answers.containsKey('main'), isFalse);
    expect(_asks(parent).single.subagentId, isNull);

    // The parent's own is its own to answer.
    parent.conversation.choose(byAsker[null]!, 'deny');
    await pumpEventQueue();
    expect(answers['main'], '{outcome: selected, optionId: deny}');
    expect(_asks(parent), isEmpty);
    // The closed task sent no report; it was stopped by an agent, so no
    // line waits for the person's prompt.
    expect(parent.session.turns, hasLength(1));
  });

  test('Esc stops the turn and its tasks, which send no report; the aside '
      "goes ahead of the person's next prompt", () async {
    final parent = Scripted();
    parent.conversation.start();
    await pumpEventQueue();
    parent.conversation.send('go');
    await pumpEventQueue();
    final task = _Task(parent, 'task-1', 'Fix it');
    await pumpEventQueue();

    parent.conversation.interrupt();
    expect(task.own.session.cancels, 1);
    task.own.session.turns.single.answer(const TurnAnswered('cancelled'));
    parent.session.turns.single.answer(const TurnAnswered('cancelled'));
    await pumpEventQueue();
    expect(task.agent.running, isFalse);
    final block = _folded(
      parent,
    ).entries.whereType<SubagentEntry>().single.subagent;
    expect(block.state, SubagentState.cancelled);
    expect(block.task!.stoppedWith, TaskStop.esc);
    // No report: no turn of the task's came.
    expect(parent.session.turns, hasLength(1));

    parent.conversation.send('next');
    await pumpEventQueue();
    expect(
      parent.session.turns.last.text,
      '<message from="Fix it · scripted">\n'
      'The person stopped this task before it reported.\n'
      '</message>\n\nnext',
    );
    // What the person typed is drawn as they typed it.
    expect(_folded(parent).entries.whereType<UserEntry>().last.text, 'next');
    // The aside goes once.
    parent.session.turns.last.answer();
    await pumpEventQueue();
    parent.conversation.send('again');
    await pumpEventQueue();
    expect(parent.session.turns.last.text, 'again');
  });

  test("a task's ask with no turn of its parent's running holds the "
      "parent's queue until it is answered, and the task's report then "
      'goes', () async {
    final parent = Scripted();
    parent.conversation.start();
    await pumpEventQueue();
    final task = _Task(parent, 'task-1', 'Fix it');
    await pumpEventQueue();
    String? answered;
    task.own.session.ask().then((r) => answered = _optionOf(r)).ignore();
    await pumpEventQueue();
    final ask = _asks(parent).single;
    expect(ask.subagentId, 'task-1');

    // The person's prompt waits for the answer.
    parent.conversation.send('later');
    await pumpEventQueue();
    expect(parent.session.turns, isEmpty);

    parent.conversation.choose(ask.id, 'allow');
    await pumpEventQueue();
    expect(answered, contains('allow'));
    task.own.session.chunk('Fixed.');
    task.own.session.turns.single.answer();
    // The quiet after an answer between turns, then what waited goes.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await pumpEventQueue();
    expect([for (final turn in parent.session.turns) turn.text], ['later']);
    parent.session.turns.single.answer();
    // The next turn waits for the agent to go quiet after an answer.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await pumpEventQueue();
    expect(
      parent.session.turns.last.text,
      '<message from="Fix it · scripted · report">\nFixed.\n</message>',
    );
  });

  test("a parent's clear lets its tasks go: their end is no news to the "
      'fresh session', () async {
    final parent = Scripted();
    parent.conversation.start();
    await pumpEventQueue();
    final task = _Task(parent, 'task-1', 'Fix it');
    await pumpEventQueue();
    final cleared = parent.conversation.clear();
    final from = parent.events.length;
    await pumpEventQueue();
    expect(task.agent.running, isFalse);
    expect(task.own.session.closes, 1);
    expect(parent.conversation.tasks, isEmpty);
    expect(
      parent
          .since(from)
          .whereType<Transcribed>()
          .where((event) => event.action is UpdateAction),
      isEmpty,
    );
    await cleared;
  });

  test("the parent's close closes its tasks", () async {
    final parent = Scripted();
    parent.conversation.start();
    await pumpEventQueue();
    final task = _Task(parent, 'task-1', 'Fix it');
    await pumpEventQueue();
    await parent.conversation.close();
    expect(task.agent.running, isFalse);
    expect(task.own.session.closes, 1);
  });
}

void _testerTaskForms() {
  group('CTUI-35 tester: task forms and cancellation boundaries', () {
    Map<String, Object?> form(String session) => {
      'sessionId': session,
      'mode': 'form',
      'message': 'Name it',
      'requestedSchema': {'type': 'object', 'properties': <String, Object?>{}},
    };
    test(
      'parent and two tasks answer distinct UUID forms without crossing sessions',
      () async {
        final parent = Scripted();
        parent.conversation.start();
        await pumpEventQueue();
        parent.conversation.send('go');
        await pumpEventQueue();
        final a = _Task(parent, 'form-a', 'First');
        final b = _Task(parent, 'form-b', 'Second');
        addTearDown(parent.conversation.close);
        await pumpEventQueue();
        final tokens = [for (var i = 0; i < 3; i++) CancellationToken()];
        final answers = <String, Map<String, Object?>>{};
        parent.session.elicitations
            .handler(form(parent.session.id), tokens[0])
            .then((r) => answers['parent'] = r);
        a.own.session.elicitations
            .handler(form(a.own.session.id), tokens[1])
            .then((r) => answers['a'] = r);
        b.own.session.elicitations
            .handler(form(b.own.session.id), tokens[2])
            .then((r) => answers['b'] = r);
        await pumpEventQueue();
        final pending = _folded(parent).asking;
        expect(pending, hasLength(3));
        expect(pending.map((wait) => wait.id).toSet(), hasLength(3));
        final byAsker = {for (final wait in pending) wait.subagentId: wait.id};
        final uuid = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        );
        for (final id in byAsker.values) {
          expect(uuid.hasMatch(id), isTrue);
        }
        parent.conversation.answer(
          byAsker['form-b']!,
          const AcceptReply({'name': 'B'}),
        );
        await pumpEventQueue();
        expect(answers, {
          'b': {
            'action': 'accept',
            'content': {'name': 'B'},
          },
        });
        tokens[1].cancel();
        await pumpEventQueue();
        expect(_folded(parent).asking.map((wait) => wait.subagentId), [null]);
        final before = parent.events.length;
        parent.conversation.answer(
          byAsker['form-a']!,
          const AcceptReply({'name': 'late'}),
        );
        await pumpEventQueue();
        expect(parent.events.length, before);
        parent.conversation.answer(byAsker[null]!, const DeclineReply());
        await pumpEventQueue();
        expect(answers['parent'], {'action': 'decline'});
        expect(answers['a'], {'action': 'cancel'});
        expect(_folded(parent).asking, isEmpty);
      },
    );

    test(
      'ending one task withdraws its unacknowledged form without touching the other task',
      () async {
        final parent = Scripted();
        parent.conversation.start();
        await pumpEventQueue();
        parent.conversation.send('go');
        await pumpEventQueue();
        final a = _Task(parent, 'form-a', 'First');
        final b = _Task(parent, 'form-b', 'Second');
        addTearDown(parent.conversation.close);
        await pumpEventQueue();
        final answers = <String, Map<String, Object?>>{};
        a.own.session.elicitations
            .handler(form(a.own.session.id), CancellationToken())
            .then((r) => answers['a'] = r);
        b.own.session.elicitations
            .handler(form(b.own.session.id), CancellationToken())
            .then((r) => answers['b'] = r);
        await pumpEventQueue();
        expect(_folded(parent).asking, hasLength(2));
        a.agent.cancel(const TaskStop.agent('main'));
        a.own.session.turns.single.answer(const TurnAnswered('cancelled'));
        await pumpEventQueue();
        expect(a.agent.running, isFalse);
        expect(answers['a'], {'action': 'cancel'});
        expect(answers.containsKey('b'), isFalse);
        expect(_folded(parent).asking.map((wait) => wait.subagentId), [
          'form-b',
        ]);
      },
    );

    test(
      'two tasks cancelled by Esc add one aside each and no late report',
      () async {
        final parent = Scripted();
        parent.conversation.start();
        await pumpEventQueue();
        parent.conversation.send('go');
        await pumpEventQueue();
        final a = _Task(parent, 'cancel-a', 'First');
        final b = _Task(parent, 'cancel-b', 'Second');
        addTearDown(parent.conversation.close);
        await pumpEventQueue();
        parent.conversation.interrupt();
        a.own.session.chunk('late successful text');
        b.own.session.chunk('late successful text');
        a.own.session.turns.single.answer();
        b.own.session.turns.single.answer();
        parent.session.turns.single.answer(const TurnAnswered('cancelled'));
        await pumpEventQueue();
        expect(parent.conversation.tasks, isEmpty);
        expect(parent.session.turns, hasLength(1));
        parent.conversation.send('next');
        await pumpEventQueue();
        final next = parent.session.turns.last.text;
        expect(
          RegExp(
            'The person stopped this task before it reported.',
          ).allMatches(next),
          hasLength(2),
        );
        expect(next, contains('<message from="First · scripted">'));
        expect(next, contains('<message from="Second · scripted">'));
        expect(next, isNot(contains('late successful text')));
        parent.session.turns.last.answer();
        await pumpEventQueue();
        parent.conversation.send('again');
        await pumpEventQueue();
        expect(parent.session.turns.last.text, 'again');
      },
    );
  });
}

void _testerWithdrawalOrderings() {
  group('CTUI-35 tester: ended ask ordering', () {
    for (final permission in [true, false]) {
      for (final withdrawFirst in [true, false]) {
        test(
          'permission=$permission withdraw-before-result=$withdrawFirst settles once and keeps its sibling answerable',
          () async {
            final parent = Scripted();
            parent.conversation.start();
            await pumpEventQueue();
            parent.conversation.send('go');
            await pumpEventQueue();
            final a = _Task(parent, 'ordering-a', 'First');
            final b = _Task(parent, 'ordering-b', 'Second');
            addTearDown(parent.conversation.close);
            await pumpEventQueue();
            final cancelled = CancellationToken();
            final answers = <String, Object?>{};
            for (final (name, task) in [('a', a), ('b', b)]) {
              final token = name == 'a' ? cancelled : CancellationToken();
              if (permission) {
                task.own.session
                    .ask(token: token)
                    .then((r) => answers[name] = r);
              } else {
                task.own.session.elicitations
                    .handler({
                      'sessionId': task.own.session.id,
                      'mode': 'form',
                      'message': name,
                      'requestedSchema': {
                        'type': 'object',
                        'properties': <String, Object?>{},
                      },
                    }, token)
                    .then((r) => answers[name] = r);
              }
            }
            await pumpEventQueue();
            final aId = permission
                ? _asks(parent).firstWhere((ask) => ask.subagentId == a.id).id
                : _folded(
                    parent,
                  ).asking.firstWhere((ask) => ask.subagentId == a.id).id;
            a.agent.cancel(const TaskStop.agent('main'));
            if (withdrawFirst) {
              cancelled.cancel();
              await pumpEventQueue();
            }
            a.own.session.turns.single.answer(const TurnAnswered('cancelled'));
            await pumpEventQueue();
            cancelled.cancel();
            await pumpEventQueue();
            final remaining = permission
                ? _asks(parent).map((ask) => ask.subagentId)
                : _folded(parent).asking.map((ask) => ask.subagentId);
            expect(remaining, ['ordering-b']);
            final settled = parent.events
                .whereType<Transcribed>()
                .map((e) => e.action)
                .where(
                  (action) =>
                      action is PermissionSettledAction && action.id == aId ||
                      action is ElicitationSettledAction && action.id == aId,
                )
                .toList();
            expect(settled, hasLength(1));
            expect(answers.containsKey('a'), isTrue);
            expect(answers.containsKey('b'), isFalse);
            final count = parent.events.length;
            if (permission) {
              parent.conversation.choose(aId, 'allow');
            } else {
              parent.conversation.answer(
                aId,
                const AcceptReply({'late': true}),
              );
            }
            await pumpEventQueue();
            expect(parent.events.length, count);
            if (permission) {
              parent.conversation.choose(_asks(parent).single.id, 'allow');
            } else {
              parent.conversation.answer(
                _folded(parent).asking.single.id,
                const AcceptReply({'sibling': true}),
              );
            }
            await pumpEventQueue();
            expect(answers.containsKey('b'), isTrue);
            expect(_asks(parent), isEmpty);
            expect(_folded(parent).asking, isEmpty);
          },
        );
      }
    }
  });
}
