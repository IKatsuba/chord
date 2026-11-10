import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import process from 'node:process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert';
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  createAgentsHost,
  type AgentsEvent,
  type AgentsHostOptions,
  type AgentsPort,
  type FoldedSession,
  type TeamRunNow,
} from '../../src/session/agents_host.ts';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import type { Place } from '../../src/session/place.ts';
import type { Caller, WindowView } from '../../src/server/tools.ts';
import { openSession, type Session } from '../../src/session/session.ts';
import { foldEvent } from '../../src/acp/host_fold.ts';
import { findSubagent } from '../../src/session/transcript/subagents.ts';
import { LONG_TASK_ARGS } from '../fixtures/fake_agent/scenarios/tasks.ts';
import { MAX_CHILDREN } from '../../src/session/window_agents.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
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

/** A held session the host can ask for all it offers. */
const held = () =>
  Object.assign(heldSession().session, { efforts: () => undefined });

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), 'chord-agents-host-'));
});

afterEach(async () => {
  await rm(dir, { recursive: true });
});

/** A host on held sessions, its place a fresh directory, and what it told. */
function hosted(
  place: Partial<Place> = {},
  port: Partial<AgentsPort> = {},
  options: Partial<AgentsHostOptions> = {},
) {
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
      stateDir: join(dir, 'state'),
      open: () => Promise.resolve(held()),
      server: undefined,
      resume: undefined,
      ...options,
    },
    {
      heard: (key, event) => heard.push([key, event]),
      replayed: (_, replay) => replay(),
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
  options: Partial<AgentsHostOptions> = {},
) {
  const made = hosted(place, port, options);
  const key = made.host.sessions.start('fake')!;

  await until(() => made.heard.some(([, event]) => event.type === 'connected'));

  const open = (
    id: string,
    info: { team?: string; lead?: string; forkedFrom?: string } = {},
  ) =>
    made.host.sessions.openChild(
      { id, name: id, runtime: 'fake', openedAt: 1, ...info },
      (emit) => new Conversation(() => Promise.resolve(held()), emit),
    )!;

  return { ...made, key, open };
}

describe('main servers', () => {
  const server = (name: string) => ({
    name,
    command: name,
    args: [],
    env: [],
  });

  test("main takes them in place of the place's; a child, the place's", async () => {
    const opened: (readonly { readonly name: string }[] | undefined)[] = [];
    const { host, key } = await withMain(
      {
        mcpServers: [{ server: server('settings'), from: 'file' }],
      },
      {},
      {
        mainServers: [server('client')],
        open: (options) => {
          opened.push(options.mcpServers);

          return Promise.resolve(held());
        },
      },
    );

    expect(opened[0]?.map(({ name }) => name)).toEqual(['client']);

    await host.openAgent(key, { agent: 'fake', prompt: 'hi' });

    expect(opened[1]?.map(({ name }) => name)).toEqual(['settings']);

    await host.sessions.closeAll();
  });

  test("none given, main takes the place's", async () => {
    const opened: (readonly { readonly name: string }[] | undefined)[] = [];
    const { host } = await withMain(
      {
        mcpServers: [{ server: server('settings'), from: 'file' }],
      },
      {},
      {
        open: (options) => {
          opened.push(options.mcpServers);

          return Promise.resolve(held());
        },
      },
    );

    expect(opened[0]?.map(({ name }) => name)).toEqual(['settings']);

    await host.sessions.closeAll();
  });
});

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

