import { describe, expect, test } from 'bun:test';
import type {
  ConversationTurn,
  InteractionUpdate,
  SDKMessage,
  ToolCall,
} from '@cursor/sdk';
import {
  Drawing,
  firstMessage,
  line,
  noConversation,
  plan,
  replay,
  requestLine,
  resumedMessage,
  runEnd,
  shellContent,
  STARTING,
  toolKind,
  toolStatus,
  toolTitle,
  unconfirmedStop,
  usage,
} from '../src/updates.ts';

const ID = 'bc-5e1f0a7c-2d4b-4e8a-9c1f-7b2e6d3a9f10';
const LINK = `https://cursor.com/agents/${ID}`;

describe('tool rows', () => {
  test.each([
    ['shell', 'execute'],
    ['read', 'read'],
    ['edit', 'edit'],
    ['write', 'edit'],
    ['delete', 'delete'],
    ['grep', 'search'],
    ['glob', 'search'],
    ['ls', 'search'],
    ['semSearch', 'search'],
    ['webFetch', 'fetch'],
    ['mcp', 'other'],
    ['updateTodos', 'other'],
    ['somethingLater', 'other'],
  ] as const)('%s is %s', (name, kind) => {
    expect(toolKind(name)).toBe(kind);
  });

  test("a title is the one field the SDK's type names when a non-empty string, else the name", () => {
    expect(
      [
        { type: 'shell', args: { command: 'npm test' } },
        { type: 'read', args: { path: 'src/routes.ts' } },
        { type: 'grep', args: { pattern: 'login' } },
        { type: 'glob', args: { globPattern: '**/*.tsx' } },
        { type: 'task', args: { description: 'Check the forms' } },
        { type: 'semSearch', args: { query: 'form validation' } },
        { type: 'shell', args: { command: 42 } },
        { type: 'read', args: { path: '' } },
        { type: 'read' },
        { type: 'somethingLater', args: { path: 'x' } },
      ].map(toolTitle),
    ).toEqual([
      'npm test',
      'src/routes.ts',
      'login',
      '**/*.tsx',
      'Check the forms',
      'semSearch',
      'shell',
      'read',
      'read',
      'somethingLater',
    ]);
  });

  test("a row fails when the SDK's result says error, else completes", () => {
    expect(
      toolStatus({ type: 'shell', result: { status: 'error', error: 'x' } }),
    ).toBe('failed');
    expect(toolStatus({ type: 'shell', result: { status: 'success' } })).toBe(
      'completed',
    );
    expect(toolStatus({ type: 'shell' })).toBe('completed');
  });
});

test('updateTodos gives a plan, cancelled todos left out, each priority medium', () => {
  expect(
    plan({
      type: 'updateTodos',
      args: {
        todos: [
          { content: 'Read the routes', status: 'completed' },
          { content: 'Write the page', status: 'inProgress' },
          { content: 'Test it', status: 'pending' },
          { content: 'Dark mode', status: 'cancelled' },
          { content: 7, status: 'pending' },
        ],
      },
    }),
  ).toEqual({
    sessionUpdate: 'plan',
    entries: [
      { content: 'Read the routes', priority: 'medium', status: 'completed' },
      { content: 'Write the page', priority: 'medium', status: 'in_progress' },
      { content: 'Test it', priority: 'medium', status: 'pending' },
    ],
  });
  expect(plan({ type: 'shell', args: { command: 'ls' } })).toBeUndefined();
  expect(plan({ type: 'updateTodos', args: {} })).toBeUndefined();
});

test("usage: the SDK's tokens as ACP's, reasoning only when given", () => {
  const tokens = {
    inputTokens: 10,
    outputTokens: 20,
    cacheReadTokens: 3,
    cacheWriteTokens: 4,
    totalTokens: 37,
  };

  expect(usage(tokens)).toEqual({
    totalTokens: 37,
    inputTokens: 10,
    outputTokens: 20,
    cachedReadTokens: 3,
    cachedWriteTokens: 4,
  });
  expect(usage({ ...tokens, reasoningTokens: 5 }).thoughtTokens).toBe(5);
});

test('every adapter line is an agent message with an id of its own', () => {
  const [a, b] = [line('one'), line('two')];

  expect(a).toMatchObject({
    sessionUpdate: 'agent_message_chunk',
    content: { type: 'text', text: 'one' },
  });
  expect((a as { messageId: string }).messageId).toBeString();
  expect((a as { messageId: string }).messageId).not.toBe(
    (b as { messageId: string }).messageId,
  );
});

