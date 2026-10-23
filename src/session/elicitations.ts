import type {
  CreateElicitationRequest,
  CreateElicitationResponse,
  ElicitationContentValue,
  ElicitationSchema,
} from '@agentclientprotocol/sdk';
import { questionsOf } from './questions.ts';
import type { ElicitationWait } from './transcript/types.ts';

/**
 * The answers chord gives a form or link: ACP's three, without the open-ended
 * actions its type leaves room for.
 */
export type ElicitationReply =
  | {
      readonly action: 'accept';
      readonly content?: Readonly<Record<string, ElicitationContentValue>>;
    }
  | { readonly action: 'decline' }
  | { readonly action: 'cancel' };

/**
 * An elicitation the agent is waiting on, held until the person answers.
 * The transport asks through a handler that must return a response; the
 * interface answers whenever a key is pressed, so the handler parks here
 * until then.
 */
export interface PendingElicitation {
  readonly id: string;
  readonly wait: ElicitationWait;
  /** The session that asks: the agent's own, or one of its subagents'. */
  readonly sessionId?: string;
  /**
   * Aborts when the request stops mattering — the turn was cancelled or ended,
   * or the session closed — so the interface takes the form off the screen.
   */
  readonly signal: AbortSignal;
  /** Answers it: `accept` with the values, `decline`, or `cancel`. */
  answer(response: ElicitationReply): void;
}

/**
 * What the transcript keeps of a request: everything the form draws. A mode
 * chord does not draw never gets here, as the transport answers it first.
 */
export function waitOf(
  id: string,
  request: CreateElicitationRequest,
): ElicitationWait {
  const toolCallId =
    'toolCallId' in request && typeof request.toolCallId === 'string'
      ? request.toolCallId
      : undefined;
  const common = {
    id,
    message: request.message,
    ...(toolCallId === undefined ? {} : { toolCallId }),
  };

  if (request.mode === 'url' && typeof request.url === 'string') {
    return { ...common, mode: 'url', url: request.url };
  }

  const schema =
    'requestedSchema' in request
      ? (request.requestedSchema as ElicitationSchema)
      : {};

  const questions = questionsOf(request);

  return {
    ...common,
    mode: 'form',
    schema,
    ...(questions === undefined ? {} : { questions }),
  };
}

/** Bridges the transport's elicitation handler to an interface that answers later. */
export class ElicitationBridge {
  #listeners = new Set<(request: PendingElicitation) => void>();
  #closed = new AbortController();
  #linkUnheard = false;

  /**
   * Whether chord answered a link `cancel` because nobody was there to ask:
   * an agent that asks its sign-in link while a session opens, as droid
   * does, then fails the start for it (CHD-435).
   */
  get linkUnheard(): boolean {
    return this.#linkUnheard;
  }

  /**
   * The handler the transport calls; pass it as `openAgent`'s
   * `onElicitation`. Its signal aborts once the answer stops mattering.
   */
  readonly handler = (
    request: CreateElicitationRequest,
    withdrawn: AbortSignal,
  ): Promise<CreateElicitationResponse> => {
    const signal = AbortSignal.any([withdrawn, this.#closed.signal]);

    return new Promise<CreateElicitationResponse>((settle) => {
      let answered = false;
      const answer = (response: ElicitationReply) => {
        if (answered) {
          return;
        }

        answered = true;

        signal.removeEventListener('abort', onAbort);
        settle(response);
      };

      const onAbort = () => answer({ action: 'cancel' });
      const id = crypto.randomUUID();
      const pending: PendingElicitation = {
        id,
        wait: waitOf(id, request),
        ...('sessionId' in request && typeof request.sessionId === 'string'
          ? { sessionId: request.sessionId }
          : {}),
        signal,
        answer,
      };

      if (signal.aborted) {
        return onAbort();
      }

      signal.addEventListener('abort', onAbort, { once: true });

      // Nobody on screen to ask: the agent hears `cancel` rather than wait.
      if (this.#listeners.size === 0) {
        this.#linkUnheard ||= request.mode === 'url';

        return onAbort();
      }

      for (const listener of this.#listeners) {
        listener(pending);
      }
    });
  };

  /** Calls `listener` for each new request; returns the unsubscribe. */
  subscribe(listener: (request: PendingElicitation) => void): () => void {
    this.#listeners.add(listener);

    return () => this.#listeners.delete(listener);
  }

  /** Cancels every waiting request; the session is going away. */
  close(): void {
    this.#closed.abort();
    this.#listeners.clear();
  }
}
