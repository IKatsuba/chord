/**
 * An agent's plan put to the person (docs/design/CHD-437.md): the request
 * `src/acp/plans.ts` reads, held until the person answers, and their answer
 * written back in the agent's own words; `cancelled` for every answer that
 * is not the person's, never a yes.
 */
import {
  PLAN_CANCELLED,
  type PlanAgent,
  type PlanRequest,
  type PlanResponse,
} from '../acp/plans.ts';
import type { PlanAnswer, PlanWait } from './transcript/types.ts';

/** The person's answer in `agent`'s words; a note goes only with keep. */
export function planResponse(
  agent: PlanAgent,
  answer: PlanAnswer,
): PlanResponse {
  switch (answer.type) {
    case 'accepted':
      return { outcome: agent === 'cursor' ? 'accepted' : 'approved' };
    case 'kept':
      return agent === 'cursor'
        ? {
            outcome: 'rejected',
            ...(answer.note === undefined ? {} : { reason: answer.note }),
          }
        : {
            outcome: 'revise',
            ...(answer.note === undefined ? {} : { feedback: answer.note }),
          };
    case 'left':
      // Only grok takes it; cursor's box never offers it.
      return agent === 'grok' ? { outcome: 'abandoned' } : PLAN_CANCELLED;
    default:
      return PLAN_CANCELLED;
  }
}

/**
 * A plan the agent is waiting on, held until the person answers, as a
 * permission is.
 */
export interface PendingPlan {
  readonly wait: PlanWait;
  /** The session that asks, when its request names one. */
  readonly sessionId?: string;
  /** Aborts once the answer stops mattering; the agent has heard `cancelled`. */
  readonly signal: AbortSignal;
  /** The person's answer; `cancelled` or `withdrawn` answer `cancelled`. */
  answer(answer: PlanAnswer): void;
}

/** Bridges the transport's plan handler to an interface that answers later. */
export class PlanBridge {
  #listeners = new Set<(request: PendingPlan) => void>();
  #closed = new AbortController();

  /**
   * The handler the transport calls with a request it read, or none for one
   * that did not read, which is answered `cancelled` at once.
   */
  readonly handler = (
    request: PlanRequest | undefined,
    withdrawn: AbortSignal,
  ): Promise<PlanResponse> => {
    const signal = AbortSignal.any([withdrawn, this.#closed.signal]);

    return new Promise<PlanResponse>((settle) => {
      let answered = false;
      const answer = (response: PlanResponse) => {
        if (answered) {
          return;
        }

        answered = true;

        signal.removeEventListener('abort', onAbort);
        settle(response);
      };

      const onAbort = () => answer(PLAN_CANCELLED);

      // Nobody to ask, or nothing to show: never taken as a yes.
      if (
        request === undefined ||
        signal.aborted ||
        this.#listeners.size === 0
      ) {
        return onAbort();
      }

      const id = crypto.randomUUID();
      const { agent, sessionId, ...shown } = request;
      const pending: PendingPlan = {
        wait: { id, agent, ...shown },
        ...(sessionId === undefined ? {} : { sessionId }),
        signal,
        answer: (person) => answer(planResponse(agent, person)),
      };

      signal.addEventListener('abort', onAbort, { once: true });

      for (const listener of this.#listeners) {
        listener(pending);
      }
    });
  };

  /** Calls `listener` for each new request; returns the unsubscribe. */
  subscribe(listener: (request: PendingPlan) => void): () => void {
    this.#listeners.add(listener);

    return () => this.#listeners.delete(listener);
  }

  /** Cancels every waiting request; the session is going away. */
  close(): void {
    this.#closed.abort();
    this.#listeners.clear();
  }
}
