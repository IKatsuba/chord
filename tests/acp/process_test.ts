import { execFile } from 'node:child_process';
import { expect, test } from 'bun:test';
import process from 'node:process';
import { spawnAgent, STDERR_SETTLE_MS } from '../../src/acp/process.ts';

/** How a test stops what it started, a failed one too. */
const STOP = { exitMs: 100, termMs: 300, killMs: 2000 } as const;

function isAlive(pid: number): Promise<boolean> {
  return new Promise((resolve) => {
    execFile('ps', ['-p', String(pid)], (error) => resolve(error === null));
  });
}

test("an agent's last words are its stderr's tail once stderr has ended (CHD-495)", async () => {
  const agent = await spawnAgent({
    command: ['sh', '-c', 'echo "no credentials" >&2; exit 1'],
    cwd: process.cwd(),
  });

  try {
    await agent.status;
    expect(await agent.lastWords()).toBe('no credentials\n');
  } finally {
    await agent.stop(STOP);
  }
});

test('a stderr that stays open past the cap: the last words so far come at the cap, and the agent stops whole (CHD-495)', async () => {
  // The process it leaves holds stderr open well past the cap.
  const agent = await spawnAgent({
    command: ['sh', '-c', 'echo "out of tokens" >&2; exec sleep 30'],
    cwd: process.cwd(),
  });

  try {
    await new Promise((resolve) => setTimeout(resolve, 100));

    const asked = Date.now();
    const words = await agent.lastWords();
    const waited = Date.now() - asked;

    expect(words).toBe('out of tokens\n');
    expect(waited).toBeGreaterThanOrEqual(STDERR_SETTLE_MS - 50);
    expect(waited).toBeLessThan(STDERR_SETTLE_MS + 1500);
  } finally {
    await agent.stop(STOP);
  }

  expect(await isAlive(agent.pid)).toBe(false);
});
