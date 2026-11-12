import { afterEach, describe, expect, test } from 'bun:test';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import {
  client,
  type ClientConnection,
  ndJsonStream,
  type SessionNotification,
} from '@agentclientprotocol/sdk/unstable';
import type { SdkCredentialStore } from '@cursor/sdk';
import { CursorError, KeychainError } from '../src/errors.ts';
import type { Git } from '../src/repo.ts';
import { serve } from '../src/serve.ts';
import { fakeCursor } from './fixtures/fake_port.ts';

const CWD = '/work/acme-web';
const LINK = (id: string) => `https://cursor.com/agents/${id}`;

/** git in a pushed repository, answered from a table. */
function fakeGit(
  overrides: Record<
    string,
    { status: number | null; stdout?: string; stderr?: string }
  > = {},
): Git {
  const answers: Record<
    string,
    { status: number | null; stdout?: string; stderr?: string }
  > = {
    'rev-parse --is-inside-work-tree': { status: 0, stdout: 'true\n' },
    'symbolic-ref --quiet --short HEAD': { status: 0, stdout: 'login-page\n' },
    'for-each-ref --format=%(push:remotename) refs/heads/login-page': {
      status: 0,
      stdout: 'origin\n',
    },
    'rev-parse --verify --quiet refs/remotes/origin/login-page': {
      status: 0,
      stdout: 'abc\n',
    },
    'merge-base --is-ancestor HEAD refs/remotes/origin/login-page': {
      status: 0,
    },
    'remote get-url --push origin': {
      status: 0,
      stdout: 'git@github.com:acme/web.git\n',
    },
    ...overrides,
  };

  return (args) => {
    const answer = answers[args.join(' ')];

    return Promise.resolve({
      status: answer?.status ?? 1,
      stdout: answer?.stdout ?? '',
      stderr: answer?.stderr ?? `fatal: unexpected git ${args.join(' ')}`,
    });
  };
}

/** The keychain as an in-memory store, with `key` in it or none. */
function store(key?: string, loads?: { count: number }): SdkCredentialStore {
  return {
    load: () => {
      if (loads !== undefined) {
        loads.count += 1;
      }

      return Promise.resolve(
        key === undefined
          ? undefined
          : {
              version: 1,
              backendUrl: 'https://api2.cursor.sh',
              apiKey: key,
              createdAtMs: 0,
            },
      );
    },
    save: () => Promise.resolve(),
    clear: () => Promise.resolve(),
  };
}

const open: ClientConnection[] = [];

afterEach(() => {
  for (const each of open.splice(0)) {
    each.close();
  }
});

/** The adapter on fakes, a client on the other end recording every message in order. */
function connect(
  options: {
    git?: Git;
    store?: SdkCredentialStore;
    env?: Record<string, string | undefined>;
  } = {},
) {
  const cursor = fakeCursor();
  const toAgent = new TransformStream<Uint8Array, Uint8Array>();
  const toClient = new TransformStream<Uint8Array, Uint8Array>();
  const seen: (
    | { readonly kind: 'update'; readonly params: SessionNotification }
    | { readonly kind: 'answer'; readonly method: string }
  )[] = [];

  serve(ndJsonStream(toClient.writable, toAgent.readable), {
    port: cursor.port,
    git: options.git ?? fakeGit(),
    credentials: () => ({
      env: options.env ?? {},
      store: options.store ?? store('key_good'),
      now: () => 0,
    }),
    version: '0.1.0',
  });

  const connection = client({ name: 'test' })
    .onNotification('session/update', ({ params }) => {
      seen.push({ kind: 'update', params });
    })
    .connect(ndJsonStream(toAgent.writable, toClient.readable));

  open.push(connection);

  const request = async <T>(method: string, params: unknown): Promise<T> => {
    const answer = (await connection.agent.request(method, params)) as T;

    seen.push({ kind: 'answer', method });

    return answer;
  };

  const texts = (sessionId?: string) =>
    seen.flatMap((each) =>
      each.kind === 'update' &&
      (sessionId === undefined || each.params.sessionId === sessionId) &&
      each.params.update.sessionUpdate === 'agent_message_chunk' &&
      each.params.update.content.type === 'text'
        ? [each.params.update.content.text]
        : [],
    );

  return { cursor, connection, seen, request, texts };
}

