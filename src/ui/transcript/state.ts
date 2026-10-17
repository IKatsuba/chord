/**
 * The transcript's view: where each session's is scrolled to, and whether
 * ctrl+o shows the window's thoughts and tool output in full.
 */
import {
  initialScroll,
  reduceScroll,
  type Scroll,
  type ScrollAction,
} from './scroll.ts';

/** The session's part of the view. */
export interface ViewSession {
  /** Where the transcript's view is: following the bottom or scrolled back. */
  readonly scroll: Scroll;
  /**
   * The first entry mounted while scrolled back, held as `mount.ts` says;
   * none while following, when the tail is.
   */
  readonly mounted?: number;
  /**
   * What the next measure puts on the view's top row, scrolled back there as
   * after pgup: entry `entry`, from the row of its box with id `target`
   * where one is drawn in it; none once it has, or while following.
   */
  readonly jump?: { readonly entry: number; readonly target?: string };
}

/** The window's part of the view. */
export interface ViewWindow {
  /** ctrl+o: thoughts and tool output in full rather than summarised. */
  readonly expanded: boolean;
}

export interface ViewState extends ViewSession, ViewWindow {}

export type ViewAction =
  | ScrollAction
  | { readonly type: 'expanded_toggled' }
  /**
   * The view is to scroll back so that entry `entry`, or the box with id
   * `target` in it, is its top line.
   */
  | {
      readonly type: 'jumped_to';
      readonly entry: number;
      readonly target?: string;
    }
  /** The measure put the entry asked for on top, or found it gone. */
  | { readonly type: 'jump_done' };

export const initialView: ViewState = {
  scroll: initialScroll,
  expanded: false,
};

export function reduceView(state: ViewState, action: ViewAction): ViewState {
  switch (action.type) {
    case 'expanded_toggled':
      return { ...state, expanded: !state.expanded };
    case 'jumped_to':
      return {
        ...state,
        scroll: { ...state.scroll, following: false, news: false },
        jump: {
          entry: action.entry,
          ...(action.target === undefined ? {} : { target: action.target }),
        },
      };
    case 'jump_done': {
      const { jump: _, ...rest } = state;

      return rest;
    }
    case 'scroll_measured':
    case 'scrolled':
    case 'scroll_held':
    case 'scroll_released': {
      const scroll = reduceScroll(state.scroll, action);

      if (scroll === state.scroll) {
        return state;
      }

      // Back at the bottom, nothing is left to scroll to.
      if (scroll.following && state.jump !== undefined) {
        const { jump: _, ...rest } = state;

        return { ...rest, scroll };
      }

      return { ...state, scroll };
    }
  }
}