describe('opening a child', () => {
  const onFake = {
    place: {
      startupOf: () => ({ agentCommand: fakeAgentCommand() }),
    },
    options: { open: openSession },
  };
  const prompt = { agent: 'fake', prompt: 'hello' };

  test('an unknown runtime, a bad name and a closed parent are refused', async () => {
    const { host, key } = await withMain();
    const parent = host.conversationAt(key);

    expect(
      await host.startRefusal(
        key,
        parent,
        { agent: 'other', prompt: '' },
        'agent',
      ),
    ).toBe('No agent named other; chord knows fake');
    expect(
      await host.startRefusal(
        key,
        parent,
        { ...prompt, name: 'a\nb' },
        'agent',
      ),
    ).toStartWith('An agent name ');
    expect(await host.startRefusal(key, undefined, prompt, 'task')).toBe(
      'This session is closing; no task can start from it',
    );
    expect(await host.openAgent(99, prompt)).toEqual({
      error: 'This session is closing; no agent can start from it',
    });

    await host.sessions.closeAll();
  });

  test('a caller already let go opens nothing', async () => {
    const { host, key, told } = await withMain();
    const stale: Caller = {
      role: 'person',
      key,
      window: {} as WindowView,
      launch: {
        valid: () => false,
        signal: () => new AbortController().signal,
      },
    };

    expect(host.stale(stale)).toBe(true);
    expect(await host.openAgent(key, prompt, stale)).toEqual(host.STALE);
    expect(told).toEqual([]);

    await host.sessions.closeAll();
  });

  test('its state is told before its first event, and its first prompt runs', async () => {
    const before: number[] = [];
    const { host, key, heard } = await withMain(
      onFake.place,
      {
        told: (event) => {
          if (event.type === 'agent_opened') {
            before.push(heard.filter(([at]) => at === event.key).length);
          }
        },
      },
      onFake.options,
    );
    const opened = await host.openAgent(key, { ...prompt, name: 'one' });

    assert(!('error' in opened));

    const child = host.childOf(key, opened.id)!;

    expect(opened).toMatchObject({ name: 'one', agent: 'fake' });
    expect(before).toEqual([0]);

    await until(() =>
      heard.some(([at, event]) => at === child.key && event.type === 'result'),
    );

    expect(host.early.has(child.key)).toBe(false);

    await host.sessions.closeAll();
  });

  test('a launch cancelled before its first job is refused and dropped', async () => {
    const { host, key, heard } = await withMain(
      onFake.place,
      {},
      onFake.options,
    );
    const stop = new AbortController();
    const refusals: string[] = [];
    const launch = host.captureLaunch(key, {
      role: 'person',
      key,
      window: {} as WindowView,
      signal: stop.signal,
    });

    expect(launch.valid()).toBe(true);

    const { validated } = host.startChild(key, prompt, {
      name: 'one',
      parent: () => host.conversationAt(key),
      from: host.MAIN,
      asked: 'a test',
      launch,
      refused: (reason) => refusals.push(reason),
    });

    stop.abort();

    expect(launch.valid()).toBe(false);
    expect(await validated).toBe(
      'Cancelled before its first job; the attempted agent is closing.',
    );
    expect(refusals).toHaveLength(1);
    expect(host.childOf(key, 'one')).toBeUndefined();
    expect(heard.filter(([, event]) => event.type === 'result')).toEqual([]);

    await host.sessions.closeAll();
  });

  test('a full session refuses another', async () => {
    const { host, key, open } = await withMain();

    for (let index = 0; index < MAX_CHILDREN; index++) {
      open(`child-${index}`);
    }

    expect(host.fullRefusal(key)).toBe(
      `This session has ${MAX_CHILDREN} agents open; close_agent one first`,
    );
    expect(host.fullRefusal(99)).toBe('This session has closed');

    await host.sessions.closeAll();
  });

  test('a task runs under its parent and goes once it ends', async () => {
    const { host, key } = await withMain(onFake.place, {}, onFake.options);
    const answer = await host.spawn(
      { role: 'person', key, window: {} as WindowView },
      prompt,
    );

    assert(!('error' in answer));

    expect(host.children.has(answer.id)).toBe(true);
    expect(host.conversationAt(key)!.task(answer.id)?.running).toBe(true);

    await until(() => !host.children.has(answer.id));
    await host.sessions.closeAll();
  });
});

