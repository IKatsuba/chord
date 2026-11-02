import { describe, expect, test } from 'bun:test';
import assert from 'node:assert';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { runAcp } from '../../src/acp_agent.ts';
import { killSpawnedGroups } from '../../src/platform/process.ts';
import type { LeaveExit } from '../../src/session/leaving.ts';
import { openSession } from '../../src/session/session.ts';
import { type AcpClient, clientOverStreams } from '../fixtures/acp_client.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { until } from '../session/conversation_fake.ts';

const PERMISSION = 'session/request_permission';
const FORM = 'elicitation/create';

async function withClient(
  flags: readonly string[],
  body: (client: AcpClient, cwd: string) => Promise<void>,
): Promise<void> {
  const cwd = await mkdtemp(join(tmpdir(), 'chord-acp-tester-'));
  const { client, input, output, end } = clientOverStreams();
  const exits: LeaveExit[] = [];

  runAcp({
    input,
    output,
    stderr: () => {},
    exit: (how) => exits.push(how),
    agent: 'fake',
    agentCommand: fakeAgentCommand(undefined, ...flags),
    version: '1.2.3',
    stateDir: cwd,
    open: openSession,
    place: () => Promise.resolve({ mcpServers: [] }),
  });

  try {
    await client.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: {},
    });
    await body(client, cwd);
  } finally {
    end();

    await until(() => exits.length > 0, 20_000);
    await until(() => killSpawnedGroups().length === 0);
    await rm(cwd, { recursive: true, force: true });

    expect(exits).toEqual([{ code: 0 }]);
  }
}

async function newSession(client: AcpClient, cwd: string): Promise<string> {
  const answer = await client.request('session/new', { cwd, mcpServers: [] });

  expect(answer.error).toBeUndefined();

  const id = answer.result?.sessionId;

  assert(typeof id === 'string');

  return id;
}

function prompt(client: AcpClient, sessionId: string, text: string): number {
  return client.send('session/prompt', {
    sessionId,
    prompt: [{ type: 'text', text }],
  });
}

async function ask(client: AcpClient, method: string, sessionId: string) {
  const message = await client.until(
    (entry) => entry.method === method && entry.params?.sessionId === sessionId,
  );

  assert(message.id !== undefined && message.id !== null);

  return { ...message, id: message.id };
}

function answers(client: AcpClient, id: number) {
  return client.messages.filter(
    (message) => message.id === id && message.method === undefined,
  );
}

const selected = (optionId: string) => ({
  outcome: { outcome: 'selected', optionId },
});

describe('CHD-574 tester: agent app session and ask boundaries', () => {
  test('equal downstream ids keep concurrent permissions and answers separate', () =>
    withClient(['--session-id', 'fixed'], async (client, cwd) => {
      const first = await newSession(client, cwd);
      const second = await newSession(client, cwd);

      expect([first, second]).toEqual(['fixed', 'fixed~2']);

      const firstTurn = prompt(client, first, 'permission');
      const secondTurn = prompt(client, second, 'permission');
      const firstAsk = await ask(client, PERMISSION, first);
      const secondAsk = await ask(client, PERMISSION, second);

      expect(firstAsk.id).not.toBe(secondAsk.id);

      client.respond(secondAsk.id, selected('allow'));
      client.respond(firstAsk.id, selected('not-offered'));

      expect((await client.answerTo(secondTurn)).result?.stopReason).toBe(
        'end_turn',
      );
      expect((await client.answerTo(firstTurn)).result?.stopReason).toBe(
        'end_turn',
      );
      expect(client.said(first)).toContain('Permission: deny');
      expect(client.said(first)).not.toContain('Permission: allow');
      expect(client.said(second)).toContain('Permission: allow');
      expect(answers(client, firstTurn)).toHaveLength(1);
      expect(answers(client, secondTurn)).toHaveLength(1);
    }));

  test('cancelling one session leaves another form open despite a late answer', () =>
    withClient([], async (client, cwd) => {
      const first = await newSession(client, cwd);
      const second = await newSession(client, cwd);
      const firstTurn = prompt(client, first, 'permission');
      const secondTurn = prompt(client, second, 'form');
      const permission = await ask(client, PERMISSION, first);
      const form = await ask(client, FORM, second);

      client.notify('$/cancel_request', { requestId: firstTurn });

      await client.until(
        (message) =>
          message.method === '$/cancel_request' &&
          message.params?.requestId === permission.id,
      );

      expect((await client.answerTo(firstTurn)).result?.stopReason).toBe(
        'cancelled',
      );

      client.respond(permission.id, selected('allow'));

      // A real round trip establishes that the late answer has been read.
      expect((await client.request('_tester/barrier')).error?.code).toBe(
        -32601,
      );
      expect(answers(client, secondTurn)).toHaveLength(0);
      expect(
        client.messages.some(
          (message) =>
            message.method === '$/cancel_request' &&
            message.params?.requestId === form.id,
        ),
      ).toBe(false);

      client.respond(form.id, { action: 'decline' });

      expect((await client.answerTo(secondTurn)).result?.stopReason).toBe(
        'end_turn',
      );
      expect(client.said(second)).toContain('Elicitation answer: decline');
      expect(client.said(first)).not.toContain('Permission: allow');
      expect(answers(client, firstTurn)).toHaveLength(1);
    }));

  test('closing a session cancels its queue and leaves a separate turn intact', () =>
    withClient([], async (client, cwd) => {
      const first = await newSession(client, cwd);
      const second = await newSession(client, cwd);
      const running = prompt(client, first, 'permission');

      await ask(client, PERMISSION, first);

      const queued = prompt(client, first, 'never sent');
      const independent = prompt(client, second, 'text');

      expect(
        (await client.request('session/close', { sessionId: first })).error,
      ).toBeUndefined();

      for (const id of [running, queued]) {
        expect((await client.answerTo(id)).result?.stopReason).toBe(
          'cancelled',
        );
        expect(answers(client, id)).toHaveLength(1);
      }

      expect((await client.answerTo(independent)).result?.stopReason).toBe(
        'end_turn',
      );
      expect(client.said(second)).toContain('Hello, world.');
      expect(
        (await client.answerTo(prompt(client, first, 'text'))).error?.code,
      ).toBe(-32002);
    }));

  test('a string cancel id cannot cancel a numeric request with the same digits', () =>
    withClient([], async (client, cwd) => {
      const session = await newSession(client, cwd);
      const running = prompt(client, session, 'permission');
      const permission = await ask(client, PERMISSION, session);

      client.notify('$/cancel_request', { requestId: String(running) });

      await client.request('_tester/barrier');

      expect(answers(client, running)).toHaveLength(0);

      client.respond(permission.id, selected('deny'));

      expect((await client.answerTo(running)).result?.stopReason).toBe(
        'end_turn',
      );
      expect(client.said(session)).toContain('Permission: deny');
      expect(answers(client, running)).toHaveLength(1);
    }));
});
