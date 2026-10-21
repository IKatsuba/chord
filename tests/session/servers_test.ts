import { describe, expect, test } from 'bun:test';
import type { McpCapabilities, McpServer } from '@agentclientprotocol/sdk';
import {
  type HeldBack,
  heldBackLine,
  serversFor,
} from '../../src/session/servers.ts';

const STDIO: McpServer = {
  name: 'docs',
  command: 'docs-server',
  args: [],
  env: [],
};
const HTTP: McpServer = {
  type: 'http',
  name: 'search',
  url: 'https://search.example/mcp',
  headers: [],
};
const SSE: McpServer = {
  type: 'sse',
  name: 'logs',
  url: 'https://logs.example/sse',
  headers: [],
};
const CHORD: McpServer = {
  type: 'http',
  name: 'chord',
  url: 'http://127.0.0.1:9/mcp',
  headers: [{ name: 'Authorization', value: 'Bearer token' }],
};

/** A held-back entry as `serversFor` gives it for the fake. */
const held = (
  server: string,
  transport: string,
  takes: readonly string[],
  own = false,
): HeldBack => ({
  server,
  agent: 'fake',
  transport,
  takes,
  ...(own ? { own: true as const } : {}),
});

describe('an agent gets only the MCP servers whose transport it advertises (CHD-441)', () => {
  const advertised: [string, McpCapabilities | undefined][] = [
    ['nothing', undefined],
    ['none past stdio', {}],
    ['http alone', { http: true }],
    ['sse alone', { sse: true }],
    ['http and sse', { http: true, sse: true }],
    ['http, sse said false', { http: true, sse: false }],
  ];

  for (const [label, capabilities] of advertised) {
    test(`advertising ${label}`, () => {
      const http = capabilities?.http === true;
      const sse = capabilities?.sse === true;
      const takes = [
        'stdio',
        ...(http ? ['http'] : []),
        ...(sse ? ['sse'] : []),
      ];
      const given = serversFor('fake', capabilities, [STDIO, HTTP, SSE], CHORD);

      expect(given.servers).toStrictEqual([
        STDIO,
        ...(http ? [HTTP] : []),
        ...(sse ? [SSE] : []),
        ...(http ? [CHORD] : []),
      ]);
      expect(given.heldBack).toStrictEqual([
        ...(http ? [] : [held('search', 'http', takes)]),
        ...(sse ? [] : [held('logs', 'sse', takes)]),
        ...(http ? [] : [held('chord', 'http', takes, true)]),
      ]);
      expect(given.chord).toStrictEqual(http ? CHORD : undefined);
    });
  }

  test('a transport ACP names past the three goes only where advertised', () => {
    const acp: McpServer = { type: 'acp', name: 'peer', serverId: 'peer-1' };

    expect(serversFor('fake', { acp: true }, [acp]).servers).toStrictEqual([
      acp,
    ]);
    expect(serversFor('fake', { http: true }, [acp]).heldBack).toStrictEqual([
      held('peer', 'acp', ['stdio', 'http']),
    ]);
  });

  test('with no servers and no chord server, nothing goes and nothing is held back', () => {
    expect(serversFor('fake', undefined, [])).toStrictEqual({
      servers: [],
      heldBack: [],
    });
  });
});

test("chord's server takes the first free name among the servers that go", () => {
  const user = (name: string): McpServer => ({ ...CHORD, name, url: 'u' });

  expect(
    serversFor('fake', { http: true }, [user('docs')], CHORD).servers,
  ).toStrictEqual([user('docs'), CHORD]);
  expect(
    serversFor('fake', { http: true }, [user('chord'), user('chord-2')], CHORD)
      .servers,
  ).toStrictEqual([
    user('chord'),
    user('chord-2'),
    { ...CHORD, name: 'chord-3' },
  ]);

  // A user's `chord` held back takes no name from chord's own.
  const sse = { ...SSE, name: 'chord' };

  expect(serversFor('fake', { http: true }, [sse], CHORD).chord).toStrictEqual(
    CHORD,
  );
});

