import { describe, expect, test } from 'bun:test';
import type { McpCapabilities, McpServer } from '@agentclientprotocol/sdk';
import { type HeldBack, serversFor } from '../../src/session/servers.ts';

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
const held = (server: string, transport: string): HeldBack => ({
  server,
  agent: 'fake',
  transport,
  why: 'transport not advertised',
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
      const given = serversFor('fake', capabilities, [STDIO, HTTP, SSE], CHORD);

      expect(given.servers).toStrictEqual([
        STDIO,
        ...(http ? [HTTP] : []),
        ...(sse ? [SSE] : []),
        ...(http ? [CHORD] : []),
      ]);
      expect(given.heldBack).toStrictEqual([
        ...(http ? [] : [held('search', 'http')]),
        ...(sse ? [] : [held('logs', 'sse')]),
        ...(http ? [] : [held('chord', 'http')]),
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
      held('peer', 'acp'),
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
