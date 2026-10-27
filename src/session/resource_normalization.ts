/** Maps documented provider fields into source-scoped facts, never account identity. */
import { z } from '@zod/zod';
import { createHash } from 'node:crypto';
import type { UnboundObservation, WindowSnapshot } from './budgets.ts';

export interface ResourceSource {
  readonly sourceRef: string;
  readonly sessionRef: string;
  readonly receivedAt: string;
}

export type NormalizedResources =
  | { readonly observation: UnboundObservation }
  | {
      readonly unavailable: { readonly agent: string; readonly reason: string };
    };

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

const UNKNOWN_TIME = 'Provider observation time unavailable.';

/** A salted reference cannot link provider bucket IDs across source instances. */
function windowRef(source: ResourceSource, name: string): string {
  return createHash('sha256')
    .update(source.sourceRef)
    .update('\0')
    .update(name)
    .digest('hex');
}

function emptyWindow(
  source: ResourceSource,
  name: string,
  reason: string,
): WindowSnapshot {
  return {
    windowRef: windowRef(source, name),
    models: null,
    usedPercent: null,
    windowSeconds: null,
    resetsAt: null,
    observedAt: null,
    receivedAt: source.receivedAt,
    state: 'unknown',
    reason,
  };
}

function observation(
  source: ResourceSource,
  agent: 'claude' | 'codex',
  windows: WindowSnapshot[],
): NormalizedResources {
  if (
    !windows.some(
      (window) => window.usedPercent !== null || window.resetsAt !== null,
    )
  ) {
    return {
      unavailable: {
        agent,
        reason: 'The source supplied no subscription windows.',
      },
    };
  }

  return {
    observation: {
      observationRef: source.sourceRef,
      sourceRef: source.sourceRef,
      sessionRef: source.sessionRef,
      agent,
      source: agent === 'codex' ? 'codex-app-server' : 'claude-agent-sdk',
      sourceVersion: agent === 'codex' ? '0.163.0' : '0.3.311',
      observedAt: null,
      billingKind: 'subscription',
      coverage: 'account',
      externalActivity: 'unknown',
      windows,
      reason:
        'Account and resource pool identity are unverified; sources are not merged.',
    },
  };
}

export function normalizeCodex(
  account: unknown,
  limits: unknown,
  source: ResourceSource,
): NormalizedResources {
  const auth = z
    .object({ account: z.object({ type: z.literal('chatgpt') }) })
    .safeParse(account);

  if (!auth.success) {
    return {
      unavailable: {
        agent: 'codex',
        reason: 'Subscription account metadata is unavailable or unsupported.',
      },
    };
  }

  const parsed = CodexLimits.safeParse(limits);

  if (!parsed.success) {
    return {
      unavailable: { agent: 'codex', reason: 'Malformed rate-limit snapshot.' },
    };
  }

  // The map supersedes the legacy duplicate, including when the map is empty.
  const buckets =
    parsed.data.rateLimitsByLimitId === null
      ? [['legacy', parsed.data.rateLimits] as const]
      : Object.entries(parsed.data.rateLimitsByLimitId);
  const windows: WindowSnapshot[] = [];

  if (buckets.length > 64) {
    return {
      unavailable: {
        agent: 'codex',
        reason:
          'The quota map exceeds the supported snapshot bound; coverage is incomplete.',
      },
    };
  }

  for (const [id, value] of buckets) {
    const bucket = CodexBucket.safeParse(value);

    for (const name of ['primary', 'secondary'] as const) {
      const raw = bucket.success ? bucket.data[name] : undefined;
      const parsedWindow = CodexWindow.safeParse(raw);
      const base = emptyWindow(
        source,
        `${id}.${name}`,
        raw === null || raw === undefined
          ? 'Window unavailable.'
          : 'Malformed subscription window.',
      );

      if (!parsedWindow.success) {
        windows.push(base);

        continue;
      }

      const reset =
        parsedWindow.data.resetsAt === null
          ? null
          : new Date(parsedWindow.data.resetsAt * 1000);

      windows.push({
        ...base,
        usedPercent: parsedWindow.data.usedPercent,
        windowSeconds:
          parsedWindow.data.windowDurationMins === null
            ? null
            : parsedWindow.data.windowDurationMins * 60,
        resetsAt:
          reset !== null && Number.isFinite(reset.getTime())
            ? reset.toISOString()
            : null,
        reason:
          reset !== null && !Number.isFinite(reset.getTime())
            ? 'Malformed reset time; provider observation time unavailable.'
            : UNKNOWN_TIME,
      });
    }
  }

  return observation(source, 'codex', windows);
}

export function normalizeClaude(
  usage: unknown,
  source: ResourceSource,
): NormalizedResources {
  const parsed = ClaudeLimits.safeParse(usage);

  if (!parsed.success) {
    return {
      unavailable: {
        agent: 'claude',
        reason: 'Malformed experimental usage snapshot.',
      },
    };
  }

  if (!parsed.data.rate_limits_available || parsed.data.rate_limits === null) {
    return {
      unavailable: {
        agent: 'claude',
        reason:
          'Subscription limits unavailable: unsupported authentication source or missing profile scope.',
      },
    };
  }

  const windows: WindowSnapshot[] = [];
  const append = (
    name: string,
    raw: unknown,
    seconds: number,
    modelScoped: boolean,
  ) => {
    const parsedWindow = ClaudeWindow.safeParse(raw);
    const base = emptyWindow(
      source,
      name,
      raw === null || raw === undefined
        ? 'Window unavailable.'
        : 'Malformed subscription window.',
    );

    windows.push(
      parsedWindow.success
        ? {
            ...base,
            usedPercent: parsedWindow.data.utilization,
            resetsAt: parsedWindow.data.resets_at,
            windowSeconds: seconds,
            reason: modelScoped
              ? 'Model applicability and provider observation time are unknown.'
              : UNKNOWN_TIME,
          }
        : base,
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
      name !== 'five_hour' && name !== 'seven_day',
    );
  }

  const models = z
    .array(
      z.object({
        display_name: z.string().min(1),
        utilization: Percent,
        resets_at: z.iso.datetime().nullable(),
      }),
    )
    .max(123)
    .safeParse(parsed.data.rate_limits.model_scoped);

  if (models.success) {
    for (const model of models.data) {
      append(`model.${model.display_name}`, model, 604_800, true);
    }
  } else if (parsed.data.rate_limits.model_scoped !== undefined) {
    windows.push(
      emptyWindow(
        source,
        'model_scoped',
        'Model-scoped windows are malformed or exceed the supported bound; coverage is incomplete.',
      ),
    );
  }

  return observation(source, 'claude', windows);
}
