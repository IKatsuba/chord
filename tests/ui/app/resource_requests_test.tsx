/** Runtime-scoped factual reads through the real MCP server, with fixture-only collectors. */
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { performance } from 'node:perf_hooks';
import { join } from 'node:path';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { createResources } from '../../../src/platform/resources.ts';
import { serveChord } from '../../../src/server/server.ts';
import type { Caller } from '../../../src/server/tools.ts';
import type { ChordCall } from '../../../src/session/transcript/types.ts';
import { BudgetSnapshot } from '../../../src/session/budgets.ts';
import { openSession } from '../../../src/session/session.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { ESC, ready, send, until, withWindow, type Window } from './render.tsx';

const definition = (body: string) => `---
description: MCP discovery routing fixture
lead:
  agent: codex
members:
  - name: reviewer
    role: Review only
    agent: claude
    instructions: Preserve review independence.
---
${body}
`;

async function withRequests(
  body: (f: {
    window: Window;
    main: Caller;
    callers: Caller[];
    client: (caller: Caller) => Promise<Client>;
    retained: { agent: string; released: boolean; signal: AbortSignal }[];
    prompts: string[];
    completed: string[];
    calls: { caller: Caller; call: ChordCall }[];
  }) => Promise<void>,
  teamBody = 'Preserve every saved instruction.',
) {
  const directory = await mkdtemp(join(tmpdir(), 'chord-filtered-facts-'));
  const resources = createResources({
    stateDirectory: directory,
    collectors: 'fixture',
  });
  const retain = resources.retain;
  const retained: { agent: string; released: boolean; signal: AbortSignal }[] =
    [];
  const callers: Caller[] = [];
  const admissions = new Map<Caller, string>();
  const clients: Client[] = [];
  const prompts: string[] = [];
  const completed: string[] = [];
  const calls: { caller: Caller; call: ChordCall }[] = [];
  const watched = new WeakSet<object>();
  const server = serveChord();
  const admit = server.admit.bind(server);

  resources.retain = (interest, signal, valid) => {
    const entry = { agent: interest.agent, released: false, signal };
    const release = retain(interest, signal, valid);

    retained.push(entry);

    return () => {
      entry.released = true;

      release();
    };
  };

  server.admit = (caller) => {
    if (!watched.has(caller.window)) {
      const served = caller.window.served;

      caller.window.served = (owner, call) => {
        calls.push({ caller: owner, call });
        served(owner, call);
      };

      watched.add(caller.window);
    }

    const admitted = admit(caller);

    callers.push(caller);
    admissions.set(caller, admitted.token);

    return admitted;
  };

  try {
    await resources.start();
    await withWindow(
      async (window) => {
        await ready(window);

        const main = callers.find((caller) => caller.role === 'person');

        assert(main);
        await body({
          window,
          main,
          callers,
          retained,
          prompts,
          completed,
          calls,
          client: async (caller) => {
            const token = admissions.get(caller);

            assert(token);

            const client = new Client({
              name: 'fixture-filter-client',
              version: '1',
            });
            const transport = new StreamableHTTPClientTransport(
              new URL(server.url),
              {
                requestInit: { headers: { Authorization: `Bearer ${token}` } },
              },
            );

            await client.connect(transport as Parameters<Client['connect']>[0]);
            clients.push(client);

            return client;
          },
        });
      },
      {
        server,
        resources,
        agent: 'fake',
        runtimes: ['fake', 'codex', 'claude'],
        teams: { fixture: definition(teamBody) },
        startupOf: () => ({ agentCommand: fakeAgentCommand() }),
        openWith: async (options) => {
          const session = await openSession(options);
          const prompt = session.prompt.bind(session);

          session.prompt = (text, ...rest) => {
            prompts.push(text);

            const answer = prompt(text, ...rest);

            void answer.result.then(
              () => {
                completed.push(text);
              },
              () => {},
            );

            return answer;
          };

          return session;
        },
      },
    );
  } finally {
    await Promise.all(clients.map((client) => client.close()));
    await resources.close();
    await server.close();
    await rm(directory, { recursive: true, force: true });
  }
}

async function read(client: Client, agents?: string[]) {
  const answer = await client.callTool({
    name: 'get_budgets',
    arguments: agents === undefined ? {} : { agents },
  });

  expect(answer.isError).not.toBe(true);

  return BudgetSnapshot.parse(answer.structuredContent);
}

const live = (
  entries: { agent: string; released: boolean; signal: AbortSignal }[],
  agent: string,
) =>
  entries.filter(
    (entry) =>
      entry.agent === agent && !entry.released && !entry.signal.aborted,
  ).length;

