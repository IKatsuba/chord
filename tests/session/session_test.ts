/**
 * A session on the fake agent: the tokens its turns report, its modes,
 * models and efforts, mentions, an agent that exits or never answers, its
 * close, the MCP servers it is given and Claude's prompt suggestions.
 */
import { execFile } from 'node:child_process';
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { chmod, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { findAgent } from '../../src/agents.ts';
import { startFailureOf } from '../../src/session/start_failure.ts';
import { signInOf, SignInNeeded } from '../../src/session/sign_in.ts';
import { FILLED, GUARDIAN_REVIEW } from '../../src/session/enrich.ts';
import { recordActions, type RecordEntry } from '../../src/session/record.ts';
import { pastActions } from '../../src/session/replay.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import { emptyTranscript } from '../../src/session/transcript/types.ts';
import type { PendingPermission } from '../../src/session/permissions.ts';
import {
  openSession,
  type Session,
  type Turn,
} from '../../src/session/session.ts';
import type { HeldBack } from '../../src/session/servers.ts';
import { readRecords, type Resume } from '../../src/session/sessions.ts';
import { FAKE_COMMANDS } from '../fixtures/commands.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { recordSession } from '../fixtures/records.ts';
import { CRASH_WORDS } from '../fixtures/fake_agent/scenarios/agents.ts';
import { mentionsIn } from '../../src/ui/prompt/mentions.ts';
import { run, said } from '../fixtures/recorder.ts';
import { isAlive, withSession, collect, calls } from './session_fake.ts';

test("each turn's answer carries its tokens, and usage_update the session's cost", () =>
  withSession(async (session) => {
    const turn = {
      inputTokens: 1000,
      outputTokens: 200,
      cachedReadTokens: 800,
      totalTokens: 2000,
    };
    const costs: unknown[] = [];

    for (const prompt of ['text', 'tools']) {
      const { updates, result } = await run(session, prompt);

      assert(result.status === 'completed');
      expect(result.usage).toStrictEqual(turn);
      costs.push(
        ...updates.flatMap((e) =>
          e.sessionUpdate === 'usage_update' ? [e.cost] : [],
        ),
      );
    }

    expect(costs).toStrictEqual([
      { amount: 0.0125, currency: 'USD' },
      { amount: 0.025, currency: 'USD' },
    ]);
  }));

const FAKE_MODES = [
  { id: 'default', name: 'Default' },
  { id: 'acceptEdits', name: 'Accept edits' },
  { id: 'plan', name: 'Plan' },
];

test("the agent's modes come in its order, with the one it starts in", () =>
  withSession(async (session) => {
    expect(await session.modes()).toStrictEqual({
      available: FAKE_MODES,
      current: 'default',
    });
  }));

test('the commands the agent advertises after the session starts are read', () =>
  withSession(async (session) => {
    const deadline = Date.now() + 5_000;
    let commands = await session.commands();

    // The agent sends them after its reply to session/new, as Claude's does.
    while (commands.length === 0 && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 20));

      commands = await session.commands();
    }

    expect(commands).toStrictEqual(FAKE_COMMANDS);
  }));

test("an agent's command goes to it as a prompt", () =>
  withSession(async (session) => {
    expect(said(await collect(session, '/greet'))).toStrictEqual([
      'Hello',
      ' from the fake agent.',
    ]);
    expect(said(await collect(session, '/echo two words'))).toStrictEqual([
      'two words',
    ]);
  }));

test('a mode change reaches the agent, and its answer is read back', () =>
  withSession(async (session) => {
    for (const mode of ['acceptEdits', 'plan', 'default']) {
      await session.setMode(mode);
      expect((await session.modes())?.current).toStrictEqual(mode);
    }
  }));

test('a mode the agent does not offer is refused, and nothing moves', () =>
  withSession(async (session) => {
    await expect(session.setMode('yolo')).rejects.toThrow();
    expect((await session.modes())?.current).toStrictEqual('default');
  }));

test("a mode change is read back before a prompt from an agent that answers it with nothing, as Codex's does", () =>
  withSession(
    async (session) => {
      for (const mode of ['plan', 'acceptEdits', 'default']) {
        await session.setMode(mode);
        expect((await session.modes())?.current).toStrictEqual(mode);
      }
    },
    undefined,
    '--silent-set-mode',
  ));

test('a mode change the agent refuses leaves the mode it holds', () =>
  withSession(
    async (session) => {
      await session.setMode('plan');
      await collect(session, 'lock');

      const refused = session.setMode('acceptEdits');

      await expect(refused).rejects.toThrow(Error);
      await expect(refused).rejects.toThrow('holds its mode');
      expect((await session.modes())?.current).toStrictEqual('plan');
    },
    undefined,
    '--silent-set-mode',
  ));

test('an agent that offers no mode config option is asked through set_mode', () =>
  withSession(
    async (session) => {
      expect(await session.modes()).toStrictEqual(undefined);

      // The fake refuses set_mode then, as an agent without modes would; its
      // words show that the older call is the one that reached it.
      const refused = session.setMode('plan');

      await expect(refused).rejects.toThrow(Error);
      await expect(refused).rejects.toThrow('session/set_mode');
    },
    undefined,
    '--no-modes',
  ));

test('a mode the agent leaves by itself is read back after the turn', () =>
  withSession(async (session) => {
    await session.setMode('plan');
    await collect(session, 'exitplan');
    expect((await session.modes())?.current).toStrictEqual('default');
  }));

const FAKE_MODELS = [
  { id: 'fake-large', name: 'Fake Large with a 1M context window' },
  { id: 'fake-small', name: 'Fake Small' },
];

test("the agent's models come in its order, with the one it uses", () =>
  withSession(async (session) => {
    expect(await session.models()).toStrictEqual({
      available: FAKE_MODELS,
      current: 'fake-large',
    });
  }));

test('a model change reaches the agent, and its answer is read back', () =>
  withSession(async (session) => {
    await session.setModel('fake-small');
    expect((await session.models())?.current).toStrictEqual('fake-small');

    // A turn after it leaves the model where it was put.
    await collect(session, 'text');
    expect((await session.models())?.current).toStrictEqual('fake-small');
  }));

