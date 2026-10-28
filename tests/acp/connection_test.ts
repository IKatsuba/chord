import { execFile, spawn } from 'node:child_process';
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import type * as acp from '@agentclientprotocol/sdk';
import {
  type Agent,
  AgentGone,
  connectAgent,
  openAgent,
  type OpenAgentOptions,
} from '../../src/acp/connection.ts';
import manifest from '../../package.json' with { type: 'json' };
import { commandArgv, settledWithin } from '../../src/acp/process.ts';
import type { Traffic } from '../../src/acp/traffic.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { TRACEBACK_ERROR } from '../fixtures/fake_agent/options.ts';
import { FORM_SCHEMA, LINK_URL } from '../fixtures/forms.ts';

/** Short enough to keep a wedged agent's test quick, long enough to be real. */
const STOP = { exitMs: 300, termMs: 300, killMs: 2000 } as const;

function isAlive(pid: number): Promise<boolean> {
  return new Promise((resolve) => {
    execFile('ps', ['-p', String(pid)], (error) => resolve(error === null));
  });
}

/** What the subscriber saw, and the notifications among it. */
class Seen {
  readonly all: Traffic[] = [];

  readonly push = (traffic: Traffic) => void this.all.push(traffic);

  /** The params of every notification the agent sent under `method`. */
  notified(method: string): unknown[] {
    return this.all.flatMap((traffic) =>
      traffic.from === 'agent' &&
      'method' in traffic.message &&
      !('id' in traffic.message) &&
      traffic.message.method === method
        ? [traffic.message.params]
        : [],
    );
  }

  /** Every `session/update`'s update, in order. */
  updates(): acp.SessionUpdate[] {
    return this.notified('session/update').map(
      (params) => (params as acp.SessionNotification).update,
    );
  }

  /** The text of every agent message chunk, joined. */
  said(): string {
    return this.updates()
      .map((update) =>
        update.sessionUpdate === 'agent_message_chunk' &&
        update.content.type === 'text'
          ? update.content.text
          : '',
      )
      .join('');
  }

  /** The methods chord sent, requests and notifications alike. */
  sent(): string[] {
    return this.all.flatMap((traffic) =>
      traffic.from === 'chord' && 'method' in traffic.message
        ? [traffic.message.method]
        : [],
    );
  }
}

type Handlers = Pick<OpenAgentOptions, 'onPermission' | 'onElicitation'>;

const REFUSE: Handlers = {
  onPermission: () => Promise.resolve({ outcome: { outcome: 'cancelled' } }),
  onElicitation: () => Promise.resolve({ action: 'decline' }),
};

/**
 * Starts the fake agent with `flags`, hands it to `body`, then closes it and
 * proves the process is gone.
 */
async function withAgent(
  flags: string[],
  body: (agent: Agent, seen: Seen, cwd: string) => void | Promise<void>,
  handlers: Handlers = REFUSE,
) {
  const cwd = await mkdtemp(join(tmpdir(), 'chord-acp-'));
  const seen = new Seen();
  const agent = await openAgent({
    command: fakeAgentCommand(undefined, ...flags),
    cwd,
    onTraffic: seen.push,
    stop: STOP,
    ...handlers,
  });

  try {
    await body(agent, seen, cwd);
  } finally {
    await agent.close();
    await rm(cwd, { recursive: true });
  }

  expect(
    !(await isAlive(agent.pid)),
    'the agent is still running',
  ).toBeTruthy();
}

function text(value: string): acp.ContentBlock {
  return { type: 'text', text: value };
}

