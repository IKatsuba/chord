// The original's enrichers_test.ts, the cases of the five question
// enrichers: claudeQuestions, codexQuestions, droidQuestions,
// opencodeQuestions and dimcodeQuestions, run as the whole chain.
import 'dart:convert';

import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:chord/session/questions.dart';
import 'package:test/test.dart';

import '../fixtures/forms.dart';
import '../fixtures/questions.dart';

const _session = 'session-1';

/// A mutable deep copy of [value].
Map<String, Object?> _copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

/// [value] with every map and list in it unmodifiable, as the original
/// freezes its fixtures.
Object? _frozen(Object? value) => switch (value) {
  final Map<String, Object?> map => Map<String, Object?>.unmodifiable({
    for (final MapEntry(:key, :value) in map.entries) key: _frozen(value),
  }),
  final List<Object?> list => List<Object?>.unmodifiable(list.map(_frozen)),
  _ => value,
};

Map<String, Object?> _properties(Map<String, Object?> form) =>
    recordOf(recordOf(form['requestedSchema'])['properties']);

/// What the chain makes of [form] asked as `elicitation/create`.
Map<String, Object?> _asked(Map<String, Object?> form) {
  final [message] = enricherRelay(m1Enrichers).fromAgent({
    'jsonrpc': '2.0',
    'id': 'e-1',
    'method': 'elicitation/create',
    'params': {...form, 'sessionId': _session},
  });
  return recordOf(message['params']);
}

/// The questions the chain read from [form], checking it left the form be.
Map<String, Object?>? _questionsIn(Map<String, Object?> form) {
  final params = _asked(form);
  final meta = {...recordOf(params['_meta'])};
  final questions = meta.remove(questionsKey);
  final filled = meta.remove(filledKey);
  expect({...params}..remove('_meta'), {
    for (final MapEntry(:key, :value) in form.entries)
      if (key != '_meta') key: value,
    'sessionId': _session,
  });
  expect(meta, recordOf(form['_meta']));
  if (questions != null) expect(filled, [questionsKey]);
  return questions as Map<String, Object?>?;
}

/// [form] with [properties] beside its own.
Map<String, Object?> _withFields(
  Map<String, Object?> form,
  Map<String, Object?> properties,
) => {
  ...form,
  'requestedSchema': {
    ...recordOf(form['requestedSchema']),
    'properties': {..._properties(form), ...properties},
  },
};

