/** Per-turn review authority: an exact call is reviewed at most once. */
import { createHash } from 'node:crypto';
import { reviewInput, type ReviewEvidence } from './input.ts';
import type { ReviewOutcome } from './review.ts';

export type AutoReview =
  ReviewOutcome | { readonly outcome: 'incomplete'; readonly reason: string };

export class ReviewTurn {
  private cache = new Map<string, Promise<AutoReview>>();
  private reviews = 0;

  constructor(
    private readonly send: (
      input: string,
      signal: AbortSignal,
    ) => Promise<ReviewOutcome>,
  ) {}

  /** Include normalized targets/pre-image as well as the exact tool arguments. */
  run(
    arguments_: unknown,
    evidence: ReviewEvidence,
    signal: AbortSignal,
  ): Promise<AutoReview> {
    signal.throwIfAborted();

    const key = createHash('sha256')
      .update(
        JSON.stringify({ action: evidence.action, arguments: arguments_ }),
      )
      .digest('hex');
    const cached = this.cache.get(key);

    if (cached !== undefined) {
      return cached;
    }

    if (this.reviews >= 64) {
      return Promise.resolve({
        outcome: 'incomplete',
        reason: 'The turn reached its limit of 64 safety reviews.',
      });
    }

    const input = reviewInput(evidence);

    if (input.outcome === 'incomplete') {
      const result = Promise.resolve(input);

      this.cache.set(key, result);

      return result;
    }

    this.reviews++;

    const result = this.send(input.text, signal);

    this.cache.set(key, result);

    return result;
  }
}