describe('running a team', () => {
  const onFake = {
    place: {
      startupOf: () => ({ agentCommand: fakeAgentCommand() }),
    },
    options: { open: openSession },
  };
  const saved = async (text: string) => {
    const teams = join(dir, '.chord', 'teams');

    await mkdir(teams, { recursive: true });
    await writeFile(join(teams, 'bugfix.md'), text);
  };

  const crew = `---
description: A crew
lead:
  agent: fake
members:
  - name: coder
    role: Code
    agent: fake
    instructions: Code it.
---
Lead it.
`;
  const caller = (key: number, agent: string): Caller => ({
    role: 'child',
    key,
    agent,
    team: 'lead',
    window: {} as WindowView,
  });

  test('refuses a team not found, and a file that fails its check', async () => {
    const { host, key } = await withMain();

    expect(
      await host.runTeamAt(
        key,
        { team: 'who', job: 'j' },
        'list_teams lists them',
      ),
    ).toEqual({ error: 'No team named who · list_teams lists them' });

    await saved('not a team');

    const answer = await host.runTeamAt(
      key,
      { team: 'bugfix', job: 'j' },
      'list_teams lists them',
    );

    assert('error' in answer);
    expect(answer.error).toStartWith(
      `${join('.chord', 'teams', 'bugfix.md')} is not a team chord can run:`,
    );

    await host.sessions.closeAll();
  });

  test('a run opens its lead as a child of main, and keeps the file as read', async () => {
    const { host, key, heard } = await withMain(
      onFake.place,
      {},
      onFake.options,
    );

    await saved(crew);

    const answer = await host.runTeamAt(
      key,
      { team: 'bugfix', job: 'Fix it.' },
      'list_teams lists them',
    );

    assert(!('error' in answer));

    const lead = host.childOf(key, answer.ran.id)!;

    expect(answer.ran).toMatchObject({ name: 'bugfix', team: 'bugfix' });
    expect(lead.team).toBe('bugfix');
    expect(host.runs.get(lead.id)?.job).toBe('Fix it.');

    await until(() =>
      heard.some(([at, event]) => at === lead.key && event.type === 'result'),
    );

    // A file changed since does not change a running team.
    await saved('not a team');

    expect(
      host.runs.get(lead.id)?.team.members.map(({ name }) => name),
    ).toEqual(['coder']);

    await host.sessions.closeAll();
  });

  test('a launch already cancelled opens nothing', async () => {
    const { host, key, told } = await withMain();
    const launch = host.captureLaunch(key);

    await saved(crew);
    await host.sessions.closeAll();

    expect(
      await host.runTeamAt(key, { team: 'bugfix', job: 'j' }, 'lists', launch),
    ).toEqual({ error: 'This launch was cancelled; no run started.' });
    expect(told.some(({ type }) => type === 'agent_opened')).toBe(false);
  });

  test('a lead opens a member of its file, once, and no other', async () => {
    const { host, key } = await withMain(onFake.place, {}, onFake.options);

    await saved(crew);

    const answer = await host.runTeamAt(
      key,
      { team: 'bugfix', job: 'Fix it.' },
      'lists',
    );

    assert(!('error' in answer));

    const lead = caller(key, answer.ran.id);

    // A lead still starting has no session to open a member from.
    await until(
      () =>
        host.childOf(key, answer.ran.id)?.conversation.session !== undefined,
    );

    expect(await host.openMember(lead, { member: 'who', prompt: 'p' })).toEqual(
      {
        error: 'Team bugfix has no member who; its members are coder',
      },
    );

    const opened = await host.openMember(lead, {
      member: 'coder',
      prompt: 'Code.',
    });

    assert(!('error' in opened));

    expect(opened.name).toBe('coder');
    expect(host.childOf(key, 'coder')?.lead).toBe(answer.ran.id);
    expect(
      await host.openMember(lead, { member: 'coder', prompt: 'Again.' }),
    ).toEqual({ error: 'coder is open; send_message reaches it' });

    await host.sessions.closeAll();
  });

  test('a closed lead opens no members', async () => {
    const { host, key } = await withMain();

    expect(
      await host.openMember(caller(key, 'gone'), {
        member: 'coder',
        prompt: 'p',
      }),
    ).toEqual({ error: 'You are closed; you open no members' });

    await host.sessions.closeAll();
  });

  test('a selection of a saved team that fails its check starts nothing', async () => {
    const { host, key, told } = await withMain();

    await saved('not a team');

    expect(
      await host.runTeamAt(
        key,
        { team: 'bugfix', job: 'j', selection: { reason: 'a test' } },
        'lists',
      ),
    ).toEqual({ error: 'The saved team is invalid. No run started.' });
    expect(told).toEqual([]);

    await host.sessions.closeAll();
  });
});

