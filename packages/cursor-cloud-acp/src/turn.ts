/**
 * One prompt's run (CHD-622, "Cancel, one turn, one run"): it sends, draws
 * what the run streams, and answers once. A cancel before `send()` gives a
 * run is held for it; one during the run asks Cursor to stop, keeps drawing
 * until the run ends or the bound passes, then answers `cancelled`. Anything
 * late from a run whose prompt has answered is dropped, so one turn never
 * ends or cancels the next. The stream lost ends the turn with the link.
 */
import type { ModelSelection, SDKArtifact, SendOptions } from '@cursor/sdk';
import type {
  PromptResponse,
  SessionUpdate,
} from '@agentclientprotocol/sdk/unstable';
import { RequestError } from '@agentclientprotocol/sdk';
import { CursorError, INTERNAL_ERROR, lost } from './errors.ts';
import type { PortRun } from './port.ts';
import {
  Drawing,
  line,
  link,
  runEnd,
  unconfirmedStop,
  usage,
} from './updates.ts';

/** How long Cursor has to confirm a stop. */
export const CANCEL_BOUND_MS = 10_000;

/** What one turn reaches. */
export interface TurnContext {
  readonly agentId: string;
  /** The agent's `send` with the prompt and every option but `onDelta`. */
  readonly send: (
    onDelta: NonNullable<SendOptions['onDelta']>,
  ) => Promise<PortRun>;
  readonly artifacts: () => Promise<readonly Pick<SDKArtifact, 'path'>[]>;
  /** One update to the client, awaited, so its backpressure holds. */
  readonly emit: (update: SessionUpdate) => Promise<void>;
  /** The model the run used, as the SDK reports it. */
  readonly ran?: (model: ModelSelection) => void;
  readonly bound?: number;
}

export class Turn {
  readonly #context: TurnContext;
  readonly #drawing: Drawing;
  #run: PortRun | undefined;
  #cancelled = false;
  #answered = false;
  /** Settles the turn with `cancelled` once the bound passes. */
  #stopped: (() => void) | undefined;
  /** Settles once the turn is cancelled. */
  readonly #cancelling: Promise<'cancelled'>;
  #timer: ReturnType<typeof setTimeout> | undefined;
  #onCancel: () => void = () => undefined;

  constructor(context: TurnContext) {
    this.#context = context;
    this.#drawing = new Drawing(context.agentId);
    this.#cancelling = new Promise((resolve) => {
      this.#onCancel = () => resolve('cancelled');
    });
  }

  /** Draws `updates` unless the turn has answered. */
  async #draw(updates: readonly SessionUpdate[]): Promise<void> {
    for (const update of updates) {
      if (this.#answered) {
        return;
      }

      await this.#context.emit(update);
    }
  }

  /** Runs the prompt to its one answer; a failure rejects with a RequestError or CursorError. */
  async run(): Promise<PromptResponse> {
    try {
      return await this.#turn();
    } finally {
      this.#answered = true;

      // The bound runs until the turn has answered, not until the run ends.
      clearTimeout(this.#timer);
    }
  }

  async #turn(): Promise<PromptResponse> {
    const run = await this.#context.send(({ update }) =>
      this.#draw(this.#drawing.delta(update)),
    );

    this.#run = run;

    const stop = new Promise<'stopped'>((resolve) => {
      this.#stopped = () => resolve('stopped');
    });

    if (this.#cancelled) {
      this.#cancel(run);
    }

    const waited = run.wait().then((result) => ({ result }));
    const read = this.#read(run);
    const first = await Promise.race([waited, read, stop]);
    // The stream ended first: the answer is still wait()'s.
    const outcome =
      first !== 'stopped' && 'ended' in first
        ? await Promise.race([waited, stop])
        : first;

    if (outcome === 'stopped') {
      return this.#unconfirmed();
    }

    if ('lost' in outcome) {
      throw lost(outcome.lost, link(this.#context.agentId));
    }

    if ('failed' in outcome) {
      throw outcome.failed;
    }

    // The run ended first: what its stream still holds is drawn before the
    // turn answers, as the SDK's stream ends with its run. A cancel meanwhile
    // answers at once: the run has already ended.
    if (first === outcome) {
      const drained = await Promise.race([read, stop, this.#cancelling]);

      if (drained === 'stopped') {
        return this.#unconfirmed();
      }

      if (drained === 'cancelled') {
        return { stopReason: 'cancelled' };
      }

      if ('lost' in drained) {
        throw lost(drained.lost, link(this.#context.agentId));
      }

      if ('failed' in drained) {
        throw drained.failed;
      }
    }

    const { result } = outcome;

    if (result.model !== undefined) {
      this.#context.ran?.(result.model);
    }

    const tokens =
      result.usage === undefined ? {} : { usage: usage(result.usage) };

    if (result.status === 'cancelled' || this.#cancelled) {
      return { stopReason: 'cancelled', ...tokens };
    }

    if (result.status === 'error') {
      throw new RequestError(
        INTERNAL_ERROR,
        result.error?.message ?? 'The run failed.',
        result.error?.code === undefined
          ? undefined
          : { code: result.error.code },
      );
    }

    // A cancel while the artifacts are asked for still answers at once.
    const artifacts = await Promise.race([
      this.#context.artifacts(),
      this.#cancelling,
    ]);

    if (artifacts === 'cancelled' || this.#cancelled) {
      return { stopReason: 'cancelled', ...tokens };
    }

    await this.#draw(runEnd(result, artifacts).map((text) => line(text)));

    return this.#cancelled
      ? { stopReason: 'cancelled', ...tokens }
      : { stopReason: 'end_turn', ...tokens };
  }

  /** A stop Cursor did not confirm within the bound. */
  async #unconfirmed(): Promise<PromptResponse> {
    await this.#draw([line(unconfirmedStop(this.#context.agentId))]);

    return { stopReason: 'cancelled' };
  }

  /**
   * Draws the run's stream until it ends or the turn answers: `ended`, or
   * how it failed, `lost` when its connection to Cursor went.
   */
  async #read(
    run: PortRun,
  ): Promise<
    | { readonly ended: true }
    | { readonly lost: CursorError }
    | { readonly failed: unknown }
  > {
    try {
      for await (const message of run.stream()) {
        if (this.#answered) {
          break;
        }

        await this.#draw(this.#drawing.message(message));
      }
    } catch (error) {
      return error instanceof CursorError && error.kind === 'network'
        ? { lost: error }
        : { failed: error };
    }

    return { ended: true };
  }

  /** Stops the run: at once when it exists, else once `send()` gives it. */
  cancel(): void {
    if (this.#cancelled || this.#answered) {
      return;
    }

    this.#cancelled = true;

    this.#onCancel();

    if (this.#run !== undefined) {
      this.#cancel(this.#run);
    }
  }

  #cancel(run: PortRun): void {
    this.#timer = setTimeout(
      () => this.#stopped?.(),
      this.#context.bound ?? CANCEL_BOUND_MS,
    );

    run.cancel().catch(() => this.#stopped?.());
  }
}
