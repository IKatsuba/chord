import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { copyFile, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import {
  NO_TURNS,
  reduceTurns,
  sessionStateOf,
  type TurnInput,
} from '../src/acp/upstream_turns.ts';
import { runAcp } from '../src/acp_agent.ts';
import { killSpawnedGroups } from '../src/platform/process.ts';
import { serveChord } from '../src/server/server.ts';
import { openSession, type Session } from '../src/session/session.ts';
import type { EndedMonitor, RunningMonitor } from '../src/session/monitors.ts';
import { type AcpClient, clientOverStreams } from './fixtures/acp_client.ts';
import { fakeAgentCommand } from './fixtures/fake.ts';
import {
  ended,
  onFake,
  promptsIn,
  saidIn,
  until,
} from './session/conversation_fake.ts';

/** Runs the existing raw ACP client against chord and the scripted agent. */
async function withExtensionWire(
  flags: readonly string[],
  capabilities: object,
  body: (
    client: AcpClient,
    newSession: () => Promise<string>,
    cwd: string,
  ) => Promise<void>,
  watch: (session: Session) => Session = (session) => session,
  opening: typeof openSession = openSession,
) {
  const cwd = await mkdtemp(join(tmpdir(), 'chord-extension-wire-'));
  const { client, input, output, end } = clientOverStreams();
  let exited = false;

  runAcp({
    input,
    output,
    stderr: () => {},
    exit: () => {
      exited = true;
    },
    agent: 'fake',
    version: '1.2.3',
    home: cwd,
    configHome: join(cwd, 'config'),
    stateDir: join(cwd, 'state'),
    open: async (options) => watch(await opening(options)),
    server: serveChord(),
    place: () =>
      Promise.resolve({
        cwd,
        startupOf: () => ({
          agentCommand: fakeAgentCommand(undefined, ...flags),
        }),
        mcpServers: [],
        mcpIgnored: [],
        runtimes: ['fake'],
      }),
  });

  try {
    await client.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: capabilities,
    });
    await body(
      client,
      async () => {
        const response = await client.request('session/new', {
          cwd,
          mcpServers: [],
        });

        expect(response.error).toBeUndefined();
        assert(typeof response.result?.sessionId === 'string');

        return response.result.sessionId;
      },
      cwd,
    );
  } finally {
    end();
    await until(() => exited, 20_000);
    await until(() => killSpawnedGroups().length === 0);
    await rm(cwd, { recursive: true, force: true });
  }
}

const wirePrompt = (client: AcpClient, sessionId: string, text: string) =>
  client.send('session/prompt', {
    sessionId,
    prompt: [{ type: 'text', text }],
  });

const wireStates = (client: AcpClient, sessionId: string) =>
  client.messages.flatMap((message) =>
    message.method === '_chord/session/state' &&
    message.params?.sessionId === sessionId
      ? [{ state: message.params.state, origin: message.params.origin }]
      : [],
  );

const wireChildren = (client: AcpClient, parent: string) => {
  const children = new Map<
    string,
    { id: string; title: string; state: string; agent: Record<string, unknown> }
  >();

  for (const update of client.updates(parent)) {
    const agent = (
      update._meta as Record<string, Record<string, unknown>> | undefined
    )?.['chord/agent'];

    if (update.sessionUpdate === 'subagent_update' && agent !== undefined) {
      const id = String(update.sessionId);

      children.set(id, {
        id,
        title: String(update.title),
        state: String((update.state as { state: string }).state),
        agent,
      });
    }
  }

  return [...children.values()];
};

const wireMonitors = (client: AcpClient, sessionId: string) =>
  client.messages.flatMap((message) =>
    message.method === '_chord/monitors/changed' &&
    message.params?.sessionId === sessionId
      ? [
          message.params as unknown as {
            running: RunningMonitor[];
            ended: EndedMonitor[];
          },
        ]
      : [],
  );

