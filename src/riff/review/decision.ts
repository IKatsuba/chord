/** The only authority a review model can return is one bounded verdict. */
import { z } from '@zod/zod';
import { bytePrefix } from './input.ts';

export type ReviewDecision =
  | { readonly outcome: 'clear' }
  | { readonly outcome: 'caution'; readonly rationale: string };

const Decision = z.object({
  decision: z.enum(['clear', 'caution']),
  rationale: z.string().optional(),
});

/** Unknown fields grant no authority; malformed decisions grant none either. */
export function reviewDecision(value: unknown): ReviewDecision | undefined {
  const parsed = Decision.safeParse(value);

  if (!parsed.success) {
    return undefined;
  }

  return parsed.data.decision === 'clear'
    ? { outcome: 'clear' }
    : {
        outcome: 'caution',
        rationale: bytePrefix(parsed.data.rationale ?? '', 240),
      };
}
