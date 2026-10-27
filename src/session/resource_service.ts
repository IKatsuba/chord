/** Shared advisory reads: relevance owns collectors, never a scheduler of agent work. */
import { performance } from 'node:perf_hooks';
import { randomUUID } from 'node:crypto';
import { settledWithin } from '../acp/process.ts';
import {
  CACHE_RETENTION_MS,
  type BudgetCacheFile,
  foldBudgetCache,
} from '../platform/budget_cache.ts';
import { ResourceReadError } from '../platform/resource_process.ts';
import {
  type ActiveRun,
  ageWindow,
  type BudgetClock,
  type BudgetSnapshot,
  failedWindows,
  HEARTBEAT_MS,
  HISTORY_MS,
  mergeWindows,
  type TeamSelection,
  UnboundObservation,
} from './budgets.ts';
import type { NormalizedResources } from './resource_normalization.ts';

export type ResourceRetry = 'configuration' | 'transient';

export interface ResourceRead {
  readonly facts: NormalizedResources;
  readonly retry?: ResourceRetry;
  readonly retryAfterMs?: number;
}

/** An internal configuration key and collector; no path enters the public facts. */
export interface ResourceTarget {
  readonly key: string;
  readonly agent: string;
  read(signal: AbortSignal): Promise<ResourceRead>;
}

export interface ResourceStorage {
  read(
    startup: boolean,
  ): Promise<{ files: BudgetCacheFile[]; warnings: string[] }>;
  write(file: BudgetCacheFile): Promise<void>;
  close(now: number): Promise<void>;
}

export interface ResourceServiceOptions {
  readonly processRef?: string;
  readonly storage?: ResourceStorage;
  readonly now?: () => BudgetClock;
  readonly every?: (callback: () => void, milliseconds: number) => () => void;
}

interface Consumer {
  readonly valid: () => boolean;
  release(): void;
}

interface Flight {
  readonly abort: AbortController;
  readonly deadline: ReturnType<typeof setTimeout>;
  promise: Promise<void>;
  invalidated: boolean;
  timedOut: boolean;
}

interface SourceState {
  readonly target: ResourceTarget;
  readonly consumers: Set<Consumer>;
  observation: UnboundObservation | undefined;
  unavailable: { agent: string; reason: string } | undefined;
  flight: Flight | undefined;
  failures: number;
  nextAt: number;
  permanent: boolean;
}

const CADENCE_MS = 120_000;
const DEADLINE_MS = 20_000;
const BACKOFF_MS = [120_000, 240_000, 480_000, 900_000] as const;
const nowClock = (): BudgetClock => ({
  wall: Date.now(),
  monotonic: performance.now(),
});

function every(callback: () => void, milliseconds: number): () => void {
  const timer = setInterval(callback, milliseconds);

  timer.unref();

  return () => clearInterval(timer);
}

/** The immediate read path performs no I/O, prompt, provider start or refresh. */
export class ResourceService {
  readonly processRef: string;
  readonly #options: ResourceServiceOptions;
  readonly #now: () => BudgetClock;
  readonly #sources = new Map<string, SourceState>();
  readonly #anchors = new Map<string, { clock: BudgetClock; epoch: number }>();
  #epoch = 0;
  #lastClock: BudgetClock | undefined;
  #files: BudgetCacheFile[] = [];
  #warnings: string[] = [];
  #cacheWarnings: string[] = [];
  #active: ActiveRun[] = [];
  #stopTimer: (() => void) | undefined;
  #closed = false;
  #started = false;
  #readingCache = false;
  #writing: Promise<void> | undefined;
  #dirty = false;

  constructor(options: ResourceServiceOptions = {}) {
    this.#options = options;
    this.processRef = options.processRef ?? randomUUID();
    this.#now = options.now ?? nowClock;
  }