describe('CHD-575 U1 tester: named queue ownership', () => {
  test('a refused middle entry returns between the older and newer entries exactly once', async () => {
    const release = Promise.withResolvers<void>();
    let finished = false;

    try {
      await onFake(
        ['--steering', 'claude'],
        async (conversation, events) => {
          try {
            conversation.send('text');
            await until(() => finished);
            conversation.send('Older.', undefined, [], [], { turnId: 'older' });
            conversation.send('Mine.', undefined, [], [], { turnId: 'mine' });
            conversation.send('Newer.', undefined, [], [], { turnId: 'newer' });
            expect(conversation.steerQueued('mine')).toBe('sent');
            await until(() =>
              events.some(
                (event) =>
                  event.type === 'queued' &&
                  event.turnId === 'mine' &&
                  event.refused,
              ),
            );
            release.resolve();
            await ended(events, 4);
            expect(promptsIn(events)).toEqual([
              ['text', undefined],
              ['Older.', undefined],
              ['Mine.', undefined],
              ['Newer.', undefined],
            ]);
            expect(conversation.steerQueued('mine')).toBe('none');
          } finally {
            release.resolve();
          }
        },
        (session) => {
          const prompt = session.prompt.bind(session);
          let first = true;

          session.prompt = (...args) => {
            const turn = prompt(...args);

            if (!first) {
              return turn;
            }

            first = false;

            return {
              ...turn,
              result: turn.result.then(async (result) => {
                finished = true;

                await release.promise;

                return result;
              }),
            };
          };

          return session;
        },
      );
    } finally {
      release.resolve();
    }
  });

  test('a held named entry and an unknown target never select the older personal entry', () =>
    onFake(['--steering', 'claude'], async (conversation, events) => {
      conversation.send('permissionsteer');
      await until(() =>
        events.some((event) => event.type === 'permission_requested'),
      );
      conversation.send('Older.', undefined, [], [], { turnId: 'older' });
      conversation.send('Mine.', undefined, [], [], { turnId: 'mine' });
      expect(conversation.steerQueued('mine')).toBe('sent');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'queued' &&
            event.turnId === 'mine' &&
            event.afterAnswer,
        ),
      );

      const before = events.length;

      expect(conversation.steerQueued('mine')).toBe('none');
      expect(conversation.steerQueued('unknown')).toBe('none');
      expect(events).toHaveLength(before);

      const asked = events.find(
        (event) => event.type === 'permission_requested',
      );

      assert(asked?.type === 'permission_requested');
      conversation.choose(asked.permission.id, 'allow');
      await ended(events, 2);
      expect(promptsIn(events).map(([text]) => text)).toEqual([
        'permissionsteer',
        'Mine.',
        'Older.',
      ]);
    }));

  test('matching turn ids in simultaneous sessions steer only their own session', () =>
    onFake(['--steering', 'claude'], async (first, firstEvents) => {
      await onFake(['--steering', 'claude'], async (second, secondEvents) => {
        first.send('slow');
        second.send('slow');
        await until(
          () =>
            saidIn(firstEvents).startsWith('Working') &&
            saidIn(secondEvents).startsWith('Working'),
        );
        first.send('First only.', undefined, [], [], { turnId: 'same' });
        second.send('Second only.', undefined, [], [], { turnId: 'same' });
        expect(first.steerQueued('same')).toBe('sent');
        await until(() => promptsIn(firstEvents).length === 2);
        expect(promptsIn(secondEvents)).toEqual([['slow', undefined]]);
        expect(second.steerQueued('same')).toBe('sent');
        await until(() => promptsIn(secondEvents).length === 2);
        expect(promptsIn(firstEvents).map(([text]) => text)).toEqual([
          'slow',
          'First only.',
        ]);
        expect(promptsIn(secondEvents).map(([text]) => text)).toEqual([
          'slow',
          'Second only.',
        ]);
        first.interrupt();
        second.interrupt();
        await ended(firstEvents, 1);
        await ended(secondEvents, 1);
      });
    }));
});