const newSession = (
  at: ReturnType<typeof connect>,
  mcpServers: unknown[] = [],
) =>
  at.request<{ sessionId: string; configOptions: { id: string }[] }>(
    'session/new',
    { cwd: CWD, mcpServers },
  );

const refusal = async (promise: Promise<unknown>) => {
  const error = (await promise.catch((caught: unknown) => caught)) as {
    code: number;
    message: string;
    data?: unknown;
  };

  return { code: error.code, message: error.message };
};

describe('initialize', () => {
  test('names the package, its one sign-in and what it serves', async () => {
    const at = connect();

    expect(
      await at.request('initialize', {
        protocolVersion: 1,
        clientCapabilities: {},
      }),
    ).toEqual({
      protocolVersion: 1,
      agentInfo: {
        name: '@chorded/cursor-cloud-acp',
        title: 'Cursor Cloud Agents',
        version: '0.1.0',
      },
      authMethods: [
        {
          id: 'cursor-login',
          name: 'Cursor login',
          description:
            'Run `npx -y @chorded/cursor-cloud-acp@0.1.0 login` in a terminal, or set CURSOR_API_KEY',
        },
      ],
      agentCapabilities: {
        loadSession: true,
        promptCapabilities: { image: true, embeddedContext: false },
        mcpCapabilities: { http: false, sse: false },
        sessionCapabilities: { list: {}, resume: {}, close: {} },
      },
      _meta: { steering: { supported: false } },
    });
  });

  test('authenticate is refused, naming the login command', async () => {
    const at = connect();

    await at.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: {},
    });
    expect(
      await refusal(at.request('authenticate', { methodId: 'cursor-login' })),
    ).toEqual({
      code: -32602,
      message:
        'Sign in with `npx -y @chorded/cursor-cloud-acp@0.1.0 login` in a terminal, or set CURSOR_API_KEY.',
    });
  });
});

