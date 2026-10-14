/**
 * The models, efforts and modes each runtime offers, as `list_agents` answers
 * them. ACP gives them only in a session's answer, so for a
 * runtime with no session open one is opened for the purpose, read and
 * closed, within a bound, and its answer kept for the window.
 */
import type { AgentEfforts } from '../session/efforts.ts';
import type { AgentModels } from '../session/models.ts';
import type { AgentModes } from '../session/modes.ts';
import { openSession } from '../session/session.ts';
import type { RuntimeOffer } from './tools.ts';

/** How long a runtime gets to start and answer `session/new`. */
export const PROBE_MS = 60_000;

/** What a session of a runtime said it offers. */
export interface Offered {
  readonly models: AgentModels | undefined;
  readonly modes: AgentModes | undefined;
  /** The efforts of the model the session is on. */
  readonly efforts: AgentEfforts | undefined;
}

/**
 * Opens a session of `runtime`, reads what it offers and closes it;
 * the signal gives up on one still starting.
 */
export type Probe = (runtime: string, signal: AbortSignal) => Promise<Offered>;

export interface RuntimesOptions {
  readonly probe: Probe;
  readonly bound?: number;
}

/** The runtimes' offers read so far in one window, and those being read. */
export class Runtimes {
  readonly #probe: Probe;
  readonly #bound: number;
  /** Only what was read: a runtime that failed is tried again when asked. */
  readonly #known = new Map<string, RuntimeOffer>();
  readonly #reading = new Map<string, Promise<RuntimeOffer>>();
  readonly #stop = new AbortController();

  constructor({ probe, bound = PROBE_MS }: RuntimesOptions) {
    this.#probe = probe;
    this.#bound = bound;
  }

  /**
   * Keeps what an open session of `runtime` said it offers, once it has said
   * anything: one still starting leaves the runtime to be read.
   */
  heard(runtime: string, offered: Offered): void {
    const offer = offerOf(offered);

    if (offer !== undefined) {
      this.#known.set(runtime, offer);
    }
  }

  /**
   * `runtime`'s offer as last read, or, with `probe`, read now if it was
   * never read; one read at a time for each runtime.
   */
  read(runtime: string, probe: boolean): Promise<RuntimeOffer | undefined> {
    const known = this.#known.get(runtime);

    if (known !== undefined || !probe) {
      return Promise.resolve(known);
    }

    const reading = this.#reading.get(runtime) ?? this.#read(runtime);

    this.#reading.set(runtime, reading);

    return reading;
  }

  /** Gives up on every read still under way, which close their sessions. */
  close(): void {
    this.#stop.abort(new Error('chord is closing'));
  }

  async #read(runtime: string): Promise<RuntimeOffer> {
    const timeout = AbortSignal.timeout(this.#bound);
    const signal = AbortSignal.any([this.#stop.signal, timeout]);

    try {
      const read = offerOf(await this.#probe(runtime, signal)) ?? {
        error: 'it offers no models or modes',
      };

      this.#known.set(runtime, read);

      return read;
    } catch (error) {
      return {
        error: timeout.aborted
          ? `it did not open a session within ${this.#bound / 1000} s`
          : messageOf(error),
      };
    } finally {
      this.#reading.delete(runtime);
    }
  }
}

function offerOf({
  models,
  modes,
  efforts,
}: Offered): RuntimeOffer | undefined {
  if (models === undefined && modes === undefined && efforts === undefined) {
    return undefined;
  }

  const current = models?.current;
  // On the model they were read for, as each model has its own; beside the
  // models only for an agent that names none.
  const onModel =
    efforts !== undefined &&
    models?.available.some((model) => model.id === current) === true;

  return {
    models: (models?.available ?? []).map((model) =>
      onModel && model.id === current
        ? { ...model, efforts: efforts.available, effort: efforts.current }
        : model,
    ),
    current,
    ...(modes === undefined
      ? {}
      : { modes: modes.available, currentMode: modes.current }),
    ...(efforts === undefined || onModel
      ? {}
      : { efforts: efforts.available, currentEffort: efforts.current }),
  };
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * Reads what a runtime offers from a session of its own in `cwd`,
 * started as `commandOf` says or as the registry does, with no MCP servers:
 * it is closed as soon as it has answered.
 */
export function sessionProbe(
  cwd: string,
  commandOf: (runtime: string) => string | string[] | undefined,
): Probe {
  return async (runtime, signal) => {
    const agentCommand = commandOf(runtime);
    const session = await openSession({
      agent: runtime,
      cwd,
      signal,
      ...(agentCommand === undefined ? {} : { agentCommand }),
    });

    try {
      return {
        models: session.models(),
        modes: session.modes(),
        efforts: session.efforts(),
      };
    } finally {
      await session.close();
    }
  };
}
