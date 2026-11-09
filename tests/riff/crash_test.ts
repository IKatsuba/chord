import { afterEach, describe, expect, test } from 'bun:test';
import { ndJsonStream } from '@agentclientprotocol/sdk/unstable';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { libfxBackend } from '../../src/platform/libfx.ts';
import { connectRiff, INTERRUPTED } from '../../src/riff/adapter.ts';
import { AcpClient, clientOverStreams } from '../fixtures/acp_client.ts';
import { serveFakeChat } from '../fixtures/riff/fake_chat.ts';
import { notFound } from '../../src/not_found.ts';

const CHILD = join(import.meta.dir, '../fixtures/riff/crash_child.ts');

const cleanups: (() => Promise<void>)[] = [];

afterEach(async () => {
  for (const cleanup of cleanups.splice(0).reverse()) {
    await cleanup();
  }
});

/** Until `file` exists, polling: the child publishes it whole. */
async function published(file: string): Promise<string> {
  for (;;) {
    try {
      return await readFile(file, 'utf8');
    } catch (error) {
      if (!notFound(error)) {
        throw error;
      }
    }

    await Bun.sleep(20);
  }
}

/**
 * The owner's T2 (CHD-485): reopening cancels a turn a dead process left
 * open, so none of its model requests or tools run. It holds for a turn whose
 * call has effects, as edit, write and shell have: libfx stores the turn
 * before such a call runs. The owner accepted the narrow case left: a crash
 * after a prompt is accepted but before its turn is journaled can run that
 * prompt once on reopen, with one model request and read-only, idempotent
 * calls only; edits, writes and shell never rerun.
 */
describe('a turn a crashed riff left open (T2)', () => {
  test('reopening cancels it: no model request and no tool run of the dead turn', async () => {
    const fake = serveFakeChat();
    const state = await mkdtemp(join(tmpdir(), 'chord-riff-crash-'));
    const ready = join(state, 'ready');

    cleanups.push(async () => {
      await fake.stop();
      await rm(state, { recursive: true, force: true });
    });

    const child = spawn(
      process.execPath,
      [CHILD, join(state, 'state'), fake.url, ready],
      { stdio: ['pipe', 'pipe', 'inherit'] },
    );

    cleanups.push(async () => {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill('SIGKILL');
        await new Promise((resolve) => child.once('exit', resolve));
      }
    });

    const dead = new AcpClient((line) => child.stdin.write(line), child.stdout);

    await dead.request('initialize', { protocolVersion: 1 });

    const created = await dead.request('session/new', {
      cwd: process.cwd(),
      mcpServers: [],
    });
    const sessionId = created.result?.['sessionId'] as string;

    dead.send('session/prompt', {
      sessionId,
      prompt: [{ type: 'text', text: 'call the tool' }],
    });

    expect(Number(await published(ready))).toBe(child.pid ?? -1);

    child.kill('SIGKILL');
    await new Promise((resolve) => child.once('exit', resolve));

    const requests = fake.requests.length;
    const runs: string[] = [];
    const pair = clientOverStreams();
    const riff = connectRiff(ndJsonStream(pair.output, pair.input), {
      version: '0.0.0',
      provider: { baseUrl: fake.url },
      backend: await libfxBackend(),
      stateDir: join(state, 'state'),
      tools: [
        {
          name: 'mark',
          description: 'Marks the test.',
          inputSchema: { type: 'object', properties: {} },
          idempotent: false,
          writes: true,
          execute: (_input, { executionId }) => {
            runs.push(executionId);

            return 'marked';
          },
        },
      ],
    });

    cleanups.push(async () => {
      pair.end();
      await riff.finished;
    });

    await pair.client.request('initialize', { protocolVersion: 1 });

    const resumed = await pair.client.request('session/resume', {
      sessionId,
      cwd: process.cwd(),
      mcpServers: [],
    });

    expect(resumed.error).toBeUndefined();
    expect(fake.requests.length - requests).toBe(0);
    expect(runs).toStrictEqual([]);
    expect(pair.client.said(sessionId)).toBe(INTERRUPTED);
    // main: the open call is as libfx leaves it. For a call with effects,
    // libfx ends it failed itself, and riff sends that on; riff adds only
    // the line.
    expect(
      pair.client
        .updates(sessionId)
        .filter(({ sessionUpdate }) => sessionUpdate === 'tool_call_update'),
    ).toStrictEqual([
      expect.objectContaining({ toolCallId: 'call_mark', status: 'failed' }),
    ]);
  });
});