describe("what chord's server reads", () => {
  test('main opens through the host, and each event is watched before it is heard', async () => {
    const order: string[] = [];
    const { host } = hosted(
      {},
      {
        watched: (id, _, event) => {
          if (event.type === 'connected') {
            order.push(`watched ${id}`);
          }
        },
        heard: (at, event) => {
          if (event.type === 'connected') {
            order.push(`heard ${at}`);
          }
        },
      },
    );
    const key = host.sessions.start('fake')!;

    await until(() => order.length === 2);

    expect(order).toEqual([`watched main:${key}`, `heard ${key}`]);

    await host.sessions.closeAll();
  });

  test('the first session resumes what was asked, the next what is picked', async () => {
    const asked: unknown[] = [];
    const resume = { agent: 'fake', sessionId: 'old', cwd: dir } as const;
    const { host, heard } = hosted(
      {},
      {},
      {
        resume,
        open: (options) => {
          asked.push(options.resume);

          return Promise.resolve(held());
        },
      },
    );
    const key = host.sessions.start('fake')!;

    await until(() => heard.some(([, event]) => event.type === 'connected'));

    const next = { ...resume, sessionId: 'next' };

    host.resumeNext(next);
    await host.conversationAt(key)!.clear();
    await until(() => asked.length === 2);

    expect(asked).toEqual([resume, next]);

    await host.sessions.closeAll();
  });

  test('a replay goes through the port', async () => {
    const replays: number[] = [];
    const session = Object.assign(held(), {
      history: () => [{ type: 'prompt', turnId: 'old', text: 'past', at: 1 }],
    });
    const { host, heard } = hosted(
      {},
      {
        replayed: (key, replay) => {
          replays.push(key);
          replay();
        },
      },
      { open: () => Promise.resolve(session as never) },
    );
    const key = host.sessions.start('fake')!;

    await until(() => heard.some(([, event]) => event.type === 'connected'));

    expect(replays).toEqual([key]);
    expect(heard.some(([, event]) => event.type === 'prompt')).toBe(true);

    await host.sessions.closeAll();
  });

  test('a saved setting is told with what the driver can take up', () => {
    const { host, told } = hosted();

    host.view.settingSaved(['theme'], { set: 'light' });

    expect(told).toEqual([
      { type: 'setting_saved', picked: { key: 'theme', theme: 'light' } },
    ]);
  });

  test('sessions lists main with its children and each fork beside it', async () => {
    const { host, key, open } = await withMain();

    open('one');
    open('fork', { forkedFrom: 'main' });

    expect(host.view.sessions()).toMatchObject([
      { key, runtime: 'fake', children: [{ id: 'one', name: 'one' }] },
      { runtime: 'fake', children: [] },
    ]);

    await host.sessions.closeAll();
  });

  test('a caller already let go is refused by every tool that acts', async () => {
    const { host, key, told } = await withMain();
    const stale: Caller = {
      role: 'child',
      key,
      agent: 'gone',
      window: host.view,
      launch: {
        valid: () => false,
        signal: () => new AbortController().signal,
      },
    };

    expect(host.view.tell(stale, 'x', 'y', () => {})).toEqual(host.STALE);
    expect(host.view.message(stale, 'y', () => {})).toEqual(host.STALE);
    expect(host.view.close(stale, 'x')).toEqual(host.STALE);
    expect(await host.view.clear(stale, 'x')).toEqual(host.STALE);
    expect(
      await host.view.spawn(stale, { agent: 'fake', prompt: 'p' }),
    ).toEqual(host.STALE);
    expect(
      await host.view.openMember(stale, { member: 'm', prompt: 'p' }),
    ).toEqual(host.STALE);
    expect(host.view.served(stale, {} as never)).toBeUndefined();
    expect(told).toEqual([]);

    await host.sessions.closeAll();
  });

  test('the settings box is held by one change at a time', () => {
    const { host } = hosted();
    const release = host.view.claimSettingsBox();

    expect(release).toBeDefined();
    expect(host.view.claimSettingsBox()).toBeUndefined();

    release!();

    expect(host.view.claimSettingsBox()).toBeDefined();
  });
});

