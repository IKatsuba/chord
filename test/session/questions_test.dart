// The original's tests/session/questions_test.ts, with the shape's own
// reading and writing under `_meta` beside it.
import 'package:chord/session/questions.dart';
import 'package:test/test.dart';

const _options = [
  QuestionOption(value: 'a', title: 'A'),
  QuestionOption(value: 'b', title: 'B'),
];

Question _question({
  String id = 'q',
  List<QuestionOption> options = _options,
  bool multiSelect = false,
  bool required = false,
  bool? secret,
  OwnAnswer? own,
}) => Question(
  id: id,
  text: 'Which?',
  options: options,
  multiSelect: multiSelect,
  required: required,
  secret: secret,
  own: own,
);

Map<String, Object?> _sent(Question asked, QuestionAnswer? answer) => answerOf(
  Questions(QuestionsAgent.claude, [asked]),
  answer == null ? {} : {'q': answer},
);

void main() {
  group('CTUI-68 tester: question shape and answer boundaries', () {
    test('every agent and own mode survives JSON with false and zero kept', () {
      for (final agent in QuestionsAgent.values) {
        for (final mode in OwnMode.values) {
          final json = {
            'agent': agent.name,
            'questions': [
              {
                'id': 'q',
                'header': 'Header',
                'text': 'Which?',
                'multiSelect': false,
                'required': false,
                'secret': false,
                'options': [
                  {'value': 'a', 'title': 'A'},
                ],
                'own': {'field': 'note', 'mode': mode.name},
              },
            ],
            'expiresInMs': 0,
          };
          expect(Questions.fromJson(json)?.toJson(), json);
        }
      }
      expect(const Questions(QuestionsAgent.claude, []).toJson(), {
        'agent': 'claude',
        'questions': [],
      });
    });

    test(
      'choices rejects a whole mixed list and keeps adapter text literal',
      () {
        for (final multi in [false, true]) {
          final entries = [
            {'const': 'a'},
            {'const': false},
          ];
          expect(
            choices(
              multi
                  ? {
                      'type': 'array',
                      'items': {'anyOf': entries},
                    }
                  : {'type': 'string', 'oneOf': entries},
            ),
            isNull,
          );
        }
        final result = choices({
          'type': 'string',
          'oneOf': [
            {
              'const': '界🙂e\u0301\u001b[31m',
              'title': '',
              'description': ' ',
              '_meta': {
                '_claude/askUserQuestionOption': {'preview': ''},
              },
            },
          ],
        })!;
        expect(result.options.single.toJson(), {
          'value': '界🙂e\u0301\u001b[31m',
          'title': '界🙂e\u0301\u001b[31m',
          'description': ' ',
        });
      },
    );

    test('form readers tolerate malformed properties and required entries', () {
      final fields = formFields({
        'mode': 'form',
        'requestedSchema': {
          'properties': {'broken': null, 'scalar': 3, 'list': []},
          'required': ['broken', 'broken', null, false, 'absent'],
        },
      })!;
      expect(
        [for (final (key, _) in fields.properties) key],
        ['broken', 'scalar', 'list'],
      );
      expect([
        for (final (_, value) in fields.properties) value,
      ], everyElement(isEmpty));
      expect(fields.required, {'broken', 'absent'});
      for (final malformed in [
        null,
        false,
        [],
        {'mode': 'form'},
      ]) {
        expect(formFields(malformed), isNull);
      }
      expect(isText({'type': 'string', 'oneOf': null}), isFalse);
      expect(isText({'type': 'string', 'enum': null}), isFalse);
    });

    test(
      'single choice sends the last pick and own text needs no sentinel',
      () {
        expect(_sent(_question(), const QuestionAnswer(picks: ['a', 'b'])), {
          'q': 'b',
        });
        expect(
          _sent(
            _question(
              own: const OwnAnswer(field: 'note', mode: OwnMode.withValue),
            ),
            const QuestionAnswer(picks: ['a'], own: ' typed ', ownChosen: true),
          ),
          {'q': 'a', 'note': 'typed'},
        );
      },
    );

    test(
      'typed Unicode and escape sequences survive answer and secret filtering',
      () {
        const literal = '界🙂e\u0301\u001b[31mred\u001b[0m';
        final content = _sent(
          _question(
            options: [],
            own: const OwnAnswer(field: 'note', mode: OwnMode.beside),
          ),
          const QuestionAnswer(text: ' \t$literal\n ', own: ' $literal '),
        );
        expect(content, {'q': literal, 'note': literal});
        final filtered = withoutSecrets(
          Questions(QuestionsAgent.codex, [
            _question(id: 'secret', secret: true),
            _question(secret: false),
          ]),
          {...content, 'secret': literal},
        );
        expect(filtered, content);
        expect(identical(filtered, content), isFalse);
      },
    );
  });

  test("a pick goes in its question's field, a list where it takes several, "
      'and an unanswered question sends nothing', () {
    expect(_sent(_question(), const QuestionAnswer(picks: ['b'])), {'q': 'b'});
    expect(
      _sent(
        _question(multiSelect: true),
        const QuestionAnswer(picks: ['a', 'b']),
      ),
      {
        'q': ['a', 'b'],
      },
    );
    expect(_sent(_question(), null), isEmpty);
    expect(_sent(_question(), const QuestionAnswer(own: '  ')), isEmpty);
  });

  test('a typed question sends its text in its own field', () {
    expect(
      _sent(_question(options: []), const QuestionAnswer(text: ' main ')),
      {'q': 'main'},
    );
  });

  test('beside: the pick and the text both go, the text whether its row is '
      'chosen or not', () {
    final asked = _question(
      own: const OwnAnswer(field: 'q_note', mode: OwnMode.beside),
    );
    expect(
      _sent(asked, const QuestionAnswer(picks: ['a'], own: 'tests first')),
      {'q': 'a', 'q_note': 'tests first'},
    );
    expect(_sent(asked, const QuestionAnswer(own: 'my own')), {
      'q_note': 'my own',
    });
  });

  test('instead: the text alone once its row is chosen, else the pick '
      'alone', () {
    final asked = _question(
      own: const OwnAnswer(field: 'q_own', mode: OwnMode.instead),
    );
    expect(
      _sent(
        asked,
        const QuestionAnswer(picks: ['a'], own: 'mine', ownChosen: true),
      ),
      {'q_own': 'mine'},
    );
    expect(_sent(asked, const QuestionAnswer(picks: ['a'], own: 'mine')), {
      'q': 'a',
    });
  });

  test('withValue: the option the text stands for goes with it, beside other '
      'picks where it takes several', () {
    const own = OwnAnswer(
      field: 'q_other',
      mode: OwnMode.withValue,
      value: 'other',
    );
    expect(
      _sent(
        _question(own: own),
        const QuestionAnswer(own: 'NFS', ownChosen: true),
      ),
      {'q': 'other', 'q_other': 'NFS'},
    );
    expect(
      _sent(
        _question(own: own, multiSelect: true),
        const QuestionAnswer(picks: ['a'], own: 'HEIC', ownChosen: true),
      ),
      {
        'q': ['a', 'other'],
        'q_other': 'HEIC',
      },
    );
    // Another option picked: the text is kept on screen but not sent.
    expect(
      _sent(
        _question(own: own),
        const QuestionAnswer(picks: ['b'], own: 'NFS'),
      ),
      {'q': 'b'},
    );
  });

  test('a typed question sends its text and its note, each in its own '
      'field', () {
    expect(
      _sent(
        _question(
          options: [],
          own: const OwnAnswer(field: 'q_note', mode: OwnMode.beside),
        ),
        const QuestionAnswer(text: 'main', own: 'the release branch'),
      ),
      {'q': 'main', 'q_note': 'the release branch'},
    );
  });

  test("a secret question's values are left out of what is kept", () {
    expect(
      withoutSecrets(
        Questions(QuestionsAgent.codex, [
          _question(
            id: 'token',
            options: [],
            secret: true,
            own: const OwnAnswer(field: 'token_note', mode: OwnMode.beside),
          ),
          _question(),
        ]),
        {'token': 'sk-1', 'token_note': 'staging', 'q': 'a'},
      ),
      {'q': 'a'},
    );
  });

  group('CHD-1 tester: independent question answers', () {
    test('all own-answer modes keep each question independent and leave the '
        'supplied picks unchanged', () {
      final questions = Questions(QuestionsAgent.codex, [
        _question(
          id: 'choice',
          own: const OwnAnswer(field: 'choice_note', mode: OwnMode.beside),
        ),
        _question(
          id: 'custom',
          own: const OwnAnswer(field: 'custom_text', mode: OwnMode.instead),
        ),
        _question(
          id: 'many',
          multiSelect: true,
          own: const OwnAnswer(
            field: 'many_other',
            mode: OwnMode.withValue,
            value: 'other',
          ),
        ),
        _question(
          id: 'typed',
          options: [],
          own: const OwnAnswer(field: 'typed_note', mode: OwnMode.beside),
        ),
        _question(id: 'unanswered', required: true),
      ]);
      final manyPicks = List<String>.unmodifiable(['a', 'b']);
      final answers = {
        'choice': const QuestionAnswer(picks: ['b'], own: ' note '),
        'custom': const QuestionAnswer(
          picks: ['a'],
          own: ' mine ',
          ownChosen: true,
        ),
        'many': QuestionAnswer(
          picks: manyPicks,
          own: ' extra ',
          ownChosen: true,
        ),
        'typed': const QuestionAnswer(text: ' answer ', own: ' context '),
        'unrelated': const QuestionAnswer(picks: ['a']),
      };
      final result = answerOf(questions, answers);

      expect(result, {
        'choice': 'b',
        'choice_note': 'note',
        'custom_text': 'mine',
        'many': ['a', 'b', 'other'],
        'many_other': 'extra',
        'typed': 'answer',
        'typed_note': 'context',
      });
      expect(manyPicks, ['a', 'b']);
      expect(identical(result['many'], manyPicks), isFalse);
    });

    test('an empty own answer never suppresses a pick or adds its sentinel '
        'value', () {
      for (final mode in [OwnMode.instead, OwnMode.withValue]) {
        expect(
          _sent(
            _question(
              own: OwnAnswer(field: 'other', mode: mode, value: 'other'),
            ),
            const QuestionAnswer(picks: ['b'], own: ' \t ', ownChosen: true),
          ),
          {'q': 'b'},
        );
      }
      expect(
        _sent(
          _question(
            options: [],
            own: const OwnAnswer(field: 'note', mode: OwnMode.beside),
          ),
          const QuestionAnswer(text: ' \n ', own: 'still a note'),
        ),
        {'note': 'still a note'},
      );
    });

    test('secret filtering removes both fields of every secret without '
        'changing the original answer', () {
      final questions = Questions(QuestionsAgent.codex, [
        _question(
          id: 'secret',
          secret: true,
          own: const OwnAnswer(field: 'secret_note', mode: OwnMode.beside),
        ),
        _question(id: 'another_secret', secret: true),
        _question(
          id: 'public',
          own: const OwnAnswer(field: 'public_note', mode: OwnMode.beside),
        ),
      ]);
      final original = Map<String, Object?>.unmodifiable({
        'secret': 'sensitive',
        'secret_note': 'sensitive note',
        'another_secret': 'also sensitive',
        'public': 'a',
        'public_note': 'keep this',
      });
      expect(withoutSecrets(questions, original), {
        'public': 'a',
        'public_note': 'keep this',
      });
      expect(withoutSecrets(null, original), original);
    });
  });

  group('the shape under _meta', () {
    test('questionsOf reads back what toJson wrote, and nothing else', () {
      final questions = Questions(QuestionsAgent.codex, [
        _question(
          secret: true,
          own: const OwnAnswer(
            field: 'q_other',
            mode: OwnMode.withValue,
            value: 'other',
            placeholder: 'Type here',
          ),
          options: const [
            QuestionOption(
              value: 'a',
              title: 'A',
              description: 'first',
              preview: 'code',
            ),
          ],
        ),
      ], expiresInMs: 60000);
      final json = questions.toJson();
      expect(
        questionsOf({
          '_meta': {questionsKey: json},
        })?.toJson(),
        json,
      );
      expect(questionsOf({}), isNull);
      expect(
        questionsOf({
          '_meta': {
            questionsKey: {'agent': 'nobody', 'questions': []},
          },
        }),
        isNull,
      );
      expect(
        questionsOf({
          '_meta': {
            questionsKey: {'agent': 'claude'},
          },
        }),
        isNull,
      );
    });

    test('formFields takes a form with properties, in order, and its '
        'required keys', () {
      final fields = formFields({
        'mode': 'form',
        'requestedSchema': {
          'properties': {
            'b': {'type': 'string'},
            'a': {'type': 'string'},
          },
          'required': ['a', 3],
        },
      })!;
      expect([for (final (key, _) in fields.properties) key], ['b', 'a']);
      expect(fields.required, {'a'});
      expect(formFields({'mode': 'url'}), isNull);
      expect(
        formFields({
          'mode': 'form',
          'requestedSchema': {'properties': {}},
        }),
        isNull,
      );
    });

    test("choices takes a string's oneOf or an array's anyOf of consts, "
        "with claude's preview", () {
      final one = choices({
        'type': 'string',
        'oneOf': [
          {
            'const': 'a',
            'title': 'A',
            'description': 'first',
            '_meta': {
              '_claude/askUserQuestionOption': {'preview': 'code'},
            },
          },
          {'const': 'b'},
        ],
      })!;
      expect(one.multiSelect, isFalse);
      expect(
        [for (final o in one.options) o.toJson()],
        [
          {
            'value': 'a',
            'title': 'A',
            'description': 'first',
            'preview': 'code',
          },
          {'value': 'b', 'title': 'b'},
        ],
      );
      final many = choices({
        'type': 'array',
        'items': {
          'anyOf': [
            {'const': 'x', 'title': 'X'},
          ],
        },
      })!;
      expect(many.multiSelect, isTrue);
      expect(
        choices({
          'type': 'string',
          'enum': ['a'],
        }),
        isNull,
      );
      expect(
        choices({
          'type': 'string',
          'oneOf': [
            {'const': 1},
          ],
        }),
        isNull,
      );
      expect(choices({'type': 'string', 'oneOf': []}), isNull);
    });

    test('isText takes a plain string, and text a non-empty one', () {
      expect(isText({'type': 'string'}), isTrue);
      expect(isText({'type': 'string', 'oneOf': []}), isFalse);
      expect(isText({'type': 'string', 'enum': []}), isFalse);
      expect(isText({'type': 'number'}), isFalse);
      expect(text('x'), 'x');
      expect(text(''), isNull);
      expect(text(1), isNull);
    });
  });
}