describe("the design's words", () => {
  test('the first message', () => {
    expect(
      firstMessage({
        url: 'https://github.com/acme/web',
        branch: 'login-page',
        remote: 'origin',
        agentId: ID,
        mcpServers: [],
      }),
    ).toBe(
      `Cursor cloud agent on github.com/acme/web, starting from branch login-page on origin. It runs in Cursor's cloud, not on this machine, pushes its work to a branch of its own, and keeps running if chord closes.  \n${LINK}`,
    );
  });

  test('the first message names MCP servers given anyway (Q5)', () => {
    expect(
      firstMessage({
        url: 'https://git.example.com/a/b.git',
        branch: 'main',
        remote: 'fork',
        agentId: ID,
        mcpServers: ['files', 'github'],
      }),
    ).toBe(
      `Cursor cloud agent on git.example.com/a/b.git, starting from branch main on fork. It runs in Cursor's cloud, not on this machine, pushes its work to a branch of its own, and keeps running if chord closes. The MCP servers files, github given to this session are not reachable from Cursor's cloud.  \n${LINK}`,
    );
  });

  test('CREATING, a request, an unconfirmed stop', () => {
    expect(STARTING).toBe("Cursor is starting the agent's machine…");
    expect(requestLine('r-81c2', ID)).toBe(
      `Cursor's agent is waiting for input or approval (request r-81c2). This adapter cannot answer it; Esc stops the run.  \n${LINK}`,
    );
    expect(unconfirmedStop(ID)).toBe(
      `Cursor did not confirm the stop; the run may still be going: ${LINK}`,
    );
  });
});

describe("a resumed session's first message", () => {
  const url = 'https://github.com/acme/web';
  const say = (
    last: Parameters<typeof resumedMessage>[0]['last'],
    options: { url?: string; mcpServers?: string[] } = { url },
  ) =>
    resumedMessage({
      url: options.url,
      agentId: ID,
      last,
      mcpServers: options.mcpServers ?? [],
    });

  test.each([
    [
      { status: 'finished', branch: 'cursor/login-page-5e1f' },
      'Its last run finished: pushed to cursor/login-page-5e1f.',
    ],
    [{ status: 'finished' }, 'Its last run finished.'],
    [
      { status: 'running' },
      'Its last run is still going; a prompt is refused until it ends.',
    ],
    [
      { status: 'error', error: 'The VM ran out of disk' },
      'Its last run failed: The VM ran out of disk.',
    ],
    [
      { status: 'error', error: 'The VM ran out of disk!' },
      'Its last run failed: The VM ran out of disk!',
    ],
    [{ status: 'error' }, 'Its last run failed.'],
    [{ status: 'cancelled' }, 'Its last run was cancelled.'],
    [undefined, 'It has no runs yet.'],
  ] as const)('%p', (last, state) => {
    expect(say(last)).toBe(
      `Cursor cloud agent on github.com/acme/web. ${state}  \n${LINK}`,
    );
  });

  test('without a repository, and with MCP servers', () => {
    expect(say(undefined, { mcpServers: ['files'] })).toBe(
      `Cursor cloud agent. It has no runs yet. The MCP servers files given to this session are not reachable from Cursor's cloud.  \n${LINK}`,
    );
  });
});

test("a run that cannot give its conversation, with Cursor's reason when given", () => {
  expect(noConversation('Not available for this run')).toBe(
    "Cursor cannot give this run's conversation: Not available for this run.",
  );
  expect(noConversation('Expired.')).toBe(
    "Cursor cannot give this run's conversation: Expired.",
  );
  expect(noConversation(undefined)).toBe(
    "Cursor cannot give this run's conversation.",
  );
});

test("the run's end: each pushed branch with its pull request, then the artifacts", () => {
  expect(
    runEnd(
      {
        git: {
          branches: [
            {
              repoUrl: 'https://github.com/acme/web',
              branch: 'cursor/login-page-5e1f',
            },
            {
              repoUrl: 'https://github.com/acme/api',
              branch: 'cursor/login-api',
              prUrl: 'https://github.com/acme/api/pull/7',
            },
            { repoUrl: 'https://github.com/acme/docs' },
          ],
        },
      },
      [{ path: 'screens/login.png' }, { path: 'report.md' }],
    ),
  ).toEqual([
    'Pushed to cursor/login-page-5e1f on github.com/acme/web.',
    'Pushed to cursor/login-api on github.com/acme/api. Pull request: https://github.com/acme/api/pull/7',
    'Artifacts in the cloud: screens/login.png, report.md.',
  ]);
  expect(runEnd({}, [])).toEqual([]);
});

