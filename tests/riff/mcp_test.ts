import { afterEach, describe, expect, test } from 'bun:test';
import type { McpServer } from '@agentclientprotocol/sdk/unstable';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { mkdtemp, readFile, realpath, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  connectSdk,
  mcpTitle,
  type McpTools,
  openMcp,
  PREFIX_CHARS,
  prefixes,
  renamed,
  skippedNote,
  transportOf,
} from '../../src/riff/mcp.ts';
import { serveFakeMcp } from '../fixtures/riff/fake_mcp.ts';
import { until } from '../session/conversation_fake.ts';

const STDIO = join(import.meta.dir, '..', 'fixtures', 'riff', 'mcp_stdio.ts');
const cleanups: (() => Promise<void>)[] = [];

afterEach(async () => {
  for (const cleanup of cleanups.splice(0).reverse()) {
    await cleanup();
  }
});

function stdio(name: string, mode: string, pidFile?: string): McpServer {
  return {
    name,
    command: process.execPath,
    args: [STDIO, mode],
    env: pidFile === undefined ? [] : [{ name: 'PID_FILE', value: pidFile }],
  };
}

async function opened(
  servers: McpServer[],
  timeout?: number,
): Promise<McpTools> {
  const tools = await openMcp(
    servers,
    process.cwd(),
    connectSdk('1.2.3'),
    timeout,
  );

  cleanups.push(() => tools.close());

  return tools;
}

const call = (tools: McpTools, name: string, input: unknown) =>
  tools.tools
    .find((tool) => tool.name === name)!
    .execute(input, {
      signal: new AbortController().signal,
      executionId: 'call',
      sessionId: 'session',
    });

describe('riff MCP prefixes', () => {
  test("a server's name made libfx's, at most 27 characters, _2 and _3 on a clash", () => {
    expect(
      prefixes(['notes', 'my notes', 'my_notes', 'my.notes', 'x'.repeat(40)]),
    ).toEqual([
      'notes__',
      'my_notes__',
      'my_notes_2__',
      'my_notes_3__',
      `${'x'.repeat(25)}__`,
    ]);

    const long = prefixes(['y'.repeat(40), 'y'.repeat(41)]);

    expect(long[1]).toBe(`${'y'.repeat(23)}_2__`);

    for (const prefix of long) {
      expect(prefix.length).toBeLessThanOrEqual(PREFIX_CHARS);
    }
  });

  test('the title keeps the original names', () => {
    expect(mcpTitle({ server: 'my notes', tool: 'save.note' })).toBe(
      'mcp__my notes__save.note',
    );
  });

  test('a name libfx would change is refused, not guessed at', () => {
    expect(
      renamed(
        'n__',
        [{ name: 'a' }, { name: 'b' }],
        [{ name: 'n__a' }, { name: 'n__b' }],
      ),
    ).toBe(undefined);
    expect(renamed('n__', [{ name: 'a b' }], [{ name: 'n__a_b' }])).toContain(
      '"a b"',
    );
    expect(
      renamed('n__', [{ name: 'a'.repeat(70) }], [{ name: 'n__a' }]),
    ).toContain('cannot call');
  });
});

describe("chord's own MCP server for riff", () => {
  test('its read-only tools are idempotent, by the name the server reports and nothing else', async () => {
    const own = serveFakeMcp('chord', 'chord');
    const lookalike = serveFakeMcp('not-chord', 'chord');

    cleanups.push(
      () => own.close(),
      () => lookalike.close(),
    );

    // The server chord gives may go as `chord-2`; a user's may take `chord`.
    const tools = await opened([
      { type: 'http', name: 'chord-2', url: own.url, headers: [] },
      { type: 'http', name: 'chord', url: lookalike.url, headers: [] },
    ]);

    expect(
      tools.tools
        .filter((tool) => tool.idempotent)
        .map((tool) => tool.name)
        .sort(),
    ).toEqual([
      'chord-2__get_budgets',
      'chord-2__list_agents',
      'chord-2__list_monitors',
    ]);
    expect(tools.tools).toHaveLength(10);
  });
});

describe('riff MCP transports', () => {
  test('stdio and streamable HTTP as the SDK makes them; no SSE', () => {
    expect(transportOf(stdio('n', 'ok'), '/')).toBeInstanceOf(
      StdioClientTransport,
    );
    expect(
      transportOf(
        { type: 'http', name: 'n', url: 'http://127.0.0.1:1/mcp', headers: [] },
        '/',
      ),
    ).toBeInstanceOf(StreamableHTTPClientTransport);
    expect(() =>
      transportOf(
        { type: 'sse', name: 'n', url: 'http://127.0.0.1:1/sse', headers: [] },
        '/',
      ),
    ).toThrow('riff takes no sse server');
  });
});

