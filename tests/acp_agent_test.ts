import { describe, expect, test } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { type AcpOptions, type AcpRun, runAcp } from '../src/acp_agent.ts';
import { killSpawnedGroups } from '../src/platform/process.ts';
import type { LeaveExit } from '../src/session/leaving.ts';
import { openSession } from '../src/session/session.ts';
import {
  type AcpClient,
  clientOverStreams,
  type WireMessage,
} from './fixtures/acp_client.ts';
import { fakeAgentCommand, gatedCommand } from './fixtures/fake.ts';
import { until } from './session/conversation_fake.ts';

const FULL = {
  subagents: {},
  plan: {},
  session: { compaction: {}, notices: {} },
};

interface Acp {
  readonly client: AcpClient;
  readonly cwd: string;
  readonly lines: string[];
  readonly exits: LeaveExit[];
  readonly run: AcpRun;
  /** Ends chord's stdin, and waits for the way out. */
  eof(): Promise<void>;
  /** A new session's id, on the agent as started. */
  newSession(): Promise<string>;
  /** Sends a prompt of plain words; its request's id. */
  prompt(sessionId: string, text: string): number;
}

async function onAcp(
  flags: readonly string[],
  body: (acp: Acp) => Promise<void>,
  {
    capabilities = FULL,
    ...over
  }: Partial<AcpOptions> & { capabilities?: object } = {},
): Promise<void> {
  const cwd = await mkdtemp(join(tmpdir(), 'chord-acp-'));
  const { client, input, output, end } = clientOverStreams();
  const lines: string[] = [];
  const exits: LeaveExit[] = [];
  const run = runAcp({
    input,
    output,
    stderr: (line) => lines.push(line),
    exit: (how) => exits.push(how),
    agent: 'fake',
    agentCommand: fakeAgentCommand(undefined, ...flags),
    version: '1.2.3',
    open: openSession,
    place: () => Promise.resolve({ mcpServers: [] }),
    ...over,
  });

  const eof = async () => {
    end();

    await until(() => exits.length > 0, 20_000);
  };

  try {
    await client.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: capabilities,
    });
    await body({
      client,
      cwd,
      lines,
      exits,
      run,
      eof,
      newSession: async () => {
        const { result, error } = await client.request('session/new', {
          cwd,
          mcpServers: [],
        });

        expect(error).toBeUndefined();

        return result?.sessionId as string;
      },
      prompt: (sessionId, text) =>
        client.send('session/prompt', {
          sessionId,
          prompt: [{ type: 'text', text }],
        }),
    });
  } finally {
    await eof();
    // No process left behind, whatever the test did.
    await until(() => killSpawnedGroups().length === 0);
    await rm(cwd, { recursive: true, force: true });
  }
}

const kinds = (client: AcpClient, sessionId?: string) =>
  client.updates(sessionId).map((update) => update.sessionUpdate);

describe('initialize', () => {
  test('answers what the design says, starting no agent', async () => {
    let opened = 0;

    await onAcp(
      [],
      async ({ client }) => {
        const { result } = await client.answerTo(1);

        expect(result).toEqual({
          protocolVersion: 1,
          agentInfo: { name: 'chord', version: '1.2.3' },
          authMethods: [],
          agentCapabilities: {
            loadSession: true,
            promptCapabilities: {
              image: true,
              audio: false,
              embeddedContext: false,
            },
            mcpCapabilities: { http: true, sse: true },
            sessionCapabilities: { list: {}, resume: {}, close: {} },
          },
          _meta: {
            'chord/acp': {
              version: 1,
              extensions: {},
              agent: { name: 'fake' },
            },
          },
        });
        expect(opened).toBe(0);
      },
      {
        open: (options) => {
          opened += 1;

          return openSession(options);
        },
      },
    );
  });

  test('authenticate is -32601, as nothing there asks for it', () =>
    onAcp([], async ({ client }) => {
      const { error } = await client.request('authenticate', { methodId: 'x' });

      expect(error?.code).toBe(-32601);
    }));

  test('a line that is not JSON, or a batch, leaves the next prompt answered', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      client.raw('garbage');

      expect(
        (await client.until((message) => message.error?.code === -32700)).id,
      ).toBeNull();

      client.raw('[{"jsonrpc":"2.0"}]');

      await client.until((message) => message.error?.code === -32600);

      const sessionId = await newSession();
      const { result } = await client.answerTo(prompt(sessionId, 'text'));

      expect(result?.stopReason).toBe('end_turn');
    }));
});

