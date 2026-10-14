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
}

/** The window's part of the view. */
export interface ViewWindow {
  /** ctrl+o: thoughts and tool output in full rather than summarised. */
  readonly expanded: boolean;
}

export interface ViewState extends ViewSession, ViewWindow {}

export type ViewAction = ScrollAction | { readonly type: 'expanded_toggled' };

export const initialView: ViewState = {
  scroll: initialScroll,
  expanded: false,
};

export function reduceView(state: ViewState, action: ViewAction): ViewState {
  switch (action.type) {
    case 'expanded_toggled':
      return { ...state, expanded: !state.expanded };
    case 'scroll_measured':
    case 'scrolled': {
      const scroll = reduceScroll(state.scroll, action);

      return scroll === state.scroll ? state : { ...state, scroll };
    }
  }
}
