import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import type { FxAgentHostTool } from 'libfx/node';
import { mkdtemp, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { type Finder, openFinder } from '../../../src/platform/fff.ts';
import { drawn, riffTools } from '../../../src/riff/tools/tools.ts';

describe('how riff draws a call', () => {
  test('read: verb-first title with its range, kind read, its file as location', () => {
    expect(drawn('/p/app', 'read', { path: 'src/a.ts' })).toEqual({
      title: 'Read src/a.ts',
      kind: 'read',
      locations: [{ path: '/p/app/src/a.ts' }],
    });
    expect(
      drawn('/p/app', 'read', { path: 'src/a.ts', offset: 10, limit: 31 }),
    ).toEqual({
      title: 'Read src/a.ts:10-40',
      kind: 'read',
      locations: [{ path: '/p/app/src/a.ts', line: 10 }],
    });
    expect(drawn('/p/app', 'read', { path: 'a.ts', offset: 5 }).title).toBe(
      'Read a.ts:5',
    );
    expect(drawn('/p/app', 'read', { path: 'a.ts', limit: 5 }).title).toBe(
      'Read a.ts:1-5',
    );
    expect(drawn('/p/app', 'read', { path: '/etc/hosts' }).title).toBe(
      'Read /etc/hosts',
    );
  });

  test('list and search: verb-first, kind search, the directory as location', () => {
    expect(drawn('/p/app', 'list', { pattern: 'src/**/*.ts' })).toEqual({
      title: 'List src/**/*.ts',
      kind: 'search',
      locations: [{ path: '/p/app' }],
    });
    expect(drawn('/p/app', 'search', { query: 'welcome' })).toEqual({
      title: 'Search welcome',
      kind: 'search',
      locations: [{ path: '/p/app' }],
    });
  });

  test('an input it cannot read, or a tool it does not know, by name', () => {
    expect(drawn('/p/app', 'read', undefined)).toEqual({
      title: 'Read',
      kind: 'read',
    });
    expect(drawn('/p/app', 'mark', {})).toEqual({
      title: 'mark',
      kind: 'other',
    });
  });
});

describe("riff's tools as libfx takes them", () => {
  let root: string;
  let finder: Finder;
  let tools: Record<string, FxAgentHostTool>;

  beforeAll(async () => {
    root = await realpath(await mkdtemp(join(tmpdir(), 'chord-riff-tools-')));

    await writeFile(join(root, 'a.txt'), 'needle\n');

    finder = openFinder(root);
    tools = Object.fromEntries(
      riffTools({ directory: root, finder }).map((tool) => [tool.name, tool]),
    );
  });

  afterAll(async () => {
    await finder.destroy();
    await rm(root, { recursive: true, force: true });
  });

  const run = (name: string, input: unknown, signal?: AbortSignal) =>
    tools[name]!.execute(input, {
      signal: signal ?? new AbortController().signal,
      executionId: 'call',
      sessionId: 'session',
    }) as Promise<string>;

  test('three idempotent tools that write nothing, each with a JSON Schema', () => {
    expect(Object.keys(tools)).toEqual(['read', 'list', 'search']);

    for (const tool of Object.values(tools)) {
      expect(tool.idempotent).toBe(true);
      expect(tool.writes).toBe(false);
      expect(tool.inputSchema).toMatchObject({
        type: 'object',
        additionalProperties: false,
      });
    }
  });

  test('read resolves its path against the session directory', async () => {
    expect(await run('read', { path: 'a.txt' })).toBe('1\tneedle');
  });

  test('list and search run on the session finder', async () => {
    expect(await run('list', { pattern: '*.txt' })).toBe('a.txt');
    expect(await run('search', { query: 'needle' })).toBe('a.txt:1: needle');
  });

  test('an input outside the schema is refused with why', async () => {
    await expect(run('read', { file: 'a.txt' })).rejects.toThrow(
      /^invalid input: /,
    );
  });

  test('each tool takes the call signal', async () => {
    const controller = new AbortController();
    const reason = new Error('stopped');

    controller.abort(reason);

    for (const [name, input] of [
      ['read', { path: 'a.txt' }],
      ['list', { pattern: '*' }],
      ['search', { query: 'needle' }],
    ] as const) {
      await expect(run(name, input, controller.signal)).rejects.toBe(reason);
    }
  });
});