/** Until `check` holds, or a second passes. */
async function eventually(check: () => boolean): Promise<void> {
  const deadline = Date.now() + 1000;

  while (!check()) {
    expect(Date.now() < deadline, 'it never happened').toBeTruthy();
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

test('a command line splits as a shell would, with nothing expanded', () => {
  expect(
    commandArgv(`deno run --config '/a b/deno.json' "x y" a\\ b $HOME`),
  ).toStrictEqual([
    'deno',
    'run',
    '--config',
    '/a b/deno.json',
    'x y',
    'a b',
    '$HOME',
  ]);
  expect(commandArgv(['npx', '-y', 'a b'])).toStrictEqual(['npx', '-y', 'a b']);
  expect(() => commandArgv('agent | tee log')).toThrow(Error);
  expect(() => commandArgv('agent | tee log')).toThrow('shell syntax');
  expect(() => commandArgv('  ')).toThrow(Error);
  expect(() => commandArgv('  ')).toThrow('empty');
});

test("initialize declares ACP v1, chord, forms and links, plans by id, compactions by id, subagents, terminals' output as meta, and neither files nor terminals; the agent keeps its capabilities", () =>
  withAgent(['--resume-only'], (agent, seen) => {
    const initialize = seen.all.find(
      (traffic) =>
        traffic.from === 'chord' &&
        'method' in traffic.message &&
        traffic.message.method === 'initialize',
    );

    assert(initialize?.from === 'chord' && 'params' in initialize.message);
    expect(initialize.message.params).toStrictEqual({
      protocolVersion: 1,
      clientCapabilities: {
        elicitation: { form: {}, url: {} },
        plan: {},
        session: { compaction: {} },
        subagents: {},
        _meta: { terminal_output_delta: true },
      },
      clientInfo: { name: 'chord', version: manifest.version },
    });
    expect(agent.init.protocolVersion).toStrictEqual(1);
    expect(agent.init.agentCapabilities).toStrictEqual({
      loadSession: true,
      mcpCapabilities: { http: true, sse: true },
      promptCapabilities: { image: true },
      sessionCapabilities: { list: {}, resume: {} },
    });
  }));

test('session/new takes the directory and the MCP servers', () =>
  withAgent([], async (agent, seen, cwd) => {
    const servers: acp.McpServer[] = [
      {
        name: 'files',
        command: '/bin/files',
        args: ['--root', cwd],
        env: [{ name: 'TOKEN', value: 'x' }],
      },
    ];
    const { sessionId } = await agent.newSession({ cwd, mcpServers: servers });

    await agent.prompt({ sessionId, prompt: [text('mcp')] });

    expect(JSON.parse(seen.said().replace(/^```json|```$/g, ''))).toStrictEqual(
      servers,
    );
  }));

// The fake's `--auth-required`, which chord's tests of a start that needs a
// login play against (CHD-435).
test('an agent nobody signed in to offers its ways in at initialize and refuses session/new authRequired', () =>
  withAgent(['--auth-required', 'methods'], async (agent, _seen, cwd) => {
    expect(agent.init.authMethods).toStrictEqual([
      {
        id: 'fake-login',
        name: 'Log in with the fake',
        description: 'Run `fake login` in the terminal',
      },
      { id: 'fake-sso', name: 'Log in with SSO' },
    ]);
    await expect(
      agent.newSession({ cwd, mcpServers: [] }),
    ).rejects.toMatchObject({
      code: -32000,
      message:
        'Authentication required: run `fake login` from your terminal, or set FAKE_API_KEY',
    });
  }));

test('an agent that says only that it needs a login offers no ways in', () =>
  withAgent(['--auth-required', 'bare'], async (agent, _seen, cwd) => {
    expect(agent.init.authMethods).toBeUndefined();
    await expect(
      agent.newSession({ cwd, mcpServers: [] }),
    ).rejects.toMatchObject({
      code: -32000,
      message: 'Authentication required',
    });
  }));

// The fake's `--start-fails`, which chord's tests of an agent that cannot
// start play against (CHD-454).
describe('an agent that cannot start, as the fake plays it', () => {
  test('a broken one exits 1 before initialize, its traceback on stderr', async () => {
    const refused = openAgent({
      command: fakeAgentCommand(undefined, '--start-fails', 'traceback'),
      cwd: process.cwd(),
      onTraffic: () => {},
      stop: STOP,
      ...REFUSE,
    });

    await expect(refused).rejects.toThrow('The agent exited: ');
    await expect(refused).rejects.toThrow(TRACEBACK_ERROR);
  });

  test('one that prints a line on stdout and exits 0 before initialize leaves chord nothing of it', async () => {
    const refused = openAgent({
      command: fakeAgentCommand(undefined, '--start-fails', 'stdout'),
      cwd: process.cwd(),
      onTraffic: () => {},
      stop: STOP,
      ...REFUSE,
    });

    await expect(refused).rejects.toThrow(/^The agent exited\.$/);
  });

  test('one that is not an ACP agent answers initialize and no session request', () =>
    withAgent(['--start-fails', 'notacp'], async (agent, _seen, cwd) => {
      await expect(
        agent.newSession({ cwd, mcpServers: [] }),
      ).rejects.toMatchObject({
        code: -32601,
        message: 'Method not found: session/new',
        data: undefined,
      });
    }));

  test('one that needs an agent alias refuses session/new -32602 with no data', () =>
    withAgent(['--start-fails', 'alias'], async (agent, _seen, cwd) => {
      await expect(
        agent.newSession({ cwd, mcpServers: [] }),
      ).rejects.toMatchObject({
        code: -32602,
        message:
          'session/new requires `agentAlias` (alias of a configured [agents.<alias>] entry)',
        data: undefined,
      });
    }));
});

test('session/load replays the past before it answers', () =>
  withAgent([], async (agent, seen, cwd) => {
    const sessionId = crypto.randomUUID();

    await agent.loadSession({ sessionId, cwd, mcpServers: [] });

    expect(
      seen
        .updates()
        .filter(
          (update) => update.sessionUpdate !== 'available_commands_update',
        )
        .map((update) => update.sessionUpdate),
    ).toStrictEqual([
      'user_message_chunk',
      'tool_call',
      'agent_message_chunk',
      'user_message_chunk',
      'agent_message_chunk',
    ]);
  }));

test('session/resume is asked only of an agent that offers it', async () => {
  await withAgent([], async (agent, seen, cwd) => {
    const refused = agent.resumeSession({
      sessionId: crypto.randomUUID(),
      cwd,
    });

    await expect(refused).rejects.toThrow(Error);
    await expect(refused).rejects.toThrow('does not offer session/resume');
    expect(!seen.sent().includes('session/resume')).toBeTruthy();
  });

  await withAgent(['--resume-only'], async (agent, seen, cwd) => {
    await agent.resumeSession({ sessionId: crypto.randomUUID(), cwd });

    expect(seen.sent().includes('session/resume')).toBeTruthy();
  });
});

test('session/fork is asked only of an agent that offers it, and answers a new session (CHD-101)', async () => {
  await withAgent([], async (agent, seen, cwd) => {
    const refused = agent.forkSession({ sessionId: crypto.randomUUID(), cwd });

    await expect(refused).rejects.toThrow('does not offer session/fork');
    expect(!seen.sent().includes('session/fork')).toBeTruthy();
  });

  await withAgent(['--fork'], async (agent, seen, cwd) => {
    const source = await agent.newSession({ cwd, mcpServers: [] });
    const fork = await agent.forkSession({ sessionId: source.sessionId, cwd });

    expect(seen.sent().includes('session/fork')).toBeTruthy();
    expect(fork.sessionId).not.toStrictEqual(source.sessionId);
  });
});

test('session/list gives the sessions in a directory', () =>
  withAgent([], async (agent, _seen, cwd) => {
    const first = await agent.newSession({ cwd, mcpServers: [] });
    const second = await agent.newSession({ cwd, mcpServers: [] });

    await agent.newSession({ cwd: '/elsewhere', mcpServers: [] });

    const { sessions } = await agent.listSessions({ cwd });

    expect(sessions.map((session) => session.sessionId)).toStrictEqual([
      second.sessionId,
      first.sessionId,
    ]);
  }));

test('a prompt carries text, images and resource links', () =>
  withAgent(['--no-usage'], async (agent, seen, cwd) => {
    const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });
    const answer = await agent.prompt({
      sessionId,
      prompt: [
        { type: 'image', mimeType: 'image/png', data: btoa('png!') },
        {
          type: 'resource_link',
          name: 'README.md',
          uri: 'file:///repo/README.md',
        },
        text('text'),
      ],
    });

    expect(answer).toStrictEqual({ stopReason: 'end_turn' });
    expect(seen.said()).toStrictEqual(
      'Received an image: image/png, 4 bytes\n\n' +
        'Received a link: README.md, file:///repo/README.md\n\n' +
        'Hello, world. This reply came in chunks.',
    );
  }));

test("a turn's updates reach the subscriber, in order, before its answer settles", () =>
  withAgent([], async (agent, seen, cwd) => {
    const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });
    const answer = await agent.prompt({ sessionId, prompt: [text('text')] });
    const response = seen.all.findIndex(
      (traffic) =>
        traffic.from === 'agent' &&
        'result' in traffic.message &&
        (traffic.message.result as acp.PromptResponse | null)?.stopReason ===
          'end_turn',
    );
    const updates = seen.all.flatMap((traffic, index) =>
      traffic.from === 'agent' &&
      'method' in traffic.message &&
      traffic.message.method === 'session/update'
        ? [index]
        : [],
    );

    expect(seen.said()).toStrictEqual(
      'Hello, world. This reply came in chunks.',
    );
    expect(answer.usage?.totalTokens).toStrictEqual(2000);
    expect(
      response > Math.max(...updates),
      'the answer came before an update',
    ).toBeTruthy();
    expect(
      seen.updates().at(-1)?.sessionUpdate,
      'the usage the agent sent before answering is in',
    ).toStrictEqual('usage_update');
  }));

