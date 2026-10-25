import { createContext, useContext, useMemo } from 'react';
import type { Renderable, RGBA } from '@opentui/core';
import {
  type Action,
  DEFAULT_KEYMAP,
  hintKey,
  type Keymap,
} from '../shortcuts/bindings.ts';
import type { BlockRef } from '../transcript/code_pick.ts';
import { highlighting } from '../transcript/highlight.ts';
import type { Soft } from '../transcript/markdown.ts';
import { type Palette, paletteOf } from '../theme/theme.ts';
import { capital } from '../shortcuts/state.ts';
import { colour } from '../theme/text.ts';

/** Whether this terminal takes colour, decided once, as chalk decides it. */
export const COLOUR = highlighting();

/**
 * The palette the window is drawn in, handed down rather than passed to each
 * component, so `/theme`'s preview reaches every one at once.
 */
export const Colours = createContext<Palette>(paletteOf('dark', COLOUR));

/**
 * The palette the window drew in last, which the crash screen takes, as it
 * draws outside every `Colours` (CHD-468).
 */
export const drawnColours: { current?: Palette } = {};

export function useColours(): Palette {
  return useContext(Colours);
}

/**
 * What a `<text>` the agent or the person wrote takes on top of `TEXT`,
 * `FILL` or `CUT`: selectable, painted in the palette's `selection` role
 * where a drag covers it. A reply, a prompt, a message, a thought, a tool's
 * output, a diff's code, the header's lines and the draft take it; chord's
 * furniture does not (`theme/text.ts`'s `TEXT` says why).
 */
export function useSelectable(): {
  readonly selectable: true;
  readonly selectionBg: RGBA;
} {
  const { selection } = useColours();

  return useMemo(
    () => ({ selectable: true, selectionBg: colour(selection) }),
    [selection],
  );
}

/**
 * What a code box's buttons do, handed down to every reply (CHD-394): its
 * text copied, or its command put into the prompt in bash mode.
 */
export interface CodeActions {
  copy(text: string): void;
  prompt(command: string): void;
  /** The left button went down on the button `target`. */
  pressed(target: unknown): void;
  /**
   * The first release since that press, which it takes: whether it was on
   * `target`. Any later release, a second delivery of the same one too,
   * finds no press (CHD-394 §1).
   */
  released(target: unknown): boolean;
}

/** A code block drawn in the transcript, for `ctrl+x b` to find (CHD-394). */
export interface DrawnBlock {
  readonly ref: BlockRef;
  /** What `c` copies. */
  readonly copy: string;
  /** What `r` puts into the prompt, on an `sh` or `bash` block. */
  readonly run?: string;
  /** Its box, or the quote it is drawn in, as laid out now. */
  readonly node: () => Renderable | undefined;
}

/** Where drawn code blocks say they are there, and that they went. */
export interface CodeRegistry {
  add(block: DrawnBlock): () => void;
}

/** The window's; none where nothing picks a block, as in a test's draw. */
export const CodeBlocks = createContext<CodeRegistry | undefined>(undefined);

/** The ids a reply's code boxes and quotes are drawn with, by block. */
export const CodeIds = createContext<ReadonlyMap<Soft, string> | undefined>(
  undefined,
);

/** The window's code box actions; none where nothing answers a button. */
export const CodeBlockActions = createContext<CodeActions | undefined>(
  undefined,
);

/**
 * Which key does what, handed down as the palette is, so every hint that
 * names a key names the one bound to it.
 */
export const Keys = createContext<Keymap>(DEFAULT_KEYMAP);

/** `action`'s key as a hint names it; none when nothing is bound to it. */
export function useHintKey(action: Action): string | undefined {
  return hintKey(useContext(Keys), action);
}

/** A hint's parts, those with a key to name, joined as the hints join them. */
export function hintOf(...parts: (string | undefined)[]): string {
  return parts.filter((part) => part !== undefined).join(' · ');
}

/** `Esc to close`, or whatever key closes a list, when one does. */
export function useCloseHint(words = 'to close'): string | undefined {
  const key = useHintKey('select:cancel');

  return key === undefined ? undefined : `${capital(key)} ${words}`;
}

/**
 * The colours of the agents of the session on screen, by the names their
 * messages go under, so a `←` or `→` row is in its agent's colour; `main`
 * and `chord` take none.
 */
export const AgentColours = createContext<Readonly<Record<string, string>>>({});

/**
 * The name chord's own MCP server went to the agent by, `chord` or, beside
 * a server of the person's of that name, `chord-2`; none when it was not
 * passed. A call to it is chord's own from its first update (CHD-415).
 */
export const ChordServerName = createContext<string | undefined>(undefined);

/** The colour of the agent `name`; none for one with no colour. */
export function useAgentColour(name: string): string | undefined {
  return useContext(AgentColours)[name];
}

/** A role's colour as a `Gutter`'s `color` takes it; none for a role left unpainted. */
export function paint(colour: string | undefined): { color?: string } {
  return colour === undefined ? {} : { color: colour };
}