test('idle SDK reads retain only configured requested runtimes, return eventual original facts and deduplicate', () =>
  withRequests(async ({ main, client, retained }) => {
    const sdk = await client(main);

    await read(sdk);
    expect(retained.map((entry) => entry.agent)).toEqual(['fake']);
    await read(sdk, ['claude', 'missing']);
    await until('fixture quota observation', async () =>
      (await read(sdk, ['missing', 'claude', 'claude'])).unbound.some(
        (one) => one.agent === 'claude',
      ),
    );

    const first = await read(sdk, ['claude', 'missing']);
    const second = await read(sdk, ['missing', 'claude']);

    expect(first.unbound).toHaveLength(1);
    expect(first.unbound[0]?.agent).toBe('claude');
    expect(second.unbound).toEqual(first.unbound);
    expect(first.unavailable.some((one) => one.agent === 'missing')).toBe(true);
    expect(retained.map((entry) => entry.agent)).toEqual(['fake', 'claude']);
    expect(live(retained, 'claude')).toBe(1);

    const empty = await read(sdk, []);

    expect(empty.unbound).toEqual([]);
    expect(empty.unavailable).toEqual([]);
    expect(empty.activeRuns).toEqual([]);
    expect(live(retained, 'claude')).toBe(0);
    expect(live(retained, 'fake')).toBe(1);
  }));

test('ordinary instructed agent discovers runtimes before facts and launches one frozen run without an injected turn', () =>
  withRequests(async ({ window, main, retained, prompts, calls: recorded }) => {
    await send(window, 'budgetawareteam');
    await window.shows('Ordinary budget-aware handoff completed.');
    await until('temporary sources detached on actual main result', () =>
      retained
        .filter((entry) => entry.agent === 'claude')
        .some((entry) => entry.released),
    );

    const calls = recorded
      .filter((one) => one.caller.role === 'person')
      .map((one) => one.call);

    expect(calls.map((call) => call.tool)).toEqual([
      'list_teams',
      'list_agents',
      'get_budgets',
      'get_budgets',
      'run_team',
    ]);
    expect(
      calls
        .filter((call) => call.tool === 'get_budgets')
        .map((call) => call.input),
    ).toEqual([
      { agents: ['codex', 'claude'] },
      { agents: ['codex', 'claude'] },
    ]);
    expect(calls.find((call) => call.tool === 'run_team')?.input).toMatchObject(
      { selection: { lead: { model: 'fake-small', mode: 'plan' } } },
    );
    expect(
      prompts.filter((prompt) => prompt === 'budgetawareteam'),
    ).toHaveLength(1);
    expect(prompts).toHaveLength(2);
    expect(live(retained, 'claude')).toBe(1);

    const run = await main.window.teams(main);
    const lead = run.runs[0];

    assert(lead?.id);
    main.window.close(main, lead.id);
    await until(
      'run source released independently',
      () => live(retained, 'claude') === 0,
    );
    expect(live(retained, 'fake')).toBe(1);
  }, 'Read resource facts before this fixture handoff; preserve every role.'));

test('instruction-free ordinary saved handoff needs neither facts nor selection', () =>
  withRequests(async ({ window, prompts, calls: recorded }) => {
    await send(window, 'savedteamplain');
    await window.shows('Ordinary saved-composition handoff completed.');

    const calls = recorded
      .filter((one) => one.caller.role === 'person')
      .map((one) => one.call);

    expect(calls.map((call) => call.tool)).toEqual(['list_teams', 'run_team']);
    expect(calls.find((call) => call.tool === 'run_team')?.input).toEqual({
      team: 'fixture',
      job: 'selectedidle',
    });
    expect(
      prompts.filter((prompt) => prompt === 'savedteamplain'),
    ).toHaveLength(1);
    await until(
      'saved lead received its actual first job',
      () => prompts.length === 2,
    );
    expect(prompts).toHaveLength(2);
  }));

test('actual main interrupt releases temporary interest without releasing the current session owner', () =>
  withRequests(async ({ window, main, client, retained }) => {
    await send(window, 'costwait');
    await window.shows('Working until stopped.');

    const sdk = await client(main);

    await read(sdk, ['claude']);
    expect(live(retained, 'claude')).toBe(1);
    await window.press(ESC);
    await until(
      'cancelled main interest detached',
      () => live(retained, 'claude') === 0,
    );
    expect(live(retained, 'fake')).toBe(1);
  }));

