// The original's record.ts for a form whose questions chord read: its
// `asked` line keeps the questions, its `answered` line what was given but
// for a secret question, and a replay draws them as the live box left
// them, the secret gone.
import 'package:chord/session/conversation.dart';
import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:chord/session/questions.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import '../fixtures/questions.dart';
import 'recording_test.dart' show lines, opening;

/// codex's form as the enrichers read it.
FormWait _codex() {
  final [message] = enricherRelay(m1Enrichers).fromAgent({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'elicitation/create',
    'params': {...codexQuestionsForm, 'sessionId': 's'},
  });
  final params = recordOf(message['params']);
  return FormWait(
    'q',
    codexQuestionsForm['message'] as String,
    schema: recordOf(codexQuestionsForm['requestedSchema']),
    questions: questionsOf(params),
  );
}

void main() {
  group('CTUI-68 tester: redacted answer persistence', () {
    Future<List<Map<String, Object?>>> recorded(
      FormWait wait,
      ElicitationAnswer answer,
    ) async {
      final writes = <String>[];
      final recording = FileRecording(
        'state',
        failed: fail,
        uuid: () => 'redaction-fixture',
        now: () => 1,
        append: (path, text) async => writes.add(text),
      );
      recording.opened(opening('id'));
      recording.sent('t', 'questions', 0, const [], 1);
      recording.heard(
        Transcribed(ElicitationRequestedAction('t', wait.asked(at: 2))),
      );
      recording.heard(
        Transcribed(ElicitationSettledAction('t', wait.id, answer)),
      );
      await recording.flushed();
      return lines(writes.join());
    }

    test(
      'secret text and its own note are absent while public Unicode survives replay',
      () async {
        const questions = Questions(QuestionsAgent.codex, [
          Question(
            id: 'public',
            text: 'Public?',
            multiSelect: false,
            required: false,
            options: [],
            own: OwnAnswer(field: 'public_note', mode: OwnMode.beside),
          ),
          Question(
            id: 'secret',
            text: 'Secret?',
            multiSelect: false,
            required: false,
            options: [],
            secret: true,
            own: OwnAnswer(field: 'secret_note', mode: OwnMode.beside),
          ),
        ]);
        const wait = FormWait('q', 'Questions', questions: questions);
        final content = Map<String, Object?>.unmodifiable({
          'public': '界🙂e\u0301',
          'public_note': 'keep this',
          'secret': 'private-secret-content',
          'secret_note': 'private-secret-note',
        });
        final written = await recorded(wait, ElicitationAccepted(content));
        expect(written.toString(), isNot(contains('private-secret-content')));
        expect(written.toString(), isNot(contains('private-secret-note')));
        expect(content['secret'], 'private-secret-content');
        expect(content['secret_note'], 'private-secret-note');
        final past = PreparedHistory.fromJson(recordActions(written).toJson());
        final transcript = past.actions.fold(
          Transcript.empty,
          reduceTranscript,
        );
        final entry = transcript.entries.whereType<ElicitationEntry>().single;
        expect(entry.content, {
          'public': '界🙂e\u0301',
          'public_note': 'keep this',
        });
        expect(
          (entry.wait as FormWait).questions?.toJson(),
          questions.toJson(),
        );
      },
    );

    test(
      'generic forms still omit every accepted field from persistent history',
      () async {
        final written = await recorded(
          const FormWait('generic', 'Generic'),
          const ElicitationAccepted({'arbitrary': 'private-generic-value'}),
        );
        expect(written.toString(), isNot(contains('private-generic-value')));
        expect(
          written.singleWhere((line) => line['type'] == 'answered')['answer'],
          {'type': 'accepted'},
        );
        final transcript = recordActions(
          written,
        ).actions.fold(Transcript.empty, reduceTranscript);
        final entry = transcript.entries.whereType<ElicitationEntry>().single;
        expect(entry.content, isNull);
        expect((entry.wait as FormWait).questions, isNull);
      },
    );
  });

  group('CTUI-68 tester: timed-out question record replay', () {
    test(
      'the timed_out answer survives the file and prepared-history codec',
      () async {
        final writes = <String>[];
        final recording = FileRecording(
          'state',
          failed: fail,
          uuid: () => 'timeout-fixture',
          now: () => 1,
          append: (path, text) async => writes.add(text),
        );
        final wait = _codex();
        recording.opened(opening('id'));
        recording.sent('t', 'askcodexwait', 0, const [], 1);
        recording.heard(
          Transcribed(ElicitationRequestedAction('t', wait.asked(at: 7))),
        );
        recording.heard(
          const Transcribed(
            ElicitationSettledAction('t', 'q', ElicitationTimedOut()),
          ),
        );
        await recording.flushed();
        final written = lines(writes.join());
        expect(
          written.singleWhere((line) => line['type'] == 'answered')['answer'],
          {'type': 'timed_out'},
        );
        final past = PreparedHistory.fromJson(recordActions(written).toJson());
        final transcript = past.actions.fold(
          Transcript.empty,
          reduceTranscript,
        );
        final entry = transcript.entries.whereType<ElicitationEntry>().single;
        expect(entry.outcome, ElicitationOutcome.timedOut);
        expect(entry.content, isNull);
        expect(
          (entry.wait as FormWait).questions?.toJson(),
          wait.questions?.toJson(),
        );
        expect(transcript.asking, isEmpty);
      },
    );
  });

  test('a secret question\'s values are left out of the answered line, and '
      'the questions are kept on the asked line and read back', () async {
    final writes = <String>[];
    final recording = FileRecording(
      'state',
      failed: fail,
      uuid: () => 'fixture',
      now: () => 1,
      append: (path, text) async => writes.add(text),
    );
    final wait = _codex();
    recording.opened(opening('id'));
    recording.heard(const Transcribed(CycleStartedAction('c1', 5)));
    recording.heard(
      Transcribed(ElicitationRequestedAction('c1', wait.asked(at: 7))),
    );
    recording.heard(
      const Transcribed(
        ElicitationSettledAction(
          'c1',
          'q',
          ElicitationAccepted({
            'next': 'Review existing work',
            'next_note': 'tests first',
            'token': 'record-secret-for-tests',
          }),
        ),
      ),
    );
    await recording.flushed();
    final written = [
      for (final line in lines(writes.join()))
        if (line['type'] == 'asked' || line['type'] == 'answered') line,
    ];
    expect(writes.join(), isNot(contains('record-secret-for-tests')));
    expect(written[0]['wait'], {
      'id': 'q',
      'message': 'Codex needs your input to continue.',
      'mode': 'form',
      'schema': codexQuestionsForm['requestedSchema'],
      'questions': wait.questions!.toJson(),
    });
    expect(written[1]['answer'], {
      'type': 'accepted',
      'content': {'next': 'Review existing work', 'next_note': 'tests first'},
    });

    final past = PreparedHistory.fromJson(
      recordActions([
        {
          'type': 'prompt',
          'turnId': 'c1',
          'at': 1,
          'prompt': 'askcodex',
          'images': 0,
        },
        ...written,
      ]).toJson(),
    );
    final transcript = past.actions.fold(Transcript.empty, reduceTranscript);
    final entry = transcript.entries.whereType<ElicitationEntry>().single;
    expect(entry.outcome, ElicitationOutcome.accepted);
    expect(entry.content, {
      'next': 'Review existing work',
      'next_note': 'tests first',
    });
    expect(
      (entry.wait as FormWait).questions?.toJson(),
      wait.questions!.toJson(),
    );
  });
}