describe('session/new', () => {
  const ready = async (options?: Parameters<typeof connect>[0]) => {
    const at = connect(options);

    await at.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: {},
    });

    return at;
  };

  test('creates the cloud agent from the pushed branch, answers with its id and options', async () => {
    const at = await ready();
    const answer = await newSession(at);

    expect(answer.sessionId).toBe('bc-1');
    expect(answer.configOptions.map((each) => each.id)).toEqual([
      'mode',
      'model',
    ]);
    expect(
      at.cursor.calls.find((each) => each.method === 'create')?.args,
    ).toEqual({
      apiKey: 'key_good',
      mode: 'agent',
      cloud: {
        repos: [
          { url: 'https://github.com/acme/web', startingRef: 'login-page' },
        ],
        workOnCurrentBranch: false,
        autoCreatePR: false,
      },
    });
  });

  test('the first message comes before the answer, and before an immediate prompt', async () => {
    const at = await ready();
    const answer = newSession(at);
    const { sessionId } = await answer;

    await at.request('session/prompt', {
      sessionId,
      prompt: [{ type: 'text', text: 'hi' }],
    });

    const order = at.seen.map((each) =>
      each.kind === 'answer'
        ? each.method
        : each.params.update.sessionUpdate === 'agent_message_chunk' &&
            each.params.update.content.type === 'text'
          ? each.params.update.content.text
          : each.params.update.sessionUpdate,
    );

    expect(order).toEqual([
      'initialize',
      `Cursor cloud agent on github.com/acme/web, starting from branch login-page on origin. It runs in Cursor's cloud, not on this machine, pushes its work to a branch of its own, and keeps running if chord closes.  \n${LINK('bc-1')}`,
      'session/new',
      'ok',
      'session/prompt',
    ]);
  });

  test('MCP servers given anyway are named unreachable', async () => {
    const at = await ready();

    await newSession(at, [
      { name: 'files', command: 'files-mcp', args: [], env: [] },
    ]);
    expect(at.texts()[0]).toContain(
      "The MCP servers files given to this session are not reachable from Cursor's cloud.",
    );
  });

  test.each([
    [
      'outside a work tree',
      {
        'rev-parse --is-inside-work-tree': {
          status: 128,
          stderr: 'fatal: not a git repository',
        },
      },
      `${CWD} is not in a git work tree. A cloud agent starts from a pushed branch: start chord in a repository, then start again.`,
    ],
    [
      'a detached HEAD',
      { 'symbolic-ref --quiet --short HEAD': { status: 1 } },
      'HEAD is detached. A cloud agent starts from a pushed branch: run git switch <branch>, then start again.',
    ],
    [
      'no remote',
      {
        'for-each-ref --format=%(push:remotename) refs/heads/login-page': {
          status: 0,
        },
        remote: { status: 0 },
      },
      'Branch login-page has no remote to push to. A cloud agent starts from a pushed branch: run git remote add origin <url> and git push -u origin login-page, then start again.',
    ],
    [
      'not pushed',
      {
        'merge-base --is-ancestor HEAD refs/remotes/origin/login-page': {
          status: 1,
        },
      },
      'Branch login-page is not pushed to origin. A cloud agent starts from a pushed branch: run git push -u origin login-page, then start again.',
    ],
  ])(
    '%s: refused -32602 before any key or Cursor call',
    async (_, git, message) => {
      const loads = { count: 0 };
      const at = await ready({
        git: fakeGit(git),
        store: store('key_good', loads),
      });

      expect(await refusal(newSession(at))).toEqual({ code: -32602, message });
      expect(loads.count).toBe(0);
      expect(at.cursor.calls).toEqual([]);
    },
  );

  test('signed out: authRequired, and Cursor is not asked', async () => {
    const at = await ready({ store: store() });

    expect(await refusal(newSession(at))).toEqual({
      code: -32000,
      message: 'Not signed in to Cursor.',
    });
    expect(at.cursor.calls).toEqual([]);
  });

  test("a key Cursor refuses: authRequired with the SDK's words", async () => {
    const at = await ready({ store: store('key_other_backend') });

    expect(await refusal(newSession(at))).toEqual({
      code: -32000,
      message: 'Invalid API key',
    });
  });

  test('a keychain that does not answer refuses naming the keychain', async () => {
    const at = await ready({
      store: {
        ...store(),
        load: () =>
          Promise.reject(
            new KeychainError('The keychain did not answer within 10 s.'),
          ),
      },
    });

    expect(await refusal(newSession(at))).toEqual({
      code: -32603,
      message: 'The keychain did not answer within 10 s.',
    });
  });

  test('CURSOR_API_KEY over the keychain, passed as apiKey to every call', async () => {
    const at = await ready({
      env: { CURSOR_API_KEY: 'key_env' },
      store: store('key_good'),
    });

    at.cursor.keys.add('key_env');
    await newSession(at);
    expect(
      at.cursor.calls
        .filter((each) => each.method !== 'send')
        .map((each) => each.apiKey),
    ).toEqual(['key_env', 'key_env', 'key_env']);
  });
});