describe('CHD-575 U2 tester: independent steered turn lifetimes', () => {
  test('consuming one steered id leaves another queued id client-owned without echo', () => {
    const first = reduceTurns(NO_TURNS, { type: 'steered', turnId: 'first' });
    const both = reduceTurns(first.turns, {
      type: 'steered',
      turnId: 'second',
    });
    const played = reduceTurns(both.turns, {
      type: 'prompt',
      turnId: 'first',
      text: 'First words.',
      into: 'running',
    });

    expect(played.sends).toEqual([]);
    expect(played.turns.steered).toEqual(new Set(['second']));
    expect(both.turns.steered).toEqual(new Set(['first', 'second']));

    const next = reduceTurns(played.turns, {
      type: 'prompt',
      turnId: 'second',
      text: 'Second words.',
    });

    expect(next.sends).toEqual([]);
    expect(next.turns.steered).toBeUndefined();
    expect(sessionStateOf(next.turns, false)).toEqual({
      state: 'running',
      origin: 'client',
    });
  });

  test('disconnect preserves a queued steered id until it plays without echo', () => {
    const marked = reduceTurns(NO_TURNS, { type: 'steered', turnId: 'mine' });
    const gone = reduceTurns(marked.turns, { type: 'disconnected' });

    expect(gone.sends).toEqual([]);
    expect(sessionStateOf(gone.turns, true)).toEqual({
      state: 'requires_action',
    });

    const played = reduceTurns(gone.turns, {
      type: 'prompt',
      turnId: 'mine',
      text: 'Queued words.',
    });

    expect(played.sends).toEqual([]);
    expect(sessionStateOf(played.turns, true)).toEqual({
      state: 'requires_action',
      origin: 'client',
    });
    expect(played.turns.steered).toBeUndefined();
  });

  test('a late result of a steered turn preserves a newer agent-originated turn', () => {
    const marked = reduceTurns(NO_TURNS, { type: 'steered', turnId: 'old' });
    const running = reduceTurns(marked.turns, {
      type: 'cycle_started',
      turnId: 'new',
    });
    const late = reduceTurns(running.turns, {
      type: 'result',
      turnId: 'old',
      result: { status: 'cancelled', stopReason: 'cancelled' },
    });

    expect(late.sends).toEqual([]);
    expect(late.turns.steered).toBeUndefined();
    expect(late.turns.running).toEqual({ turnId: 'new', origin: 'agent' });
    expect(sessionStateOf(late.turns, false)).toEqual({
      state: 'running',
      origin: 'agent',
    });
  });

  test.each(['unbind', 'result', 'queue_withdrawn'] as const)(
    '%s removes only the named steered id and leaves other sessions untouched',
    (kind) => {
      const marked = reduceTurns(NO_TURNS, { type: 'steered', turnId: 'a' });
      const both = reduceTurns(marked.turns, {
        type: 'steered',
        turnId: 'b',
      });
      const input: TurnInput =
        kind === 'queue_withdrawn'
          ? { type: kind, turnIds: ['a'] }
          : kind === 'result'
            ? {
                type: kind,
                turnId: 'a',
                result: { status: 'completed', stopReason: 'end_turn' },
              }
            : { type: kind, turnId: 'a' };
      const cleaned = reduceTurns(both.turns, input);

      expect(cleaned.sends).toEqual([]);
      expect(cleaned.turns.steered).toEqual(new Set(['b']));
      expect(marked.turns.steered).toEqual(new Set(['a']));
      expect(NO_TURNS.steered).toBeUndefined();
    },
  );

  test('closing clears pending steers without adding request answers', () => {
    const marked = reduceTurns(NO_TURNS, { type: 'steered', turnId: 'mine' });
    const bound = reduceTurns(marked.turns, {
      type: 'bind',
      requestId: 'request',
      turnId: 'ordinary',
    });
    const closed = reduceTurns(bound.turns, { type: 'closing' });

    expect(closed.turns).toEqual(NO_TURNS);
    expect(closed.sends).toEqual([{ type: 'cancelled', requestId: 'request' }]);
    expect(marked.turns.steered).toEqual(new Set(['mine']));
  });
});

