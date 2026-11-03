import { describe, expect, test } from 'bun:test';
import assert from 'node:assert';
import { spawnSync } from 'node:child_process';
import {
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import {
  type AcpOptions,
  type AcpPlace,
  type AcpRun,
  runAcp,
} from '../src/acp_agent.ts';
import { killSpawnedGroups } from '../src/platform/process.ts';
import { serveChord } from '../src/server/server.ts';
import type { LeaveExit } from '../src/session/leaving.ts';
import {
  parseRecord,
  recordActions,
  type RecordEntry,
} from '../src/session/record.ts';
import {
  openSession,
  type OpenSessionOptions,
  type Session,
} from '../src/session/session.ts';
import { earlierSessions, readRecords } from '../src/session/sessions.ts';
import {
  type AcpClient,
  clientOverStreams,
  type WireMessage,
} from './fixtures/acp_client.ts';
import { fakeAgentCommand, gatedCommand } from './fixtures/fake.ts';
import { recordSession } from './fixtures/records.ts';
import { until } from './session/conversation_fake.ts';

const FULL = {
  subagents: {},
  plan: {},
  session: { compaction: {}, notices: {} },
};

interface Acp {
  readonly client: AcpClient;
  readonly cwd: string;
  readonly stateDir: string;
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

/** A directory that starts the fake on `flags`, with `servers` of its own. */
function fakePlace(
  flags: readonly string[] = [],
  servers: AcpPlace['mcpServers'][number]['server'][] = [],
): AcpPlace {
  return {
    cwd: '',
    startupOf: () => ({ agentCommand: fakeAgentCommand(undefined, ...flags) }),
    mcpServers: servers.map((server) => ({ server, from: 'a test' })),
    mcpIgnored: [],
    runtimes: ['fake'],
  };
}

async function onAcp(
  flags: readonly string[],
  body: (acp: Acp) => Promise<void>,
  {
    capabilities = FULL,
    state,
    ...over
  }: Partial<AcpOptions> & {
    capabilities?: object;
    /** Lays a record down in the state directory before chord starts. */
    state?: (stateDir: string, cwd: string) => Promise<void>;
  } = {},
): Promise<void> {
  const cwd = await mkdtemp(join(tmpdir(), 'chord-acp-'));
  const stateDir = await mkdtemp(join(tmpdir(), 'chord-acp-state-'));

  await state?.(stateDir, cwd);

  const { client, input, output, end } = clientOverStreams();
  const lines: string[] = [];
  const exits: LeaveExit[] = [];
  const run = runAcp({
    input,
    output,
    stderr: (line) => lines.push(line),
    exit: (how) => exits.push(how),
    agent: 'fake',
    version: '1.2.3',
    stateDir,
    open: openSession,
    place: () => Promise.resolve(fakePlace(flags)),
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
      stateDir,
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
    await rm(stateDir, { recursive: true, force: true });
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
              extensions: { 'session/state': 1, 'session/steer': 1, agents: 1 },
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
          Promise.resolve(
            fakePlace(
              [],
              [
                { name: 'both', command: 'mine', args: [], env: [] },
                { name: 'ours', command: 'ours', args: [], env: [] },
              ],
            ),
          ),
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

  test("a command its directory's files refuse is -32603 in their words, nothing started", async () => {
    let opens = 0;
    let refuses = true;

    await onAcp(
      [],
      async ({ client, cwd, newSession }) => {
        const { error } = await client.request('session/new', {
          cwd,
          mcpServers: [],
        });

        expect(error?.code).toBe(-32603);
        expect(error?.message).toBe('fake: refused by a file');
        expect(opens).toBe(0);

        refuses = false;

        // Nothing was left behind, and the process goes on.
        expect(await newSession()).not.toBe('');
        expect(opens).toBe(1);
      },
      {
        place: () =>
          Promise.resolve(
            refuses
              ? {
                  ...fakePlace(),
                  startupOf: () => ({ refused: 'fake: refused by a file' }),
                }
              : fakePlace(),
          ),
        open: (options) => {
          opens += 1;

          return openSession(options);
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
    const reading = Promise.withResolvers<AcpPlace>();
    let asked = false;
    let opens = 0;

    await onAcp(
      [],
      async ({ client, cwd }) => {
        const id = client.send('session/new', { cwd, mcpServers: [] });

        await until(() => asked);

        client.notify('$/cancel_request', { requestId: id });

        await client.request('session/list', {});

        reading.resolve(fakePlace());

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
        place: () =>
          Promise.resolve({
            ...fakePlace(),
            startupOf: () => ({
              agentCommand: gatedCommand(
                join(gateDir, 'release'),
                fakeAgentCommand(),
              ),
            }),
          }),
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

  test('a close withdraws it upstream, heard as main closes', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'permission');
      const ask = await asked(client, PERMISSION);

      await client.request('session/close', { sessionId });

      await client.until(
        (message) =>
          message.method === '$/cancel_request' &&
          message.params?.requestId === ask.id,
      );

      expect((await client.answerTo(running)).result?.stopReason).toBe(
        'cancelled',
      );
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

/** Waits for a session's record to hold a line of this kind. */
async function recorded(stateDir: string, sessionId: string, type: string) {
  let entries: readonly RecordEntry[] = [];

  await untilAsync(async () => {
    const records = await readRecords(stateDir);
    const record = records.find((each) => each.sessionId === sessionId);

    entries =
      record === undefined
        ? []
        : parseRecord(await readFile(record.path, 'utf8'));

    return entries.some((entry) => entry.type === type);
  });

  return entries;
}

async function untilAsync(check: () => Promise<boolean>): Promise<void> {
  const deadline = performance.now() + 10_000;

  while (!(await check())) {
    if (performance.now() > deadline) {
      throw new Error(`timed out waiting for ${String(check)}`);
    }

    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

describe('sessions and records', () => {
  test('a session is recorded as the window records, and recordActions opens it', () =>
    onAcp([], async ({ client, newSession, prompt, stateDir }) => {
      const sessionId = await newSession();

      await client.answerTo(prompt(sessionId, 'text'));

      const entries = await recorded(stateDir, sessionId, 'result');

      expect(entries[0]).toMatchObject({
        type: 'session',
        sessionId,
        agent: 'fake',
      });

      const actions = recordActions(entries);

      expect(actions.some((action) => action.type === 'prompt')).toBe(true);
      expect(actions.some((action) => action.type === 'update')).toBe(true);
    }));

  test('session/list is the records, all in one answer, by directory or all', () =>
    onAcp([], async ({ client, newSession, prompt, cwd, stateDir }) => {
      const sessionId = await newSession();

      await client.answerTo(prompt(sessionId, 'text'));
      await recorded(stateDir, sessionId, 'result');

      const here = await client.request('session/list', { cwd });
      const all = await client.request('session/list', {});
      const elsewhere = await client.request('session/list', {
        cwd: '/nowhere',
      });

      expect(here.result?.sessions).toEqual([
        {
          sessionId,
          cwd,
          title: 'text',
          updatedAt: expect.any(String) as string,
        },
      ]);
      expect(here.result).not.toHaveProperty('nextCursor');
      expect(all.result?.sessions).toEqual(here.result?.sessions);
      expect(elsewhere.result?.sessions).toEqual([]);
    }));

  test('a window record of this agent is listed and loaded, its past ahead of the answer', () => {
    const made: { sessionId?: string } = {};

    return onAcp(
      [],
      async ({ client, cwd }) => {
        const sessionId = made.sessionId as string;
        const { result } = await client.request('session/list', { cwd });

        expect(result?.sessions).toContainEqual(
          expect.objectContaining({ sessionId }),
        );

        const load = client.send('session/load', {
          sessionId,
          cwd,
          mcpServers: [],
        });
        const answer = await client.answerTo(load);

        expect(answer.error).toBeUndefined();
        expect(answer.result).not.toHaveProperty('sessionId');
        expect(answer.result).toHaveProperty('configOptions');

        const at = client.messages.indexOf(
          client.messages.find(
            (m) => m.id === load && !m.method,
          ) as WireMessage,
        );
        const before = client.messages
          .slice(0, at)
          .filter((m) => m.method === 'session/update')
          .map((m) => m.params?.update as Record<string, unknown>);

        expect(before[0]).toMatchObject({
          sessionUpdate: 'user_message_chunk',
          content: { text: 'text' },
        });
        expect(
          before.some((u) => u.sessionUpdate === 'agent_message_chunk'),
        ).toBe(true);
      },
      {
        state: async (stateDir, cwd) => {
          made.sessionId = await recordSession({
            stateDir,
            cwd,
            command: fakeAgentCommand(),
            prompts: ['text'],
          });
        },
      },
    );
  });

  test('a load replays under the drop-only check, and the record keeps what it drops', () => {
    const made: { sessionId?: string } = {};

    return onAcp(
      [],
      async ({ client, cwd, stateDir }) => {
        const sessionId = made.sessionId as string;

        await client.request('session/load', {
          sessionId,
          cwd,
          mcpServers: [],
        });

        const kinds = client.updates(sessionId).map((u) => u.sessionUpdate);

        expect(kinds).not.toContain('plan_update');
        expect(kinds).toContain('user_message_chunk');

        const records = await readRecords(stateDir);
        const text = await readFile(records[0]?.path ?? '', 'utf8');

        expect(text).toContain('plan_update');
      },
      {
        capabilities: {},
        state: async (stateDir, cwd) => {
          made.sessionId = await recordSession({
            stateDir,
            cwd,
            command: fakeAgentCommand(),
            prompts: ['proposal'],
          });
        },
      },
    );
  });

  test('session/resume answers with nothing replayed, and the session goes on', () => {
    const made: { sessionId?: string } = {};

    return onAcp(
      [],
      async ({ client, cwd, prompt }) => {
        const sessionId = made.sessionId as string;
        const { result, error } = await client.request('session/resume', {
          sessionId,
          cwd,
          mcpServers: [],
        });

        expect(error).toBeUndefined();
        expect(result).toHaveProperty('configOptions');
        expect(client.said(sessionId)).toBe('');
        expect(
          client
            .updates(sessionId)
            .some((u) => u.sessionUpdate === 'user_message_chunk'),
        ).toBe(false);
        expect(
          (await client.answerTo(prompt(sessionId, 'text'))).result?.stopReason,
        ).toBe('end_turn');
      },
      {
        state: async (stateDir, cwd) => {
          made.sessionId = await recordSession({
            stateDir,
            cwd,
            command: fakeAgentCommand(),
            prompts: ['text'],
          });
        },
      },
    );
  });

  test('a record laid down before this version still lists and loads', () => {
    const sessionId = '11111111-2222-4333-8444-555555555555';

    return onAcp(
      [],
      async ({ client, cwd }) => {
        const { result } = await client.request('session/list', { cwd });

        expect(result?.sessions).toEqual([
          expect.objectContaining({ sessionId, title: 'an older prompt' }),
        ]);

        const load = await client.request('session/load', {
          sessionId,
          cwd,
          mcpServers: [],
        });

        expect(load.error).toBeUndefined();
        expect(client.updates(sessionId)[0]).toMatchObject({
          sessionUpdate: 'user_message_chunk',
          content: { text: 'an older prompt' },
        });
      },
      {
        state: async (stateDir, cwd) => {
          const dir = join(stateDir, 'records');

          await mkdir(dir, { recursive: true });
          await writeFile(
            join(dir, `${sessionId}.jsonl`),
            `${[
              {
                type: 'session',
                version: 1,
                sessionId,
                agent: 'fake',
                cwd,
                at: 1,
              },
              {
                type: 'prompt',
                turnId: 't1',
                at: 2,
                prompt: 'an older prompt',
                images: 0,
              },
            ]
              .map((entry) => JSON.stringify(entry))
              .join('\n')}\n`,
          );
        },
      },
    );
  });

  test('a load or resume of an id live here is -32602, and its turn still answers', () =>
    onAcp([], async ({ client, cwd, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'long');

      await until(() => client.said(sessionId) !== '');

      for (const method of ['session/load', 'session/resume']) {
        const { error } = await client.request(method, {
          sessionId,
          cwd,
          mcpServers: [],
        });

        expect(error?.code).toBe(-32602);
      }

      client.notify('session/cancel', { sessionId });

      expect((await client.answerTo(running)).result?.stopReason).toBe(
        'cancelled',
      );
    }));

  for (const [first, second] of [
    ['session/load', 'session/load'],
    ['session/load', 'session/resume'],
    ['session/resume', 'session/load'],
  ]) {
    test(`${first} then ${second} of one id at once: one opens it, the other is -32602`, async () => {
      const made: { sessionId?: string } = {};
      const reading = Promise.withResolvers<AcpPlace>();
      let opens = 0;

      await onAcp(
        [],
        async ({ client, cwd }) => {
          const params = { sessionId: made.sessionId, cwd, mcpServers: [] };
          const winner = client.send(first as string, params);
          const loser = await client.request(second as string, params);

          expect(loser.error?.code).toBe(-32602);

          reading.resolve(fakePlace());

          expect((await client.answerTo(winner)).error).toBeUndefined();
          expect(opens).toBe(1);

          const again = await client.request(second as string, params);

          expect(again.error?.code).toBe(-32602);
        },
        {
          place: () => reading.promise,
          open: (options) => {
            opens += 1;

            return openSession(options);
          },
          state: async (stateDir, cwd) => {
            made.sessionId = await recordSession({
              stateDir,
              cwd,
              command: fakeAgentCommand(),
              prompts: ['text'],
            });
          },
        },
      );
    });
  }

  test('a reopen cancelled gives its id back', async () => {
    const made: { sessionId?: string } = {};
    const reading = Promise.withResolvers<AcpPlace>();
    let places = 0;

    await onAcp(
      [],
      async ({ client, cwd }) => {
        const params = { sessionId: made.sessionId, cwd, mcpServers: [] };
        const load = client.send('session/load', params);

        await until(() => places === 1);

        client.notify('$/cancel_request', { requestId: load });

        await client.request('session/list', {});

        reading.resolve(fakePlace());

        expect((await client.answerTo(load)).error?.code).toBe(-32800);
        expect(
          (await client.request('session/load', params)).error,
        ).toBeUndefined();
      },
      {
        place: () => {
          places += 1;

          return places === 1 ? reading.promise : Promise.resolve(fakePlace());
        },
        state: async (stateDir, cwd) => {
          made.sessionId = await recordSession({
            stateDir,
            cwd,
            command: fakeAgentCommand(),
            prompts: ['text'],
          });
        },
      },
    );
  });

  test('a new session answered with an id being reopened takes an alias', async () => {
    const SHAPED = '11111111-2222-4333-8444-555555555555';
    const reading = Promise.withResolvers<AcpPlace>();
    let places = 0;

    await onAcp(
      ['--session-id', SHAPED],
      async ({ client, cwd, newSession }) => {
        const load = client.send('session/load', {
          sessionId: SHAPED,
          cwd,
          mcpServers: [],
        });

        await until(() => places === 1);

        expect(await newSession()).toBe(`${SHAPED}~2`);

        reading.resolve(fakePlace(['--session-id', SHAPED]));

        expect((await client.answerTo(load)).error).toBeUndefined();
      },
      {
        place: () => {
          places += 1;

          return places === 1
            ? reading.promise
            : Promise.resolve(fakePlace(['--session-id', SHAPED]));
        },
      },
    );
  });

  test('a reopen that fails gives its id back', async () => {
    const made: { sessionId?: string } = {};
    let opens = 0;

    await onAcp(
      [],
      async ({ client, cwd }) => {
        const params = { sessionId: made.sessionId, cwd, mcpServers: [] };

        expect((await client.request('session/load', params)).error?.code).toBe(
          -32603,
        );
        expect(
          (await client.request('session/load', params)).error,
        ).toBeUndefined();
      },
      {
        open: (options) => {
          opens += 1;

          return openSession({
            ...options,
            ...(opens === 1 ? { agentCommand: ['/no/such/agent'] } : {}),
          });
        },
        state: async (stateDir, cwd) => {
          made.sessionId = await recordSession({
            stateDir,
            cwd,
            command: fakeAgentCommand(),
            prompts: ['text'],
          });
        },
      },
    );
  });

  test("a load in another directory than the record names the record's", () => {
    const made: { sessionId?: string } = {};

    return onAcp(
      [],
      async ({ client, cwd }) => {
        const { error } = await client.request('session/load', {
          sessionId: made.sessionId,
          cwd: '/elsewhere',
          mcpServers: [],
        });

        expect(error?.code).toBe(-32602);
        expect(error?.message).toContain(cwd);
      },
      {
        state: async (stateDir, cwd) => {
          made.sessionId = await recordSession({
            stateDir,
            cwd,
            command: fakeAgentCommand(),
            prompts: ['text'],
          });
        },
      },
    );
  });

  test("an id of another agent's record is -32602 in ResumeError's words", () => {
    const made: { sessionId?: string } = {};

    return onAcp(
      [],
      async ({ client, cwd }) => {
        const { error } = await client.request('session/load', {
          sessionId: made.sessionId,
          cwd,
          mcpServers: [],
        });

        expect(error?.code).toBe(-32602);
        expect(error?.message).toContain('belongs to another agent (other)');
      },
      {
        state: async (stateDir, cwd) => {
          made.sessionId = await recordSession({
            stateDir,
            cwd,
            command: fakeAgentCommand(),
            prompts: ['text'],
            agent: 'other',
          });
        },
      },
    );
  });

  test('a session chord never recorded is unlisted, but load by id reaches the agent', () =>
    onAcp([], async ({ client, cwd }) => {
      const sessionId = '99999999-2222-4333-8444-555555555555';
      const { result } = await client.request('session/list', { cwd });

      expect(result?.sessions).toEqual([]);

      const load = await client.request('session/load', {
        sessionId,
        cwd,
        mcpServers: [],
      });

      expect(load.error).toBeUndefined();
    }));

  test("an alias is not listed, and its record holds the agent's id", () =>
    onAcp(
      ['--session-id', 's1'],
      async ({ client, cwd, newSession, prompt, stateDir }) => {
        await newSession();

        const second = await newSession();

        expect(second).toBe('s1~2');

        await client.answerTo(prompt(second, 'text'));
        await recorded(stateDir, 's1', 'result');

        const { result } = await client.request('session/list', { cwd });

        expect(result?.sessions).toEqual([
          expect.objectContaining({ sessionId: 's1' }),
        ]);
      },
    ));

  test('a record that cannot be written: stderr and notice, the session goes on', () =>
    onAcp([], async ({ client, newSession, prompt, lines, stateDir }) => {
      await writeFile(join(stateDir, 'records'), 'not a directory');

      const sessionId = await newSession();
      const { result } = await client.answerTo(prompt(sessionId, 'text'));

      expect(result?.stopReason).toBe('end_turn');

      await until(() => lines.some((line) => line.startsWith('chord: ')));
      await until(() =>
        client
          .updates(sessionId)
          .some((update) => update.sessionUpdate === 'notice'),
      );
    }));

  test('an agent dead between turns: the next prompt is -32002, session/resume reopens', async () => {
    const opened: Session[] = [];

    await onAcp(
      [],
      async ({ client, cwd, newSession, prompt, stateDir }) => {
        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'text'));
        await recorded(stateDir, sessionId, 'result');

        const [session] = opened;

        assert(session !== undefined);

        const [pid] = session.agentPids;

        assert(pid !== undefined);

        process.kill(pid, 'SIGKILL');

        await session.exited;

        const dead = await client.answerTo(prompt(sessionId, 'text'));

        expect(dead.error?.code).toBe(-32002);

        const resumed = await client.request('session/resume', {
          sessionId,
          cwd,
          mcpServers: [],
        });

        expect(resumed.error).toBeUndefined();
        expect(
          (await client.answerTo(prompt(sessionId, 'text'))).result?.stopReason,
        ).toBe('end_turn');
      },
      {
        open: async (options) => {
          const session = await openSession(options);

          opened.push(session);

          return session;
        },
      },
    );
  });
});

const BUGFIX = fileURLToPath(
  new URL('./fixtures/teams/fake/bugfix.md', import.meta.url),
);

// Signal 0 only: a kill here would hide what a close left behind.
const groupAlive = (pid: number) => {
  try {
    return process.kill(-pid, 0);
  } catch {
    return false;
  }
};

describe("chord's server", () => {
  const server = () => ({ server: serveChord() });

  test("main gets it last, renamed past a client's of its name", () =>
    onAcp(
      [],
      async ({ client, cwd, prompt }) => {
        const { result } = await client.request('session/new', {
          cwd,
          mcpServers: [{ name: 'chord', command: 'x', args: [], env: [] }],
        });
        const sessionId = result?.sessionId as string;

        await client.answerTo(prompt(sessionId, 'mcp'));

        const said = client.said(sessionId);

        expect(said.indexOf('"chord"')).toBeGreaterThan(-1);
        expect(said.indexOf('"chord-2"')).toBeGreaterThan(
          said.indexOf('"chord"'),
        );
      },
      server(),
    ));

  test("mcpServers: false holds back the client's and its own, and says so", () =>
    onAcp(
      [],
      async ({ client, cwd, prompt, lines }) => {
        const { result } = await client.request('session/new', {
          cwd,
          mcpServers: [{ name: 'theirs', command: 'x', args: [], env: [] }],
        });
        const sessionId = result?.sessionId as string;
        const held = (result?._meta as Record<string, { server: string }[]>)[
          'chord/held_back'
        ];

        expect(held?.map((each) => each.server)).toEqual(['theirs', 'chord']);

        await client.answerTo(prompt(sessionId, 'mcp'));

        expect(client.said(sessionId)).not.toContain('theirs');
        expect(lines.some((line) => line.includes('not passed'))).toBe(true);
      },
      {
        ...server(),
        place: () =>
          Promise.resolve({
            ...fakePlace(),
            startupOf: () => ({
              agentCommand: fakeAgentCommand(),
              mcpServers: false as const,
            }),
          }),
      },
    ));

  test("a second session's token sees only its own children", () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const first = await newSession();
        const second = await newSession();

        await client.answerTo(prompt(first, 'agentsquiet'));
        await client.answerTo(prompt(first, 'chordtools'));
        await client.answerTo(prompt(second, 'chordtools'));

        expect(client.said(first)).toContain('parser');
        expect(client.said(second)).toContain('list_sessions');
        expect(client.said(second)).not.toContain('parser');
      },
      server(),
    ));

  test("one settings box among sessions: a second is refused while the first's waits", async () => {
    const home = await mkdtemp(join(tmpdir(), 'chord-acp-home-'));

    try {
      await onAcp(
        [],
        async ({ client, newSession, prompt }) => {
          const first = await newSession();
          const second = await newSession();
          const asking = prompt(first, 'settingstheme');
          const ask = await asked(client, PERMISSION);

          await client.answerTo(prompt(second, 'settingstheme'));

          expect(JSON.stringify(client.updates(second))).toContain(
            'Another settings change is waiting',
          );

          client.respond(ask.id, selected('no'));

          await client.answerTo(asking);
        },
        { ...server(), configHome: home },
      );
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  test("chord's own asks say what they are about: a setting's change", async () => {
    const home = await mkdtemp(join(tmpdir(), 'chord-acp-home-'));

    try {
      await onAcp(
        [],
        async ({ client, newSession, prompt }) => {
          const sessionId = await newSession();
          const asking = prompt(sessionId, 'settingstheme');
          const ask = await asked(client, PERMISSION);
          const toolCall = ask.params?.toolCall as {
            title?: string;
            content?: { content: { text: string } }[];
          };

          expect(toolCall.title).toBe('Settings(theme)');
          expect(toolCall.content?.[0]?.content.text).toContain('"light"');

          client.respond(ask.id, selected('no'));

          await client.answerTo(asking);
        },
        { ...server(), configHome: home },
      );
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  test("chord's own asks say what they are about: a team's whole file", async () => {
    const home = await mkdtemp(join(tmpdir(), 'chord-acp-home-'));

    try {
      await onAcp(
        [],
        async ({ client, newSession, prompt }) => {
          const sessionId = await newSession();
          const asking = prompt(sessionId, 'propose');
          const ask = await asked(client, PERMISSION);
          const toolCall = ask.params?.toolCall as {
            title?: string;
            content?: { content: { text: string } }[];
          };
          const options = ask.params?.options as {
            optionId: string;
            kind: string;
          }[];

          expect(toolCall.title).toBe('Team(bugfix)');
          expect(toolCall.content?.[0]?.content.text).toContain('lead:');

          client.respond(
            ask.id,
            selected(
              options.find(({ kind }) => kind === 'reject_once')!.optionId,
            ),
          );

          await client.answerTo(asking);
        },
        {
          ...server(),
          configHome: home,
          // What the fake proposes runs on these; nothing here starts them.
          place: () =>
            Promise.resolve({
              ...fakePlace(),
              runtimes: ['fake', 'claude', 'codex'],
            }),
        },
      );
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  test('a team and a task, closed with session/close, leave no group', async () => {
    const pids: number[] = [];

    await onAcp(
      [],
      async ({ client, cwd, newSession, prompt }) => {
        await mkdir(join(cwd, '.chord', 'teams'), { recursive: true });
        await copyFile(BUGFIX, join(cwd, '.chord', 'teams', 'bugfix.md'));

        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'teamtask'));
        // Main, the task, the lead and its two members.
        await until(() => pids.length >= 5, 20_000);

        expect(pids.some(groupAlive)).toBe(true);

        await client.request('session/close', { sessionId });

        await until(() => !pids.some(groupAlive));
      },
      {
        ...server(),
        open: async (options) => {
          const session = await openSession(options);

          pids.push(...session.agentPids);

          return session;
        },
      },
    );
  });

  test('the way out closes the server and the readers', async () => {
    const closed: string[] = [];
    const served = serveChord();

    await onAcp(
      [],
      async ({ newSession, eof }) => {
        await newSession();
        await eof();

        expect(closed.toSorted()).toEqual(['readers', 'server']);
      },
      {
        server: {
          ...served,
          close: () => {
            closed.push('server');

            return served.close();
          },
        },
        resources: {
          read: () => Promise.resolve([]) as never,
          close: () => {
            closed.push('readers');

            return Promise.resolve([]);
          },
        },
      },
    );
  });

  test('a reader that could not clean up makes EOF exit 1, and says why', () =>
    onAcp(
      [],
      async ({ newSession, eof, exits, lines }) => {
        await newSession();
        await eof();

        expect(exits).toEqual([{ code: 1 }]);
        expect(lines.join('\n')).toContain('a provider left a process');
      },
      {
        resources: {
          read: () => Promise.resolve([]) as never,
          close: () => Promise.resolve(['a provider left a process']),
        },
      },
    ));
});

describe("chord's commands in the list", () => {
  const listed = (client: AcpClient, sessionId: string) =>
    client
      .updates(sessionId)
      .filter((update) => update.sessionUpdate === 'available_commands_update')
      .map((update) =>
        (update.availableCommands as { name: string }[]).map(
          ({ name }) => name,
        ),
      );

  test("join the agent's, once it sends its own", () =>
    onAcp([], async ({ client, newSession }) => {
      const sessionId = await newSession();

      await until(() =>
        listed(client, sessionId).some((names) => names.includes('greet')),
      );

      expect(listed(client, sessionId).at(-1)).toEqual([
        'team',
        'new',
        'greet',
        'echo',
      ]);
    }));

  test('go to an agent that sends none, once the answer is written', () =>
    onAcp(['--no-commands'], async ({ client, newSession }) => {
      const sessionId = await newSession();

      await until(() => listed(client, sessionId).length > 0);

      expect(listed(client, sessionId)).toEqual([['team', 'new']]);
    }));

  test("an agent whose list came ahead of its answer gets no list of chord's alone", () =>
    onAcp(
      ['--config-delay', '300'],
      async ({ client, newSession }) => {
        const sessionId = await newSession();

        await until(() => listed(client, sessionId).length > 0);

        expect(listed(client, sessionId)).toEqual([
          ['team', 'new', 'greet', 'echo'],
        ]);
      },
      {
        place: () =>
          Promise.resolve({
            ...fakePlace(['--config-delay', '300']),
            startupOf: () => ({
              agentCommand: fakeAgentCommand(
                undefined,
                '--config-delay',
                '300',
              ),
              starting: { mode: { id: 'plan', from: 'a test' } },
            }),
          }),
      },
    ));

  test('go after a load answer too, its past ahead of it', () =>
    onAcp(['--no-commands'], async ({ client, cwd }) => {
      const sessionId = '11111111-2222-4333-8444-555555555555';
      const id = client.send('session/load', {
        sessionId,
        cwd,
        mcpServers: [],
      });

      expect((await client.answerTo(id)).error).toBeUndefined();

      await until(() => listed(client, sessionId).length > 0);

      const answer = client.messages.findIndex(
        (message) => message.id === id && message.method === undefined,
      );
      const commands = client.messages.findIndex(
        (message) =>
          (message.params?.update as { sessionUpdate?: string } | undefined)
            ?.sessionUpdate === 'available_commands_update',
      );

      expect(commands).toBeGreaterThan(answer);
    }));

  test("a name both offer is chord's alone", () =>
    onAcp(['--also-commands', 'new,team'], async ({ client, newSession }) => {
      const sessionId = await newSession();

      await until(() =>
        listed(client, sessionId).some((names) => names.includes('greet')),
      );

      expect(listed(client, sessionId).at(-1)).toEqual([
        'team',
        'new',
        'greet',
        'echo',
      ]);
    }));
});

describe('children', () => {
  interface Report {
    readonly on: string;
    readonly sessionId: string;
    readonly title: string;
    readonly state: { state: string; stopReason?: string };
    readonly capabilities?: object;
    readonly agent: Record<string, unknown>;
  }

  /** What chord said of each long-lived child, in order. */
  const reports = (client: AcpClient): Report[] =>
    client.messages.flatMap((message) => {
      const update = message.params?.update as
        | (Omit<Report, 'on' | 'agent'> & {
            sessionUpdate: string;
            _meta?: Record<string, Record<string, unknown>>;
          })
        | undefined;
      const agent = update?._meta?.['chord/agent'];

      return message.method === 'session/update' &&
        update?.sessionUpdate === 'subagent_update' &&
        agent?.['runtime'] !== undefined
        ? [{ ...update, on: String(message.params?.sessionId), agent }]
        : [];
    });

  const reportOf = (client: AcpClient, title: string) =>
    reports(client).findLast((report) => report.title === title);
  const reported = async (
    client: AcpClient,
    title: string,
    holds: (report: Report) => boolean = () => true,
  ) => {
    await until(() => {
      const report = reportOf(client, title);

      return report !== undefined && holds(report);
    }, 20_000);

    return reportOf(client, title)!;
  };

  const withTeam = async (cwd: string, text?: string) => {
    await mkdir(join(cwd, '.chord', 'teams'), { recursive: true });
    await writeFile(
      join(cwd, '.chord', 'teams', 'bugfix.md'),
      text ?? (await readFile(BUGFIX, 'utf8')),
    );
  };

  const server = () => ({ server: serveChord() });
  const allowing = (ask: { params?: Record<string, unknown> }) =>
    selected(
      (ask.params?.options as { optionId: string; kind: string }[]).find(
        ({ kind }) => kind === 'allow_once',
      )!.optionId,
    );

  test('a child is announced on main, its ask and its words under its composite id', () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();
        const running = prompt(sessionId, 'agentsquiet');
        const ask = await asked(client, PERMISSION);
        const composite = String(ask.params?.sessionId);

        expect(composite.startsWith(`${sessionId}/`)).toBe(true);

        const docs = await reported(client, 'docs');

        expect(docs).toMatchObject({
          on: sessionId,
          sessionId: composite,
          capabilities: { cancel: {} },
          agent: { runtime: 'fake' },
        });

        await reported(
          client,
          'docs',
          ({ state }) => state.state === 'requires_action',
        );

        client.respond(ask.id, allowing(ask));

        await client.answerTo(running);
        await until(() => client.said(composite) !== '', 20_000);
      },
      server(),
    ));

  test('a client without subagents: an ask refused on stderr, nothing of a child', () =>
    onAcp(
      [],
      async ({ client, newSession, prompt, lines }) => {
        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'agentsquiet'));

        await until(() =>
          lines.some((line) => line.includes("subagent's permission")),
        );

        expect(client.messages.some((m) => m.method === PERMISSION)).toBe(
          false,
        );
        expect(
          client.messages
            .filter((message) => message.method === 'session/update')
            .every((message) => message.params?.sessionId === sessionId),
        ).toBe(true);
        expect(reports(client)).toEqual([]);
      },
      { ...server(), capabilities: {} },
    ));

  test("a child's plan to a client without subagents is refused, never a yes", () =>
    onAcp(
      ['--tester-plays', 'cursorplan'],
      async ({ client, cwd, newSession, prompt, lines }) => {
        await withTeam(cwd);

        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'team'));

        await until(
          () => lines.some((line) => line.includes("subagent's plan")),
          20_000,
        );

        expect(client.messages.some((m) => m.method === PERMISSION)).toBe(
          false,
        );
      },
      { ...server(), capabilities: {} },
    ));

  test('a team: a member nests under its lead, its ask there; close leaves no group', async () => {
    const pids: number[] = [];

    await onAcp(
      [],
      async ({ client, cwd, newSession, prompt }) => {
        await withTeam(cwd);

        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'team'));

        const lead = await reported(client, 'bugfix');
        const tester = await reported(client, 'tester');

        expect(lead).toMatchObject({
          on: sessionId,
          agent: { team: 'bugfix', role: 'lead', runtime: 'fake' },
        });
        expect(tester.on).toBe(lead.sessionId);
        expect(tester.sessionId.startsWith(`${lead.sessionId}/`)).toBe(true);
        expect(tester.agent).toMatchObject({
          role: 'member',
          model: 'fake-small',
          mode: 'acceptEdits',
        });

        const ask = await asked(client, PERMISSION);

        expect(ask.params?.sessionId).toBe(tester.sessionId);

        client.respond(ask.id, allowing(ask));

        await until(() => pids.length >= 3, 20_000);

        expect(pids.some(groupAlive)).toBe(true);

        await client.request('session/close', { sessionId });

        await until(() => !pids.some(groupAlive));
        await reported(
          client,
          'bugfix',
          ({ agent }) => agent['closed'] === true,
        );
      },
      {
        ...server(),
        open: async (options) => {
          const session = await openSession(options);

          pids.push(...session.agentPids);

          return session;
        },
      },
    );
  });

  test('a child in bypassPermissions says so, reported only', () =>
    onAcp(
      ['--bypass-mode'],
      async ({ client, cwd, newSession, prompt }) => {
        await withTeam(
          cwd,
          (await readFile(BUGFIX, 'utf8')).replace(
            'mode: default',
            'mode: bypassPermissions',
          ),
        );

        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'team'));

        await reported(
          client,
          'bugfix',
          ({ agent }) => agent['mode'] === 'bypassPermissions',
        );
      },
      server(),
    ));

  test("a child's mode moved goes up with the next report", () =>
    onAcp(
      ['--tester-plays', 'status'],
      async ({ client, cwd, newSession, prompt }) => {
        await withTeam(cwd);

        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'team'));

        await reported(
          client,
          'tester',
          ({ agent }) => agent['mode'] === 'plan',
        );
      },
      server(),
    ));

  test('a cancel of a long-lived child stops its turn; it stays open', () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'agentcost'));

        const { sessionId: composite } = await reported(
          client,
          'parser',
          ({ state }) => state.state === 'running',
        );

        client.notify('session/cancel', { sessionId: composite });

        const stopped = await reported(
          client,
          'parser',
          ({ state }) => state.state === 'idle',
        );

        expect(stopped.state.stopReason).toBe('cancelled');
        expect(stopped.agent['closed']).toBeUndefined();
      },
      server(),
    ));

  test('a child cleared after it died reports afresh, under the same id', () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'agentexit'));

        const dead = await reported(
          client,
          'parser',
          ({ agent }) => agent['gone'] === 'exited',
        );

        expect(dead.state.state).toBe('unknown');

        await client.answerTo(prompt(sessionId, 'agentclearonly'));

        const fresh = await reported(
          client,
          'parser',
          ({ agent, state }) =>
            agent['gone'] === undefined && state.state === 'idle',
        );

        expect(fresh.sessionId).toBe(dead.sessionId);
      },
      server(),
    ));

  test('close_agent says closed, with nothing left to cancel', () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'agentcost'));
        await client.answerTo(prompt(sessionId, 'agentclose'));

        const closed = await reported(
          client,
          'parser',
          ({ agent }) => agent['closed'] === true,
        );

        expect(closed.capabilities).toBeUndefined();
      },
      server(),
    ));

  test("a task's permission goes under its composite id; its answer reaches it", () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();
        const running = prompt(sessionId, 'taskstays');
        const ask = await asked(client, PERMISSION);

        expect(String(ask.params?.sessionId).startsWith(`${sessionId}/`)).toBe(
          true,
        );

        client.respond(ask.id, allowing(ask));
        client.notify('session/cancel', { sessionId });

        await client.answerTo(running);
      },
      server(),
    ));

  test("a task's form (taskask) goes under its composite id, and is answered", () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();
        const running = prompt(sessionId, 'taskask');
        const ask = await asked(client, 'elicitation/create');

        expect(String(ask.params?.sessionId).startsWith(`${sessionId}/`)).toBe(
          true,
        );

        client.respond(ask.id, { action: 'cancel' });

        await client.answerTo(running);
      },
      server(),
    ));

  test("a task's form to a client without subagents is cancelled, on stderr", () =>
    onAcp(
      [],
      async ({ client, newSession, prompt, lines }) => {
        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'taskask'));

        await until(
          () => lines.some((line) => line.includes("subagent's form")),
          20_000,
        );

        expect(
          client.messages.some((m) => m.method === 'elicitation/create'),
        ).toBe(false);
      },
      { ...server(), capabilities: {} },
    ));

  test('what a child says before it is up goes up after, under its composite id', () =>
    onAcp(
      ['--config-delay', '300'],
      async ({ client, cwd, newSession, prompt }) => {
        await withTeam(cwd);

        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'team'));

        // A member's model and mode are set before `connected`, and its
        // commands come while they are.
        const { sessionId: composite } = await reported(client, 'tester');

        await until(
          () => kinds(client, composite).includes('available_commands_update'),
          20_000,
        );
      },
      server(),
    ));

  for (const [name, capabilities] of [
    ['takes subagents', FULL],
    ['takes none', {}],
  ] as const) {
    test(`a task's agent asking as main is refused, to a client that ${name}`, () =>
      onAcp(
        [],
        async ({ client, newSession, prompt, lines }) => {
          const sessionId = await newSession();

          await client.answerTo(prompt(sessionId, 'taskaskas'));

          await until(
            () => lines.some((line) => line.includes('does not know')),
            20_000,
          );

          expect(client.messages.some((m) => m.method === PERMISSION)).toBe(
            false,
          );
        },
        { ...server(), capabilities },
      ));
  }

  test("a task's agent's form as main goes under the task, not main", () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'taskformas'));

        const ask = await asked(client, 'elicitation/create');

        expect(ask.params?.sessionId).not.toBe(sessionId);
        expect(String(ask.params?.sessionId).startsWith(`${sessionId}/`)).toBe(
          true,
        );

        client.respond(ask.id, { action: 'cancel' });
      },
      server(),
    ));

  test("a task's agent's form as main to a client without subagents is cancelled", () =>
    onAcp(
      [],
      async ({ client, newSession, prompt, lines }) => {
        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'taskformas'));

        await until(
          () => lines.some((line) => line.includes("subagent's form")),
          20_000,
        );

        expect(
          client.messages.some((m) => m.method === 'elicitation/create'),
        ).toBe(false);
      },
      { ...server(), capabilities: {} },
    ));

  test('a task says it can be cancelled, and a cancel ends it alone', () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();
        const tasks = () =>
          client
            .updates(sessionId)
            .filter((update) => update.sessionUpdate === 'subagent_update');

        await client.answerTo(prompt(sessionId, 'tasklong'));
        await until(() => tasks().length > 0, 20_000);

        const [started] = tasks();

        expect(started?.capabilities).toEqual({ cancel: {} });

        client.notify('session/cancel', {
          sessionId: started?.sessionId as string,
        });

        await until(() =>
          tasks().some(
            (update) =>
              (update.state as { stopReason?: string }).stopReason ===
              'cancelled',
          ),
        );
      },
      server(),
    ));

  for (const method of ['session/resume', 'session/load']) {
    test(`main's agent dying closes its children; ${method} names them`, async () => {
      const opened: Session[] = [];
      const pids: number[] = [];

      await onAcp(
        [],
        async ({ client, cwd, newSession, prompt, stateDir }) => {
          const sessionId = await newSession();

          await client.answerTo(prompt(sessionId, 'agentcost'));
          await reported(
            client,
            'parser',
            ({ state }) => state.state === 'running',
          );
          await recorded(stateDir, sessionId, 'result');

          const [pid] = opened[0]!.agentPids;

          process.kill(pid!, 'SIGKILL');

          await reported(
            client,
            'parser',
            ({ agent }) => agent['closed'] === true,
          );
          await until(() => !pids.some(groupAlive));

          const { result, error } = await client.request(method, {
            sessionId,
            cwd,
            mcpServers: [],
          });

          expect(error).toBeUndefined();
          expect(
            (result?._meta as Record<string, unknown>)['chord/left_open'],
          ).toEqual([expect.objectContaining({ name: 'parser' })]);
        },
        {
          ...server(),
          open: async (options) => {
            const session = await openSession(options);

            opened.push(session);
            pids.push(...session.agentPids);

            return session;
          },
        },
      );
    });
  }

  test("dimcode's notice covers a child, once", () =>
    onAcp(
      ['--dimcode-permission', 'full-access', '--child-runtime', 'dimcode'],
      async ({ client, newSession, prompt, lines }) => {
        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'agentother'));

        await until(() => kinds(client, sessionId).includes('notice'), 20_000);

        expect(
          kinds(client, sessionId).filter((kind) => kind === 'notice'),
        ).toHaveLength(1);
        expect(lines.length).toBeGreaterThan(0);
      },
      {
        ...server(),
        place: () =>
          Promise.resolve({
            ...fakePlace([
              '--dimcode-permission',
              'full-access',
              '--child-runtime',
              'dimcode',
            ]),
            runtimes: ['fake', 'dimcode'],
          }),
      },
    ));
});

