/**
 * A reply's code block picked through the leader, `ctrl+x b`
 * (docs/design/CHD-394.md §3): which block is picked, and where ↑ and ↓
 * take the pick. The window draws the picked box and hands its keys here.
 */

import {
  type Action,
  type Keymap,
  keysOf,
  sequencePanel,
} from '../shortcuts/bindings.ts';
import stringWidth from 'string-width';
import stripAnsi from 'strip-ansi';
import type { Entry } from '../../session/transcript/types.ts';
import {
  codeBlocks,
  codePlaces,
  openFences,
  runCommand,
  type Soft,
} from './markdown.ts';

/** A code block where it is drawn: the text it is in, then its place there. */
export interface BlockRef {
  /** The reply, message or tool text it is in, by the number its drawing took. */
  readonly entry: number;
  /** Its place among the reply's code blocks, as `codeBlocks` numbers it. */
  readonly block: number;
}

/** The block picked; none while no pick is on. */
export type CodePick = BlockRef | undefined;

export type CodePickAction =
  /**
   * `ctrl+x b`, with every block in the order drawn and those on screen:
   * the newest on screen is picked, or else the newest of all.
   */
  | {
      readonly type: 'code_pick_started';
      readonly blocks: readonly BlockRef[];
      readonly shown: readonly BlockRef[];
    }
  /** ↑ or ↓: the block above or below, in the order drawn. */
  | {
      readonly type: 'code_pick_moved';
      readonly by: -1 | 1;
      readonly blocks: readonly BlockRef[];
    }
  /** c, r, esc or any other key: the pick is over. */
  | { readonly type: 'code_pick_ended' };

export function reduceCodePick(
  state: CodePick,
  action: CodePickAction,
): CodePick {
  switch (action.type) {
    case 'code_pick_started':
      return (
        newest(action.blocks, action.shown) ??
        newest(action.blocks, action.blocks)
      );
    case 'code_pick_moved': {
      if (state === undefined) {
        return undefined;
      }

      const at = action.blocks.findIndex((ref) => same(ref, state));

      // The block gone, as its reply was cleared, the pick goes to the newest.
      if (at === -1) {
        return action.blocks.at(-1);
      }

      // At either end it stays, as the agents list's pick does.
      return action.blocks[
        Math.min(Math.max(at + action.by, 0), action.blocks.length - 1)
      ];
    }
    case 'code_pick_ended':
      return undefined;
  }
}

/** The last of `blocks` that is among `among`; none when none is. */
function newest(
  blocks: readonly BlockRef[],
  among: readonly BlockRef[],
): BlockRef | undefined {
  return blocks.findLast((ref) => among.some((other) => same(ref, other)));
}

/** Whether two refs name the same block. */
export function same(a: BlockRef, b: BlockRef): boolean {
  return a.entry === b.entry && a.block === b.block;
}

/**
 * The ids a reply's code boxes and quotes are drawn with, the reply being
 * `entry`, and, by each block's `codeBlocks` index, the id of what it is
 * drawn in: its own box, or the quote whose text holds it. `soft` is the
 * reply as `softMarkdown` laid it out, and `places` as `codePlaces` says.
 */
export function drawnIds(
  soft: readonly Soft[],
  places: {
    readonly boxes: readonly number[];
    readonly quotes: readonly (readonly number[])[];
  },
  entry: number,
): {
  readonly ids: ReadonlyMap<Soft, string>;
  readonly nodes: readonly string[];
} {
  const ids = new Map<Soft, string>();
  const nodes: string[] = [];
  let box = 0;
  let quote = 0;
  const walk = (blocks: readonly Soft[]) => {
    for (const block of blocks) {
      if (block.kind === 'list') {
        for (const item of block.items) {
          walk(item.blocks);
        }
      } else if (block.kind === 'code') {
        const index = places.boxes[box++];

        if (index !== undefined) {
          const id = `code-${entry}-${index}`;

          ids.set(block, id);

          nodes[index] = id;
        }
      } else if (block.kind === 'quote') {
        const held = places.quotes[quote] ?? [];
        const id = `quote-${entry}-${quote++}`;

        ids.set(block, id);

        for (const index of held) {
          nodes[index] = id;
        }
      }
    }
  };

  walk(soft);

  return { ids, nodes };
}

/**
 * A code block found only while it is drawn, where it is: the transcript
 * entry it is drawn in, none outside the transcript, and its screen place.
 */
export interface Drawn {
  readonly ref: BlockRef;
  readonly at: number | undefined;
  readonly top: number;
  readonly left: number;
}

/**
 * Every block the pick reaches, in one transcript order for ↑ and ↓: the
 * listed ones by entry and place, each drawn-only one in its entry's place
 * after that entry's listed ones, top to bottom, those drawn outside the
 * transcript last (CHD-394 §3).
 */
export function inOrder(
  listed: readonly BlockRef[],
  drawn: readonly Drawn[],
): BlockRef[] {
  const keyed = [
    ...listed.map((ref) => ({ ref, keys: [ref.entry, 0, ref.block, 0] })),
    ...drawn.map(({ ref, at, top, left }) => ({
      ref,
      keys: [at ?? Number.POSITIVE_INFINITY, 1, top, left],
    })),
  ];

  return keyed
    .sort((a, b) => {
      for (let at = 0; at < a.keys.length; at++) {
        const by = a.keys[at]! - b.keys[at]!;

        if (by !== 0) {
          return by;
        }
      }

      return 0;
    })
    .map(({ ref }) => ref);
}

