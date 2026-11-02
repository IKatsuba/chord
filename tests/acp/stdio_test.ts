import { afterEach, describe, expect, test } from 'bun:test';
import assert from 'node:assert';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import type { AnyMessage } from '@agentclientprotocol/sdk/unstable';
import {
  outputStream,
  seeingWrites,
  type WritableOutput,
} from '../../src/acp/stdio.ts';
import {
  execPath,
  type GroupProcess,
  spawnGroup,
} from '../../src/platform/process.ts';
import { until } from '../session/conversation_fake.ts';

const CHILD = fileURLToPath(new URL('./stdio_child.ts', import.meta.url));
const MIB = 1024 * 1024;
const started: GroupProcess[] = [];

afterEach(() => {
  for (const group of started.splice(0)) {
    group.signal('SIGKILL');
  }
});

function run(shell: string, mode: string): GroupProcess {
  const group = spawnGroup('sh', ['-c', shell, 'sh', execPath(), CHILD, mode], {
    cwd: process.cwd(),
    stdin: 'pipe',
    stdout: 'pipe',
    stderr: 'pipe',
  });

  started.push(group);

  return group;
}

describe('the stream on stdout', () => {
  test('a pipe nobody reads: the write stays pending, the loop runs, EOF exits', async () => {
    // `sleep` holds the pipe's read end and never reads it.
    const group = run('"$@" | sleep 60', 'blocked');
    let seen = '';

    group.child.stderr?.setEncoding('utf8').on('data', (text: string) => {
      seen += text;
    });

    await until(() => seen.split('tick').length > 5);

    expect(seen).not.toContain('written');

    group.child.stdin?.end();

    await until(() => seen.includes('eof'));

    expect(seen).not.toContain('written');
  });

  test('exit after 1 MiB to a slow reader delivers every byte', async () => {
    // Fails on `Writable.toWeb(process.stdout)`, which settles before the bytes
    // have gone, so `process.exit` drops them.
    const group = run('"$@"', 'deliver');
    let bytes = 0;

    const stdout = group.child.stdout;

    assert(stdout !== null);

    for await (const chunk of stdout) {
      bytes += (chunk as Uint8Array).length;

      // Slower than the writer, so the pipe stays full.
      await new Promise((resolve) => setTimeout(resolve, 1));
    }

    expect(bytes).toBe(MIB);
    expect((await group.exit).code).toBe(0);
  });

  test('a failed write rejects', async () => {
    const output: WritableOutput = {
      write: (_, callback) => callback(new Error('EPIPE')),
    };
    const writer = outputStream(output).getWriter();

    await expect(writer.write(new Uint8Array(1))).rejects.toThrow('EPIPE');
  });
});

function held() {
  const writes: Array<{ message: AnyMessage; done: () => void }> = [];
  const failing = { current: false };
  const writable = new WritableStream<AnyMessage>({
    write: (message) =>
      new Promise<void>((resolve, reject) => {
        if (failing.current) {
          reject(new Error('EPIPE'));

          return;
        }

        writes.push({ message, done: resolve });
      }),
  });

  return {
    writes,
    failing,
    seen: seeingWrites({ writable, readable: new ReadableStream() }),
  };
}

const answer = (id: number): AnyMessage => ({
  jsonrpc: '2.0',
  id,
  result: {},
});

function settles(promise: Promise<void>): Promise<boolean> {
  return Promise.race([
    promise.then(() => true),
    new Promise<boolean>((resolve) => setTimeout(() => resolve(false), 10)),
  ]);
}

describe('seeing writes', () => {
  test('nothing expected is drained at once', async () => {
    const { seen } = held();

    expect(await settles(seen.drained())).toBe(true);
  });

  test('drained waits for every expected answer to be written', async () => {
    const { seen, writes } = held();
    const writer = seen.stream.writable.getWriter();

    seen.expect(1);
    seen.expect(2);

    const drained = seen.drained();

    void writer.write(answer(1));

    await until(() => writes.length === 1);

    expect(await settles(drained)).toBe(false);

    writes[0]?.done();

    void writer.write(answer(2));

    await until(() => writes.length === 2);

    expect(await settles(drained)).toBe(false);

    writes[1]?.done();

    expect(await settles(drained)).toBe(true);
  });

  test('expect settles on its own answer, and failed says when one could not go', async () => {
    const { seen, writes, failing } = held();
    const writer = seen.stream.writable.getWriter();
    let heard = false;

    void seen.expect(1).then(() => {
      heard = true;
    });

    void writer.write(answer(1));

    await until(() => writes.length === 1);

    expect(heard).toBe(false);

    writes[0]?.done();

    await until(() => heard);

    expect(seen.failed()).toBe(false);

    failing.current = true;

    await expect(writer.write(answer(2))).rejects.toThrow('EPIPE');

    expect(seen.failed()).toBe(true);
  });

  test('a request or a notification with the same id is not the answer', async () => {
    const { seen, writes } = held();
    const writer = seen.stream.writable.getWriter();

    seen.expect(1);

    void writer.write({ jsonrpc: '2.0', id: 1, method: 'x' });

    await until(() => writes.length === 1);

    writes[0]?.done();

    expect(await settles(seen.drained())).toBe(false);
  });

  test('a failed write gives up rather than waits', async () => {
    const { seen, failing } = held();
    const writer = seen.stream.writable.getWriter();

    seen.expect(1);

    const drained = seen.drained();

    failing.current = true;

    await expect(writer.write(answer(2))).rejects.toThrow('EPIPE');

    expect(await settles(drained)).toBe(true);
  });

  test('a close gives up too', async () => {
    const { seen } = held();
    const writer = seen.stream.writable.getWriter();

    seen.expect(1);

    const drained = seen.drained();

    await writer.close();

    expect(await settles(drained)).toBe(true);
  });
});

describe('CHD-574 tester: distinct response lifetimes', () => {
  test('numeric and string request ids settle independently, including an error', async () => {
    const { seen, writes } = held();
    const writer = seen.stream.writable.getWriter();

    seen.expect(1);
    seen.expect('1');

    const drained = seen.drained();
    const first = writer.write(answer(1));

    await until(() => writes.length === 1);

    writes[0]?.done();

    await first;

    expect(await settles(drained)).toBe(false);

    const second = writer.write({
      jsonrpc: '2.0',
      id: '1',
      error: { code: -32603, message: 'closing' },
    });

    await until(() => writes.length === 2);

    writes[1]?.done();

    await second;
    await drained;

    writer.releaseLock();
  });

  test('a later expected answer starts a fresh drain after the first settled', async () => {
    const { seen, writes } = held();
    const writer = seen.stream.writable.getWriter();

    for (const id of [1, 2]) {
      seen.expect(id);

      const drained = seen.drained();
      const written = writer.write(answer(id));

      await until(() => writes.length === id);

      expect(await settles(drained)).toBe(false);

      writes[id - 1]?.done();

      await written;
      await drained;
    }

    writer.releaseLock();
  });

  test('abort releases a drain while no answer was written', async () => {
    const { seen } = held();
    const writer = seen.stream.writable.getWriter();

    seen.expect('unanswered');

    const drained = seen.drained();

    await writer.abort(new Error('client gone'));
    await drained;

    writer.releaseLock();
  });
});
