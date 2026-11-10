/** Optional permission presentation shared by agents, headless clients and the window. */
import { z } from '@zod/zod';

const Review = z.object({
  outcome: z.enum(['caution', 'incomplete', 'failed']),
  reason: z.string(),
});

export type PermissionReview = z.infer<typeof Review>;

export interface PermissionPresentation {
  readonly review?: PermissionReview;
  readonly deadlineAt?: number;
}

/** Invalid optional fields never invent a review or a deadline. */
export function permissionPresentation(meta: unknown): PermissionPresentation {
  const parsed = z
    .object({
      'chord/permission': z.object({
        review: z.unknown().optional(),
        deadlineAt: z.unknown().optional(),
      }),
    })
    .safeParse(meta);

  if (!parsed.success) {
    return {};
  }

  const value = parsed.data['chord/permission'];
  const review = Review.safeParse(value.review);
  const deadline = z
    .number()
    .finite()
    .nonnegative()
    .safeParse(value.deadlineAt);

  return {
    ...(review.success ? { review: review.data } : {}),
    ...(deadline.success ? { deadlineAt: deadline.data } : {}),
  };
}
