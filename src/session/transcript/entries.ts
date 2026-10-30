/**
 * How the reducers write a transcript's entries. Live, each write gives a new
 * array, as React needs one to see a change. Folding a resumed session's past
 * in one batch, an array the batch made is written in place: a copy for each
 * of 40,000 past actions made the fold quadratic (CHD-559, the owner's Q316).
 * An array made before the batch, which the window may hold, is copied first.
 */
import type { Entry } from './types.ts';

/** The arrays the batch running now made, which it may write in place. */
let made: WeakSet<readonly Entry[]> | undefined;

/** What `fold` returns, its entries written in place where the batch made them. */
export function inBatch<T>(fold: () => T): T {
  const outer = made;

  made = new WeakSet();

  try {
    return fold();
  } finally {
    made = outer;
  }
}

/** `entries` to write: itself where the batch made it, else a copy. */
function writable(entries: readonly Entry[]): Entry[] {
  if (made?.has(entries)) {
    return entries as Entry[];
  }

  const copy = [...entries];

  made?.add(copy);

  return copy;
}

/** `entries` with `more` after them. */
export function appended(
  entries: readonly Entry[],
  ...more: readonly Entry[]
): readonly Entry[] {
  const out = writable(entries);

  out.push(...more);

  return out;
}

/** `entries` with their last one `entry` instead. */
export function lastReplaced(
  entries: readonly Entry[],
  entry: Entry,
): readonly Entry[] {
  return replacedAt(entries, entries.length - 1, entry);
}

/** `entries` with the one at `at` `entry` instead. */
export function replacedAt(
  entries: readonly Entry[],
  at: number,
  entry: Entry,
): readonly Entry[] {
  const out = writable(entries);

  out[at] = entry;

  return out;
}
