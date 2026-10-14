/**
 * The question box, kept out of the component: an agent's questions one step
 * at a time, then a Submit step, as Claude Code's AskUserQuestion draws them;
 * what each key does to them, the rows a step draws, the hint line and the
 * answer it sends, under the agent's own field ids (`answerOf`). A form the
 * enrichers read no questions in keeps the field table (`form.ts`).
 */
import type {
  ElicitationContentValue,
  ElicitationSchema,
} from '@agentclientprotocol/sdk';
import type { ElicitationReply } from '../../session/elicitations.ts';
import {
  answerOf,
  type Question,
  type QuestionAnswer,
  type Questions,
} from '../../session/questions.ts';
import type { KeyPress } from '../shortcuts/state.ts';
import { openForm, problemsOf } from './form.ts';

/** The box as the person has it: the step, the row and the answers. */
export interface AskState {
  /** A question's index, or the questions' count for Submit. */
  readonly step: number;
  /** The row the `❯` is on within the step. */
  readonly row: number;
  readonly answers: Readonly<Record<string, QuestionAnswer>>;
  /** When the box opened, for the time an agent waits before it answers. */
  readonly openedAt: number;
}

/** One row a question step's `❯` moves through. */
export type StepRow =
  | { readonly kind: 'option'; readonly index: number }
  /** A question with no options: its answer, typed. */
  | { readonly kind: 'text' }
  /** Its own answer: a `Note` beside the pick, or a last numbered option. */
  | { readonly kind: 'own' };

const EMPTY: QuestionAnswer = {
  picks: [],
  text: '',
  own: '',
  ownChosen: false,
};

/** The rows of `question`'s step, in order. */
export function rowsOf(question: Question): StepRow[] {
  return [
    ...question.options.map((_, index) => ({ kind: 'option', index }) as const),
    ...(question.options.length === 0 ? [{ kind: 'text' } as const] : []),
    ...(question.own === undefined ? [] : [{ kind: 'own' } as const]),
  ];
}

/** Whether the own answer is a numbered option of its own, not a note. */
export function ownIsOption(question: Question): boolean {
  return question.own !== undefined && question.own.mode !== 'beside';
}

export function answerTo(state: AskState, question: Question): QuestionAnswer {
  return state.answers[question.id] ?? EMPTY;
}

/** The content Send gives the agent. */
export function contentOf(
  questions: Questions,
  state: AskState,
): Record<string, ElicitationContentValue> {
  return answerOf(questions, state.answers);
}

/** Whether `question` has an answer that would be sent. */
export function answered(question: Question, state: AskState): boolean {
  const content = answerOf(
    { agent: 'claude', questions: [question] },
    state.answers,
  );

  return Object.keys(content).length > 0;
}

/**
 * What stops Send, by question: a required one with no answer, or what the
 * agent's own schema finds wrong with the content, in the field table's
 * words, against the question its field belongs to.
 */
export function blockers(
  questions: Questions,
  schema: ElicitationSchema,
  state: AskState,
): Map<string, string> {
  const content = contentOf(questions, state);
  const problems = problemsOf({
    ...openForm(schema),
    values: content as Record<string, string | readonly string[]>,
  });
  const found = new Map<string, string>();

  for (const question of questions.questions) {
    const problem =
      problems.get(question.id) ??
      (question.own === undefined
        ? undefined
        : problems.get(question.own.field));

    if (
      problem === 'Required' ||
      (question.required && !answered(question, state))
    ) {
      found.set(question.id, 'required');
    } else if (problem !== undefined) {
      found.set(question.id, problem);
    }
  }

  return found;
}

/** The box as it opens: the first question, on its picked or first row. */
export function openAsk(questions: Questions, now: number): AskState {
  return enter({ step: 0, row: 0, answers: {}, openedAt: now }, questions, 0);
}

/** The row `❯` takes on entering a step: Send where it can go, else Skip. */
function enter(state: AskState, questions: Questions, step: number): AskState {
  const question = questions.questions[step];

  if (question === undefined) {
    return { ...state, step, row: 0 };
  }

  const { picks, ownChosen } = answerTo(state, question);
  const rows = rowsOf(question);
  const picked = rows.findIndex(
    (row) =>
      (row.kind === 'option' &&
        picks.includes(question.options[row.index]?.value ?? '')) ||
      (row.kind === 'own' && ownChosen && ownIsOption(question)),
  );

  return { ...state, step, row: Math.max(picked, 0) };
}