describe('the typed commands', () => {
  const onFake = {
    place: {
      startupOf: () => ({ agentCommand: fakeAgentCommand() }),
    },
    options: { open: openSession },
  };
  const words = {
    whichRun: 'which',
    closedLead: 'lead words',
    closedRun: 'run words',
    noRun: 'the list under the prompt names them',
  };
  const crew = `---
description: A crew
lead:
  agent: fake
members:
  - name: coder
    role: Code
    agent: fake
    instructions: Code it.
---
Lead it.
`;
  const saved = async (text = crew) => {
    const teams = join(dir, '.chord', 'teams');

    await mkdir(teams, { recursive: true });
    await writeFile(join(teams, 'bugfix.md'), text);
  };

  const said = (text: string) => ({
    kind: 'said' as const,
    text,
    failed: true,
  });

  test('/team lists the files, the runs and both directories', async () => {
    const { host, open } = await withMain();

    await saved();
    open('bugfix', { team: 'bugfix' });

    const listing = await host.listTeams();

    expect(listing?.teams.map(({ name }) => name)).toEqual(['bugfix']);
    expect(listing?.runs).toMatchObject([{ team: 'bugfix', name: 'bugfix' }]);
    expect(listing?.dirs).toEqual({ project: join('.chord', 'teams') });

    await host.sessions.closeAll();

    expect(await host.listTeams()).toBeUndefined();
  });

  test('/team run refuses an unknown team and starts a known one', async () => {
    const { host, key } = await withMain(onFake.place, {}, onFake.options);

    expect(await host.runTyped('who', 'job')).toEqual(
      said('No team named who · /team lists them'),
    );

    await saved();

    const shown = await host.runTyped('bugfix', 'Fix it.');

    expect(shown).toMatchObject({
      kind: 'ran',
      call: { tool: 'run_team', input: { team: 'bugfix', job: 'Fix it.' } },
    });
    expect(host.childOf(key, 'bugfix')?.team).toBe('bugfix');

    await host.sessions.closeAll();
  });

  test('/new picks the agent opened, shows it, and sends it nothing', async () => {
    const shows: number[] = [];
    const { host, key } = await withMain(onFake.place, {}, onFake.options);
    const shown = await host.newTyped('', () =>
      shows.push(host.sessions.agents.picked),
    );

    expect(shown).toMatchObject({
      kind: 'ran',
      call: { tool: 'open_agent', input: { agent: 'fake', typed: '/new' } },
    });

    const [child] = host.front()!.children;

    expect(shows).toEqual([child!.key]);
    expect(host.sessions.agents.picked).toBe(child!.key);
    expect(host.sessions.agents.main!.key).toBe(key);
    expect(host.early.get(child!.key) ?? []).toEqual([]);

    await host.sessions.closeAll();
  });

  test('/new refused says why and shows nothing', async () => {
    const shows: number[] = [];
    const { host } = await withMain();

    expect(await host.newTyped('other', () => shows.push(1))).toEqual(
      said('No agent named other; chord knows fake'),
    );
    expect(shows).toEqual([]);

    await host.sessions.closeAll();
  });

  test('/new opens an idle child after an established main agent exits', async () => {
    const exited = Promise.withResolvers<void>();
    let first = true;
    const { host, key, heard } = await withMain(
      {},
      {},
      {
        open: () => {
          const session = held();

          if (first) {
            first = false;

            return Promise.resolve({ ...session, exited: exited.promise });
          }

          return Promise.resolve(session);
        },
      },
    );

    try {
      exited.resolve();
      await until(() =>
        heard.some(([, event]) => event.type === 'disconnected'),
      );

      const parent = host.conversationAt(key);

      expect(parent?.launchSignal.aborted).toBe(true);
      expect(parent?.session).toBeDefined();

      const shown = await host.newTyped('', () => {});

      expect(shown).toMatchObject({
        kind: 'ran',
        call: { tool: 'open_agent', input: { agent: 'fake', typed: '/new' } },
      });
      expect(host.sessions.agents.children).toHaveLength(1);
      expect(host.conversationAt(key)).toBe(parent);
      expect(
        host.early.get(host.sessions.agents.children[0]!.key) ?? [],
      ).toEqual([]);
    } finally {
      await host.sessions.closeAll();
    }
  });

  test("/team stop says what it did before main is told, in the host's words", async () => {
    const order: string[] = [];
    const { host, key, open } = await withMain();

    open('bugfix', { team: 'bugfix' });
    open('coder', { team: 'bugfix', lead: 'bugfix' });

    host.conversationAt(key)!.deliver = (_, text) => {
      order.push(`main: ${text.split(':')[0]}`);

      return 'sent';
    };

    host.stopTyped(
      'bugfix',
      (shown) => order.push(`shown: ${shown.kind}`),
      words,
    );

    expect(order).toEqual([
      'shown: said',
      'main: The person closed team bugfix',
    ]);
    expect(host.childOf(key, 'bugfix')).toBeUndefined();
    expect(host.childOf(key, 'coder')).toBeUndefined();

    const stopped: unknown[] = [];

    host.stopTyped('bugfix', (shown) => stopped.push(shown), words);

    expect(stopped).toEqual([
      said(
        'No run named bugfix is open · the list under the prompt names them',
      ),
    ]);

    await host.sessions.closeAll();
  });

  test('closing by the person redraws between closing and telling', async () => {
    const order: string[] = [];
    const { host, key, open } = await withMain(
      {},
      { redraw: () => order.push('redraw') },
    );

    open('one');

    host.conversationAt(key)!.deliver = (_, text) => {
      order.push(text);

      return 'sent';
    };

    host.conversationAt(key)!.agentClosed = () => {
      order.push('closed');
    };

    expect(host.closeByPerson(host.childOf(key, 'one')!)).toEqual([]);
    expect(order).toEqual([
      'closed',
      'redraw',
      'The person closed one (fake, id one). It takes no more messages; open_agent starts another.',
    ]);

    await host.sessions.closeAll();
  });

  test('/team show reads the file, a run as it was read, or says why not', async () => {
    const { host, key, open } = await withMain(
      onFake.place,
      {},
      onFake.options,
    );

    const never = () => {
      throw new Error('no run to fill in');
    };

    expect(await host.showTyped('who', never)).toEqual(
      said('No team named who · /team lists them'),
    );

    await saved();

    expect(await host.showTyped('bugfix', never)).toMatchObject({
      kind: 'show',
      name: 'bugfix',
      file: join('.chord', 'teams', 'bugfix.md'),
    });

    const answer = await host.runTeamAt(
      key,
      { team: 'bugfix', job: 'Fix it.' },
      'lists',
    );

    assert(!('error' in answer));

    open('coder', { team: 'bugfix', lead: answer.ran.id });

    // The running file wins over what was saved since.
    await saved('not a team');

    const filled: TeamRunNow[] = [];
    const shown = host.showTyped('bugfix', (now) => {
      filled.push(now);

      return {
        kind: 'show',
        name: 'bugfix',
        file: now.file,
        team: now.run.team,
      };
    });

    // Filled in at once for an open run: nothing queued can come between
    // what the host read of it and what the driver reads.
    expect(filled).toHaveLength(1);
    expect(filled[0]!.lead.id).toBe(answer.ran.id);
    expect(filled[0]!.run.job).toBe('Fix it.');
    expect(filled[0]!.members.map(({ name }) => name)).toEqual(['coder']);
    expect((await shown).kind).toBe('show');

    await host.sessions.closeAll();
  });
});

