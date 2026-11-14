/**
 * Renaming a session (CHD-629): `session/set_title` where the agent takes a
 * title, a rename chain of the session's own, and the record's `renamed`
 * line from the answer.
 */
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import { FileRecording, parseRecord } from '../../src/session/record.ts';
import { readRecords, type Resume } from '../../src/session/sessions.ts';
import { openSession } from '../../src/session/session.ts';
import { agentMessageOf } from '../../src/session/starting.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { TITLES_HEARD } from '../fixtures/fake_agent/scenarios/titles.ts';
import { until } from './conversation_fake.ts';

/**
 * A conversation on the fake under `flags`, with its record, prompted once
 * so the record is kept; `lines` reads back the record's kinds of `kinds`.
 */
async function renaming(
  flags: readonly string[],
  body: (seen: {
    conversation: Conversation;
    events: ConversationEvent[];
    dir: string;
    /** Each title handed to the session's setTitle, as it was called. */
    asked: string[];
    lines: (...kinds: string[]) => Promise<unknown[]>;
  }) => Promise<void>,
) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-rename-'));
  const stateDir = join(dir, 'state');
  const events: ConversationEvent[] = [];
  const recording = new FileRecording(stateDir, () => {});

  const asked: string[] = [];
  const conversation = new Conversation(
    async () => {
      const session = await openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(undefined, ...flags),
      });

      return {
        ...session,
        setTitle: (title: string) => {
          asked.push(title);

          return session.setTitle(title);
        },
      };
    },
    (event) => events.push(event),
    Date.now,
    {},
    recording,
  );
  const lines = async (...kinds: string[]) => {
    await recording.flushed();

    const records = await readRecords(stateDir);

    return (
      await Promise.all(
        records.map(async ({ path }) =>
          parseRecord(await readFile(path, 'utf8')),
        ),
      )
    )
      .flat()
      .filter(
        (entry) =>
          kinds.includes(entry.type) &&
          (entry.type !== 'update' ||
            entry.update.sessionUpdate === 'session_info_update'),
      )
      .map((entry) =>
        entry.type === 'renamed'
          ? { type: 'renamed', title: entry.title }
          : entry.type === 'update' &&
              entry.update.sessionUpdate === 'session_info_update'
            ? { type: 'update', title: entry.update.title }
            : entry,
      );
  };

  try {
    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));
    conversation.send('text');
    await until(() => events.some((event) => event.type === 'result'));
    await body({ conversation, events, dir, asked, lines });
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }
}

/** The titles whose `session/set_title` reached the fake, in order. */
async function heard(dir: string): Promise<string[]> {
  const text = await readFile(
    join(dir, '.fake-gate', TITLES_HEARD),
    'utf8',
  ).catch(() => '');

  return text.split('\n').filter((line) => line !== '');
}

/** Until the fake has heard `count` titles. */
async function hearing(dir: string, count: number): Promise<void> {
  let titles: string[] = [];

  await until(() => {
    void heard(dir).then((now) => (titles = now));

    return titles.length >= count;
  });
}

/** Opens `dir`'s fake gate, which `--set-title hang` waits on. */
async function release(dir: string): Promise<void> {
  await mkdir(join(dir, '.fake-gate'), { recursive: true });
  await writeFile(join(dir, '.fake-gate', 'release'), '');
}

