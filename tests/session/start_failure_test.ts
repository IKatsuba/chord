import { expect, test } from 'bun:test';
import { RequestError } from '@agentclientprotocol/sdk';
import { AgentGone } from '../../src/acp/connection.ts';
import { asSignIn } from '../../src/session/sign_in.ts';
import {
  failureLines,
  failureNote,
  sentence,
  startFailed,
  startFailureOf,
  stepWords,
  wayOnFor,
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

test("the step says what failed in chord words, and the agent's own only where it refused", () => {
  const at = (failure: Parameters<typeof stepWords>[1]) =>
    stepWords('the agent said this', failure);

  expect(at({ step: 'initialize', exit: { code: 1 } })).toBe(
    'it exited with code 1 before answering initialize.',
  );
  expect(
    at({ step: 'session/load', exit: { code: 137, signal: 'SIGKILL' } }),
  ).toBe('it was stopped by SIGKILL before answering session/load.');
  expect(at({ step: 'session/new', code: -32601 })).toBe(
    'it does not serve ACP sessions: not an ACP agent, or not at this version.',
  );
  expect(at({ step: 'initialize', code: -32601 })).toBe(
    'it refused initialize: the agent said this',
  );
  expect(at({ step: 'session/resume', code: -32602 })).toBe(
    'it refused session/resume: the agent said this',
  );
  // A sign-in says it its own way, and a command not found keeps today's words.
  expect(at({ step: 'session/new', code: -32000 })).toBe('the agent said this');
  expect(at({ step: 'initialize' })).toBe('the agent said this');
  expect(at(undefined)).toBe('the agent said this');
});

test('the block as lines: the pin, the end of stderr with what was cut, the way on', () => {
  expect(
    failureLines('minion-code', {
      step: 'initialize',
      exit: { code: 1 },
      pinned: 'minion-code@0.1.44',
      stderr: { lines: ['Traceback', '  File "x"', 'ImportError: y'], cut: 1 },
    }),
  ).toStrictEqual([
    'chord ran minion-code@0.1.44, the version the ACP Registry names.',
    'The end of its stderr:',
    '  … +1 line',
    '  Traceback',
    '    File "x"',
    '  ImportError: y',
  ]);
  expect(
    failureLines('zeroclaw', { step: 'session/new', code: -32602 }),
  ).toStrictEqual([
    'Set a default agent: [acp] default_agent = "<alias>" in ZeroClaw\'s config, or start it with zeroclaw acp --agent <alias>.',
  ]);
  expect(
    wayOnFor('qoder', { step: 'session/new', code: -32602 }),
  ).toBeUndefined();
  expect(
    wayOnFor('zeroclaw', { step: 'initialize', code: -32602 }),
  ).toBeUndefined();
  expect(
    failureLines('kimi', { step: 'initialize', exit: { code: 0 } }),
  ).toStrictEqual([]);
});

test("an agent that opened one hears the pin, the tail's last line and the person's way on, as sentences", () => {
  expect(
    failureNote('minion-code', {
      step: 'initialize',
      exit: { code: 1 },
      pinned: 'minion-code@0.1.44',
      stderr: { lines: ['  File "x"', '  ImportError: y'], cut: 0 },
    }),
  ).toBe(
    ' chord ran minion-code@0.1.44, the version the ACP Registry names. Its stderr ended: "ImportError: y".',
  );
  expect(failureNote('zeroclaw', { step: 'session/new', code: -32602 })).toBe(
    ' The person sets a default agent: [acp] default_agent = "<alias>" in ZeroClaw\'s config, or start it with zeroclaw acp --agent <alias>.',
  );
  expect(sentence('it refused session/new: no')).toBe(
    'it refused session/new: no.',
  );
  expect(sentence('it exited.')).toBe('it exited.');
});