describe('a whole turn', () => {
  test('updates under the session, then its answer, every line JSON', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const answer = await client.answerTo(prompt(sessionId, 'text'));

      expect(answer.result?.stopReason).toBe('end_turn');
      expect(client.said(sessionId)).not.toBe('');

      for (const line of client.lines) {
        expect(() => JSON.parse(line) as unknown).not.toThrow();
      }
    }));

  test('tool calls come through whole', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();

      await client.answerTo(prompt(sessionId, 'tools'));

      expect(kinds(client, sessionId)).toContain('tool_call');
      expect(kinds(client, sessionId)).toContain('tool_call_update');
    }));

  test('a resource_link reaches the agent; an image an agent lacks is -32602', () =>
    onAcp(['--no-images'], async ({ client, newSession }) => {
      const session = await client.request('session/new', {
        cwd: tmpdir(),
        mcpServers: [],
      });

      expect(session.result?._meta).toMatchObject({
        'chord/acp': { image: false },
      });

      const sessionId = await newSession();
      const { error } = await client.request('session/prompt', {
        sessionId,
        prompt: [{ type: 'image', data: 'AAAA', mimeType: 'image/png' }],
      });

      expect(error?.code).toBe(-32602);
      expect(error?.message).toContain('fake does not take images');

      const uri = 'file:///somewhere/a.ts';

      await client.request('session/prompt', {
        sessionId,
        prompt: [
          { type: 'text', text: 'text' },
          { type: 'resource_link', name: 'a.ts', uri },
        ],
      });

      expect(client.said(sessionId)).toContain(`a.ts, ${uri}`);
    }));

  test('resource and audio blocks are -32602', () =>
    onAcp([], async ({ client, newSession }) => {
      const sessionId = await newSession();

      for (const block of [
        { type: 'audio', data: 'AAAA', mimeType: 'audio/wav' },
        { type: 'resource', resource: { uri: 'file:///a', text: 'x' } },
      ]) {
        const { error } = await client.request('session/prompt', {
          sessionId,
          prompt: [block],
        });

        expect(error?.code).toBe(-32602);
      }
    }));

  test('a prompt to no session is -32002', () =>
    onAcp([], async ({ client, prompt }) => {
      expect(
        (await client.answerTo(prompt('nobody', 'text'))).error?.code,
      ).toBe(-32002);
    }));
});

describe('cancel', () => {
  test('session/cancel: the turn and every queued prompt cancelled, once each', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'long');

      await until(() => client.said(sessionId) !== '');

      const queued = prompt(sessionId, 'text');

      client.notify('session/cancel', { sessionId });

      expect((await client.answerTo(running)).result?.stopReason).toBe(
        'cancelled',
      );
      expect((await client.answerTo(queued)).result?.stopReason).toBe(
        'cancelled',
      );
      expect(
        client.messages.filter(
          (message) => message.id === running && !message.method,
        ),
      ).toHaveLength(1);
    }));

  test('$/cancel_request on a queued prompt takes it alone', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'long');

      await until(() => client.said(sessionId) !== '');

      const first = prompt(sessionId, 'one');
      const second = prompt(sessionId, 'text');

      client.notify('$/cancel_request', { requestId: first });

      expect((await client.answerTo(first)).result?.stopReason).toBe(
        'cancelled',
      );
      expect(
        client.messages.some(
          (message) => message.id === running && !message.method,
        ),
      ).toBe(false);

      client.notify('$/cancel_request', { requestId: running });

      expect((await client.answerTo(running)).result?.stopReason).toBe(
        'cancelled',
      );
      expect((await client.answerTo(second)).result?.stopReason).toBe(
        'end_turn',
      );
    }));

  test('a cancel of a request already answered changes nothing', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const done = prompt(sessionId, 'text');

      await client.answerTo(done);

      client.notify('$/cancel_request', { requestId: done });

      expect(
        (await client.answerTo(prompt(sessionId, 'text'))).result?.stopReason,
      ).toBe('end_turn');
    }));

  test('an agent that ignores a cancel: open, no timer, until session/close', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'ignorescancel');

      await until(() => client.said(sessionId).includes('Holding on.'));

      client.notify('session/cancel', { sessionId });

      await client.request('session/list', {});

      expect(
        client.messages.some(
          (message) => message.id === running && !message.method,
        ),
      ).toBe(false);

      const close = client.send('session/close', { sessionId });

      expect((await client.answerTo(running)).result?.stopReason).toBe(
        'cancelled',
      );

      await client.answerTo(close);

      expect(
        client.messages.filter(
          (message) => message.id === running && !message.method,
        ),
      ).toHaveLength(1);
      expect(
        (await client.answerTo(prompt(sessionId, 'text'))).error?.code,
      ).toBe(-32002);
    }));
});

