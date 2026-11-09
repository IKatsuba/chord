import { describe, expect, test } from 'bun:test';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { serveFakeChat } from '../../scripts/dev/release/fake_chat.ts';
import { riffProblems } from '../../scripts/dev/release/selftest.ts';
import { RIFF_SELFTEST_FLAG } from '../../src/platform/riff_selftest.ts';

const MAIN = fileURLToPath(new URL('../../src/main.tsx', import.meta.url));

/** chord from source with `args`, its output once it has gone. */
function chord(
  args: readonly string[],
): Promise<{ code: number | null; out: string; err: string }> {
  const child = spawn(process.execPath, [MAIN, ...args], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '';
  let err = '';

  child.stdout.setEncoding('utf8').on('data', (text: string) => {
    out += text;
  });

  child.stderr.setEncoding('utf8').on('data', (text: string) => {
    err += text;
  });

  return new Promise((done) =>
    child.once('close', (code) => done({ code, out, err })),
  );
}

describe('--riff-selftest', () => {
  test('runs a libfx turn on native and on Wasm and an fff grep, as the self-test checks', async () => {
    const fake = serveFakeChat();

    try {
      const ran = await chord([RIFF_SELFTEST_FLAG, fake.url]);

      expect(ran.err).toBe('');
      expect(ran.code).toBe(0);
      expect(
        riffProblems(JSON.parse(ran.out) as object, fake.requests()),
      ).toBeUndefined();
    } finally {
      await fake.stop();
    }
  }, 60_000);

  test('no help lists it', async () => {
    const help = await chord(['--help']);

    expect(help.code).toBe(0);
    expect(help.out).not.toContain(RIFF_SELFTEST_FLAG);
  });
});
