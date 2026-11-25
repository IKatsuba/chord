// The original's tests/ui/dialogs/questions_test.ts: the question box's
// keys, hints, windows and records, on the adapters' own forms as the
// enrichers read them.
import 'package:chord/session/elicitations.dart' hide answerOf;
import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:chord/session/questions.dart';
import 'package:chord/ui/dialogs/questions.dart';
import 'package:test/test.dart';

import '../../fixtures/questions.dart';

/// One key's press, by the name the shortcuts panel gives it.
const _keys = {
  'esc': AskKey(escape: true),
  'enter': AskKey(enter: true),
  'tab': AskKey(tab: true),
  'shift + tab': AskKey(tab: true, shift: true),
  '↑': AskKey(upArrow: true),
  '↓': AskKey(downArrow: true),
  '←': AskKey(leftArrow: true),
  '→': AskKey(rightArrow: true),
  'backspace': AskKey(backspace: true),
  'ctrl + u': AskKey(ctrl: true),
};

Map<String, Object?> _schema(Map<String, Object?> form) =>
    recordOf(form['requestedSchema']);

/// The questions the enrichers read in [form].
Questions _read(Map<String, Object?> form) {
  final [message] = enricherRelay(m1Enrichers).fromAgent({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'elicitation/create',
    'params': {...form, 'sessionId': 's'},
  });
  return questionsOf(recordOf(message['params']))!;
}

/// The box after each of [keys], a named key or text typed as it is, with
/// the answer the last one gave, if any.
({AskState state, ElicitationReply? response}) _play(
  Map<String, Object?> form,
  List<String> keys,
) {
  final questions = _read(form);
  var state = openAsk(questions);
  ElicitationReply? response;
  for (final name in keys) {
    final key = _keys[name];
    final input = name == 'ctrl + u' ? 'u' : (key == null ? name : '');
    final step = askKey(
      questions,
      _schema(form),
      state,
      input,
      key ?? const AskKey(),
    );
    state = step.state;
    response = step.response;
  }
  return (state: state, response: response);
}

Map<String, Object?> _answer(QuestionAnswer? answer) => {
  'picks': answer?.picks,
  'text': answer?.text,
  'own': answer?.own,
  'ownChosen': answer?.ownChosen,
};

