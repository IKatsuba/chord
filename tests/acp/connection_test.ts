import { execFile } from 'node:child_process';
import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import type * as acp from '@agentclientprotocol/sdk';
import {
  type Agent,
  openAgent,
  type OpenAgentOptions,
} from '../../src/acp/connection.ts';
import manifest from '../../package.json' with { type: 'json' };
import { commandArgv } from '../../src/acp/process.ts';
import type { Traffic } from '../../src/acp/traffic.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
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
  // pgrep exits 1 when nothing matches, which is an answer too.
  return new Promise((resolve) => {
    execFile('pgrep', ['-f', tag], (_error, stdout) =>
      resolve(stdout.split('\n').filter(Boolean).map(Number)),
    );
  });
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

  while ((await tagged(tag)).length === 0) {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }

  const started = Date.now();

  stop.abort(new Error('given up'));
  await expect(opening).rejects.toThrow(Error);
  await expect(opening).rejects.toThrow('given up');
  expect(
    Date.now() - started < 5000,
    'the open did not give up in time',
  ).toBeTruthy();
  expect(await tagged(tag)).toStrictEqual([]);
});