test('an idle child owns its requested filter independently of a busy main and closes without revoking main interest', () =>
  withRequests(
    async ({ window, main, callers, client, retained, prompts, completed }) => {
      await send(window, 'costwait');
      await window.shows('Working until stopped.');

      const parent = await client(main);

      await read(parent, ['claude']);

      const opened = await parent.callTool({
        name: 'open_agent',
        arguments: { agent: 'fake', name: 'reader', prompt: 'text' },
      });

      expect(opened.isError).not.toBe(true);
      await until('child admission', () =>
        callers.some((caller) => caller.agent !== undefined),
      );

      const child = callers.find((caller) => caller.agent !== undefined);

      assert(child?.agent);
      await until(
        'actual child first turn completed',
        () => prompts.length === 2 && completed.includes(prompts[1]!),
      );

      const childSDK = await client(child);

      await read(childSDK, ['codex']);
      expect(live(retained, 'codex')).toBe(1);
      expect(live(retained, 'claude')).toBe(1);
      await parent.callTool({
        name: 'close_agent',
        arguments: { to: child.agent },
      });
      await until(
        'closed child filter detached',
        () => live(retained, 'codex') === 0,
      );
      expect(live(retained, 'claude')).toBe(1);
      expect(live(retained, 'fake')).toBe(1);
      await window.press(ESC);
      await until(
        'main filter detached separately',
        () => live(retained, 'claude') === 0,
      );
    },
  ));

test('clear releases the old generation and late old scope reads cannot detach its replacement', () =>
  withRequests(async ({ window, main, callers, client, retained }) => {
    const old = await client(main);

    await read(old, ['codex']);
    expect(live(retained, 'codex')).toBe(1);
    await send(window, '/clear');
    await until(
      'replacement main admitted',
      () => callers.filter((caller) => caller.role === 'person').length === 2,
    );
    await ready(window);

    const replacement = callers.findLast((caller) => caller.role === 'person');

    assert(replacement && replacement !== main);

    const current = await client(replacement);

    await read(current, ['claude']);
    expect(live(retained, 'codex')).toBe(0);
    expect(live(retained, 'claude')).toBe(1);
    main.window.budgets?.(main, [], performance.now());
    main.window.budgets?.(main, ['codex'], performance.now());
    expect(live(retained, 'claude')).toBe(1);
    expect(live(retained, 'codex')).toBe(0);
    expect(live(retained, 'fake')).toBe(1);
  }));

test('actual fake-provider disconnect releases an idle temporary filter', () =>
  withRequests(async ({ window, main, client, retained }) => {
    const session = window.session();

    assert(session);

    const sdk = await client(main);

    await read(sdk, ['claude']);
    expect(live(retained, 'claude')).toBe(1);
    await session.close();
    await until(
      'disconnected caller interest detached',
      () => live(retained, 'claude') === 0,
    );
    expect(live(retained, 'fake')).toBe(0);
  }));

describe('CHD-533 tester: production factual-read boundaries', () => {
  test('idle SDK repeats expire at the original real deadline without a synthetic turn', () =>
    withRequests(async ({ main, client, retained }) => {
      const sdk = await client(main);
      const started = performance.now();

      await read(sdk, ['claude']);
      expect(live(retained, 'claude')).toBe(1);
      await until(
        'near the original request deadline',
        () => performance.now() - started >= 25_000,
        28_000,
      );
      await read(sdk, ['claude', 'claude']);
      expect(retained.filter((entry) => entry.agent === 'claude')).toHaveLength(
        1,
      );
      expect(live(retained, 'claude')).toBe(1);
      await until(
        'original absolute expiry releases the idle filter',
        () => live(retained, 'claude') === 0,
        10_000,
      );
      expect(live(retained, 'fake')).toBe(1);
    }));

  test('pre-cancelled SDK clearing and an expired late admission cannot release the current owner', () =>
    withRequests(async ({ main, client, retained }) => {
      const sdk = await client(main);
      const cancelled = new AbortController();

      await read(sdk, ['claude']);
      cancelled.abort();
      await expect(
        sdk.callTool(
          { name: 'get_budgets', arguments: { agents: [] } },
          undefined,
          { signal: cancelled.signal },
        ),
      ).rejects.toThrow();
      main.window.budgets?.(main, [], performance.now() - 30_001);
      await read(sdk);
      expect(live(retained, 'claude')).toBe(1);
      expect(live(retained, 'fake')).toBe(1);
      expect(retained.map((entry) => entry.agent)).toEqual(['fake', 'claude']);
    }));

  test('request cancellation at window admission releases only its temporary source and a later SDK read recovers', () =>
    withRequests(async ({ main, client, retained }) => {
      const request = new AbortController();

      main.window.budgets?.(
        { ...main, signal: request.signal },
        ['claude'],
        performance.now(),
      );
      expect(live(retained, 'claude')).toBe(1);
      request.abort();
      await until(
        'request-only cancellation releases its source',
        () => live(retained, 'claude') === 0,
      );
      expect(live(retained, 'fake')).toBe(1);

      const sdk = await client(main);

      await read(sdk, ['claude']);
      request.abort();
      expect(live(retained, 'claude')).toBe(1);
      expect(live(retained, 'fake')).toBe(1);
    }));
});