describe('one surface', () => {
  test('the answer holds one configOptions; modes never go', () =>
    onAcp([], async ({ client, cwd }) => {
      const { result } = await client.request('session/new', {
        cwd,
        mcpServers: [],
      });
      const options = result?.configOptions as { id: string }[];

      expect(options.map(({ id }) => id)).toContain('mode');
      expect(options.map(({ id }) => id)).toContain('model');
      expect(result).not.toHaveProperty('modes');
    }));

  test('set_config_option answers the whole list, moved', () =>
    onAcp([], async ({ client, newSession }) => {
      const sessionId = await newSession();
      const { result } = await client.request('session/set_config_option', {
        sessionId,
        configId: 'effort',
        value: 'high',
      });

      expect(result?.configOptions).toContainEqual(
        expect.objectContaining({ id: 'effort', currentValue: 'high' }),
      );
    }));

  test('a boolean, or an option none offers, is -32602', () =>
    onAcp([], async ({ client, newSession }) => {
      const sessionId = await newSession();

      for (const params of [
        { configId: 'effort', type: 'boolean', value: true },
        { configId: 'nothing', value: 'x' },
      ]) {
        const { error } = await client.request('session/set_config_option', {
          sessionId,
          ...params,
        });

        expect(error?.code).toBe(-32602);
      }
    }));

  test("a refused set is that request's error, and no notice", () =>
    onAcp(['--refuse-config'], async ({ client, newSession, lines }) => {
      const sessionId = await newSession();
      const { error } = await client.request('session/set_config_option', {
        sessionId,
        configId: 'effort',
        value: 'high',
      });

      expect(error?.message).toContain('holds its effort');
      expect(lines).toEqual([]);
      expect(kinds(client, sessionId)).not.toContain('notice');
    }));

  test('set_mode answers {}, and the change goes as the one shape', () =>
    onAcp([], async ({ client, newSession }) => {
      const sessionId = await newSession();
      const { result } = await client.request('session/set_mode', {
        sessionId,
        modeId: 'plan',
      });

      expect(result).toEqual({});

      await until(() =>
        client
          .updates(sessionId)
          .some(
            (update) =>
              update.sessionUpdate === 'config_option_update' &&
              (
                update.configOptions as { id: string; currentValue: string }[]
              ).some(
                ({ id, currentValue }) =>
                  id === 'mode' && currentValue === 'plan',
              ),
          ),
      );

      expect(kinds(client, sessionId)).not.toContain('current_mode_update');
    }));

  for (const flags of [['--config-in-responses'], ['--silent-set-mode']]) {
    test(`${flags[0]} reads as any other agent`, () =>
      onAcp(flags, async ({ client, newSession }) => {
        const sessionId = await newSession();

        await client.request('session/set_mode', {
          sessionId,
          modeId: 'plan',
        });

        await until(() =>
          client
            .updates(sessionId)
            .some((update) => update.sessionUpdate === 'config_option_update'),
        );
      }));
  }

  test('an agent with only session/set_model shows the same option', () =>
    onAcp(['--no-config'], async ({ client, cwd }) => {
      const { result } = await client.request('session/new', {
        cwd,
        mcpServers: [],
      });

      expect(result?.configOptions).toContainEqual(
        expect.objectContaining({ category: 'model' }),
      );
    }));

  test("a client's servers go to the session it named; acp's is -32602", async () => {
    const seen: unknown[] = [];

    await onAcp(
      [],
      async ({ client, cwd, newSession }) => {
        const { error } = await client.request('session/new', {
          cwd,
          mcpServers: [{ type: 'acp', name: 'bad', id: 'x' }],
        });

        expect(error?.code).toBe(-32602);

        await client.request('session/new', {
          cwd,
          mcpServers: [{ name: 'both', command: 'theirs', args: [], env: [] }],
        });

        expect(seen).toEqual([
          [
            { name: 'both', command: 'theirs', args: [], env: [] },
            { name: 'ours', command: 'ours', args: [], env: [] },
          ],
        ]);

        await newSession();
      },
      {
        place: () =>
          Promise.resolve({
            mcpServers: [
              { name: 'both', command: 'mine', args: [], env: [] },
              { name: 'ours', command: 'ours', args: [], env: [] },
            ],
          }),
        open: (options) => {
          if (seen.length === 0) {
            seen.push(options.mcpServers);
          }

          return openSession(options);
        },
      },
    );
  });

  test("dimcode's notice goes once, on stderr and as a notice", () =>
    onAcp(
      ['--dimcode-permission', 'full-access'],
      async ({ client, newSession, lines }) => {
        const sessionId = await newSession();

        await until(() => kinds(client, sessionId).includes('notice'));

        expect(lines.filter((line) => line.includes('dimcode'))).not.toEqual(
          [],
        );
        expect(
          kinds(client, sessionId).filter((kind) => kind === 'notice'),
        ).toHaveLength(1);
      },
      { agent: 'dimcode' },
    ));
});