describe("chord's commands", () => {
  const server = () => ({ server: serveChord() });
  const withTeam = async (cwd: string) => {
    await mkdir(join(cwd, '.chord', 'teams'), { recursive: true });
    await copyFile(BUGFIX, join(cwd, '.chord', 'teams', 'bugfix.md'));
  };

  /** What a command said, as its one marked chunk, then its answer. */
  const ran = async (client: AcpClient, sessionId: string, text: string) => {
    const before = client.updates(sessionId).length;
    const answer = await client.answerTo(
      client.send('session/prompt', {
        sessionId,
        prompt: [{ type: 'text', text }],
      }),
    );
    const said = client
      .updates(sessionId)
      .slice(before)
      .find(
        (update) =>
          update._meta !== undefined &&
          'chord/command' in (update._meta as object),
      );

    return {
      answer,
      text: (said?.content as { text?: string } | undefined)?.text,
      meta: (said?._meta as Record<string, unknown> | undefined)?.[
        'chord/command'
      ],
    };
  };

  test('/team lists, and nothing of it reaches the agent or the record', () =>
    onAcp(
      [],
      async ({ client, cwd, newSession, stateDir }) => {
        await withTeam(cwd);

        const sessionId = await newSession();
        const { answer, text, meta } = await ran(client, sessionId, '/team');

        expect(answer.result?.stopReason).toBe('end_turn');
        expect(answer.result?.usage).toBeUndefined();
        expect(meta).toEqual({ name: 'team', failed: false });
        expect(text).toContain('Teams:\n\n- bugfix · 3 agents · fake');
        expect(text).toContain('No run is open.');
        expect(kinds(client, sessionId)).not.toContain('user_message_chunk');

        const { sessions } = (await client.request('session/list', {}))
          .result as { sessions: unknown[] };

        expect(sessions).toEqual([]);
        expect(stateDir).not.toBe('');
      },
      server(),
    ));

  test('/team show of a team, then of its run; a run and its stop', () =>
    onAcp(
      [],
      async ({ client, cwd, newSession }) => {
        await withTeam(cwd);

        const sessionId = await newSession();

        expect(
          (await ran(client, sessionId, '/team show bugfix')).text,
        ).toContain('bugfix · .chord/teams/bugfix.md\n\nFixes a bug');

        const started = await ran(
          client,
          sessionId,
          '/team run bugfix fix the quote',
        );

        expect(started.text).toBe(
          'Team bugfix started. Its lead is bugfix; /team stop bugfix ends it.',
        );
        expect(started.meta).toEqual({ name: 'team', failed: false });

        const shown = await ran(client, sessionId, '/team show bugfix');

        expect(shown.text).toContain('on "fix the quote"');
        expect(shown.text).toContain('- lead (bugfix) · open · fake');

        expect((await ran(client, sessionId, '/team')).text).toContain(
          'Runs open:\n\n- bugfix · team bugfix · working',
        );

        const stopped = await ran(client, sessionId, '/team stop bugfix');

        expect(stopped.text).toContain('Stopped bugfix:');
        // Its members may or may not have opened by now.
        expect(stopped.text).toMatch(
          /chord with (its|each) agent's name and -r lists (it|them)$/,
        );
        expect((await ran(client, sessionId, '/team stop bugfix')).text).toBe(
          'No run named bugfix is open · /team lists them',
        );
      },
      server(),
    ));

  test.each([
    ['/team run bugfix', '/team run bugfix takes the job after the name'],
    ['/team run', 'Which team? /team lists them'],
    ['/team run nope a job', 'No team named nope · /team lists them'],
    ['/team stop', 'Which run? /team lists them'],
    ['/team show', 'Which team? /team lists them'],
    ['/team nope', '/team has no nope; it takes list, new, show, run or stop'],
    ['/new nope', 'No agent named nope; chord knows fake'],
  ])('%s is refused in a chunk, not an error', (typed, words) =>
    onAcp(
      [],
      async ({ client, cwd, newSession }) => {
        await withTeam(cwd);

        const sessionId = await newSession();
        const { answer, text, meta } = await ran(client, sessionId, typed);

        expect(answer.error).toBeUndefined();
        expect(answer.result?.stopReason).toBe('end_turn');
        expect(text).toBe(words);
        expect(meta).toMatchObject({ failed: true });
      },
      server(),
    ),
  );

  test('a signal while a command is at its work: cancelled once, no chunk after', async () => {
    await onAcp(
      [],
      async ({ client, cwd, newSession, run, exits }) => {
        const sessionId = await newSession();

        // Reading a team file that is a pipe holds `/team` until it is written.
        const held = join(cwd, '.chord', 'teams', 'held.md');

        await mkdir(join(cwd, '.chord', 'teams'), { recursive: true });

        expect(spawnSync('mkfifo', [held]).status).toBe(0);

        const id = client.send('session/prompt', {
          sessionId,
          prompt: [{ type: 'text', text: '/team' }],
        });

        // Requests start in order: answered, this one has reached its read.
        await client.request('session/list', {});

        void run.leave({ kind: 'signal', signal: 'SIGTERM' });

        expect((await client.answerTo(id)).result?.stopReason).toBe(
          'cancelled',
        );

        await until(() => exits.length > 0, 20_000);

        // Its work ends now, with its request answered.
        await writeFile(held, '---\n');

        expect(
          client.messages.filter(
            (message) => message.id === id && message.method === undefined,
          ),
        ).toHaveLength(1);
        expect(client.said(sessionId)).toBe('');
      },
      server(),
    );
  });

  test("/new opens an idle child, on main's runtime with none named", () =>
    onAcp(
      [],
      async ({ client, newSession }) => {
        const sessionId = await newSession();
        const { text, meta } = await ran(client, sessionId, '/new');

        expect(text).toBe(
          "Opened fake (fake). It is idle, with no prompt yet; main's send_message starts it, so ask main to send it the work.",
        );
        expect(meta).toEqual({ name: 'new', failed: false });
      },
      server(),
    ));

  test("/team new is a turn of the agent's, its preamble ahead", () =>
    onAcp(
      [],
      async ({ client, newSession }) => {
        const sessionId = await newSession();
        const running = client.send('session/prompt', {
          sessionId,
          prompt: [{ type: 'text', text: '/team new fixes bugs' }],
        });

        await asked(client, PERMISSION);

        client.notify('session/cancel', { sessionId });

        await client.answerTo(running);
      },
      {
        ...server(),
        // What the fake proposes runs on these; nothing here starts them.
        place: () =>
          Promise.resolve({
            ...fakePlace(),
            runtimes: ['fake', 'claude', 'codex'],
          }),
      },
    ));

  test('a command beside an image is refused, and nothing runs', () =>
    onAcp(
      [],
      async ({ client, cwd, newSession }) => {
        await withTeam(cwd);

        const sessionId = await newSession();
        const answer = await client.answerTo(
          client.send('session/prompt', {
            sessionId,
            prompt: [
              { type: 'text', text: '/team run bugfix fix it' },
              { type: 'image', data: 'x', mimeType: 'image/png' },
            ],
          }),
        );

        expect(answer.result?.stopReason).toBe('end_turn');
        expect(client.said(sessionId)).toBe(
          '/team takes text alone, and this prompt had other blocks beside it. Nothing ran; send the command by itself.',
        );
        expect(
          client
            .updates(sessionId)
            .some((update) => update.sessionUpdate === 'subagent_update'),
        ).toBe(false);
      },
      server(),
    ));

  test('another slash command still goes to the agent as typed', () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, '/greet'));

        expect(client.said(sessionId)).not.toBe('');
      },
      server(),
    ));

  test('a command overtakes a queued prompt, and its note reaches the next send', () =>
    onAcp(
      ['--echo-messages'],
      async ({ client, cwd, newSession, prompt }) => {
        await withTeam(cwd);

        const sessionId = await newSession();
        const running = prompt(sessionId, 'slow');
        const queued = prompt(sessionId, 'text');
        const { answer } = await ran(client, sessionId, '/team');

        // Answered with the first turn and the queued one both unanswered.
        expect(answer.result?.stopReason).toBe('end_turn');
        expect(
          client.messages.some(
            (message) => message.id === running && message.method === undefined,
          ),
        ).toBe(false);

        await client.answerTo(running);
        await client.answerTo(queued);
      },
      server(),
    ));

  test("a session/cancel aborts a run still starting; a run's reply already went", async () => {
    const lead = { started: false };
    const gateDir = await mkdtemp(join(tmpdir(), 'chord-acp-gate-'));

    try {
      await onAcp(
        [],
        async ({ client, cwd, newSession }) => {
          await withTeam(cwd);

          const sessionId = await newSession();
          const { text } = await ran(
            client,
            sessionId,
            '/team run bugfix fix it',
          );

          expect(text).toContain('Team bugfix started.');

          client.notify('session/cancel', { sessionId });

          // Its lead was still starting: it goes, and no run is left.
          await until(() =>
            client
              .updates(sessionId)
              .some(
                (update) =>
                  update.sessionUpdate === 'subagent_update' &&
                  (update._meta as Record<string, { closed?: boolean }>)?.[
                    'chord/agent'
                  ]?.closed === true,
              ),
          );

          expect((await ran(client, sessionId, '/team')).text).toContain(
            'No run is open.',
          );
        },
        {
          ...server(),
          place: () =>
            Promise.resolve({
              ...fakePlace(),
              startupOf: (name: string) => ({
                agentCommand:
                  name === 'fake' && !lead.started
                    ? fakeAgentCommand()
                    : gatedCommand(
                        join(gateDir, 'release'),
                        fakeAgentCommand(),
                      ),
              }),
            }),
          open: (options) => {
            const opening = openSession(options);

            lead.started = true;

            return opening;
          },
        },
      );
    } finally {
      await writeFile(join(gateDir, 'release'), '');
      await rm(gateDir, { recursive: true, force: true });
    }
  });

  test('/team show of a selected run is refused, open or by its id once closed', () =>
    onAcp(
      [],
      async ({ client, cwd, newSession, prompt }) => {
        await mkdir(join(cwd, '.chord', 'teams'), { recursive: true });
        await copyFile(BUGFIX, join(cwd, '.chord', 'teams', 'fixture.md'));

        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'budgetawareteam'));

        const open = await ran(client, sessionId, '/team show fixture');
        const [, runId] =
          /then \/team show (\S+) there$/.exec(open.text ?? '') ?? [];

        expect(open.text).toStartWith(
          "fixture is a selected run, and only chord's window shows its receipt: chord -r with this session's id",
        );
        expect(open.meta).toEqual({ name: 'team', failed: true });
        expect(runId).toBeString();

        await ran(client, sessionId, '/team stop fixture');

        const closed = await ran(client, sessionId, `/team show ${runId}`);

        expect(closed.text).toBe(
          `${runId} is a selected run, and only chord's window shows its receipt: chord -r with this session's id, then /team show ${runId} there`,
        );
      },
      {
        ...server(),
        place: () =>
          Promise.resolve({
            ...fakePlace(),
            teamSelection: { intent: 'balanced' as const },
          }),
      },
    ));

  test('a session/cancel while the team is read: no run started', () =>
    onAcp(
      [],
      async ({ client, cwd, newSession }) => {
        await withTeam(cwd);

        const sessionId = await newSession();
        const running = client.send('session/prompt', {
          sessionId,
          prompt: [{ type: 'text', text: '/team run bugfix fix it' }],
        });

        client.notify('session/cancel', { sessionId });

        expect((await client.answerTo(running)).result?.stopReason).toBe(
          'end_turn',
        );
        expect(client.said(sessionId)).toBe(
          'This launch was cancelled; no run started.',
        );
      },
      server(),
    ));

  test("session/load of a run's records: main's runtime opens, another's is refused", () =>
    onAcp(
      [],
      async ({ client, cwd, newSession, stateDir }) => {
        await mkdir(join(cwd, '.chord', 'teams'), { recursive: true });
        await writeFile(
          join(cwd, '.chord', 'teams', 'bugfix.md'),
          (await readFile(BUGFIX, 'utf8'))
            .replace(/(- name: tester[\s\S]*?agent: )fake/, '$1codex')
            .replace(
              /(- name: tester[\s\S]*?model: )fake-small/,
              '$1fake-large',
            ),
        );

        const sessionId = await newSession();

        await ran(client, sessionId, '/team run bugfix fix it');
        await until(
          () =>
            client.messages.some(
              (message) =>
                (message.params?.update as { title?: string } | undefined)
                  ?.title === 'tester',
            ),
          20_000,
        );

        const ask = await asked(client, PERMISSION);

        client.respond(ask.id, selected('deny'));

        await ran(client, sessionId, '/team stop bugfix');

        const records = await readRecords(stateDir);
        const load = (name: string) =>
          client.request('session/load', {
            sessionId: records.find((each) => each.name === name)?.sessionId,
            cwd,
            mcpServers: [],
          });

        // On main's runtime it opens; on another, it is that agent's to open.
        expect((await load('bugfix')).error).toBeUndefined();
        expect((await load('tester')).error?.message).toContain(
          'belongs to another agent (codex)',
        );

        // What the stop words send a person to: that agent's list.
        expect(
          earlierSessions(records, { agent: 'codex', cwd }).map(
            ({ resume }) => resume.name,
          ),
        ).toContain('tester');
      },
      {
        ...server(),
        place: () =>
          Promise.resolve({ ...fakePlace(), runtimes: ['fake', 'codex'] }),
      },
    ));

  test('a session whose only act is /team run is unlisted; a later prompt shows no note on load', () =>
    onAcp(
      [],
      async ({ client, cwd, newSession, prompt, stateDir }) => {
        await withTeam(cwd);

        const sessionId = await newSession();

        await ran(client, sessionId, '/team run bugfix fix it');

        // Its lead has a record of its own, which is not this session's.
        const listed = async () =>
          (
            (await client.request('session/list', {})).result as {
              sessions: { sessionId: string; title: string }[];
            }
          ).sessions.filter((each) => each.sessionId === sessionId);

        expect(await listed()).toEqual([]);

        await client.answerTo(prompt(sessionId, 'text'));
        await recorded(stateDir, sessionId, 'result');
        await client.request('session/close', { sessionId });

        expect((await listed()).map(({ title }) => title)).toEqual(['text']);

        const seen = client.messages.length;

        await client.request('session/load', {
          sessionId,
          cwd,
          mcpServers: [],
        });

        const said = client.messages.slice(seen).flatMap((message) => {
          const update = message.params?.update as
            | {
                sessionUpdate?: string;
                content?: { text?: string };
              }
            | undefined;

          return update?.sessionUpdate === 'user_message_chunk'
            ? [update.content?.text]
            : [];
        });

        expect(said).toContain('text');
        expect(said.join('\n')).not.toContain('message from');
        expect(said.join('\n')).not.toContain('/team');
      },
      server(),
    ));
});