describe('CHD-575 U3 tester: state on the wire', () => {
  test.each(['omitted', 'declared'] as const)(
    'separate sessions deduplicate state, declared extensions=%s',
    (declared) =>
      withExtensionWire(
        [],
        declared === 'declared'
          ? { _meta: { 'chord/acp': { extensions: { 'session/state': 1 } } } }
          : {},
        async (client, newSession) => {
          const first = await newSession();
          const second = await newSession();
          const running = wirePrompt(client, first, 'slow');

          await until(() => client.said(first).includes('Working'));
          await client.answerTo(wirePrompt(client, second, 'text'));
          await until(() => wireStates(client, second).length === 2);
          expect(wireStates(client, first)).toEqual([
            { state: 'running', origin: 'client' },
          ]);
          expect(wireStates(client, second)).toEqual([
            { state: 'running', origin: 'client' },
            { state: 'idle', origin: undefined },
          ]);
          client.notify('session/cancel', { sessionId: first });
          await client.answerTo(running);
          await until(() => wireStates(client, first).length === 2);
          expect(wireStates(client, first).at(-1)).toEqual({
            state: 'idle',
            origin: undefined,
          });
          await client.request('session/close', { sessionId: first });
          await client.answerTo(wirePrompt(client, second, 'text'));
          expect(wireStates(client, first)).toHaveLength(2);
        },
      ),
  );

  for (const [flags, scenario] of [
    [['--adapter', 'claude'], 'claudecycle'],
    [[], 'codebuddycycle'],
  ] as const) {
    test(`${scenario} reports an autonomous cycle as agent origin`, () =>
      withExtensionWire(flags, {}, async (client, newSession) => {
        const sessionId = await newSession();

        await client.answerTo(wirePrompt(client, sessionId, scenario));
        await until(() => wireStates(client, sessionId).length === 4);
        expect(wireStates(client, sessionId)).toEqual([
          { state: 'running', origin: 'client' },
          { state: 'idle', origin: undefined },
          { state: 'running', origin: 'agent' },
          { state: 'idle', origin: undefined },
        ]);
      }));
  }

  test('an exiting main reports idle without waiting for an explicit close', () =>
    withExtensionWire([], {}, async (client, newSession) => {
      const sessionId = await newSession();
      const response = await client.answerTo(
        wirePrompt(client, sessionId, 'crash'),
      );

      expect(response.error).toBeDefined();
      await until(() => wireStates(client, sessionId).length === 2);
      expect(wireStates(client, sessionId)).toEqual([
        { state: 'running', origin: 'client' },
        { state: 'idle', origin: undefined },
      ]);
    }));

  test('a child permission requires action only on the child subagent update', () =>
    withExtensionWire([], { subagents: {} }, async (client, newSession) => {
      const sessionId = await newSession();
      const running = wirePrompt(client, sessionId, 'agentsquiet');
      const ask = await client.until(
        (message) => message.method === 'session/request_permission',
      );
      const childId = String(ask.params?.sessionId);

      assert(ask.id !== undefined && ask.id !== null);
      expect(childId.startsWith(`${sessionId}/`)).toBe(true);
      await until(() =>
        client
          .updates(sessionId)
          .some(
            (update) =>
              update.sessionUpdate === 'subagent_update' &&
              update.sessionId === childId &&
              (update.state as { state?: string }).state === 'requires_action',
          ),
      );
      expect(wireStates(client, childId)).toEqual([]);
      expect(
        wireStates(client, sessionId).some(
          ({ state }) => state === 'requires_action',
        ),
      ).toBe(false);
      client.respond(ask.id, {
        outcome: { outcome: 'selected', optionId: 'allow' },
      });
      await client.answerTo(running);
      expect(
        wireStates(client, sessionId).some(
          ({ state }) => state === 'requires_action',
        ),
      ).toBe(false);
    }));
});