describe('sessions side by side', () => {
  test('the same id from a second process takes an alias, and both route', () =>
    onAcp(['--session-id', 's1'], async ({ client, newSession, prompt }) => {
      const first = await newSession();
      const second = await newSession();

      expect([first, second]).toEqual(['s1', 's1~2']);
      expect(
        (await client.answerTo(prompt(second, 'text'))).result?.stopReason,
      ).toBe('end_turn');
      expect(client.said('s1~2')).not.toBe('');
      expect(client.said('s1')).toBe('');
      expect(
        (await client.answerTo(prompt(first, 'text'))).result?.stopReason,
      ).toBe('end_turn');
    }));
});

describe('starts that fail', () => {
  test('a missing command is -32603 with its lines, and chord lives', async () => {
    let opens = 0;

    await onAcp(
      [],
      async ({ client, cwd, newSession }) => {
        const { error } = await client.request('session/new', {
          cwd,
          mcpServers: [],
        });

        expect(error?.code).toBe(-32603);
        expect(error?.message).toContain('/no/such/agent');
        expect(error?.data).toHaveProperty('lines');
        expect(await newSession()).not.toBe('');
      },
      {
        open: (options) => {
          opens += 1;

          return openSession({
            ...options,
            ...(opens === 1 ? { agentCommand: ['/no/such/agent'] } : {}),
          });
        },
      },
    );
  });

  test('a login is -32000, its ways in the data', () =>
    onAcp(['--auth-required', 'methods'], async ({ client, cwd }) => {
      const { error } = await client.request('session/new', {
        cwd,
        mcpServers: [],
      });

      expect(error?.code).toBe(-32000);
      expect(
        (error?.data as { lines: readonly string[] }).lines.length,
      ).toBeGreaterThan(0);
    }));

  test('a cancel while the place is read starts no agent', async () => {
    const reading = Promise.withResolvers<{ mcpServers: [] }>();
    let asked = false;
    let opens = 0;

    await onAcp(
      [],
      async ({ client, cwd }) => {
        const id = client.send('session/new', { cwd, mcpServers: [] });

        await until(() => asked);

        client.notify('$/cancel_request', { requestId: id });

        await client.request('session/list', {});

        reading.resolve({ mcpServers: [] });

        expect((await client.answerTo(id)).error?.code).toBe(-32800);
        expect(client.messages.filter((m) => m.id === id)).toHaveLength(1);
        expect(opens).toBe(0);
      },
      {
        place: () => {
          asked = true;

          return reading.promise;
        },
        open: (options) => {
          opens += 1;

          return openSession(options);
        },
      },
    );
  });

  test('a hanging start stays open until its request is cancelled, leaving no group', async () => {
    const gateDir = await mkdtemp(join(tmpdir(), 'chord-acp-gate-'));

    await onAcp(
      [],
      async ({ client, cwd }) => {
        const id = client.send('session/new', { cwd, mcpServers: [] });

        await client.request('session/list', {});

        expect(
          client.messages.some(
            (message) => message.id === id && !message.method,
          ),
        ).toBe(false);

        client.notify('$/cancel_request', { requestId: id });

        expect((await client.answerTo(id)).error?.code).toBe(-32800);
      },
      {
        agentCommand: gatedCommand(
          join(gateDir, 'release'),
          fakeAgentCommand(),
        ),
      },
    );

    await rm(gateDir, { recursive: true, force: true });
  });
});

