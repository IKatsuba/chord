/** Attempt bounds around libfx's own provider retries. */
import type { ReviewDecision } from './decision.ts';

export type ReviewOutcome =
  ReviewDecision | { readonly outcome: 'unavailable'; readonly reason: string };

export type ReviewAttempt = (
  input: string,
  signal: AbortSignal,
) => Promise<ReviewDecision | undefined>;

export const REVIEW_TIMEOUT_MS = 30_000;

/** A caution is final; transport and format failures each receive one retry. */
export async function review(
  attempt: ReviewAttempt,
  input: string,
  signal: AbortSignal,
): Promise<ReviewOutcome> {
  let transportRetried = false;
  let formatRetried = false;

  for (;;) {
    signal.throwIfAborted();

    const deadline = new AbortController();
    const timeout = setTimeout(
      () => deadline.abort(new Error('the reviewer did not answer in 30 s')),
      REVIEW_TIMEOUT_MS,
    );
    const active = AbortSignal.any([signal, deadline.signal]);

    try {
      // The attempt owns its engine through close. Abort requests teardown;
      // retrying or returning before it settles would abandon that engine.
      const decision = await attempt(input, active);

      active.throwIfAborted();

      if (decision !== undefined) {
        return decision;
      }

      if (formatRetried) {
        return {
          outcome: 'unavailable',
          reason: 'the reviewer returned an invalid decision',
        };
      }

      formatRetried = true;
    } catch (error) {
      signal.throwIfAborted();

      if (transportRetried) {
        return {
          outcome: 'unavailable',
          reason: error instanceof Error ? error.message : String(error),
        };
      }

      transportRetried = true;
    } finally {
      clearTimeout(timeout);
    }
  }
}