describe('the session state (CHD-575)', () => {
  /** What `_chord/session/state` said of `sessionId`, in order. */
  const states = (client: AcpClient, sessionId: string) =>
    client.messages.flatMap((message) => {
      if (
        message.method !== '_chord/session/state' ||
        message.params?.sessionId !== sessionId
      ) {
        return [];
      }

      const state: Record<string, unknown> = { ...message.params };

      delete state['sessionId'];

      return [state];
    });

  test("a client's turn runs as the client's, then idle", () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();

      await client.answerTo(prompt(sessionId, 'text'));
      await until(() => states(client, sessionId).length === 2);

      expect(states(client, sessionId)).toEqual([
        { state: 'running', origin: 'client' },
        { state: 'idle' },
      ]);
    }));

  test('an ask requires action until it is answered', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'permission');
      const ask = await asked(client, PERMISSION);

      expect(states(client, sessionId).at(-1)).toEqual({
        state: 'requires_action',
        origin: 'client',
      });

      client.respond(ask.id, selected('allow'));
      await client.answerTo(running);
      await until(() => states(client, sessionId).at(-1)?.['state'] === 'idle');

      expect(states(client, sessionId)).toEqual([
        { state: 'running', origin: 'client' },
        { state: 'requires_action', origin: 'client' },
        { state: 'running', origin: 'client' },
        { state: 'idle' },
      ]);
    }));

  test('closed with an ask open, nothing more is said of it', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'permission');

      await asked(client, PERMISSION);

      const said = states(client, sessionId).length;

      await client.request('session/close', { sessionId });
      await client.answerTo(running);

      expect(states(client, sessionId)).toHaveLength(said);
      expect(states(client, sessionId).at(-1)).toEqual({
        state: 'requires_action',
        origin: 'client',
      });
    }));

  test("a monitor's turn, which no client began, runs as a message", () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'monitor'));
        await until(
          () =>
            states(client, sessionId).some(
              (state) => state['origin'] === 'message',
            ),
          20_000,
        );

        expect(states(client, sessionId).slice(0, 3)).toEqual([
          { state: 'running', origin: 'client' },
          { state: 'idle' },
          { state: 'running', origin: 'message' },
        ]);
      },
      { server: serveChord() },
    ));

  test('a load says nothing: nothing runs on it', () =>
    onAcp([], async ({ client, cwd, stateDir, newSession, prompt }) => {
      const sessionId = await newSession();

      await client.answerTo(prompt(sessionId, 'text'));
      await recorded(stateDir, sessionId, 'result');
      await client.request('session/close', { sessionId });

      const seen = client.messages.length;

      await client.request('session/load', { sessionId, cwd, mcpServers: [] });

      expect(
        client.messages
          .slice(seen)
          .some((message) => message.method === '_chord/session/state'),
      ).toBe(false);
    }));
});