void main() {
  _noteHelpers();

  group('CTUI-68 tester: schema blockers and retained answers', () {
    test(
      'an invalid own-field schema disables validation for the whole form',
      () {
        const questions = Questions(QuestionsAgent.codex, [
          Question(
            id: 'q',
            text: 'Name?',
            options: [],
            multiSelect: false,
            required: false,
            own: OwnAnswer(field: 'note', mode: OwnMode.beside),
          ),
        ]);
        const schema = {
          'type': 'object',
          'properties': {
            'q': {'type': 'string', 'minLength': 3},
            'note': {'type': 'string', 'pattern': '('},
          },
        };
        const state = AskState(
          step: 1,
          row: 0,
          answers: {'q': QuestionAnswer(text: 'a', own: 'note')},
        );
        // The original disables the whole validator for the invalid pattern.
        expect(blockers(questions, schema, state), isEmpty);
      },
      skip:
          'Malformed agent schema fallback differs from the original; deferred by the lead.',
    );

    const typed = Question(
      id: 'typed',
      text: 'Name?',
      multiSelect: false,
      required: true,
      options: [],
    );

    test(
      'string length and pattern block Send until the typed answer is valid',
      () {
        const questions = Questions(QuestionsAgent.codex, [typed]);
        const schema = {
          'type': 'object',
          'properties': {
            'typed': {'type': 'string', 'minLength': 3, 'pattern': r'^[a-z]+$'},
          },
          'required': ['typed'],
        };
        for (final (text, problem) in [
          ('ab', 'At least 3 characters'),
          ('ABC', r'Must match ^[a-z]+$'),
        ]) {
          final state = AskState(
            step: 1,
            row: 0,
            answers: {'typed': QuestionAnswer(text: text)},
          );
          expect(blockers(questions, schema, state), {'typed': problem});
          expect(
            askKey(questions, schema, state, '1', const AskKey()).response,
            isNull,
          );
          expect(
            askKey(
              questions,
              schema,
              state,
              '',
              const AskKey(enter: true),
            ).response,
            isA<DeclineReply>(),
          );
        }
        const valid = AskState(
          step: 1,
          row: 0,
          answers: {'typed': QuestionAnswer(text: 'abc')},
        );
        expect(blockers(questions, schema, valid), isEmpty);
        expect(
          askKey(
            questions,
            schema,
            valid,
            '1',
            const AskKey(),
          ).response?.toJson(),
          {
            'action': 'accept',
            'content': {'typed': 'abc'},
          },
        );
      },
    );

    test(
      'minItems and maxItems block invalid selections and allow the boundary',
      () {
        const question = Question(
          id: 'many',
          text: 'Pick two',
          multiSelect: true,
          required: true,
          options: [
            QuestionOption(value: 'a', title: 'A'),
            QuestionOption(value: 'b', title: 'B'),
            QuestionOption(value: 'c', title: 'C'),
          ],
        );
        const questions = Questions(QuestionsAgent.claude, [question]);
        const schema = {
          'type': 'object',
          'properties': {
            'many': {
              'type': 'array',
              'items': {'type': 'string'},
              'minItems': 2,
              'maxItems': 2,
            },
          },
          'required': ['many'],
        };
        for (final (picks, problem) in [
          (<String>[], 'required'),
          (['a'], 'Pick at least 2'),
          (['a', 'b', 'c'], 'Pick at most 2'),
        ]) {
          final state = AskState(
            step: 1,
            row: 0,
            answers: {'many': QuestionAnswer(picks: picks)},
          );
          expect(blockers(questions, schema, state), {'many': problem});
          expect(
            askKey(questions, schema, state, '1', const AskKey()).response,
            isNull,
          );
        }
        const valid = AskState(
          step: 1,
          row: 0,
          answers: {
            'many': QuestionAnswer(picks: ['a', 'b']),
          },
        );
        expect(blockers(questions, schema, valid), isEmpty);
        expect(
          askKey(
            questions,
            schema,
            valid,
            '',
            const AskKey(enter: true),
          ).response?.toJson(),
          {
            'action': 'accept',
            'content': {
              'many': ['a', 'b'],
            },
          },
        );
      },
    );

    test(
      'a note problem belongs to its question and main field problems take precedence',
      () {
        const question = Question(
          id: 'q',
          text: 'Which?',
          multiSelect: false,
          required: false,
          options: [QuestionOption(value: 'a', title: 'A')],
          own: OwnAnswer(field: 'note', mode: OwnMode.beside),
        );
        const questions = Questions(QuestionsAgent.codex, [question]);
        const schema = {
          'type': 'object',
          'properties': {
            'q': {'type': 'string', 'pattern': r'^a$'},
            'note': {'type': 'string', 'minLength': 3},
          },
        };
        for (final (pick, problem) in [
          ('a', 'At least 3 characters'),
          ('b', r'Must match ^a$'),
        ]) {
          final state = AskState(
            step: 1,
            row: 0,
            answers: {
              'q': QuestionAnswer(picks: [pick], own: 'x'),
            },
          );
          expect(blockers(questions, schema, state), {'q': problem});
        }
      },
    );

    test(
      'a thousand note edits preserve prior states and cursor offsets across navigation',
      () {
        final questions = _read(claudeQuestionsForm);
        final initial = openAsk(questions);
        var state = initial;
        const literal = '界🙂e\u0301\u001b[31m';
        for (var update = 0; update < 1000; update++) {
          state = changedNote(
            state,
            questions.questions.first,
            '$literal$update',
            update,
          );
        }
        final edited = state;
        state = askKey(
          questions,
          _schema(claudeQuestionsForm),
          state,
          '',
          const AskKey(tab: true),
        ).state;
        state = changedNote(state, questions.questions.last, 'second', 2);
        state = askKey(
          questions,
          _schema(claudeQuestionsForm),
          state,
          '',
          const AskKey(tab: true, shift: true),
        ).state;
        expect(initial.answers, isEmpty);
        expect(initial.noteCursors, isEmpty);
        expect(edited.answers.keys, ['question_0']);
        expect(state.answers['question_0']?.own, '${literal}999');
        expect(state.answers['question_1']?.own, 'second');
        expect(state.noteCursors, {'question_0': 999, 'question_1': 2});
        expect(state.step, 0);
      },
    );
  });

  test("Enter picks a question's option and goes on; Send sends it under the "
      "agent's field", () {
    final (:state, :response) = _play(claudeQuestionsForm, [
      'enter',
      ' ',
      '3',
      'enter',
      'enter',
    ]);
    expect(state.step, 2);
    expect(response?.toJson(), {
      'action': 'accept',
      'content': {
        'question_0': 'Deno (TypeScript) (Recommended)',
        'question_1': ['Types', 'Tests'],
      },
    });
  });

  test('a digit picks and goes on, or on a multi-select toggles and '
      'stays', () {
    final one = _play(claudeQuestionsForm, ['2']).state;
    expect(one.step, 1);
    expect(one.answers['question_0']?.picks, ['Python']);
    final many = _play(claudeQuestionsForm, ['2', '2', '2', '3']).state;
    expect(many.step, 1);
    expect(many.row, 2);
    expect(many.answers['question_1']?.picks, ['Tests']);
  });

  test('the note beside a pick is typed on its own row, and both are '
      'sent', () {
    final (state: _, :response) = _play(codexQuestionsForm, [
      '2',
      'shift + tab',
      '↓',
      '↓',
      '↓',
      'tests',
      ' ',
      'first',
      'tab',
      'sk-1',
      'enter',
      'enter',
    ]);
    expect(response?.toJson(), {
      'action': 'accept',
      'content': {
        'next': 'Review existing work',
        'next_note': 'tests first',
        'token': 'sk-1',
      },
    });
  });

  test("an own answer that stands for droid's other option is picked by "
      'typing, and dropped by another pick', () {
    final typed = _play(droidQuestionsForm, ['↓', '↓', 'NFS']);
    expect(_answer(typed.state.answers['question_0']), {
      'picks': <String>[],
      'text': '',
      'own': 'NFS',
      'ownChosen': true,
    });
    final other = _play(droidQuestionsForm, [
      '↓',
      '↓',
      'NFS',
      '↑',
      'enter',
    ]).state.answers['question_0'];
    expect(other?.picks, ['option_1']);
    expect(other?.own, 'NFS');
    expect(other?.ownChosen, isFalse);
    // A multi-select's own row: Space is typed into it, and it is ticked
    // exactly while it holds text.
    final space = _play(droidQuestionsForm, [
      'tab',
      '↓',
      '↓',
      ' ',
    ]).state.answers['question_1'];
    expect((space?.ownChosen, space?.own), (true, ' '));
    final word = _play(droidQuestionsForm, [
      'tab',
      '↓',
      '↓',
      'HE',
      ' ',
      'IC',
    ]).state.answers['question_1'];
    expect((word?.ownChosen, word?.own), (true, 'HE IC'));
    final cleared = _play(droidQuestionsForm, [
      'tab',
      '↓',
      '↓',
      'HEIC',
      'ctrl + u',
    ]).state.answers['question_1'];
    expect((cleared?.ownChosen, cleared?.own), (false, ''));
  });

  test("dimcode's own answer clears the pick it stands instead of", () {
    final (state: _, :response) = _play(dimcodeQuestionsForm, [
      '1',
      '←',
      '↓',
      '↓',
      'canary',
      'tab',
      'enter',
    ]);
    expect(response?.toJson(), {
      'action': 'accept',
      'content': {'__custom_0': 'canary'},
    });
  });

  test('Send is out of reach while a required question has no answer; '
      'Enter then skips', () {
    final questions = _read(codexQuestionsForm);
    final (:state, :response) = _play(codexQuestionsForm, [
      '→',
      '→',
      '↑',
      'enter',
    ]);
    expect(blockers(questions, _schema(codexQuestionsForm), state), {
      'next': 'required',
      'token': 'required',
    });
    expect(response, isA<DeclineReply>());
    expect(_play(codexQuestionsForm, ['→', '→', '1']).response, isNull);
  });

  test('Esc cancels from any step, and ← → stop at the ends', () {
    expect(
      _play(claudeQuestionsForm, ['→', 'esc']).response,
      isA<CancelReply>(),
    );
    expect(_play(claudeQuestionsForm, ['←']).state.step, 0);
    expect(_play(claudeQuestionsForm, ['→', '→', '→']).state.step, 2);
  });

  test('text is edited at its end: backspace, ctrl+u', () {
    expect(
      _play(codexQuestionsForm, [
        'tab',
        'abc',
        'backspace',
      ]).state.answers['token']?.text,
      'ab',
    );
    expect(
      _play(codexQuestionsForm, [
        'tab',
        'abc',
        'ctrl + u',
      ]).state.answers['token']?.text,
      '',
    );
  });

  test('the summary reads titles, a note after ·, and a secret as dots', () {
    final questions = _read(codexQuestionsForm);
    final (:state, response: _) = _play(codexQuestionsForm, [
      '2',
      'sk-1',
      'shift + tab',
      '↓',
      '↓',
      'first',
    ]);
    final [next, token] = questions.questions;
    expect(answerText(next, state), 'Review existing work · first');
    expect(answerText(token, state), '••••');
    expect(
      answerText(
        _read(droidQuestionsForm).questions[0],
        state.copyWith(
          answers: {
            'question_0': const QuestionAnswer(picks: ['option_1']),
          },
        ),
      ),
      'S3 bucket',
    );
  });

  test('the heading counts the questions, and the countdown runs from when '
      'the request came', () {
    final questions = _read(codexQuestionsForm);
    expect(askHeading('codex', questions), 'codex asks you 2 questions');
    expect(
      askHeading(
        'claude',
        Questions(questions.agent, questions.questions.sublist(1)),
      ),
      'claude asks you a question',
    );
    expect(clock(expiresIn(questions, 1000, 1000 + 28500) ?? 0), '4:32');
    expect(expiresIn(questions, 1000, 1000 + 400000), 0);
    expect(expiresIn(_read(claudeQuestionsForm), 1000, 0), isNull);
  });

  test('the hint names ←→ for the questions on every row, short at 80 '
      'columns', () {
    final questions = _read(droidQuestionsForm);
    final open = openAsk(questions);
    for (final state in [
      open,
      open.copyWith(row: 2),
      open.copyWith(step: 1, row: 2),
      open.copyWith(step: 3),
    ]) {
      expect(
        askHint(questions, state, 116),
        contains('←→ or Tab for the questions'),
      );
      expect(askHint(questions, state, 76), contains('←→ questions'));
      expect(askHint(questions, state, 76).length, lessThanOrEqualTo(76));
    }
  });

  test('a step too tall keeps the focused row whole and counts the rows cut '
      'off', () {
    // The question, a blank, four one-line options and one of three lines.
    const rows = [null, null, 0, 1, 1, 1, 2, 3, 4];
    expect(windowOf(rows, 0, 9), (top: 0, end: 9, above: 0, below: 0));
    // The option of three lines does not fit whole below the focused one.
    expect(windowOf(rows, 0, 6), (top: 0, end: 3, above: 0, below: 4));
    expect(windowOf(rows, 4, 6), (top: 6, end: 9, above: 2, below: 0));
  });

  test("the own answer's number takes the ❯ there, and picks it once it "
      'holds text; the hint counts it', () {
    final questions = _read(droidQuestionsForm);
    final at = _play(droidQuestionsForm, ['3']).state;
    expect((at.step, at.row), (0, 2));
    expect(at.answers['question_0'], isNull);
    final again = _play(droidQuestionsForm, [
      '3',
      'NFS',
      '↑',
      'enter',
      '←',
      '3',
    ]).state;
    expect((again.step, again.row), (0, 2));
    expect(_answer(again.answers['question_0']), {
      'picks': <String>[],
      'text': '',
      'own': 'NFS',
      'ownChosen': true,
    });
    expect(askHint(questions, openAsk(questions), 76), contains('1–3'));
    final deploy = _play(dimcodeQuestionsForm, [
      '3',
      'canary',
      '↑',
      'enter',
      '←',
      '3',
    ]).state.answers['deploy'];
    expect(deploy?.picks, isEmpty);
    expect(deploy?.ownChosen, isTrue);
  });

  test("an answered box's record reads titles, a note after ·, its own "
      'answer, (hidden) for a secret and skipped for none', () {
    expect(
      answeredQuestions(_read(codexQuestionsForm), {
        'next': 'Review existing work',
        'next_note': 'tests first',
      }),
      [
        (label: 'Next step', value: 'Review existing work · tests first'),
        (label: 'Token', value: '(hidden)'),
      ],
    );
    expect(
      answeredQuestions(_read(droidQuestionsForm), {
        'question_0': 'other',
        'question_0_other': 'NFS',
        'question_1': ['option_0', 'other'],
        'question_1_other': 'HEIC',
      }),
      [
        (label: 'Storage', value: 'NFS'),
        (label: 'Formats', value: 'PNG, HEIC'),
        (label: 'Bucket', value: 'skipped'),
      ],
    );
  });

  test('a paste goes into the text row the ❯ is on, its line breaks spaces, '
      'and picks nothing elsewhere', () {
    final questions = _read(codexQuestionsForm);
    final open = openAsk(questions);
    // On an option row a pasted digit is not a pick.
    expect(identical(askPaste(questions, open, '2'), open), isTrue);
    expect(
      askPaste(
        questions,
        open.copyWith(step: 1),
        'sk-1\nrest',
      ).answers['token']?.text,
      'sk-1 rest',
    );
    expect(
      askPaste(
        questions,
        open.copyWith(row: 3),
        'tests first',
      ).answers['next']?.own,
      'tests first',
    );
    final droid = _read(droidQuestionsForm);
    final pasted = askPaste(
      droid,
      openAsk(droid).copyWith(row: 2),
      'NFS',
    ).answers['question_0'];
    expect((pasted?.own, pasted?.ownChosen), ('NFS', true));
  });

  test('a focused row taller than the box is cut at its end, so the window '
      'never passes its limit', () {
    final rows = <int?>[null, null, ...List.filled(20, 0), 1];
    final window = windowOf(rows, 0, 9);
    expect(window, (top: 2, end: 9, above: 0, below: 1));
    expect(
      window.end -
          window.top +
          (window.top > 0 ? 1 : 0) +
          (window.end < rows.length ? 1 : 0),
      lessThanOrEqualTo(9),
    );
  });

  test("an option's description too long for the box keeps its first lines "
      'and ends in …', () {
    expect(capLines(['one two', 'three four', 'five six'], 2), [
      'one two',
      'three fou…',
    ]);
    expect(capLines(['one'], 2), ['one']);
  });

  test('another option that does not fit whole is left out below and '
      'counted, never cut', () {
    final rows = <int?>[null, null, 0, ...List.filled(7, 1), 2];
    expect(windowOf(rows, 0, 9), (top: 0, end: 3, above: 0, below: 2));
  });

  group('CHD-1 tester: question viewport and editing invariants', () {
    test('every focused option fits and every non-focused option is either '
        'whole or counted outside', () {
      for (var limit = 6; limit <= 14; limit++) {
        final sizes = [1, limit - 2, 2, limit - 3, 1, 3];
        final lines = <int?>[
          null,
          null,
          for (final (row, size) in sizes.indexed) ...List.filled(size, row),
        ];
        for (var focus = 0; focus < sizes.length; focus++) {
          final view = windowOf(lines, focus, limit);
          final shown = lines.sublist(view.top, view.end);
          expect(shown, contains(focus));
          expect(shown.where((row) => row == focus).length, sizes[focus]);
          expect(
            shown.length +
                (view.top > 0 ? 1 : 0) +
                (view.end < lines.length ? 1 : 0),
            lessThanOrEqualTo(limit),
          );
          for (var row = 0; row < sizes.length; row++) {
            final count = shown.where((value) => value == row).length;
            expect(count == 0 || count == sizes[row], isTrue);
          }
          expect(
            view.above,
            [
              for (var row = 0; row < sizes.length; row++)
                if (lines.lastIndexOf(row) < view.top) row,
            ].length,
          );
          expect(
            view.below,
            [
              for (var row = 0; row < sizes.length; row++)
                if (lines.indexOf(row) >= view.end) row,
            ].length,
          );
        }
      }
    });

    test('own-row digits and Space type text; ctrl+w and ctrl+u clear its '
        'tick without changing normal picks', () {
      final (:state, response: _) = _play(droidQuestionsForm, [
        'tab',
        '1',
        '↓',
        '↓',
        '2',
        ' ',
        'HEIC',
      ]);
      expect(_answer(state.answers['question_1']), {
        'picks': ['option_0'],
        'text': '',
        'own': '2 HEIC',
        'ownChosen': true,
      });
      final questions = _read(droidQuestionsForm);
      final schema = _schema(droidQuestionsForm);
      final shortened = askKey(
        questions,
        schema,
        state,
        'w',
        const AskKey(ctrl: true),
      ).state;
      final cleared = askKey(
        questions,
        schema,
        shortened,
        'u',
        const AskKey(ctrl: true),
      ).state;
      expect(shortened.answers['question_1']?.own, '2 ');
      expect(_answer(cleared.answers['question_1']), {
        'picks': ['option_0'],
        'text': '',
        'own': '',
        'ownChosen': false,
      });
      expect(
        _answer(
          askPaste(questions, cleared, 'one\r\ntwo').answers['question_1'],
        ),
        {
          'picks': ['option_0'],
          'text': '',
          'own': 'one two',
          'ownChosen': true,
        },
      );
    });
  });

  test("↓ on a step's last row, or on Skip, leaves for the agents list with "
      'the answers as they are', () {
    final questions = _read(claudeQuestionsForm);
    final schema = _schema(claudeQuestionsForm);
    AskStep down(AskState state) =>
        askKey(questions, schema, state, '', _keys['↓']!);
    final last = openAsk(
      questions,
    ).copyWith(row: rowsOf(questions.questions[0]).length - 1);
    final skip = openAsk(questions).copyWith(step: questions.questions.length);
    final onSkip = down(skip).state;

    final leaving = down(last);
    expect((identical(leaving.state, last), leaving.leave), (true, true));
    // On the Submit step ↓ goes to Skip, and from Skip it leaves.
    expect(down(skip).leave, isFalse);
    final left = down(onSkip);
    expect((identical(left.state, onSkip), left.leave), (true, true));
    expect(down(openAsk(questions)).leave, isFalse);
  });
}