test('a model the agent does not offer is refused, and nothing moves', () =>
  withSession(async (session) => {
    await expect(session.setModel('fake-huge')).rejects.toThrow();
    expect((await session.models())?.current).toStrictEqual('fake-large');
  }));

const EFFORT = {
  id: 'effort',
  name: 'Effort',
  values: [
    { value: 'low', name: 'Low' },
    { value: 'medium', name: 'Medium' },
    { value: 'high', name: 'High' },
  ],
  current: 'medium',
};

test("the agent's other config options come without its mode and model", () =>
  withSession(async (session) => {
    expect(await session.options()).toStrictEqual([EFFORT]);
  }));

test('a config option change reaches the agent, and its answer is read back', () =>
  withSession(async (session) => {
    await session.setOption('effort', 'high');
    expect(await session.options()).toStrictEqual([
      { ...EFFORT, current: 'high' },
    ]);

    // A turn after it leaves the option where it was put.
    await collect(session, 'text');
    expect((await session.options())[0]?.current).toStrictEqual('high');
  }));

test('a config option change the agent refuses moves nothing', () =>
  withSession(
    async (session) => {
      const refused = session.setOption('effort', 'high');

      await expect(refused).rejects.toThrow(Error);
      await expect(refused).rejects.toThrow('The fake agent holds its effort.');
      expect(await session.options()).toStrictEqual([EFFORT]);
    },
    undefined,
    '--refuse-config',
  ));

test('an agent with no other config options offers none', () =>
  withSession(
    async (session) => {
      expect(await session.options()).toStrictEqual([]);
      expect((await session.models())?.current).toStrictEqual('fake-large');
    },
    undefined,
    '--no-config',
  ));

/** What the fake said it received as links, for a prompt typed as `text`. */
async function linksSent(session: Session, text: string) {
  const { updates } = await run(session, text, { mentions: mentionsIn(text) });

  return said(updates).filter((line) => line.startsWith('Received a link'));
}

test("a prompt's mentions of files go after its text as resource links, once each", () =>
  withSession(async (session) => {
    const { cwd } = session;
    const uri = (path: string) => pathToFileURL(join(cwd, path)).href;

    await mkdir(join(cwd, 'src'));
    await writeFile(join(cwd, 'src/a.ts'), '');
    await writeFile(join(cwd, 'my notes.md'), '');

    expect(
      await linksSent(session, 'see @src/a.ts and @"my notes.md", @src/a.ts'),
    ).toStrictEqual([
      `Received a link: src/a.ts, ${uri('src/a.ts')}\n\n`,
      `Received a link: my notes.md, ${uri('my notes.md')}\n\n`,
    ]);
    expect(await linksSent(session, 'text')).toStrictEqual([]);
  }));

test('a mention of what is not a file @ offers sends no link', () =>
  withSession(async (session) => {
    const { cwd } = session;

    await mkdir(join(cwd, 'src'));
    await mkdir(join(cwd, 'dist'));
    await writeFile(join(cwd, 'dist/out.js'), '');
    await writeFile(join(cwd, '.gitignore'), 'dist/\n');

    expect(
      await linksSent(
        session,
        'see @src @missing.ts @../outside.ts @dist/out.js',
      ),
    ).toStrictEqual([]);
  }));

test('a turn says which links went with its prompt, and none went when a cancel came before the walk ended', () =>
  withSession(async (session) => {
    const { cwd } = session;

    await writeFile(join(cwd, 'a.ts'), '');

    const { turn } = await run(session, 'see @a.ts', { mentions: ['a.ts'] });

    expect(await turn.sent).toStrictEqual([
      {
        type: 'resource_link',
        name: 'a.ts',
        uri: pathToFileURL(join(cwd, 'a.ts')).href,
      },
    ]);

    const held = session.prompt('see @a.ts', [], ['a.ts']);

    await held.cancel();

    expect(await held.sent).toStrictEqual(undefined);
    expect((await held.result).status).toStrictEqual('cancelled');
    expect(await linksSent(session, 'text')).toStrictEqual([]);
  }));

// The agent may take the next prompt before a cancel sent ahead of it, so a
// cancel for a prompt it never got could stop the next turn (Q42).
test('a cancel before the walk ended tells the agent nothing, so it cannot land on the next turn', () =>
  withSession(async (session) => {
    await writeFile(join(session.cwd, 'a.ts'), '');

    const held = session.prompt('see @a.ts', [], ['a.ts']);

    await held.cancel();
    expect((await held.result).status).toStrictEqual('cancelled');

    const { updates, result } = await run(session, 'cancels');

    expect(result.status).toStrictEqual('completed');
    expect(said(updates).join('')).toStrictEqual('Cancels with no turn: 0.');
  }));

test('a failed turn says why, and the session takes the next prompt', () =>
  withSession(async (session) => {
    const { updates, result } = await run(session, 'error');

    expect(said(updates)).toStrictEqual(['About to fail.']);
    assert(result.status === 'failed');
    expect(result.error.message).toStrictEqual(
      'The fake agent failed on purpose.',
    );
    expect((await run(session, 'text')).result.status).toStrictEqual(
      'completed',
    );
    // The agent is still up: the failure is the turn's, not an exit.
    expect(session.gone()).toStrictEqual(undefined);
  }));

test('an agent that exits mid-turn fails the turn, and its last words are what it left on stderr', () =>
  withSession(async (session) => {
    expect(session.gone()).toStrictEqual(undefined);

    const { result } = await run(session, 'crash');

    expect(result.status === 'failed').toBeTruthy();
    expect(session.gone()).toStrictEqual(CRASH_WORDS);
    await session.exited;
  }));

async function cancelSlowTurn(
  session: Session,
  cancel: (turn: Turn) => Promise<void>,
) {
  const { updates, result } = await run(session, 'slow', {
    onUpdate: (so, turn) => {
      if (so.length === 3) {
        void cancel(turn);
      }
    },
  });

  expect(result.status).toStrictEqual('cancelled');
  // The fake turn is a thousand chunks long; stopping early is the agent
  // honouring cancel.
  expect(
    updates.length < 100,
    `${updates.length} updates after cancel`,
  ).toBeTruthy();
}