test('an update the agent sends after answering still reaches the subscriber, without a wait on the answer', () =>
  withAgent([], async (agent, seen, cwd) => {
    const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });

    await agent.prompt({ sessionId, prompt: [text('late')] });

    expect(seen.said()).toStrictEqual('Answered.');
    await eventually(() => seen.said() === 'Answered. Late, after the answer.');
  }));

test('an update or notification of a kind no schema knows comes through raw, and nothing is said on the console', async () => {
  const errors: unknown[] = [];
  const { error, warn } = console;

  console.error = (...args: unknown[]) => void errors.push(args);
  console.warn = console.error;

  try {
    await withAgent([], async (agent, seen, cwd) => {
      const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });

      await agent.prompt({ sessionId, prompt: [text('unknown')] });

      expect(
        seen
          .updates()
          .find(
            (update) => (update.sessionUpdate as string) === 'future_update',
          ),
      ).toStrictEqual({
        sessionUpdate: 'future_update',
        detail: 'from later',
      } as unknown as acp.SessionUpdate);
      expect(seen.notified('_fake/notice')).toStrictEqual([
        { text: 'an extension' },
      ]);
      expect(seen.said()).toStrictEqual('Sent the unknown.');
    });
  } finally {
    console.error = error;
    console.warn = warn;
  }

  expect(errors).toStrictEqual([]);
});

test('a cancel ends the turn, and the agent answers it cancelled', () =>
  withAgent([], async (agent, seen, cwd) => {
    const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });
    const turn = agent.prompt({ sessionId, prompt: [text('slow')] });

    await eventually(() => seen.said().startsWith('Working'));
    await agent.cancel(sessionId);

    expect((await turn).stopReason).toStrictEqual('cancelled');
  }));

test('steering is read from initialize, and an agent that does not advertise it is never asked', async () => {
  await withAgent([], async (agent, seen, cwd) => {
    const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });
    const refused = agent.steer({ sessionId, prompt: [text('text')] });

    expect(agent.steering).toStrictEqual(false);
    await expect(refused).rejects.toThrow('does not offer _session/steering');
    expect(!seen.sent().includes('_session/steering')).toBeTruthy();
  });

  for (const adapter of ['claude', 'codex']) {
    await withAgent(['--steering', adapter], (agent) => {
      expect(agent.steering).toStrictEqual(true);
      expect(agent.init._meta).toStrictEqual({ steering: { supported: true } });
    });
  }
});

for (const adapter of ['claude', 'codex']) {
  test(`a steer goes into the running turn, which reads it at its next step, as ${adapter}'s adapter does`, () =>
    withAgent(['--steering', adapter], async (agent, seen, cwd) => {
      const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });
      const turn = agent.prompt({ sessionId, prompt: [text('slow')] });

      await eventually(() => seen.said().startsWith('Working'));

      const answer = await agent.steer({
        sessionId,
        prompt: [text('<message from="main">\nStop.\n</message>')],
        _meta: { steering: { idleBehavior: 'promptRequired' } },
      });

      expect(answer).toStrictEqual({ outcome: 'injected' });
      await eventually(() =>
        seen.said().includes('Read the message from main.'),
      );
      await agent.cancel(sessionId);
      expect((await turn).stopReason).toStrictEqual('cancelled');
    }));
}

test("with no turn running, Claude's adapter answers promptRequired where asked and does nothing, and starts a turn of its own where not", () =>
  withAgent(['--steering', 'claude'], async (agent, seen, cwd) => {
    const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });

    expect(
      await agent.steer({
        sessionId,
        prompt: [text('text')],
        _meta: { steering: { idleBehavior: 'promptRequired' } },
      }),
    ).toStrictEqual({ outcome: 'promptRequired', reason: 'noRunningTurn' });
    expect(seen.said()).toStrictEqual('');

    expect(
      await agent.steer({ sessionId, prompt: [text('text')] }),
    ).toStrictEqual({ outcome: 'startedNewTurn' });
    await eventually(() =>
      seen.said().startsWith('Hello, world. This reply came in chunks.'),
    );
    expect(!seen.sent().includes('session/prompt')).toBeTruthy();
  }));

test("with no turn running, Codex's adapter starts a turn of its own that no prompt of chord's owns, whatever it was asked", () =>
  withAgent(['--steering', 'codex'], async (agent, seen, cwd) => {
    const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });

    expect(
      await agent.steer({
        sessionId,
        prompt: [text('text')],
        _meta: { steering: { idleBehavior: 'promptRequired' } },
      }),
    ).toStrictEqual({ outcome: 'startedNewTurn' });
    await eventually(() =>
      seen.said().startsWith('Hello, world. This reply came in chunks.'),
    );
    expect(!seen.sent().includes('session/prompt')).toBeTruthy();
  }));

test("a prompt's signal stops the wait and cancels the turn", () =>
  withAgent([], async (agent, seen, cwd) => {
    const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });
    const stop = new AbortController();
    const turn = agent.prompt(
      { sessionId, prompt: [text('slow')] },
      stop.signal,
    );

    await eventually(() => seen.said().startsWith('Working'));
    stop.abort(new Error('given up'));

    await expect(turn).rejects.toThrow(Error);
    await expect(turn).rejects.toThrow('given up');
    expect(seen.sent().includes('session/cancel')).toBeTruthy();
  }));

test('config options, modes and models are set on the agent', () =>
  withAgent([], async (agent, seen, cwd) => {
    const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });
    const { configOptions } = await agent.setConfigOption({
      sessionId,
      configId: 'effort',
      value: 'high',
    });

    expect(
      configOptions.find((option) => option.id === 'effort')?.currentValue,
    ).toStrictEqual('high');

    await agent.setMode({ sessionId, modeId: 'plan' });
    await agent.setModel({ sessionId, modelId: 'fake-small' });
    await agent.prompt({ sessionId, prompt: [text('mode')] });

    expect(seen.said()).toStrictEqual('Mode: plan.');

    const usage = seen
      .updates()
      .findLast((update) => update.sessionUpdate === 'usage_update');

    assert(usage?.sessionUpdate === 'usage_update');
    expect(usage.size, "the small model's window").toStrictEqual(200_000);

    const refused = agent.setModel({ sessionId, modelId: 'no-such-model' });

    await expect(refused).rejects.toThrow(Error);
    await expect(refused).rejects.toThrow('not available');
  }));

