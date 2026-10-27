/** Advisory resource facts; local receipt never establishes provider freshness. */
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

export const WindowSnapshot = z.strictObject({
  windowRef: ref,
  models: ids.nullable(),
  usedPercent: z.number().min(0).max(100).nullable(),
  windowSeconds: z.number().positive().nullable(),
  resetsAt: time.nullable(),
  observedAt: time.nullable(),
  receivedAt: time.nullable(),
  state: z.enum(['fresh', 'stale', 'unknown', 'unsupported']),
  reason: text.nullable(),
});

export type WindowSnapshot = z.infer<typeof WindowSnapshot>;

const source = {
  source: ref,
  sourceVersion: ref,
  coverage: z.enum(['account', 'chord', 'unknown']),
  externalActivity: z.enum(['visible', 'unknown']),
  windows: z.array(WindowSnapshot).max(128),
};

export const PoolSnapshot = z.strictObject({
  ...source,
  coverage: z.enum(['account', 'chord']),
  poolRef: ref,
  accountRef: ref,
  provider: ref,
  billing: z.enum(['subscription', 'api']),
  identityObservedAt: time,
  identity: z.literal('verified'),
});

export type PoolSnapshot = z.infer<typeof PoolSnapshot>;

export const UnboundObservation = z.strictObject({
  ...source,
  observationRef: ref,
  sourceRef: ref,
  sessionRef: ref,
  agent: ref,
  observedAt: time.nullable(),
  billingKind: z.enum(['subscription', 'api', 'unknown']),
  reason: text,
});

export type UnboundObservation = z.infer<typeof UnboundObservation>;

/** One role, including planned members that have not started spending. */
export const ActiveRun = z.strictObject({
  processRef: ref,
  runRef: ref,
  sessionRef: ref,
  team: ref.nullable(),
  member: ref,
  agent: ref,
  model: ref.nullable(),
  resourceRefs: ids,
  state: z.enum([
    'planned',
    'starting',
    'working',
    'idle',
    'refused',
    'ended',
    'stale',
  ]),
  lastSeenAt: time,
});

export type ActiveRun = z.infer<typeof ActiveRun>;

export const ResourceFacts = {
  pools: z.array(PoolSnapshot).max(128),
  unbound: z.array(UnboundObservation).max(128),
  unavailable: z.array(z.strictObject({ agent: ref, reason: text })).max(128),
  activeRuns: z.array(ActiveRun).max(256),
};

export const BudgetSnapshot = z.strictObject({
  schemaVersion: z.literal(1),
  observedAt: time,
  preferences: TeamSelection,
  ...ResourceFacts,
  warnings: z.array(text).max(256),
});

export type BudgetSnapshot = z.infer<typeof BudgetSnapshot>;

/** A wall/monotonic anchor prevents clock rollback from extending freshness. */
export interface BudgetClock {
  readonly wall: number;
  readonly monotonic: number;
}

export const WINDOW_FRESH_MS = 60_000;
export const READ_RECENT_MS = 180_000;
export const HISTORY_MS = 900_000;
export const HEARTBEAT_MS = 15_000;
export const ACTIVE_STALE_MS = 45_000;

/** Re-evaluates original times without redating retained values. */
export function ageWindow(
  window: WindowSnapshot,
  now: BudgetClock,
  anchor?: BudgetClock,
): WindowSnapshot {
  const mark = (state: WindowSnapshot['state'], reason: string) => ({
    ...window,
    state,
    reason,
  });

  if (window.state === 'unsupported') {
    return window;
  }

  if (
    anchor !== undefined &&
    (now.wall < anchor.wall || now.monotonic < anchor.monotonic)
  ) {
    return mark(
      'unknown',
      'Clock moved backwards; observation age is unknown.',
    );
  }

  const effective =
    anchor === undefined
      ? now.wall
      : Math.max(now.wall, anchor.wall + now.monotonic - anchor.monotonic);
  const received =
    window.receivedAt === null ? null : Date.parse(window.receivedAt);
  const observed =
    window.observedAt === null ? null : Date.parse(window.observedAt);
  const reset = window.resetsAt === null ? null : Date.parse(window.resetsAt);

  if (
    (received !== null && received > now.wall + 5000) ||
    (observed !== null && observed > now.wall + 5000)
  ) {
    return mark('unknown', 'Observation time is ahead of the local clock.');
  }

  if (reset !== null && reset <= effective) {
    return mark('stale', 'The recorded reset has passed; capacity is unknown.');
  }

  if (received !== null && effective - received >= HISTORY_MS) {
    return mark('stale', 'The original read is at least 15 minutes old.');
  }

  if (observed === null) {
    return mark(
      'unknown',
      window.reason ?? 'Provider observation time unavailable.',
    );
  }

  if (
    effective -
      Math.min(observed, received ?? now.wall, anchor?.wall ?? now.wall) >=
    WINDOW_FRESH_MS
  ) {
    return mark('stale', 'Provider observation is at least 60 seconds old.');
  }

  if (window.usedPercent === null) {
    return mark('unknown', window.reason ?? 'Utilization unavailable.');
  }

  // A refresh failure cannot become fresh merely because the clock is read.
  return window.state === 'stale' ? window : { ...window, state: 'fresh' };
}

/** Partial events replace only their named windows, never newer observations. */
export function mergeWindows(
  previous: readonly WindowSnapshot[],
  updates: readonly WindowSnapshot[],
): WindowSnapshot[] {
  const windows = new Map(previous.map((window) => [window.windowRef, window]));

  for (const update of updates) {
    const old = windows.get(update.windowRef);
    const stamp = (window: WindowSnapshot) =>
      Date.parse(window.observedAt ?? window.receivedAt ?? '') || 0;

    if (old === undefined || stamp(update) >= stamp(old)) {
      windows.set(update.windowRef, update);
    }
  }

  return [...windows.values()];
}

/** Failed reads preserve original values and times and retain an explicit reason. */
export function failedWindows(
  windows: readonly WindowSnapshot[],
  reason: string,
): WindowSnapshot[] {
  return windows.map((window) => ({
    ...window,
    state: window.observedAt === null ? 'unknown' : 'stale',
    reason,
  }));
}

export function activeAt(run: ActiveRun, now: number): ActiveRun {
  const seen = Date.parse(run.lastSeenAt);

  return run.state === 'ended' ||
    run.state === 'refused' ||
    (seen <= now + 5000 && now - seen < ACTIVE_STALE_MS)
    ? run
    : { ...run, state: 'stale' };
}