describe('a rename (CHD-629)', () => {
  test("an agent that echoes it stores and says the title before it answers; the record keeps its update and then chord's line from the answer", () =>
    renaming(['--set-title', 'echo'], async ({ conversation, lines }) => {
      expect(await conversation.rename('Fix   the\nparser')).toStrictEqual({
        title: 'Fix the parser',
        agent: true,
      });
      expect(conversation.title).toBe('Fix the parser');
      expect(await lines('update', 'renamed')).toStrictEqual([
        { type: 'update', title: 'Fix the parser' },
        { type: 'renamed', title: 'Fix the parser' },
      ]);
    }));

  test('a silent answer is the title as the agent stored it, recorded from the answer', () =>
    renaming(['--set-title', 'silent'], async ({ conversation, lines }) => {
      const long = 'x'.repeat(100);

      expect(await conversation.rename(long)).toStrictEqual({
        title: 'x'.repeat(80),
        agent: true,
      });
      expect(conversation.title).toBe('x'.repeat(80));
      expect(await lines('update', 'renamed')).toStrictEqual([
        { type: 'renamed', title: 'x'.repeat(80) },
      ]);
    }));

  test("a refusal records nothing, leaves the title, and rejects with the agent's words (the owner's Q1 a)", () =>
    renaming(['--set-title', 'refuse'], async ({ conversation, lines }) => {
      const refused = await conversation.rename('Fix the parser').then(
        () => undefined,
        (error: unknown) => error,
      );

      expect(agentMessageOf(refused)).toContain('cannot rename');
      expect(conversation.title).toBeUndefined();
      expect(await lines('renamed')).toStrictEqual([]);
    }));

  test('an agent that takes no title is renamed in chord alone, the typed title folded', () =>
    renaming([], async ({ conversation, lines }) => {
      expect(await conversation.rename('  Fix  the parser ')).toStrictEqual({
        title: 'Fix the parser',
        agent: false,
      });
      expect(await lines('renamed')).toStrictEqual([
        { type: 'renamed', title: 'Fix the parser' },
      ]);
    }));

  test('two renames go one at a time, in order, the second off the wire until the first is answered, and the second holds', () =>
    renaming(
      ['--set-title', 'hang'],
      async ({ conversation, dir, asked, lines }) => {
        const first = conversation.rename('First');

        await hearing(dir, 1);

        const second = conversation.rename('Second');

        // Its turn in the chain comes only once the first's answer has: by
        // the time the chain's next link would have run, nothing more was asked.
        await Promise.resolve();
        await Promise.resolve();
        expect(asked).toStrictEqual(['First']);

        await release(dir);
        await Promise.all([first, second]);

        expect(asked).toStrictEqual(['First', 'Second']);
        expect(await heard(dir)).toStrictEqual(['First', 'Second']);

        expect(conversation.title).toBe('Second');
        expect(await lines('renamed')).toStrictEqual([
          { type: 'renamed', title: 'First' },
          { type: 'renamed', title: 'Second' },
        ]);
      },
    ));

  test('a /clear while a rename is out drops its answer: the new session keeps no title and neither record has the line', () =>
    renaming(['--set-title', 'hang'], async ({ conversation, dir, lines }) => {
      const renamed = conversation.rename('Fix the parser');

      // The request is with the agent, not waiting in chord.
      await hearing(dir, 1);
      await conversation.clear();
      await release(dir);

      expect(await renamed).toBeUndefined();
      expect(conversation.title).toBeUndefined();
      expect(await lines('renamed')).toStrictEqual([]);
    }));

  test('a rename still queued when /clear comes is never sent', () =>
    renaming(['--set-title', 'hang'], async ({ conversation, dir, lines }) => {
      const first = conversation.rename('First');

      await hearing(dir, 1);

      const queued = conversation.rename('Queued');

      await conversation.clear();
      await release(dir);

      expect(await first).toBeUndefined();
      expect(await queued).toBeUndefined();
      expect(await heard(dir)).toStrictEqual(['First']);
      expect(await lines('renamed')).toStrictEqual([]);
    }));

  test('a rename during a turn goes at once: a title is not a prompt', () =>
    renaming(['--set-title', 'echo'], async ({ conversation, events }) => {
      const results = () =>
        events.filter((event) => event.type === 'result').length;

      conversation.send('texttillsteered');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'prompt' && event.text === 'texttillsteered',
        ),
      );

      expect(await conversation.rename('Mid-turn')).toStrictEqual({
        title: 'Mid-turn',
        agent: true,
      });
      expect(results()).toBe(1);
    }));

  test("the agent's own title later takes over: last title wins, whoever set it", () =>
    renaming(['--set-title', 'echo'], async ({ conversation, dir, events }) => {
      await conversation.rename('Mine');
      conversation.send('titledlater');
      await until(() =>
        events.some(
          (event) => event.type === 'prompt' && event.text === 'titledlater',
        ),
      );
      await release(dir);
      await until(() => conversation.title === 'Tidy the parser tests');
    }));
});