describe('an agent that dies', () => {
  test('in a turn: the prompt is -32603 with its last words', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const { error } = await client.answerTo(prompt(sessionId, 'crash'));

      expect(error?.code).toBe(-32603);
      expect(
        (await client.answerTo(prompt(sessionId, 'text'))).error?.code,
      ).toBe(-32002);
    }));

  test('with a prompt queued: it is -32002, the running one its error', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'crash');
      const queued = prompt(sessionId, 'text');

      expect((await client.answerTo(running)).error?.code).toBe(-32603);
      expect((await client.answerTo(queued)).error?.code).toBe(-32002);
    }));
});

/** The request chord made of the client with `method`, waited for. */
const asked = (client: AcpClient, method: string, nth = 0) =>
  until(
    () =>
      client.messages.filter(
        (message) => message.method === method && message.id !== undefined,
      ).length > nth,
  ).then(
    () =>
      client.messages.filter(
        (message) => message.method === method && message.id !== undefined,
      )[nth] as WireMessage & { id: number },
  );
const PERMISSION = 'session/request_permission';
const selected = (optionId: string) => ({
  outcome: { outcome: 'selected', optionId },
});

describe('permissions', () => {
  test('forwarded whole; the answer reaches the agent', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'permission');
      const ask = await asked(client, PERMISSION);

      expect(ask.params?.sessionId).toBe(sessionId);
      expect(ask.params?.toolCall).toMatchObject({
        title: 'Write notes.txt',
        rawInput: { file_path: 'notes.txt' },
      });

      client.respond(ask.id, selected('allow'));

      expect((await client.answerTo(running)).result?.stopReason).toBe(
        'end_turn',
      );
      expect(client.said(sessionId)).toContain('Permission: allow');
    }));

  test('_meta goes as it is, on the request and on its call', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'permissionmeta');
      const ask = await asked(client, PERMISSION);

      expect(ask.params?._meta).toEqual({ 'fake/asked': 1 });
      expect(ask.params?.toolCall).toMatchObject({
        _meta: { 'fake/call': 1 },
      });

      client.respond(ask.id, selected('deny'));

      await client.answerTo(running);
    }));

  test('an ask under a session the agent never announced is refused, never shown', () =>
    onAcp([], async ({ client, newSession, prompt, lines }) => {
      const sessionId = await newSession();

      await client.answerTo(prompt(sessionId, 'strangerask'));

      expect(client.messages.some((m) => m.method === PERMISSION)).toBe(false);
      expect(client.said(sessionId)).toContain('deny');
      expect(lines.join('\n')).toContain('a session it does not know');
    }));

  test('an error answer is a refusal, with a line on stderr', () =>
    onAcp([], async ({ client, newSession, prompt, lines }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'permission');
      const ask = await asked(client, PERMISSION);

      client.respondError(ask.id, -32603, 'the client broke');

      await client.answerTo(running);

      expect(client.said(sessionId)).toContain('Permission: deny');
      expect(lines.join('\n')).toContain('the client broke');
    }));

  test('an unknown option is a refusal before choose', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'permission');
      const ask = await asked(client, PERMISSION);

      client.respond(ask.id, selected('nothing-offered'));

      await client.answerTo(running);

      expect(client.said(sessionId)).toContain('Permission: deny');
    }));

  test('a cancel withdraws it upstream and ends the turn; a late answer changes nothing', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'permission');
      const ask = await asked(client, PERMISSION);

      client.notify('session/cancel', { sessionId });

      await client.until(
        (message) =>
          message.method === '$/cancel_request' &&
          message.params?.requestId === ask.id,
      );

      expect((await client.answerTo(running)).result?.stopReason).toBe(
        'cancelled',
      );

      client.respond(ask.id, selected('allow'));
      client.respond(ask.id, selected('allow'));

      expect(
        (await client.answerTo(prompt(sessionId, 'text'))).result?.stopReason,
      ).toBe('end_turn');
      expect(client.said(sessionId)).not.toContain('Permission: allow');
    }));

  test('a duplicate answer changes nothing', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'permission');
      const ask = await asked(client, PERMISSION);

      client.respond(ask.id, selected('deny'));
      client.respond(ask.id, selected('allow'));

      await client.answerTo(running);

      expect(client.said(sessionId)).toContain('Permission: deny');
      expect(client.said(sessionId)).not.toContain('Permission: allow');
    }));

  test("a child's ask goes under its composite id", () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'subagent');
      const ask = await asked(client, PERMISSION);

      expect(String(ask.params?.sessionId).startsWith(`${sessionId}/`)).toBe(
        true,
      );

      client.respond(ask.id, selected('allow'));
      client.notify('session/cancel', { sessionId });

      await client.answerTo(running);
    }));

  test("a child's ask to a client without subagents is refused, on stderr", () =>
    onAcp(
      [],
      async ({ client, newSession, prompt, lines }) => {
        const sessionId = await newSession();
        const running = prompt(sessionId, 'subagent');

        await until(() =>
          lines.some((line) => line.includes("subagent's permission")),
        );

        expect(client.messages.some((m) => m.method === PERMISSION)).toBe(
          false,
        );

        client.notify('session/cancel', { sessionId });

        await client.answerTo(running);
      },
      { capabilities: {} },
    ));
});

