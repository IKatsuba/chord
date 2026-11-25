// The original's tests/session/oneshot_test.ts for forms and links under
// -p, on its fake agent: a form is declined, told first, a link cancelled.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/session/oneshot.dart';
import 'package:chord/session/questions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';
import '../fixtures/questions.dart';

void main() {
  final skip = fakeAgentSkip;

  group('CTUI-68 tester: async question diagnostic lifecycle', () {
    test(
      'question metadata is available before an async diagnostic releases the decline',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'chord-question-diagnostic-',
        );
        final offered = Completer<FormWait>();
        final release = Completer<void>();
        final updates = <Map<String, Object?>>[];
        var completed = false;
        final work =
            runOneshot(
              agent: 'fake',
              command: fakeAgentCommand(),
              cwd: dir.path,
              prompt: 'askclaude',
              open: fakeSessionOpener(),
              onUpdate: (update) => updates.add(update.toJson()),
              onRefused: (_) {},
              onDeclined: (form) {
                offered.complete(form);
                return release.future;
              },
            ).then((outcome) {
              completed = true;
              return outcome;
            });
        try {
          final form = await offered.future;
          expect(form.questions?.agent, QuestionsAgent.claude);
          expect(form.questions?.questions, hasLength(2));
          expect(form.schema, claudeQuestionsForm['requestedSchema']);
          expect(completed, isFalse);
          expect(
            updates.where((u) => u['sessionUpdate'] == 'agent_message_chunk'),
            isEmpty,
          );
          release.complete();
          final outcome = await work;
          expect(outcome.result, isA<TurnAnswered>());
          expect(
            updates.where((u) => u['sessionUpdate'] == 'tool_call'),
            isNotEmpty,
          );
          expect(
            updates
                .where((u) => u['sessionUpdate'] == 'agent_message_chunk')
                .map((u) => (u['content'] as Map)['text'])
                .join(),
            'Elicitation answer: decline',
          );
        } finally {
          if (!release.isCompleted) release.complete();
          await work;
          dir.deleteSync(recursive: true);
        }
      },
      skip: skip,
    );
  });

  Future<(OneshotOutcome, String)> run(
    String prompt, {
    void Function(FormWait form)? onDeclined,
  }) async {
    final dir = Directory.systemTemp.createTempSync('chord-oneshot-form-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final said = StringBuffer();
    final outcome = await runOneshot(
      agent: 'fake',
      command: fakeAgentCommand(),
      cwd: dir.path,
      prompt: prompt,
      open: fakeSessionOpener(),
      onUpdate: (update) {
        if (update.kind != 'agent_message_chunk') return;
        if (update.toJson()['content'] case {'text': final String text}) {
          said.write(text);
        }
      },
      onRefused: (_) {},
      onDeclined: onDeclined,
    );
    return (outcome, '$said');
  }

  test('a form is told before it is declined, as its message', () async {
    final told = <FormWait>[];
    final (outcome, said) = await run('form', onDeclined: told.add);
    expect(said, 'Elicitation answer: decline');
    expect(
      [for (final form in told) form.message],
      ['Set up the deploy target'],
    );
    expect(
      outcome.result,
      isA<TurnAnswered>().having((r) => r.stopReason, 'stopReason', 'end_turn'),
    );
  }, skip: skip);

  test('without a callback a form still declines, and a link alongside '
      'cancels', () async {
    final [(_, form), (_, link)] = await Future.wait([
      run('form'),
      run('link'),
    ]);
    expect(form, 'Elicitation answer: decline');
    expect(link, 'Elicitation answer: cancel');
  }, skip: skip);

  test("a claude question form is told with its questions read, then "
      "declined", () async {
    final told = <FormWait>[];
    final (outcome, said) = await run('askclaude', onDeclined: told.add);
    expect(told.single.questions?.agent, QuestionsAgent.claude);
    expect(told.single.questions?.questions, hasLength(2));
    expect(said, contains('Elicitation answer: decline'));
    expect(outcome.result, isA<TurnAnswered>());
  }, skip: skip);
}
