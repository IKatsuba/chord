import { expect, test } from 'bun:test';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import {
  type ChordServer,
  serveChord,
  SERVER_NAME,
} from '../../src/server/server.ts';
import type { Caller, WindowView } from '../../src/server/tools.ts';
import type { ChordCall } from '../../src/session/transcript/types.ts';

const WINDOW: WindowView = {
  sessions: () => [
    {
      key: 0,
      tab: 1,
      runtime: 'fake',
      id: 'one',
      model: 'fake-large',
      children: [],
    },
    {
      key: 3,
      tab: 2,
      runtime: 'codex',
      id: undefined,
      model: undefined,
      children: [],
    },
  ],
  runtimes: () => ['fake', 'codex'],
  offer: (runtime) =>
    Promise.resolve(
      runtime === 'fake'
        ? { models: [{ id: 'fake-large', name: 'Fake Large' }] }
        : undefined,
    ),
  spawn: () => Promise.resolve({ error: 'no tasks here' }),
  teams: () => Promise.resolve({ found: [], runs: [] }),
  runTeam: () => Promise.resolve({ error: 'no teams here' }),
  teamPlaces: () => Promise.reject(new Error('no teams here')),
  askPerson: () => Promise.resolve(undefined),
  openMember: () => Promise.resolve({ error: 'no members here' }),
  message: () => ({ error: 'no parent here' }),
  open: () => Promise.resolve({ error: 'no agents here' }),
  tell: () => ({ error: 'no children here' }),
  close: () => ({ error: 'no children here' }),
  monitor: () => ({ error: 'no monitors here' }),
  stopMonitor: () => ({ error: 'no monitors here' }),
  monitors: () => [],
  served: () => {},
  servedLater(caller) {
    return (call) => this.served(caller, call);
  },
};

const PERSON: Caller = { role: 'person', key: 3, window: WINDOW };

async function withServer(body: (server: ChordServer) => Promise<void>) {
  const server = serveChord();

  try {
    await body(server);
  } finally {
    await server.close();
  }
}

/** The SDK's client on `url`, sending `token` as a bearer. */
async function connect(url: string, token?: string): Promise<Client> {
  const client = new Client({ name: 'test', version: '0.0.0' });
  const transport = new StreamableHTTPClientTransport(new URL(url), {
    requestInit: {
      headers: token === undefined ? {} : { Authorization: `Bearer ${token}` },
    },
  });

  await client.connect(transport as Parameters<Client['connect']>[0]);

  return client;
}

function textOf(result: Awaited<ReturnType<Client['callTool']>>): unknown {
  const [block] = Array.isArray(result.content) ? result.content : [];

  return JSON.parse(block?.type === 'text' ? block.text : 'null');
}

test("a session's entry is chord's server over HTTP with its own bearer token", () =>
  withServer((server) => {
    const one = server.admit(PERSON);
    const two = server.admit(PERSON);

    expect(server.url.startsWith('http://127.0.0.1:')).toBeTruthy();
    expect(one.server).toStrictEqual({
      type: 'http',
      name: SERVER_NAME,
      url: server.url,
      headers: [{ name: 'Authorization', value: `Bearer ${one.token}` }],
    });
    expect(one.token !== two.token).toBeTruthy();

    return Promise.resolve();
  }));

test('a session the person opened lists the agents and the sessions', () =>
  withServer(async (server) => {
    const client = await connect(server.url, server.admit(PERSON).token);

    try {
      const { tools } = await client.listTools();

      expect(tools.map(({ name }) => name)).toStrictEqual([
        'list_agents',
        'list_sessions',
        'list_teams',
        'spawn_task',
        'open_agent',
        'run_team',
        'propose_team',
        'send_message',
        'close_agent',
        'monitor',
        'stop_monitor',
        'list_monitors',
      ]);

      // The agent reads the team file's structure as JSON Schema.
      const propose = tools.find(({ name }) => name === 'propose_team');

      expect(propose?.inputSchema.required).toStrictEqual([
        'name',
        'description',
        'lead',
        'members',
        'body',
      ]);
      expect(
        Object.keys(
          (
            propose?.inputSchema.properties?.members as {
              items: { properties: object };
            }
          ).items.properties,
        ),
      ).toStrictEqual([
        'name',
        'role',
        'agent',
        'model',
        'effort',
        'mode',
        'instructions',
      ]);
      expect(
        textOf(await client.callTool({ name: 'list_sessions' })),
      ).toStrictEqual({
        sessions: [
          { id: 'one', runtime: 'fake', model: 'fake-large', tab: 1 },
          { id: null, runtime: 'codex', model: null, tab: 2, you: true },
        ],
      });
      expect(
        textOf(
          await client.callTool({
            name: 'list_agents',
            arguments: { agent: 'fake' },
          }),
        ),
      ).toStrictEqual({
        agents: [
          {
            name: 'fake',
            models: [{ id: 'fake-large', name: 'Fake Large' }],
          },
        ],
      });
    } finally {
      await client.close();
    }
  }));

