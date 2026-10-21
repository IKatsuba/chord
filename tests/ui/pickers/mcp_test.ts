import { expect, test } from 'bun:test';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import type { McpServer } from '@agentclientprotocol/sdk';
import { join } from 'node:path';
import stringWidth from 'string-width';
import {
  type DefinedServer,
  loadMcpServers,
  mergeServers,
  parseMcpJson,
  parseServers,
} from '../../../src/mcp.ts';
import { openSession, type Session } from '../../../src/session/session.ts';
import { sessionById } from '../../../src/session/sessions.ts';
import { loadSettings, parseSettings } from '../../../src/settings.ts';
import {
  cutPath,
  heldNote,
  ignoredNote,
  mcpFit,
  mcpRows,
  targetOf,
  withHeldBack,
  wrapTarget,
} from '../../../src/ui/pickers/mcp.ts';
import { serversFor } from '../../../src/session/servers.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { run, said } from '../../fixtures/recorder.ts';

const STDIO = {
  command: 'npx',
  args: ['-y', '@modelcontextprotocol/server-filesystem', '.'],
  env: { DEBUG: '1' },
};

const HTTP = {
  type: 'http',
  url: 'https://mcp.example.com/mcp',
  headers: { Authorization: 'Bearer secret' },
};

function messages(found: { problems: { message: string }[] }): string[] {
  return found.problems.map((problem) => problem.message);
}

function names(servers: readonly DefinedServer[]): string[] {
  return servers.map(({ server, from }) => `${server.name} from ${from}`);
}

test('a command server goes to ACP with its env as name and value pairs', () => {
  const { servers, problems } = parseServers('.mcp.json', {
    filesystem: STDIO,
    bare: { type: 'stdio', command: 'serve' },
  });

  expect(problems).toStrictEqual([]);
  expect(servers).toStrictEqual([
    {
      server: {
        name: 'filesystem',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-filesystem', '.'],
        env: [{ name: 'DEBUG', value: '1' }],
      },
      from: '.mcp.json',
    },
    {
      server: { name: 'bare', command: 'serve', args: [], env: [] },
      from: '.mcp.json',
    },
  ]);
});

test('an HTTP or SSE server goes to ACP with its headers as pairs', () => {
  const { servers, problems } = parseServers('settings.json', {
    docs: HTTP,
    events: { type: 'sse', url: 'http://localhost:9000/sse' },
  });

  expect(problems).toStrictEqual([]);
  expect(servers.map(({ server }) => server)).toStrictEqual([
    {
      type: 'http',
      name: 'docs',
      url: 'https://mcp.example.com/mcp',
      headers: [{ name: 'Authorization', value: 'Bearer secret' }],
    },
    {
      type: 'sse',
      name: 'events',
      url: 'http://localhost:9000/sse',
      headers: [],
    },
  ]);
});

test('a wrong server costs only itself, named with what is wrong', () => {
  const found = parseServers('.mcp.json', {
    search: { type: 'ws', url: 'wss://example.com' },
    github: { type: 'http' },
    plain: { url: 'https://example.com/mcp' },
    nothing: {},
    odd: { command: 3 },
    secret: { command: 'serve', env: { TOKEN: 1 } },
    ftp: { type: 'sse', url: 'ftp://example.com' },
    word: 'npx serve',
    memory: {
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-memory'],
    },
  });

  expect(names(found.servers)).toStrictEqual(['memory from .mcp.json']);
  expect(messages(found)).toStrictEqual([
    '"mcpServers.search.type": "ws" is not a transport ACP carries (stdio, http, sse); the server is ignored',
    '"mcpServers.github.url": missing; the server is ignored',
    '"mcpServers.plain.type": missing; a server with a url needs "http" or "sse"; the server is ignored',
    '"mcpServers.nothing.command": missing; the server is ignored',
    '"mcpServers.odd.command": invalid input: expected string, received number; the server is ignored',
    '"mcpServers.secret.env.TOKEN": invalid input: expected string, received number; the server is ignored',
    '"mcpServers.ftp.url": invalid url; the server is ignored',
    '"mcpServers.word": expected an object with a command or a url; the server is ignored',
  ]);
});

