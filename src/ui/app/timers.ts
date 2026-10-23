/**
 * What runs out on its own: an armed quit or close, the status line's note
 * of a copy, which leaves the selection it copied standing, and a chord's
 * first keys waiting for the next.
 */
import { type Dispatch, useEffect } from 'react';
import { CHORD_WAIT_MS } from '../shortcuts/bindings.ts';
import {
  type AppState,
  COPIED_NOTE_MS,
  QUIT_WINDOW_MS,
  type WindowedAction,
} from './state.ts';

/** Calls `lapse` once `ms` have gone, unless `armed` changes first. */
function useLapse(armed: unknown, ms: number, lapse: () => void): void {
  useEffect(() => {
    if (armed === undefined || armed === false) {
      return;
    }

    const timer = setTimeout(lapse, ms);

    return () => clearTimeout(timer);
  }, [armed]);
}

export function useTimers(
  state: AppState,
  dispatch: Dispatch<WindowedAction>,
): void {
  useLapse(state.quitArmed, QUIT_WINDOW_MS, () =>
    dispatch({ type: 'quit_disarmed' }),
  );

  const copied = state.copied;

  // A failure stays until a key clears the selection it would copy again.
  useLapse(
    copied?.result.kind === 'failed' ? undefined : copied?.id,
    COPIED_NOTE_MS,
    () =>
      copied !== undefined && dispatch({ type: 'copied_gone', id: copied.id }),
  );
  useLapse(state.agentCloseArmed, QUIT_WINDOW_MS, () =>
    dispatch({ type: 'agent_close_disarmed' }),
  );
  // A chord's first keys wait this long for the next, as in Claude Code.
  useLapse(state.pendingKeys, CHORD_WAIT_MS, () =>
    dispatch({ type: 'keys_pending' }),
  );
}