/** The Submit step's rows: Send, which may be out of reach, and Skip. */
const SEND = 0;
const SKIP = 1;

function setAnswer(
  state: AskState,
  question: Question,
  change: Partial<QuestionAnswer>,
): AskState {
  return {
    ...state,
    answers: {
      ...state.answers,
      [question.id]: { ...answerTo(state, question), ...change },
    },
  };
}

/** What a key press did: the box after it, and the answer if it gave one. */
export interface AskStep {
  readonly state: AskState;
  readonly response?: ElicitationReply;
}

/** The parts of a press the box reads. */
export interface AskKey extends KeyPress {
  readonly leftArrow?: boolean;
  readonly rightArrow?: boolean;
}

/** Typing and deleting at the end of a text row's value. */
function edited(value: string, input: string, key: AskKey): string | undefined {
  const chars = [...value];

  if (key.backspace) {
    return chars.slice(0, -1).join('');
  }

  if (key.ctrl && input === 'u') {
    return '';
  }

  if (key.ctrl && input === 'w') {
    return value.replace(/\S*\s*$/, '');
  }

  if (
    key.ctrl ||
    key.meta ||
    input === '' ||
    key.tab ||
    key.return ||
    key.escape
  ) {
    return undefined;
  }

  // A line break pasted into one line of text is a space.
  return value + input.replaceAll(/\r\n|\r|\n/g, ' ');
}

/** Picks or toggles option `index` of `question`. */
function pick(state: AskState, question: Question, index: number): AskState {
  const option = question.options[index];
  const answer = answerTo(state, question);

  if (option === undefined) {
    return state;
  }

  if (!question.multiSelect) {
    return setAnswer(state, question, {
      picks: [option.value],
      // A single question's own option and a pick are one choice.
      ownChosen: ownIsOption(question) ? false : answer.ownChosen,
    });
  }

  const ticked = answer.picks.includes(option.value)
    ? answer.picks.filter((value) => value !== option.value)
    : [...answer.picks, option.value];
  const ordered = question.options
    .map((entry) => entry.value)
    .filter((value) => ticked.includes(value));

  // dimcode refuses its own answer beside a pick.
  return setAnswer(state, question, {
    picks: ordered,
    ...(question.own?.mode === 'instead' ? { ownChosen: false } : {}),
  });
}

/** Typing in the own answer's row. */
function typeOwn(state: AskState, question: Question, own: string): AskState {
  const mode = question.own?.mode;
  const chosen = own !== '';

  if (mode === 'beside') {
    return setAnswer(state, question, { own });
  }

  return setAnswer(state, question, {
    own,
    ownChosen: chosen,
    // Typing an answer of one's own is the one choice on a single
    // question, and stands instead of every pick on dimcode's.
    ...(chosen && (mode === 'instead' || !question.multiSelect)
      ? { picks: [] }
      : {}),
  });
}

/**
 * What a key does to the box. Esc answers `cancel`; Send `accept` with the
 * content, and Skip `decline`.
 */