describe('forms and links', () => {
  const FORM = 'elicitation/create';

  test('a form goes raw under the session; its answer reaches the agent', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'form');
      const form = await asked(client, FORM);

      expect(form.params).toMatchObject({
        sessionId,
        mode: 'form',
        message: 'Set up the deploy target',
      });
      expect(form.params).toHaveProperty('requestedSchema');

      client.respond(form.id, { action: 'decline' });

      await client.answerTo(running);

      expect(client.said(sessionId)).toContain('Elicitation answer: decline');
    }));

  test('a form to a client that declared none still goes', () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();
        const running = prompt(sessionId, 'form');
        const form = await asked(client, FORM);

        client.respond(form.id, { action: 'cancel' });

        await client.answerTo(running);
      },
      { capabilities: {} },
    ));

  test('an error answer is cancel', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'form');
      const form = await asked(client, FORM);

      client.respondError(form.id, -32603, 'no');

      await client.answerTo(running);

      expect(client.said(sessionId)).toContain('Elicitation answer: cancel');
    }));

  test('a link accepted passes its completion on', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'link');
      const link = await asked(client, FORM);

      expect(link.params).toMatchObject({ mode: 'url', sessionId });

      client.respond(link.id, { action: 'accept' });

      await client.answerTo(running);
      await client.until(
        (message) =>
          message.method === 'elicitation/complete' &&
          message.params?.elicitationId === link.params?.elicitationId,
      );
    }));

  test('one scoped to a request is cancelled, never asked', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();

      await client.answerTo(prompt(sessionId, 'requestform'));

      expect(client.messages.some((m) => m.method === FORM)).toBe(false);
      expect(client.said(sessionId)).toContain('Elicitation answer: cancel');
    }));

  test('one under a session the agent never announced is cancelled, never asked', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();

      await client.answerTo(prompt(sessionId, 'strangerform'));

      expect(client.messages.some((m) => m.method === FORM)).toBe(false);
      expect(client.said(sessionId)).toContain('Elicitation answer: cancel');
    }));

  test('a cancel withdraws a form upstream', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'form');
      const form = await asked(client, FORM);

      client.notify('session/cancel', { sessionId });

      await client.until(
        (message) =>
          message.method === '$/cancel_request' &&
          message.params?.requestId === form.id,
      );
      await client.answerTo(running);
    }));
});