describe('CHD-575 U4 tester: steering delivery on the wire', () => {
  const steer = (client: AcpClient, sessionId: string, text: string) =>
    client.send('_chord/session/steer', {
      sessionId,
      prompt: [{ type: 'text', text }],
    });
  const echoes = (client: AcpClient, sessionId: string) =>
    client
      .updates(sessionId)
      .filter((update) => update.sessionUpdate === 'user_message_chunk');

  test('a steer refused after cancellation runs as its own client turn and answers only once', () =>
    withExtensionWire(
      ['--steering', 'claude', '--steer-late'],
      {},
      async (client, newSession) => {
        const sessionId = await newSession();
        const running = wirePrompt(client, sessionId, 'texttillsteeredheld');

        await until(() => client.said(sessionId).includes('came in chunks'));

        const request = steer(client, sessionId, 'text');

        expect((await client.answerTo(request)).result).toEqual({
          delivery: 'sent',
        });
        client.notify('session/cancel', { sessionId });
        expect((await client.answerTo(running)).result?.stopReason).toBe(
          'cancelled',
        );
        await until(() => wireStates(client, sessionId).length === 4);
        expect(wireStates(client, sessionId)).toEqual([
          { state: 'running', origin: 'client' },
          { state: 'idle', origin: undefined },
          { state: 'running', origin: 'client' },
          { state: 'idle', origin: undefined },
        ]);
        expect(echoes(client, sessionId)).toEqual([]);
        expect(
          client.messages.filter(
            (message) => message.id === request && message.method === undefined,
          ),
        ).toHaveLength(1);
      },
    ));

  test('a held ask delays its named steer until the permission is answered', async () => {
    const steers: Parameters<Session['steer']>[] = [];

    await withExtensionWire(
      ['--steering', 'claude'],
      {},
      async (client, newSession) => {
        const sessionId = await newSession();
        const running = wirePrompt(client, sessionId, 'permissionsteer');
        const ask = await client.until(
          (message) => message.method === 'session/request_permission',
        );

        assert(ask.id !== undefined && ask.id !== null);

        const request = steer(client, sessionId, 'After permission.');

        expect((await client.answerTo(request)).result).toEqual({
          delivery: 'sent',
        });
        expect(wireStates(client, sessionId).at(-1)).toEqual({
          state: 'requires_action',
          origin: 'client',
        });
        expect(steers).toHaveLength(0);
        client.respond(ask.id, {
          outcome: { outcome: 'selected', optionId: 'allow' },
        });
        await client.answerTo(running);
        expect(steers).toHaveLength(1);
        expect(steers[0]?.[0]).toBe('After permission.');
        expect(echoes(client, sessionId)).toEqual([]);
        expect(
          client.messages.filter((message) => message.id === request),
        ).toHaveLength(1);
      },
      (session) => {
        const original = session.steer.bind(session);

        session.steer = (...args) => {
          steers.push(args);

          return original(...args);
        };

        return session;
      },
    );
  });

  test('a running turn receives both the image and the resource link in a steer', () =>
    withExtensionWire(
      ['--steering', 'claude'],
      {},
      async (client, newSession) => {
        const sessionId = await newSession();
        const running = wirePrompt(client, sessionId, 'slow');

        await until(() => client.said(sessionId).includes('Working'));

        const response = await client.request('_chord/session/steer', {
          sessionId,
          prompt: [
            { type: 'text', text: 'Read these blocks.' },
            { type: 'image', mimeType: 'image/png', data: 'aGVsbG8=' },
            {
              type: 'resource_link',
              uri: 'file:///tmp/chord-extension-link.ts',
              name: 'linked.ts',
              mimeType: 'text/typescript',
              _meta: { source: 'extension-test' },
            },
          ],
        });

        expect(response.result).toEqual({ delivery: 'sent' });
        await until(() => client.said(sessionId).includes('Received an image'));
        expect(client.said(sessionId)).toContain(
          'Received an image: image/png, 5 bytes',
        );
        expect(client.said(sessionId)).toContain(
          'Received a link: linked.ts, file:///tmp/chord-extension-link.ts',
        );
        client.notify('session/cancel', { sessionId });
        await client.answerTo(running);
      },
    ));

  test('an idle steer retains resource link metadata in the prompt that actually runs', async () => {
    const prompts: Parameters<Session['prompt']>[] = [];
    const link = {
      type: 'resource_link',
      uri: 'file:///tmp/chord-extension-link.ts',
      name: 'linked.ts',
      mimeType: 'text/typescript',
      description: 'A link supplied by the client.',
      _meta: { source: 'extension-test' },
    } as const;

    await withExtensionWire(
      [],
      {},
      async (client, newSession) => {
        const sessionId = await newSession();
        const request = client.send('_chord/session/steer', {
          sessionId,
          prompt: [{ type: 'text', text: 'text' }, link],
        });

        expect((await client.answerTo(request)).result).toEqual({
          delivery: 'queued',
        });
        await until(() => wireStates(client, sessionId).length === 2);
        expect(prompts).toHaveLength(1);
        expect(prompts[0]?.[3]).toEqual([link]);
        expect(echoes(client, sessionId)).toEqual([]);
        await client.request('session/close', { sessionId });
        expect(
          (await client.answerTo(steer(client, sessionId, 'closed'))).error
            ?.code,
        ).toBe(-32002);
      },
      (session) => {
        const prompt = session.prompt.bind(session);

        session.prompt = (...args) => {
          prompts.push(args);

          return prompt(...args);
        };

        return session;
      },
    );
  });
});

