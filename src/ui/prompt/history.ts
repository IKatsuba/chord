import type { PastedImage } from './images.ts';

/**
 * The prompts sent this session, walked with ↑ and ↓ as a shell walks its
 * history: ↑ from a fresh draft keeps that draft aside, and ↓ past the newest
 * prompt brings it back.
 */
export interface History {
  /** Oldest first. */
  readonly prompts: readonly string[];
  /** Which prompt the box shows, or undefined while it shows the draft. */
  readonly index: number | undefined;
  /** What the box held when the walk began. */
  readonly draft: string;
  /**
   * The images a prompt sent, by its text, so a recalled prompt brings them
   * back with its placeholders.
   */
  readonly images?: Readonly<Record<string, readonly PastedImage[]>>;
}

export const emptyHistory: History = {
  prompts: [],
  index: undefined,
  draft: '',
};

/** A prompt was sent; the walk ends, and a repeat is not kept twice. */
export function recorded(history: History, prompt: string): History {
  return recordedWith(history, prompt, []);
}

/** A prompt was sent with `images`, which come back when it is recalled. */
export function recordedWith(
  history: History,
  prompt: string,
  images: readonly PastedImage[],
): History {
  const { prompts } = history;
  const kept = { ...history.images };

  if (images.length > 0) {
    kept[prompt] = images;
  } else {
    delete kept[prompt];
  }

  return {
    prompts: prompts.at(-1) === prompt ? prompts : [...prompts, prompt],
    index: undefined,
    draft: '',
    ...(Object.keys(kept).length > 0 ? { images: kept } : {}),
  };
}

/** The images `prompt` took when it was sent; none for most. */
export function recalledImages(
  history: History,
  prompt: string,
): readonly PastedImage[] {
  return history.images?.[prompt] ?? [];
}

/**
 * The box took a prompt some other way, a search's match: the walk ends, as
 * after sending, and ↑ starts again from the newest.
 */
export function left(history: History): History {
  return history.index === undefined
    ? history
    : { ...history, index: undefined, draft: '' };
}

/**
 * A step of the walk: the box shows `text`, which is the agent's kept draft
 * `kept` when it is one, else a prompt sent or the draft the walk began on.
 */
export interface Walked {
  readonly history: History;
  readonly text: string;
  readonly kept?: number;
}

/**
 * Where the walk stands among the prompts and then `kept`, the agent's own
 * drafts set aside, oldest first (U10): past them is the box's draft. The
 * walk is the window's and the drafts an agent's, so a walk begun on an
 * agent with more of them stands at the draft on one with fewer.
 */
function standing(history: History, kept: number): number {
  const end = history.prompts.length + kept;

  return Math.min(history.index ?? end, end);
}

/** What the walk shows at `index`, among the prompts and `kept`. */
function at(
  history: History,
  index: number,
  kept: readonly string[],
): { text: string; kept?: number } | undefined {
  const prompt = history.prompts[index];

  if (prompt !== undefined) {
    return { text: prompt };
  }

  const own = index - history.prompts.length;
  const text = kept[own];

  return text === undefined ? undefined : { text, kept: own };
}

/**
 * One step older, the agent's newest kept draft first, with what the box
 * should show; undefined at the oldest prompt.
 */
export function older(
  history: History,
  draft: string,
  kept: readonly string[] = [],
): Walked | undefined {
  const index = standing(history, kept.length) - 1;
  const shown = at(history, index, kept);

  if (shown === undefined) {
    return undefined;
  }

  return {
    history: {
      ...history,
      index,
      draft: history.index === undefined ? draft : history.draft,
    },
    ...shown,
  };
}

/**
 * One step newer: a newer prompt, or the agent's next kept draft, or after
 * them the draft the walk began on; undefined off the walk.
 */
export function newer(
  history: History,
  kept: readonly string[] = [],
): Walked | undefined {
  if (history.index === undefined) {
    return undefined;
  }

  const index = standing(history, kept.length) + 1;
  const shown = at(history, index, kept);

  if (shown === undefined) {
    return {
      history: { ...history, index: undefined, draft: '' },
      text: history.draft,
    };
  }

  return { history: { ...history, index }, ...shown };
}

/**
 * Whether the box shows a recalled prompt untouched. Then ↑ and ↓ walk on from
 * any line, as they do in Claude Code; once it is edited they move the cursor
 * again, and walk only from the first or the last line.
 */
export function walking(history: History, draft: string): boolean {
  return (
    history.index !== undefined && history.prompts[history.index] === draft
  );
}
