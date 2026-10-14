/** The states and key presses the state tests start from. */
import {
  type AppAction,
  type AppState,
  initialAppState,
  reduceApp,
} from '../../../src/ui/app/state.ts';

export function after(...actions: AppAction[]): AppState {
  return actions.reduce(reduceApp, initialAppState);
}

export const ready = after({ type: 'connected', sessionId: 'session-1' });
export const busy = reduceApp(ready, {
  type: 'prompt',
  turnId: 't1',
  text: 'hi',
  at: 0,
});
export const plain = { ctrl: false, escape: false };
export const ctrl = { ctrl: true, escape: false };
export const escape = { ctrl: false, escape: true };
