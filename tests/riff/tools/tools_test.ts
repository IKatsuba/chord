import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import type { FxAgentHostTool } from 'libfx/node';
import { mkdtemp, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { type Finder, openFinder } from '../../../src/platform/fff.ts';
import type { RiffMode } from '../../../src/riff/models.ts';
import {
  ALLOW,
  ALLOW_SESSION,
  DENY,
} from '../../../src/riff/tools/permission.ts';
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
    expect(
      drawn('/p/app', 'read', { path: 'a.ts', offset: 3, limit: 1 }).title,
    ).toBe('Read a.ts:3');
    expect(drawn('/p/app', 'read', { path: '/nowhere/hosts' }).title).toBe(
      'Read /nowhere/hosts',
    );
  });

  test('a read through a link names where it points, as option 2 spells it', () => {
    expect(
      drawn(
        '/p/app',
        'read',
        { path: 'docs/notes.txt', offset: 2, limit: 3 },
        join(homedir(), '.ssh', 'id_rsa'),
      ).title,
    ).toBe('Read docs/notes.txt:2-4 → ~/.ssh/id_rsa');
    expect(drawn('/p/app', 'read', { path: 'a.ts' }, '/p/app/a.ts').title).toBe(
      'Read a.ts',
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

describe("riff's tools ask as the session's mode says", () => {
  let root: string;
  let outside: string;
  let finder: Finder;

  beforeAll(async () => {
    root = await realpath(await mkdtemp(join(tmpdir(), 'chord-riff-ask-')));
    outside = await realpath(
      await mkdtemp(join(tmpdir(), 'chord-riff-ask-out-')),
    );

    await writeFile(join(root, 'a.txt'), 'needle\n');
    await writeFile(join(outside, 'b.txt'), 'far\n');
    await symlink(join(outside, 'b.txt'), join(root, 'link.txt'));

    finder = openFinder(root);
  });

  afterAll(async () => {
    await finder.destroy();
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  });

  /** The tools of a session whose asks are answered by `answers`, in order. */
  const session = (
    mode: RiffMode,
    answers: (string | undefined)[],
    grants = new Set<string>(),
  ) => {
    const asked: {
      title: string;
      options: string[];
      locations?: unknown;
    }[] = [];
    let current = mode;
    const tools = Object.fromEntries(
      riffTools({
        directory: root,
        finder,
        mode: () => current,
        grants,
        ask: (toolCall, options) => {
          asked.push({
            title: toolCall.title ?? '',
            options: options.map(({ optionId }) => optionId),
            locations: toolCall.locations,
          });

          return Promise.resolve(answers.shift());
        },
      }).map((tool) => [tool.name, tool]),
    );
    const run = (name: string, input: unknown, signal?: AbortSignal) =>
      tools[name]!.execute(input, {
        signal: signal ?? new AbortController().signal,
        executionId: 'call',
        sessionId: 'session',
      }) as Promise<string>;

    return {
      asked,
      run,
      grants,
      switchTo: (next: RiffMode) => {
        current = next;
      },
    };
  };

  test('in ask, every call asks with the three options, and Allow runs it', async () => {
    const { asked, run } = session('ask', [ALLOW, ALLOW, ALLOW]);

    expect(await run('read', { path: 'a.txt' })).toBe('1\tneedle');
    expect(await run('list', { pattern: '*.txt' })).toContain('a.txt');
    expect(await run('search', { query: 'needle' })).toBe('a.txt:1: needle');
    // A read's ask names its file in the title alone; list and search
    // keep the directory.
    expect(asked).toStrictEqual([
      {
        title: 'Read a.txt',
        options: [ALLOW, ALLOW_SESSION, DENY],
        locations: [],
      },
      {
        title: 'List *.txt',
        options: [ALLOW, ALLOW_SESSION, DENY],
        locations: [{ path: root }],
      },
      {
        title: 'Search needle',
        options: [ALLOW, ALLOW_SESSION, DENY],
        locations: [{ path: root }],
      },
    ]);
  });

  test('a path with no real path is refused before any ask, and nothing is read', async () => {
    const { asked, run } = session('ask', [ALLOW]);

    await expect(run('read', { path: 'later.txt' })).rejects.toThrow(
      /^later\.txt: no such file$/,
    );
    expect(asked).toStrictEqual([]);
  });

  test('a call is announced before its ask, begins once allowed, never when denied', async () => {
    const order: string[] = [];
    const answers = [ALLOW, DENY];
    const [read] = riffTools({
      directory: root,
      finder,
      mode: () => 'ask',
      ask: () => {
        order.push('ask');

        return Promise.resolve(answers.shift());
      },
      announce: (id) => {
        order.push(`announce ${id}`);
      },
      begin: (id, name) => {
        order.push(`begin ${name} ${id}`);
      },
      show: () => order.push('read'),
    });
    const call = (id: string) =>
      read!.execute(
        { path: 'a.txt' },
        {
          signal: new AbortController().signal,
          executionId: id,
          sessionId: 's',
        },
      ) as Promise<string>;

    await call('one');
    await expect(call('two')).rejects.toThrow('The person denied this call.');
    expect(order).toStrictEqual([
      'announce one',
      'ask',
      'begin read one',
      'read',
      'announce two',
      'ask',
    ]);
  });

  test('Deny, or an ask nobody answers, keeps the call from running', async () => {
    const { run } = session('ask', [DENY, undefined]);

    await expect(run('read', { path: 'a.txt' })).rejects.toThrow(
      'The person denied this call.',
    );
    await expect(run('read', { path: 'a.txt' })).rejects.toThrow(
      'Nobody answered the permission ask; the call did not run.',
    );
  });

  test('a grant for the session is not asked again, and holds after a switch to auto', async () => {
    const { asked, run, switchTo } = session('ask', [ALLOW_SESSION]);
    const far = join(outside, 'b.txt');

    expect(await run('read', { path: far })).toBe('1\tfar');
    expect(await run('read', { path: far, offset: 1 })).toBe('1\tfar');
    switchTo('auto');
    expect(await run('read', { path: far })).toBe('1\tfar');
    expect(asked).toHaveLength(1);
  });

  test('a list grant leaves search asking', async () => {
    const { asked, run } = session('ask', [ALLOW_SESSION, DENY]);

    await run('list', { pattern: '*' });
    await run('list', { pattern: '*.txt' });
    await expect(run('search', { query: 'needle' })).rejects.toThrow(
      'The person denied this call.',
    );
    expect(asked.map(({ title }) => title)).toStrictEqual([
      'List *',
      'Search needle',
    ]);
  });

  test('in auto, reads, lists and searches inside run unasked; a read outside asks', async () => {
    const { asked, run } = session('auto', [DENY, DENY]);

    expect(await run('read', { path: 'a.txt' })).toBe('1\tneedle');
    await run('list', { pattern: '*' });
    await run('search', { query: 'needle' });
    expect(asked).toStrictEqual([]);

    await expect(run('read', { path: join(outside, 'b.txt') })).rejects.toThrow(
      'The person denied this call.',
    );
    // A link inside that points out is outside, and the ask says where.
    await expect(run('read', { path: 'link.txt' })).rejects.toThrow(
      'The person denied this call.',
    );
    expect(asked.map(({ title }) => title)).toStrictEqual([
      `Read ${join(outside, 'b.txt')}`,
      `Read link.txt → ${join(outside, 'b.txt')}`,
    ]);
  });

  test("an abort while the ask waits ends the call with the signal's reason", async () => {
    const controller = new AbortController();
    const reason = new Error('stopped');
    const tools = riffTools({
      directory: root,
      finder,
      mode: () => 'ask',
      ask: () => {
        controller.abort(reason);

        return Promise.resolve(undefined);
      },
    });

    await expect(
      tools[0]!.execute(
        { path: 'a.txt' },
        { signal: controller.signal, executionId: 'call', sessionId: 's' },
      ) as Promise<string>,
    ).rejects.toBe(reason);
  });

  test('a read whose real path changed after it was allowed is refused', async () => {
    await writeFile(join(root, 'moving.txt'), 'here\n');

    const tools = riffTools({
      directory: root,
      finder,
      mode: () => 'ask',
      ask: async () => {
        // The name the person allowed becomes a link to elsewhere.
        await rm(join(root, 'moving.txt'));
        await symlink(join(outside, 'b.txt'), join(root, 'moving.txt'));

        return ALLOW;
      },
    });

    await expect(
      tools[0]!.execute(
        { path: 'moving.txt' },
        {
          signal: new AbortController().signal,
          executionId: 'call',
          sessionId: 's',
        },
      ) as Promise<string>,
    ).rejects.toThrow('the file changed while it was opened; read it again');
  });
});