describe('a steer (CHD-575)', () => {
  const STEER = '_chord/session/steer';
  const steer = (client: AcpClient, sessionId: string, text: string) =>
    client.request(STEER, {
      sessionId,
      prompt: [{ type: 'text', text }],
    });
  /** What the client was told someone said in `sessionId`. */
  const toldWords = (client: AcpClient, sessionId: string) =>
    client
      .updates(sessionId)
      .flatMap((update) =>
        update['sessionUpdate'] === 'user_message_chunk'
          ? [(update['content'] as { text?: string }).text]
          : [],
      );

  test('it takes its own entry into the running turn, not the prompt queued ahead', () =>
    onAcp(['--steering', 'claude'], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'texttillsteered');

      await until(() => client.said(sessionId).includes('came in chunks'));

      const queued = prompt(sessionId, 'text');

      expect((await steer(client, sessionId, 'Mine.')).result).toEqual({
        delivery: 'sent',
      });
      // The steer ended the running turn; the prompt ahead of it ran as its
      // own and answers on its own end.
      expect((await client.answerTo(running)).result?.stopReason).toBe(
        'end_turn',
      );
      expect((await client.answerTo(queued)).result?.stopReason).toBe(
        'end_turn',
      );
      expect(toldWords(client, sessionId)).not.toContain('Mine.');
    }));

  test('with no turn running it starts one, queued, the client’s, its words not told back', () =>
    onAcp(['--steering', 'claude'], async ({ client, newSession }) => {
      const sessionId = await newSession();

      expect((await steer(client, sessionId, 'text')).result).toEqual({
        delivery: 'queued',
      });
      await until(() =>
        client.messages.some(
          (message) =>
            message.method === '_chord/session/state' &&
            message.params?.['state'] === 'idle',
        ),
      );

      expect(
        client.messages
          .filter((message) => message.method === '_chord/session/state')
          .map((message) => message.params?.['origin']),
      ).toEqual(['client', undefined]);
      expect(client.said(sessionId)).toContain('came in chunks');
      expect(toldWords(client, sessionId)).toEqual([]);
    }));

  test('on an agent that takes no steering it waits queued', () =>
    onAcp([], async ({ client, newSession, prompt }) => {
      const sessionId = await newSession();
      const running = prompt(sessionId, 'long');

      await until(() => client.said(sessionId) !== '');

      expect((await steer(client, sessionId, 'text')).result).toEqual({
        delivery: 'queued',
      });

      client.notify('session/cancel', { sessionId });

      expect((await client.answerTo(running)).result?.stopReason).toBe(
        'cancelled',
      );
    }));

  test('an unknown session is -32002, a prompt that does not read -32602', () =>
    onAcp([], async ({ client, newSession }) => {
      const sessionId = await newSession();

      expect((await steer(client, 'nobody', 'text')).error?.code).toBe(-32002);
      expect(
        (await client.request(STEER, { sessionId, prompt: [{ type: 'text' }] }))
          .error?.code,
      ).toBe(-32602);
      expect(
        (
          await client.request(STEER, {
            sessionId,
            prompt: [{ type: 'audio', data: '', mimeType: 'audio/wav' }],
          })
        ).error?.code,
      ).toBe(-32602);
    }));

  test('advertised', () =>
    onAcp([], async ({ client }) => {
      expect(
        (
          (await client.answerTo(1)).result?._meta as Record<
            string,
            { extensions: object }
          >
        )['chord/acp']?.extensions,
      ).toMatchObject({ 'session/steer': 1 });
    }));
});