test('a slow turn stops when the turn is cancelled', () =>
  withSession((session) => cancelSlowTurn(session, (turn) => turn.cancel())));

test('a slow turn stops when the session cancels its active turn', () =>
  withSession((session) => cancelSlowTurn(session, () => session.cancel())));

test('closing mid-turn ends the turn and the agent', () =>
  withSession(async (session) => {
    const first = Promise.withResolvers<void>();
    const unsubscribe = session.subscribe(() => first.resolve());
    const turn = session.prompt('slow');

    await first.promise;
    unsubscribe();
    await session.close();
    expect((await turn.result).status !== 'completed').toBeTruthy();
  }));

test("the scenario can come from the agent's command line", () =>
  withSession(async (session) => {
    expect(said(await collect(session, 'anything'))).toStrictEqual([
      'Here is',
      ' the answer.',
    ]);
  }, 'thought'));

test('an agent that cannot start fails the open and leaves nothing running', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-session-'));

  await expect(
    openSession({
      agent: 'missing',
      cwd: dir,
      agentCommand: [join(dir, 'no-such-agent')],
    }),
  ).rejects.toThrow();
  await rm(dir, { recursive: true });
});

test('an agent command given as one string is split the way a shell would', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-session-'));
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand()
      .map((arg) => `'${arg}'`)
      .join(' '),
  });

  try {
    expect(said(await collect(session, 'text')).length).toStrictEqual(4);
  } finally {
    await session.close();
    await rm(dir, { recursive: true });
  }
});

/** The pids of every process whose command line holds `tag`. */
function tagged(tag: string): Promise<number[]> {
  // pgrep exits 1 when nothing matches, which is an answer too.
  return new Promise((resolve) => {
    execFile('pgrep', ['-f', tag], (_error, stdout) =>
      resolve(stdout.split('\n').filter(Boolean).map(Number)),
    );
  });
}

/**
 * Opens a session on a fake agent that wedges at `step`, plays `body` into it,
 * and proves the close comes back within the bound with the agent gone.
 */
async function quitsWedged(step: string, body: (session: Session) => void) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-session-'));
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand(undefined, '--hang', step),
  });
  const pids = [...session.agentPids];

  try {
    body(session);
    // Long enough for the request to be out to the agent.
    await new Promise((resolve) => setTimeout(resolve, 200));

    const started = Date.now();

    await session.close();
    expect(
      Date.now() - started < 10_000,
      'the close was not bounded',
    ).toBeTruthy();
    expect(session.agentPids.size).toStrictEqual(0);

    for (const pid of pids) {
      expect(!(await isAlive(pid)), `agent ${pid} still running`).toBeTruthy();
    }
  } finally {
    await rm(dir, { recursive: true });
  }
}

test('closing comes back and kills an agent that never answers a config change', () =>
  quitsWedged('config', (session) => {
    session.setOption('effort', 'high').catch(() => {});
  }));

test('closing comes back and kills an agent whose turn ignores its cancel', () =>
  quitsWedged('turn', (session) => {
    const turn = session.prompt('text');

    turn.result.catch(() => {});

    session.cancel().catch(() => {});
  }));

test('an open given up while the agent never answers its start leaves nothing running', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-session-'));
  const tag = `chord-wedged-${crypto.randomUUID()}`;
  const stop = new AbortController();
  const opening = openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand(undefined, '--hang', 'start', tag),
    signal: stop.signal,
  });

  try {
    while ((await tagged(tag)).length === 0) {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }

    const started = Date.now();

    stop.abort(new Error('given up'));
    await expect(opening).rejects.toThrow(Error);
    await expect(opening).rejects.toThrow('given up');
    expect(
      Date.now() - started < 10_000,
      'the open did not give up in time',
    ).toBeTruthy();
    expect(await tagged(tag)).toStrictEqual([]);
  } finally {
    await rm(dir, { recursive: true });
  }
});

test("an agent that reports tokens alone gets a cost and a window, marked as chord's", () =>
  withSession(
    async (session) => {
      const { updates, result } = await run(session, 'text');
      const usage = updates.filter(
        (update) => update.sessionUpdate === 'usage_update',
      );

      expect(result.status === 'completed' && result.usage).toStrictEqual({
        inputTokens: 1000,
        outputTokens: 200,
        cachedReadTokens: 800,
        totalTokens: 2000,
      });
      expect(usage.length).toStrictEqual(1);
      expect(
        usage[0]?.sessionUpdate === 'usage_update' && {
          used: usage[0].used,
          size: usage[0].size,
          currency: usage[0].cost?.currency,
          filled: usage[0]._meta?.[FILLED],
        },
      ).toStrictEqual({
        used: 2000,
        size: 400_000,
        currency: 'USD',
        filled: ['used', 'cost', 'size'],
      });
    },
    undefined,
    '--tokens-only',
  ));

/** chord's own server as a session would get it, at a URL nothing serves. */
const CHORD_SERVER = {
  type: 'http' as const,
  name: 'chord',
  url: 'http://127.0.0.1:9/mcp',
  headers: [{ name: 'Authorization', value: 'Bearer token' }],
};

/** The user's servers in the MCP tests: one of each transport chord reads. */
const DOCS = { name: 'docs', command: 'docs-server', args: [], env: [] };
const SEARCH = {
  type: 'http' as const,
  name: 'search',
  url: 'https://search.example/mcp',
  headers: [],
};
const LOGS = {
  type: 'sse' as const,
  name: 'logs',
  url: 'https://logs.example/sse',
  headers: [],
};

/**
 * The MCP servers the fake agent says its session was opened with, and what
 * the session says it held back; opened again from `resume` when given.
 */