describe('CHD-575 U5 tester: child control boundaries', () => {
  const send = (client: AcpClient, sessionId: string, text = 'text') =>
    client.request('_chord/agents/send', {
      sessionId,
      prompt: [{ type: 'text', text }],
    });
  const close = (client: AcpClient, sessionId: string) =>
    client.request('_chord/agents/close', { sessionId });

  test('same-named children stay separate, content reaches the selected child, and close stops its process', async () => {
    const opened: Session[] = [];

    await withExtensionWire(
      [],
      { subagents: {} },
      async (client, newSession) => {
        const first = await newSession();

        await client.answerTo(wirePrompt(client, first, 'agenttitled'));
        await until(() =>
          wireChildren(client, first).some(
            (child) =>
              child.state === 'idle' &&
              client.said(child.id).includes('came in chunks'),
          ),
        );

        const firstChild = wireChildren(client, first)[0];
        const pids = [...(opened.at(-1)?.agentPids ?? [])];

        assert(firstChild && pids.length > 0);

        const second = await newSession();

        await client.answerTo(wirePrompt(client, second, 'agenttitled'));
        await until(() =>
          wireChildren(client, second).some(
            (child) =>
              child.state === 'idle' &&
              client.said(child.id).includes('came in chunks'),
          ),
        );

        const secondChild = wireChildren(client, second)[0];

        assert(secondChild);
        expect(secondChild.title).toBe(firstChild.title);
        expect(secondChild.id).not.toBe(firstChild.id);
        expect((await close(client, firstChild.id)).result).toEqual({
          closed: [firstChild.title],
        });

        for (const pid of pids) {
          await until(() => {
            try {
              process.kill(pid, 0);

              return false;
            } catch {
              return true;
            }
          });
        }

        const content = await client.request('_chord/agents/send', {
          sessionId: secondChild.id,
          prompt: [
            { type: 'text', text: 'text' },
            { type: 'image', mimeType: 'image/png', data: 'aGVsbG8=' },
            {
              type: 'resource_link',
              name: 'child.ts',
              uri: 'file:///tmp/chord-extension-child.ts',
              _meta: { source: 'child-test' },
            },
          ],
        });

        expect(content.result).toEqual({ delivery: 'sent' });
        await until(() =>
          client.said(secondChild.id).includes('Received a link: child.ts'),
        );
        expect(client.said(secondChild.id)).toContain(
          'Received an image: image/png, 5 bytes',
        );
        expect(client.said(firstChild.id)).not.toContain(
          'Received a link: child.ts',
        );
        expect((await send(client, firstChild.id)).error?.code).toBe(-32002);
        expect((await close(client, firstChild.id)).error?.code).toBe(-32002);
        expect((await close(client, secondChild.id)).result).toEqual({
          closed: [secondChild.title],
        });
      },
      (session) => {
        opened.push(session);

        return session;
      },
    );
  });

  test('an actual task id is refused by both long-lived child methods', () =>
    withExtensionWire([], { subagents: {} }, async (client, newSession) => {
      const main = await newSession();

      await client.answerTo(wirePrompt(client, main, 'tasklong'));
      await until(() =>
        client
          .updates(main)
          .some((update) => update.sessionUpdate === 'subagent_update'),
      );

      const task = client
        .updates(main)
        .find((update) => update.sessionUpdate === 'subagent_update');

      assert(typeof task?.sessionId === 'string');
      expect((await send(client, task.sessionId)).error?.code).toBe(-32002);
      expect((await close(client, task.sessionId)).error?.code).toBe(-32002);
      client.notify('session/cancel', { sessionId: task.sessionId });
    }));

  test('an actual adapter subagent id is refused without cancelling its ask', () =>
    withExtensionWire([], { subagents: {} }, async (client, newSession) => {
      const main = await newSession();
      const running = wirePrompt(client, main, 'subagent');
      const ask = await client.until(
        (message) => message.method === 'session/request_permission',
      );
      const child = String(ask.params?.sessionId);

      assert(ask.id !== undefined && ask.id !== null);
      expect(child.startsWith(`${main}/`)).toBe(true);
      expect((await send(client, child)).error?.code).toBe(-32002);
      expect((await close(client, child)).error?.code).toBe(-32002);
      client.respond(ask.id, {
        outcome: { outcome: 'selected', optionId: 'allow' },
      });
      client.notify('session/cancel', { sessionId: main });
      await client.answerTo(running);
    }));

  test('an exited child is not an addressable child for either method', () =>
    withExtensionWire([], { subagents: {} }, async (client, newSession) => {
      const main = await newSession();

      await client.answerTo(wirePrompt(client, main, 'agentexit'));
      await until(() =>
        wireChildren(client, main).some(
          (child) => child.agent['gone'] === 'exited',
        ),
      );

      const child = wireChildren(client, main).find(
        (child) => child.agent['gone'] === 'exited',
      );

      assert(child);
      expect((await send(client, child.id)).error?.code).toBe(-32002);
      expect((await close(client, child.id)).error?.code).toBe(-32002);
    }));

  test('a failed child start refuses prompts but remains closable', async () => {
    let opened = 0;

    await withExtensionWire(
      [],
      { subagents: {} },
      async (client, newSession) => {
        const main = await newSession();

        await client.answerTo(wirePrompt(client, main, 'agentcost'));
        await until(() =>
          wireChildren(client, main).some(
            (child) => typeof child.agent['failed'] === 'string',
          ),
        );

        const child = wireChildren(client, main).find(
          (child) => typeof child.agent['failed'] === 'string',
        );

        assert(child);
        expect((await send(client, child.id)).error?.code).toBe(-32002);
        expect((await close(client, child.id)).result).toEqual({
          closed: [child.title],
        });
      },
      (session) => session,
      (options) => {
        opened += 1;

        return openSession(
          opened === 2
            ? { ...options, agentCommand: ['chord-missing-fixture-command'] }
            : options,
        );
      },
    );
  });
});