describe('session/prompt', () => {
  const started = async () => {
    const at = connect();

    await at.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: {},
    });

    const { sessionId } = await newSession(at);

    return { at, sessionId };
  };

  const prompt = (
    at: ReturnType<typeof connect>,
    sessionId: string,
    text = 'add a login page',
  ) =>
    at.request<{ stopReason: string; usage?: unknown }>('session/prompt', {
      sessionId,
      prompt: [
        { type: 'text', text },
        { type: 'image', data: 'aGk=', mimeType: 'image/png' },
      ],
    });

  test('streams the run and ends the turn with its usage; mode sent on every send', async () => {
    const { at, sessionId } = await started();

    at.cursor.scripts.push({
      deltas: [
        { type: 'thinking-delta', text: 'Routes first' },
        {
          type: 'tool-call-started',
          callId: 'c1',
          modelCallId: 'm1',
          toolCall: { type: 'read', args: { path: 'src/routes.ts' } } as never,
        },
        { type: 'text-delta', text: 'Done.' },
      ],
      result: {
        usage: {
          inputTokens: 1,
          outputTokens: 2,
          cacheReadTokens: 0,
          cacheWriteTokens: 0,
          totalTokens: 3,
        },
      },
    });

    expect(await prompt(at, sessionId)).toEqual({
      stopReason: 'end_turn',
      usage: {
        totalTokens: 3,
        inputTokens: 1,
        outputTokens: 2,
        cachedReadTokens: 0,
        cachedWriteTokens: 0,
      },
    });
    expect(
      at.seen.flatMap((each) =>
        each.kind === 'update' ? [each.params.update.sessionUpdate] : [],
      ),
    ).toEqual([
      'agent_message_chunk',
      'agent_thought_chunk',
      'tool_call',
      'agent_message_chunk',
    ]);

    const sent = at.cursor.calls.find((each) => each.method === 'send')
      ?.args as {
      message: unknown;
      options: { mode: string; idempotencyKey: string };
    };

    expect(sent.message).toEqual({
      text: 'add a login page',
      images: [{ data: 'aGk=', mimeType: 'image/png' }],
    });
    expect(sent.options.mode).toBe('agent');
    expect(sent.options.idempotencyKey).toBeString();
  });

  test('a cancel stops the run and the turn answers cancelled', async () => {
    const { at, sessionId } = await started();

    at.cursor.scripts.push({ hang: true });

    const answer = prompt(at, sessionId);

    await new Promise((resolve) => setTimeout(resolve, 20));
    await at.connection.agent.notify('session/cancel', { sessionId });
    expect(await answer).toEqual({ stopReason: 'cancelled' });
    expect(at.cursor.runs.get(sessionId)?.[0]?.cancelled).toBe(true);
  });

  test("a refused send fails the turn with the SDK's message and its data", async () => {
    const { at, sessionId } = await started();

    at.cursor.scripts.push({
      refuse: new CursorError('busy', 'Agent has an active run', {
        sdkClass: 'AgentBusyError',
      }),
    });

    const error = (await prompt(at, sessionId).catch(
      (caught: unknown) => caught,
    )) as {
      code: number;
      message: string;
      data: unknown;
    };

    expect(error).toMatchObject({
      code: -32603,
      message: `Agent has an active run\n${LINK(sessionId)}`,
      data: { class: 'AgentBusyError' },
    });
  });

  test('a prompt for a session not open is refused', async () => {
    const at = connect();

    await at.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: {},
    });
    expect((await refusal(prompt(at, 'bc-9'))).code).toBe(-32002);
  });
});

describe('config options', () => {
  test('a mode is sent from the next send; a model change sends the whole set again', async () => {
    const at = connect();

    await at.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: {},
    });
    at.cursor.models.push({
      id: 'gpt-5',
      displayName: 'GPT-5',
      parameters: [
        { id: 'reasoning', values: [{ value: 'low' }, { value: 'high' }] },
      ],
      variants: [
        {
          displayName: 'GPT-5',
          isDefault: true,
          params: [{ id: 'reasoning', value: 'high' }],
        },
        {
          displayName: 'GPT-5 Low',
          params: [{ id: 'reasoning', value: 'low' }],
        },
      ],
    });

    const { sessionId } = await newSession(at);

    await at.request('session/set_config_option', {
      sessionId,
      configId: 'mode',
      value: 'plan',
    });

    const changed = await at.request<{
      configOptions: { id: string; currentValue: string }[];
    }>('session/set_config_option', {
      sessionId,
      configId: 'model',
      value: 'gpt-5',
    });

    expect(
      changed.configOptions.map((each) => [each.id, each.currentValue]),
    ).toEqual([
      ['mode', 'plan'],
      ['model', 'gpt-5'],
      ['parameter:reasoning', 'high'],
    ]);
    await at.request('session/prompt', {
      sessionId,
      prompt: [{ type: 'text', text: 'go' }],
    });
    expect(
      (
        at.cursor.calls.find((each) => each.method === 'send')?.args as {
          options: unknown;
        }
      ).options,
    ).toMatchObject({
      mode: 'plan',
      model: { id: 'gpt-5', params: [{ id: 'reasoning', value: 'high' }] },
    });

    // Once sent, Cursor's default has no way back.
    const after = await at.request<{
      configOptions: { id: string; options: { value: string }[] }[];
    }>('session/set_config_option', {
      sessionId,
      configId: 'mode',
      value: 'default',
    });

    expect(after.configOptions[1]?.options.map((each) => each.value)).toEqual([
      'composer-2',
      'gpt-5',
    ]);
    expect(
      (
        await refusal(
          at.request('session/set_config_option', {
            sessionId,
            configId: 'model',
            value: 'cursor-default',
          }),
        )
      ).code,
    ).toBe(-32602);
  });
});