describe('CHD-629 tester: rename lifecycle boundaries', () => {
  test('a refused empty title does not poison the next rename or change the record', () =>
    renaming(
      ['--set-title', 'silent', '--title', 'Existing title'],
      async ({ conversation, lines }) => {
        await expect(conversation.rename(' \n ')).rejects.toThrow('empty');
        expect(conversation.title).toBe('Existing title');
        expect(await lines('renamed')).toEqual([]);
        expect(await conversation.rename('Next title')).toEqual({
          title: 'Next title',
          agent: true,
        });
        expect(await lines('renamed')).toEqual([
          { type: 'renamed', title: 'Next title' },
        ]);
      },
    ));

  test('a rename before any prompt does not keep a session record', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-rename-only-'));
    const stateDir = join(dir, 'state');
    const events: ConversationEvent[] = [];
    const recording = new FileRecording(stateDir, () => {});

    const conversation = new Conversation(
      () =>
        openSession({
          agent: 'fake',
          cwd: dir,
          agentCommand: fakeAgentCommand(undefined, '--set-title', 'silent'),
        }),
      (event) => events.push(event),
      Date.now,
      {},
      recording,
    );

    try {
      conversation.start();
      await until(() => events.some((event) => event.type === 'connected'));
      await conversation.rename('No prompt yet');
      await conversation.close();
      await recording.flushed();
      expect(await readRecords(stateDir)).toEqual([]);
    } finally {
      await conversation.close();
      await rm(dir, { recursive: true });
    }
  });

  test('a config request hung at the agent cannot hold a rename', () =>
    renaming(
      ['--set-title', 'echo', '--hang', 'config'],
      async ({ conversation, events, lines }) => {
        void conversation.setMode('plan').catch(() => {});

        const from = events.length;

        conversation.send('configsheard');
        await until(() =>
          events
            .slice(from)
            .some(
              (event) =>
                event.type === 'update' &&
                event.update.sessionUpdate === 'agent_message_chunk' &&
                event.update.content.type === 'text' &&
                event.update.content.text.includes('"configId": "mode"'),
            ),
        );

        expect(await conversation.rename('While config waits')).toEqual({
          title: 'While config waits',
          agent: true,
        });
        expect(await lines('renamed')).toEqual([
          { type: 'renamed', title: 'While config waits' },
        ]);
      },
    ));

  test('a held rename holds neither the config chain nor another session', () =>
    renaming(['--set-title', 'hang'], async ({ conversation, dir }) => {
      const pending = conversation.rename('First connection');

      await hearing(dir, 1);
      await conversation.setMode('plan');
      expect(conversation.session?.modes()?.current).toBe('plan');
      await renaming(['--set-title', 'echo'], async (other) => {
        expect(await other.conversation.rename('Other connection')).toEqual({
          title: 'Other connection',
          agent: true,
        });
        expect(conversation.title).toBeUndefined();
      });

      await release(dir);
      expect(await pending).toEqual({ title: 'First connection', agent: true });
    }));

  test('an agent exiting with a rename pending leaves the last title and records no rename', () =>
    renaming(
      ['--set-title', 'hang', '--title', 'Existing title'],
      async ({ conversation, dir, lines }) => {
        const pending = conversation.rename('Never answered').then(
          () => undefined,
          (error: unknown) => error,
        );

        await hearing(dir, 1);

        const session = conversation.session;

        assert(session);
        await session.close();
        expect(await pending).toBeInstanceOf(Error);
        expect(conversation.title).toBe('Existing title');
        expect(await lines('renamed')).toEqual([]);
      },
    ));

  test('cancelling a turn does not revoke subsequent title changes', () =>
    renaming(['--set-title', 'silent'], async ({ conversation, events }) => {
      const from = events.length;

      conversation.send('slow');
      await until(() =>
        events
          .slice(from)
          .some(
            (event) =>
              event.type === 'update' &&
              event.update.sessionUpdate === 'agent_message_chunk',
          ),
      );
      conversation.interrupt();
      await until(() =>
        events.slice(from).some((event) => event.type === 'result'),
      );

      expect(await conversation.rename('After cancellation')).toEqual({
        title: 'After cancellation',
        agent: true,
      });
      expect(conversation.title).toBe('After cancellation');
    }));

  test('a silent normalized title is identical live, in the picker record, and after resume', () =>
    renaming(
      ['--set-title', 'silent'],
      async ({ conversation, dir, lines }) => {
        const title = 'x'.repeat(80);

        await conversation.rename('x'.repeat(120));
        await lines('renamed');
        await conversation.close();

        const [record] = await readRecords(join(dir, 'state'));

        assert(record);
        expect(record.title).toBe(title);

        const events: ConversationEvent[] = [];
        const resumed = new Conversation(
          () =>
            openSession({
              agent: 'fake',
              cwd: dir,
              agentCommand: fakeAgentCommand(
                undefined,
                '--set-title',
                'silent',
                '--resume-only',
              ),
              resume: {
                sessionId: record.sessionId,
                cwd: dir,
                record: record.path,
              },
            }),
          (event) => events.push(event),
        );

        try {
          resumed.start();
          await until(() => events.some((event) => event.type === 'connected'));
          expect(resumed.title).toBe(title);
          expect(conversation.title).toBe(title);
        } finally {
          await resumed.close();
        }
      },
    ));
});