describe('closing a task by close_agent (CHD-590)', () => {
  /** Whether the process group `pid` leads still has a process in it. */
  const groupAlive = (pid: number) => {
    try {
      return process.kill(-pid, 0);
    } catch {
      return false;
    }
  };

  /** Main on the fake, its events folded, and every session it opened. */
  async function onFake() {
    const opened: Session[] = [];
    const fold = (key: number) =>
      made.heard.reduce<FoldedSession | undefined>(
        (folded, [at, event]) =>
          at === key ? foldEvent(folded, event) : folded,
        undefined,
      );
    const made = await withMain(
      { startupOf: () => ({ agentCommand: fakeAgentCommand() }) },
      { stateOf: (key) => fold(key) },
      {
        open: async (options) => {
          const session = await openSession(options);

          opened.push(session);

          return session;
        },
      },
    );
    const person: Caller = {
      role: 'person',
      key: made.key,
      window: {} as WindowView,
    };
    const spawn = async (by: Caller = person, name = LONG_TASK_ARGS.name) => {
      const answer = await made.host.spawn(by, { ...LONG_TASK_ARGS, name });

      assert(!('error' in answer));

      return answer.id;
    };

    /** The task's own fake agent, once its job has reached it. */
    const working = async (id: string, key = made.key) => {
      await until(
        () =>
          findSubagent(fold(key)?.transcript.entries ?? [], id)?.entries.some(
            (entry) => entry.kind === 'assistant',
          ) === true,
      );

      const pid = [...opened.at(-1)!.agentPids][0];

      assert(pid !== undefined);

      return pid;
    };

    return { ...made, fold, person, spawn, working };
  }

  test('a running task stopped by its id ends with its process group, the line naming main', async () => {
    const { host, key, fold, person, spawn, working } = await onFake();
    const id = await spawn();
    const pid = await working(id);

    expect(groupAlive(pid)).toBe(true);
    expect(host.closeAgent(person, id)).toEqual({ closed: 'Watch the build' });

    await until(() => !groupAlive(pid));

    expect(host.conversationAt(key)!.task(id)).toBeUndefined();
    expect(
      findSubagent(fold(key)!.transcript.entries, id)?.task?.stoppedWith,
    ).toEqual({ agent: 'main' });

    await host.sessions.closeAll();
  });

  test('a task already ended is said to have ended, by its id or its name', async () => {
    const { host, person, spawn, working } = await onFake();
    const id = await spawn();

    await working(id);

    expect(host.closeAgent(person, 'Watch the build')).toEqual({
      closed: 'Watch the build',
    });
    await until(() => host.conversationAt(person.key)!.task(id) === undefined);
    expect(host.closeAgent(person, id)).toEqual({ ended: 'Watch the build' });
    expect(host.closeAgent(person, 'Watch the build')).toEqual({
      ended: 'Watch the build',
    });

    await host.sessions.closeAll();
  });

  test('a task ended before anything is drawn is said to have ended, not unknown', async () => {
    // Nothing folded: the window has drawn none of the task's blocks.
    const { host, key } = await withMain(
      { startupOf: () => ({ agentCommand: fakeAgentCommand() }) },
      {},
      { open: openSession },
    );
    const person: Caller = {
      role: 'person',
      key,
      window: {} as WindowView,
    };
    const answer = await host.spawn(person, LONG_TASK_ARGS);

    assert(!('error' in answer));

    // Closed while it starts, it ends there and then.
    expect(host.closeAgent(person, answer.id)).toEqual({
      closed: 'Watch the build',
    });
    expect(host.conversationAt(key)!.task(answer.id)).toBeUndefined();
    expect(host.closeAgent(person, answer.id)).toEqual({
      ended: 'Watch the build',
    });
    expect(host.closeAgent(person, 'Watch the build')).toEqual({
      ended: 'Watch the build',
    });

    await host.sessions.closeAll();
  });

  test('a task ended before a /clear does not share its name with one after', async () => {
    const { host, key } = await withMain(
      { startupOf: () => ({ agentCommand: fakeAgentCommand() }) },
      {},
      { open: openSession },
    );
    const person: Caller = {
      role: 'person',
      key,
      window: {} as WindowView,
    };
    const before = await host.spawn(person, LONG_TASK_ARGS);

    assert(!('error' in before));
    expect(host.closeAgent(person, before.id)).toEqual({
      closed: 'Watch the build',
    });

    const conversation = host.conversationAt(key)!;
    const old = conversation.session;

    await conversation.clear();
    // The fresh session up, which a task starts from.
    await until(
      () => conversation.session !== undefined && conversation.session !== old,
    );

    const after = await host.spawn(person, LONG_TASK_ARGS);

    assert(!('error' in after));
    expect(host.closeAgent(person, 'Watch the build')).toEqual({
      closed: 'Watch the build',
    });
    expect(host.closeAgent(person, before.id)).toEqual({
      error: `No agent ${before.id} is open in this session; list_sessions names them`,
    });

    await host.sessions.closeAll();
  });

  test('a name two of the caller’s tasks have is refused, naming their ids', async () => {
    const { host, person, spawn } = await onFake();
    const one = await spawn();
    const two = await spawn();

    expect(host.closeAgent(person, 'Watch the build')).toEqual({
      error: `2 of your tasks are named Watch the build; close_agent one by its id: ${one} and ${two}`,
    });
    expect(host.conversationAt(person.key)!.task(one)?.running).toBe(true);
    expect(host.conversationAt(person.key)!.task(two)?.running).toBe(true);

    await host.sessions.closeAll();
  });

  test("a child closes only its own tasks: not another's, nor a long-lived agent", async () => {
    const { host, key, open, person, spawn, working } = await onFake();

    const helper = open('helper');

    open('other');

    const child: Caller = {
      role: 'child',
      key,
      agent: 'helper',
      window: {} as WindowView,
    };
    const mains = await spawn(person, 'Main task');
    const own = await spawn(child, 'Own task');

    await working(own, helper);

    expect(host.closeAgent(child, mains)).toEqual({
      error: `No task ${mains} of yours; spawn_task's answer names them`,
    });
    expect(host.closeAgent(child, 'Main task')).toEqual({
      error: "No task Main task of yours; spawn_task's answer names them",
    });
    expect(host.closeAgent(child, 'other')).toEqual({
      error: "No task other of yours; spawn_task's answer names them",
    });
    expect(host.closeAgent(person, own)).toEqual({
      error: `No agent ${own} is open in this session; list_sessions names them`,
    });
    expect(host.conversationAt(key)!.task(mains)?.running).toBe(true);
    expect(host.closeAgent(child, own)).toEqual({ closed: 'Own task' });
    expect(host.closeAgent(person, 'other')).toEqual({ closed: 'other' });

    await host.sessions.closeAll();
  });
});