/** Whether a block placed so has a row in `view`, the transcript's rows on screen. */
export function inView(
  at: { readonly top: number; readonly height: number },
  view: { readonly top: number; readonly height: number },
): boolean {
  return at.top < view.top + view.height && at.top + at.height > view.top;
}

/**
 * The status line while a block is picked: the keys that do something to
 * it, named as the shortcuts panel names them, `r` only on a block with
 * `[run]` (docs/design/CHD-394.md §3). An action with no key bound is left
 * out.
 */
export function pickHint(
  keymap: Keymap,
  run: boolean,
  width = Number.POSITIVE_INFINITY,
): string {
  const key = (action: Action) => {
    const [first] = keysOf(keymap, action);

    return first === undefined ? undefined : sequencePanel(first);
  };

  const up = key('codeBlock:previous');
  const down = key('codeBlock:next');
  const moves = [up, down].filter((name) => name !== undefined).join(' ');
  // Each item's keys, its words, and its short words for a narrow line.
  const parts: [string | undefined, string, string][] = [
    [moves === '' ? undefined : moves, 'another block', 'block'],
    [key('codeBlock:copy'), 'copy', 'copy'],
    [run ? key('codeBlock:prompt') : undefined, 'put in the prompt', 'prompt'],
    [key('codeBlock:cancel'), 'done', 'done'],
  ];
  const items = (short: boolean) =>
    parts.flatMap(([keys, words, brief]) =>
      keys === undefined ? [] : [`${keys} ${short ? brief : words}`],
    );
  const line = (shown: readonly string[]) => shown.join(' · ');
  const full = line(items(false));

  if (stringWidth(full) <= width) {
    return full;
  }

  // Short words, then whole items dropped from the end, never one cut
  // through, and never none (docs/design/CHD-394.md §3).
  const short = items(true);

  while (short.length > 1 && stringWidth(line(short)) > width) {
    short.pop();
  }

  return line(short);
}

/**
 * Whether a block placed so is whole in `view`, every row of it, so the
 * view need not move to show it once picked (CHD-394 §3).
 */
export function wholeInView(
  at: { readonly top: number; readonly height: number },
  view: { readonly top: number; readonly height: number },
): boolean {
  return at.top >= view.top && at.top + at.height <= view.top + view.height;
}

/** A code block the transcript holds, mounted or not (CHD-394 §3). */
export interface ListedBlock {
  readonly ref: BlockRef;
  /** What `c` copies. */
  readonly copy: string;
  /** What `r` puts into the prompt, on an `sh` or `bash` block. */
  readonly run?: string;
  /** The id of what it is drawn in, its box or its quote, to jump to. */
  readonly node: string;
}

/**
 * The text of an entry whose code blocks are listed from the transcript,
 * whether or not it is mounted: an assistant's reply, and a message, but a
 * monitor's; none for any other. Code drawn elsewhere, as an expanded tool
 * summary or the plan box, is found only while it is drawn (the lead's
 * choice on CHD-394).
 */
export function listedText(entry: Entry): string | undefined {
  return entry.kind === 'assistant' ||
    (entry.kind === 'message' && entry.from.monitor === undefined)
    ? stripAnsi(entry.text)
    : undefined;
}

/**
 * Every listed code block of `entries`, in transcript order, each named by
 * its entry's index and its place among the entry's blocks; a block whose
 * fence is still open is not one yet.
 */
export function listedBlocks(entries: readonly Entry[]): ListedBlock[] {
  return entries.flatMap((entry, at) => {
    const text = listedText(entry);

    if (text === undefined) {
      return [];
    }

    const open = openFences(text);
    const { boxes, quotes } = codePlaces(text);

    return codeBlocks(text).flatMap((block): ListedBlock[] => {
      if (open.has(block.index)) {
        return [];
      }

      const quote = quotes.findIndex((held) => held.includes(block.index));

      return [
        {
          ref: { entry: at, block: block.index },
          copy: block.text,
          ...(block.runnable ? { run: runCommand(block.text) } : {}),
          node: boxes.includes(block.index)
            ? `code-${at}-${block.index}`
            : `quote-${at}-${quote}`,
        },
      ];
    });
  });
}

/**
 * The blocks the pick reaches now, in `inOrder`'s order, and those shown:
 * every listed block, mounted or not, shown while a row of it is in the
 * transcript's `view`; a drawn-only one only while it is seen, in `view`
 * where it is drawn in the transcript, on the window's `screen` where it is
 * drawn outside it, as the plan box (CHD-394 §3, "What can be picked").
 */
export function pickableBlocks(
  listed: readonly {
    readonly ref: BlockRef;
    readonly at?: { readonly top: number; readonly height: number };
  }[],
  drawn: readonly (Drawn & { readonly height: number })[],
  view: { readonly top: number; readonly height: number },
  screen: { readonly top: number; readonly height: number },
): { readonly blocks: BlockRef[]; readonly shown: BlockRef[] } {
  const seen = drawn.filter((block) =>
    inView(block, block.at === undefined ? screen : view),
  );
  const blocks = inOrder(
    listed.map(({ ref }) => ref),
    seen,
  );
  const visible = [
    ...listed.flatMap(({ ref, at }) =>
      at !== undefined && inView(at, view) ? [ref] : [],
    ),
    ...seen.map(({ ref }) => ref),
  ];

  return {
    blocks,
    shown: blocks.filter((ref) => visible.some((other) => same(ref, other))),
  };
}
