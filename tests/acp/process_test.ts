import { execFile } from 'node:child_process';
import { describe, expect, test } from 'bun:test';
import process from 'node:process';
import {
  spawnAgent,
  STDERR_LINE_MAX,
  STDERR_SETTLE_MS,
} from '../../src/acp/process.ts';

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

/** The end of the stderr of an agent that runs `script` in sh and exits. */
async function stderrEndOf(script: string) {
  const agent = await spawnAgent({
    command: ['sh', '-c', script],
    cwd: process.cwd(),
  });

  try {
    await agent.status;
    await agent.lastWords();

    return agent.stderrEnd();
  } finally {
    await agent.stop(STOP);
  }
}

test('the end of its stderr is its last non-empty lines as they came, indents kept, and how many came before (CHD-454)', async () => {
  expect(
    await stderrEndOf(
      'printf "a\\n\\n  b" >&2; printf " still b\\n" >&2; i=0; while [ $i -lt 300 ]; do echo "    at frame $i" >&2; i=$((i+1)); done; exit 1',
    ),
  ).toStrictEqual({
    lines: [
      '    at frame 294',
      '    at frame 295',
      '    at frame 296',
      '    at frame 297',
      '    at frame 298',
      '    at frame 299',
    ],
    cut: 296,
  });
});

test('an unfinished last line is a line of the end, and one past the bound is cut there and marked (CHD-454)', async () => {
  const end = await stderrEndOf(
    `printf "  first\\n" >&2; printf "%02000d\\n" 0 >&2; printf "Error: no newline" >&2; exit 1`,
  );

  expect(end.cut).toBe(0);
  expect(end.lines[0]).toBe('  first');
  expect(end.lines[1]).toBe(`${'0'.repeat(STDERR_LINE_MAX)}…`);
  expect(end.lines[2]).toBe('Error: no newline');
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

describe('CHD-495 tester: inherited stderr has a bounded lifetime', () => {
  test('an exited shell leaves a grandchild holding stderr, but draining and stopping remain bounded', async () => {
    const agent = await spawnAgent({
      command: [
        'sh',
        '-c',
        'sleep 30 >/dev/null & echo $!; echo "last diagnostic" >&2; exit 1',
      ],
      cwd: process.cwd(),
    });
    let descendant: number | undefined;

    try {
      descendant = Number(await new Response(agent.stdout).text());

      expect(descendant).toBeGreaterThan(0);
      await agent.status;
      expect(await isAlive(agent.pid)).toBe(false);
      expect(await isAlive(descendant)).toBe(true);

      const started = performance.now();

      expect(await agent.lastWords()).toBe('last diagnostic\n');
      expect(performance.now() - started).toBeGreaterThanOrEqual(
        STDERR_SETTLE_MS - 50,
      );
      expect(performance.now() - started).toBeLessThan(2500);
    } finally {
      await agent.stop(STOP);
    }

    expect(await isAlive(agent.pid)).toBe(false);

    if (descendant !== undefined) {
      const deadline = Date.now() + 2000;

      while ((await isAlive(descendant)) && Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 10));
      }

      expect(await isAlive(descendant)).toBe(false);
    }
  });
});