  async start(): Promise<void> {
    if (this.#started || this.#closed) {
      return;
    }

    this.#started = true;

    await this.#readCache(true);

    if (!this.#closed && this.#stopTimer === undefined) {
      this.#stopTimer = (this.#options.every ?? every)(
        () => this.tick(),
        HEARTBEAT_MS,
      );
    }
  }

  retain(
    target: ResourceTarget,
    signal: AbortSignal,
    valid: () => boolean = () => true,
  ): () => void {
    if (this.#closed || signal.aborted || !valid()) {
      return () => {};
    }

    let source = this.#sources.get(target.key);

    if (source === undefined) {
      if (this.#sources.size >= 128) {
        this.#warn('Resource coverage is incomplete: source limit reached.');

        return () => {};
      }

      source = {
        target,
        consumers: new Set(),
        failures: 0,
        nextAt: 0,
        permanent: false,
        observation: undefined,
        unavailable: undefined,
        flight: undefined,
      };

      this.#sources.set(target.key, source);
    } else if (source.consumers.size === 0) {
      // A new session/configuration may make a previously unsupported source usable.
      source.permanent = false;
    }

    const state = source;
    const consumer: Consumer = {
      valid,
      release: () => {
        signal.removeEventListener('abort', consumer.release);
        state.consumers.delete(consumer);

        if (!this.#live(state) && state.flight !== undefined) {
          state.flight.invalidated = true;

          clearTimeout(state.flight.deadline);
          state.flight.abort.abort();
        }
      },
    };

    state.consumers.add(consumer);
    signal.addEventListener('abort', consumer.release, { once: true });
    this.#refresh(state);

    return consumer.release;
  }

  active(runs: readonly ActiveRun[]): void {
    if (runs.length > 256) {
      this.#warn('Active-work coverage is incomplete: role limit reached.');
    }

    this.#active = runs
      .slice(0, 256)
      .map((run) => ({ ...run, resourceRefs: [...run.resourceRefs] }));
  }

  tick(): void {
    if (this.#closed) {
      return;
    }

    for (const source of this.#sources.values()) {
      for (const consumer of source.consumers) {
        if (!consumer.valid()) {
          consumer.release();
        }
      }

      this.#refresh(source);
    }

    void this.#readCache(false);

    this.#active = this.#active.map((run) => ({
      ...run,
      lastSeenAt: new Date(this.#now().wall).toISOString(),
    }));

    this.#persist();
  }

  read(preferences: TeamSelection = {}): BudgetSnapshot {
    const now = this.#now();

    if (
      this.#lastClock !== undefined &&
      (now.wall < this.#lastClock.wall ||
        now.monotonic < this.#lastClock.monotonic)
    ) {
      this.#epoch++;
    }

    this.#lastClock = now;

    const touched = new Set<string>();
    const historical = new Set<string>();
    const result = foldBudgetCache(
      [
        ...this.#files.filter(
          (file) =>
            file.processRef !== this.processRef &&
            now.wall - Date.parse(file.writtenAt) <= CACHE_RETENTION_MS,
        ),
        this.#file(now),
      ],
      preferences,
      now,
      [...new Set([...this.#warnings, ...this.#cacheWarnings])],
      (window, key) => {
        const identity = JSON.stringify([
          key,
          window.windowRef,
          window.observedAt,
          window.receivedAt,
        ]);
        const anchor = this.#anchors.get(identity) ?? {
          clock: now,
          epoch: this.#epoch,
        };

        if (!this.#anchors.has(identity) && this.#anchors.size >= 32768) {
          this.#warn(
            'Resource coverage is incomplete: freshness anchor limit reached.',
          );

          return {
            ...window,
            state: 'unknown',
            reason: 'Freshness tracking limit reached; capacity unknown.',
          };
        }

        this.#anchors.set(identity, anchor);
        touched.add(identity);

        if (
          window.receivedAt !== null &&
          Math.max(
            now.wall,
            anchor.clock.wall + now.monotonic - anchor.clock.monotonic,
          ) -
            Date.parse(window.receivedAt) >=
            HISTORY_MS
        ) {
          historical.add(
            JSON.stringify([
              window.windowRef,
              window.observedAt,
              window.receivedAt,
            ]),
          );
        }

        return anchor.epoch !== this.#epoch && window.state !== 'unsupported'
          ? {
              ...window,
              state: 'unknown',
              reason: 'Clock moved backwards; refresh required.',
            }
          : ageWindow(window, now, anchor.clock);
      },
    );

    // Keep anchors across a transient cache-file gap, including future-skew clamps.
    for (const [key, anchor] of this.#anchors) {
      if (
        !touched.has(key) &&
        Math.max(
          now.wall - anchor.clock.wall,
          now.monotonic - anchor.clock.monotonic,
        ) >= HISTORY_MS
      ) {
        this.#anchors.delete(key);
      }
    }

    for (const source of this.#sources.values()) {
      if (
        source.observation === undefined &&
        source.unavailable === undefined
      ) {
        result.unavailable.push({
          agent: source.target.agent,
          reason:
            source.flight !== undefined &&
            !source.flight.invalidated &&
            !source.flight.abort.signal.aborted
              ? 'Quota read pending; capacity unknown.'
              : 'Quota unavailable; capacity unknown.',
        });
      } else if (
        source.observation !== undefined &&
        source.observation.windows.every(
          (window) =>
            window.receivedAt === null ||
            historical.has(
              JSON.stringify([
                window.windowRef,
                window.observedAt,
                window.receivedAt,
              ]),
            ) ||
            (window.resetsAt !== null &&
              Date.parse(window.resetsAt) <= now.wall),
        )
      ) {
        result.unavailable.push({
          agent: source.target.agent,
          reason: 'Retained quota is historical; current capacity unknown.',
        });
      }
    }

    if (result.unavailable.length > 128) {
      result.unavailable = result.unavailable.slice(0, 128);
      result.warnings = [
        ...result.warnings.slice(0, 255),
        'Resource coverage is incomplete: unavailable-source output limit reached.',
      ];
    }

    result.warnings = [
      ...new Set([...result.warnings, ...this.#warnings]),
    ].slice(0, 256);

    return result;
  }

  async close(): Promise<void> {
    this.#closed = true;

    this.#stopTimer?.();

    const pending: Promise<void>[] = [];

    for (const source of this.#sources.values()) {
      for (const consumer of source.consumers) {
        consumer.release();
      }

      if (source.flight !== undefined) {
        source.flight.invalidated = true;

        clearTimeout(source.flight.deadline);
        source.flight.abort.abort();
        pending.push(source.flight.promise);
      }
    }

    const settled = await settledWithin(Promise.all(pending), 2000);

    if (settled === undefined) {
      this.#warn(
        'Collector shutdown could not be verified within its cleanup bound.',
      );
    }

    await this.#writing;
    await this.#options.storage?.close(this.#now().wall);
  }

  #live(source: SourceState): boolean {
    return [...source.consumers].some((consumer) => consumer.valid());
  }

  #refresh(source: SourceState): void {
    const now = this.#now();

    if (
      this.#closed ||
      source.flight !== undefined ||
      source.permanent ||
      !this.#live(source) ||
      now.monotonic < source.nextAt
    ) {
      return;
    }

    const abort = new AbortController();

    source.nextAt = now.monotonic + CADENCE_MS;

    const deadline = setTimeout(() => {
      flight.timedOut = true;

      abort.abort(
        new ResourceReadError(
          'timeout',
          'Resource acquisition exceeded its deadline.',
        ),
      );

      if (!flight.invalidated && !this.#closed && this.#live(source)) {
        this.#failure(
          source,
          'Resource acquisition exceeded its deadline.',
          'transient',
        );
        this.#persist();
      }
    }, DEADLINE_MS);
    const flight: Flight = {
      abort,
      deadline,
      invalidated: false,
      timedOut: false,
      promise: Promise.resolve(),
    };
    const promise = Promise.resolve()
      .then(() => {
        abort.signal.throwIfAborted();

        return source.target.read(abort.signal);
      })
      .then(
        (read) => {
          if (
            flight.invalidated ||
            abort.signal.aborted ||
            this.#closed ||
            !this.#live(source)
          ) {
            return;
          }

          if ('observation' in read.facts) {
            const parsed = UnboundObservation.safeParse(read.facts.observation);

            if (!parsed.success) {
              this.#failure(
                source,
                'Resource collector returned incomplete or unsupported facts.',
                'transient',
              );
              this.#persist();

              return;
            }

            const incoming = parsed.data;
            const previous = source.observation;
            const updates = incoming.windows.filter(
              (window) =>
                window.usedPercent !== null ||
                window.resetsAt !== null ||
                !previous?.windows.some(
                  (old) => old.windowRef === window.windowRef,
                ),
            );
            const merged = mergeWindows(previous?.windows ?? [], updates);

            if (merged.length > 128) {
              this.#warn(
                'Resource coverage is incomplete: window limit reached.',
              );
            }

            const windows = merged.slice(0, 128);

            source.observation = {
              ...incoming,
              windows,
              reason: windows.some((window) => !updates.includes(window))
                ? 'Partial update; omitted windows retain original times. Identity unverified.'
                : incoming.reason,
            };
            source.unavailable = undefined;
            source.failures = 0;
            source.nextAt = this.#now().monotonic + CADENCE_MS;

            this.read();
          } else {
            this.#failure(
              source,
              read.facts.unavailable.reason,
              read.retry ?? 'transient',
              read.retryAfterMs,
            );
          }

          this.#persist();
        },
        (error: unknown) => {
          if (
            !flight.invalidated &&
            !flight.timedOut &&
            !this.#closed &&
            this.#live(source)
          ) {
            this.#failure(
              source,
              error instanceof ResourceReadError
                ? error.message
                : 'Resource collector failed.',
              error instanceof ResourceReadError &&
                error.kind === 'authentication'
                ? 'configuration'
                : 'transient',
            );
            this.#persist();
          }
        },
      )
      .finally(() => {
        clearTimeout(deadline);

        if (source.flight === flight) {
          source.flight = undefined;
        }
      });

    flight.promise = promise;
    source.flight = flight;
  }

  #failure(
    source: SourceState,
    reason: string,
    retry: ResourceRetry,
    retryAfterMs?: number,
  ): void {
    source.failures++;

    source.permanent = retry === 'configuration';
    source.nextAt =
      this.#now().monotonic +
      Math.max(
        BACKOFF_MS[Math.min(source.failures - 1, 3)]!,
        retryAfterMs !== undefined &&
          Number.isFinite(retryAfterMs) &&
          retryAfterMs > 0
          ? retryAfterMs
          : 0,
      );

    if (source.observation === undefined) {
      source.unavailable = { agent: source.target.agent, reason };
    } else {
      source.observation = {
        ...source.observation,
        reason,
        windows: failedWindows(source.observation.windows, reason),
      };
    }
  }

  #file(now: BudgetClock): BudgetCacheFile {
    return {
      schemaVersion: 1,
      processRef: this.processRef,
      writtenAt: new Date(now.wall).toISOString(),
      pools: [],
      unbound: [...this.#sources.values()].flatMap((source) =>
        source.observation === undefined ? [] : [source.observation],
      ),
      unavailable: [...this.#sources.values()].flatMap((source) =>
        source.unavailable === undefined ? [] : [source.unavailable],
      ),
      activeRuns: this.#active,
    };
  }

  async #readCache(startup: boolean): Promise<void> {
    if (this.#readingCache || this.#options.storage === undefined) {
      return;
    }

    this.#readingCache = true;

    try {
      const cached = await this.#options.storage.read(startup);

      if (this.#closed) {
        return;
      }

      this.#files = cached.files;
      this.#cacheWarnings = cached.warnings;

      this.read();
    } catch {
      this.#cacheWarnings = [
        'Resource cache coverage is incomplete: cache read failed.',
      ];
    } finally {
      this.#readingCache = false;
    }
  }

  #persist(): void {
    const storage = this.#options.storage;

    if (storage === undefined || this.#closed) {
      return;
    }

    this.#dirty = true;

    if (this.#writing !== undefined) {
      return;
    }

    this.#writing = (async () => {
      while (this.#dirty && !this.#closed) {
        this.#dirty = false;

        try {
          await storage.write(this.#file(this.#now()));

          this.#warnings = this.#warnings.filter(
            (warning) =>
              warning !==
              'Resource cache coverage is incomplete: cache write failed.',
          );
        } catch {
          this.#warn(
            'Resource cache coverage is incomplete: cache write failed.',
          );
        }
      }
    })().finally(() => {
      this.#writing = undefined;
    });
  }

  #warn(reason: string): void {
    this.#warnings = [...new Set([...this.#warnings, reason])].slice(0, 256);
  }
}
