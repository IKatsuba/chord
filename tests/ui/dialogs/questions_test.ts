import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { enricherRelay } from '../../../src/session/enrich.ts';
import { ENRICHERS } from '../../../src/session/enrichers.ts';
import { type Questions, questionsOf } from '../../../src/session/questions.ts';
import {
  answerText,
  askHeading,
  askHint,
  type AskKey,
  askKey,
  type AskState,
  blockers,
  clock,
  expiresIn,
  openAsk,
  windowOf,
} from '../../../src/ui/dialogs/questions.ts';
import type { ElicitationReply } from '../../../src/session/elicitations.ts';
import {
  CLAUDE_QUESTIONS,
  CODEX_QUESTIONS,
  DIMCODE_QUESTIONS,
  DROID_QUESTIONS,
  type QuestionForm,
} from '../../fixtures/questions.ts';

const NONE: AskKey = { ctrl: false, escape: false };

/** One key's press, by the name the shortcuts panel gives it. */
const KEYS: Record<string, AskKey> = {
  esc: { ...NONE, escape: true },
  enter: { ...NONE, return: true },
  tab: { ...NONE, tab: true },
  'shift + tab': { ...NONE, tab: true, shift: true },
  '↑': { ...NONE, upArrow: true },
  '↓': { ...NONE, downArrow: true },
  '←': { ...NONE, leftArrow: true },
  '→': { ...NONE, rightArrow: true },
  backspace: { ...NONE, backspace: true },
  'ctrl + u': { ...NONE, ctrl: true },
};

/** The questions the enrichers read in `form`, with its schema. */
function read(form: QuestionForm): {
  questions: Questions;
  form: QuestionForm;
} {
  const [message] = enricherRelay(ENRICHERS).fromAgent({
    jsonrpc: '2.0',
    id: 1,
    method: 'elicitation/create',
    params: { ...form, sessionId: 's' },
  });

  assert(message !== undefined && 'params' in message);

  const questions = questionsOf(message.params as QuestionForm);

  assert(questions !== undefined);

  return { questions, form };
}

/**
 * The box after each of `keys`, a named key or text typed as it is, with the
 * answer the last one gave, if any.
 */
function play(
  form: QuestionForm,
  ...keys: string[]
): { state: AskState; response?: ElicitationReply } {
  const { questions } = read(form);
  let state = openAsk(questions, 0);
  let response: ElicitationReply | undefined;

  for (const name of keys) {
    const key = KEYS[name];
    const input = name === 'ctrl + u' ? 'u' : key === undefined ? name : '';
    const step = askKey(
      questions,
      form.requestedSchema,
      state,
      input,
      key ?? NONE,
    );

    state = step.state;
    response = step.response;
  }

  return { state, ...(response === undefined ? {} : { response }) };
}

test("Enter picks a question's option and goes on; Send sends it under the agent's field", () => {
  const { state, response } = play(
    CLAUDE_QUESTIONS,
    'enter',
    ' ',
    '3',
    'enter',
    'enter',
  );

  expect(state.step).toBe(2);
  expect(response).toStrictEqual({
    action: 'accept',
    content: {
      question_0: 'Deno (TypeScript) (Recommended)',
      question_1: ['Types', 'Tests'],
    },
  });
});

test('a digit picks and goes on, or on a multi-select toggles and stays', () => {
  expect(play(CLAUDE_QUESTIONS, '2').state).toMatchObject({
    step: 1,
    answers: { question_0: { picks: ['Python'] } },
  });
  expect(play(CLAUDE_QUESTIONS, '2', '2', '2', '3').state).toMatchObject({
    step: 1,
    row: 2,
    answers: { question_1: { picks: ['Tests'] } },
  });
});

test('the note beside a pick is typed on its own row, and both are sent', () => {
  const { response } = play(
    CODEX_QUESTIONS,
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
  );

  expect(response).toStrictEqual({
    action: 'accept',
    content: {
      next: 'Review existing work',
      next_note: 'tests first',
      token: 'sk-1',
    },
  });
});

test("an own answer that stands for droid's other option is picked by typing, and dropped by another pick", () => {
  const typed = play(DROID_QUESTIONS, '↓', '↓', 'NFS');

  expect(typed.state.answers.question_0).toStrictEqual({
    picks: [],
    text: '',
    own: 'NFS',
    ownChosen: true,
  });
  expect(
    play(DROID_QUESTIONS, '↓', '↓', 'NFS', '↑', 'enter').state.answers,
  ).toMatchObject({
    question_0: { picks: ['option_1'], own: 'NFS', ownChosen: false },
  });
  // A multi-select's own option ticks with Space while it holds no text.
  expect(
    play(DROID_QUESTIONS, 'tab', '↓', '↓', ' ').state.answers.question_1,
  ).toMatchObject({ ownChosen: true, own: '' });
});

