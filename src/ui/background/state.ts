/**
 * The background's part of the window's state: when the person last sent a
 * prompt in each tab, which clears the tab's ended items, and the view of
 * them while it is open.
 */
import type { ItemRef } from './view.ts';

export interface BackgroundState {
  /** By tab key: the person's last prompt there, epoch milliseconds. */
  readonly backgroundCleared: Readonly<Record<number, number>>;
  /**
   * The background view is open over the window, with the `❯` on the item
   * `focus` names, or on the first while it names none still listed.
   */
  readonly backgroundView?: { readonly focus?: ItemRef };
}

export type BackgroundAction =
  /** The person sent a prompt in tab `tab` at `at`, to any of its agents. */
  | {
      readonly type: 'background_cleared';
      readonly tab: number;
      readonly at: number;
    }
  /** `enter` on the summary line opened the view; esc closes it. */
  | { readonly type: 'background_opened' }
  | { readonly type: 'background_closed' }
  /** ↑ ↓ in the view put the `❯` on `focus`. */
  | { readonly type: 'background_focused'; readonly focus: ItemRef };

export const initialBackground: BackgroundState = { backgroundCleared: {} };

export function reduceBackground(
  state: BackgroundState,
  action: BackgroundAction,
): BackgroundState {
  switch (action.type) {
    case 'background_cleared':
      return {
        ...state,
        backgroundCleared: {
          ...state.backgroundCleared,
          [action.tab]: action.at,
        },
      };
    case 'background_opened':
      return { ...state, backgroundView: {} };
    case 'background_closed': {
      const { backgroundView: _, ...rest } = state;

      return rest;
    }
    case 'background_focused':
      return state.backgroundView === undefined
        ? state
        : { ...state, backgroundView: { focus: action.focus } };
  }
}