test('a request whose signal has already stopped is never sent, so it changes nothing and starts no turn', () =>
  withAgent([], async (agent, seen, cwd) => {
    const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });
    const signal = AbortSignal.abort(new Error('already stopped'));
    const before = seen.sent().length;
    const withdrawn = [
      () => agent.newSession({ cwd, mcpServers: [] }, signal),
      () => agent.loadSession({ sessionId, cwd, mcpServers: [] }, signal),
      () => agent.listSessions({ cwd }, signal),
      () =>
        agent.setConfigOption(
          { sessionId, configId: 'effort', value: 'high' },
          signal,
        ),
      () => agent.setMode({ sessionId, modeId: 'plan' }, signal),
      () => agent.setModel({ sessionId, modelId: 'fake-small' }, signal),
      () => agent.prompt({ sessionId, prompt: [text('mode')] }, signal),
    ];

    for (const ask of withdrawn) {
      const asking = ask();

      await expect(asking).rejects.toThrow(Error);
      await expect(asking).rejects.toThrow('already stopped');
    }

    expect(
      seen.sent().slice(before),
      'nothing reached the agent',
    ).toStrictEqual([]);

    await agent.prompt({ sessionId, prompt: [text('mode')] });

    expect(seen.said(), 'one turn, in the old mode').toStrictEqual(
      'Mode: default.',
    );
  }));

test('an open whose signal has already stopped starts no agent and sends nothing', async () => {
  const seen = new Seen();

  const refused = openAgent({
    command: fakeAgentCommand(),
    cwd: process.cwd(),
    onTraffic: seen.push,
    stop: STOP,
    signal: AbortSignal.abort(new Error('already stopped')),
    ...REFUSE,
  });

  await expect(refused).rejects.toThrow(Error);
  await expect(refused).rejects.toThrow('already stopped');
  expect(seen.sent()).toStrictEqual([]);
});

test('a permission is answered by the exact option picked, even among two of one kind', async () => {
  const asked: acp.RequestPermissionRequest[] = [];

  await withAgent(
    [],
    async (agent, seen, cwd) => {
      const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });

      await agent.prompt({ sessionId, prompt: [text('twins')] });

      expect(seen.said()).toStrictEqual('Permission: allow-here.');
    },
    {
      ...REFUSE,
      onPermission: (request) => {
        asked.push(request);

        return Promise.resolve({
          outcome: { outcome: 'selected', optionId: 'allow-here' },
        });
      },
    },
  );

  expect(asked[0]?.options.map((option) => option.kind)).toStrictEqual([
    'allow_once',
    'allow_once',
    'reject_once',
  ]);
});

test('a cancel answers a permission still waiting on the person as cancelled', async () => {
  let withdrawn: AbortSignal | undefined;

  await withAgent(
    [],
    async (agent, seen, cwd) => {
      const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });
      const turn = agent.prompt({ sessionId, prompt: [text('permission')] });

      await eventually(() => withdrawn !== undefined);
      await agent.cancel(sessionId);

      expect((await turn).stopReason).toStrictEqual('cancelled');
      expect(
        withdrawn?.aborted,
        "the handler's signal was not aborted",
      ).toBeTruthy();

      const answer = seen.all.find(
        (traffic) => traffic.from === 'chord' && 'result' in traffic.message,
      );

      assert(answer?.from === 'chord' && 'result' in answer.message);
      expect(answer.message.result).toStrictEqual({
        outcome: { outcome: 'cancelled' },
      });
    },
    {
      ...REFUSE,
      // The person never answers.
      onPermission: (_, signal) => {
        withdrawn = signal;

        return new Promise(() => {});
      },
    },
  );
});

test('a form is answered with what the person filled in', async () => {
  const asked: acp.CreateElicitationRequest[] = [];

  await withAgent(
    [],
    async (agent, seen, cwd) => {
      const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });

      await agent.prompt({ sessionId, prompt: [text('form')] });

      expect(seen.said()).toStrictEqual(
        'Elicitation answer: accept  \n{"name":"chord"}',
      );
    },
    {
      ...REFUSE,
      onElicitation: (request) => {
        asked.push(request);

        return Promise.resolve({
          action: 'accept',
          content: { name: 'chord' },
        });
      },
    },
  );

  assert(asked[0]?.mode === 'form');
  expect(asked[0].requestedSchema).toStrictEqual(FORM_SCHEMA);
});

test("a link opened is answered, and the agent's elicitation/complete is received", () =>
  withAgent(
    [],
    async (agent, seen, cwd) => {
      const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });

      await agent.prompt({ sessionId, prompt: [text('link')] });

      const [complete] = seen.notified('elicitation/complete');

      expect(seen.said()).toStrictEqual('Elicitation answer: accept');
      expect(
        typeof (complete as { elicitationId?: unknown }).elicitationId ===
          'string',
      ).toBeTruthy();
    },
    {
      ...REFUSE,
      onElicitation: (request) => {
        assert(request.mode === 'url');
        expect(request.url).toStrictEqual(LINK_URL);

        return Promise.resolve({ action: 'accept' });
      },
    },
  ));

test("the agent's stderr reaches the subscriber, and an agent that exits at start says why", async () => {
  const seen = new Seen();

  const refused = openAgent({
    command: ['sh', '-c', 'echo "no credentials" >&2; exit 1'],
    cwd: process.cwd(),
    onTraffic: seen.push,
    stop: STOP,
    ...REFUSE,
  });

  await expect(refused).rejects.toThrow(Error);
  await expect(refused).rejects.toThrow('The agent exited: no credentials');
  expect(seen.all.filter((traffic) => traffic.from === 'stderr')).toStrictEqual(
    [{ from: 'stderr', text: 'no credentials\n' }],
  );
});