describe('Drawing: the stream as updates', () => {
  const shell = {
    type: 'shell',
    args: { command: 'npm test' },
  } as const;

  test('text and thinking stream as chunks, one message id until something else is drawn', () => {
    const drawing = new Drawing(ID);
    const [a] = drawing.delta({ type: 'text-delta', text: 'Look' });
    const [b] = drawing.delta({ type: 'text-delta', text: 'ing' });
    const [thought] = drawing.delta({ type: 'thinking-delta', text: 'hm' });
    const [c] = drawing.delta({ type: 'text-delta', text: 'Done' });

    expect(a).toMatchObject({
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text: 'Look' },
    });
    expect(thought).toMatchObject({
      sessionUpdate: 'agent_thought_chunk',
      content: { type: 'text', text: 'hm' },
    });

    const id = (update: unknown) => (update as { messageId: string }).messageId;

    expect(id(a)).toBe(id(b));
    expect(id(c)).not.toBe(id(a));
    expect(id(thought)).not.toBe(id(a));
  });

  test('a tool call: started, its partial and delta, then completed or failed', () => {
    const drawing = new Drawing(ID);

    expect(
      drawing.delta({
        type: 'tool-call-started',
        callId: 'c1',
        modelCallId: 'm1',
        toolCall: shell,
      }),
    ).toEqual([
      {
        sessionUpdate: 'tool_call',
        toolCallId: 'c1',
        title: 'npm test',
        kind: 'execute',
        status: 'in_progress',
        rawInput: { command: 'npm test' },
      },
    ]);
    expect(
      drawing.delta({
        type: 'partial-tool-call',
        callId: 'c1',
        modelCallId: 'm1',
        toolCall: shell,
      }),
    ).toEqual([
      {
        sessionUpdate: 'tool_call_update',
        toolCallId: 'c1',
        title: 'npm test',
        kind: 'execute',
        rawInput: { command: 'npm test' },
      },
    ]);
    expect(
      drawing.delta({
        type: 'tool-call-delta',
        callId: 'c1',
        modelCallId: 'm1',
      } as unknown as InteractionUpdate),
    ).toEqual([{ sessionUpdate: 'tool_call_update', toolCallId: 'c1' }]);

    const result = { status: 'error', error: 'exit 1' };

    expect(
      drawing.delta({
        type: 'tool-call-completed',
        callId: 'c1',
        modelCallId: 'm1',
        toolCall: { ...shell, result } as unknown as ToolCall,
      }),
    ).toEqual([
      {
        sessionUpdate: 'tool_call_update',
        toolCallId: 'c1',
        status: 'failed',
        rawInput: { command: 'npm test' },
        rawOutput: result,
      },
    ]);
  });

  test('an updateTodos call also sends its plan', () => {
    const updates = new Drawing(ID).delta({
      type: 'tool-call-started',
      callId: 'c2',
      modelCallId: 'm2',
      toolCall: {
        type: 'updateTodos',
        args: { todos: [{ content: 'Test it', status: 'pending' }] },
      } as unknown as ToolCall,
    });

    expect(updates.map((each) => each.sessionUpdate)).toEqual([
      'tool_call',
      'plan',
    ]);
  });

  test('a tool the union does not know is an other row under its own name', () => {
    expect(
      new Drawing(ID).delta({
        type: 'tool-call-started',
        callId: 'c3',
        modelCallId: 'm3',
        toolCall: {
          type: 'webSearch',
          args: { q: 'x' },
        } as unknown as ToolCall,
      }),
    ).toMatchObject([{ title: 'webSearch', kind: 'other' }]);
  });

  test("kinds not drawn, and a later SDK's unknown kind, give nothing", () => {
    const drawing = new Drawing(ID);

    for (const type of [
      'shell-output-delta',
      'turn-ended',
      'step-started',
      'step-completed',
      'token-delta',
      'summary-started',
      'summary-completed',
      'thinking-completed',
      'user-message-appended',
      'something-later',
    ]) {
      expect(drawing.delta({ type } as unknown as InteractionUpdate)).toEqual(
        [],
      );
    }
  });

  test("the run's stream: CREATING, a terminal status's message, task text, a request", () => {
    const drawing = new Drawing(ID);
    const base = { agent_id: ID, run_id: 'r' } as const;
    const texts = (message: SDKMessage) =>
      drawing
        .message(message)
        .map((update) =>
          update.sessionUpdate === 'agent_message_chunk' &&
          update.content.type === 'text'
            ? update.content.text
            : update.sessionUpdate,
        );

    expect(texts({ ...base, type: 'status', status: 'CREATING' })).toEqual([
      "Cursor is starting the agent's machine…",
    ]);
    expect(texts({ ...base, type: 'status', status: 'RUNNING' })).toEqual([]);
    expect(
      texts({ ...base, type: 'status', status: 'ERROR', message: 'VM lost' }),
    ).toEqual(['VM lost']);
    expect(texts({ ...base, type: 'status', status: 'FINISHED' })).toEqual([]);
    expect(texts({ ...base, type: 'task', text: 'Planning' })).toEqual([
      'Planning',
    ]);
    expect(texts({ ...base, type: 'task' })).toEqual([]);
    expect(texts({ ...base, type: 'request', request_id: 'r-81c2' })).toEqual([
      `Cursor's agent is waiting for input or approval (request r-81c2). This adapter cannot answer it; Esc stops the run.  \n${LINK}`,
    ]);
    expect(
      texts({ ...base, type: 'assistant' } as unknown as SDKMessage),
    ).toEqual([]);
  });
});

