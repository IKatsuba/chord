import { describe, expect, test } from 'bun:test';
import type { ToolCallUpdate } from '@agentclientprotocol/sdk/unstable';
import { mkdtemp, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { openFinder } from '../../../src/platform/fff.ts';
import { LIMITS } from '../../../src/riff/tools/limits.ts';
import { ALLOW_SESSION, DENY } from '../../../src/riff/tools/permission.ts';
import { shell } from '../../../src/riff/tools/shell.ts';
import { riffTools } from '../../../src/riff/tools/tools.ts';

const live = () => new AbortController().signal;
const meta = (update: ToolCallUpdate, key: string) =>
  update._meta?.[key] as
    | {
        data?: string;
        terminal_id?: string;
        exit_code?: number | null;
        signal?: string | null;
      }
    | undefined;

async function directory() {
  return realpath(await mkdtemp(join(tmpdir(), 'chord-riff-shell-')));
}

describe('riff shell execution', () => {
  test('streams both outputs before exit and returns the real exit code', async () => {
    const root = await directory();
    const updates: ToolCallUpdate[] = [];
    let sawFirst = false;

    try {
      const result = await shell(
        root,
        {
          command:
            'printf first; printf error >&2; while test ! -e gate; do sleep 0.01; done; printf second; exit 7',
        },
        live(),
        'shell-1',
        async (update) => {
          updates.push(update);

          if (meta(update, 'terminal_output_delta')?.data?.includes('first')) {
            sawFirst = true;

            await writeFile(join(root, 'gate'), '');
          }
        },
      );

      expect(sawFirst).toBe(true);
      expect(result.text).toContain('first');
      expect(result.text).toContain('second');
      expect(result.text).toContain('error');
      expect(result.text).toContain('Exit code 7');
      expect(result.isError).toBe(true);
      expect(updates[0]).toMatchObject({
        content: [{ type: 'terminal', terminalId: 'shell-1' }],
        _meta: { terminal_info: { terminal_id: 'shell-1', cwd: root } },
      });
      expect(meta(updates.at(-1)!, 'terminal_exit')).toEqual({
        terminal_id: 'shell-1',
        exit_code: 7,
        signal: null,
      });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test('abort kills the shell group including its child sleep and preserves received output', async () => {
    const root = await directory();
    const controller = new AbortController();
    const updates: ToolCallUpdate[] = [];
    let child = 0;

    try {
      await expect(
        shell(
          root,
          { command: "sleep 30 & child=$!; printf 'child:%s\\n' $child; wait" },
          controller.signal,
          'abort',
          (update) => {
            updates.push(update);

            const data = meta(update, 'terminal_output_delta')?.data ?? '';
            const match = /child:(\d+)/.exec(data);

            if (match !== null) {
              child = Number(match[1]);

              controller.abort(new Error('stopped by person'));
            }
          },
        ),
      ).rejects.toThrow('stopped by person');
      expect(child).toBeGreaterThan(0);
      expect(() => process.kill(child, 0)).toThrow();
      expect(
        updates.some((update) =>
          meta(update, 'terminal_output_delta')?.data?.includes('child:'),
        ),
      ).toBe(true);
      expect(meta(updates.at(-1)!, 'terminal_exit')?.exit_code).toBeNull();
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test('model byte and line caps leave the terminal stream complete', async () => {
    const root = await directory();

    try {
      for (const command of [
        "printf '%270000s' x",
        'i=0; while test $i -lt 2100; do printf "line\\n"; i=$((i+1)); done',
      ]) {
        let streamed = 0;
        const result = await shell(
          root,
          { command },
          live(),
          'capped',
          (update) => {
            streamed +=
              meta(update, 'terminal_output_delta')?.data?.length ?? 0;
          },
        );

        expect(result.text).toContain('output truncated');
        expect(result.text).toContain('Exit code 0');
        expect(result.isError).toBe(false);
        expect(result.text.length).toBeLessThanOrEqual(LIMITS.shellBytes + 100);
        expect(streamed).toBeGreaterThan(result.text.length);
      }
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test('an exact session grant admits only that command in ask and auto', async () => {
    const root = await directory();
    const finder = openFinder(root);
    let asks = 0;
    let mode: 'ask' | 'auto' = 'ask';
    const tools = riffTools({
      directory: root,
      finder,
      grants: new Set(),
      mode: () => mode,
      ask: () => Promise.resolve(++asks === 1 ? ALLOW_SESSION : DENY),
    });
    const tool = tools.find((tool) => tool.name === 'shell')!;
    const run = (command: string) =>
      tool.execute(
        { command },
        { signal: live(), executionId: 'shell', sessionId: 's' },
      ) as Promise<unknown>;

    try {
      await run('ls');
      await run('ls');

      mode = 'auto';

      await run('ls');
      await expect(run('ls -la')).rejects.toThrow('denied');
      expect(asks).toBe(2);
    } finally {
      await finder.destroy();
      await rm(root, { recursive: true, force: true });
    }
  });
});
