/**
 * What the agent asks the person, as the window holds it: the form being
 * filled in, and whether a permission, a form or a link waits on them.
 */
import type {
  ElicitationWait,
  Transcript,
} from '../../session/transcript/types.ts';
import type { FormState } from './form.ts';

/** The session's part: a dialog's state lives with the session asking. */
export interface DialogsState {
  /**
   * The form on screen as the person has filled it so far, by the request it
   * answers, so switching away and back finds it as it was left.
   */
  readonly filling?: { readonly id: string; readonly form: FormState };
}

export type DialogsAction =
  /** A key changed the form answering the request `id`. */
  {
    readonly type: 'form_filled';
    readonly id: string;
    readonly form: FormState;
  };

export function reduceDialogs(
  state: DialogsState,
  action: DialogsAction,
): DialogsState {
  return { ...state, filling: { id: action.id, form: action.form } };
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
