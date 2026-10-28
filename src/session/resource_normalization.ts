/** Maps documented provider fields into plain windows, never account identity. */
import { z } from '@zod/zod';
import type { ProviderLimits, ResourceWindow } from './budgets.ts';

const Percent = z.number().min(0).max(100).nullable();
const CodexWindow = z.object({
  usedPercent: Percent,
  windowDurationMins: z
    .number()
    .positive()
    .max(Number.MAX_SAFE_INTEGER / 60)
    .nullable(),
  resetsAt: z.number().int().nonnegative().nullable(),
});
const CodexBucket = z.object({
  primary: z.unknown(),
  secondary: z.unknown(),
});
const CodexLimits = z.object({
  rateLimits: z.unknown(),
  rateLimitsByLimitId: z.record(z.string(), z.unknown()).nullable(),
});
const ClaudeWindow = z.object({
  utilization: Percent,
  resets_at: z.iso.datetime().nullable(),
});
const ClaudeLimits = z.object({
  rate_limits_available: z.boolean(),
  rate_limits: z.record(z.string(), z.unknown()).nullable(),
});

/** A window the provider sent but did not fill as documented reads as unknown. */
function unknownWindow(name: string): ResourceWindow {
  return {
    name,
    usedPercent: null,
    windowSeconds: null,
    resetsAt: null,
    models: null,
  };
}

export function normalizeCodex(
  account: unknown,
  limits: unknown,
): ProviderLimits {
  const auth = z
    .object({ account: z.object({ type: z.literal('chatgpt') }) })
    .safeParse(account);

  if (!auth.success) {
    return {
      agent: 'codex',
      unavailable:
        'Subscription account metadata is unavailable or unsupported.',
    };
  }

  const parsed = CodexLimits.safeParse(limits);

  if (!parsed.success) {
    return { agent: 'codex', unavailable: 'Malformed rate-limit snapshot.' };
  }

  // The map supersedes the legacy duplicate, including when the map is empty.
  const buckets =
    parsed.data.rateLimitsByLimitId === null
      ? [[undefined, parsed.data.rateLimits] as const]
      : Object.entries(parsed.data.rateLimitsByLimitId);

  if (buckets.length > 64) {
    return {
      agent: 'codex',
      unavailable: 'The quota map exceeds the supported bound.',
    };
  }

  const windows: ResourceWindow[] = [];

  for (const [id, value] of buckets) {
    const bucket = CodexBucket.safeParse(value);

    for (const kind of ['primary', 'secondary'] as const) {
      const raw = bucket.success ? bucket.data[kind] : undefined;
      const name = id === undefined ? kind : `${id}.${kind}`;

      if (raw === null || raw === undefined) {
        continue;
      }

      const window = CodexWindow.safeParse(raw);

      if (!window.success) {
        windows.push(unknownWindow(name));

        continue;
      }

      const reset =
        window.data.resetsAt === null
          ? null
          : new Date(window.data.resetsAt * 1000);

      windows.push({
        name,
        usedPercent: window.data.usedPercent,
        windowSeconds:
          window.data.windowDurationMins === null
            ? null
            : window.data.windowDurationMins * 60,
        resetsAt:
          reset !== null && Number.isFinite(reset.getTime())
            ? reset.toISOString()
            : null,
        models: null,
      });
    }
  }

  return { agent: 'codex', windows };
}

export function normalizeClaude(usage: unknown): ProviderLimits {
  const parsed = ClaudeLimits.safeParse(usage);

  if (!parsed.success) {
    return {
      agent: 'claude',
      unavailable: 'Malformed experimental usage snapshot.',
    };
  }

  if (!parsed.data.rate_limits_available || parsed.data.rate_limits === null) {
    return {
      agent: 'claude',
      unavailable:
        'Subscription limits unavailable: unsupported authentication source or missing profile scope.',
    };
  }

  const windows: ResourceWindow[] = [];
  const append = (
    name: string,
    raw: unknown,
    seconds: number,
    models: string[] | null,
  ) => {
    if (raw === null || raw === undefined) {
      return;
    }

    const window = ClaudeWindow.safeParse(raw);

    windows.push(
      window.success
        ? {
            name,
            usedPercent: window.data.utilization,
            windowSeconds: seconds,
            resetsAt: window.data.resets_at,
            models,
          }
        : unknownWindow(name),
    );
  };

  for (const name of [
    'five_hour',
    'seven_day',
    'seven_day_oauth_apps',
    'seven_day_opus',
    'seven_day_sonnet',
  ]) {
    append(
      name,
      parsed.data.rate_limits[name],
      name === 'five_hour' ? 18_000 : 604_800,
      null,
    );
  }

  const scoped = parsed.data.rate_limits['model_scoped'];
  const models = z
    .array(
      z.object({
        display_name: z.string().min(1).max(128),
        utilization: Percent,
        resets_at: z.iso.datetime().nullable(),
      }),
    )
    .max(123)
    .safeParse(scoped);

  if (models.success) {
    for (const model of models.data) {
      append('model_scoped', model, 604_800, [model.display_name]);
    }
  } else if (scoped !== undefined && scoped !== null) {
    windows.push(unknownWindow('model_scoped'));
  }

  return { agent: 'claude', windows };
}
