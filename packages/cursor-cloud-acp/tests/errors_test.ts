import { describe, expect, test } from 'bun:test';
import { RequestError } from '@agentclientprotocol/sdk';
import {
  CursorError,
  lostConnection,
  plain,
  refused,
  signedOut,
  toAcp,
} from '../src/errors.ts';

const LINK = 'https://cursor.com/agents/bc-1';

/** `error`'s answer as code, message and data. */
function answer(error: RequestError) {
  return { code: error.code, message: error.message, data: error.data };
}

describe("toAcp answers each kind as the design's table says", () => {
  test.each([
    ['auth', -32000, 'Invalid API key'],
    ['not-found', -32002, 'Agent bc-1 not found'],
    ['archived', -32602, 'Agent bc-1 is archived'],
    ['rate-limit', -32603, 'Too many requests'],
    ['network', -32603, 'Service unavailable'],
  ] as const)("%s → %i with the SDK's message", (kind, code, message) => {
    expect(answer(toAcp(new CursorError(kind, message)))).toEqual({
      code,
      message,
      data: undefined,
    });
  });

  test("integration: -32603, the SDK's message and its help link", () => {
    const error = new CursorError('integration', 'GitHub is not connected', {
      helpUrl: 'https://cursor.com/dashboard/integrations',
    });

    expect(answer(toAcp(error))).toEqual({
      code: -32603,
      message:
        'GitHub is not connected\nhttps://cursor.com/dashboard/integrations',
      data: undefined,
    });
  });

  test("busy: -32603, the SDK's message and the agent's link", () => {
    expect(
      answer(toAcp(new CursorError('busy', 'Agent has an active run'), LINK)),
    ).toEqual({
      code: -32603,
      message: `Agent has an active run\n${LINK}`,
      data: undefined,
    });
    expect(
      toAcp(new CursorError('busy', 'Agent has an active run')).message,
    ).toBe('Agent has an active run');
  });

  test("every kind carries the SDK's class, code and request id in data", () => {
    for (const kind of [
      'auth',
      'not-found',
      'archived',
      'integration',
      'busy',
      'rate-limit',
      'network',
      'other',
    ] as const) {
      expect(
        toAcp(
          new CursorError(kind, 'Usage limit exceeded', {
            sdkClass: 'ConfigurationError',
            code: 'usage_limit_exceeded',
          }),
        ).data,
      ).toEqual({ class: 'ConfigurationError', code: 'usage_limit_exceeded' });
    }
  });

  test('other: -32603, its code and request id in data', () => {
    const error = new CursorError('other', 'Something broke', {
      code: 'internal',
      requestId: 'req-1',
    });

    expect(answer(toAcp(error))).toEqual({
      code: -32603,
      message: 'Something broke',
      data: { code: 'internal', requestId: 'req-1' },
    });
    expect(toAcp(new CursorError('other', 'Something broke')).data).toBe(
      undefined,
    );
  });
});

test("an error not the SDK's is an internal error with its message", () => {
  expect(answer(toAcp(new Error('spawn git ENOENT')))).toEqual({
    code: -32603,
    message: 'spawn git ENOENT',
    data: undefined,
  });
  expect(toAcp('a string').message).toBe('a string');
});

test('plain is the one line written: a message, never a stack', () => {
  const error = new CursorError('other', 'Usage limit exceeded');

  expect(plain(error)).toBe('Usage limit exceeded');
  expect(plain('x')).toBe('x');
});

test('a RequestError answers as it is', () => {
  const error = refused('Branch a is not pushed to origin.');

  expect(toAcp(error)).toBe(error);
});

test("signed out is authRequired with the design's words, a refusal -32602 with its own", () => {
  expect(answer(signedOut())).toEqual({
    code: -32000,
    message: 'Not signed in to Cursor.',
    data: undefined,
  });
  expect(answer(refused('Not a git repository.'))).toEqual({
    code: -32602,
    message: 'Not a git repository.',
    data: undefined,
  });
});

test('a lost stream names the link and how to see where the agent got to', () => {
  expect(lostConnection(LINK)).toBe(
    `Lost the connection to Cursor; the agent keeps running there: ${LINK}. Reopen the session to see where it got to.`,
  );
});
