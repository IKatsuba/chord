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
import { CursorError, INTERNAL_ERROR, lostConnection } from './errors.ts';
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

  constructor(context: TurnContext) {
    this.#context = context;
    this.#drawing = new Drawing(context.agentId);
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

    const lost = this.#read(run);
    const outcome = await Promise.race([run.wait(), stop, lost]);

    if (outcome === 'stopped') {
      await this.#draw([line(unconfirmedStop(this.#context.agentId))]);

      return { stopReason: 'cancelled' };
    }

    if (typeof outcome === 'object' && 'failed' in outcome) {
      throw outcome.failed;
    }

    if (outcome === 'lost') {
      throw new RequestError(
        INTERNAL_ERROR,
        lostConnection(link(this.#context.agentId)),
      );
    }

    if (outcome.model !== undefined) {
      this.#context.ran?.(outcome.model);
    }

    const tokens =
      outcome.usage === undefined ? {} : { usage: usage(outcome.usage) };

    if (outcome.status === 'cancelled' || this.#cancelled) {
      return { stopReason: 'cancelled', ...tokens };
    }

    if (outcome.status === 'error') {
      throw new RequestError(
        INTERNAL_ERROR,
        outcome.error?.message ?? 'The run failed.',
      );
    }

    await this.#draw(
      runEnd(outcome, await this.#context.artifacts()).map((text) =>
        line(text),
      ),
    );

    return { stopReason: 'end_turn', ...tokens };
  }

  /**
   * Draws the run's stream until the turn answers. Settles only when the
   * stream fails: `lost` when its connection to Cursor goes, the error
   * otherwise; a stream that simply ends leaves the answer to `wait()`.
   */
  async #read(run: PortRun): Promise<'lost' | { readonly failed: unknown }> {
    try {
      for await (const message of run.stream()) {
        if (this.#answered) {
          break;
        }

        await this.#draw(this.#drawing.message(message));
      }
    } catch (error) {
      return error instanceof CursorError && error.kind === 'network'
        ? 'lost'
        : { failed: error };
    }

    return new Promise<never>(() => undefined);
  }

  /** Stops the run: at once when it exists, else once `send()` gives it. */
  cancel(): void {
    if (this.#cancelled || this.#answered) {
      return;
    }

    this.#cancelled = true;

    if (this.#run !== undefined) {
      this.#cancel(this.#run);
    }
  }

  #cancel(run: PortRun): void {
    const timer = setTimeout(
      () => this.#stopped?.(),
      this.#context.bound ?? CANCEL_BOUND_MS,
    );

    run.cancel().catch(() => this.#stopped?.());
    void run
      .wait()
      .finally(() => clearTimeout(timer))
      .catch(() => undefined);
  }
}