test("a task agent's session sends messages to its parent and does nothing else, each call served to its session", () =>
  withServer(async (server) => {
    const served: unknown[] = [];
    const child: Caller = {
      role: 'child',
      key: 3,
      task: 'task-1',
      window: {
        ...WINDOW,
        message: (_caller, text) =>
          text === 'refuse me' ? { error: 'gone' } : { delivered: 'queued' },
        served: (caller, call) => served.push([caller.task, call]),
      },
    };
    const client = await connect(server.url, server.admit(child).token);

    try {
      const { tools } = await client.listTools();

      expect(tools.map(({ name }) => name)).toStrictEqual(['send_message']);
      expect(
        textOf(
          await client.callTool({
            name: 'send_message',
            arguments: { text: 'Found it' },
          }),
        ),
      ).toStrictEqual({ delivered: 'queued' });

      const refused = await client.callTool({
        name: 'send_message',
        arguments: { text: 'refuse me' },
      });

      expect(refused.isError).toStrictEqual(true);
      expect(served).toStrictEqual([
        [
          'task-1',
          {
            tool: 'send_message',
            input: { text: 'Found it' },
            answer: { delivered: 'queued' },
            asked: expect.any(String),
            queued: true,
          },
        ],
        [
          'task-1',
          {
            tool: 'send_message',
            input: { text: 'refuse me' },
            error: 'gone',
            asked: expect.any(String),
          },
        ],
      ]);
    } finally {
      await client.close();
    }
  }));

test('a message sent into a turn that went as the next turn after all is served again, queued, with the answer the agent had, where the sender was found as it sent', () =>
  withServer(async (server) => {
    const served: ChordCall[] = [];
    const later: ChordCall[] = [];
    let queued: (() => void) | undefined;
    const child: Caller = {
      role: 'child',
      key: 3,
      task: 'task-1',
      window: {
        ...WINDOW,
        message: (_caller, _text, later) => {
          queued = later;

          return { delivered: 'sent' };
        },
        served: (_caller, call) => served.push(call),
        servedLater: (caller) => {
          expect(caller.task).toBe('task-1');

          return (call) => later.push(call);
        },
      },
    };
    const client = await connect(server.url, server.admit(child).token);

    try {
      expect(
        textOf(
          await client.callTool({
            name: 'send_message',
            arguments: { text: 'Found it' },
          }),
        ),
      ).toStrictEqual({ delivered: 'sent' });
      queued?.();

      const [first] = served;
      const [again] = later;

      expect(served).toHaveLength(1);
      expect(first).toStrictEqual({
        tool: 'send_message',
        input: { text: 'Found it' },
        answer: { delivered: 'sent' },
        asked: expect.any(String),
      });
      expect(again).toStrictEqual({ ...first!, queued: true });
    } finally {
      await client.close();
    }
  }));

test('a request without a token, or with one chord never gave, is refused', () =>
  withServer(async (server) => {
    server.admit(PERSON);

    for (const ask of [
      () => connect(server.url),
      () => connect(server.url, 'made-up'),
    ]) {
      const refused = ask();

      await expect(refused).rejects.toThrow(Error);
      await expect(refused).rejects.toThrow('Unknown token');
    }

    const plain = await fetch(server.url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{}',
    });

    expect(plain.status).toStrictEqual(401);
    await plain.body?.cancel();
  }));

