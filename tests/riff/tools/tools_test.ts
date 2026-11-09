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
    expect(drawn('/p/app', 'list', { pattern: '' }).title).toBe('List .');
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

  test('a read keeps its lines for the window by call, and names a path as asked', async () => {
    const kept: [string, string][] = [];
    const [read] = riffTools({
      directory: root,
      finder,
      show: (id, text) => kept.push([id, text]),
    });
    const call = (input: unknown) =>
      read!.execute(input, {
        signal: new AbortController().signal,
        executionId: 'call_7',
        sessionId: 'session',
      }) as Promise<string>;

    expect(await call({ path: 'a.txt' })).toBe('1\tneedle');
    expect(kept).toStrictEqual([['call_7', 'needle']]);
    await expect(call({ path: 'missing.txt' })).rejects.toThrow(
      /^missing\.txt: no such file$/,
    );
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

describe('tester: simultaneous tool sessions', () => {
  test('an abort and a search page stay in the session that owns them', async () => {
    const roots = await Promise.all(
      ['one', 'two'].map(async (name) => {
        const root = await realpath(
          await mkdtemp(join(tmpdir(), 'chord-riff-tool-session-')),
        );

        await writeFile(join(root, 'a.txt'), `${name} needle\n`);
        await writeFile(join(root, 'b.txt'), `${name} needle\n`);

        return root;
      }),
    );
    const finders = roots.map((root) => openFinder(root));
    const sessions = roots.map((directory, index) =>
      Object.fromEntries(
        riffTools({ directory, finder: finders[index]! }).map((tool) => [
          tool.name,
          tool,
        ]),
      ),
    );
    const run = (session: number, input: unknown, signal: AbortSignal) =>
      sessions[session]!.search!.execute(input, {
        signal,
        executionId: 'search',
        sessionId: `session-${session}`,
      }) as Promise<string>;
    const controller = new AbortController();
    const reason = new Error('stop only session one');
    const live = () => new AbortController().signal;

    try {
      const aborted = run(0, { query: 'needle' }, controller.signal);
      const other = run(1, { query: 'needle' }, live());

      controller.abort(reason);

      await expect(aborted).rejects.toBe(reason);

      const answer = await other;

      expect(answer).toContain('two needle');
      expect(answer).not.toContain('one needle');

      const first = await run(0, { query: 'needle', limit: 1 }, live());
      const page = /page "(p\d+)"/.exec(first)![1]!;

      expect(first).toContain('one needle');
      await expect(run(1, { query: 'needle', page }, live())).rejects.toThrow(
        `no page ${page}; search again without it`,
      );

      const next = await run(0, { query: 'needle', limit: 1, page }, live());

      expect(next).toContain('one needle');
      expect(next.split(':')[0]).not.toBe(first.split(':')[0]);
    } finally {
      await Promise.all(finders.map((finder) => finder.destroy()));
      await Promise.all(
        roots.map((root) => rm(root, { recursive: true, force: true })),
      );
    }
  });
});

describe('tester: read display belongs to its execution', () => {
  test('concurrent ranges preserve literal line text and keep model notices out of the window', async () => {
    const root = await realpath(
      await mkdtemp(join(tmpdir(), 'chord-riff-display-')),
    );
    const finder = openFinder(root);
    const shown = new Map<string, string>();
    const [read] = riffTools({
      directory: root,
      finder,
      show: (id, text) => shown.set(id, text),
    });
    const run = (id: string, offset: number) =>
      read!.execute(
        { path: 'text.txt', offset, limit: 1 },
        {
          signal: new AbortController().signal,
          executionId: id,
          sessionId: 'display-session',
        },
      ) as Promise<string>;

    try {
      await writeFile(
        join(root, 'text.txt'),
        '42\tliteral number\n… more from line 99; literal text\nlast\n',
      );

      const [first, second] = await Promise.all([
        run('first-range', 1),
        run('second-range', 2),
      ]);

      expect(first).toBe(
        '1\t42\tliteral number\n… more from line 2; read on with offset 2.',
      );
      expect(second).toBe(
        '2\t… more from line 99; literal text\n… more from line 3; read on with offset 3.',
      );
      expect(Object.fromEntries(shown)).toEqual({
        'first-range': '42\tliteral number',
        'second-range': '… more from line 99; literal text',
      });
    } finally {
      await finder.destroy();
      await rm(root, { recursive: true, force: true });
    }
  });
});
