/**
 * React's log of the error chord's crash boundary caught, kept off the
 * window (the owner's Q82). OpenTUI's root hands React `console.error` as
 * its caught-error callback, which writes over the crash screen; the
 * console's overlay and a repaint could not stop it (`docs/decisions.md`).
 */

/** The errors the boundary caught whose one log from React is still to come. */
const caught = new Set<unknown>();

/** Marks `error`, which the crash boundary caught, so React's log of it is dropped. */
export function caughtByBoundary(error: unknown): void {
  caught.add(error);
}

/**
 * `log` but for the one call per caught error whose first argument is that
 * error, as React's `onCaughtError(error, info)` makes: every other call,
 * a later one of the same error among them, goes to `log` unchanged.
 */
export function quietCaught(
  log: (...data: unknown[]) => void,
): (...data: unknown[]) => void {
  return (...data) => {
    if (data.length > 0 && caught.delete(data[0])) {
      return;
    }

    log(...data);
  };
}
