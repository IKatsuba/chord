/**
 * The background's part of the window's state: when the person last sent a
 * prompt in each tab, which clears the tab's ended items, and the view of
 * them while it is open.
 */
import type { Transcript } from '../../session/transcript/types.ts';
import { askedIds } from '../dialogs/state.ts';
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
     * The line of all the rows' on top of the frame, for the size `laid`
     * it was laid out at (CHD-430).
     */
    readonly top?: number;
    readonly laid?: string;
    /**
     * The requests already waiting on the person as it opened, which it
     * stays over, holding the keys, as the agents list did (CHD-462).
     */
    readonly over?: readonly string[];
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
  /**
   * `enter` on the summary line opened the view over the requests `over`
   * already waiting; esc closes it.
   */
  | { readonly type: 'background_opened'; readonly over?: readonly string[] }
  | { readonly type: 'background_closed' }
  /**
   * The window took another size: the frame is found again from the `❯`,
   * a tall row from its first line (CHD-430).
   */
  | { readonly type: 'background_resized' }
  /** ↑ ↓ in the view put the `❯` on `focus`. */
  | {
      readonly type: 'background_focused';
      readonly focus: ItemRef;
      /** The line on top of the frame, at the size `laid`; kept if not given. */
      readonly top?: number;
      readonly laid?: string;
    }
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

/**
 * Whether the background view is on screen: open, and not hidden by a
 * permission or form the front tab asked since it opened, as every picker
 * is; it comes back as it was once that is answered. Those already waiting
 * as it opened it stays over, the keys its own (CHD-462).
 */
export function backgroundShown(
  state: BackgroundState & { readonly transcript: Transcript },
): boolean {
  const view = state.backgroundView;

  return (
    view !== undefined &&
    askedIds(state.transcript).every((id) => view.over?.includes(id))
  );
}

/**
 * Whether the list under the prompt has the keys: focused, and the view
 * opened from its summary line not open, which takes them while it is up
 * and hands them to what the front tab asks while it is hidden.
 */
export function agentsHaveKeys(
  state: BackgroundState & { readonly agentsFocus?: true },
): boolean {
  return state.agentsFocus === true && state.backgroundView === undefined;
}

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
      return {
        ...state,
        backgroundView:
          action.over === undefined || action.over.length === 0
            ? {}
            : { over: action.over },
      };
    case 'background_resized': {
      const view = state.backgroundView;

      if (view?.top === undefined && view?.laid === undefined) {
        return state;
      }

      const { top: _, laid: __, ...kept } = view;

      return { ...state, backgroundView: kept };
    }
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

      // Where in a tall row it is stays with the row, unless a move says.
      const at =
        action.top !== undefined
          ? { top: action.top, laid: action.laid }
          : stays
            ? { top: view.top, laid: view.laid }
            : {};

      return {
        ...state,
        backgroundView: {
          focus: action.focus,
          ...(at.top === undefined ? {} : { top: at.top }),
          ...(at.laid === undefined ? {} : { laid: at.laid }),
          ...(view.over === undefined ? {} : { over: view.over }),
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