describe('agents/send and agents/close (CHD-575)', () => {
  const SEND = '_chord/agents/send';
  const CLOSE = '_chord/agents/close';
  const server = () => ({ server: serveChord() });
  const send = (client: AcpClient, sessionId: string, text: string) =>
    client.request(SEND, { sessionId, prompt: [{ type: 'text', text }] });

  /** Each long-lived child chord announced, by its title, as last told. */
  const children = (client: AcpClient) =>
    new Map(
      client.messages.flatMap((message) => {
        const update = message.params?.update as
          | {
              sessionUpdate?: string;
              sessionId?: string;
              title?: string;
              state?: { state: string };
              _meta?: Record<string, { role?: string }>;
            }
          | undefined;
        const agent = update?._meta?.['chord/agent'];

        return message.method === 'session/update' &&
          update?.sessionUpdate === 'subagent_update' &&
          agent !== undefined
          ? [
              [
                update.title!,
                { id: update.sessionId!, state: update.state?.state },
              ],
            ]
          : [];
      }),
    );
  const childNamed = async (client: AcpClient, title: string) => {
    await until(() => children(client).has(title), 20_000);

    return children(client).get(title)!.id;
  };

  /** The first child announced: its title and its id. */
  const firstChild = async (client: AcpClient) => {
    await until(() => children(client).size > 0, 20_000);

    const [first] = children(client);

    assert(first !== undefined);

    return { title: first[0], id: first[1].id };
  };

  /** Starts after the first `plain` go through only once `gate` exists. */
  const gatedAfter = (plain: number, gate: string) => {
    let opened = 0;

    return {
      ...server(),
      place: () =>
        Promise.resolve({
          ...fakePlace(),
          startupOf: () => ({
            agentCommand:
              opened < plain
                ? fakeAgentCommand()
                : gatedCommand(gate, fakeAgentCommand()),
          }),
        }),
      open: (options: OpenSessionOptions) => {
        opened += 1;

        return openSession(options);
      },
    };
  };

  test("a child's prompt is sent, or queued behind its turn; closed, it is -32002", () =>
    onAcp(
      [],
      async ({ client, newSession, prompt }) => {
        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, 'agenttitled'));

        const { title, id: parser } = await firstChild(client);

        // Its first turn over, as chord reads it: idle is said of it while
        // it starts too.
        await until(
          () =>
            client.said(parser).includes('came in chunks') &&
            children(client).get(title)?.state === 'idle',
          20_000,
        );

        const said = client.said(parser).length;

        expect((await send(client, parser, 'long')).result).toEqual({
          delivery: 'sent',
        });
        await until(() => client.said(parser).length > said);
        expect((await send(client, parser, 'text')).result).toEqual({
          delivery: 'queued',
        });

        expect(
          (await client.request(CLOSE, { sessionId: parser })).result,
        ).toEqual({ closed: [title] });
        expect((await send(client, parser, 'text')).error?.code).toBe(-32002);
        expect(
          (await client.request(CLOSE, { sessionId: parser })).error?.code,
        ).toBe(-32002);
      },
      server(),
    ));

  test('main, a typo, or a task is no child of these: -32002', () =>
    onAcp(
      [],
      async ({ client, newSession }) => {
        const sessionId = await newSession();

        for (const id of [sessionId, `${sessionId}/nobody`, 'nobody']) {
          expect((await send(client, id, 'text')).error?.code).toBe(-32002);
          expect(
            (await client.request(CLOSE, { sessionId: id })).error?.code,
          ).toBe(-32002);
        }
      },
      server(),
    ));

  test('a lead closes with its members, each by name', () =>
    onAcp(
      [],
      async ({ client, cwd, newSession, prompt }) => {
        await mkdir(join(cwd, '.chord', 'teams'), { recursive: true });
        await copyFile(BUGFIX, join(cwd, '.chord', 'teams', 'bugfix.md'));

        const sessionId = await newSession();

        await client.answerTo(prompt(sessionId, '/team run bugfix fix it'));

        const lead = await childNamed(client, 'bugfix');

        await childNamed(client, 'tester');
        await childNamed(client, 'coder');

        const { result } = await client.request(CLOSE, { sessionId: lead });
        const closed = (result as { closed: string[] }).closed;

        expect(closed[0]).toBe('bugfix');
        expect(closed.slice(1).toSorted()).toEqual(['coder', 'tester']);
      },
      server(),
    ));

  test('a child still starting is not sent to: -32603, nothing held', async () => {
    const gates = await mkdtemp(join(tmpdir(), 'chord-acp-gate-'));
    const gate = join(gates, 'release');

    try {
      await onAcp(
        [],
        async ({ client, newSession, prompt }) => {
          const sessionId = await newSession();

          await client.answerTo(prompt(sessionId, '/new'));

          const { title, id: child } = await firstChild(client);
          const { error } = await send(client, child, 'text');

          expect(error?.code).toBe(-32603);
          expect(error?.message).toBe(
            `${title} is starting; send once its subagent_update says idle`,
          );
        },
        gatedAfter(1, gate),
      );
    } finally {
      await writeFile(gate, '');
      await rm(gates, { recursive: true, force: true });
    }
  });

  test('a child being cleared is not sent to: -32603, nothing held', async () => {
    const gates = await mkdtemp(join(tmpdir(), 'chord-acp-gate-'));
    const gate = join(gates, 'release');

    try {
      await onAcp(
        [],
        async ({ client, newSession, prompt }) => {
          const sessionId = await newSession();

          // parser works on until it is stopped, which the clear does.
          await client.answerTo(prompt(sessionId, 'agentcost'));

          const parser = await childNamed(client, 'parser');
          const clearing = prompt(sessionId, 'agentclearonly');

          await until(
            () =>
              JSON.stringify(client.updates(sessionId)).includes('clear_agent'),
            20_000,
          );

          // The call reaches chord a moment after the agent says it makes it:
          // asked again, a little apart, until the clear has begun.
          let error: WireMessage['error'];

          for (
            const deadline = performance.now() + 20_000;
            error?.message.includes('cleared') !== true &&
            performance.now() < deadline;
          ) {
            error = (await send(client, parser, 'text')).error;

            await new Promise((resolve) => setTimeout(resolve, 50));
          }

          expect(error?.message).toBe(
            'parser is being cleared; send once its subagent_update says idle',
          );

          await writeFile(gate, '');

          expect((await client.answerTo(clearing)).result?.stopReason).toBe(
            'end_turn',
          );
        },
        gatedAfter(2, gate),
      );
    } finally {
      await writeFile(gate, '');
      await rm(gates, { recursive: true, force: true });
    }
  });

  test('advertised', () =>
    onAcp([], async ({ client }) => {
      expect(
        (
          (await client.answerTo(1)).result?._meta as Record<
            string,
            { extensions: object }
          >
        )['chord/acp']?.extensions,
      ).toMatchObject({ agents: 1 });
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