describe('a plan ask', () => {
  for (const [scenario, flags, choice, heard] of [
    ['cursorplan', [], 'accepted', 'accepted'],
    ['cursorplan', [], 'kept', 'rejected'],
    ['grokplan', [], 'accepted', 'approved'],
    ['grokplan', [], 'left', 'abandoned'],
  ] as const) {
    test(`${scenario}: ${choice} reaches the agent in its own words`, () =>
      onAcp(flags, async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();
        const running = prompt(sessionId, scenario);
        const ask = await asked(client, PERMISSION);

        expect(ask.params?.options).toContainEqual(
          expect.objectContaining({ optionId: 'accepted', kind: 'allow_once' }),
        );

        client.respond(ask.id, selected(choice));

        await client.answerTo(running);

        expect(client.said(sessionId)).toContain('Plan answer:');
        expect(client.said(sessionId).toLowerCase()).toContain(heard);
      }));
  }

  for (const [name, answer] of [
    ['a cancel', { outcome: { outcome: 'cancelled' } }],
    ['an unknown id', selected('yes-please')],
  ] as const) {
    test(`${name} is never a yes`, () =>
      onAcp([], async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();
        const running = prompt(sessionId, 'cursorplan');
        const ask = await asked(client, PERMISSION);

        client.respond(ask.id, answer);

        await client.answerTo(running);

        expect(client.said(sessionId).toLowerCase()).not.toContain('accepted');
      }));
  }

  test('an error is never a yes', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'cursorplan');
      const ask = await asked(client, PERMISSION);

      client.respondError(ask.id, -32603, 'no');

      await client.answerTo(running);

      expect(client.said(sessionId).toLowerCase()).not.toContain('accepted');
    }));
});

describe('the way out', () => {
  test('EOF idle: exit 0', () =>
    onAcp([], async ({ newSession, eof, exits }) => {
      await newSession();
      await eof();

      expect(exits).toEqual([{ code: 0 }]);
    }));

  test('EOF with an ask open: no answer, the agent hears cancelled', () =>
    onAcp([], async ({ client, newSession, prompt, eof, exits }) => {
      const sessionId = await newSession();

      prompt(sessionId, 'permission');

      await asked(client, PERMISSION);
      await eof();

      expect(exits).toEqual([{ code: 0 }]);
    }));

  test('a signal with an ask open withdraws it, then the prompt is cancelled', () =>
    onAcp([], async ({ client, newSession, prompt, run }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'permission');
      const ask = await asked(client, PERMISSION);

      await run.leave({ kind: 'signal', signal: 'SIGTERM' });

      expect((await client.answerTo(running)).result?.stopReason).toBe(
        'cancelled',
      );
      await client.until(
        (message) =>
          message.method === '$/cancel_request' &&
          message.params?.requestId === ask.id,
      );
    }));

  test('a signal in a turn: cancelled first, then the signal', () =>
    onAcp([], async ({ client, newSession, prompt, run, exits }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'long');

      await until(() => client.said(sessionId) !== '');

      await run.leave({ kind: 'signal', signal: 'SIGTERM' });

      expect((await client.answerTo(running)).result?.stopReason).toBe(
        'cancelled',
      );
      expect(exits).toEqual([{ signal: 'SIGTERM' }]);
    }));

  test('a request while closing is -32603', () =>
    onAcp([], async ({ client, newSession, run, cwd }) => {
      await newSession();

      const leaving = run.leave({ kind: 'signal', signal: 'SIGINT' });
      const id = client.send('session/new', { cwd, mcpServers: [] });

      await leaving;

      // Written if the drain reached it; never an agent started for it.
      expect(client.messages.filter((m) => m.id === id && m.result)).toEqual(
        [],
      );
    }));
});
