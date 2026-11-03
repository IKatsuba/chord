/**
 * Which `session/prompt` a turn answers. `Conversation.send` mints its turn and
 * emits before it returns, and a monitor's turn may run with prompts queued
 * behind it, so arrival cannot say: a request binds its turn before it sends.
 */
import type { JsonRpcId } from '@agentclientprotocol/sdk/unstable';
import type { MessageFrom, TurnResult } from '../session/transcript/types.ts';

/** Who began the turn running now. */
export type TurnOrigin = 'client' | 'message' | 'agent';

export interface Turns {
  /** Each prompt not yet answered, by its turn. */
  readonly bound: ReadonlyMap<string, JsonRpcId>;
  readonly running?: {
    readonly turnId: string;
    readonly origin: TurnOrigin;
  };
  /**
   * The bound turn that was running when its agent went: its `result` is still
   * to come, and it answers then, unlike a prompt that was queued.
   */
  readonly lost?: string;
  /**
   * Turns a client steered, which answer no request: when one runs as its
   * own turn it is the client's, and its words are not told back.
   */
  readonly steered?: ReadonlySet<string>;
}

export const NO_TURNS: Turns = { bound: new Map() };

/** What the table hears: the handler's own, and `Conversation`'s events. */
export type TurnInput =
  | {
      readonly type: 'bind';
      readonly requestId: JsonRpcId;
      readonly turnId: string;
    }
  /** `send` refused it, so no turn of it will ever be heard of. */
  | { readonly type: 'unbind'; readonly turnId: string }
  /** A turn `_chord/session/steer` sends, before it is sent. */
  | { readonly type: 'steered'; readonly turnId: string }
  | {
      readonly type: 'prompt';
      readonly turnId: string;
      readonly text: string;
      readonly from?: MessageFrom;
      /** Set on a message steered into a running turn; it gets no `result`. */
      readonly into?: string;
    }
  | {
      readonly type: 'result';
      readonly turnId: string;
      readonly result: TurnResult;
    }
  | { readonly type: 'queue_withdrawn'; readonly turnIds?: readonly string[] }
  | { readonly type: 'cycle_started'; readonly turnId: string }
  | { readonly type: 'self_started'; readonly turnId: string }
  | { readonly type: 'disconnected' }
  /** `session/close`, or the way out. */
  | { readonly type: 'closing' };

/** What the table says to do about what it heard. */
export type TurnSend =
  | {
      readonly type: 'answer';
      readonly requestId: JsonRpcId;
      readonly result: TurnResult;
    }
  | { readonly type: 'cancelled'; readonly requestId: JsonRpcId }
  /** Queued when its agent went: `turnId` is still to be taken out of the queue. */
  | {
      readonly type: 'session_gone';
      readonly requestId: JsonRpcId;
      readonly turnId: string;
    }
  /** A turn no client began: the client is told what started it. */
  | {
      readonly type: 'message';
      readonly text: string;
      readonly from?: MessageFrom;
    };

export interface TurnStep {
  readonly turns: Turns;
  readonly sends: readonly TurnSend[];
}

/** The turn a request is bound to; none once it has been answered. */
export function turnOf(turns: Turns, requestId: JsonRpcId): string | undefined {
  for (const [turnId, bound] of turns.bound) {
    if (bound === requestId) {
      return turnId;
    }
  }

  return undefined;
}

/** `turns` with none of `turnIds` steered. */
function unsteered(turns: Turns, turnIds: Iterable<string>): Turns {
  const { steered, ...rest } = turns;
  const left = new Set(steered);

  for (const turnId of turnIds) {
    left.delete(turnId);
  }

  return left.size === 0 ? rest : { ...rest, steered: left };
}

function without(
  bound: ReadonlyMap<string, JsonRpcId>,
  turnIds: Iterable<string>,
): ReadonlyMap<string, JsonRpcId> {
  const left = new Map(bound);

  for (const turnId of turnIds) {
    left.delete(turnId);
  }

  return left;
}

