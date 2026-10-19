/**
 * What the agent asks the person, as the window holds it: the form being
 * filled in, and whether a permission, a form or a link waits on them.
 */
import type {
  ElicitationWait,
  Transcript,
} from '../../session/transcript/types.ts';
import { askedPermission } from './permission.ts';
import { hintKey, type Keymap } from '../shortcuts/bindings.ts';
import type { FormState } from './form.ts';
import type { AskState } from './questions.ts';

/** The session's part: a dialog's state lives with the session asking. */
export interface DialogsState {
  /**
   * The form on screen as the person has filled it so far, by the request it
   * answers, so switching away and back finds it as it was left.
   */
  readonly filling?: { readonly id: string; readonly form: FormState };
  /** The question box as the person has answered it so far, the same way. */
  readonly answering?: { readonly id: string; readonly state: AskState };
  /**
   * The permission request, by id, whose request runs past the box's room,
   * so the scroll keys move it rather than the transcript (CHD-246).
   */
  readonly overflowing?: string;
  /**
   * The request, by id, asked between turns that the person has taken the
   * keys into with `ctrl+x a` (CHD-158).
   */
  readonly attended?: string;
}

export type DialogsAction =
  /** A key changed the form answering the request `id`. */
  | {
      readonly type: 'form_filled';
      readonly id: string;
      readonly form: FormState;
    }
  /** A key changed the question box answering the request `id`. */
  | {
      readonly type: 'questions_answered';
      readonly id: string;
      readonly state: AskState;
    }
  /** The person took the keys into the request `id` asked between turns. */
  | { readonly type: 'request_attended'; readonly id: string }
  /** The permission box laid out request `id`, which `overflows` or fits. */
  | {
      readonly type: 'request_overflowed';
      readonly id: string;
      readonly overflows: boolean;
    };

export function reduceDialogs(
  state: DialogsState,
  action: DialogsAction,
): DialogsState {
  switch (action.type) {
    case 'form_filled':
      return { ...state, filling: { id: action.id, form: action.form } };
    case 'questions_answered':
      return { ...state, answering: { id: action.id, state: action.state } };
    case 'request_attended':
      return { ...state, attended: action.id };
    case 'request_overflowed': {
      if (action.overflows) {
        return state.overflowing === action.id
          ? state
          : { ...state, overflowing: action.id };
      }

      if (state.overflowing !== action.id) {
        return state;
      }

      const { overflowing: _, ...left } = state;

      return left;
    }
  }
}

/**
 * Whether the turn waits on the person: a permission asked, or a form or
 * link. Either takes the place of every picker and list until it is answered.
 */
export function asksPerson(transcript: Transcript): boolean {
  return (
    transcript.turn.status === 'awaiting_permission' ||
    transcript.asking.length > 0
  );
}

/** The ids of every permission and form the transcript asks the person. */
export function askedIds(transcript: Transcript): string[] {
  const { turn } = transcript;

  return [
    ...(turn.status === 'awaiting_permission'
      ? turn.permissions.map((wait) => wait.id)
      : []),
    ...transcript.asking.map((wait) => wait.id),
  ];
}

/**
 * The form or link on screen: the oldest the turn asks for, once no
 * permission is asked, as that prompt answers first.
 */
export function askedInput(
  transcript: Transcript,
): ElicitationWait | undefined {
  return transcript.turn.status === 'awaiting_permission'
    ? undefined
    : transcript.asking[0];
}

/**
 * The id of the request on screen when it came with no turn of chord's
 * running: a permission while the session waits between turns, or a form or
 * link asked so, or a task's with no turn in flight (CHD-158).
 */
export function betweenAsked(transcript: Transcript): string | undefined {
  const { turn } = transcript;
  const permission = askedPermission(turn);

  if (permission !== undefined) {
    return turn.status === 'awaiting_permission' && turn.between === true
      ? permission.id
      : undefined;
  }

  const input = askedInput(transcript);
  const outside =
    turn.status === 'idle' ||
    (turn.status === 'awaiting_permission' && turn.between === true);

  return input !== undefined &&
    (input.between === true || (input.subagentId !== undefined && outside))
    ? input.id
    : undefined;
}

/** What decides whether a request is held: the session's and the keys. */
type Holding = DialogsState & {
  readonly transcript: Transcript;
  readonly keys: Keymap;
};

/**
 * Whether the request on screen came between turns and the person has not
 * taken the keys into it: drawn without them, the prompt keeping its draft
 * and its keys, so a key typed for the prompt never answers it. With no key
 * to take them in, `session:attention` unbound, it has them at once, as in
 * a turn.
 */
export function heldBack(state: Holding): boolean {
  const id = betweenAsked(state.transcript);

  return (
    id !== undefined &&
    id !== state.attended &&
    hintKey(state.keys, 'session:attention') !== undefined
  );
}

/**
 * Whether a permission, form or link on screen has the keys: asked in a
 * turn, or between turns once the person took the keys into it.
 */
export function asksWithKeys(state: Holding): boolean {
  return asksPerson(state.transcript) && !heldBack(state);
}
