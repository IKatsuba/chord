/**
 * The adapter on Bun over a scripted Cursor, for chord's `--qa` runs and the
 * package's tests (CHD-622, "--fake and tests"): serve.ts with the fake
 * Port, a fake git and a fake key, so a `--qa` directory need not be a
 * repository and nothing reaches Cursor, a keychain or the network.
 *
 *   bun dev chord --qa <name> cursor-cloud --agent-command "bun packages/cursor-cloud-acp/tests/fixtures/main.ts"
 *
 * `CURSOR_CLOUD_QA` picks how a start goes: `signed-out`, `key-refused`,
 * `outside`, `detached`, `no-remote`, `not-pushed`; unset, it starts. A
 * prompt's first word picks its run: `think`, `tool`, `plan`, `request`,
 * `hang` (until Esc), `fail`, `busy`, `lost`; any other is answered `ok`.
 * Words later in a prompt never pick one. One earlier agent, `EARLIER`,
 * can be resumed by id.
 */
import type { InteractionUpdate, ToolCall } from '@cursor/sdk';
import { CursorError } from '../../src/errors.ts';
import type { Git, GitResult } from '../../src/repo.ts';
import { serveStdio } from '../../src/serve.ts';
import { fakeCursor, fakeRun, type Script } from './fake_port.ts';

const START = process.env.CURSOR_CLOUD_QA ?? '';

/** git in a pushed repository, or in the start the scenario names. */
const git: Git = (args) => {
  const asked = args.join(' ');
  const answer = (
    status: number,
    stdout = '',
    stderr = '',
  ): Promise<GitResult> => Promise.resolve({ status, stdout, stderr });

  switch (asked) {
    case 'rev-parse --is-inside-work-tree':
      return START === 'outside'
        ? answer(128, '', 'fatal: not a git repository')
        : answer(0, 'true\n');
    case 'symbolic-ref --quiet --short HEAD':
      return START === 'detached' ? answer(1) : answer(0, 'login-page\n');
    case 'for-each-ref --format=%(push:remotename) refs/heads/login-page':
      return answer(0, START === 'no-remote' ? '' : 'origin\n');
    case 'remote':
      return answer(0, START === 'no-remote' ? '' : 'origin\n');
    case 'rev-parse --verify --quiet refs/remotes/origin/login-page':
      return START === 'not-pushed' ? answer(1) : answer(0, 'abc\n');
    case 'merge-base --is-ancestor HEAD refs/remotes/origin/login-page':
      return answer(0);
    case 'remote get-url --push origin':
      return answer(0, 'git@github.com:acme/web.git\n');
    default:
      return answer(1, '', `fatal: the fixture has no answer for git ${asked}`);
  }
};

/** A tool call started, then done with `value` as its own output. */
const tool = (
  callId: string,
  toolCall: object,
  value: unknown,
): InteractionUpdate[] => [
  {
    type: 'tool-call-started',
    callId,
    modelCallId: callId,
    toolCall: toolCall as ToolCall,
  },
  {
    type: 'tool-call-completed',
    callId,
    modelCallId: callId,
    toolCall: {
      ...toolCall,
      result: { status: 'success', value },
    } as ToolCall,
  },
];

/** `text` as the SDK streams it, a word at a time. */
const words = (text: string) =>
  text
    .split(/(?<= )/)
    .map((piece): InteractionUpdate => ({ type: 'text-delta', text: piece }));

