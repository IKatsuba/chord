import { describe, expect, test } from 'bun:test';
import {
  answerOf,
  withoutSecrets,
  type Question,
  type QuestionAnswer,
} from '../../src/session/questions.ts';

const OPTIONS = [
  { value: 'a', title: 'A' },
  { value: 'b', title: 'B' },
];

function question(extra: Partial<Question> = {}): Question {
  return {
    id: 'q',
    text: 'Which?',
    options: OPTIONS,
    multiSelect: false,
    required: false,
    ...extra,
  };
}

function sent(
  asked: Question,
  answer: Partial<QuestionAnswer> | undefined,
): ReturnType<typeof answerOf> {
  return answerOf(
    { agent: 'claude', questions: [asked] },
    answer === undefined
      ? {}
      : { q: { picks: [], text: '', own: '', ownChosen: false, ...answer } },
  );
}

test("a pick goes in its question's field, a list where it takes several, and an unanswered question sends nothing", () => {
  expect(sent(question(), { picks: ['b'] })).toStrictEqual({ q: 'b' });
  expect(
    sent(question({ multiSelect: true }), { picks: ['a', 'b'] }),
  ).toStrictEqual({ q: ['a', 'b'] });
  expect(sent(question(), undefined)).toStrictEqual({});
  expect(sent(question(), { own: '  ' })).toStrictEqual({});
});

test('a typed question sends its text in its own field', () => {
  expect(sent(question({ options: [] }), { text: ' main ' })).toStrictEqual({
    q: 'main',
  });
});

test('beside: the pick and the text both go, the text whether its row is chosen or not', () => {
  const asked = question({ own: { field: 'q_note', mode: 'beside' } });

  expect(sent(asked, { picks: ['a'], own: 'tests first' })).toStrictEqual({
    q: 'a',
    q_note: 'tests first',
  });
  expect(sent(asked, { own: 'my own' })).toStrictEqual({ q_note: 'my own' });
});

test('instead: the text alone once its row is chosen, else the pick alone', () => {
  const asked = question({ own: { field: 'q_own', mode: 'instead' } });

  expect(
    sent(asked, { picks: ['a'], own: 'mine', ownChosen: true }),
  ).toStrictEqual({ q_own: 'mine' });
  expect(sent(asked, { picks: ['a'], own: 'mine' })).toStrictEqual({
    q: 'a',
  });
});

test('withValue: the option the text stands for goes with it, beside other picks where it takes several', () => {
  const own = { field: 'q_other', mode: 'withValue', value: 'other' } as const;

  expect(
    sent(question({ own }), { own: 'NFS', ownChosen: true }),
  ).toStrictEqual({ q: 'other', q_other: 'NFS' });
  expect(
    sent(question({ own, multiSelect: true }), {
      picks: ['a'],
      own: 'HEIC',
      ownChosen: true,
    }),
  ).toStrictEqual({ q: ['a', 'other'], q_other: 'HEIC' });
  // Another option picked: the text is kept on screen but not sent.
  expect(sent(question({ own }), { picks: ['b'], own: 'NFS' })).toStrictEqual({
    q: 'b',
  });
});

test('a typed question sends its text and its note, each in its own field', () => {
  expect(
    sent(question({ options: [], own: { field: 'q_note', mode: 'beside' } }), {
      text: 'main',
      own: 'the release branch',
    }),
  ).toStrictEqual({ q: 'main', q_note: 'the release branch' });
});

test("a secret question's values are left out of what is kept", () => {
  expect(
    withoutSecrets(
      {
        agent: 'codex',
        questions: [
          question({
            id: 'token',
            options: [],
            secret: true,
            own: { field: 'token_note', mode: 'beside' },
          }),
          question(),
        ],
      },
      { token: 'sk-1', token_note: 'staging', q: 'a' },
    ),
  ).toStrictEqual({ q: 'a' });
});

describe('CHD-1 tester: independent question answers', () => {
  test('all own-answer modes keep each question independent and leave the supplied picks unchanged', () => {
    const questions = {
      agent: 'codex' as const,
      questions: [
        question({
          id: 'choice',
          own: { field: 'choice_note', mode: 'beside' },
        }),
        question({
          id: 'custom',
          own: { field: 'custom_text', mode: 'instead' },
        }),
        question({
          id: 'many',
          multiSelect: true,
          own: { field: 'many_other', mode: 'withValue', value: 'other' },
        }),
        question({
          id: 'typed',
          options: [],
          own: { field: 'typed_note', mode: 'beside' },
        }),
        question({ id: 'unanswered', required: true }),
      ],
    };
    const answers = {
      choice: {
        picks: Object.freeze(['b']),
        text: '',
        own: ' note ',
        ownChosen: false,
      },
      custom: {
        picks: Object.freeze(['a']),
        text: '',
        own: ' mine ',
        ownChosen: true,
      },
      many: {
        picks: Object.freeze(['a', 'b']),
        text: '',
        own: ' extra ',
        ownChosen: true,
      },
      typed: {
        picks: Object.freeze([]),
        text: ' answer ',
        own: ' context ',
        ownChosen: false,
      },
      unrelated: { picks: ['a'], text: '', own: '', ownChosen: false },
    };
    const before = structuredClone(answers);
    const result = answerOf(questions, answers);

    expect(result).toStrictEqual({
      choice: 'b',
      choice_note: 'note',
      custom_text: 'mine',
      many: ['a', 'b', 'other'],
      many_other: 'extra',
      typed: 'answer',
      typed_note: 'context',
    });
    expect(answers).toStrictEqual(before);
    expect(result.many).not.toBe(answers.many.picks);
  });

  test('an empty own answer never suppresses a pick or adds its sentinel value', () => {
    for (const mode of ['instead', 'withValue'] as const) {
      expect(
        sent(question({ own: { field: 'other', mode, value: 'other' } }), {
          picks: ['b'],
          own: ' \t ',
          ownChosen: true,
        }),
      ).toStrictEqual({ q: 'b' });
    }

    expect(
      sent(question({ options: [], own: { field: 'note', mode: 'beside' } }), {
        text: ' \n ',
        own: 'still a note',
      }),
    ).toStrictEqual({ note: 'still a note' });
  });

  test('secret filtering removes both fields of every secret without changing the original answer', () => {
    const questions = {
      agent: 'codex' as const,
      questions: [
        question({
          id: 'secret',
          secret: true,
          own: { field: 'secret_note', mode: 'beside' },
        }),
        question({ id: 'another_secret', secret: true }),
        question({
          id: 'public',
          own: { field: 'public_note', mode: 'beside' },
        }),
      ],
    };
    const original = {
      secret: 'sensitive',
      secret_note: 'sensitive note',
      another_secret: 'also sensitive',
      public: 'a',
      public_note: 'keep this',
    };
    const before = structuredClone(original);

    expect(withoutSecrets(questions, original)).toStrictEqual({
      public: 'a',
      public_note: 'keep this',
    });
    expect(original).toStrictEqual(before);
    expect(withoutSecrets(undefined, original)).toStrictEqual(original);
  });
});
