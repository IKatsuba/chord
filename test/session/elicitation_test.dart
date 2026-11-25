// The original's tests/session/elicitation_test.ts on its fake agent: a
// form or link reaches the window through the session's bridge, its answer
// reaches the agent, a cancel withdraws it, and the conversation records
// it, and each adapter's question form arrives with its questions read.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart' show windowCapabilities;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/elicitations.dart';
import 'package:chord/session/questions.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import '../fixtures/forms.dart';
import '../fixtures/questions.dart';
import 'session_fake.dart';

/// Plays [scenario], answering its request with [reply] a moment after it
/// arrives, as a key press would; returns the request and what the agent
/// said.
Future<({PendingElicitation request, String said})> answered(
  Session session,
  String scenario,
  ElicitationReply reply,
) async {
  PendingElicitation? request;
  final unsubscribe = session.elicitations.subscribe((pending) {
    request = pending;
    Timer(const Duration(milliseconds: 10), () => pending.answer(reply));
  });
  try {
    final ran = await run(session, scenario);
    expect(request, isNotNull);
    return (request: request!, said: said(ran.updates).join());
  } finally {
    unsubscribe();
  }
}

void main() {
  final skip = fakeAgentSkip;
  final declared = windowCapabilities();

  group('CTUI-68 tester: independent pending question sessions', () {
    test(
      'closing one session rejects late answers without withdrawing another',
      () async {
        await withSession(capabilities: declared, (first, _) async {
          await withSession(capabilities: declared, (second, _) async {
            final firstAsk = Completer<PendingElicitation>();
            final secondAsk = Completer<PendingElicitation>();
            final stopFirst = first.elicitations.subscribe(firstAsk.complete);
            final stopSecond = second.elicitations.subscribe(
              secondAsk.complete,
            );
            try {
              final firstTurn = first.prompt('askcodex');
              final secondRun = run(second, 'askcodex');
              final firstRequest = await firstAsk.future;
              final secondRequest = await secondAsk.future;
              expect(firstRequest.id, isNot(secondRequest.id));
              await first.close();
              await firstTurn.result;
              expect(firstRequest.withdrawn.isCancelled, isTrue);
              firstRequest.answer(const AcceptReply({'next_note': 'stale'}));
              expect(secondRequest.withdrawn.isCancelled, isFalse);
              expect(
                (secondRequest.wait as FormWait).questions?.agent,
                QuestionsAgent.codex,
              );
              secondRequest.answer(
                const AcceptReply({'next_note': 'survivor'}),
              );
              final result = await secondRun;
              expect(
                said(result.updates).join(),
                'Elicitation answer: accept  \n{"next_note":"survivor"}',
              );
            } finally {
              stopFirst();
              stopSecond();
            }
          });
        });
      },
      skip: skip,
    );
  });

  test('a form request reaches the window with its schema', () async {
    await withSession(capabilities: declared, (session, _) async {
      final (:request, said: _) = await answered(
        session,
        'form',
        const CancelReply(),
      );
      final wait = request.wait as FormWait;
      expect(wait.message, 'Set up the deploy target');
      expect(wait.schema, formSchema);
    });
  }, skip: skip);

  test('an accepted form reaches the agent with its content', () async {
    await withSession(capabilities: declared, (session, _) async {
      const content = {'name': 'web-app', 'replicas': 3, 'region': 'us'};
      final (request: _, :said) = await answered(
        session,
        'form',
        const AcceptReply(content),
      );
      expect(
        said,
        'Elicitation answer: accept  \n'
        '{"name":"web-app","replicas":3,"region":"us"}',
      );
    });
  }, skip: skip);

  test('a declined or cancelled form reaches the agent as such', () async {
    await withSession(capabilities: declared, (session, _) async {
      for (final (reply, action) in const [
        (DeclineReply(), 'decline'),
        (CancelReply(), 'cancel'),
      ]) {
        final (request: _, :said) = await answered(session, 'form', reply);
        expect(said, 'Elicitation answer: $action');
      }
    });
  }, skip: skip);

  test('a link request carries the link, and nothing opens it', () async {
    final completed = <Map<String, Object?>>[];
    await withSession(capabilities: declared, (session, _) async {
      final (:request, :said) = await answered(
        session,
        'link',
        const DeclineReply(),
      );
      final wait = request.wait as LinkWait;
      expect(wait.url, linkUrl);
      expect(wait.message, 'Sign in to Example to continue');
      expect(said, 'Elicitation answer: decline');
    });
    expect(completed, isEmpty);
  }, skip: skip);

  test('a link accepted is said complete by the agent, which the session '
      'hands on', () async {
    final dir = Directory.systemTemp.createTempSync('chord-link-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final completed = <Map<String, Object?>>[];
    final session = await openSession(
      agent: 'fake',
      command: fakeAgentCommand(),
      cwd: dir.path,
      open: fakeOpenerWith(capabilities: declared),
      onElicitationComplete: completed.add,
    );
    try {
      final (:request, :said) = await answered(
        session,
        'link',
        const AcceptReply(),
      );
      expect(said, 'Elicitation answer: accept');
      expect(completed, hasLength(1));
      expect(completed.single['elicitationId'], isA<String>());
      expect(request.wait, isA<LinkWait>());
    } finally {
      await session.close();
    }
  }, skip: skip);

  test('cancelling the turn withdraws its open form', () async {
    await withSession(capabilities: declared, (session, _) async {
      final asked = Completer<PendingElicitation>();
      session.elicitations.subscribe(asked.complete);
      final turn = session.prompt('form');
      final request = await asked.future;
      await turn.cancel();
      expect(request.withdrawn.isCancelled, isTrue);
      final result = await turn.result;
      expect(
        result,
        isA<TurnAnswered>().having((r) => r.cancelled, 'cancelled', isTrue),
      );
    });
  }, skip: skip);

  test('with nobody listening the agent hears cancel', () async {
    await withSession(capabilities: declared, (session, _) async {
      final ran = await run(session, 'form');
      expect(said(ran.updates).join(), 'Elicitation answer: cancel');
    });
  }, skip: skip);

  test("each adapter's question form reaches the window with its questions "
      'read, and its answer goes back as given', () async {
    await withSession(capabilities: declared, (session, _) async {
      for (final (scenario, agent) in const [
        ('askclaude', QuestionsAgent.claude),
        ('askclaudeone', QuestionsAgent.claude),
        ('askcodex', QuestionsAgent.codex),
        ('askdroid', QuestionsAgent.droid),
        ('askopencode', QuestionsAgent.opencode),
        ('askdimcode', QuestionsAgent.dimcode),
      ]) {
        const content = {'picked': 'yes'};
        final (:request, :said) = await answered(
          session,
          scenario,
          const AcceptReply(content),
        );
        expect((request.wait as FormWait).questions?.agent, agent);
        expect(said, 'Elicitation answer: accept  \n{"picked":"yes"}');
      }
    });
  }, skip: skip);

  test("a form with no adapter's marks reaches the window with no "
      'questions', () async {
    await withSession(capabilities: declared, (session, _) async {
      final (:request, said: _) = await answered(
        session,
        'form',
        const CancelReply(),
      );
      expect((request.wait as FormWait).questions, isNull);
    });
  }, skip: skip);

  group('CHD-1 tester: question request round trips', () {
    final cases = [
      (
        scenario: 'askclaude',
        agent: QuestionsAgent.claude,
        form: claudeQuestionsForm,
        content: <String, Object?>{
          'question_0': 'Python',
          'question_0_custom': 'portable',
          'question_1': ['Types', 'Tests'],
          'question_1_custom': 'lint later',
        },
      ),
      (
        scenario: 'askclaudeone',
        agent: QuestionsAgent.claude,
        form: claudeQuestionForm,
        content: <String, Object?>{
          'question_0': 'Deno',
          'question_0_custom': 'from source',
        },
      ),
      (
        scenario: 'askcodex',
        agent: QuestionsAgent.codex,
        form: codexQuestionsForm,
        content: <String, Object?>{
          'next': 'Review existing work',
          'next_note': 'tests first',
          'token': 'fake-secret-for-tests',
        },
      ),
      (
        scenario: 'askdroid',
        agent: QuestionsAgent.droid,
        form: droidQuestionsForm,
        content: <String, Object?>{
          'question_0': 'other',
          'question_0_other': 'NFS',
          'question_1': ['option_0', 'other'],
          'question_1_other': 'HEIC',
          'question_2': 'uploads',
        },
      ),
      (
        scenario: 'askopencode',
        agent: QuestionsAgent.opencode,
        form: opencodeQuestionsForm,
        content: <String, Object?>{
          'q0': 'Beside the module',
          'q0_custom': 'with fixtures',
        },
      ),
      (
        scenario: 'askdimcode',
        agent: QuestionsAgent.dimcode,
        form: dimcodeQuestionsForm,
        content: <String, Object?>{'__custom_0': 'Preview environment'},
      ),
    ];

    // The original's SDK strips droid's `uniqueItems`; the port's
    // transport passes the schema as the agent sent it.
    test('six sessions ask concurrently and return their own field ids and '
        'content unchanged', () async {
      await Future.wait([
        for (final entry in cases)
          withSession(capabilities: declared, (session, _) async {
            final (:request, :said) = await answered(
              session,
              entry.scenario,
              AcceptReply(entry.content),
            );
            final wait = request.wait as FormWait;
            expect(wait.schema, entry.form['requestedSchema']);
            expect(wait.message, entry.form['message']);
            expect(wait.questions?.agent, entry.agent);
            expect(
              said,
              'Elicitation answer: accept  \n${jsonEncode(entry.content)}',
            );
          }),
      ]);
    }, skip: skip);

    for (final entry in cases) {
      test('${entry.scenario}: cancellation rejects a late answer and the '
          'next request is independent', () async {
        await withSession(capabilities: declared, (session, _) async {
          final asked = Completer<PendingElicitation>();
          final unsubscribe = session.elicitations.subscribe(asked.complete);
          final first = session.prompt(entry.scenario);
          final request = await asked.future;
          unsubscribe();
          await first.cancel();
          expect(request.withdrawn.isCancelled, isTrue);
          expect(
            await first.result,
            isA<TurnAnswered>().having((r) => r.cancelled, 'cancelled', isTrue),
          );
          request.answer(const AcceptReply({'stale': 'late answer'}));

          final next = await answered(
            session,
            entry.scenario,
            AcceptReply(entry.content),
          );
          expect(next.request.id, isNot(request.id));
          final wait = next.request.wait as FormWait;
          expect(wait.schema, entry.form['requestedSchema']);
          expect(wait.questions?.agent, entry.agent);
          expect(
            next.said,
            'Elicitation answer: accept  \n${jsonEncode(entry.content)}',
          );
          expect(next.said, isNot(contains('late answer')));
        });
      }, skip: skip);
    }
  });

  test("a form is read as timed out within a second of the agent's wait "
      'ending, a cancel before', () {
    FormWait wait([num? expiresInMs]) => FormWait(
      'e',
      'Questions',
      schema: const {'type': 'object', 'properties': <String, Object?>{}},
      questions: expiresInMs == null
          ? null
          : Questions(QuestionsAgent.codex, const [], expiresInMs: expiresInMs),
    );
    // The request reached chord late, so its countdown ends after the
    // agent's.
    expect(ranOut(wait(300000), 298999), isFalse);
    expect(ranOut(wait(300000), 299000), isTrue);
    expect(ranOut(wait(300000), 299950), isTrue);
    expect(ranOut(wait(300000), 300000), isTrue);
    expect(ranOut(wait(300000), 301000), isTrue);
    // Withdrawn well before the end: the agent cancelled it.
    expect(ranOut(wait(300000), 10000), isFalse);
    // A wait of under a second is within the tolerance from the start.
    expect(ranOut(wait(300), 10), isTrue);
    expect(ranOut(wait(), 1000000), isFalse);
  });

  group('the conversation', () {
    late List<ConversationEvent> events;
    late Conversation conversation;

    setUp(() {
      final dir = Directory.systemTemp.createTempSync('chord-elicitation-');
      events = [];
      conversation = Conversation(
        ({required onTraffic, required CancellationToken cancellationToken}) =>
            openSession(
              agent: 'fake',
              command: fakeAgentCommand(),
              cwd: dir.path,
              open: fakeOpenerWith(capabilities: declared),
              onTraffic: onTraffic,
              cancellationToken: cancellationToken,
            ),
      )..listen(events.add);
      addTearDown(() async {
        await conversation.close();
        dir.deleteSync(recursive: true);
      });
      conversation.start();
    });

    Future<void> until(bool Function() holds) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!holds()) {
        if (DateTime.now().isAfter(deadline)) fail('timed out');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    List<TranscriptAction> actions() => [
      for (final event in events)
        if (event case Transcribed(:final action)) action,
    ];

    List<ElicitationWait> asked() => [
      for (final action in actions())
        if (action is ElicitationRequestedAction) action.elicitation,
    ];

    List<Entry> entries() =>
        actions().fold(Transcript.empty, reduceTranscript).entries;

    test("a box withdrawn as the agent's wait runs out is recorded timed "
        'out, once', () async {
      await until(() => events.any((e) => e is Connected));
      conversation.send('askcodexwait');
      await until(() => actions().any((a) => a is ResultAction));
      final records = entries().whereType<ElicitationEntry>().toList();
      expect(records.single.outcome, ElicitationOutcome.timedOut);
      expect(actions().whereType<ElicitationSettledAction>(), hasLength(1));
    }, skip: skip);

    test('an answered form leaves its record, and the agent goes on', () async {
      await until(() => events.any((e) => e is Connected));
      conversation.send('form');
      await until(() => asked().isNotEmpty);
      final wait = asked().single;
      expect(wait.at, isNotNull);
      expect(wait.between, isFalse);
      conversation.answer(wait.id, const AcceptReply({'name': 'web-app'}));
      await until(() => actions().any((a) => a is ResultAction));
      final [_, record, echo] = entries();
      expect(record, isA<ElicitationEntry>());
      record as ElicitationEntry;
      expect(record.outcome, ElicitationOutcome.accepted);
      expect(record.content, {'name': 'web-app'});
      expect(
        (echo as AssistantEntry).text.text,
        'Elicitation answer: accept  \n{"name":"web-app"}',
      );
      expect(conversation.elicitationRequest(wait.id), isNull);
    }, skip: skip);

    test(
      'an interrupt takes the open form with it, recorded as cancelled',
      () async {
        await until(() => events.any((e) => e is Connected));
        conversation.send('form');
        await until(() => asked().isNotEmpty);
        expect(conversation.elicitationRequest(asked().single.id), isNotNull);
        conversation.interrupt();
        await until(() => actions().any((a) => a is ResultAction));
        final settled = actions().whereType<ElicitationSettledAction>().single;
        expect(settled.answer, isA<ElicitationWithdrawn>());
        expect(
          [
            for (final entry in entries())
              switch (entry) {
                ElicitationEntry(:final outcome) =>
                  'elicitation:${outcome.name}',
                UserEntry() => 'user',
                CancelledEntry() => 'cancelled',
                _ => '$entry',
              },
          ],
          ['user', 'elicitation:cancelled', 'cancelled'],
        );
        // A late answer settles nothing.
        conversation.answer(settled.id, const DeclineReply());
        expect(actions().whereType<ElicitationSettledAction>(), hasLength(1));
      },
      skip: skip,
    );
  });
}