test("a token cannot speak in another token's session", () =>
  withServer(async (server) => {
    const client = await connect(server.url, server.admit(PERSON).token);
    const other = server.admit(PERSON).token;

    try {
      const transport = client.transport as StreamableHTTPClientTransport;
      const response = await fetch(server.url, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          accept: 'application/json, text/event-stream',
          authorization: `Bearer ${other}`,
          'mcp-session-id': transport.sessionId ?? '',
          'mcp-protocol-version': '2025-06-18',
        },
        body: JSON.stringify({ jsonrpc: '2.0', id: 9, method: 'tools/list' }),
      });

      expect(response.status).toStrictEqual(403);
      await response.body?.cancel();
    } finally {
      await client.close();
    }
  }));

test('a revoked token is refused, and its sessions end', () =>
  withServer(async (server) => {
    const { token } = server.admit(PERSON);
    const client = await connect(server.url, token);

    try {
      server.revoke(token);

      await expect(client.listTools()).rejects.toThrow();

      const refused = connect(server.url, token);

      await expect(refused).rejects.toThrow(Error);
      await expect(refused).rejects.toThrow('Unknown token');
    } finally {
      await client.close();
    }
  }));

test('a closed server listens no more', async () => {
  const server = serveChord();
  const client = await connect(server.url, server.admit(PERSON).token);

  await server.close();
  await client.close();
  await expect(fetch(server.url, { method: 'POST' })).rejects.toThrow();
});

test(
  'a call the window answers well past 10 s still gets its answer, its stream held open',
  () =>
    withServer(async (server) => {
      const caller: Caller = {
        ...PERSON,
        window: {
          ...WINDOW,
          // Bun.serve cuts a connection idle for 10 s by default, on a timer
          // that ticks late: about 12 s in.
          spawn: () =>
            new Promise((resolve) =>
              setTimeout(
                () => resolve({ id: 't1', name: 'Fix it', agent: 'fake' }),
                15_000,
              ),
            ),
        },
      };
      const client = await connect(server.url, server.admit(caller).token);

      try {
        expect(
          textOf(
            await client.callTool({
              name: 'spawn_task',
              arguments: { agent: 'fake', prompt: 'Fix it' },
            }),
          ),
        ).toStrictEqual({ id: 't1', name: 'Fix it', agent: 'fake' });
      } finally {
        await client.close();
      }
    }),
  25_000,
);

test('a long-lived child starts task agents of its own, as the session that opened it does', () =>
  withServer(async (server) => {
    const served: unknown[] = [];
    const asked: unknown[] = [];
    const child: Caller = {
      role: 'child',
      key: 3,
      agent: 'a1b2c3d4',
      window: {
        ...WINDOW,
        spawn: (caller, args) => {
          asked.push([caller.key, caller.agent, args.prompt]);

          return Promise.resolve({ id: 't1', name: 'Fix it', agent: 'fake' });
        },
        served: (_caller, call) => served.push(call),
      },
    };
    const client = await connect(server.url, server.admit(child).token);

    try {
      expect(
        textOf(
          await client.callTool({
            name: 'spawn_task',
            arguments: { agent: 'fake', prompt: 'Fix it' },
          }),
        ),
      ).toStrictEqual({ id: 't1', name: 'Fix it', agent: 'fake' });
      expect(asked).toStrictEqual([[3, 'a1b2c3d4', 'Fix it']]);
      expect(served).toStrictEqual([
        {
          tool: 'spawn_task',
          input: { agent: 'fake', prompt: 'Fix it' },
          answer: { id: 't1', name: 'Fix it', agent: 'fake' },
          task: 't1',
        },
      ]);
    } finally {
      await client.close();
    }
  }));