describe('riff MCP servers against the fake', () => {
  test('a stdio server and an HTTP one with its bearer, each under its prefix', async () => {
    const http = serveFakeMcp('remote');

    cleanups.push(() => http.close());

    const tools = await opened([
      stdio('notes', 'ok'),
      {
        type: 'http',
        name: 'remote notes',
        url: http.url,
        headers: [{ name: 'Authorization', value: 'Bearer fixture-token' }],
      },
    ]);

    expect(tools.skipped).toEqual([]);
    expect(tools.tools.map((tool) => [tool.name, tool.idempotent])).toEqual([
      ['notes__save_note', false],
      ['remote_notes__save_note', false],
    ]);
    expect(tools.originals.get('remote_notes__save_note')).toEqual({
      server: 'remote notes',
      tool: 'save_note',
    });
    expect(await call(tools, 'notes__save_note', { title: 'Deploy' })).toBe(
      'Saved Deploy',
    );
    expect(
      await call(tools, 'remote_notes__save_note', { title: 'Remote' }),
    ).toBe('Saved Remote');
    expect(
      http.authorizations.every((value) => value === 'Bearer fixture-token'),
    ).toBe(true);
  });

  test('a server that exits is skipped with the tail of its stderr; the rest stay', async () => {
    const tools = await opened([
      stdio('broken', 'crash'),
      stdio('notes', 'ok'),
    ]);

    expect(tools.tools.map((tool) => tool.name)).toEqual(['notes__save_note']);
    expect(tools.skipped).toHaveLength(1);
    expect(tools.skipped[0]?.name).toBe('broken');
    expect(tools.skipped[0]?.said).toBe(
      'starting notes\nnotes: no database at ./notes.db',
    );
    expect(skippedNote(tools.skipped[0]!)).toBe(
      `MCP server broken was not started: ${tools.skipped[0]!.reason}\n\n\`\`\`\nstarting notes\nnotes: no database at ./notes.db\n\`\`\``,
    );
  });

  test('a command that does not exist, and a tool name libfx would change, are skipped', async () => {
    const tools = await opened([
      { name: 'gone', command: '/nonexistent/notes-mcp', args: [], env: [] },
      stdio('odd', 'badname'),
    ]);

    expect(tools.tools).toEqual([]);
    expect(tools.skipped.map((each) => each.name)).toEqual(['gone', 'odd']);
    expect(tools.skipped[1]?.reason).toContain('"list notes"');
  });

  test('a later server whose prefixed name is taken by another is refused whole', async () => {
    const first = serveFakeMcp('a', 'ok', 'note__save');
    const second = serveFakeMcp('b', 'ok', 'save');

    cleanups.push(
      () => first.close(),
      () => second.close(),
    );

    // `my` with `note__save` and `my__note` with `save` both make
    // `my__note__save`.
    const tools = await opened([
      { type: 'http', name: 'my', url: first.url, headers: [] },
      { type: 'http', name: 'my__note', url: second.url, headers: [] },
    ]);

    expect(tools.tools.map((tool) => tool.name)).toEqual([
      'my__save_note',
      'my__note__save',
    ]);
    expect(tools.originals.get('my__note__save')).toEqual({
      server: 'my',
      tool: 'note__save',
    });
    expect(tools.skipped).toEqual([
      {
        name: 'my__note',
        reason: `its tool "my__note__save" has the name of server my's note__save`,
      },
    ]);
  });

  test('a server that never answers is skipped at the bound and its process ended', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-mcp-'));
    const pidFile = join(dir, 'pid');

    cleanups.push(() => rm(dir, { recursive: true, force: true }));

    const tools = await opened([stdio('slow', 'hang', pidFile)], 1500);

    expect(tools.skipped[0]?.reason).toBe('it did not answer within 1.5 s');

    const pid = Number(await readFile(pidFile, 'utf8'));

    await until(() => !alive(pid));
  });

  test('close ends every stdio server, once', async () => {
    const dir = await realpath(await mkdtemp(join(tmpdir(), 'chord-mcp-')));
    const pidFile = join(dir, 'pid');

    cleanups.push(() => rm(dir, { recursive: true, force: true }));

    const tools = await opened([stdio('notes', 'ok', pidFile)]);
    const pid = Number(await readFile(pidFile, 'utf8'));

    expect(alive(pid)).toBe(true);

    await Promise.all([tools.close(), tools.close()]);
    await until(() => !alive(pid));
  });
});

function alive(pid: number): boolean {
  try {
    process.kill(pid, 0);

    return true;
  } catch {
    return false;
  }
}