describe('CHD-495: an agent that goes says why, its stderr read to its end first', () => {
  /**
   * An agent process whose pipes the test drives: what chord writes is
   * heard, stdout is closed and stderr written and ended when the test
   * says, in that order, whatever the scheduler would do with real pipes.
   */
  function heldProcess() {
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    let out!: ReadableStreamDefaultController<Uint8Array>;
    let tail = '';
    let written = '';
    const heard: Record<string, unknown>[] = [];
    const stderrEnded = Promise.withResolvers<void>();
    const exit = Promise.withResolvers<{ code: number }>();
    const stopped: number[] = [];
    const held = {
      heard,
      stopped,
      /** Answers the request chord sent under `method` with `result`. */
      answer: (method: string, result: unknown) => {
        const request = heard.find((each) => each['method'] === method);

        assert(request !== undefined, `no ${method} heard`);
        out.enqueue(
          encoder.encode(
            `${JSON.stringify({ jsonrpc: '2.0', id: request['id'], result })}\n`,
          ),
        );
      },
      /** The agent's stdout ends, before its stderr has. */
      closeStdout: () => out.close(),
      /** Its last words and its stderr's end, while it lives on. */
      endStderr: (words: string) => {
        tail += words;

        stderrEnded.resolve();
      },
      /** Its last words, then its stderr's end and its exit. */
      leave: (words: string) => {
        tail += words;

        stderrEnded.resolve();
        exit.resolve({ code: 1 });
      },
      process: {
        pid: 0,
        stdin: new WritableStream<Uint8Array>({
          write: (chunk) => {
            written += decoder.decode(chunk);

            const lines = written.split('\n');

            written = lines.pop()!;

            heard.push(...lines.map((line) => JSON.parse(line)));
          },
        }),
        stdout: new ReadableStream<Uint8Array>({
          start: (controller) => {
            out = controller;
          },
        }),
        status: exit.promise,
        stderrTail: () => tail,
        stderrEnd: () => ({
          lines: tail.split('\n').filter((line) => line.trim() !== ''),
          cut: 0,
        }),
        lastWords: async () => {
          await stderrEnded.promise;

          return tail;
        },
        stop: () => {
          stopped.push(Date.now());
          held.leave('');

          return Promise.resolve();
        },
      } as unknown as Parameters<typeof connectAgent>[0],
    };

    return held;
  }

  /** Waits for `check`, a few seconds at most. */
  const soon = async (check: () => boolean) => {
    const deadline = Date.now() + 5000;

    while (!check()) {
      assert(Date.now() < deadline, 'timed out');
      await new Promise((resolve) => setTimeout(resolve, 5));
    }
  };

  const OPTIONS = {
    command: 'held',
    cwd: process.cwd(),
    onTraffic: () => {},
    stop: STOP,
    ...REFUSE,
  } satisfies OpenAgentOptions;

  /** Whether `promise` has settled by the time the loop is idle. */
  const settled = async (promise: Promise<unknown>) => {
    let done = false;

    void promise.then(
      () => (done = true),
      () => (done = true),
    );
    await new Promise((resolve) => setTimeout(resolve, 50));

    return done;
  };

  const opened = async (held: ReturnType<typeof heldProcess>) => {
    const agent = connectAgent(held.process, OPTIONS);

    await soon(() => held.heard.length > 0);
    held.answer('initialize', {
      protocolVersion: 1,
      agentCapabilities: {},
      authMethods: [],
    });

    return await agent;
  };

  test('at start: the open waits past the end of stdout for the last words, and says them', async () => {
    const held = heldProcess();
    const refused = connectAgent(held.process, OPTIONS);

    refused.catch(() => {});

    await soon(() => held.heard.length > 0);
    held.closeStdout();
    expect(await settled(refused)).toBe(false);
    held.leave('no credentials\n');
    await expect(refused).rejects.toThrow('The agent exited: no credentials');
  });

  test('one that closes its stdout and lives on: the open fails with its last words, no exit, and stops it (CHD-454)', async () => {
    const held = heldProcess();
    const refused = connectAgent(held.process, OPTIONS);

    refused.catch(() => {});

    await soon(() => held.heard.length > 0);
    held.closeStdout();
    held.endStderr('still here\n');
    await expect(refused).rejects.toThrow('The agent exited: still here');
    await expect(refused).rejects.toMatchObject({
      exit: undefined,
      stderr: { lines: ['still here'], cut: 0 },
    });
    expect(held.stopped.length).toBeGreaterThan(0);
  });

  test('mid-session: a request fails with the last words, and gone() gives them once exited', async () => {
    const held = heldProcess();
    const agent = await opened(held);
    const asked = agent.newSession({ cwd: process.cwd(), mcpServers: [] });

    asked.catch(() => {});

    await soon(() => held.heard.length > 1);
    held.closeStdout();
    expect(await settled(asked)).toBe(false);
    held.leave('out of tokens\n');
    await expect(asked).rejects.toThrow('The agent exited: out of tokens');
    await agent.exited;
    expect(agent.gone()).toBe('out of tokens');
  });

  test("the caller's abort while the last words are awaited ends the wait at once, with its reason", async () => {
    const held = heldProcess();
    const agent = await opened(held);
    const caller = new AbortController();
    const reason = new Error('the person pressed esc');
    const asked = agent.newSession(
      { cwd: process.cwd(), mcpServers: [] },
      caller.signal,
    );

    asked.catch(() => {});

    await soon(() => held.heard.length > 1);
    held.closeStdout();
    expect(await settled(asked)).toBe(false);
    caller.abort(reason);
    await expect(asked).rejects.toBe(reason);
    // The agent never said its last words; nothing waits on them.
    expect(held.stopped).toStrictEqual([]);
    await agent.close();
  });

  test('a close while the last words are awaited stops the agent, and the request fails at once', async () => {
    const held = heldProcess();
    const agent = await opened(held);
    const asked = agent.newSession({ cwd: process.cwd(), mcpServers: [] });

    asked.catch(() => {});

    await soon(() => held.heard.length > 1);
    held.closeStdout();
    expect(await settled(asked)).toBe(false);
    await agent.close();
    expect(held.stopped).toHaveLength(1);
    await expect(asked).rejects.toThrow('The agent exited.');
  });

  describe('CHD-454 tester: failure snapshot order', () => {
    test('stdout can close before stderr; an observed status is retained with the eventual diagnostic', async () => {
      const held = heldProcess();
      const status = Promise.withResolvers<{ code: number }>();
      const reading = Promise.withResolvers<void>();
      const process = {
        ...held.process,
        status: status.promise,
        lastWords: () => {
          reading.resolve();

          return held.process.lastWords();
        },
      };
      const refused = connectAgent(process, OPTIONS);
      const failed = refused.catch((error: unknown) => error);

      try {
        await soon(() => held.heard.length > 0);
        held.closeStdout();
        await reading.promise;
        status.resolve({ code: 7 });
        expect(held.stopped).toEqual([]);
        held.endStderr('  delayed frame\nFinal diagnostic\n');

        const error = await failed;

        assert(error instanceof AgentGone);
        expect(error.exit).toEqual({ code: 7 });
        expect(error.stderr).toEqual({
          lines: ['  delayed frame', 'Final diagnostic'],
          cut: 0,
        });
        expect(error.message).toContain('Final diagnostic');
      } finally {
        status.resolve({ code: 7 });
        await held.process.stop();
      }
    });

    test('a status first observed during cleanup is not invented in the already captured failure', async () => {
      const held = heldProcess();
      const status = Promise.withResolvers<{ code: number }>();
      const reading = Promise.withResolvers<void>();
      const process = {
        ...held.process,
        status: status.promise,
        lastWords: () => {
          reading.resolve();

          return held.process.lastWords();
        },
        stop: () => {
          status.resolve({ code: 9 });

          return held.process.stop();
        },
      };
      const refused = connectAgent(process, OPTIONS);
      const failed = refused.catch((error: unknown) => error);

      try {
        await soon(() => held.heard.length > 0);
        held.closeStdout();
        await reading.promise;
        held.endStderr('  captured diagnostic\n');

        const outcome = await settledWithin(failed, 3000);

        assert(outcome?.status === 'fulfilled');
        assert(outcome.value instanceof AgentGone);
        expect(await status.promise).toEqual({ code: 9 });
        expect(outcome.value.exit).toBeUndefined();
        expect(outcome.value.stderr).toEqual({
          lines: ['  captured diagnostic'],
          cut: 0,
        });
        held.endStderr('a later diagnostic\n');
        expect(outcome.value.stderr).toEqual({
          lines: ['  captured diagnostic'],
          cut: 0,
        });
      } finally {
        await process.stop();
      }
    });
  });
});