async function serversGiven(
  flags: readonly string[],
  resume?: Resume,
): Promise<{
  given: unknown;
  session: Pick<Session, 'heldBack'> & {
    chordServer?: unknown;
  };
}> {
  const dir = resume?.cwd ?? (await mkdtemp(join(tmpdir(), 'chord-session-')));
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand(undefined, ...flags),
    mcpServers: [DOCS, SEARCH, LOGS],
    chordServer: CHORD_SERVER,
    ...(resume === undefined ? {} : { resume }),
  });

  try {
    const reply = said((await run(session, 'mcp')).updates).join('');

    return {
      given: JSON.parse(reply.replace(/^```json\n|\n```$/g, '')),
      session: {
        heldBack: session.heldBack,
        ...(session.chordServer === undefined
          ? {}
          : { chordServer: session.chordServer }),
      },
    };
  } finally {
    await session.close();

    if (resume === undefined) {
      await rm(dir, { recursive: true });
    }
  }
}

/** A held-back entry as the session lists it for the fake. */
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

describe('an agent is given only the MCP servers whose transport it advertises (CHD-441)', () => {
  const combinations: [string, readonly string[], unknown[], HeldBack[]][] = [
    [
      'http and sse',
      ['--mcp-transports', 'http,sse'],
      [DOCS, SEARCH, LOGS, CHORD_SERVER],
      [],
    ],
    [
      'http alone',
      ['--mcp-transports', 'http'],
      [DOCS, SEARCH, CHORD_SERVER],
      [held('logs', 'sse', ['stdio', 'http'])],
    ],
    [
      'sse alone',
      ['--mcp-transports', 'sse'],
      [DOCS, LOGS],
      [
        held('search', 'http', ['stdio', 'sse']),
        held('chord', 'http', ['stdio', 'sse'], true),
      ],
    ],
    [
      'stdio alone',
      ['--mcp-transports', 'none'],
      [DOCS],
      [
        held('search', 'http', ['stdio']),
        held('logs', 'sse', ['stdio']),
        held('chord', 'http', ['stdio'], true),
      ],
    ],
    [
      'sse with --no-http',
      ['--no-http'],
      [DOCS, LOGS],
      [
        held('search', 'http', ['stdio', 'sse']),
        held('chord', 'http', ['stdio', 'sse'], true),
      ],
    ],
  ];

  for (const [label, flags, given, heldBack] of combinations) {
    test(`a new session on an agent advertising ${label}`, async () => {
      const { given: got, session } = await serversGiven(flags);

      expect(got).toStrictEqual(given);
      expect(session.heldBack).toStrictEqual(heldBack);
      expect(session.chordServer).toStrictEqual(
        given.includes(CHORD_SERVER) ? CHORD_SERVER : undefined,
      );
    });
  }

  test('a session loaded or resumed again is given the same, and holds back the same', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-session-'));

    try {
      const loaded = await serversGiven(['--mcp-transports', 'sse'], {
        sessionId: crypto.randomUUID(),
        cwd: dir,
      });

      expect(loaded.given).toStrictEqual([DOCS, LOGS]);
      expect(loaded.session.heldBack).toStrictEqual([
        held('search', 'http', ['stdio', 'sse']),
        held('chord', 'http', ['stdio', 'sse'], true),
      ]);

      const stateDir = join(dir, 'state');
      const flags = ['--mcp-transports', 'http'];
      const sessionId = await recordSession({
        stateDir,
        cwd: dir,
        command: fakeAgentCommand(undefined, ...flags),
        prompts: ['text'],
      });
      const [record] = await readRecords(stateDir);

      assert(record !== undefined);

      const resumed = await serversGiven([...flags, '--resume-only'], {
        sessionId,
        cwd: dir,
        record: record.path,
      });

      expect(resumed.given).toStrictEqual([DOCS, SEARCH, CHORD_SERVER]);
      expect(resumed.session.heldBack).toStrictEqual([
        held('logs', 'sse', ['stdio', 'http']),
      ]);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});

/** Claude's adapter's prompt suggestions off, as chord opens its sessions. */
const NO_SUGGESTIONS = {
  claudeCode: { options: { promptSuggestions: false } },
};

/**
 * The request that opened a session in `dir`, and its `_meta`, as the fake
 * agent says them; opened again from `resume` when there is one.
 */
async function openedBy(
  dir: string,
  flags: readonly string[],
  resume?: Resume,
): Promise<unknown> {
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand(undefined, ...flags),
    ...(resume === undefined ? {} : { resume }),
  });

  try {
    const reply = said((await run(session, 'opened')).updates).join('');

    return JSON.parse(reply.replace(/^```json\n|\n```$/g, ''));
  } finally {
    await session.close();
  }
}

describe("Claude's prompt suggestions are off in every session chord opens (CHD-439)", () => {
  const inDir = async (body: (dir: string) => Promise<void>) => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-opened-'));

    try {
      await body(dir);
    } finally {
      await rm(dir, { recursive: true });
    }
  };

  test('a new Claude session asks for none, and a Codex or other one is sent no _meta', () =>
    inDir(async (dir) => {
      expect(await openedBy(dir, ['--adapter', 'claude'])).toStrictEqual({
        method: 'session/new',
        meta: NO_SUGGESTIONS,
      });
      expect(await openedBy(dir, ['--steering', 'codex'])).toStrictEqual({
        method: 'session/new',
      });
      expect(await openedBy(dir, [])).toStrictEqual({
        method: 'session/new',
      });
    }));

  test('a Claude session loaded again asks for none, and a Codex one is sent no _meta', () =>
    inDir(async (dir) => {
      const resume = { sessionId: crypto.randomUUID(), cwd: dir };

      expect(
        await openedBy(dir, ['--adapter', 'claude'], resume),
      ).toStrictEqual({ method: 'session/load', meta: NO_SUGGESTIONS });
      expect(
        await openedBy(dir, ['--steering', 'codex'], resume),
      ).toStrictEqual({ method: 'session/load' });
    }));

  test('a Claude session resumed from its record asks for none, and a Codex one is sent no _meta', () =>
    inDir(async (dir) => {
      const stateDir = join(dir, 'state');

      for (const flags of [
        ['--adapter', 'claude'],
        ['--steering', 'codex'],
      ]) {
        await rm(stateDir, { recursive: true, force: true });

        const sessionId = await recordSession({
          stateDir,
          cwd: dir,
          command: fakeAgentCommand(undefined, ...flags),
          prompts: ['text'],
        });
        const [record] = await readRecords(stateDir);

        assert(record !== undefined);
        expect(
          await openedBy(dir, [...flags, '--resume-only'], {
            sessionId,
            cwd: dir,
            record: record.path,
          }),
        ).toStrictEqual(
          flags[0] === '--adapter'
            ? { method: 'session/resume', meta: NO_SUGGESTIONS }
            : { method: 'session/resume' },
        );
      }
    }));
});

