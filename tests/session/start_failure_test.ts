import { expect, test } from 'bun:test';
import { RequestError } from '@agentclientprotocol/sdk';
import { AgentGone } from '../../src/acp/connection.ts';
import { asSignIn } from '../../src/session/sign_in.ts';
import {
  startFailed,
  startFailureOf,
} from '../../src/session/start_failure.ts';

test('an agent that went says how it ended and the end of its stderr, by the step it went at', () => {
  const gone = new AgentGone(
    'The agent exited: boom',
    { code: 1 },
    { lines: ['trace', 'boom'], cut: 0 },
  );
  const failed = startFailed(gone, 'initialize', 'pkg@1.0.0');

  expect(failed.message).toStrictEqual('The agent exited: boom');
  expect(failed.failure).toStrictEqual({
    step: 'initialize',
    exit: { code: 1 },
    stderr: { lines: ['trace', 'boom'], cut: 0 },
    pinned: 'pkg@1.0.0',
  });
  expect(
    startFailed(
      new AgentGone('The agent exited.', { code: 0 }, { lines: [], cut: 0 }),
      'initialize',
      undefined,
    ).failure,
  ).toStrictEqual({ step: 'initialize', exit: { code: 0 } });
  // An exit not seen by the time its stderr was read is not said.
  expect(
    startFailed(
      new AgentGone('The agent exited.', undefined, { lines: [], cut: 0 }),
      'session/new',
      undefined,
    ).failure,
  ).toStrictEqual({ step: 'session/new' });
});

test("a refusal says its code, the sign-in's too, whatever its words", () => {
  expect(
    startFailed(
      new RequestError(-32601, 'Method not found: session/new'),
      'session/new',
      undefined,
    ).failure,
  ).toStrictEqual({ step: 'session/new', code: -32601 });
  expect(
    startFailed(
      asSignIn(RequestError.authRequired(), []),
      'session/load',
      undefined,
    ).failure,
  ).toStrictEqual({ step: 'session/load', code: -32000 });
  expect(
    startFailed(new Error('spawn x ENOENT'), 'initialize', undefined).failure,
  ).toStrictEqual({
    step: 'initialize',
  });
});

test('a failure is found under the error that wraps it', () => {
  const failed = startFailed(
    new RequestError(-32602, 'no alias'),
    'session/new',
    undefined,
  );

  expect(
    startFailureOf(
      new Error('it cannot resume session s: no alias', { cause: failed }),
    ),
  ).toStrictEqual({ step: 'session/new', code: -32602 });
  expect(startFailureOf(new Error('boom'))).toBeUndefined();
});