test('an agent that cannot be started says so', async () => {
  const refused = openAgent({
    command: 'chord-no-such-agent --acp',
    cwd: process.cwd(),
    onTraffic: () => {},
    ...REFUSE,
  });

  await expect(refused).rejects.toThrow(Error);
  await expect(refused).rejects.toThrow('cannot start chord-no-such-agent');
});

/**
 * Starts the fake agent wedged at `step`, plays `body` into it, and proves the
 * close comes back within the bound with the agent's whole group gone.
 */
async function closesWedged(
  step: string,
  body: (agent: Agent, sessionId: string) => void | Promise<void>,
) {
  const tag = `chord-wedged-${crypto.randomUUID()}`;
  const agent = await openAgent({
    command: fakeAgentCommand(undefined, '--hang', step, tag),
    cwd: process.cwd(),
    onTraffic: () => {},
    stop: STOP,
    ...REFUSE,
  });
  const { sessionId } = await agent.newSession({
    cwd: process.cwd(),
    mcpServers: [],
  });

  await body(agent, sessionId);
  // Long enough for the request to be out to the agent.
  await new Promise((resolve) => setTimeout(resolve, 200));

  const started = Date.now();

  await agent.close();
  expect(Date.now() - started < 5000, 'the close was not bounded').toBeTruthy();
  expect(await tagged(tag)).toStrictEqual([]);
}

/** The pids of every process whose command line holds `tag`. */
function tagged(tag: string): Promise<number[]> {
  return new Promise((resolve, reject) => {
    execFile('pgrep', ['-f', tag], (error, stdout) => {
      // pgrep exits 1 when nothing matches, which is an answer too; any
      // other failure, such as a sandbox denying it, would read as nothing
      // running and leave a wait on it spinning.
      if (error && error.code !== 1) {
        reject(error);
      } else {
        resolve(stdout.split('\n').filter(Boolean).map(Number));
      }
    });
  });
}

/**
 * Waits until `check` holds, failing once `ms` pass without it, so a test
 * that cleans up after itself gets to.
 */
async function until(what: string, check: () => Promise<boolean>, ms: number) {
  const deadline = Date.now() + ms;

  while (!(await check())) {
    if (Date.now() > deadline) {
      throw new Error(`no ${what} within ${ms} ms`);
    }

    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}

/** Kills every process whose command line holds `tag`, one a test owns. */
async function killTagged(tag: string) {
  for (const pid of await tagged(tag)) {
    try {
      process.kill(pid, 'SIGKILL');
    } catch {
      // Gone between the look and the kill.
    }
  }
}

test('closing is bounded and kills an agent that never answers a config change', () =>
  closesWedged('config', (agent, sessionId) => {
    agent
      .setConfigOption({ sessionId, configId: 'effort', value: 'high' })
      .catch(() => {});
  }));

test('closing is bounded and kills an agent whose turn ignores its cancel', () =>
  closesWedged('turn', (agent, sessionId) => {
    agent.prompt({ sessionId, prompt: [text('text')] }).catch(() => {});

    agent.cancel(sessionId).catch(() => {});
  }));

test("a request's signal stops the wait on an agent that never answers", () =>
  closesWedged('config', async (agent, sessionId) => {
    const stop = new AbortController();
    const asked = agent.setMode({ sessionId, modeId: 'plan' }, stop.signal);

    setTimeout(() => stop.abort(new Error('given up')), 100);
    await expect(asked).rejects.toThrow(Error);
    await expect(asked).rejects.toThrow('given up');
  }));

test('a wedged fake agent goes when the process that started it is killed', async () => {
  const tag = `chord-wedged-${crypto.randomUUID()}`;
  const command = fakeAgentCommand(undefined, '--hang', 'config', tag);
  // A stand-in for a test run killed mid-test: it starts the fake in a group
  // of its own, as chord does, says so once the fake has answered
  // `initialize`, so it is past reading who its parent is, and then dies
  // without closing it.
  const starter = spawn(
    process.execPath,
    [
      '-e',
      `const [program, ...args] = ${JSON.stringify(command)};
      const fake = require('node:child_process').spawn(program, args, {
        detached: true,
        stdio: ['pipe', 'pipe', 'ignore'],
      });
      fake.stdout.once('data', () => process.stdout.write('ready\\n'));
      fake.stdin.write(JSON.stringify({
        jsonrpc: '2.0',
        id: 0,
        method: 'initialize',
        params: { protocolVersion: 1 },
      }) + '\\n');
      setInterval(() => {}, 1000);`,
    ],
    { stdio: ['ignore', 'pipe', 'inherit'] },
  );

  let ready = false;

  starter.stdout.once('data', () => (ready = true));

  try {
    await until(
      'answer to initialize',
      () => {
        assert.equal(starter.exitCode, null, 'the starter ended');

        return Promise.resolve(ready);
      },
      10_000,
    );
    starter.kill('SIGKILL');
    await until(
      'end of the orphaned fake',
      async () => (await tagged(tag)).length === 0,
      5000,
    );
  } finally {
    starter.kill('SIGKILL');
    await killTagged(tag);
  }
});

test('an open given up while the agent never answers initialize leaves nothing running', async () => {
  const tag = `chord-wedged-${crypto.randomUUID()}`;
  const stop = new AbortController();
  const opening = openAgent({
    command: fakeAgentCommand(undefined, '--hang', 'start', tag),
    cwd: process.cwd(),
    onTraffic: () => {},
    stop: STOP,
    signal: stop.signal,
    ...REFUSE,
  });

  try {
    await until(
      'agent started',
      async () => (await tagged(tag)).length > 0,
      10_000,
    );

    const started = Date.now();

    stop.abort(new Error('given up'));
    await expect(opening).rejects.toThrow(Error);
    await expect(opening).rejects.toThrow('given up');
    expect(
      Date.now() - started < 5000,
      'the open did not give up in time',
    ).toBeTruthy();
    expect(await tagged(tag)).toStrictEqual([]);
  } finally {
    // Whatever failed above, the open is given up and its agent stopped.
    stop.abort(new Error('given up'));
    await opening.catch(() => {});
  }
});

describe('CHD-467 tester: EOF releases the fake gate without a termination signal', () => {
  for (const count of [0, 1]) {
    test(`closing stdin while bashtwo has ${count} messages exits normally`, () =>
      withAgent(['--steering', 'claude'], async (agent, seen, cwd) => {
        const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });
        const running = agent.prompt({ sessionId, prompt: [text('bashtwo')] });

        running.catch(() => {});

        await eventually(() =>
          seen
            .updates()
            .some(
              (update) =>
                update.sessionUpdate === 'tool_call_update' &&
                update.status === 'completed',
            ),
        );

        if (count === 1) {
          expect(
            await agent.steer({ sessionId, prompt: [text('Only one.')] }),
          ).toMatchObject({ outcome: 'injected' });
        }

        await agent.close();

        const exit = await agent.exited;

        expect(exit).toEqual({ code: 0 });
        expect(seen.said()).not.toContain('Two files changed.');
        await running.catch(() => {});
      }));
  }
});

