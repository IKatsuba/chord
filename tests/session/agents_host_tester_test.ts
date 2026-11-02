import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, test } from 'bun:test';
import {
  createAgentsHost,
  type AgentsEvent,
} from '../../src/session/agents_host.ts';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import { openSession, type Session } from '../../src/session/session.ts';
import { emptyTranscript } from '../../src/session/transcript/types.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { heldSession, isAlive, until } from './conversation_fake.ts';

describe('CHD-580 layer 1 tester: independent closing sessions', () => {
  test('spend settles independently in reverse order, including a failed close', async () => {
    const told: AgentsEvent[] = [];
    const host = createAgentsHost(
      {
        place: {
          cwd: tmpdir(),
          startupOf: () => ({}),
          mcpServers: [],
          mcpIgnored: [],
        },
        runtimes: ['fake'],
        home: undefined,
        configHome: undefined,
        conversation: (_, emit) =>
          new Conversation(() => Promise.resolve(heldSession().session), emit),
      },
      {
        heard: () => {},
        closingHeard: () => {},
        told: (event) => told.push(event),
        stateOf: () => undefined,
      },
    );
    const first = Promise.withResolvers<void>();
    const second = Promise.withResolvers<void>();
    const place = { name: 'one', kind: 'agent', runtime: 'fake' } as const;

    host.keepSpend(1, place)(first.promise);
    host.keepSpend(2, { ...place, name: 'two' })(second.promise);
    second.reject(new Error('failed close'));
    await until(() => told.some((event) => event.type === 'spend_closed'));

    expect(
      told.map((event) => [event.type, 'key' in event && event.key]),
    ).toEqual([
      ['spend_closing', 1],
      ['spend_closing', 2],
      ['spend_closed', 2],
    ]);

    first.resolve();
    await until(() => told.length === 4);

    expect(told[3]).toEqual({ type: 'spend_closed', key: 1 });
  });

  for (const hanging of [false, true]) {
    test(`closing a ${hanging ? 'hung' : 'cancelled'} child keeps its sibling alive and retires late events`, async () => {
      const dir = await mkdtemp(join(tmpdir(), 'chord-host-tester-'));
      const heard: [number, ConversationEvent][] = [];
      const closing: [number, ConversationEvent][] = [];
      const told: AgentsEvent[] = [];
      const opened: Session[] = [];
      const host = createAgentsHost(
        {
          place: {
            cwd: dir,
            startupOf: () => ({}),
            mcpServers: [],
            mcpIgnored: [],
          },
          runtimes: ['fake'],
          home: undefined,
          configHome: undefined,
          conversation: (_, emit) =>
            new Conversation(
              () => Promise.resolve(heldSession().session),
              emit,
            ),
        },
        {
          heard: (key, event) => heard.push([key, event]),
          closingHeard: (key, event) => closing.push([key, event]),
          told: (event) => told.push(event),
          stateOf: () => ({
            queue: [],
            transcript: {
              ...emptyTranscript,
              turn: { status: 'working', turnId: 'busy', since: 1 },
            },
          }),
        },
      );

      try {
        const main = host.sessions.start('fake')!;
        const open = (id: string, flags: string[]) =>
          host.sessions.openChild(
            { id, name: id, runtime: 'fake', openedAt: 1 },
            (emit) =>
              new Conversation(async (signal) => {
                const session = await openSession({
                  agent: 'fake',
                  cwd: dir,
                  agentCommand: fakeAgentCommand(undefined, ...flags),
                  signal,
                });

                opened.push(session);

                return session;
              }, emit),
          )!;
        const child = open('closing', hanging ? ['--hang', 'turn'] : []);
        const sibling = open('survivor', []);

        await until(() =>
          [main, child, sibling].every((key) =>
            heard.some(
              ([at, event]) => at === key && event.type === 'connected',
            ),
          ),
        );

        const conversation = host.conversationAt(child)!;
        const session = conversation.session!;
        const pids = [...session.agentPids];

        expect(conversation.send('costwaitlate')).toBe(true);
        await until(() =>
          heard.some(
            ([at, event]) =>
              at === child &&
              (hanging
                ? event.type === 'prompt'
                : event.type === 'update' &&
                  event.update.sessionUpdate === 'usage_update'),
          ),
        );
        host.dropChild(child);

        expect(host.conversationAt(child)).toBeUndefined();
        expect(host.conversationAt(sibling)).toBeDefined();
        expect(told.some((event) => event.type === 'agents_unfocused')).toBe(
          false,
        );

        const before = heard.filter(([at]) => at === child).length;

        host.dropChild(child);
        await until(() =>
          told.some(
            (event) => event.type === 'spend_closed' && event.key === child,
          ),
        );

        expect(heard.filter(([at]) => at === child)).toHaveLength(before);
        expect(closing.some(([at]) => at === child)).toBe(true);
        expect(
          told.filter((event) => event.type === 'session_closed'),
        ).toHaveLength(1);

        for (const pid of pids) {
          expect(await isAlive(pid)).toBe(false);
        }

        expect(host.conversationAt(sibling)!.send('hello')).toBe(true);
        await until(() =>
          heard.some(
            ([at, event]) => at === sibling && event.type === 'result',
          ),
        );
      } finally {
        await host.sessions.closeAll();

        for (const session of opened) {
          expect(session.agentPids.size).toBe(0);
        }

        await rm(dir, { recursive: true });
      }
    });
  }
});