describe("the start line says what an agent was not given, in docs/design/CHD-441.md's words", () => {
  const tracker: McpServer = { ...SSE, name: 'tracker' };
  const docs: McpServer = { ...HTTP, name: 'docs' };
  const line = (
    capabilities: McpCapabilities | undefined,
    servers: readonly McpServer[],
    chord?: McpServer,
  ) => heldBackLine(serversFor('fake', capabilities, servers, chord).heldBack);

  test('stdio alone names each with its transport, chord first, and what losing it costs', () => {
    expect(line(undefined, [STDIO, docs, tracker], CHORD)).toBe(
      '3 MCP servers were not passed to fake, which takes them over stdio ' +
        "only: chord (http, chord's own), docs (http), tracker (sse). " +
        "Without chord's own, fake cannot start other agents or use chord's " +
        'tools. /mcp lists them.',
    );
  });

  const peer: McpServer = { type: 'acp', name: 'peer', serverId: 'peer-1' };
  const all = [STDIO, docs, tracker, peer];

  test('each transport the agent takes is named; lacking two or more, the names carry theirs', () => {
    expect(line({ http: true }, [STDIO, tracker])).toBe(
      '1 MCP server was not passed to fake, which takes them over stdio and ' +
        'HTTP only: tracker (sse). /mcp lists it.',
    );
    expect(line({ sse: true }, [docs, tracker])).toBe(
      '1 MCP server was not passed to fake, which takes them over stdio and ' +
        'SSE only: docs (http). /mcp lists it.',
    );
    expect(line({ acp: true }, all)).toBe(
      '2 MCP servers were not passed to fake, which takes them over stdio and ' +
        'ACP only: docs (http), tracker (sse). /mcp lists them.',
    );
  });

  test('lacking one transport, the names go bare', () => {
    expect(line({ http: true, sse: true }, all)).toBe(
      '1 MCP server was not passed to fake, which takes them over stdio, ' +
        'HTTP and SSE only: peer. /mcp lists it.',
    );
    expect(line({ http: true, acp: true }, all)).toBe(
      '1 MCP server was not passed to fake, which takes them over stdio, ' +
        'HTTP and ACP only: tracker. /mcp lists it.',
    );
    expect(line({ sse: true, acp: true }, all, CHORD)).toBe(
      '2 MCP servers were not passed to fake, which takes them over stdio, ' +
        "SSE and ACP only: chord (chord's own), docs. Without chord's own, " +
        "fake cannot start other agents or use chord's tools. /mcp lists " +
        'them.',
    );
  });

  test("chord's own alone is 'it'", () => {
    expect(line({}, [STDIO], CHORD)).toBe(
      '1 MCP server was not passed to fake, which takes them over stdio ' +
        "only: chord (http, chord's own). Without it, fake cannot start " +
        "other agents or use chord's tools. /mcp lists it.",
    );
  });

  test('nothing is said when every server went', () => {
    expect(
      line({ http: true, sse: true, acp: true }, all, CHORD),
    ).toBeUndefined();
  });
});

describe('CHD-441 tester: immutable transport filtering across agents', () => {
  test('frozen request payloads survive filtering and collision renaming unchanged', () => {
    const stdio: McpServer = {
      name: 'chord',
      command: 'docs-server',
      args: ['--watch'],
      env: [{ name: 'MODE', value: 'docs' }],
    };
    const http: McpServer = {
      type: 'http',
      name: 'search',
      url: 'https://search.example/mcp',
      headers: [{ name: 'X-Route', value: 'docs' }],
    };
    const chord = structuredClone(CHORD);

    Object.freeze(stdio.args);
    Object.freeze(stdio.env[0]);
    Object.freeze(stdio.env);
    Object.freeze(stdio);
    Object.freeze(http.headers[0]);
    Object.freeze(http.headers);
    Object.freeze(http);
    Object.freeze(chord);

    const users = Object.freeze([stdio, http]);
    const before = structuredClone([...users, chord]);
    const given = serversFor('fake', { http: true }, users, chord);

    expect(given.servers).toStrictEqual([
      stdio,
      http,
      { ...chord, name: 'chord-2' },
    ]);
    expect(given.servers[0]).toBe(stdio);
    expect(given.servers[1]).toBe(http);
    expect(given.chord).toStrictEqual({ ...chord, name: 'chord-2' });
    expect([...users, chord]).toStrictEqual(before);
  });

  test('one agent’s retained servers and warnings do not inherit another agent’s capabilities', () => {
    const users = [SSE, STDIO, HTTP];
    const first = serversFor('alpha', { http: true }, users, CHORD);
    const second = serversFor('beta', { sse: true }, users, CHORD);

    expect(second.servers).toStrictEqual([SSE, STDIO]);
    expect(second.chord).toBeUndefined();
    expect(
      second.heldBack.map(({ server, agent, transport }) => ({
        server,
        agent,
        transport,
      })),
    ).toStrictEqual([
      { server: 'search', agent: 'beta', transport: 'http' },
      { server: 'chord', agent: 'beta', transport: 'http' },
    ]);
    expect(first.servers).toStrictEqual([STDIO, HTTP, CHORD]);
    expect(first.chord).toStrictEqual(CHORD);
    expect(
      first.heldBack.map(({ server, agent, transport }) => ({
        server,
        agent,
        transport,
      })),
    ).toStrictEqual([{ server: 'logs', agent: 'alpha', transport: 'sse' }]);
  });

  test('an unsupported server leaves the first naming gap free without reordering the accepted servers', () => {
    const userChord = { ...HTTP, name: 'chord' };
    const blockedGap = { ...SSE, name: 'chord-2' };
    const laterName = { ...STDIO, name: 'chord-3' };
    const given = serversFor(
      'fake',
      { http: true, sse: false },
      [userChord, blockedGap, laterName],
      CHORD,
    );

    expect(given.servers).toStrictEqual([
      userChord,
      laterName,
      { ...CHORD, name: 'chord-2' },
    ]);
    expect(
      given.heldBack.map(({ server, agent, transport }) => ({
        server,
        agent,
        transport,
      })),
    ).toStrictEqual([{ server: 'chord-2', agent: 'fake', transport: 'sse' }]);
    expect(given.chord?.name).toBe('chord-2');
  });
});