describe('list, resume, load, close', () => {
  const withHistory = async () => {
    const at = connect();

    await at.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: {},
    });

    const { sessionId } = await newSession(at);

    at.cursor.scripts.push({
      result: {
        git: {
          branches: [
            {
              repoUrl: 'https://github.com/acme/web',
              branch: 'cursor/login-page-5e1f',
            },
          ],
        },
      },
    });
    await at.request('session/prompt', {
      sessionId,
      prompt: [{ type: 'text', text: 'one' }],
    });
    at.cursor.scripts.push({
      result: {
        git: {
          branches: [
            {
              repoUrl: 'https://github.com/acme/web',
              branch: 'cursor/login-page-5e1f',
            },
          ],
        },
      },
    });
    await at.request('session/prompt', {
      sessionId,
      prompt: [{ type: 'text', text: 'two' }],
    });

    return { at, sessionId };
  };

  test("list: the account's cloud agents for the cwd's repository, archived left out", async () => {
    const { at, sessionId } = await withHistory();

    at.cursor.listed.push(
      {
        agentId: 'bc-other',
        name: 'Elsewhere',
        summary: '',
        lastModified: 0,
        runtime: 'cloud',
        repos: ['https://github.com/acme/api'],
      },
      {
        agentId: 'bc-old',
        name: 'Old',
        summary: '',
        lastModified: 0,
        runtime: 'cloud',
        archived: true,
        repos: ['git@github.com:acme/web.git'],
      },
      {
        agentId: 'bc-web',
        name: 'From the web',
        summary: '',
        lastModified: 0,
        runtime: 'cloud',
        repos: ['git@github.com:acme/web.git'],
      },
    );

    const listed = await at.request<{
      sessions: { sessionId: string; title: string; cwd: string }[];
    }>('session/list', { cwd: CWD });

    expect(listed.sessions.map((each) => each.sessionId)).toEqual([
      sessionId,
      'bc-web',
    ]);
    expect(listed.sessions[1]).toMatchObject({
      title: 'From the web',
      cwd: CWD,
    });
  });

  test('resume: answers, then the first message with the latest run', async () => {
    const { at, sessionId } = await withHistory();
    const before = at.texts().length;

    await at.request('session/resume', { sessionId, cwd: CWD });
    expect(at.texts().slice(before)).toEqual([
      `Cursor cloud agent on github.com/acme/web. Its last run finished: pushed to cursor/login-page-5e1f.  \n${LINK(sessionId)}`,
    ]);
  });

  test('load: each run replayed oldest first, then the first message, then the answer', async () => {
    const { at, sessionId } = await withHistory();
    const runs = at.cursor.runs.get(sessionId)!;
    const before = at.seen.length;

    await at.request('session/load', { sessionId, cwd: CWD, mcpServers: [] });

    const after = at.seen
      .slice(before)
      .map((each) =>
        each.kind === 'answer'
          ? each.method
          : (each.params.update.sessionUpdate === 'agent_message_chunk' ||
                each.params.update.sessionUpdate === 'user_message_chunk') &&
              each.params.update.content.type === 'text'
            ? `${each.params.update.sessionUpdate}: ${each.params.update.content.text.split('\n')[0]}`
            : each.params.update.sessionUpdate,
      );

    expect(after).toEqual([
      `user_message_chunk: asked ${runs[0]!.id}`,
      `agent_message_chunk: answered ${runs[0]!.id}`,
      `user_message_chunk: asked ${runs[1]!.id}`,
      `agent_message_chunk: answered ${runs[1]!.id}`,
      'agent_message_chunk: Cursor cloud agent on github.com/acme/web. Its last run finished: pushed to cursor/login-page-5e1f.  ',
      'session/load',
    ]);
  });

  test('resume, load and list of an agent Cursor does not know: -32002', async () => {
    const at = connect();

    await at.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: {},
    });

    // Created, never prompted: Cursor makes the agent at the first send.
    const { sessionId } = await newSession(at);

    expect(
      await refusal(at.request('session/resume', { sessionId, cwd: CWD })),
    ).toEqual({
      code: -32002,
      message: `Agent ${sessionId} not found`,
    });
    expect(
      (
        await refusal(
          at.request('session/load', { sessionId, cwd: CWD, mcpServers: [] }),
        )
      ).code,
    ).toBe(-32002);
  });

  test('close closes the adapter’s hold; the cloud agent goes on', async () => {
    const { at, sessionId } = await withHistory();

    await at.request('session/close', { sessionId });
    expect(at.cursor.closed).toEqual([sessionId]);
    expect(
      at.cursor.runs.get(sessionId)?.every((each) => !each.cancelled),
    ).toBe(true);
  });
});

