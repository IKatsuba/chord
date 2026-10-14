import type {
  PermissionOption,
  RequestPermissionRequest,
  RequestPermissionResponse,
  ToolCallUpdate,
} from '@agentclientprotocol/sdk';
import type { PermissionWait } from './transcript/types.ts';

/**
 * A permission request the agent is waiting on, held until the person answers.
 * The transport asks through a handler that must return the answer; the
 * interface answers whenever a key is pressed, so the handler parks here until
 * then.
 */
export interface PendingPermission {
  readonly id: string;
  readonly sessionId: string;
  readonly toolCall: ToolCallUpdate;
  readonly options: readonly PermissionOption[];
  /**
   * Aborts when the request stops mattering — the turn was cancelled or the
   * session closed — so the interface takes the prompt off the screen.
   */
  readonly signal: AbortSignal;
  /** Answers with one of `options`, by its `optionId`. */
  resolve(optionId: string): void;
  /**
   * Declines, as Esc does in Claude Code: the agent hears its own reject
   * option, and the turn goes on.
   */
  reject(): void;
}

/**
 * The option `--dangerously-skip-permissions` answers with: allow once,
 * else allow always, so nothing is remembered past the run unless the
 * agent leaves no other way to allow. None when the request offers no allow.
 */
export function allowOption(
  options: readonly PermissionOption[],
): PermissionOption | undefined {
  return (
    options.find((option) => option.kind === 'allow_once') ??
    options.find((option) => option.kind === 'allow_always')
  );
}

/**
 * What Esc answers: the agent's reject-once option, else its reject-always
 * one, else `cancelled`, which is ACP's only answer that picks no option.
 */
export function rejection(
  options: readonly PermissionOption[],
): RequestPermissionResponse {
  const option =
    options.find((candidate) => candidate.kind === 'reject_once') ??
    options.find((candidate) => candidate.kind === 'reject_always');

  return {
    outcome:
      option === undefined
        ? { outcome: 'cancelled' }
        : { outcome: 'selected', optionId: option.optionId },
  };
}

/**
 * What the transcript keeps of a request: everything but the answering, and
 * the subagent that asks, when it is not `sessionId`, the session's own.
 */
export function waitFor(
  request: PendingPermission,
  sessionId?: string,
): PermissionWait {
  const { toolCallId, title, kind, locations, content, rawInput } =
    request.toolCall;

  return {
    id: request.id,
    ...(sessionId === undefined || request.sessionId === sessionId
      ? {}
      : { subagentId: request.sessionId }),
    toolCallId,
    ...(title ? { title } : {}),
    ...(kind ? { kind } : {}),
    ...(locations ? { locations } : {}),
    // An MCP tool's request is its name alone, with the arguments only here;
    // a request with content says what it does without them.
    ...((content ?? []).length === 0 && rawInput !== undefined
      ? { rawInput }
      : {}),
    options: request.options,
  };
}

/** Bridges the transport's permission handler to an interface that answers later. */
export class PermissionBridge {
  #pending = new Map<string, PendingPermission>();
  #listeners = new Set<(request: PendingPermission) => void>();
  #closed = new AbortController();

  /**
   * The handler the transport calls; pass it as `openAgent`'s
   * `onPermission`. Its signal aborts once the answer stops mattering, and
   * the transport has then answered `cancelled` itself.
   */
  readonly handler = (
    request: RequestPermissionRequest,
    withdrawn: AbortSignal,
  ): Promise<RequestPermissionResponse> => {
    const signal = AbortSignal.any([withdrawn, this.#closed.signal]);

    return new Promise<RequestPermissionResponse>((settle) => {
      const id = crypto.randomUUID();
      let answered = false;
      const answer = (response: RequestPermissionResponse) => {
        if (answered) {
          return;
        }

        answered = true;

        this.#pending.delete(id);
        signal.removeEventListener('abort', onAbort);
        settle(response);
      };

      const onAbort = () => answer({ outcome: { outcome: 'cancelled' } });
      const pending: PendingPermission = {
        id,
        sessionId: request.sessionId,
        toolCall: request.toolCall,
        options: request.options,
        signal,
        resolve: (optionId) => {
          if (!request.options.some((option) => option.optionId === optionId)) {
            throw new Error(`No permission option "${optionId}".`);
          }

          answer({ outcome: { outcome: 'selected', optionId } });
        },
        reject: () => answer(rejection(request.options)),
      };

      if (signal.aborted) {
        return onAbort();
      }

      signal.addEventListener('abort', onAbort, { once: true });
      this.#pending.set(id, pending);

      for (const listener of this.#listeners) {
        listener(pending);
      }
    });
  };

  /** Calls `listener` for each new request; returns the unsubscribe. */
  subscribe(listener: (request: PendingPermission) => void): () => void {
    this.#listeners.add(listener);

    return () => this.#listeners.delete(listener);
  }

  /** Requests still waiting for an answer, oldest first. */
  pending(): PendingPermission[] {
    return [...this.#pending.values()];
  }

  /** Cancels every waiting request; the session is going away. */
  close(): void {
    this.#closed.abort();
    this.#listeners.clear();
  }
}
