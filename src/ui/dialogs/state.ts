/**
 * What the agent asks the person, as the window holds it: the form being
 * filled in, and whether a permission, a form or a link waits on them.
 */
import type {
  ElicitationWait,
  Transcript,
} from '../../session/transcript/types.ts';
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