describe('the fixture over real pipes', () => {
  /** The QA route's agent command, as the guide gives it (CHD-622). */
  const QA_COMMAND = 'bun packages/cursor-cloud-acp/tests/fixtures/main.ts';
  const root = fileURLToPath(new URL('../../..', import.meta.url));

  test('the QA argv serves: stdout only JSON-RPC, exit within 1.5 s of stdin ending', async () => {
    const [, script] = QA_COMMAND.split(' ');
    const child = spawn(process.execPath, [script!], {
      cwd: root,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, CURSOR_CLOUD_QA: '' },
    });
    let stdout = '';
    const answers = new Map<number, unknown>();
    const waiters = new Map<number, () => void>();

    child.stdout.setEncoding('utf8').on('data', (chunk: string) => {
      stdout += chunk;

      for (const each of stdout.split('\n').slice(0, -1)) {
        const message = JSON.parse(each) as { id?: number };

        if (message.id !== undefined && !answers.has(message.id)) {
          answers.set(message.id, message);
          waiters.get(message.id)?.();
        }
      }
    });

    const ask = (id: number, method: string, params: unknown) =>
      new Promise<unknown>((resolve) => {
        waiters.set(id, () => resolve(answers.get(id)));
        child.stdin.write(
          `${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`,
        );
      });

    await ask(1, 'initialize', { protocolVersion: 1, clientCapabilities: {} });

    const created = (await ask(2, 'session/new', {
      cwd: root,
      mcpServers: [],
    })) as { result: { sessionId: string } };

    await ask(3, 'session/prompt', {
      sessionId: created.result.sessionId,
      prompt: [{ type: 'text', text: 'tool please' }],
    });

    const exited = once(child, 'exit');
    const ended = performance.now();

    child.stdin.end();
    await exited;
    expect(performance.now() - ended).toBeLessThan(1500);

    const lines = stdout.split('\n').filter((each) => each !== '');

    expect(lines.length).toBeGreaterThan(5);

    for (const each of lines) {
      expect(JSON.parse(each)).toMatchObject({ jsonrpc: '2.0' });
    }

    expect(stdout).toContain('"title":"src/routes.ts"');
    expect(child.exitCode).toBe(0);
  }, 20_000);
});