describe('CHD-590 tester: task ownership and ended identities', () => {
  test('a fake team lead and member close only their own tasks, keeping their names', async () => {
    const { host, key, heard } = await withMain(
      { startupOf: () => ({ agentCommand: fakeAgentCommand() }) },
      {},
      { open: openSession },
    );

    try {
      const teams = join(dir, '.chord', 'teams');

      await mkdir(teams, { recursive: true });
      await writeFile(
        join(teams, 'bugfix.md'),
        await readFile(
          new URL('../fixtures/teams/fake/bugfix.md', import.meta.url),
        ),
      );

      const run = await host.runTeamAt(
        key,
        { team: 'bugfix', job: 'text' },
        'list_teams lists them',
      );

      assert(!('error' in run));

      const lead: Caller = {
        role: 'child',
        key,
        agent: run.ran.id,
        team: 'lead',
        window: host.view,
      };

      await until(
        () => host.childOf(key, run.ran.id)?.conversation.session !== undefined,
      );

      const opened = await host.openMember(lead, {
        member: 'coder',
        prompt: 'text',
      });

      assert(!('error' in opened));

      const member: Caller = {
        role: 'child',
        key,
        agent: opened.id,
        team: 'member',
        window: host.view,
      };

      await until(
        () => host.childOf(key, opened.id)?.conversation.session !== undefined,
      );

      const tasks = [];

      for (const caller of [lead, member]) {
        const task = await host.spawn(caller, LONG_TASK_ARGS);

        assert(!('error' in task));
        tasks.push(task);
      }

      const [leadTask, memberTask] = tasks;

      assert(leadTask && memberTask);
      expect(host.closeAgent(lead, memberTask.id)).toHaveProperty('error');
      expect(host.closeAgent(member, leadTask.id)).toHaveProperty('error');

      for (const [caller, task] of [
        [lead, leadTask],
        [member, memberTask],
      ] as const) {
        expect(host.closeAgent(caller, task.id)).toEqual({
          closed: LONG_TASK_ARGS.name,
        });

        const child = host.childOf(key, caller.agent!)!;

        await until(() => child.conversation.task(task.id) === undefined);
        expect(host.closeAgent(caller, task.id)).toEqual({
          ended: LONG_TASK_ARGS.name,
        });
        expect(host.closeAgent(caller, LONG_TASK_ARGS.name)).toEqual({
          ended: LONG_TASK_ARGS.name,
        });

        const folded = heard.reduce<FoldedSession | undefined>(
          (state, [at, event]) =>
            at === child.key ? foldEvent(state, event) : state,
          undefined,
        );

        expect(
          findSubagent(folded?.transcript.entries ?? [], task.id)?.task
            ?.stoppedWith,
        ).toEqual({ agent: child.name });
      }
    } finally {
      await host.sessions.closeAll();
    }
  });

  test('a fork cannot be mistaken for a task or closed by its former parent', async () => {
    const { host, key, open } = await withMain();
    const fork = open('fork', { forkedFrom: 'main' });
    const caller: Caller = { role: 'person', key, window: host.view };

    try {
      expect(host.closeAgent(caller, 'fork')).toHaveProperty('error');
      expect(host.conversationAt(fork)).toBeDefined();
    } finally {
      await host.sessions.closeAll();
    }
  });

  test('an ended task and a running namesake require an id, leaving the live task alone', async () => {
    const { host, key } = await withMain(
      { startupOf: () => ({ agentCommand: fakeAgentCommand() }) },
      {},
      { open: openSession },
    );
    const caller: Caller = { role: 'person', key, window: host.view };

    try {
      const ended = await host.spawn(caller, LONG_TASK_ARGS);

      assert(!('error' in ended));
      expect(host.closeAgent(caller, ended.id)).toEqual({
        closed: LONG_TASK_ARGS.name,
      });
      await until(() => host.conversationAt(key)!.task(ended.id) === undefined);

      const running = await host.spawn(caller, LONG_TASK_ARGS);

      assert(!('error' in running));
      expect(host.closeAgent(caller, LONG_TASK_ARGS.name)).toEqual({
        error: `2 of your tasks are named ${LONG_TASK_ARGS.name}; close_agent one by its id: ${running.id} and ${ended.id}`,
      });
      expect(host.conversationAt(key)!.task(running.id)?.running).toBe(true);
      expect(host.closeAgent(caller, ended.id)).toEqual({
        ended: LONG_TASK_ARGS.name,
      });
      expect(host.closeAgent(caller, running.id)).toEqual({
        closed: LONG_TASK_ARGS.name,
      });
    } finally {
      await host.sessions.closeAll();
    }
  });
});
