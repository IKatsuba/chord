import { afterEach, describe, expect, test } from 'bun:test';
import assert from 'node:assert';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { type GroupProcess, spawnGroup } from '../../src/platform/process.ts';
import { until } from '../session/conversation_fake.ts';
import { AcpClient, clientOverStreams } from './acp_client.ts';
import { fakeAgentCommand } from './fake.ts';

const running: GroupProcess[] = [];

afterEach(() => {
  for (const group of running.splice(0)) {
    group.signal('SIGKILL');
  }
});

/** The fake agent itself, on the client: the fixtures' own check of each other. */
function onFake(...flags: string[]) {
  const [program, ...args] = fakeAgentCommand(undefined, ...flags);

  assert(program !== undefined);

  const group = spawnGroup(program, args, {
    cwd: process.cwd(),
    stdin: 'pipe',
    stdout: 'pipe',
    stderr: 'ignore',
  });

  running.push(group);

  const { stdin, stdout } = group.child;

  assert(stdin !== null && stdout !== null);

  return {
    group,
    stdin,
    client: new AcpClient(
      (line) => {
        stdin.write(line);
      },
      stdout as unknown as AsyncIterable<Uint8Array>,
    ),
  };
}

async function up(client: AcpClient, cwd: string): Promise<string> {
  await client.request('initialize', {
    protocolVersion: 1,
    clientCapabilities: {},
  });

  const { result } = await client.request('session/new', {
    cwd,
    mcpServers: [],
  });

  return result?.sessionId as string;
}

async function inDirectory(body: (cwd: string) => Promise<void>) {
  const cwd = await mkdtemp(join(tmpdir(), 'chord-acp-client-'));

  try {
    await body(cwd);
  } finally {
    await rm(cwd, { recursive: true });
  }
}

const prompt = (sessionId: string, text: string) => ({
  sessionId,
  prompt: [{ type: 'text', text }],
});

describe('the raw client', () => {
  test('sees every line, a malformed one too, over a stream pair', async () => {
    const { client, output, end, input } = clientOverStreams();
    const writer = output.getWriter();

    await writer.write(new TextEncoder().encode('garbage\n{"id":1}\n'));

    await until(() => client.lines.length === 2);

    expect(client.lines).toEqual(['garbage', '{"id":1}']);

    end();

    const reader = input.getReader();

    expect((await reader.read()).done).toBe(true);

    await writer.close();
    await until(() => client.closed);
  });

  const heardFrom = async (chunks: readonly Uint8Array[]) => {
    const client = new AcpClient(
      () => {},
      (async function* () {
        await Promise.resolve();

        yield* chunks;
      })(),
    );

    await until(() => client.closed);

    return client;
  };

  const bytes = (text: string) => new TextEncoder().encode(text);

  test('keeps what came with no line end, malformed or not', async () => {
    const malformed = await heardFrom([bytes('{}\ngarbage')]);
    const valid = await heardFrom([bytes('{}\n{"id":1}')]);

    expect(malformed.lines).toEqual(['{}', 'garbage']);
    expect(() => malformed.messages).toThrow();
    expect(valid.lines).toEqual(['{}', '{"id":1}']);
  });

  test('a character split across chunks arrives whole', async () => {
    const word = bytes('"é"\n');
    const client = await heardFrom([word.slice(0, 2), word.slice(2)]);

    expect(client.lines).toEqual(['"é"']);
  });

  test('a split character cut off at the end still leaves a line', async () => {
    const client = await heardFrom([bytes('é').slice(0, 1)]);

    expect(client.lines).toEqual(['\uFFFD']);
  });

  test('plays a whole turn against the fake agent', () =>
    inDirectory(async (cwd) => {
      const { client, stdin, group } = onFake();
      const sessionId = await up(client, cwd);
      const { result } = await client.request(
        'session/prompt',
        prompt(sessionId, 'text'),
      );

      expect(result?.stopReason).toBe('end_turn');
      expect(client.said(sessionId).length).toBeGreaterThan(0);

      stdin.end();

      await group.exit;
      await until(() => client.closed);
    }));
});

describe('what the fake agent gained', () => {
  test('--session-id answers every session/new with that id', () =>
    inDirectory(async (cwd) => {
      const { client } = onFake('--session-id', 's1');

      expect(await up(client, cwd)).toBe('s1');
    }));

  test('flood outruns any pipe, and a cancel ends it', () =>
    inDirectory(async (cwd) => {
      const { client } = onFake();
      const sessionId = await up(client, cwd);
      const id = client.send('session/prompt', prompt(sessionId, 'flood'));

      await until(() => client.lines.join('').length > 1024 * 1024);

      client.notify('session/cancel', { sessionId });

      const { result } = await client.answerTo(id);

      expect(result?.stopReason).toBe('cancelled');
    }));

  test('ignorescancel holds through a cancel, until its client goes', () =>
    inDirectory(async (cwd) => {
      const { client, stdin, group } = onFake();
      const sessionId = await up(client, cwd);
      const id = client.send(
        'session/prompt',
        prompt(sessionId, 'ignorescancel'),
      );

      await until(() => client.said(sessionId).includes('Holding on.'));

      client.notify('session/cancel', { sessionId });

      const after = client.send('session/list', {});

      await client.answerTo(after);

      expect(client.messages.some((message) => message.id === id)).toBe(false);

      stdin.end();

      await group.exit;
    }));

  test('--config-in-responses says a set in its answer, and sends no update', () =>
    inDirectory(async (cwd) => {
      const { client } = onFake('--config-in-responses');
      const sessionId = await up(client, cwd);
      const set = await client.request('session/set_config_option', {
        sessionId,
        configId: 'mode',
        value: 'plan',
      });

      expect(set.result?.configOptions).toBeDefined();

      await client.request('session/set_mode', {
        sessionId,
        modeId: 'default',
      });

      expect(
        client
          .updates(sessionId)
          .some((update) => update.sessionUpdate === 'config_option_update'),
      ).toBe(false);
    }));
});
