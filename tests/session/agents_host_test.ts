import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  createAgentsHost,
  type AgentsEvent,
  type AgentsPort,
  type FoldedSession,
} from '../../src/session/agents_host.ts';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import type { Place } from '../../src/session/place.ts';
import { heldSession, until } from './conversation_fake.ts';

const HOST = fileURLToPath(
  new URL('../../src/session/agents_host.ts', import.meta.url),
);

/** Every package `file` reaches through static imports, types left out. */
async function packagesReached(file: string): Promise<Set<string>> {
  const seen = new Set<string>();
  const packages = new Set<string>();
  const walk = async (at: string) => {
    // A JSON file imports nothing.
    if (seen.has(at) || !/\.tsx?$/.test(at)) {
      return;
    }

    seen.add(at);

    const scanner = new Bun.Transpiler({
      loader: at.endsWith('.tsx') ? 'tsx' : 'ts',
    });

    for (const { path } of scanner.scanImports(await readFile(at, 'utf8'))) {
      if (path.startsWith('.')) {
        await walk(resolve(dirname(at), path));
      } else {
        packages.add(path);
      }
    }
  };

  await walk(file);

  return packages;
}

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), 'chord-agents-host-'));
});

afterEach(async () => {
  await rm(dir, { recursive: true });
});

/** A host on held sessions, its place a fresh directory, and what it told. */
function hosted(place: Partial<Place> = {}, port: Partial<AgentsPort> = {}) {
  const heard: [number, ConversationEvent][] = [];
  const told: AgentsEvent[] = [];
  const host = createAgentsHost(
    {
      place: {
        cwd: dir,
        startupOf: () => ({}),
        mcpServers: [],
        mcpIgnored: [],
        ...place,
      },
      runtimes: ['fake'],
      home: undefined,
      configHome: undefined,
      conversation: (_, emit) =>
        new Conversation(() => Promise.resolve(heldSession().session), emit),
    },
    {
      heard: (key, event) => heard.push([key, event]),
      closingHeard: () => {},
      told: (event) => told.push(event),
      stateOf: () => undefined,
      ...port,
    },
  );

  return { host, heard, told };
}

/** Main up on a held session, with children to open beside it. */
async function withMain(
  place: Partial<Place> = {},
  port: Partial<AgentsPort> = {},
) {
  const made = hosted(place, port);
  const key = made.host.sessions.start('fake')!;

  await until(() => made.heard.some(([, event]) => event.type === 'connected'));

  const open = (
    id: string,
    info: { team?: string; lead?: string; forkedFrom?: string } = {},
  ) =>
    made.host.sessions.openChild(
      { id, name: id, runtime: 'fake', openedAt: 1, ...info },
      (emit) =>
        new Conversation(() => Promise.resolve(heldSession().session), emit),
    )!;

  return { ...made, key, open };
}

describe('closing a child', () => {
  test('says so in order: its spend held, then closed, then the keys', async () => {
    const order: string[] = [];
    const { host, told, open } = await withMain(
      {},
      { stopCommand: (at) => order.push(`stop ${at}`) },
    );
    const child = open('one');

    host.dropChild(child);

    expect(order).toEqual([`stop ${child}`]);
    expect(told.map(({ type }) => type)).toEqual([
      'spend_closing',
      'session_closed',
      'agents_unfocused',
    ]);
    expect(told[1]).toEqual({
      type: 'session_closed',
      key: child,
      front: host.sessions.agents.main!.key,
    });

    await until(() => told.some(({ type }) => type === 'spend_closed'));
    await host.sessions.closeAll();
  });

  test("takes a lead's members first and forgets its run", async () => {
    const { host, told, open } = await withMain();
    const lead = open('lead', { team: 'bugfix' });
    const member = open('member', { team: 'bugfix', lead: 'lead' });

    host.runs.set('lead', {
      name: 'bugfix',
      place: 'project',
      file: 'bugfix.md',
      team: { lead: { agent: 'fake', instructions: '' }, members: [] },
      job: 'job',
    } as never);
    host.dropChild(lead);

    expect(
      told.flatMap((event) =>
        event.type === 'session_closed' ? [event.key] : [],
      ),
    ).toEqual([member, lead]);
    expect(host.runs.size).toBe(0);

    await host.sessions.closeAll();
  });

  test('settles a clear under way and what waited on it', async () => {
    const { host, open } = await withMain();
    const child = open('one');
    const settled: unknown[] = [];

    host.clearing.set(child, (failed, dropped) =>
      settled.push(failed, dropped),
    );
    host.early.set(child, [[{ name: 'main', reachable: true }, 'hello']]);
    host.dropChild(child);

    expect(settled).toEqual([
      'it was closed',
      [{ name: 'main', reachable: true }],
    ]);
    expect(host.early.has(child)).toBe(false);

    await host.sessions.closeAll();
  });

  test('a stale fold leaves its turn alone; a busy one is interrupted', async () => {
    const fold: { now?: FoldedSession } = {};
    const { host, open } = await withMain({}, { stateOf: () => fold.now });
    const interruptsOf = (child: number) => {
      const interrupted = { count: 0 };

      host.conversationAt(child)!.interrupt = () => {
        interrupted.count++;

        return true;
      };

      return interrupted;
    };

    const quiet = open('quiet');
    const quietOnes = interruptsOf(quiet);

    host.dropChild(quiet);

    expect(quietOnes.count).toBe(0);

    const busy = open('busy');
    const busyOnes = interruptsOf(busy);

    fold.now = {
      queue: [],
      transcript: { turn: { status: 'awaiting_permission' } } as never,
    };

    host.dropChild(busy);

    expect(busyOnes.count).toBe(1);

    await host.sessions.closeAll();
  });

  test('an unknown key does nothing', async () => {
    const { host, told } = await withMain();

    host.dropChild(99);

    expect(told).toEqual([]);

    await host.sessions.closeAll();
  });

  test("retired keys count down apart from every session's", () => {
    const { host } = hosted();

    expect([host.retiredKey(), host.retiredKey()]).toEqual([-1, -2]);
  });
});