export function askKey(
  questions: Questions,
  schema: ElicitationSchema,
  state: AskState,
  input: string,
  key: AskKey,
): AskStep {
  const count = questions.questions.length;
  const go = (step: number) => ({
    state: enter(state, questions, Math.min(Math.max(step, 0), count)),
  });

  if (key.escape) {
    return { state, response: { action: 'cancel' } };
  }

  // shift+↑ and shift+↓ scroll the transcript; they are the window's.
  if (key.shift && (key.upArrow || key.downArrow)) {
    return { state };
  }

  if (key.tab) {
    return go(state.step + (key.shift ? -1 : 1));
  }

  if (key.leftArrow) {
    return go(state.step - 1);
  }

  if (key.rightArrow) {
    return go(state.step + 1);
  }

  const question = questions.questions[state.step];

  if (question === undefined) {
    const sendable = blockers(questions, schema, state).size === 0;
    const choose = (row: number): AskStep =>
      row === SEND
        ? {
            state,
            response: {
              action: 'accept',
              content: contentOf(questions, state),
            },
          }
        : { state, response: { action: 'decline' } };

    if (key.upArrow && sendable) {
      return { state: { ...state, row: SEND } };
    }

    if (key.downArrow) {
      return { state: { ...state, row: SKIP } };
    }

    if (key.return) {
      return choose(sendable ? state.row : SKIP);
    }

    if (input === '1' && sendable) {
      return choose(SEND);
    }

    if (input === '2') {
      return choose(SKIP);
    }

    return { state };
  }

  const rows = rowsOf(question);
  const row = rows[state.row];

  if (key.upArrow) {
    return { state: { ...state, row: Math.max(state.row - 1, 0) } };
  }

  if (key.downArrow) {
    return {
      state: { ...state, row: Math.min(state.row + 1, rows.length - 1) },
    };
  }

  if (row?.kind === 'text') {
    if (key.return) {
      return go(state.step + 1);
    }

    const text = edited(answerTo(state, question).text, input, key);

    return {
      state: text === undefined ? state : setAnswer(state, question, { text }),
    };
  }

  if (row?.kind === 'own') {
    const answer = answerTo(state, question);

    if (key.return) {
      return go(state.step + 1);
    }

    // Space ticks or unticks a multi-select's own option while nothing is
    // typed in it, as on any other of its rows; then it is a space.
    if (
      input === ' ' &&
      question.multiSelect &&
      ownIsOption(question) &&
      answer.own === ''
    ) {
      return {
        state: setAnswer(state, question, { ownChosen: !answer.ownChosen }),
      };
    }

    const own = edited(answer.own, input, key);

    return {
      state: own === undefined ? state : typeOwn(state, question, own),
    };
  }

  const digit = /^[1-9]$/.test(input) ? Number(input) - 1 : undefined;

  if (digit !== undefined && digit < question.options.length) {
    const picked = pick(state, question, digit);

    return question.multiSelect
      ? { state: { ...picked, row: digit } }
      : { state: enter(picked, questions, state.step + 1) };
  }

  // The own answer's number takes the `❯` there to type, and picks it if
  // something is typed in it already.
  if (digit === question.options.length && ownIsOption(question)) {
    const { own } = answerTo(state, question);
    const at = { ...state, row: digit };

    return { state: own === '' ? at : typeOwn(at, question, own) };
  }

  if (row?.kind !== 'option') {
    return { state };
  }

  if (question.multiSelect) {
    if (input === ' ') {
      return { state: pick(state, question, row.index) };
    }

    return key.return ? go(state.step + 1) : { state };
  }

  if (key.return || input === ' ') {
    const picked = pick(state, question, row.index);

    return key.return
      ? { state: enter(picked, questions, state.step + 1) }
      : { state: picked };
  }

  return { state };
}

/** The wide hint from this inner width, where it fits. */
export const WIDE_ASK_HINT = 100;

/** The hint line's keys for where the `❯` is. */
export function askHint(
  questions: Questions,
  state: AskState,
  width: number,
): string {
  const pickHint = (long: string, short: string) =>
    width >= WIDE_ASK_HINT && long.length <= width ? long : short;
  const question = questions.questions[state.step];

  if (question === undefined) {
    return pickHint(
      'Enter to choose · ←→ or Tab for the questions · Esc to cancel',
      'Enter to choose · ←→ questions · Esc to cancel',
    );
  }

  const row = rowsOf(question)[state.row];

  if (row?.kind === 'text' || (row?.kind === 'own' && ownIsOption(question))) {
    const toggle =
      row.kind === 'own' && question.multiSelect ? 'Space to toggle · ' : '';

    return pickHint(
      `Type your answer · ${toggle}Enter for the next · ←→ or Tab for the questions · Esc to cancel`,
      `${toggle === '' ? 'Type your answer' : 'Type'} · ${toggle}Enter for the next · ←→ questions · Esc to cancel`,
    );
  }

  if (row?.kind === 'own') {
    return pickHint(
      'Enter for the next · ↑ to the options · ←→ or Tab for the questions · Esc to cancel',
      'Enter for the next · ↑ options · ←→ questions · Esc to cancel',
    );
  }

  if (question.multiSelect) {
    return pickHint(
      'Space to toggle · Enter for the next · ↑↓ to move · ←→ or Tab for the questions · Esc to cancel',
      'Space to toggle · Enter for the next · ↑↓ · ←→ questions · Esc to cancel',
    );
  }

  const digits = `1–${Math.min(
    question.options.length + (ownIsOption(question) ? 1 : 0),
    9,
  )}`;

  return pickHint(
    `Enter to pick · ${digits} · ↑↓ to move · ←→ or Tab for the questions · Esc to cancel`,
    `Enter to pick · ${digits} · ↑↓ · ←→ questions · Esc to cancel`,
  );
}

