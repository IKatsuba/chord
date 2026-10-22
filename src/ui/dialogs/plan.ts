/**
 * The plan box, kept out of the component (docs/design/CHD-437.md): the
 * choices each agent's plan takes, the Note row sent with keep planning,
 * what each key does to them, and the hint line.
 */
import type { PlanAnswer, PlanWait } from '../../session/transcript/types.ts';
import { type AskKey, edited } from './questions.ts';

/** One choice: its words, and the answer it sends. */
export interface PlanChoice {
  readonly label: string;
  readonly answer: 'accepted' | 'kept' | 'left';
}

/** cursor's yes and no; grok's, and its way out of plan mode (3A). */
export function planChoices(agent: PlanWait['agent']): PlanChoice[] {
  return agent === 'cursor'
    ? [
        { label: 'Yes, accept the plan', answer: 'accepted' },
        { label: 'No, keep planning', answer: 'kept' },
      ]
    : [
        { label: 'Yes, start implementing', answer: 'accepted' },
        { label: 'No, keep planning', answer: 'kept' },
        { label: 'No, and leave plan mode', answer: 'left' },
      ];
}

/** The box as the person has it: the `❯`'s row, the Note row last. */
export interface PlanBoxState {
  readonly row: number;
  readonly note: string;
}

export const OPEN_PLAN_BOX: PlanBoxState = { row: 0, note: '' };

/** What a press did: the box as it now is, and the answer if one was given. */
export interface PlanStep {
  readonly state: PlanBoxState;
  readonly answer?: PlanAnswer;
}

/** The answer `choice` sends, the note going with keep planning alone. */
function answerOf(choice: PlanChoice, note: string): PlanAnswer {
  const said = note.trim();

  return choice.answer === 'kept'
    ? { type: 'kept', ...(said === '' ? {} : { note: said }) }
    : { type: choice.answer };
}

/**
 * A press in the box: ↑ ↓ or j k move, the Note row past the last choice;
 * a digit picks that choice; enter picks the one under the `❯`, or on the
 * Note row keeps planning with the note; esc keeps planning with none. On
 * the Note row, digits and j k type.
 */
export function planKey(
  agent: PlanWait['agent'],
  state: PlanBoxState,
  input: string,
  key: AskKey,
): PlanStep {
  const choices = planChoices(agent);
  const noteRow = choices.length;
  const kept = choices.find((choice) => choice.answer === 'kept')!;

  if (key.escape) {
    return { state, answer: { type: 'kept' } };
  }

  if (state.row === noteRow) {
    if (key.return) {
      return { state, answer: answerOf(kept, state.note) };
    }

    if (key.upArrow) {
      return { state: { ...state, row: noteRow - 1 } };
    }

    const note = edited(state.note, input, key);

    return note === undefined ? { state } : { state: { ...state, note } };
  }

  if (key.return) {
    return { state, answer: answerOf(choices[state.row]!, state.note) };
  }

  if (key.upArrow || input === 'k') {
    return { state: { ...state, row: Math.max(0, state.row - 1) } };
  }

  if (key.downArrow || input === 'j') {
    return { state: { ...state, row: Math.min(noteRow, state.row + 1) } };
  }

  const picked = /^[1-9]$/.test(input) ? choices[Number(input) - 1] : undefined;

  return picked === undefined
    ? { state }
    : { state, answer: answerOf(picked, state.note) };
}

/** Text pasted onto the Note row goes into the note; elsewhere it is dropped. */
export function planPaste(
  agent: PlanWait['agent'],
  state: PlanBoxState,
  text: string,
): PlanBoxState {
  return state.row === planChoices(agent).length
    ? { ...state, note: `${state.note}${text.replace(/\s+/g, ' ')}` }
    : state;
}

/** The hint under the box, on a choice or on the Note row. */
export function planHint(
  agent: PlanWait['agent'],
  state: PlanBoxState,
): string {
  const count = planChoices(agent).length;

  return state.row === count
    ? 'Enter to keep planning with this note · ↑ to the options · Esc to keep planning'
    : `Enter to pick · 1–${count} · ↑↓ to move · Esc to keep planning`;
}