describe('who a child answers to', () => {
  test('main for a child, its lead for a member, no one for a fork', async () => {
    const { host, key, open } = await withMain();

    open('lead', { team: 'bugfix' });
    open('member', { team: 'bugfix', lead: 'lead' });
    open('fork', { forkedFrom: 'main' });

    const of = (id: string) => host.childOf(key, id)!;

    expect(host.parentOf(of('lead'))).toBe(host.conversationAt(key));
    expect(host.parentOf(of('member'))).toBe(of('lead').conversation);
    expect(host.parentOf(of('fork'))).toBeUndefined();

    await host.sessions.closeAll();
  });

  test('says why no child answers: closed, left open or unknown', async () => {
    const fold: { now?: FoldedSession } = {};
    const { host, key, open } = await withMain({}, { stateOf: () => fold.now });

    host.dropChild(open('once'));

    fold.now = {
      queue: [],
      transcript: {
        entries: [
          {
            kind: 'left_open',
            agents: [{ name: 'gone' }, { name: 'crew', team: 'bugfix' }],
          },
        ],
      } as never,
    };

    expect(host.noChild(key, 'once')).toBe(
      'once is closed; open_agent starts another',
    );
    expect(host.noChild(key, 'gone')).toBe(
      'gone was closed when this session was left; open_agent starts another',
    );
    expect(host.noChild(key, 'crew')).toBe(
      'crew was closed when this session was left; run_team starts the team again',
    );
    expect(host.noChild(key, 'who')).toBe(
      'No agent who is open in this session; list_sessions names them',
    );

    await host.sessions.closeAll();
  });

  test('a lead that disconnects takes its members; its parent hears', async () => {
    const { host, key, told, open } = await withMain();
    const lead = open('lead', { team: 'bugfix' });
    const member = open('member', { team: 'bugfix', lead: 'lead' });
    const parent = host.conversationAt(key)!;
    const delivered: string[] = [];

    parent.deliver = (_, text) => {
      delivered.push(text);

      return 'sent';
    };

    host.tellEnded(key, lead, { type: 'disconnected' } as ConversationEvent);

    expect(
      told.flatMap((event) =>
        event.type === 'session_closed' ? [event.key] : [],
      ),
    ).toEqual([member]);
    expect(delivered).toHaveLength(1);
    expect(delivered[0]).toContain('lead');

    await host.sessions.closeAll();
  });
});

describe('the host, with no window', () => {
  test('its static imports reach neither OpenTUI nor React', async () => {
    const reached = [...(await packagesReached(HOST))];

    expect(reached.filter((name) => /^(react|@opentui)/.test(name))).toEqual(
      [],
    );
    expect(reached).toContain('@agentclientprotocol/sdk/unstable');
  });

  test('main started is its front, and its events reach the port', async () => {
    const { host, heard } = hosted();

    expect(host.front()).toBeUndefined();
    expect(host.conversation()).toBeUndefined();

    const key = host.sessions.start('fake');

    expect(key).toBeDefined();

    await until(() => heard.some(([, event]) => event.type === 'connected'));

    expect(host.front()?.main.key).toBe(key!);
    expect(host.conversationAt(key!)).toBe(host.conversation());
    expect(host.callerConversation(key!, undefined)).toBe(host.conversation());
    expect(heard.every(([from]) => from === key)).toBe(true);

    await host.sessions.closeAll();

    expect(host.front()).toBeUndefined();
  });

  test('an event of an agent let go goes to closingHeard', async () => {
    const closing: number[] = [];
    const { host, heard } = hosted(
      {},
      { closingHeard: (key) => closing.push(key) },
    );
    const key = host.sessions.start('fake')!;

    await until(() => heard.some(([, event]) => event.type === 'connected'));

    const told = heard.length;

    await host.sessions.closeAll();

    expect(closing.every((each) => each === key)).toBe(true);
    expect(heard).toHaveLength(told);
  });

  test('a refused runtime is offered nothing and nothing is read', async () => {
    const { host } = hosted({
      startupOf: () => ({ refused: 'not here' }),
    });

    expect(await host.offer('fake', true)).toEqual({ error: 'not here' });
  });

  test('a selection policy that throws is a refusal', async () => {
    const { host } = hosted({
      selectionPolicy: () => Promise.reject(new Error('bad file')),
    });

    expect(await host.policyNow()).toEqual({
      error:
        'Team selection settings could not be validated. Correct the settings before selecting a team.',
    });
  });

  test('team files are read now, each path as the host shows it', async () => {
    const { host } = hosted();
    const teams = join(dir, '.chord', 'teams');

    expect(await host.teamsAt(1)).toEqual([]);

    await mkdir(teams, { recursive: true });
    await writeFile(
      join(teams, 'bugfix.md'),
      '---\nlead:\n  agent: fake\n---\nLead it.\n',
    );

    const [found] = await host.teamsAt(1);

    expect(found?.name).toBe('bugfix');
    expect(found?.shown).toBe(join('.chord', 'teams', 'bugfix.md'));
  });
});
