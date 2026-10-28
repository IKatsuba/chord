/** Team selection settings and the provider limits get_budgets reads. */
import { z } from '@zod/zod';

const text = z.string().min(1).max(500);
const ref = z.string().min(1).max(128);
const time = z.iso.datetime();
const ids = z.array(ref).max(128);

/** Preferences share ordinary user/project precedence, without payment grants. */
export const TeamSelection = z.strictObject({
  intent: z.enum(['balanced', 'prefer', 'economy', 'fixed']).optional(),
  prefer: z
    .strictObject({
      agent: ref.optional(),
      model: ref.nullable().optional(),
    })
    .optional(),
  constraints: z
    .strictObject({
      agents: ids.optional(),
      models: z.record(ref, ids).optional(),
      modes: z.record(ref, ids).optional(),
    })
    .optional(),
});

export type TeamSelection = z.infer<typeof TeamSelection>;

export function mergeTeamSelection(
  previous: TeamSelection = {},
  next: TeamSelection = {},
): TeamSelection {
  return {
    ...previous,
    ...next,
    ...(previous.prefer === undefined && next.prefer === undefined
      ? {}
      : {
          prefer: { ...previous.prefer, ...next.prefer },
        }),
    ...(previous.constraints === undefined && next.constraints === undefined
      ? {}
      : {
          constraints: {
            ...previous.constraints,
            ...next.constraints,
            ...(previous.constraints?.models === undefined &&
            next.constraints?.models === undefined
              ? {}
              : {
                  models: {
                    ...previous.constraints?.models,
                    ...next.constraints?.models,
                  },
                }),
            ...(previous.constraints?.modes === undefined &&
            next.constraints?.modes === undefined
              ? {}
              : {
                  modes: {
                    ...previous.constraints?.modes,
                    ...next.constraints?.modes,
                  },
                }),
          },
        }),
  };
}

/** One provider window as the provider names it; null is what it did not say. */
export const ResourceWindow = z.strictObject({
  name: ref,
  usedPercent: z.number().min(0).max(100).nullable(),
  windowSeconds: z.number().positive().nullable(),
  resetsAt: time.nullable(),
  models: ids.nullable(),
});

export type ResourceWindow = z.infer<typeof ResourceWindow>;

/** A provider's windows, or why they could not be read. */
export const ProviderLimits = z.union([
  z.strictObject({
    agent: ref,
    windows: z.array(ResourceWindow).max(256),
  }),
  z.strictObject({ agent: ref, unavailable: text }),
]);

export type ProviderLimits = z.infer<typeof ProviderLimits>;

/** What get_budgets answers: each provider read when it was called. */
export const Budgets = z.strictObject({
  readAt: time,
  providers: z.array(ProviderLimits).max(128),
});

export type Budgets = z.infer<typeof Budgets>;