describe('CHD-439 tester: adapter identity across session openings', () => {
  const inDir = async (body: (dir: string) => Promise<void>) => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-opening-meta-'));

    try {
      await body(dir);
    } finally {
      await rm(dir, { recursive: true });
    }
  };

  test('simultaneous Claude and other sessions keep their opening metadata separate', () =>
    inDir(async (dir) => {
      const resume = { sessionId: crypto.randomUUID(), cwd: dir };
      const results = await Promise.allSettled([
        openedBy(dir, ['--adapter', 'claude']),
        openedBy(dir, ['--steering', 'codex']),
        openedBy(dir, ['--adapter', 'claude'], resume),
        openedBy(dir, [], resume),
      ]);

      expect(results).toStrictEqual([
        {
          status: 'fulfilled',
          value: { method: 'session/new', meta: NO_SUGGESTIONS },
        },
        { status: 'fulfilled', value: { method: 'session/new' } },
        {
          status: 'fulfilled',
          value: { method: 'session/load', meta: NO_SUGGESTIONS },
        },
        { status: 'fulfilled', value: { method: 'session/load' } },
      ]);
    }));

  for (const { name, previous, next, expected } of [
    {
      name: 'recorded Claude history still gets the option through load when resume is unavailable',
      previous: ['--adapter', 'claude'],
      next: ['--adapter', 'claude'],
      expected: { method: 'session/load', meta: NO_SUGGESTIONS },
    },
    {
      name: 'a different current adapter gets no Claude options from recorded history',
      previous: ['--adapter', 'claude'],
      next: ['--steering', 'codex', '--resume-only'],
      expected: { method: 'session/resume' },
    },
    {
      name: 'a current Claude adapter gets the option when the recorded agent was different',
      previous: [],
      next: ['--adapter', 'claude', '--resume-only'],
      expected: { method: 'session/resume', meta: NO_SUGGESTIONS },
    },
  ]) {
    test(name, () =>
      inDir(async (dir) => {
        const stateDir = join(dir, 'state');
        const sessionId = await recordSession({
          stateDir,
          cwd: dir,
          command: fakeAgentCommand(undefined, ...previous),
          prompts: ['text'],
        });
        const [record] = await readRecords(stateDir);

        assert(record !== undefined);
        expect(
          await openedBy(dir, next, {
            sessionId,
            cwd: dir,
            record: record.path,
          }),
        ).toStrictEqual(expected);
      }),
    );
  }
});

describe('CHD-246 tester: large MCP permission fixture', () => {
  test.each(['allow', 'always', 'deny', 'cancel'])(
    'preserves the complete request when the answer is %s',
    (answer) =>
      withSession(async (session) => {
        let request: PendingPermission | undefined;
        const unsubscribe = session.permissions.subscribe((pending) => {
          request = pending;

          setTimeout(() => {
            if (answer === 'cancel') {
              void session.cancel();
            } else {
              pending.resolve(answer);
            }
          }, 10);
        });

        try {
          const { updates, result } = await run(session, 'bigask');

          assert(request);
          expect(request.toolCall.title).toBe('mcp__files__write_file');
          expect(request.toolCall.toolCallId).toBe('write_file-1');
          expect(request.toolCall.content).toBeUndefined();

          const input = request.toolCall.rawInput as {
            path: string;
            content: string;
            mode: string;
          };

          expect(input.path).toBe('docs/release.md');
          expect(input.mode).toBe('overwrite');
          expect(input.content.split('\n')).toHaveLength(37);
          expect(input.content).toStartWith('# Release 0.56.0\n\n');
          expect(input.content.split('\n')[2]?.length).toBeGreaterThan(200);
          expect(input.content).toEndWith(
            '- Change 30: tests run in parallel\n',
          );
          expect(request.options.map((option) => option.optionId)).toEqual([
            'allow',
            'always',
            'deny',
          ]);
          expect(request.options[1]?.name).toContain('files - write_file');
          expect(session.permissions.pending()).toEqual([]);

          if (answer === 'cancel') {
            expect(result.status).toBe('cancelled');
            expect(request.signal.aborted).toBe(true);
            expect(said(updates)).toEqual([]);
          } else {
            expect(result.status).toBe('completed');
            expect(calls(updates).at(-1)?.status).toBe(
              answer === 'deny' ? 'failed' : 'completed',
            );
            expect(said(updates)).toEqual([`Permission: ${answer}.`]);
          }
        } finally {
          unsubscribe();
        }
      }),
  );
});