test("dimcode's own answer clears the pick it stands instead of", () => {
  const { response } = play(
    DIMCODE_QUESTIONS,
    '1',
    '←',
    '↓',
    '↓',
    'canary',
    'tab',
    'enter',
  );

  expect(response).toStrictEqual({
    action: 'accept',
    content: { __custom_0: 'canary' },
  });
});

test('Send is out of reach while a required question has no answer; Enter then skips', () => {
  const { questions, form } = read(CODEX_QUESTIONS);
  const { state, response } = play(CODEX_QUESTIONS, '→', '→', '↑', 'enter');

  expect(blockers(questions, form.requestedSchema, state)).toStrictEqual(
    new Map([
      ['next', 'required'],
      ['token', 'required'],
    ]),
  );
  expect(response).toStrictEqual({ action: 'decline' });
  expect(play(CODEX_QUESTIONS, '→', '→', '1').response).toBeUndefined();
});

test('Esc cancels from any step, and ← → stop at the ends', () => {
  expect(play(CLAUDE_QUESTIONS, '→', 'esc').response).toStrictEqual({
    action: 'cancel',
  });
  expect(play(CLAUDE_QUESTIONS, '←').state.step).toBe(0);
  expect(play(CLAUDE_QUESTIONS, '→', '→', '→').state.step).toBe(2);
});

test('text is edited at its end: backspace, ctrl+u', () => {
  expect(
    play(CODEX_QUESTIONS, 'tab', 'abc', 'backspace').state.answers.token?.text,
  ).toBe('ab');
  expect(
    play(CODEX_QUESTIONS, 'tab', 'abc', 'ctrl + u').state.answers.token?.text,
  ).toBe('');
});

test('the summary reads titles, a note after ·, and a secret as dots', () => {
  const { questions } = read(CODEX_QUESTIONS);
  const { state } = play(
    CODEX_QUESTIONS,
    '2',
    'sk-1',
    'shift + tab',
    '↓',
    '↓',
    'first',
  );
  const [next, token] = questions.questions;

  assert(next !== undefined && token !== undefined);
  expect(answerText(next, state)).toBe('Review existing work · first');
  expect(answerText(token, state)).toBe('••••');
  expect(
    answerText(read(DROID_QUESTIONS).questions.questions[0]!, {
      ...state,
      answers: {
        question_0: {
          picks: ['option_1'],
          text: '',
          own: '',
          ownChosen: false,
        },
      },
    }),
  ).toBe('S3 bucket');
});

test('the heading counts the questions, and the countdown runs from when the box opened', () => {
  const { questions } = read(CODEX_QUESTIONS);
  const state = openAsk(questions, 1000);

  expect(askHeading('codex', questions)).toBe('codex asks you 2 questions');
  expect(
    askHeading('claude', {
      ...questions,
      questions: questions.questions.slice(1),
    }),
  ).toBe('claude asks you a question');
  expect(clock(expiresIn(questions, state, 1000 + 28_500) ?? 0)).toBe('4:32');
  expect(expiresIn(questions, state, 1000 + 400_000)).toBe(0);
  expect(expiresIn(read(CLAUDE_QUESTIONS).questions, state, 0)).toBeUndefined();
});

test('the hint names ←→ for the questions on every row, short at 80 columns', () => {
  const { questions } = read(DROID_QUESTIONS);
  const at = (state: AskState, width: number) =>
    askHint(questions, state, width);
  const open = openAsk(questions, 0);
  const own = { ...open, row: 2 };
  const multiOwn = { ...open, step: 1, row: 2 };

  for (const state of [open, own, multiOwn, { ...open, step: 3 }]) {
    expect(at(state, 116)).toContain('←→ or Tab for the questions');
    expect(at(state, 76)).toContain('←→ questions');
    expect(at(state, 76).length).toBeLessThanOrEqual(76);
  }
});

test('a step too tall keeps the focused row whole and counts the rows cut off', () => {
  // The question, a blank, four one-line options and one of three lines.
  const rows = [undefined, undefined, 0, 1, 1, 1, 2, 3, 4];

  expect(windowOf(rows, 0, 9)).toStrictEqual({
    top: 0,
    end: 9,
    above: 0,
    below: 0,
  });
  expect(windowOf(rows, 0, 6)).toStrictEqual({
    top: 0,
    end: 5,
    above: 0,
    below: 3,
  });
  expect(windowOf(rows, 4, 6)).toStrictEqual({
    top: 6,
    end: 9,
    above: 2,
    below: 0,
  });
});
