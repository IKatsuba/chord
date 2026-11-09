import { describe, expect, test } from 'bun:test';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { serveFakeChat } from '../../scripts/dev/release/fake_chat.ts';
import { riffProblems } from '../../scripts/dev/release/selftest.ts';
import { RIFF_SELFTEST_FLAG } from '../../src/platform/riff_selftest.ts';

const MAIN = fileURLToPath(new URL('../../src/main.tsx', import.meta.url));

/**
 * chord from source with `args`, its output once it has gone: killed and
 * reaped at `deadline` ms, so a hung turn never outlives its test.
 */
async function chord(
  args: readonly string[],
  deadline = 45_000,
): Promise<{ code: number | null; out: string; err: string; killed: boolean }> {
  const child = spawn(process.execPath, [MAIN, ...args], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const closed = new Promise<number | null>((done) =>
    child.once('close', done),
  );
  let out = '';
  let err = '';
  let killed = false;

  child.stdout.setEncoding('utf8').on('data', (text: string) => {
    out += text;
  });

  child.stderr.setEncoding('utf8').on('data', (text: string) => {
    err += text;
  });

  const timer = setTimeout(() => {
    killed = true;

    child.kill('SIGKILL');
  }, deadline);

  try {
    return { code: await closed, out, err, killed };
  } finally {
    clearTimeout(timer);

    if (child.exitCode === null && child.signalCode === null) {
      child.kill('SIGKILL');
      await closed;
    }
  }
}

describe('--riff-selftest', () => {
  test('runs a libfx turn on native and on Wasm and an fff grep, as the self-test checks', async () => {
    const fake = serveFakeChat();

    try {
      const ran = await chord([RIFF_SELFTEST_FLAG, fake.url]);

      expect(ran.err).toBe('');
      expect(ran.killed).toBeFalse();
      expect(ran.code).toBe(0);
      expect(
        riffProblems(JSON.parse(ran.out) as object, fake.requests()),
      ).toBeUndefined();
    } finally {
      await fake.stop();
    }
  }, 60_000);

  test('a turn that never gets an answer is killed and reaped at its deadline', async () => {
    // Takes requests and never answers them.
    const silent = Bun.serve({
      hostname: '127.0.0.1',
      port: 0,
      fetch: () => new Promise<Response>(() => {}),
    });

    try {
      const ran = await chord(
        [RIFF_SELFTEST_FLAG, `http://localhost:${silent.port}/v1`],
        3000,
      );

      expect(ran.killed).toBeTrue();
      expect(ran.code).toBeNull();
    } finally {
      await silent.stop(true);
    }
  }, 30_000);

  test('no help lists it', async () => {
    const help = await chord(['--help']);

    expect(help.code).toBe(0);
    expect(help.out).not.toContain(RIFF_SELFTEST_FLAG);
  });
});

describe('CHD-603 U4 tester: isolated selftest processes', () => {
  test('two processes complete both turns against their own fake provider', async () => {
    const first = serveFakeChat();
    const second = serveFakeChat();

    try {
      const results = await Promise.all([
        chord([RIFF_SELFTEST_FLAG, first.url]),
        chord([RIFF_SELFTEST_FLAG, second.url]),
      ]);

      for (const [index, fake] of [first, second].entries()) {
        const ran = results[index]!;

        expect(ran.killed).toBeFalse();
        expect(ran.code).toBe(0);
        expect(ran.err).toBe('');
        expect(fake.requests()).toBe(4);
        expect(
          riffProblems(JSON.parse(ran.out) as object, fake.requests()),
        ).toBeUndefined();
      }
    } finally {
      await first.stop();
      await second.stop();
    }
  }, 60_000);

  test('a missing fake URL fails before any turn is started', async () => {
    const ran = await chord([RIFF_SELFTEST_FLAG]);

    expect(ran.killed).toBeFalse();
    expect(ran.code).not.toBe(0);
    expect(ran.out).toBe('');
    expect(ran.err).toContain(
      `${RIFF_SELFTEST_FLAG} takes the fake server's base URL`,
    );
  });
});
