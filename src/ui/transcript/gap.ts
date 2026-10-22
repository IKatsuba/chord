/**
 * How a transcript block is set apart from the one above it: a row of
 * margin, or, inside OpenTUI's scrollbox, a row of its own, an empty box
 * before the block. A scrollbox one row tall leaves out of its
 * `scrollHeight` a margin, and padding over a box, so lines past them
 * cannot be scrolled to; a box of its own it counts (opentui#1739,
 * docs/decisions.md). The transcript keeps its margins; only a scrollbox
 * that draws blocks asks for the row.
 */
import {
  createContext,
  createElement,
  type ReactNode,
  useContext,
} from 'react';

export type BlockGap = 'margin' | 'row';

export const BlockGap = createContext<BlockGap>('margin');

/** A block's one row of space above it, as `BlockGap` has it drawn. */
export interface Gap {
  /** On the block itself: its margin, or nothing. */
  readonly props: { readonly marginTop?: 1 };
  /** Drawn before the block: the row of its own, or nothing. */
  readonly spacer: ReactNode;
}

const MARGIN: Gap = { props: { marginTop: 1 }, spacer: null };

const ROW: Gap = {
  props: {},
  spacer: createElement('box', { height: 1, flexShrink: 0 }),
};

/** The space a block puts above itself where it is drawn. */
export function useGap(): Gap {
  return useContext(BlockGap) === 'row' ? ROW : MARGIN;
}