/** A run for a prompt, by its first word. */
function scriptFor(text: string): Script | undefined {
  const base = { agent_id: 'bc-qa', run_id: 'run-qa' } as const;

  switch (text.trim().split(/\s+/)[0]) {
    case 'think':
      return {
        deltas: [
          {
            type: 'thinking-delta',
            text: 'Looking at how routes are laid out…',
          },
          ...words('The login page goes in src/pages/Login.tsx.'),
        ],
      };
    case 'tool':
      return {
        messages: [{ ...base, type: 'status', status: 'CREATING' }],
        deltas: [
          ...tool(
            'c1',
            { type: 'read', args: { path: 'src/routes.ts' } },
            { totalLines: 84 },
          ),
          ...tool(
            'c2',
            { type: 'semSearch', args: { query: 'form validation' } },
            {
              query: 'form validation',
              results: ['src/forms/validate.ts', 'src/forms/Field.tsx'],
            },
          ),
          ...tool(
            'c3',
            { type: 'shell', args: { command: 'npm test' } },
            {
              exitCode: 0,
              signal: '',
              stderr: '',
              executionTime: 6200,
              stdout: [
                ...Array.from({ length: 38 }, (_, at) => `✓ test ${at + 1}`),
                ' Tests  41 passed (41)',
                ' Time   6.2s',
              ].join('\n'),
            },
          ),
          ...words(
            'The login page is in src/pages/Login.tsx; its tests pass in the cloud VM.',
          ),
        ],
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
      };
    case 'plan':
      return {
        deltas: tool(
          'c4',
          {
            type: 'updateTodos',
            args: {
              todos: [
                { content: 'Read the routes', status: 'completed' },
                { content: 'Write the page', status: 'inProgress' },
                { content: 'Test it', status: 'pending' },
              ],
            },
          },
          { todos: 3 },
        ),
      };
    case 'request':
      return {
        messages: [{ ...base, type: 'request', request_id: 'r-81c2' }],
        hang: true,
      };
    case 'lost':
      return { deltas: words('Starting…'), lose: true };
    case 'hang':
      return { deltas: words('Working on it…'), hang: true };
    case 'fail':
      return {
        result: {
          status: 'error',
          error: { message: 'The VM ran out of disk' },
        },
      };
    case 'busy':
      return {
        refuse: new CursorError(
          'busy',
          'Agent bc-1 already has an active run.',
          {
            sdkClass: 'AgentBusyError',
          },
        ),
      };
    default:
      return undefined;
  }
}

const cursor = fakeCursor(scriptFor);

/**
 * An agent started earlier, on cursor.com or another machine, so
 * `--resume` has one to reopen in a fresh fixture: its last run finished,
 * pushed to a branch of its own.
 */
export const EARLIER = 'bc-5e1f0a7c-2d4b-4e8a-9c1f-7b2e6d3a9f10';

cursor.listed.push({
  agentId: EARLIER,
  name: 'Add login page',
  summary: '',
  lastModified: Date.now() - 3 * 3600 * 1000,
  runtime: 'cloud',
  repos: ['https://github.com/acme/web'],
});
cursor.runs.set(EARLIER, [
  fakeRun(
    EARLIER,
    {
      // The design's resume mock: the person's prompt and the agent's answer.
      conversation: [
        {
          type: 'agentConversationTurn',
          turn: {
            userMessage: {
              text: 'add a login page with email and password, tests included',
            },
            steps: [
              {
                type: 'assistantMessage',
                message: {
                  text: 'The login page is in src/pages/Login.tsx with its route in src/routes.ts; its tests pass in the cloud VM.',
                },
              },
            ],
          },
        },
      ],
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
    },
    undefined,
    Date.now() - 3 * 3600 * 1000,
  ),
]);

if (START === 'key-refused') {
  cursor.keys.clear();
}

process.exitCode = await serveStdio({
  port: cursor.port,
  git,
  credentials: () => ({
    env: {},
    store: {
      load: () =>
        Promise.resolve(
          START === 'signed-out'
            ? undefined
            : {
                version: 1,
                backendUrl: 'https://api2.cursor.sh',
                apiKey: 'key_good',
                createdAtMs: 0,
              },
        ),
      save: () => Promise.resolve(),
      clear: () => Promise.resolve(),
    },
    now: Date.now,
  }),
  version: '0.1.0',
});

process.exit();