test("keys other tools add to a server are let through, not the agent's", () => {
  const { servers, problems } = parseServers('.mcp.json', {
    filesystem: { ...STDIO, description: 'Files', disabled: false },
  });

  expect(problems).toStrictEqual([]);
  expect(Object.keys(servers[0]?.server ?? {})).toStrictEqual([
    'name',
    'command',
    'args',
    'env',
  ]);
});

/** What the runtime's own parser says of `text`, in its own words. */
function parseError(text: string): string {
  try {
    JSON.parse(text);
  } catch (error) {
    return (error as Error).message;
  }

  throw new Error(`${text} parsed`);
}

test('a broken .mcp.json costs the file and says why', () => {
  const broken = '{ "mcpServers": ';

  expect(messages(parseMcpJson('.mcp.json', broken))).toStrictEqual([
    `not valid JSON (${parseError(broken)}); the file is ignored`,
  ]);
  expect(messages(parseMcpJson('.mcp.json', '[]'))).toStrictEqual([
    'not a JSON object; the file is ignored',
  ]);
  expect(
    messages(parseMcpJson('.mcp.json', '{ "mcpServers": ["a"] }')),
  ).toStrictEqual([
    '"mcpServers": expected an object of servers by name; the file is ignored',
  ]);
  expect(parseMcpJson('.mcp.json', '[]').ignored).toStrictEqual([
    { from: '.mcp.json', servers: 'all' },
  ]);
});

test(".mcp.json's other keys are other tools' and pass without a word", () => {
  const found = parseMcpJson(
    '.mcp.json',
    JSON.stringify({ $schema: 'x', inputs: [], mcpServers: { a: STDIO } }),
  );

  expect(found.problems).toStrictEqual([]);
  expect(names(found.servers)).toStrictEqual(['a from .mcp.json']);
  expect(parseMcpJson('.mcp.json', '{}')).toStrictEqual({
    servers: [],
    problems: [],
    ignored: [],
  });
});

test('a server named again replaces the earlier one whole, in its place', () => {
  const first = parseServers('user', { a: STDIO, b: HTTP }).servers;
  const second = parseServers('project', { a: HTTP, c: STDIO }).servers;
  const merged = mergeServers(first, second);

  expect(names(merged)).toStrictEqual([
    'a from project',
    'b from user',
    'c from project',
  ]);
  expect(merged[0]?.server).toStrictEqual({ ...second[0]!.server });
});

test('the settings files take mcpServers, and one that is not an object is a problem', () => {
  expect(
    parseSettings('s.json', JSON.stringify({ mcpServers: { a: STDIO } })),
  ).toStrictEqual({ settings: { mcpServers: { a: STDIO } }, problems: [] });
  expect(
    messages(parseSettings('s.json', '{ "mcpServers": [] }')),
  ).toStrictEqual([
    '"mcpServers": invalid input: expected record, received array, ignored',
  ]);
});

/** A working directory and a config home of their own, removed after. */
async function withDirs(
  body: (dirs: { cwd: string; configHome: string }) => Promise<void>,
) {
  const root = await mkdtemp(join(tmpdir(), 'chord-mcp-'));
  const cwd = join(root, 'work');
  const configHome = join(root, 'config');

  await mkdir(join(cwd, '.chord'), { recursive: true });
  await mkdir(join(configHome, 'chord'), { recursive: true });

  try {
    await body({ cwd, configHome });
  } finally {
    await rm(root, { recursive: true });
  }
}

function write(file: string, value: unknown): Promise<void> {
  return writeFile(file, JSON.stringify(value));
}

