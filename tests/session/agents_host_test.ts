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
import type { Caller, WindowView } from '../../src/server/tools.ts';
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

describe('messages between agents', () => {
  /** `conversation`'s `tell` kept: who said what, as `sent` answers. */
  const heardBy = (conversation: Conversation) => {
    const said: [string, string][] = [];

    conversation.tell = (from, text) => {
      said.push([from.name, text]);

      return 'sent';
    };

    return said;
  };

  const asMain = (key: number): Caller => ({
    role: 'person',
    key,
    window: {} as WindowView,
  });
  const asChild = (key: number, agent: string, team?: 'lead' | 'member') =>
    ({
      role: 'child',
      key,
      agent,
      ...(team === undefined ? {} : { team }),
      window: {} as WindowView,
    }) as Caller;

  test('main reaches its child, by id or name, as main', async () => {
    const { host, key, open } = await withMain();
    const child = open('one');
    const said = heardBy(host.conversationAt(child)!);

    expect(host.tell(asMain(key), 'one', 'hello')).toEqual({
      delivered: 'sent',
      to: 'one',
    });
    expect(said).toEqual([['main', 'hello']]);
    expect(host.tell(asMain(key), 'who', 'hello')).toEqual({
      error: 'No agent who is open in this session; list_sessions names them',
    });

    await host.sessions.closeAll();
  });

  test('a message to a child still starting waits with what it holds', async () => {
    const { host, key, open } = await withMain();
    const child = open('one');

    host.early.set(child, []);

    expect(host.tell(asMain(key), 'one', 'early')).toEqual({
      delivered: 'queued',
      to: 'one',
    });
    expect(host.early.get(child)).toEqual([
      [{ name: 'main', reachable: true }, 'early'],
    ]);

    await host.sessions.closeAll();
  });

  test('team agents reach their lead, members and main directly', async () => {
    const { host, key, open } = await withMain();
    const lead = open('lead', { team: 'bugfix' });
    const member = open('member', { team: 'bugfix', lead: 'lead' });
    const toLead = heardBy(host.conversationAt(lead)!);
    const toMember = heardBy(host.conversationAt(member)!);
    const toMain = heardBy(host.conversationAt(key)!);

    expect(host.tell(asChild(key, 'member', 'member'), 'lead', 'hi')).toEqual({
      delivered: 'sent',
      to: 'lead',
    });
    expect(host.tell(asChild(key, 'lead', 'lead'), 'member', 'go')).toEqual({
      delivered: 'sent',
      to: 'member',
    });
    expect(host.tell(asChild(key, 'lead', 'lead'), 'main', 'done')).toEqual({
      delivered: 'sent',
      to: 'main',
    });
    expect(toLead).toEqual([['member', 'hi']]);
    expect(toMember).toEqual([['lead', 'go']]);
    expect(toMain).toEqual([['lead', 'done']]);

    host.dropChild(member);

    expect(host.tell(asChild(key, 'lead', 'lead'), 'member', 'go')).toEqual({
      error: 'member is closed; open_agent opens it again',
    });

    await host.sessions.closeAll();
  });

  test("a child's message goes to main, and none once it closed", async () => {
    const { host, key, open } = await withMain();
    const child = open('one');
    const said = heardBy(host.conversationAt(key)!);

    expect(host.message(asChild(key, 'one'), 'report')).toEqual({
      delivered: 'sent',
    });
    expect(said).toEqual([['one', 'report']]);

    host.dropChild(child);

    expect(host.message(asChild(key, 'one'), 'late')).toEqual({
      error: 'You are closed; nothing more reaches your parent',
    });

    await host.sessions.closeAll();
  });
});

describe('closing and clearing by a tool', () => {
  const caller = (key: number): Caller => ({
    role: 'person',
    key,
    window: {} as WindowView,
  });

  test('close_agent closes, redraws, and says what closed or why not', async () => {
    let redraws = 0;
    const { host, key, open } = await withMain({}, { redraw: () => redraws++ });

    open('one');

    expect(host.closeAgent(caller(key), 'one')).toEqual({ closed: 'one' });
    expect(redraws).toBe(1);
    expect(host.closeAgent(caller(key), 'one')).toEqual({
      error: 'one is closed; open_agent starts another',
    });
    expect(redraws).toBe(1);

    await host.sessions.closeAll();
  });

  test('a clear asks the driver for the queue, holds what comes, settles once up', async () => {
    const order: string[] = [];
    const { host, key, told, open } = await withMain(
      {},
      {
        queueBack: (at, typed) => order.push(`queue ${at} ${typed}`),
        stopCommand: (at) => order.push(`stop ${at}`),
      },
    );
    const child = open('one');

    await until(() => host.conversationAt(child)?.session !== undefined);

    const clearing = host.clearAgent(caller(key), 'one');

    expect(order).toEqual([`queue ${child} undefined`, `stop ${child}`]);
    expect(host.early.get(child)).toEqual([]);
    expect(told.at(-1)).toMatchObject({
      type: 'spend_closing',
      from: child,
      place: { name: 'one', kind: 'agent', runtime: 'fake' },
    });

    expect(
      host.clearedHeard(child, { type: 'connected' } as ConversationEvent),
    ).toBe(true);
    expect(await clearing).toEqual({ cleared: 'one', id: 'one' });
    expect(host.early.has(child)).toBe(false);

    await host.sessions.closeAll();
  });

  test('a second clear under way is refused', async () => {
    const { host, key, open } = await withMain();
    const child = open('one');

    await until(() => host.conversationAt(child)?.session !== undefined);

    const first = host.clearAgent(caller(key), 'one');

    expect(await host.clearAgent(caller(key), 'one')).toEqual({
      error: 'Could not clear one: it is being cleared already',
    });

    host.clearedHeard(child, { type: 'connected' } as ConversationEvent);
    await first;
    await host.sessions.closeAll();
  });

  test('what waited on a clear that fails is said to be dropped', async () => {
    const { host, key, open } = await withMain();
    const child = open('one');

    await until(() => host.conversationAt(child)?.session !== undefined);

    const clearing = host.clearAgent(caller(key), 'one');

    host.early.get(child)!.push([{ name: 'lead', reachable: true }, 'late']);
    host.clearedHeard(child, {
      type: 'connect_failed',
      message: 'no room',
    } as ConversationEvent);

    expect(await clearing).toEqual({
      error:
        'Could not clear one: no room. 1 queued message from lead was not delivered.',
    });

    await host.sessions.closeAll();
  });

  test("the person's clear tells its parent", async () => {
    const { host, key, open } = await withMain();
    const child = open('one');
    const said: string[] = [];

    await until(() => host.conversationAt(child)?.session !== undefined);

    host.conversationAt(key)!.deliver = (_, text) => {
      said.push(text);

      return 'sent';
    };

    const clearing = host.clearByPerson(host.childOf(key, 'one')!);

    host.clearedHeard(child, { type: 'connected' } as ConversationEvent);

    expect(await clearing).toBeUndefined();
    expect(said).toHaveLength(1);
    expect(said[0]).toStartWith(
      "The person cleared one's context (fake, id one)",
    );

    await host.sessions.closeAll();
  });
});