void main() {
  group('CTUI-68 tester: question reader boundaries', () {
    test('only form requests with an id are enriched', () {
      final request = <String, Object?>{
        'jsonrpc': '2.0',
        'id': 'request',
        'method': 'elicitation/create',
        'params': claudeQuestionsForm,
      };
      final notification = {...request}..remove('id');
      for (final message in [
        notification,
        {...request, 'method': 'unrelated'},
        {
          ...request,
          'params': {...claudeQuestionsForm, 'mode': 'url'},
        },
      ]) {
        expect(enricherRelay(m1Enrichers).fromAgent(message), [message]);
      }
    });

    test('existing non-null question metadata is never replaced', () {
      for (final existing in [
        false,
        '',
        [],
        {'agent': 'future'},
      ]) {
        final form = {
          ...claudeQuestionsForm,
          '_meta': {questionsKey: existing, 'untouched': 'keep'},
        };
        expect(_asked(form), {...form, 'sessionId': _session});
      }
    });

    test(
      'own fields can precede questions without changing question order',
      () {
        for (final fixture in [
          claudeQuestionsForm,
          droidQuestionsForm,
          opencodeQuestionsForm,
          dimcodeQuestionsForm,
        ]) {
          final form = _copy(fixture);
          final properties = _properties(form);
          final ownKeys = properties.keys
              .where(
                (key) =>
                    RegExp(r'(?:_custom|_other)$|^__custom_').hasMatch(key),
              )
              .toSet();
          (form['requestedSchema'] as Map<String, Object?>)['properties'] = {
            for (final key in ownKeys) key: properties[key],
            for (final key in properties.keys)
              if (!ownKeys.contains(key)) key: properties[key],
          };
          expect(_questionsIn(form), _questionsIn(fixture));
        }
      },
    );

    test('codex keeps zero and fractional waits and ignores invalid waits', () {
      for (final wait in <Object?>[0, 0.5, -1, '300000', false, null]) {
        final form = _copy(codexQuestionsForm);
        (form['_meta'] as Map<String, Object?>)['codex'] = {
          'autoResolutionMs': wait,
        };
        final shape = _questionsIn(form)!;
        if (wait is num && wait >= 0) {
          expect(shape['expiresInMs'], wait);
        } else {
          expect(shape.containsKey('expiresInMs'), isFalse);
        }
      }
    });

    test('required adapter marks and matching other fields cannot be lost', () {
      for (final fixture in [claudeQuestionsForm, opencodeQuestionsForm]) {
        final form = _copy(fixture);
        final own = _properties(
          form,
        ).keys.firstWhere((key) => key.endsWith('_custom'));
        (_properties(form)[own] as Map<String, Object?>)['title'] = 'Changed';
        expect(_questionsIn(form), isNull);
      }
      for (final removeOwn in [true, false]) {
        final form = _copy(droidQuestionsForm);
        final properties = _properties(form);
        if (removeOwn) {
          properties.remove('question_0_other');
        } else {
          final property = properties['question_0'] as Map<String, Object?>;
          (property['oneOf'] as List<Object?>).removeLast();
        }
        expect(_questionsIn(form), isNull);
      }
    });
  });

  test("claude's questions: its header, the question, the options and the "
      'Other beside the pick', () {
    expect(_questionsIn(claudeQuestionsForm), {
      'agent': 'claude',
      'questions': [
        {
          'id': 'question_0',
          'header': 'Language',
          'text': 'Which language should helper scripts use?',
          'multiSelect': false,
          'required': false,
          'options': [
            {
              'value': 'Deno (TypeScript) (Recommended)',
              'title': 'Deno (TypeScript) (Recommended)',
              'description':
                  'Runs from source with inline npm: and jsr: imports, no '
                  'package manager',
            },
            {
              'value': 'Python',
              'title': 'Python',
              'description': 'Only where a library has no JS or TS equivalent',
              'preview': 'print("hi")',
            },
          ],
          'own': {
            'field': 'question_0_custom',
            'mode': 'beside',
            'placeholder':
                'Type your own answer, or add a note to the option you chose '
                'above (optional).',
          },
        },
        {
          'id': 'question_1',
          'header': 'Checks',
          'text': 'Which checks should run before a commit?',
          'multiSelect': true,
          'required': false,
          'options': [
            {'value': 'Types', 'title': 'Types'},
            {'value': 'Lint', 'title': 'Lint'},
            {'value': 'Tests', 'title': 'Tests'},
          ],
          'own': {
            'field': 'question_1_custom',
            'mode': 'beside',
            'placeholder':
                'Type your own answer to add to your selection above '
                '(optional).',
          },
        },
      ],
    });
  });

  test("claude's lone question is its form's message", () {
    expect(
      Questions.fromJson(_questionsIn(claudeQuestionForm))!.questions[0].text,
      'Which language should helper scripts use?',
    );
  });

  test("codex's questions: the question its title, the header its "
      'description, the note beside, a secret and the wait', () {
    expect(_questionsIn(codexQuestionsForm), {
      'agent': 'codex',
      'expiresInMs': 300000,
      'questions': [
        {
          'id': 'next',
          'header': 'Next step',
          'text': 'What would you like to focus on next?',
          'multiSelect': false,
          'required': true,
          'options': [
            {
              'value': 'Plan a change (Recommended)',
              'title': 'Plan a change (Recommended)',
            },
            {
              'value': 'Review existing work',
              'title': 'Review existing work',
              'description': 'Read what is there first',
            },
            {
              'value': 'None of the above',
              'title': 'None of the above',
              'description': 'Provide a different answer in the note field.',
            },
          ],
          'own': {
            'field': 'next_note',
            'mode': 'beside',
            'placeholder': 'Additional answer or note',
          },
        },
        {
          'id': 'token',
          'header': 'Token',
          'text': 'Paste the API token for the staging deploy.',
          'multiSelect': false,
          'required': true,
          'secret': true,
          'options': <Object?>[],
        },
      ],
    });
  });

  test("factory-droid's questions: its other option taken out, to go with "
      'the text typed', () {
    expect(_questionsIn(droidQuestionsForm), {
      'agent': 'droid',
      'questions': [
        {
          'id': 'question_0',
          'header': 'Storage',
          'text': 'Where should uploads be kept?',
          'multiSelect': false,
          'required': true,
          'options': [
            {'value': 'option_0', 'title': 'Local disk'},
            {'value': 'option_1', 'title': 'S3 bucket'},
          ],
          'own': {
            'field': 'question_0_other',
            'mode': 'withValue',
            'value': 'other',
          },
        },
        {
          'id': 'question_1',
          'header': 'Formats',
          'text': 'Which formats should be accepted?',
          'multiSelect': true,
          'required': true,
          'options': [
            {'value': 'option_0', 'title': 'PNG'},
            {'value': 'option_1', 'title': 'JPEG'},
          ],
          'own': {
            'field': 'question_1_other',
            'mode': 'withValue',
            'value': 'other',
          },
        },
        {
          'id': 'question_2',
          'header': 'Bucket',
          'text': 'What should the bucket be called?',
          'multiSelect': false,
          'required': true,
          'options': <Object?>[],
        },
      ],
    });
  });

  test("opencode's and dimcode's questions, dimcode's own answer instead of "
      'a pick', () {
    expect(_questionsIn(opencodeQuestionsForm), {
      'agent': 'opencode',
      'questions': [
        {
          'id': 'q0',
          'header': 'Tests',
          'text': 'Where should the new tests go?',
          'multiSelect': false,
          'required': false,
          'options': [
            {
              'value': 'Beside the module',
              'title': 'Beside the module',
              'description': 'tests/ mirrors src/',
            },
            {'value': 'In one file', 'title': 'In one file'},
          ],
          'own': {'field': 'q0_custom', 'mode': 'beside'},
        },
      ],
    });
    expect(_questionsIn(dimcodeQuestionsForm), {
      'agent': 'dimcode',
      'questions': [
        {
          'id': 'deploy',
          'header': 'Deploy',
          'text': 'Where should it deploy?',
          'multiSelect': false,
          'required': false,
          'options': [
            {'value': 'Staging', 'title': 'Staging'},
            {'value': 'Production', 'title': 'Production'},
          ],
          'own': {'field': '__custom_0', 'mode': 'instead'},
        },
      ],
    });
  });

  test("a form with no adapter's marks passes as it came", () {
    const form = {
      'mode': 'form',
      'message': 'Set up the deploy target',
      'requestedSchema': formSchema,
    };
    expect(_asked(form), {...form, 'sessionId': _session});
  });

  test('a form with a field no question has a place for gets no '
      'questions', () {
    // A field of another kind.
    expect(
      _questionsIn(
        _withFields(claudeQuestionsForm, {
          'count': {'type': 'integer'},
        }),
      ),
      isNull,
    );
    // An own answer whose question is not there.
    expect(
      _questionsIn(
        _withFields(claudeQuestionsForm, {
          'question_9_custom': {'type': 'string', 'title': 'Other'},
        }),
      ),
      isNull,
    );
    // A codex note for a question it does not ask.
    expect(
      _questionsIn(
        _withFields(codexQuestionsForm, {
          'lost_note': {
            'type': 'string',
            '_meta': {
              'codex': {'questionId': 'lost', 'role': 'user_note'},
            },
          },
        }),
      ),
      isNull,
    );
    // factory-droid's form under another message.
    expect(
      _questionsIn({...droidQuestionsForm, 'message': 'Answer these.'}),
      isNull,
    );
  });

  test('a second own answer for one question, or options as a plain enum, '
      'get no questions', () {
    // codex: two notes for `next`.
    expect(
      _questionsIn(
        _withFields(codexQuestionsForm, {
          'next_note1': {
            'type': 'string',
            '_meta': {
              'codex': {'questionId': 'next', 'role': 'user_note'},
            },
          },
        }),
      ),
      isNull,
    );
    // dimcode: two custom answers for `deploy`.
    expect(
      _questionsIn(
        _withFields(dimcodeQuestionsForm, {
          '__custom_1': {
            'type': 'string',
            '_meta': {
              'lody': {
                'elicitation': {'customAnswerFor': 'deploy'},
              },
            },
          },
        }),
      ),
      isNull,
    );
    // codex and factory-droid: options as an `enum`, not `oneOf`.
    expect(
      _questionsIn(
        _withFields(codexQuestionsForm, {
          'size': {
            'type': 'string',
            'title': 'How big?',
            'enum': ['small', 'large'],
            '_meta': {
              'codex': {'isOther': false, 'isSecret': false},
            },
          },
        }),
      ),
      isNull,
    );
    expect(
      _questionsIn(
        _withFields(droidQuestionsForm, {
          'question_3': {
            'type': 'string',
            'title': 'Size',
            'description': 'How big?',
            'enum': ['option_0', 'option_1'],
          },
        }),
      ),
      isNull,
    );
  });

  group('CHD-1 tester: conservative question enrichment', () {
    const forms = [
      claudeQuestionsForm,
      claudeQuestionForm,
      codexQuestionsForm,
      droidQuestionsForm,
      opencodeQuestionsForm,
      dimcodeQuestionsForm,
    ];

    test('frozen requests keep every original field and metadata key, and '
        'enrichment is idempotent', () {
      for (final fixture in forms) {
        final form =
            _frozen({
                  ..._copy(fixture),
                  '_meta': {
                    ...recordOf(fixture['_meta']),
                    'untouched': {
                      'list': ['keep', 'these'],
                    },
                    filledKey: ['existing'],
                  },
                })
                as Map<String, Object?>;
        final original = _copy(form);

        final result = _asked(form);
        final meta = recordOf(result['_meta']);
        final questions = Questions.fromJson(meta[questionsKey])!;
        final represented = [
          for (final question in questions.questions) ...[
            question.id,
            if (question.own case final own?) own.field,
          ],
        ];

        expect(form, original);
        expect(represented.toSet().length, represented.length);
        expect(represented..sort(), _properties(form).keys.toList()..sort());
        expect(result['requestedSchema'], form['requestedSchema']);
        expect(meta['untouched'], {
          'list': ['keep', 'these'],
        });
        expect(meta[filledKey], ['existing', questionsKey]);
        final again = {
          'jsonrpc': '2.0',
          'id': 'again',
          'method': 'elicitation/create',
          'params': result,
        };
        expect(enricherRelay(m1Enrichers).fromAgent(again), [again]);
      }
    });

    test('one unsupported field leaves the whole original request available '
        'to the generic form', () {
      for (final fixture in forms) {
        for (final extra in [
          {'type': 'integer', 'minimum': 1},
          {
            'type': 'string',
            'enum': ['small', 'large'],
          },
          {
            'type': 'array',
            'items': {
              'type': 'string',
              'enum': ['one', 'two'],
            },
          },
        ]) {
          final form = _copy(fixture);
          final schema = form['requestedSchema'] as Map<String, Object?>;
          (schema['properties'] as Map<String, Object?>)['extra'] = extra;
          schema['required'] = [
            ...(schema['required'] as List<Object?>? ?? const []),
            'extra',
          ];
          final frozen = _frozen(form) as Map<String, Object?>;
          expect(_asked(frozen), {...frozen, 'sessionId': _session});
        }
      }
    });

    test('malformed choices and own answers fall back without dropping any '
        'fields', () {
      for (final fixture in forms) {
        final id = _properties(fixture).keys.first;
        for (final options in [
          <Object?>[],
          [
            {'const': 7, 'title': 'Seven'},
          ],
        ]) {
          final form = _copy(fixture);
          final property = _properties(form)[id] as Map<String, Object?>;
          property
            ..['type'] = 'string'
            ..['oneOf'] = options;
          final frozen = _frozen(form) as Map<String, Object?>;
          expect(_asked(frozen), {...frozen, 'sessionId': _session});
        }

        final own = _copy(fixture);
        final ownId = _properties(own).keys.firstWhere(
          (key) =>
              RegExp(r'(?:_custom|_note|_other)$|^__custom_').hasMatch(key),
        );
        (_properties(own)[ownId] as Map<String, Object?>)['type'] = 'integer';
        final frozen = _frozen(own) as Map<String, Object?>;
        expect(_asked(frozen), {...frozen, 'sessionId': _session});
      }
    });

    test('codex note pairing follows questionId even when the note precedes '
        'its text question', () {
      final form = _copy(codexQuestionsForm);
      final schema = form['requestedSchema'] as Map<String, Object?>;
      schema['properties'] = {
        'token_note': {
          'type': 'string',
          'title': 'Token note',
          '_meta': {
            'codex': {'role': 'user_note', 'questionId': 'token'},
          },
        },
        ...recordOf(schema['properties']),
      };

      final questions = Questions.fromJson(_questionsIn(form))!;
      expect(
        [for (final question in questions.questions) question.id],
        ['next', 'token'],
      );
      expect(questions.questions[1].own?.toJson(), {
        'field': 'token_note',
        'mode': 'beside',
        'placeholder': 'Token note',
      });
      expect(questions.questions[1].secret, isTrue);
    });
  });
}