describe('CHD-575 U6 tester: monitor ownership and lifetime', () => {
  const stop = (client: AcpClient, sessionId: string, id: string) =>
    client.request('_chord/monitors/stop', { sessionId, id });

  test('identical monitor ids in separate sessions retain complete stop and ended metadata', () =>
    withExtensionWire([], {}, async (client, newSession) => {
      const first = await newSession();
      const second = await newSession();

      await client.answerTo(wirePrompt(client, first, 'monitors'));
      await client.answerTo(wirePrompt(client, second, 'monitors'));
      await until(
        () =>
          wireMonitors(client, first).at(-1)?.running.length === 2 &&
          wireMonitors(client, second).at(-1)?.running.length === 2,
      );

      const before = wireMonitors(client, first)
        .at(-1)!
        .running.find((monitor) => monitor.id === 'm2');

      assert(before);

      const stopped = await stop(client, first, 'm2');

      expect(stopped.result).toEqual({
        id: 'm2',
        description: before.description,
        events: before.events,
        ran_ms: expect.any(Number),
      });
      await until(
        () =>
          wireMonitors(client, first)
            .at(-1)
            ?.ended.some((monitor) => monitor.id === 'm2') === true,
      );

      const ended = wireMonitors(client, first)
        .at(-1)!
        .ended.find((monitor) => monitor.id === 'm2');

      expect(ended).toEqual({
        ...before,
        end: { kind: 'stopped' },
        endedAt: expect.any(Number),
      });
      expect(
        wireMonitors(client, second)
          .at(-1)
          ?.running.map(({ id }) => id),
      ).toEqual(['m1', 'm2']);
      expect((await stop(client, first, 'm2')).error?.code).toBe(-32002);
      expect((await stop(client, second, 'm2')).result?.id).toBe('m2');
      await client.request('session/close', { sessionId: first });
      expect((await stop(client, first, 'm1')).error?.code).toBe(-32002);
    }));

  test('natural exit preserves the command, timing, event and exit metadata', () =>
    withExtensionWire([], {}, async (client, newSession) => {
      const sessionId = await newSession();

      await client.answerTo(wirePrompt(client, sessionId, 'monitorexit'));
      await until(
        () => wireMonitors(client, sessionId).at(-1)?.ended.length === 1,
      );

      const ended = wireMonitors(client, sessionId).at(-1)!.ended[0];

      assert(ended);
      expect(ended.endedAt).toBeGreaterThanOrEqual(ended.startedAt);
      expect(ended).toMatchObject({
        id: 'm1',
        description: 'CI run 4812',
        command: expect.stringContaining('exit 1'),
        startedAt: expect.any(Number),
        timeoutMs: expect.any(Number),
        events: 0,
        end: { kind: 'exit', code: 1 },
        endedAt: expect.any(Number),
        lastEvent: {
          at: expect.any(Number),
          lines: expect.arrayContaining([
            'Run 4812 (ci.yml) failed: 1 of 3 jobs failed',
          ]),
        },
      });
      expect((await stop(client, sessionId, 'm1')).error?.code).toBe(-32002);
    }));

  test('a nested team member owns its monitor independently of main and lead', () =>
    withExtensionWire(
      ['--tester-plays', 'childmonitor'],
      { subagents: {} },
      async (client, newSession, cwd) => {
        await mkdir(join(cwd, '.chord', 'teams'), { recursive: true });
        await copyFile(
          new URL('./fixtures/teams/fake/bugfix.md', import.meta.url),
          join(cwd, '.chord', 'teams', 'bugfix.md'),
        );

        const main = await newSession();

        await client.answerTo(
          wirePrompt(client, main, '/team run bugfix monitor the tests'),
        );
        await until(() =>
          wireChildren(client, main).some(
            (child) => child.agent['role'] === 'lead',
          ),
        );

        const lead = wireChildren(client, main).find(
          (child) => child.agent['role'] === 'lead',
        );

        assert(lead);
        await until(() =>
          wireChildren(client, lead.id).some(
            (child) => child.title === 'tester',
          ),
        );

        const tester = wireChildren(client, lead.id).find(
          (child) => child.title === 'tester',
        );

        assert(tester);
        await until(
          () => wireMonitors(client, tester.id).at(-1)?.running.length === 1,
        );
        expect((await stop(client, main, 'm1')).error?.code).toBe(-32002);
        expect((await stop(client, lead.id, 'm1')).error?.code).toBe(-32002);
        expect((await stop(client, tester.id, 'm1')).result).toMatchObject({
          id: 'm1',
          description: 'parser tests',
        });
        await client.request('_chord/agents/close', { sessionId: lead.id });
        expect((await stop(client, tester.id, 'm1')).error?.code).toBe(-32002);
      },
    ));

  test('clearing a child revokes its old monitor under the retained composite id', () =>
    withExtensionWire([], { subagents: {} }, async (client, newSession) => {
      const main = await newSession();

      await client.answerTo(wirePrompt(client, main, 'monitorchild'));
      await until(() =>
        wireChildren(client, main).some(
          (child) =>
            wireMonitors(client, child.id).at(-1)?.running.length === 1,
        ),
      );

      const child = wireChildren(client, main).find(
        (child) => child.title === 'parser',
      );

      assert(child);
      await client.answerTo(wirePrompt(client, main, 'agentclearonly'));
      await until(() =>
        wireChildren(client, main).some(
          (each) => each.id === child.id && each.state === 'idle',
        ),
      );
      expect((await stop(client, child.id, 'm1')).error?.code).toBe(-32002);
      expect((await stop(client, main, 'm1')).result?.id).toBe('m1');
    }));

  test('session load replays no monitor notifications or running monitor processes', () =>
    withExtensionWire([], {}, async (client, newSession, cwd) => {
      const sessionId = await newSession();

      await client.answerTo(wirePrompt(client, sessionId, 'monitors'));
      await until(
        () => wireMonitors(client, sessionId).at(-1)?.running.length === 2,
      );
      await client.request('session/close', { sessionId });

      const seen = client.messages.length;
      const loaded = await client.request('session/load', {
        sessionId,
        cwd,
        mcpServers: [],
      });

      expect(loaded.error).toBeUndefined();
      await client.request('session/list', {});
      expect(
        client.messages
          .slice(seen)
          .filter((message) => message.method === '_chord/monitors/changed'),
      ).toEqual([]);
      expect((await stop(client, sessionId, 'm1')).error?.code).toBe(-32002);
    }));
});
