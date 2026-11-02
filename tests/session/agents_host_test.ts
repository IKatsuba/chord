import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  createAgentsHost,
  type AgentsPort,
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
      ...port,
    },
  );

  return { host, heard };
}

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
