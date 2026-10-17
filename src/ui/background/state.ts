/**
 * The background's part of the window's state: when the person last sent a
 * prompt in each tab, which clears the tab's ended items.
 */

export interface BackgroundState {
  /** By tab key: the person's last prompt there, epoch milliseconds. */
  readonly backgroundCleared: Readonly<Record<number, number>>;
}

export type BackgroundAction =
  /** The person sent a prompt in tab `tab` at `at`, to any of its agents. */
  {
    readonly type: 'background_cleared';
    readonly tab: number;
    readonly at: number;
  };

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
  }
}