export function reduceTurns(turns: Turns, input: TurnInput): TurnStep {
  switch (input.type) {
    case 'bind':
      return {
        turns: {
          ...turns,
          bound: new Map(turns.bound).set(input.turnId, input.requestId),
        },
        sends: [],
      };
    case 'unbind':
      return {
        turns: unsteered(
          { ...turns, bound: without(turns.bound, [input.turnId]) },
          [input.turnId],
        ),
        sends: [],
      };
    case 'steered':
      return {
        turns: {
          ...turns,
          steered: new Set(turns.steered).add(input.turnId),
        },
        sends: [],
      };
    case 'prompt': {
      if (turns.steered?.has(input.turnId) === true) {
        const left = unsteered(turns, [input.turnId]);

        return {
          turns:
            input.into === undefined
              ? {
                  ...left,
                  running: { turnId: input.turnId, origin: 'client' },
                }
              : left,
          sends: [],
        };
      }

      const message: TurnSend = {
        type: 'message',
        text: input.text,
        ...(input.from === undefined ? {} : { from: input.from }),
      };

      if (input.into !== undefined) {
        return { turns, sends: [message] };
      }

      // Over a cycle too: a prompt takes it over, and the cycle gets no `result`.
      return turns.bound.has(input.turnId)
        ? {
            turns: {
              ...turns,
              running: { turnId: input.turnId, origin: 'client' },
            },
            sends: [],
          }
        : {
            turns: {
              ...turns,
              running: { turnId: input.turnId, origin: 'message' },
            },
            sends: [message],
          };
    }
    case 'result': {
      const { running, lost, ...rest } = unsteered(turns, [input.turnId]);
      const requestId = turns.bound.get(input.turnId);
      const left: Turns = {
        ...rest,
        bound: without(turns.bound, [input.turnId]),
        ...(running === undefined || running.turnId === input.turnId
          ? {}
          : { running }),
        ...(lost === undefined || lost === input.turnId ? {} : { lost }),
      };

      return {
        turns: left,
        sends:
          requestId === undefined
            ? []
            : [{ type: 'answer', requestId, result: input.result }],
      };
    }
    case 'queue_withdrawn': {
      const turnIds = input.turnIds ?? [];

      return {
        turns: unsteered(
          { ...turns, bound: without(turns.bound, turnIds) },
          turnIds,
        ),
        sends: turnIds.flatMap((turnId): TurnSend[] => {
          const requestId = turns.bound.get(turnId);

          return requestId === undefined
            ? []
            : [{ type: 'cancelled', requestId }];
        }),
      };
    }
    case 'cycle_started':
    case 'self_started':
      return {
        turns: {
          ...turns,
          running: { turnId: input.turnId, origin: 'agent' },
        },
        sends: [],
      };
    case 'disconnected': {
      const { running, ...rest } = turns;
      const lost = running?.turnId ?? turns.lost;
      const queued = [...turns.bound].filter(([turnId]) => turnId !== lost);

      return {
        turns: {
          ...rest,
          bound: without(
            turns.bound,
            queued.map(([turnId]) => turnId),
          ),
          ...(lost !== undefined && turns.bound.has(lost) ? { lost } : {}),
        },
        sends: queued.map(([turnId, requestId]) => ({
          type: 'session_gone',
          requestId,
          turnId,
        })),
      };
    }
    case 'closing':
      return {
        turns: NO_TURNS,
        sends: [...turns.bound.values()].map((requestId) => ({
          type: 'cancelled',
          requestId,
        })),
      };
  }
}

/** What `_chord/session/state` says of a session. */
export type SessionState =
  | {
      readonly state: 'running' | 'requires_action';
      readonly origin?: TurnOrigin;
    }
  | { readonly state: 'idle' };

/**
 * Main's state, from the turn running and whether an ask of its own is open:
 * the table's rows, read after each step, so only a change need go.
 */
export function sessionStateOf(turns: Turns, asking: boolean): SessionState {
  const origin = turns.running?.origin;

  if (asking) {
    return {
      state: 'requires_action',
      ...(origin === undefined ? {} : { origin }),
    };
  }

  return origin === undefined
    ? { state: 'idle' }
    : { state: 'running', origin };
}