describe('CHD-450 tester: unfinished call wire reports', () => {
  for (const [scenario, status] of [
    ['cutcallsunfinished', 'failed'],
    ['cutcallsunfinishedv2', 'cancelled'],
  ] as const) {
    test(`${scenario} preserves announcement, partial input and unstructured final reports in wire order`, () =>
      withAgent(['--steering', 'claude'], async (agent, seen, cwd) => {
        const { sessionId } = await agent.newSession({ cwd, mcpServers: [] });
        const answer = await agent.prompt({
          sessionId,
          prompt: [text(scenario)],
        });
        const updates = seen
          .updates()
          .filter(
            (update) =>
              update.sessionUpdate === 'tool_call' ||
              update.sessionUpdate === 'tool_call_update' ||
              update.sessionUpdate === 'agent_message_chunk',
          );
        const first = updates[0];
        const second = updates[2];

        assert(first?.sessionUpdate === 'tool_call');
        assert(second?.sessionUpdate === 'tool_call');
        expect(first.toolCallId).not.toBe(second.toolCallId);
        expect(answer.stopReason).toBe('end_turn');

        const expectedUpdates: readonly unknown[] = [
          {
            _meta: { claudeCode: { toolName: 'mcp__chord__send_message' } },
            toolCallId: first.toolCallId,
            sessionUpdate: 'tool_call',
            name: 'mcp__chord__send_message',
            rawInput: {},
            status: 'pending',
            title: 'mcp__chord__send_message',
            kind: 'other',
            content: [],
          },
          {
            _meta: { claudeCode: { toolName: 'mcp__chord__send_message' } },
            toolCallId: first.toolCallId,
            sessionUpdate: 'tool_call_update',
            rawInput: { to: 'main' },
            title: 'mcp__chord__send_message',
            kind: 'other',
          },
          {
            _meta: { claudeCode: { toolName: 'mcp__chord__open_agent' } },
            toolCallId: second.toolCallId,
            sessionUpdate: 'tool_call',
            name: 'mcp__chord__open_agent',
            rawInput: {},
            status: 'pending',
            title: 'mcp__chord__open_agent',
            kind: 'other',
            content: [],
          },
          {
            sessionUpdate: 'agent_message_chunk',
            content: {
              type: 'text',
              text: 'Read the steer; I will answer that first.',
            },
          },
          ...[first.toolCallId, second.toolCallId].map((toolCallId) => ({
            sessionUpdate: 'tool_call_update',
            toolCallId,
            status,
            content: [
              {
                type: 'content',
                content: {
                  type: 'text',
                  text: 'Claude stopped this tool call before it ran.',
                },
              },
            ],
          })),
        ];

        expect(updates as readonly unknown[]).toStrictEqual(expectedUpdates);

        // The final reports precede the prompt response, rather than
        // arriving after chord has already considered the turn settled.
        const prompt = seen.all.find(
          (traffic) =>
            traffic.from === 'chord' &&
            'method' in traffic.message &&
            traffic.message.method === 'session/prompt',
        );

        assert(prompt?.from === 'chord' && 'id' in prompt.message);

        const requestId = prompt.message.id;
        const response = seen.all.findIndex(
          (traffic) =>
            traffic.from === 'agent' &&
            'id' in traffic.message &&
            traffic.message.id === requestId &&
            'result' in traffic.message,
        );
        const lastUpdate = seen.all.findLastIndex(
          (traffic) =>
            traffic.from === 'agent' &&
            'method' in traffic.message &&
            traffic.message.method === 'session/update',
        );

        expect(response).toBeGreaterThan(lastUpdate);
      }));
  }
});

