// How an answered question box is drawn in the transcript, from the
// original's Form.tsx QuestionsRecord: a row per question under `⎿`, who
// asked before the first where it hangs under no call, `(hidden)` for a
// secret and `skipped` for none; a box not answered names its questions
// and how it ended. A form with no questions keeps its old summary.
import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:chord/session/questions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/forms.dart';
import '../../fixtures/questions.dart';

FormWait _asked(Map<String, Object?> form, {String? toolCallId}) {
  final [message] = enricherRelay(m1Enrichers).fromAgent({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'elicitation/create',
    'params': {...form, 'sessionId': 's'},
  });
  return FormWait(
    'e',
    form['message'] as String,
    schema: recordOf(form['requestedSchema']),
    questions: questionsOf(recordOf(message['params'])),
    toolCallId: toolCallId,
  );
}

Widget _record(ElicitationEntry entry, String agent, {bool expanded = false}) =>
    Column(
      children: [TranscriptEntry(entry, agent: agent, expanded: expanded)],
    );

void main() {
  group('CTUI-68 tester: record resize and secret own answers', () {
    for (final hanging in [false, true]) {
      testWidgets(
        'secret fields stay hidden across tiny and normal resizes, hanging=$hanging',
        (t) async {
          const questions = Questions(QuestionsAgent.codex, [
            Question(
              id: 'public',
              header: 'Public',
              text: 'Public?',
              multiSelect: false,
              required: false,
              options: [],
            ),
            Question(
              id: 'secret',
              header: 'Token',
              text: 'Secret?',
              multiSelect: false,
              required: false,
              secret: true,
              options: [],
              own: OwnAnswer(field: 'secret_note', mode: OwnMode.beside),
            ),
          ]);
          final entry = ElicitationEntry(
            't',
            FormWait(
              'e',
              'Questions',
              questions: questions,
              toolCallId: hanging ? 'ask' : null,
            ),
            ElicitationOutcome.accepted,
            content: const {
              'public': '界🙂e\u0301',
              'secret': 'secret-value-for-tests',
              'secret_note': 'secret-note-for-tests',
            },
          );
          await t.pumpWidget(
            _record(entry, 'codex', expanded: true),
            size: const Size(120, 40),
          );
          for (final size in const [
            Size(120, 40),
            Size(80, 24),
            Size(24, 10),
            Size.zero,
            Size(1, 1),
            Size(80, 24),
            Size(120, 40),
          ]) {
            await t.resize(size);
            final text = t.screen.text;
            expect(text, isNot(contains('secret-value-for-tests')));
            expect(text, isNot(contains('secret-note-for-tests')));
            if (size.width >= 80) {
              expect(text, contains('界🙂e\u0301'));
              expect(text, contains('(hidden)'));
              expect(text.contains('codex asked ·'), !hanging);
            }
          }
        },
      );
    }
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    for (final expanded in [false, true]) {
      testWidgets('a secret is hidden whether the record has its value or '
          'not, at $size${expanded ? ', expanded' : ''}', (t) async {
        for (final content in [
          {
            'next': 'Review existing work',
            'next_note': 'tests first',
            'token': 'record-secret-for-tests',
          },
          {'next': 'Review existing work', 'next_note': 'tests first'},
        ]) {
          await t.pumpWidget(
            _record(
              ElicitationEntry(
                't',
                _asked(codexQuestionsForm),
                ElicitationOutcome.accepted,
                content: content,
              ),
              'codex',
              expanded: expanded,
            ),
            size: size,
          );
          final frame = t.screen.text;
          expect(
            frame,
            contains(
              '  ⎿  codex asked · Next step  Review existing work · tests first',
            ),
          );
          expect(
            frame,
            matches(RegExp(r'^ {19}Token {6}\(hidden\)', multiLine: true)),
          );
          expect(frame, isNot(contains('record-secret-for-tests')));
        }
      });
    }
  }

  testWidgets('droid records show option titles, combine its own answer and '
      'label an unanswered question skipped', (t) async {
    await t.pumpWidget(
      _record(
        ElicitationEntry(
          't',
          _asked(droidQuestionsForm),
          ElicitationOutcome.accepted,
          content: const {
            'question_0': 'option_1',
            'question_1': ['option_0', 'other'],
            'question_1_other': 'HEIC',
          },
        ),
        'droid',
      ),
      size: const Size(80, 24),
    );
    final frame = t.screen.text;
    expect(frame, matches(RegExp(r'Storage +S3 bucket')));
    expect(frame, matches(RegExp(r'Formats +PNG, HEIC')));
    expect(frame, matches(RegExp(r'Bucket +skipped')));
    expect(frame, isNot(contains('option_')));
    expect(frame, isNot(contains('Answered ·')));
  });

  testWidgets('a box out of a tool call hangs under it, naming no one', (
    t,
  ) async {
    await t.pumpWidget(
      _record(
        ElicitationEntry(
          't',
          _asked(claudeQuestionForm, toolCallId: 'ask'),
          ElicitationOutcome.accepted,
          content: const {'question_0': 'Deno'},
        ),
        'claude',
      ),
      size: const Size(80, 24),
    );
    expect(t.screen.lines.first, '  ⎿  Language  Deno');
  });

  testWidgets('unanswered outcomes name all questions, while a record '
      'without questions keeps its old form summary', (t) async {
    for (final (outcome, text) in const [
      (ElicitationOutcome.declined, 'Skipped'),
      (ElicitationOutcome.cancelled, 'Cancelled'),
      (ElicitationOutcome.timedOut, 'Timed out'),
    ]) {
      await t.pumpWidget(
        _record(
          ElicitationEntry('t', _asked(codexQuestionsForm), outcome),
          'codex',
        ),
        size: const Size(80, 24),
      );
      expect(
        t.screen.text,
        contains('  ⎿  codex asked · Next step, Token · $text'),
      );
    }
    for (final expanded in [false, true]) {
      await t.pumpWidget(
        _record(
          const ElicitationEntry(
            't',
            FormWait('g', 'Set up the deploy target', schema: formSchema),
            ElicitationOutcome.accepted,
            content: {'name': 'old-form', 'replicas': 2},
          ),
          'fake',
          expanded: expanded,
        ),
        size: const Size(80, 24),
      );
      final frame = t.screen.text;
      expect(frame, contains('fake asked: Set up the deploy target'));
      expect(frame, contains('Answered · 2 fields'));
      expect(frame, isNot(contains('fake asked ·')));
      if (expanded) expect(frame, matches(RegExp(r'Project name +old-form')));
    }
  });
}
