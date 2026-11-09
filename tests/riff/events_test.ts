import { describe, expect, test } from 'bun:test';
import { RequestError } from '@agentclientprotocol/sdk/unstable';
import {
  stopReasonOf,
  updateOf,
  usageOf,
  usedOf,
} from '../../src/riff/events.ts';

describe("libfx's events as session/update", () => {
  test('text and reasoning deltas are message and thought chunks', () => {
    const started = new Set<string>();

    expect(
      updateOf({ type: 'text_delta', delta: 'Hi' }, started),
    ).toStrictEqual({
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text: 'Hi' },
    });
    expect(
      updateOf({ type: 'reasoning_delta', delta: 'Hm' }, started),
    ).toStrictEqual({
      sessionUpdate: 'agent_thought_chunk',
      content: { type: 'text', text: 'Hm' },
    });
  });

  test('a steer joining the turn sends nothing: chord drew it', () => {
    expect(
      updateOf({ type: 'user_message', text: 'and', id: 's1' }, new Set()),
    ).toBeUndefined();
  });

  test('a tool start is a pending tool_call once, by its id', () => {
    const started = new Set<string>();
    const start = {
      type: 'tool_start',
      id: 'call_1',
      name: 'read',
      input: { path: 'a.ts' },
    } as const;

    expect(updateOf(start, started)).toStrictEqual({
      sessionUpdate: 'tool_call',
      toolCallId: 'call_1',
      title: 'read',
      kind: 'other',
      status: 'pending',
      rawInput: { path: 'a.ts' },
    });
    expect(updateOf(start, started)).toBeUndefined();
    expect(updateOf({ ...start, id: 'call_2' }, started)).toMatchObject({
      toolCallId: 'call_2',
    });
  });

  test('a call ends with what its tool kept for the window, when it kept one', () => {
    const end = {
      type: 'tool_end',
      id: 'call_1',
      name: 'read',
      content: '1\thello',
      isError: false,
    } as const;
    const text = (update: unknown) =>
      (update as { content: { content: { text: string } }[] }).content[0]
        ?.content.text;

    expect(
      text(updateOf(end, new Set(), undefined, (id) => `shown ${id}`)),
    ).toBe('shown call_1');
    expect(text(updateOf(end, new Set(), undefined, () => undefined))).toBe(
      '1\thello',
    );
  });

  test("a call is drawn by its tool's own table when riff gives one", () => {
    const start = {
      type: 'tool_start',
      id: 'call_1',
      name: 'read',
      input: { path: 'a.ts' },
    } as const;

    expect(
      updateOf(start, new Set(), (name, input) => ({
        title: `Read ${(input as { path: string }).path}`,
        kind: 'read',
        locations: [{ path: '/p/a.ts' }],
      })),
    ).toStrictEqual({
      sessionUpdate: 'tool_call',
      toolCallId: 'call_1',
      title: 'Read a.ts',
      kind: 'read',
      locations: [{ path: '/p/a.ts' }],
      status: 'pending',
      rawInput: { path: 'a.ts' },
    });
  });

  test("a truncated input's preview is not sent as the input", () => {
    expect(
      updateOf(
        {
          type: 'tool_start',
          id: 'call_1',
          name: 'write',
          inputTruncated: true,
          inputPreview: '{"path":',
        },
        new Set(),
      ),
    ).not.toHaveProperty('rawInput');
  });

  test('a tool end is completed or failed, with its content', () => {
    expect(
      updateOf(
        {
          type: 'tool_end',
          id: 'call_1',
          name: 'read',
          content: 'text',
          isError: false,
        },
        new Set(),
      ),
    ).toStrictEqual({
      sessionUpdate: 'tool_call_update',
      toolCallId: 'call_1',
      status: 'completed',
      content: [{ type: 'content', content: { type: 'text', text: 'text' } }],
    });
    expect(
      updateOf(
        { type: 'tool_end', id: 'call_1', name: 'read', isError: true },
        new Set(),
      ),
    ).toStrictEqual({
      sessionUpdate: 'tool_call_update',
      toolCallId: 'call_1',
      status: 'failed',
    });
  });
});

describe("libfx's stop reasons as ACP's", () => {
  test.each([
    ['end_turn', 'end_turn'],
    ['max_output_tokens', 'max_tokens'],
    ['max_model_turns', 'max_turn_requests'],
    ['refused', 'refusal'],
    ['cancelled', 'cancelled'],
  ])('%s is %s', (libfx, acp) => {
    expect(stopReasonOf({ stopReason: libfx })).toBe(acp as never);
  });

  const thrown = (ended: Parameters<typeof stopReasonOf>[0]) => {
    try {
      stopReasonOf(ended);
    } catch (error) {
      return error as RequestError;
    }

    throw new Error('it answered');
  };

  test.each([
    'LIBFX_CHATGPT_REFRESH_FAILED',
    'LIBFX_GROK_REFRESH_FAILED',
    'LIBFX_GROK_ACCOUNT_CHANGED',
    'CHORD_SIGNED_OUT',
    401,
  ])('an error %p needs a sign-in: -32000 with libfx message', (code) => {
    const error = thrown({
      stopReason: 'error',
      error: { name: 'Error', message: 'Signed out', code },
    });

    expect(error).toBeInstanceOf(RequestError);
    expect(error.code).toBe(-32000);
    expect(error.message).toBe('Signed out');
  });

  test("any other error is -32603 with libfx's message and its code", () => {
    const error = thrown({
      stopReason: 'error',
      error: { name: 'Error', message: 'Broke', code: 'FX_X' },
    });

    expect([error.code, error.message, error.data]).toStrictEqual([
      -32603,
      'Broke',
      { code: 'FX_X' },
    ]);
  });

  test('unknown is -32603 too', () => {
    const error = thrown({ stopReason: 'unknown' });

    expect([error.code, error.data]).toStrictEqual([-32603, { code: null }]);
  });
});

describe('usage', () => {
  test("the answer's usage totals input and output", () => {
    expect(
      usageOf({ inputTokens: 10, outputTokens: 2, cacheReadTokens: 4 }),
    ).toStrictEqual({
      inputTokens: 10,
      outputTokens: 2,
      totalTokens: 12,
      cachedReadTokens: 4,
    });
    expect(usageOf({})).toBeUndefined();
    expect(usageOf(undefined)).toBeUndefined();
  });

  test("used is the last model request's tokens", () => {
    expect(
      usedOf({
        inputTokens: 100,
        outputTokens: 5,
        cacheReadTokens: null,
        cacheWriteTokens: 3,
      }),
    ).toBe(108);
  });
});