test("the user's file, then .mcp.json, then the project's file, each over the last", () =>
  withDirs(async ({ cwd, configHome }) => {
    const user = join(configHome, 'chord', 'settings.json');
    const shared = join(cwd, '.mcp.json');
    const project = join(cwd, '.chord', 'settings.json');

    await write(user, {
      mcpServers: { docs: HTTP, files: STDIO, mine: STDIO },
    });
    await write(shared, {
      mcpServers: { files: { command: 'shared' }, team: STDIO },
    });
    await write(project, {
      mcpServers: { team: { command: 'ours' }, broken: { type: 'http' } },
    });

    const { layers } = await loadSettings({ configHome, cwd });
    const found = await loadMcpServers({ layers, cwd });

    expect(names(found.servers)).toStrictEqual([
      `docs from ${user}`,
      `files from ${shared}`,
      `mine from ${user}`,
      `team from ${project}`,
    ]);
    expect(found.problems).toStrictEqual([
      {
        file: project,
        message: '"mcpServers.broken.url": missing; the server is ignored',
      },
    ]);
    expect(found.ignored).toStrictEqual([{ from: project, servers: 1 }]);
  }));

test('no .mcp.json and no settings pass no servers and say nothing', () =>
  withDirs(async ({ cwd, configHome }) => {
    const { layers } = await loadSettings({ configHome, cwd });

    expect(await loadMcpServers({ layers, cwd })).toStrictEqual({
      servers: [],
      problems: [],
      ignored: [],
    });
  }));

test('the rows fit the width and never show env or headers', () => {
  const servers = mergeServers(
    parseServers('~/.config/chord/settings.json', { docs: HTTP }).servers,
    parseServers('.mcp.json', {
      filesystem: { command: 'npx', args: ['-y', 'a server', '.'], env: {} },
    }).servers,
  );

  for (const width of [116, 76, 40]) {
    const { headings, rows } = mcpRows(servers, width);

    for (const line of [headings, ...rows.flat()]) {
      expect(
        stringWidth(line) <= width,
        `${line} is wider than ${width}`,
      ).toBeTruthy();
      expect(!line.includes('secret'), 'a header was shown').toBeTruthy();
    }
  }

  expect(targetOf(servers[1]!)).toStrictEqual('npx -y "a server" .');
});

test('a command wraps in its column rather than lose its end', () => {
  const servers = parseServers('.mcp.json', {
    memory: {
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-memory'],
    },
  }).servers;
  const settings = parseServers('~/.config/chord/settings.json', {
    docs: HTTP,
  }).servers;
  const wide = mcpRows([...settings, ...servers], 116);
  const narrow = mcpRows([...settings, ...servers], 76);

  expect(wide.rows.map((row) => row.length)).toStrictEqual([1, 1]);
  expect(narrow.rows[1]).toStrictEqual([
    'memory  stdio      npx -y                    .mcp.json',
    '                   @modelcontextprotocol/',
    '                   server-memory',
  ]);
  // The path is drawn whole, as it is short enough to be.
  expect(
    narrow.rows[0]![0]!.endsWith('  ~/.config/chord/settings.json'),
  ).toBeTruthy();
});

test('a command breaks at spaces, then after slashes, then anywhere', () => {
  expect(wrapTarget('https://mcp.example.com/mcp', 22)).toStrictEqual([
    'https://',
    'mcp.example.com/mcp',
  ]);
  expect(wrapTarget('uvx abcdefghij', 4)).toStrictEqual([
    'uvx',
    'abcd',
    'efgh',
    'ij',
  ]);
  expect(wrapTarget('npx -y a', 40)).toStrictEqual(['npx -y a']);
});

test('a path too long for its column is cut from the left, at a separator', () => {
  expect(cutPath('/tmp/chord-cfg.6XOm/chord/settings.json', 24)).toStrictEqual(
    '…/chord/settings.json',
  );
  expect(cutPath('.mcp.json', 24)).toStrictEqual('.mcp.json');
  expect(cutPath('/a/settings.json', 8)).toStrictEqual('…gs.json');
});

