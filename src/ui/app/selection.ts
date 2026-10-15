/**
 * A selection in the window, which OpenTUI draws and holds: what chord
 * keeps of its lifecycle, what each fact it observes does to that, and the
 * copy, from OpenTUI's clipboard service's result to the status line's note
 * (docs/design/CHD-172.md, "The lifecycle" and "The clipboard").
 */
import type { ClipboardWriteResult } from '@opentui/core';

/**
 * Where a selection stands. While the button is down chord keeps whether
 * the view was following the bottom at the press and whether the person
 * scrolled since, which together say whether it follows again at release.
 */
export type Selection =
  | { readonly kind: 'none' }
  | {
      readonly kind: 'dragging';
      readonly wasFollowing: boolean;
      readonly moved: boolean;
    }
  | { readonly kind: 'shown' }
  | { readonly kind: 'copying' };

export const NO_SELECTION: Selection = { kind: 'none' };

/** A press on a selectable text started a drag. */
export function pressed(following: boolean): Selection {
  return { kind: 'dragging', wasFollowing: following, moved: false };
}

/** A wheel step or a scroll key while the button is down. */
export function scrolled(selection: Selection): Selection {
  return selection.kind === 'dragging'
    ? { ...selection, moved: true }
    : selection;
}

/**
 * The release, with the text OpenTUI selected: shown, or none for a click.
 * The view follows again only if it followed at the press and the person
 * did not move it since; a release with no drag seen follows nothing.
 */
export function released(
  selection: Selection,
  text: string,
): { selection: Selection; follow: boolean } {
  return {
    selection: text === '' ? NO_SELECTION : { kind: 'shown' },
    follow:
      selection.kind === 'dragging' &&
      selection.wasFollowing &&
      !selection.moved,
  };
}

/** Whether a copy may start: one at a time, and only of something shown. */
export function copyable(selection: Selection): boolean {
  return selection.kind === 'shown';
}

/** What a copy came to, as the status line says it. */
export type CopyResult =
  | { readonly kind: 'copied'; readonly chars: number }
  | { readonly kind: 'sent'; readonly chars: number }
  | { readonly kind: 'failed'; readonly reason: string };

/** The host clipboard's bound on a write, chord's own (1 s). */
export const COPY_TIMEOUT_MS = 1_000;

/**
 * How long chord waits on a copy before calling it timed out itself: the
 * host's bound and a margin, for a host or a fake that ignores its abort.
 */
export const COPY_BOUND_MS = COPY_TIMEOUT_MS + 200;

const segmenter = new Intl.Segmenter();

/** The characters a person counts: graphemes, so `é` and `👍🏽` are one. */
export function graphemes(text: string): number {
  let count = 0;

  for (const _ of segmenter.segment(text)) {
    count += 1;
  }

  return count;
}

const NO_ANSWER = 'the clipboard did not answer';
const TOO_LARGE = 'too large to copy';
const NO_CLIPBOARD = 'no clipboard to write to';

/**
 * OpenTUI's result for `text` as chord says it: the host wrote it, or only
 * OSC 52 went, which nobody can know arrived, or neither. A timed-out host
 * gets no OSC 52 from OpenTUI, and is a failure. `undefined` for a
 * cancelled write, which only chord's own abort leaves.
 */
export function copyResult(
  text: string,
  result: ClipboardWriteResult,
): CopyResult | undefined {
  const { host, terminal } = result;

  if (host.status === 'written') {
    return { kind: 'copied', chars: graphemes(text) };
  }

  if (host.status === 'cancelled') {
    return undefined;
  }

  if (host.status === 'timed-out') {
    return { kind: 'failed', reason: NO_ANSWER };
  }

  if (terminal.status === 'attempted') {
    return { kind: 'sent', chars: graphemes(text) };
  }

  return {
    kind: 'failed',
    reason: host.status === 'failed' ? oneLine(host.error) : NO_CLIPBOARD,
  };
}

/**
 * A copy that threw: the service's own bound on what it writes, which it
 * checks before writing anything, or any other error, said as it is.
 */
export function copyRejected(error: unknown): CopyResult {
  return {
    kind: 'failed',
    reason:
      error instanceof RangeError && /byte limit/.test(error.message)
        ? TOO_LARGE
        : oneLine(error),
  };
}

/** An error's message on one line, as the status line has one. */
function oneLine(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);

  return message.replace(/\s+/g, ' ').trim() || NO_CLIPBOARD;
}

/** What the status line says of a copy; a failure in the error tone. */
export function copyNote(result: CopyResult): string {
  switch (result.kind) {
    case 'copied':
      return `copied ${result.chars} chars to clipboard`;
    case 'sent':
      return `sent ${result.chars} chars to the terminal's clipboard`;
    case 'failed':
      return `could not copy: ${result.reason} · ctrl + c to try again`;
  }
}

/** The write a copy goes through: `main.tsx`'s, a test's stub otherwise. */
export type Copy = (
  text: string,
  signal: AbortSignal,
) => Promise<ClipboardWriteResult>;

/** The copies a window makes, one at a time. */
export interface Copies {
  /**
   * Copies `text`, aborting the copy in flight. Settles with what to say,
   * or `undefined` once a later copy or `dispose` superseded it, or for a
   * cancel; a copy unanswered at `COPY_BOUND_MS` is timed out.
   */
  start(text: string): Promise<CopyResult | undefined>;
  /** Supersedes and aborts the copy in flight; none starts after. */
  dispose(): void;
}

/**
 * The window's copies over `copy`. Each bumps a generation, and only the
 * latest one's result is said, within the bound, so no stale note shows.
 */
export function copies(
  copy: Copy,
  bound = COPY_BOUND_MS,
  timers: {
    set: (run: () => void, ms: number) => unknown;
    clear: (timer: unknown) => void;
  } = {
    set: (run, ms) => setTimeout(run, ms),
    clear: (timer) => clearTimeout(timer as ReturnType<typeof setTimeout>),
  },
): Copies {
  let generation = 0;
  let disposed = false;
  let inFlight: AbortController | undefined;

  return {
    async start(text) {
      if (disposed) {
        return undefined;
      }

      inFlight?.abort();

      const mine = ++generation;
      const abort = new AbortController();
      let timer: unknown;

      inFlight = abort;

      const late = new Promise<CopyResult>((resolve) => {
        timer = timers.set(
          () => resolve({ kind: 'failed', reason: NO_ANSWER }),
          bound,
        );
      });

      try {
        const result = await Promise.race([
          copy(text, abort.signal).then(
            (written) => copyResult(text, written),
            copyRejected,
          ),
          late,
        ]);

        return mine === generation && !disposed ? result : undefined;
      } finally {
        timers.clear(timer);

        if (inFlight === abort) {
          inFlight = undefined;
        }
      }
    },
    dispose() {
      disposed = true;
      generation += 1;

      inFlight?.abort();

      inFlight = undefined;
    },
  };
}
