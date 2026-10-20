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
 * One prompt older, with what the box should show; undefined at the oldest.
 */
export function older(
  history: History,
  draft: string,
): { history: History; text: string } | undefined {
  const index = (history.index ?? history.prompts.length) - 1;
  const text = history.prompts[index];

  if (text === undefined) {
    return undefined;
  }

  return {
    history: {
      ...history,
      index,
      draft: history.index === undefined ? draft : history.draft,
    },
    text,
  };
}

/**
 * One prompt newer, the kept draft after the newest; undefined off the walk.
 */
export function newer(
  history: History,
): { history: History; text: string } | undefined {
  if (history.index === undefined) {
    return undefined;
  }

  const index = history.index + 1;
  const text = history.prompts[index];

  if (text === undefined) {
    return {
      history: { ...history, index: undefined, draft: '' },
      text: history.draft,
    };
  }

  return { history: { ...history, index }, text };
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