test('a long-lived child starts, stops and lists monitors of its own, each answer said for the model with the value beside it', () =>
  withServer(async (server) => {
    const served: unknown[] = [];
    const asked: unknown[] = [];
    const child: Caller = {
      role: 'child',
      key: 3,
      agent: 'a1b2c3d4',
      window: {
        ...WINDOW,
        monitor: (caller, args) => {
          asked.push([caller.agent, args]);

          return args.description === 'refuse me'
            ? { error: 'timeout_ms is between 1000 and 3600000 (1h)' }
            : {
                id: 'm1',
                description: args.description,
                timeout_ms: 600_000,
              };
        },
        stopMonitor: (_caller, id) => ({
          id,
          description: 'log',
          events: 1,
          ran_ms: 2000,
        }),
        monitors: () => [],
        served: (_caller, call) => served.push(call),
      },
    };
    const client = await connect(server.url, server.admit(child).token);

    try {
      const { tools } = await client.listTools();

      expect(tools.map(({ name }) => name)).toStrictEqual([
        'list_agents',
        'spawn_task',
        'send_message',
        'monitor',
        'stop_monitor',
        'list_monitors',
      ]);

      const started = await client.callTool({
        name: 'monitor',
        arguments: { command: 'tail -f log', description: 'log' },
      });

      expect(started.structuredContent).toStrictEqual({
        id: 'm1',
        description: 'log',
        timeout_ms: 600_000,
      });
      expect(
        JSON.stringify(started.content).includes(
          'Started monitor m1 (log); it times out in 10m.',
        ),
      ).toBeTruthy();

      const refused = await client.callTool({
        name: 'monitor',
        arguments: {
          command: 'tail -f log',
          description: 'refuse me',
          timeout_ms: 5,
        },
      });

      expect(refused.isError).toStrictEqual(true);
      expect(
        (
          await client.callTool({
            name: 'stop_monitor',
            arguments: { id: 'm1' },
          })
        ).structuredContent,
      ).toStrictEqual({
        id: 'm1',
        description: 'log',
        events: 1,
        ran_ms: 2000,
      });
      expect(
        (await client.callTool({ name: 'list_monitors' })).structuredContent,
      ).toStrictEqual({ monitors: [] });
      expect(asked).toStrictEqual([
        [
          'a1b2c3d4',
          {
            command: 'tail -f log',
            description: 'log',
            timeoutMs: undefined,
          },
        ],
        [
          'a1b2c3d4',
          {
            command: 'tail -f log',
            description: 'refuse me',
            timeoutMs: 5,
          },
        ],
      ]);
      expect(
        served.map((call) => {
          const { tool, error } = call as { tool: string; error?: string };

          return error === undefined ? tool : `${tool}: ${error}`;
        }),
      ).toStrictEqual([
        'monitor',
        'monitor: timeout_ms is between 1000 and 3600000 (1h)',
        'stop_monitor',
        'list_monitors',
      ]);
    } finally {
      await client.close();
    }
  }));

test("a team's lead opens, messages and closes members; a member only messages, by name", () =>
  withServer(async (server) => {
    const told: string[] = [];
    const window: WindowView = {
      ...WINDOW,
      openMember: (_caller, args) =>
        Promise.resolve({ id: 'a1', name: args.member, agent: 'fake' }),
      tell: (caller, to, text) => {
        told.push(`${caller.team} → ${to}: ${text}`);

        return { delivered: 'sent', to };
      },
    };
    const lead = await connect(
      server.url,
      server.admit({
        role: 'child',
        key: 0,
        agent: 'l1',
        team: 'lead',
        window,
      }).token,
    );
    const member = await connect(
      server.url,
      server.admit({
        role: 'child',
        key: 0,
        agent: 'm1',
        team: 'member',
        window,
      }).token,
    );

    try {
      expect(
        (await lead.listTools()).tools.map(({ name }) => name),
      ).toStrictEqual([
        'list_agents',
        'spawn_task',
        'open_agent',
        'send_message',
        'close_agent',
        'monitor',
        'stop_monitor',
        'list_monitors',
      ]);
      expect(
        (await member.listTools()).tools.map(({ name }) => name),
      ).toStrictEqual([
        'list_agents',
        'spawn_task',
        'send_message',
        'monitor',
        'stop_monitor',
        'list_monitors',
      ]);
      expect(
        textOf(
          await lead.callTool({
            name: 'open_agent',
            arguments: { member: 'tester', prompt: 'Write the test.' },
          }),
        ),
      ).toStrictEqual({ id: 'a1', name: 'tester', agent: 'fake' });
      await lead.callTool({
        name: 'send_message',
        arguments: { to: 'main', text: 'On it.' },
      });
      await member.callTool({
        name: 'send_message',
        arguments: { to: 'coder', text: 'Your turn.' },
      });
      expect(told).toStrictEqual([
        'lead → main: On it.',
        'member → coder: Your turn.',
      ]);
    } finally {
      await lead.close();
      await member.close();
    }
  }));
