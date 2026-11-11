/**
 * libfx's turn events and results as ACP has them (CHD-485, "The protocol
 * between the window and riff"): pure, so each row of the design's tables
 * has a test.
 */
import {
  RequestError,
  type SessionUpdate,
  type StopReason,
  type ToolCallLocation,
  type ToolCallContent,
  type ToolKind,
  type Usage,
} from '@agentclientprotocol/sdk/unstable';
import type { FxErrorSummary, FxSessionTurnEvent, FxUsage } from 'libfx/node';

/** How a call is drawn: its title, ACP kind and locations. */
export interface Drawn {
  readonly title: string;
  readonly kind: ToolKind;
  readonly locations?: ToolCallLocation[];
}

/** A call by its name alone, for a tool riff draws no other way. */
const byName = (name: string): Drawn => ({ title: name, kind: 'other' });

/**
 * The `session/update` an event makes, or undefined for none. `started`
 * holds the calls this turn has sent, so a duplicate start is dropped: calls
 * are merged by id, never by position. `draw` gives a call its title, kind
 * and locations from the tool's own table; `shown`, what a tool kept for the
 * window of its call, sent in place of what the model read.
 */
export function updateOf(
  event: FxSessionTurnEvent,
  started: Set<string>,
  draw: (name: string, input: unknown) => Drawn = byName,
  shown: (id: string) => string | ToolCallContent[] | undefined = () =>
    undefined,
): SessionUpdate | undefined {
  switch (event.type) {
    case 'text_delta':
      return {
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text: event.delta },
      };
    case 'reasoning_delta':
      return {
        sessionUpdate: 'agent_thought_chunk',
        content: { type: 'text', text: event.delta },
      };
    // chord drew the steer when it sent it.
    case 'user_message':
      return undefined;
    case 'tool_start':
      if (started.has(event.id)) {
        return undefined;
      }

      started.add(event.id);

      return {
        sessionUpdate: 'tool_call',
        toolCallId: event.id,
        ...draw(event.name, event.input),
        status: 'pending',
        // A truncated input's preview is not the input; the tool's own
        // start gives the whole of it.
        ...(event.input === undefined ? {} : { rawInput: event.input }),
      };
    case 'tool_end': {
      // What the tool kept for the window, or what the model was given.
      const kept = shown(event.id);
      const content =
        event.isError &&
        Array.isArray(kept) &&
        kept.some((item) => item.type === 'diff')
          ? event.content
          : (kept ?? event.content);

      return {
        sessionUpdate: 'tool_call_update',
        toolCallId: event.id,
        status: event.isError ? 'failed' : 'completed',
        ...(content === undefined
          ? {}
          : {
              content:
                typeof content === 'string'
                  ? [
                      {
                        type: 'content',
                        content: { type: 'text', text: content },
                      },
                    ]
                  : content,
            }),
      };
    }
  }
}

/** How a libfx turn ended, as far as riff reads it. */
export interface Ended {
  readonly stopReason: string;
  readonly error?: FxErrorSummary;
}

const STOP_REASONS: Readonly<Record<string, StopReason>> = {
  end_turn: 'end_turn',
  max_output_tokens: 'max_tokens',
  max_model_turns: 'max_turn_requests',
  refused: 'refusal',
  cancelled: 'cancelled',
};

/**
 * The codes of a turn that needs the person to sign in again: a refresh
 * failure, another Grok account, a 401, or chord's own signed-out.
 */
const AUTH_CODES: ReadonlySet<string | number> = new Set([
  'LIBFX_CHATGPT_REFRESH_FAILED',
  'LIBFX_GROK_REFRESH_FAILED',
  'LIBFX_GROK_ACCOUNT_CHANGED',
  'CHORD_SIGNED_OUT',
  401,
  '401',
]);

/**
 * The id of each assistant message of a turn, by its events: text runs on
 * under one id until any other event, and the next text starts a new one,
 * so the window keeps riff's messages apart from each other and from
 * chord's own notes (ACP's `messageId`).
 */
export function messageIds(
  make: () => string = () => crypto.randomUUID(),
): (event: FxSessionTurnEvent) => string | undefined {
  let current: string | undefined;

  return (event) => {
    if (event.type === 'text_delta') {
      return (current ??= make());
    }

    current = undefined;

    return undefined;
  };
}

/** The prompt's stop reason, or the error it is answered with. */
export function stopReasonOf(ended: Ended): StopReason {
  const reason = STOP_REASONS[ended.stopReason];

  if (reason !== undefined) {
    return reason;
  }

  const message = ended.error?.message ?? `The turn ended ${ended.stopReason}.`;
  const code = ended.error?.code;

  if (code !== undefined && AUTH_CODES.has(code)) {
    throw new RequestError(-32000, message);
  }

  throw new RequestError(-32603, message, { code: code ?? null });
}

/** The prompt answer's `usage`, from the turn's result. */
export function usageOf(usage: FxUsage | undefined): Usage | undefined {
  if (usage?.inputTokens === undefined && usage?.outputTokens === undefined) {
    return undefined;
  }

  const inputTokens = usage.inputTokens ?? 0;
  const outputTokens = usage.outputTokens ?? 0;

  return {
    inputTokens,
    outputTokens,
    totalTokens: inputTokens + outputTokens,
    ...(usage.reasoningTokens === undefined
      ? {}
      : { thoughtTokens: usage.reasoningTokens }),
    ...(usage.cacheReadTokens === undefined
      ? {}
      : { cachedReadTokens: usage.cacheReadTokens }),
    ...(usage.cacheWriteTokens === undefined
      ? {}
      : { cachedWriteTokens: usage.cacheWriteTokens }),
  };
}

/** A model request's usage as libfx's `model.end` hook gives it. */
export interface HookUsage {
  readonly inputTokens: number | null;
  readonly outputTokens: number | null;
  readonly cacheReadTokens: number | null;
  readonly cacheWriteTokens: number | null;
}

/**
 * The context a model request used, `usage_update`'s `used`: the last
 * request's tokens, as Codex's adapter and fx count it.
 */
export function usedOf(usage: HookUsage): number {
  return (
    (usage.inputTokens ?? 0) +
    (usage.cacheReadTokens ?? 0) +
    (usage.cacheWriteTokens ?? 0) +
    (usage.outputTokens ?? 0)
  );
}
