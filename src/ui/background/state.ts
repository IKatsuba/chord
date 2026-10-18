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
  readonly backgroundView?: {
    readonly focus?: ItemRef;
    /**
     * What the hint line says in place of the keys, about the focused item's
     * stop, until the `❯` moves.
     */
    readonly hint?: string;
    /**
     * The stop `x` last asked for, by its item and a token of its own, while
     * the `❯` has stayed on that item since: only that stop's answer, if it
     * comes later, is said.
     */
    readonly stopping?: { readonly focus: ItemRef; readonly token: string };
  };
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
  | { readonly type: 'background_focused'; readonly focus: ItemRef }
  /** `x` asked to stop `focus`, which may answer later, under `token`. */
  | {
      readonly type: 'background_stop_asked';
      readonly focus: ItemRef;
      readonly token: string;
    }
  /**
   * The stop `token` asked for could not be made, as `hint` says; said only
   * while the `❯` has stayed on its item since, and no later stop was asked.
   */
  | {
      readonly type: 'background_hinted';
      readonly token: string;
      readonly hint: string;
    };

export const initialBackground: BackgroundState = { backgroundCleared: {} };

function same(a: ItemRef | undefined, b: ItemRef | undefined): boolean {
  return a !== undefined && b !== undefined && a.key === b.key && a.id === b.id;
}

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
    case 'background_focused': {
      const view = state.backgroundView;

      if (view === undefined) {
        return state;
      }

      // The hint, and a stop awaiting its answer, stay while the `❯` stays
      // on their item.
      const stays = same(view.focus, action.focus);

      return {
        ...state,
        backgroundView: {
          focus: action.focus,
          ...(stays && view.hint !== undefined ? { hint: view.hint } : {}),
          ...(view.stopping !== undefined &&
          same(view.stopping.focus, action.focus)
            ? { stopping: view.stopping }
            : {}),
        },
      };
    }
    case 'background_stop_asked': {
      const view = state.backgroundView;

      return view === undefined
        ? state
        : {
            ...state,
            backgroundView: {
              ...view,
              stopping: { focus: action.focus, token: action.token },
            },
          };
    }
    case 'background_hinted': {
      const view = state.backgroundView;

      if (view === undefined || view.stopping?.token !== action.token) {
        return state;
      }

      const { stopping: _, ...rest } = view;

      return { ...state, backgroundView: { ...rest, hint: action.hint } };
    }
  }
}