describe('CHD-393 tester: headline scenario payloads', () => {
  test('sends four complete arguments and matching completion outputs', () =>
    withSession(async (session) => {
      const { updates, result } = await run(session, 'headlines');
      const events = calls(updates);
      const starts = events.filter(
        (event) => event.sessionUpdate === 'tool_call',
      );
      const ends = events.filter(
        (event) => event.sessionUpdate === 'tool_call_update',
      );

      expect(result.status).toBe('completed');
      expect(starts).toHaveLength(4);
      expect(ends.map((event) => [event.toolCallId, event.status])).toEqual(
        starts.map((event) => [event.toolCallId, 'completed']),
      );
      expect(new Set(starts.map((event) => event.toolCallId)).size).toBe(4);
      expect(starts.map((event) => event.status)).toEqual(
        Array.from({ length: 4 }, () => 'in_progress'),
      );

      const commands = starts
        .filter((event) => event.kind === 'execute')
        .map((event) => {
          const input = event.rawInput as { command: string };

          expect(event.title).toBe('`' + input.command + '`');

          return input.command;
        });

      expect(commands[0]?.split('\n')).toHaveLength(13);
      expect(commands[0]).toContain('\n\n');
      expect(commands[0]).toEndWith('\nEOF');
      expect(commands[1]?.length).toBeGreaterThan(200);
      expect(commands[1]).not.toContain('\n');
      expect(commands[1]).toEndWith('src/ui/transcript/tools/');
      expect(commands[2]?.split('\n')).toHaveLength(300);
      expect(commands[2]).toEndWith('line 298 of the long command\nEOF');

      const mcp = starts.find((event) => event.kind === 'other');

      assert(mcp);
      expect(mcp.title).toBe('mcp__chord__send_message');
      expect(mcp.rawInput).toEqual({
        to: 'reviewer',
        text: expect.stringContaining('a command of 300 lines'),
      });
      expect(ends.map((event) => event.content?.length)).toEqual([1, 1, 1, 1]);
      expect(said(updates)).toEqual(['Four calls with long headlines.']);
    }));

  test('can cancel between calls and play the complete scenario next turn', () =>
    withSession(
      async (session) => {
        const cancelled = await run(session, 'headlines', {
          onUpdate: (updates, turn) => {
            if (calls(updates).length === 1) {
              void turn.cancel();
            }
          },
        });

        expect(cancelled.result.status).toBe('cancelled');
        expect(said(cancelled.updates)).toEqual([]);
        expect((await run(session, 'headlines')).result.status).toBe(
          'completed',
        );
      },
      undefined,
      '--step-ms',
      '20',
    ));
});

describe('Q42 tester: prompt-send cancellation boundaries', () => {
  test('repeated cancellation of several unsent prompts leaves the next turn and stray counter untouched', () =>
    withSession(async (session) => {
      await writeFile(join(session.cwd, 'a.ts'), '');

      for (let index = 0; index < 6; index++) {
        const held = session.prompt('held mention', [], ['a.ts']);

        await Promise.all([held.cancel(), held.cancel()]);
        expect(await held.sent).toBeUndefined();
        expect((await held.result).status).toBe('cancelled');
      }

      const next = await run(session, 'cancels');

      expect(next.result.status).toBe('completed');
      expect(
        said(next.updates)
          .filter((line) => line.startsWith('Cancels with no turn:'))
          .join(''),
      ).toBe('Cancels with no turn: 0.');
    }));

  test('cancelling an unsent turn again cannot withdraw a later turn permission', () =>
    withSession(async (session) => {
      await writeFile(join(session.cwd, 'a.ts'), '');

      const waiting = Promise.withResolvers<PendingPermission>();
      const unsubscribe = session.permissions.subscribe((request) =>
        waiting.resolve(request),
      );

      try {
        const held = session.prompt('held mention', [], ['a.ts']);

        await held.cancel();
        expect(await held.sent).toBeUndefined();
        expect((await held.result).status).toBe('cancelled');

        const active = session.prompt('permission');
        const request = await waiting.promise;

        await held.cancel();
        expect(request.signal.aborted).toBe(false);
        request.resolve('allow');
        expect((await active.result).status).toBe('completed');

        const next = await run(session, 'cancels');

        expect(next.result.status).toBe('completed');
        expect(
          said(next.updates)
            .filter((line) => line.startsWith('Cancels with no turn:'))
            .join(''),
        ).toBe('Cancels with no turn: 0.');
      } finally {
        unsubscribe();
      }
    }));

  for (const mentions of [[], ['a.ts']]) {
    test(`an already-sent prompt ${mentions.length === 0 ? 'without' : 'with'} mentions still cancels its active permission`, () =>
      withSession(async (session) => {
        await writeFile(join(session.cwd, 'a.ts'), '');

        const waiting = Promise.withResolvers<PendingPermission>();
        const unsubscribe = session.permissions.subscribe((request) =>
          waiting.resolve(request),
        );

        try {
          const active = session.prompt('permission', [], mentions);
          const request = await waiting.promise;

          expect(await active.sent).toHaveLength(mentions.length);
          await active.cancel();
          expect(request.signal.aborted).toBe(true);
          expect((await active.result).status).toBe('cancelled');

          const next = await run(session, 'cancels');

          expect(next.result.status).toBe('completed');
          expect(
            said(next.updates)
              .filter((line) => line.startsWith('Cancels with no turn:'))
              .join(''),
          ).toMatch(/^Cancels with no turn: [01]\.$/);
        } finally {
          unsubscribe();
        }
      }));
  }
});

describe('CHD-407 R1 tester: screenshot model selection', () => {
  test('tokens-only keeps the original defaults and accepts both screenshot models', () =>
    withSession(
      async (session) => {
        const models = await session.models();

        expect(models?.current).toBe('gpt-5.3-codex');
        expect(models?.available.map(({ id }) => id)).toEqual([
          'gpt-5.3-codex',
          'claude-haiku-4-5',
          'claude-opus-5-5',
          'gpt-6.1-sol',
        ]);

        for (const model of ['claude-opus-5-5', 'gpt-6.1-sol']) {
          await session.setModel(model);

          const { updates, result } = await run(session, 'text');
          const usage = updates.find(
            (update) => update.sessionUpdate === 'usage_update',
          );

          expect(result.status).toBe('completed');
          expect((await session.models())?.current).toBe(model);
          assert(usage?.sessionUpdate === 'usage_update');
          expect(usage.cost?.amount).toBeGreaterThan(0);
          expect(usage.size).toBeGreaterThan(0);
        }
      },
      undefined,
      '--tokens-only',
    ));
});