void _noteHelpers() {
  test("the Note's editor takes typing, deleting and word moves, and keeps "
      'its cursor with the answers', () {
    expect(noteEdits('a', const AskKey()), isTrue);
    expect(noteEdits('', const AskKey(backspace: true)), isTrue);
    expect(noteEdits('w', const AskKey(ctrl: true)), isTrue);
    expect(noteEdits('', const AskKey(meta: true, leftArrow: true)), isTrue);
    expect(
      noteEdits('', const AskKey(superKey: true, rightArrow: true)),
      isTrue,
    );
    for (final key in const [
      AskKey(enter: true),
      AskKey(tab: true),
      AskKey(escape: true),
      AskKey(upArrow: true),
      AskKey(leftArrow: true),
      AskKey(ctrl: true),
      AskKey(shift: true, meta: true, leftArrow: true),
    ]) {
      expect(noteEdits(key.ctrl ? 'u' : '', key), isFalse);
    }
    expect(noteEdits('\n', const AskKey()), isFalse);
    expect(edited('one two ', 'w', const AskKey(ctrl: true)), 'one ');
    expect(edited('a😀', '', const AskKey(backspace: true)), 'a');
    expect(edited('a', 'x', const AskKey(meta: true)), isNull);

    final codex = _read(codexQuestionsForm);
    final [next, token] = codex.questions;
    expect(editableNote(next), isTrue);
    expect(editableNote(token), isFalse);
    expect(editableNote(_read(droidQuestionsForm).questions[0]), isFalse);
    final noted = changedNote(openAsk(codex), next, 'tests', 3);
    expect(noted.answers['next']?.own, 'tests');
    expect(noted.noteCursors, {'next': 3});
  });
}