test("replay: each turn's user message, then its steps as the live updates", () => {
  const updates = replay([
    {
      type: 'agentConversationTurn',
      turn: {
        userMessage: { text: 'add a login page' },
        steps: [
          { type: 'thinkingMessage', message: { text: 'Routes first' } },
          {
            type: 'toolCall',
            message: {
              type: 'read',
              args: { path: 'src/routes.ts' },
              result: { status: 'success', value: {} },
            } as unknown as ToolCall,
          },
          { type: 'assistantMessage', message: { text: 'Done.' } },
        ],
      },
    },
    { type: 'shellConversationTurn', turn: {} },
  ] as unknown as ConversationTurn[]);

  expect(updates).toMatchObject([
    {
      sessionUpdate: 'user_message_chunk',
      content: { type: 'text', text: 'add a login page' },
    },
    {
      sessionUpdate: 'agent_thought_chunk',
      content: { type: 'text', text: 'Routes first' },
    },
    {
      sessionUpdate: 'tool_call',
      title: 'src/routes.ts',
      kind: 'read',
      status: 'completed',
      rawInput: { path: 'src/routes.ts' },
    },
    {
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text: 'Done.' },
    },
  ]);
  expect(updates).toHaveLength(4);
});

describe('CHD-622 tester: unknown todo shapes', () => {
  test('null and non-object todos do not crash or invent plan entries', () => {
    expect(
      plan({
        type: 'updateTodos',
        args: {
          todos: [
            null,
            1,
            'later-shape',
            { content: 'Valid', status: 'pending' },
          ],
        },
      }),
    ).toEqual({
      sessionUpdate: 'plan',
      entries: [{ content: 'Valid', priority: 'medium', status: 'pending' }],
    });
  });

  test('unrecognized statuses, including object property names, are left out', () => {
    expect(
      plan({
        type: 'updateTodos',
        args: {
          todos: [
            'cancelled',
            'later-status',
            'toString',
            'constructor',
            '__proto__',
          ].map((status) => ({ content: 'Unknown', status })),
        },
      }),
    ).toEqual({ sessionUpdate: 'plan', entries: [] });
  });
});

describe("a shell's output as text the row draws by line (3b989b57)", () => {
  const shellDone = (result: unknown) =>
    ({
      type: 'shell',
      args: { command: 'npm test' },
      result,
    }) as unknown as ToolCall;
  const success = (stdout: string, stderr: string) => ({
    status: 'success',
    value: { exitCode: 0, signal: '', stdout, stderr, executionTime: 6200 },
  });

  test('stdout, then stderr, each a block; an empty one left out', () => {
    expect(
      shellContent(shellDone(success('Tests  41 passed (41)\n', 'warn: x'))),
    ).toEqual([
      {
        type: 'content',
        content: { type: 'text', text: 'Tests  41 passed (41)\n' },
      },
      { type: 'content', content: { type: 'text', text: 'warn: x' } },
    ]);
    expect(shellContent(shellDone(success('', 'only stderr')))).toEqual([
      { type: 'content', content: { type: 'text', text: 'only stderr' } },
    ]);
    expect(shellContent(shellDone(success('', '')))).toEqual([]);
  });

  test('a failed shell, any other tool, and an unknown result shape give none', () => {
    expect(
      shellContent(shellDone({ status: 'error', error: 'exit 1' })),
    ).toEqual([]);
    expect(
      shellContent({
        type: 'read',
        args: { path: 'a' },
        result: success('x', 'y'),
      } as unknown as ToolCall),
    ).toEqual([]);
    expect(
      shellContent(shellDone({ status: 'success', value: { stdout: 7 } })),
    ).toEqual([]);
    expect(shellContent(shellDone(undefined))).toEqual([]);
  });

  test("the completed row carries it beside rawOutput, as does a load's replay", () => {
    const call = shellDone(success('ok\n', ''));
    const [completed] = new Drawing(ID).delta({
      type: 'tool-call-completed',
      callId: 'c1',
      modelCallId: 'm1',
      toolCall: call,
    });

    expect(completed).toMatchObject({
      rawOutput: success('ok\n', ''),
      content: [{ type: 'content', content: { type: 'text', text: 'ok\n' } }],
    });
    expect(
      replay([
        {
          type: 'agentConversationTurn',
          turn: { steps: [{ type: 'toolCall', message: call }] },
        },
      ] as unknown as ConversationTurn[])[0],
    ).toMatchObject({
      content: [{ type: 'content', content: { type: 'text', text: 'ok\n' } }],
    });
  });
});