describe('CHD-435 tester: auth-required fixture boundaries', () => {
  async function onAuthFixture(
    flags: string[],
    environment: Readonly<Record<string, string>>,
    body: (agent: Agent, seen: Seen, cwd: string) => Promise<void>,
  ) {
    const cwd = await mkdtemp(join(tmpdir(), 'chord-auth-fixture-'));
    const seen = new Seen();
    const agent = await openAgent({
      command: fakeAgentCommand(undefined, '--resume-only', ...flags),
      cwd,
      env: environment,
      onTraffic: seen.push,
      stop: STOP,
      ...REFUSE,
    });

    try {
      await body(agent, seen, cwd);
    } finally {
      await agent.close();
      await rm(cwd, { recursive: true });
      expect(await isAlive(agent.pid)).toBe(false);
    }
  }

  for (const kind of ['methods', 'bare'] as const) {
    for (const source of ['flag', 'environment'] as const) {
      test(`${source} selects ${kind}; new, load and resume reject without creating or replaying a session`, () =>
        onAuthFixture(
          source === 'flag' ? ['--auth-required', kind] : [],
          { CHORD_FAKE_AUTH_REQUIRED: source === 'environment' ? kind : '' },
          async (agent, seen, cwd) => {
            const error = {
              code: -32000,
              message:
                kind === 'methods'
                  ? 'Authentication required: run `fake login` from your terminal, or set FAKE_API_KEY'
                  : 'Authentication required',
            };

            expect(agent.init.authMethods?.map((method) => method.id)).toEqual(
              kind === 'methods' ? ['fake-login', 'fake-sso'] : undefined,
            );
            await expect(
              agent.newSession({ cwd, mcpServers: [] }),
            ).rejects.toMatchObject(error);

            // Authentication wins even over validation of an unknown id.
            for (const sessionId of [crypto.randomUUID(), 'not-a-session']) {
              await expect(
                agent.loadSession({ sessionId, cwd, mcpServers: [] }),
              ).rejects.toMatchObject(error);
              await expect(
                agent.resumeSession({ sessionId, cwd }),
              ).rejects.toMatchObject(error);
            }

            expect((await agent.listSessions({ cwd })).sessions).toEqual([]);
            expect(seen.updates()).toEqual([]);
            expect(
              seen.sent().filter((method) => method === 'session/load'),
            ).toHaveLength(2);
            expect(
              seen.sent().filter((method) => method === 'session/resume'),
            ).toHaveLength(2);
            expect(seen.sent()).not.toContain('authenticate');
          },
        ));
    }

    test(`the ${kind} CLI value wins over the other environment value`, () =>
      onAuthFixture(
        ['--auth-required', kind],
        { CHORD_FAKE_AUTH_REQUIRED: kind === 'methods' ? 'bare' : 'methods' },
        async (agent, _seen, cwd) => {
          expect(agent.init.authMethods?.length).toBe(
            kind === 'methods' ? 2 : undefined,
          );
          await expect(
            agent.newSession({ cwd, mcpServers: [] }),
          ).rejects.toMatchObject({
            code: -32000,
            message:
              kind === 'methods'
                ? 'Authentication required: run `fake login` from your terminal, or set FAKE_API_KEY'
                : 'Authentication required',
          });
        },
      ));
  }
});

describe('CHD-454 tester: startup fixture wire boundaries', () => {
  test('notacp refuses new, load and resume without session effects or error data', () =>
    withAgent(
      ['--start-fails', 'notacp', '--resume-only'],
      async (agent, seen, cwd) => {
        const sessionId = crypto.randomUUID();
        const requests = [
          ['session/new', () => agent.newSession({ cwd, mcpServers: [] })],
          [
            'session/load',
            () => agent.loadSession({ sessionId, cwd, mcpServers: [] }),
          ],
          ['session/resume', () => agent.resumeSession({ sessionId, cwd })],
        ] as const;

        for (const [method, request] of requests) {
          await expect(request()).rejects.toMatchObject({
            code: -32601,
            message: `Method not found: ${method}`,
          });
        }

        const errors = seen.all.flatMap((traffic) =>
          traffic.from === 'agent' && 'error' in traffic.message
            ? [traffic.message.error]
            : [],
        );

        expect(errors).toStrictEqual(
          requests.map(([method]) => ({
            code: -32601,
            message: `Method not found: ${method}`,
          })),
        );
        expect(seen.updates()).toEqual([]);
        expect((await agent.listSessions({ cwd })).sessions).toEqual([]);
      },
    ));

  test('alias rejects only new with no wire data; load still replays and resume still opens', () =>
    withAgent(
      ['--start-fails', 'alias', '--resume-only'],
      async (agent, seen, cwd) => {
        await expect(
          agent.newSession({ cwd, mcpServers: [] }),
        ).rejects.toMatchObject({ code: -32602 });

        const errors = seen.all.flatMap((traffic) =>
          traffic.from === 'agent' && 'error' in traffic.message
            ? [traffic.message.error]
            : [],
        );

        expect(errors).toStrictEqual([
          {
            code: -32602,
            message:
              'session/new requires `agentAlias` (alias of a configured [agents.<alias>] entry)',
          },
        ]);
        expect(seen.updates()).toEqual([]);

        const sessionId = crypto.randomUUID();

        await agent.loadSession({ sessionId, cwd, mcpServers: [] });
        expect(seen.said()).toContain(
          'Hello, world. This reply came in chunks.',
        );

        const replies = seen
          .updates()
          .filter((update) => update.sessionUpdate === 'agent_message_chunk');

        await agent.resumeSession({ sessionId, cwd });
        expect(
          seen
            .updates()
            .filter((update) => update.sessionUpdate === 'agent_message_chunk'),
        ).toEqual(replies);
        expect(seen.sent()).toContain('session/resume');
      },
    ));

  for (const kind of ['traceback', 'stdout', 'notacp', 'alias']) {
    test(`the environment selects ${kind}, preserving the piped stderr tail or session refusal`, async () => {
      const cwd = await mkdtemp(join(tmpdir(), 'chord-start-fixture-'));
      const seen = new Seen();
      let agent: Agent | undefined;

      try {
        const opening = openAgent({
          command: fakeAgentCommand(),
          cwd,
          env: { CHORD_FAKE_START_FAILS: kind },
          onTraffic: seen.push,
          stop: STOP,
          ...REFUSE,
        });

        if (kind === 'traceback' || kind === 'stdout') {
          let failure: unknown;

          try {
            agent = await opening;
          } catch (error) {
            failure = error;
          }

          assert(failure instanceof Error);

          const stderr = seen.all
            .flatMap((traffic) =>
              traffic.from === 'stderr' ? [traffic.text] : [],
            )
            .join('');

          if (kind === 'traceback') {
            expect(stderr.length).toBeGreaterThan(4096);
            expect(stderr).toContain('module_0.py');
            expect(stderr).toContain('module_59.py');
            expect(stderr.endsWith(TRACEBACK_ERROR + '\n')).toBe(true);
            expect(failure.message.endsWith(TRACEBACK_ERROR)).toBe(true);
          } else {
            expect(stderr).toBe('');
            expect(failure.message).toBe('The agent exited.');
          }
        } else {
          agent = await opening;

          await expect(
            agent.newSession({ cwd, mcpServers: [] }),
          ).rejects.toMatchObject({
            code: kind === 'notacp' ? -32601 : -32602,
          });
        }
      } finally {
        await agent?.close();
        await rm(cwd, { recursive: true });
      }
    });
  }
});