/** A question's label on its chip and in the summary. */
export function headerOf(questions: Questions, index: number): string {
  return questions.questions[index]?.header ?? `Question ${index + 1}`;
}

/** `claude asks you 2 questions`, or `a question` for one. */
export function askHeading(agent: string, questions: Questions): string {
  const count = questions.questions.length;

  return `${agent} asks you ${count === 1 ? 'a question' : `${count} questions`}`;
}

/** `answers itself in 4:32`: what is left of the agent's wait, if it has one. */
export function expiresIn(
  questions: Questions,
  state: AskState,
  now: number,
): number | undefined {
  return questions.expiresInMs === undefined
    ? undefined
    : Math.max(state.openedAt + questions.expiresInMs - now, 0);
}

export function clock(ms: number): string {
  const seconds = Math.ceil(ms / 1000);

  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

/**
 * A question's answer as the summary reads it: the options picked, by their
 * titles, the text typed, its own answer after ` · `, `•` for each character
 * of a secret one; none when it has no answer.
 */
export function answerText(
  question: Question,
  state: AskState,
): string | undefined {
  if (!answered(question, state)) {
    return undefined;
  }

  const { picks, text, own, ownChosen } = answerTo(state, question);
  const hide = (value: string) =>
    question.secret === true ? '•'.repeat([...value].length) : value;
  const mode = question.own?.mode;
  const ownSent = own.trim() !== '' && (mode === 'beside' || ownChosen);
  const picked =
    mode === 'instead' && ownSent
      ? []
      : picks.map(
          (value) =>
            question.options.find((option) => option.value === value)?.title ??
            value,
        );
  const main = [...picked, ...(text.trim() === '' ? [] : [hide(text.trim())])];

  if (ownSent && mode !== 'beside') {
    main.push(hide(own.trim()));
  }

  const note = ownSent && mode === 'beside' ? hide(own.trim()) : undefined;

  return [main.join(', '), note]
    .filter((part) => part !== undefined && part !== '')
    .join(' · ');
}

/** The lines of a step on screen, and the rows cut off above and below. */
export interface Window {
  readonly top: number;
  readonly end: number;
  readonly above: number;
  readonly below: number;
}

/**
 * Which of a step's lines fit `limit`, given the row each line belongs to
 * (none for the question's text and blanks): all of them where they fit,
 * else the focused row's whole, a line saying how many rows are cut off on
 * each side that has any.
 */
export function windowOf(
  rowOfLine: readonly (number | undefined)[],
  focus: number,
  limit: number,
): Window {
  const count = rowOfLine.length;

  if (count <= limit) {
    return { top: 0, end: count, above: 0, below: 0 };
  }

  const first = Math.max(rowOfLine.indexOf(focus), 0);
  const last = Math.max(rowOfLine.lastIndexOf(focus), first);
  let top = 0;
  let end = limit - 1;

  // Down from the top, keeping a line for what is below, until the
  // focused row is whole; then a line for what is above too.
  if (last >= end) {
    end = Math.min(last + 1, count);
    top = Math.max(end - (limit - (end < count ? 2 : 1)), 0);
    top = Math.min(top, first);

    // Never an option's description without its title above it.
    while (
      top < first &&
      rowOfLine[top] !== undefined &&
      rowOfLine[top] === rowOfLine[top - 1]
    ) {
      top++;
    }
  }

  const shown = new Set(rowOfLine.slice(top, end));
  const above = new Set(
    rowOfLine
      .slice(0, top)
      .filter((row) => row !== undefined && !shown.has(row)),
  ).size;
  const below = new Set(
    rowOfLine.slice(end).filter((row) => row !== undefined && !shown.has(row)),
  ).size;

  return { top, end, above, below };
}