describe('a rename and the record (CHD-629)', () => {
  test('a session opened from its record keeps a rename without a prompt: the line is written at once', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-rename-'));
    const stateDir = join(dir, 'state');
    const opened = async (resume?: Resume) => {
      const events: ConversationEvent[] = [];
      const recording = new FileRecording(stateDir, () => {});

      const conversation = new Conversation(
        () =>
          openSession({
            agent: 'fake',
            cwd: dir,
            agentCommand: fakeAgentCommand(undefined, '--set-title', 'echo'),
            ...(resume === undefined ? {} : { resume }),
          }),
        (event) => events.push(event),
        Date.now,
        {},
        recording,
      );

      conversation.start();
      await until(() => events.some((event) => event.type === 'connected'));

      return { conversation, events, recording };
    };

    try {
      const first = await opened();

      first.conversation.send('text');
      await until(() => first.events.some((event) => event.type === 'result'));
      await first.conversation.close();
      await first.recording.flushed();

      const [record] = await readRecords(stateDir);

      assert(record);

      const again = await opened({
        sessionId: record.sessionId,
        cwd: dir,
        record: record.path,
      });

      await again.conversation.rename('x'.repeat(100));
      await again.conversation.close();
      await again.recording.flushed();

      const [after] = await readRecords(stateDir);

      expect(after?.title).toBe('x'.repeat(80));
      expect(
        parseRecord(await readFile(record.path, 'utf8')).filter(
          (entry) => entry.type === 'renamed',
        ),
      ).toStrictEqual([
        expect.objectContaining({ type: 'renamed', title: 'x'.repeat(80) }),
      ]);
    } finally {
      await rm(dir, { recursive: true });
    }
  });

  test('a new session renamed and left without a prompt leaves no record', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-rename-'));
    const stateDir = join(dir, 'state');
    const events: ConversationEvent[] = [];
    const recording = new FileRecording(stateDir, () => {});

    const conversation = new Conversation(
      () =>
        openSession({
          agent: 'fake',
          cwd: dir,
          agentCommand: fakeAgentCommand(undefined, '--set-title', 'echo'),
        }),
      (event) => events.push(event),
      Date.now,
      {},
      recording,
    );

    try {
      conversation.start();
      await until(() => events.some((event) => event.type === 'connected'));
      await conversation.rename('Fix the parser');
      await conversation.close();
      await recording.flushed();

      expect(await readRecords(stateDir)).toStrictEqual([]);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});