test('the list keeps whole servers to its lines and counts the rest', () => {
  const rows = [['a'], ['b', 'b'], ['c'], ['d']];

  expect(mcpFit(rows, 5)).toStrictEqual({ shown: rows, more: 0 });
  expect(mcpFit(rows, 4)).toStrictEqual({
    shown: [['a'], ['b', 'b']],
    more: 2,
  });
  expect(mcpFit([['a', 'a', 'a', 'a'], ['b']], 3)).toStrictEqual({
    shown: [['a', 'a', 'a', 'a']],
    more: 1,
  });
});

test('what the files lost is said in one line, or not at all', () => {
  expect(ignoredNote([])).toStrictEqual(undefined);
  expect(
    ignoredNote([
      { from: '~/.config/chord/settings.json', servers: 1 },
      { from: '.mcp.json', servers: 2 },
    ]),
  ).toStrictEqual(
    '1 server in ~/.config/chord/settings.json was ignored and 2 servers in .mcp.json were ignored; chord said why when it started.',
  );
  expect(ignoredNote([{ from: '.mcp.json', servers: 'all' }])).toStrictEqual(
    '.mcp.json was ignored; chord said why when it started.',
  );
});

/** What the fake agent says it received, from its `mcp` scenario. */
async function received(session: Session): Promise<McpServer[]> {
  const reply = said((await run(session, 'mcp')).updates).join('');

  return JSON.parse(reply.replace(/^```json\n|\n```$/g, ''));
}

test('the agent receives exactly the servers chord lists, new and loaded', () =>
  withDirs(async ({ cwd, configHome }) => {
    await write(join(configHome, 'chord', 'settings.json'), {
      mcpServers: { docs: HTTP },
    });
    await write(join(cwd, '.mcp.json'), {
      mcpServers: { filesystem: STDIO },
    });

    const { layers } = await loadSettings({ configHome, cwd });
    const { servers } = await loadMcpServers({ layers, cwd });
    const listed = servers.map(({ server }) => server);
    const options = {
      agent: 'fake',
      cwd,
      agentCommand: fakeAgentCommand(),
      mcpServers: listed,
    };

    expect(listed.map((server) => server.name)).toStrictEqual([
      'docs',
      'filesystem',
    ]);

    const fresh = await openSession(options);

    try {
      expect(await received(fresh)).toStrictEqual(listed);
    } finally {
      await fresh.close();
    }

    const loaded = await openSession({
      ...options,
      resume: sessionById([], crypto.randomUUID(), {
        agent: 'fake',
        cwd,
      }),
    });

    try {
      expect(await received(loaded)).toStrictEqual(listed);
    } finally {
      await loaded.close();
    }
  }));

test('/mcp lists a server its agent was not given as not passed, and says why under the list (CHD-441)', () => {
  const docs: McpServer = {
    name: 'docs',
    command: 'docs-server',
    args: [],
    env: [],
  };
  const search: McpServer = {
    type: 'http',
    name: 'search',
    url: 'https://search.example/mcp',
    headers: [],
  };
  const tracker: McpServer = {
    type: 'sse',
    name: 'tracker',
    url: 'https://tracker.example/sse',
    headers: [],
  };
  const chord: McpServer = {
    ...search,
    name: 'chord',
    url: 'http://127.0.0.1:9/mcp',
  };
  const defined = [docs, search, tracker].map((server) => ({
    server,
    from: '~/.config/chord/settings.json',
  }));
  const stdio = serversFor('fake', undefined, [docs, search, tracker], chord);

  expect(
    withHeldBack(defined, stdio.heldBack).map((each) => targetOf(each)),
  ).toStrictEqual(['docs-server', 'not passed', 'not passed']);
  expect(heldNote(stdio.heldBack)).toBe(
    'search and tracker were not passed: fake takes MCP servers over stdio only.',
  );

  const noSse = serversFor(
    'fake',
    { http: true },
    [docs, search, tracker],
    chord,
  );

  expect(heldNote(noSse.heldBack)).toBe(
    'tracker was not passed: fake takes MCP servers over stdio and HTTP only.',
  );

  // chord's own alone has its own line, not this one.
  expect(
    heldNote(serversFor('fake', {}, [docs], chord).heldBack),
  ).toBeUndefined();
});