describe('CHD-441 tester: takes-none survives every session opening path', () => {
  for (const method of ['new', 'load', 'recorded resume'] as const) {
    test(`${method}: none suppresses all transports and own server, and false restores them`, async () => {
      const dir = await mkdtemp(join(tmpdir(), 'chord-no-mcp-'));

      try {
        const stateDir = join(dir, 'state');
        const sessionId = await recordSession({
          stateDir,
          cwd: dir,
          command: fakeAgentCommand(),
          prompts: ['text'],
        });
        const [record] = await readRecords(stateDir);

        assert(record);

        for (const noMcpServers of [true, false]) {
          const session = await openSession({
            agent: 'fake',
            cwd: dir,
            agentCommand: fakeAgentCommand(
              undefined,
              ...(method === 'recorded resume' ? ['--resume-only'] : []),
            ),
            noMcpServers,
            mcpServers: [DOCS, SEARCH, LOGS],
            chordServer: CHORD_SERVER,
            ...(method === 'new'
              ? {}
              : {
                  resume: {
                    sessionId,
                    cwd: dir,
                    ...(method === 'recorded resume'
                      ? { record: record.path }
                      : {}),
                  },
                }),
          });

          try {
            const reply = said((await run(session, 'mcp')).updates).join('');
            const given: unknown = JSON.parse(
              reply.replace(/^```json\n|\n```$/g, ''),
            );

            const opening = said((await run(session, 'opened')).updates).join(
              '',
            );

            expect(
              JSON.parse(opening.replace(/^```json\n|\n```$/g, '')),
            ).toStrictEqual({
              method:
                method === 'new'
                  ? 'session/new'
                  : method === 'load'
                    ? 'session/load'
                    : 'session/resume',
            });
            expect(given).toStrictEqual(
              noMcpServers ? [] : [DOCS, SEARCH, LOGS, CHORD_SERVER],
            );
            expect(session.chordServer).toStrictEqual(
              noMcpServers ? undefined : CHORD_SERVER,
            );
            expect(session.heldBack).toStrictEqual(
              noMcpServers
                ? [
                    held('docs', 'stdio', []),
                    held('search', 'http', []),
                    held('logs', 'sse', []),
                    held('chord', 'http', [], true),
                  ]
                : [],
            );
          } finally {
            await session.close();
          }
        }
      } finally {
        await rm(dir, { recursive: true });
      }
    });
  }
});

describe('CHD-435 tester: sign-in through real session starts', () => {
  for (const entry of ['new', 'load', 'resume'] as const) {
    for (const kind of ['methods', 'bare', 'link', 'linkother'] as const) {
      test(`${entry} keeps the ${kind} failure classification and stops the agent`, async () => {
        const cwd = await mkdtemp(join(tmpdir(), 'chord-sign-in-'));
        const tag = `chd435-signin-${crypto.randomUUID()}`;
        const sessionId = crypto.randomUUID();
        const message =
          kind === 'methods'
            ? 'Authentication required: run `fake login` from your terminal, or set FAKE_API_KEY'
            : kind === 'link'
              ? 'Authentication required: Sign-in was cancelled. Retry to sign in.'
              : kind === 'linkother'
                ? 'The fake could not open its session.'
                : 'Authentication required';
        let session: Session | undefined;
        let failure: unknown;

        try {
          try {
            session = await openSession({
              agent: 'fake',
              cwd,
              agentCommand: fakeAgentCommand(
                undefined,
                '--auth-required',
                kind,
                '--tester-tag',
                tag,
                ...(entry === 'resume' ? ['--resume-only', '--no-load'] : []),
              ),
              ...(entry === 'new' ? {} : { resume: { sessionId, cwd } }),
            });
          } catch (error) {
            failure = error;
          } finally {
            await session?.close();
          }

          assert(failure instanceof Error);
          expect(signInOf(failure)).toStrictEqual(
            kind === 'linkother'
              ? undefined
              : {
                  message,
                  ways:
                    kind === 'methods'
                      ? [
                          {
                            name: 'Log in with the fake',
                            description: 'Run `fake login` in the terminal',
                          },
                          { name: 'Log in with SSO' },
                        ]
                      : [],
                },
          );

          if (kind === 'linkother') {
            expect(failure).not.toBeInstanceOf(SignInNeeded);
            expect(failure.cause).not.toBeInstanceOf(SignInNeeded);
          } else {
            expect(entry === 'new' ? failure : failure.cause).toBeInstanceOf(
              SignInNeeded,
            );
          }

          if (entry === 'new') {
            expect(failure.message).toBe(message);
          } else {
            expect(failure.message).toBe(
              `it cannot resume session ${sessionId}: ${message}`,
            );
          }

          expect(await tagged(tag)).toStrictEqual([]);
        } finally {
          await rm(cwd, { recursive: true });
        }
      });
    }
  }
});

