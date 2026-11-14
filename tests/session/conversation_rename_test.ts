/**
 * Renaming a session (CHD-629): `session/set_title` where the agent takes a
 * title, a rename chain of the session's own, and the record's `renamed`
 * line from the answer.
 */
import { describe, expect, test } from 'bun:test';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import { FileRecording, parseRecord } from '../../src/session/record.ts';
import { readRecords } from '../../src/session/sessions.ts';
import { openSession } from '../../src/session/session.ts';
import { agentMessageOf } from '../../src/session/starting.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
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
    lines: (...kinds: string[]) => Promise<unknown[]>;
  }) => Promise<void>,
) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-rename-'));
  const stateDir = join(dir, 'state');
  const events: ConversationEvent[] = [];
  const recording = new FileRecording(stateDir, () => {});

  const conversation = new Conversation(
    () =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(undefined, ...flags),
      }),
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
    await body({ conversation, events, dir, lines });
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }
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

  test('two renames go one at a time, in order, and the second holds', () =>
    renaming(['--set-title', 'hang'], async ({ conversation, dir, lines }) => {
      const first = conversation.rename('First');
      const second = conversation.rename('Second');

      await release(dir);
      await Promise.all([first, second]);

      expect(conversation.title).toBe('Second');
      expect(await lines('renamed')).toStrictEqual([
        { type: 'renamed', title: 'First' },
        { type: 'renamed', title: 'Second' },
      ]);
    }));

  test('a /clear while a rename is out drops its answer: the new session keeps no title and neither record has the line', () =>
    renaming(['--set-title', 'hang'], async ({ conversation, dir, lines }) => {
      const renamed = conversation.rename('Fix the parser');

      await conversation.clear();
      await release(dir);

      expect(await renamed).toBeUndefined();
      expect(conversation.title).toBeUndefined();
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
