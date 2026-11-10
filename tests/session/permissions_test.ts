import { describe, expect, test } from 'bun:test';
import type {
  PermissionOption,
  RequestPermissionRequest,
  RequestPermissionResponse,
} from '@agentclientprotocol/sdk/unstable';
import {
  allowOption,
  type PendingPermission,
  PermissionBridge,
  rejection,
  waitFor,
} from '../../src/session/permissions.ts';

const OPTIONS: PermissionOption[] = [
  { optionId: 'yes', name: 'Yes', kind: 'allow_once' },
  { optionId: 'always', name: 'Always', kind: 'allow_always' },
  { optionId: 'no', name: 'No', kind: 'reject_once' },
];

const RAW: RequestPermissionRequest = {
  sessionId: 's',
  toolCall: { toolCallId: 't' },
  options: OPTIONS,
};

function ask(bridge: PermissionBridge, signal = new AbortController().signal) {
  return bridge.handler(RAW, signal);
}

const CANCELLED: RequestPermissionResponse = {
  outcome: { outcome: 'cancelled' },
};

test('an answer names the option by its id, never one the agent did not offer', async () => {
  const bridge = new PermissionBridge();
  let seen: PendingPermission | undefined;

  bridge.subscribe((request) => (seen = request));

  const decision = ask(bridge);

  expect(() => seen!.resolve('maybe')).toThrow();
  seen!.resolve('always');
  expect(await decision).toStrictEqual({
    outcome: { outcome: 'selected', optionId: 'always' },
  });
});

test('Esc picks the reject option, reject once before always, else cancels', () => {
  const reject = (options: PermissionOption[]) => rejection(options).outcome;

  expect(reject(OPTIONS)).toStrictEqual({
    outcome: 'selected',
    optionId: 'no',
  });
  expect(
    reject([
      ...OPTIONS.slice(0, 2),
      {
        optionId: 'never',
        name: 'Never',
        kind: 'reject_always',
      },
    ]),
  ).toStrictEqual({ outcome: 'selected', optionId: 'never' });
  expect(reject(OPTIONS.slice(0, 2))).toStrictEqual({ outcome: 'cancelled' });
});

test('allowing everything takes allow once, else allow always, else nothing', () => {
  expect(allowOption(OPTIONS)?.optionId).toStrictEqual('yes');
  expect(allowOption(OPTIONS.slice(1))?.optionId).toStrictEqual('always');
  expect(allowOption(OPTIONS.slice(2))).toStrictEqual(undefined);
});

test('a request waits until the interface answers it, and only the first answer counts', async () => {
  const bridge = new PermissionBridge();
  let seen: PendingPermission | undefined;

  bridge.subscribe((request) => (seen = request));

  const decision = ask(bridge);

  expect(bridge.pending().length).toStrictEqual(1);
  seen!.resolve('yes');
  seen!.reject();
  expect(await decision).toStrictEqual({
    outcome: { outcome: 'selected', optionId: 'yes' },
  });
  expect(bridge.pending()).toStrictEqual([]);
});

test('an aborted request is cancelled and withdrawn', async () => {
  const bridge = new PermissionBridge();
  const turn = new AbortController();
  const decision = ask(bridge, turn.signal);

  turn.abort();
  expect(await decision).toStrictEqual(CANCELLED);
  expect(bridge.pending()).toStrictEqual([]);
});

test('closing the bridge cancels every waiting request', async () => {
  const bridge = new PermissionBridge();
  const decisions = [ask(bridge), ask(bridge)];

  bridge.close();
  expect(await Promise.all(decisions)).toStrictEqual([CANCELLED, CANCELLED]);
});

function pending(toolCall: PendingPermission['toolCall']): PendingPermission {
  return {
    raw: {} as unknown as PendingPermission['raw'],
    id: 'p',
    sessionId: 's',
    toolCall,
    options: OPTIONS,
    signal: new AbortController().signal,
    resolve() {},
    reject() {},
  };
}

test('a request with no content keeps its raw input to be shown', () => {
  const rawInput = { command: 'tail -f dev.log' };

  expect(
    waitFor(
      pending({ toolCallId: 't', title: 'mcp__chord__monitor', rawInput }),
    ).rawInput,
  ).toStrictEqual(rawInput);
  expect(
    waitFor(pending({ toolCallId: 't', content: [], rawInput })).rawInput,
  ).toStrictEqual(rawInput);
});

test('a request with content of its own keeps no raw input', () => {
  const wait = waitFor(
    pending({
      toolCallId: 't',
      content: [{ type: 'diff', path: 'notes.txt', newText: 'hi' }],
      rawInput: { file_path: 'notes.txt', content: 'hi' },
    }),
  );

  expect('rawInput' in wait).toStrictEqual(false);
  expect(wait.content).toStrictEqual([
    { type: 'diff', path: 'notes.txt', newText: 'hi' },
  ]);
});

describe('CHD-608 tester: permission presentation lifecycle', () => {
  test('withdrawal invalidates a saved choice while preserving the original deadline', async () => {
    const bridge = new PermissionBridge();
    const withdrawn = new AbortController();
    const deadlineAt = Date.now() + 300_000;
    const decision = bridge.handler(
      {
        ...RAW,
        _meta: {
          'chord/permission': {
            review: { outcome: 'caution', reason: 'held' },
            deadlineAt,
          },
        },
      },
      withdrawn.signal,
    );
    const request = bridge.pending()[0];

    if (request === undefined) {
      throw new Error('Expected a waiting permission.');
    }

    expect(waitFor(request).deadlineAt).toBe(deadlineAt);
    expect(waitFor(request, 'another-session').deadlineAt).toBe(deadlineAt);
    withdrawn.abort();
    request.resolve('yes');

    expect(await decision).toEqual(CANCELLED);
    expect(bridge.pending()).toEqual([]);
    bridge.close();
  });
});