describe('CHD-454 tester: structured failures through actual starts', () => {
  async function rejected(options: Parameters<typeof openSession>[0]) {
    let failure: unknown;
    let session: Session | undefined;

    try {
      session = await openSession(options);
    } catch (error) {
      failure = error;
    } finally {
      await session?.close();
    }

    assert(failure instanceof Error);

    return failure;
  }

  for (const step of [
    'session/new',
    'session/load',
    'session/resume',
  ] as const) {
    test(`${step} retains its actual request step and refusal code under wrappers, without an override pin`, async () => {
      const cwd = await mkdtemp(join(tmpdir(), 'chord-start-step-'));
      const sessionId = crypto.randomUUID();

      try {
        const failure = await rejected({
          agent: 'claude',
          cwd,
          agentCommand: fakeAgentCommand(
            undefined,
            '--start-fails',
            'notacp',
            ...(step === 'session/resume'
              ? ['--resume-only', '--no-load']
              : []),
          ),
          ...(step === 'session/new' ? {} : { resume: { sessionId, cwd } }),
        });

        expect(startFailureOf(failure)).toEqual({
          step,
          code: -32601,
          said: `Method not found: ${step}`,
        });
        expect(failure.message).toContain(`Method not found: ${step}`);
        expect(signInOf(failure)).toBeUndefined();
      } finally {
        await rm(cwd, { recursive: true });
      }
    });
  }

  test('a signal exit remains a signal, with its shell-style status and no invented refusal code', async () => {
    const cwd = await mkdtemp(join(tmpdir(), 'chord-start-signal-'));

    try {
      const failure = await rejected({
        agent: 'fake',
        cwd,
        agentCommand: ['sh', '-c', 'kill -TERM $$'],
      });

      expect(startFailureOf(failure)).toEqual({
        step: 'initialize',
        exit: { code: 143, signal: 'SIGTERM' },
      });
    } finally {
      await rm(cwd, { recursive: true });
    }
  });

  test('a registry launch carries its pin, but an explicit command override does not', async () => {
    const cwd = await mkdtemp(join(tmpdir(), 'chord-start-pin-'));
    const previousPath = process.env.PATH;
    const definition = findAgent('agoragentic-acp');

    assert(definition?.runner === 'npx');
    expect(definition.start.env['PATH']).toBeUndefined();

    // The registry runner is a local stub. No registry package or model is
    // ever launched; its requested argv is its diagnostic.
    await writeFile(
      join(cwd, 'npx'),
      '#!/bin/sh\nprintf \'%s\\n\' "$@" >&2\nexit 1\n',
    );
    await chmod(join(cwd, 'npx'), 0o755);

    process.env.PATH = `${cwd}:${previousPath ?? ''}`;

    try {
      const registry = await rejected({ agent: 'agoragentic-acp', cwd });
      const overridden = await rejected({
        agent: 'agoragentic-acp',
        cwd,
        agentCommand: fakeAgentCommand(undefined, '--start-fails', 'notacp'),
      });

      expect(startFailureOf(registry)?.pinned).toBe(definition.pinned);
      expect(startFailureOf(registry)?.stderr?.lines).toContain(
        definition.pinned!,
      );
      expect(startFailureOf(overridden)).toEqual({
        step: 'session/new',
        code: -32601,
        said: 'Method not found: session/new',
      });
    } finally {
      if (previousPath === undefined) {
        delete process.env.PATH;
      } else {
        process.env.PATH = previousPath;
      }

      await rm(cwd, { recursive: true });
    }
  });
});

test('Guardian statuses survive the fake transport, transcript and recorded replay, including an already-approved opening (CHD-521)', () =>
  withSession(async (session) => {
    const { updates, result } = await run(session, 'guardian');
    const actions = updates.map((update) => ({
      type: 'update' as const,
      turnId: 't1',
      update,
    }));
    const recorded = recordActions([
      { type: 'prompt', turnId: 't1', at: 0, prompt: 'guardian', images: 0 },
      ...actions,
      { type: 'result', turnId: 't1', result },
    ]);
    const replayed = pastActions(
      updates.map((update) => ({ update })),
      0,
    );

    expect(result.status).toBe('completed');

    for (const past of [actions, recorded, replayed]) {
      let transcript = emptyTranscript;

      for (const action of past) {
        if (action.type !== 'usage') {
          transcript = reduceTranscript(transcript, action);
        }
      }

      const reviews = transcript.entries.flatMap((entry) =>
        entry.kind === 'tool' ? [entry.call] : [],
      );

      expect(reviews.map((call) => call.guardian)).toStrictEqual([
        'approved',
        'denied',
        'timedOut',
        'aborted',
        'inProgress',
        undefined,
        'approved',
      ]);
      expect(reviews[0]?.rawOutput).toMatchObject({
        review: { status: 'approved' },
      });
      expect(reviews[4]?.status).toBe('in_progress');
      expect(reviews[5]?.content).toContainEqual({
        type: 'content',
        content: {
          type: 'text',
          text: 'Status: Approved\nAction: exec printf ready\nRisk: low\nAuthorization: high\nRationale: A scripted Guardian review.',
        },
      });
    }
  }));

describe('CHD-521 U1 tester: cancellation before Guardian verdicts', () => {
  test('cancelling the specifically opened reviews leaves their statuses pending and the next turn independent', () =>
    withSession(async (session) => {
      const pending = new Set<string>();
      let cancelled = false;
      const first = await run(session, 'guardiangated', {
        onUpdate: (updates, turn) => {
          for (const update of updates) {
            if (
              update.sessionUpdate === 'tool_call' &&
              update._meta?.[GUARDIAN_REVIEW] === 'inProgress'
            ) {
              pending.add(update.toolCallId);
            }
          }

          if (
            !cancelled &&
            pending.size === 5 &&
            said(updates).join('').includes('Guardian reviews opened.')
          ) {
            cancelled = true;

            void turn.cancel();
          }
        },
      });

      expect(cancelled).toBe(true);
      expect(first.result.status).toBe('cancelled');
      expect(
        calls(first.updates).filter(
          (update) => update.sessionUpdate === 'tool_call_update',
        ),
      ).toHaveLength(0);

      const second = await run(session, 'guardian');
      const secondIds = calls(second.updates).map(
        (update) => update.toolCallId,
      );

      expect(second.result.status).toBe('completed');
      expect(secondIds.every((id) => !pending.has(id))).toBe(true);

      let transcript = emptyTranscript;
      const entries: RecordEntry[] = [];

      for (const [at, ran] of [first, second].entries()) {
        const turnId = `review-turn-${at}`;

        entries.push(
          { type: 'prompt', turnId, at, prompt: 'guardian', images: 0 },
          ...ran.updates.map((update) => ({
            type: 'update' as const,
            turnId,
            update,
          })),
          { type: 'result', turnId, result: ran.result },
        );
      }

      for (const action of recordActions(entries)) {
        if (action.type !== 'usage') {
          transcript = reduceTranscript(transcript, action);
        }
      }

      const reviews = transcript.entries.flatMap((entry) =>
        entry.kind === 'tool' ? [entry.call] : [],
      );

      expect(reviews.filter((call) => pending.has(call.id))).toHaveLength(5);
      expect(
        reviews
          .filter((call) => pending.has(call.id))
          .every((call) => call.guardian === 'inProgress'),
      ).toBe(true);
      expect(
        reviews
          .filter((call) => secondIds.includes(call.id))
          .map((call) => call.guardian),
      ).toEqual([
        'approved',
        'denied',
        'timedOut',
        'aborted',
        'inProgress',
        undefined,
        'approved',
      ]);
    }));
});
