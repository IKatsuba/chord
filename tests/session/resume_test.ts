import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import process from 'node:process';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  FileRecording,
  parseRecord,
  readPast,
  recordActions,
  type RecordEntry,
} from '../../src/session/record.ts';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import { plainText } from '../../src/session/terminal_text.ts';
import { TaskAgent } from '../../src/session/tasks.ts';
import {
  openSession,
  type PastAction,
  type Session,
} from '../../src/session/session.ts';
import {
  earlierSessions,
  latestSession,
  readRecords,
  type Resume,
  sessionById,
  sessionsIn,
} from '../../src/session/sessions.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type Entry,
  type TranscriptAction,
} from '../../src/session/transcript/types.ts';
import { sessionTokens } from '../../src/ui/transcript/reports.ts';
import {
  type AppState,
  initialAppState,
  reduceApp,
} from '../../src/ui/app/state.ts';
import { EDIT_NEW } from '../fixtures/edits.ts';
import { BASH_OUTPUT, SHELL_OUTPUT } from '../fixtures/terminals.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { recordSession } from '../fixtures/records.ts';
import { play } from '../fixtures/recorder.ts';

interface Place {
  readonly dir: string;
  readonly stateDir: string;
  /** The fake agent as it loads a session, replaying its past. */
  readonly command: string[];
  /** The fake agent offering `session/resume`, which replays nothing. */
  readonly resuming: string[];
}

async function withPlace(body: (place: Place) => Promise<void>) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-resume-'));

  try {
    await body({
      dir,
      stateDir: join(dir, 'state'),
      command: fakeAgentCommand(),
      resuming: fakeAgentCommand(undefined, '--resume-only'),
    });
  } finally {
    await rm(dir, { recursive: true });
  }
}

function open(
  { dir }: Place,
  command: string[],
  resume?: Resume,
): Promise<Session> {
  return openSession({
    agent: 'fake',
    cwd: resume?.cwd ?? dir,
    agentCommand: command,
    ...(resume === undefined ? {} : { resume }),
  });
}

/** What the transcript shows of a session's past, one line per entry. */
function drawn(entries: readonly Entry[]): string[] {
  return entries.map((entry) => {
    switch (entry.kind) {
      case 'user':
      case 'assistant':
      case 'thought':
        return `${entry.kind}: ${entry.text}`;
      case 'tool': {
        const diff = entry.call.content?.some((each) => each.type === 'diff')
          ? ' with its diff'
          : '';

        return `tool: ${entry.call.title} ${entry.call.status}${diff}`;
      }
      default:
        return entry.kind;
    }
  });
}

function replayed(history: readonly PastAction[]): string[] {
  return drawn(
    history
      .filter((action): action is TranscriptAction => action.type !== 'usage')
      .reduce(reduceTranscript, emptyTranscript).entries,
  );
}

/**
 * The window's state once the record of session `id` is reopened through
 * `session/resume`, with `prompts` sent in it.
 */
async function reopened(
  place: Place,
  id: string,
  options: Pick<Parameters<typeof recordSession>[0], 'starting'> & {
    prompts?: readonly string[];
  } = {},
): Promise<AppState> {
  const [record] = await readRecords(place.stateDir);

  assert(record !== undefined);

  const events: ConversationEvent[] = [];

  await recordSession({
    stateDir: place.stateDir,
    cwd: place.dir,
    command: place.resuming,
    prompts: options.prompts ?? [],
    resume: { sessionId: id, cwd: place.dir, record: record.path },
    ...(options.starting === undefined ? {} : { starting: options.starting }),
    heard: (event) => events.push(event),
  });

  return events.reduce(reduceApp, initialAppState);
}

/** The past the fake agent replays for any session it loads. */
const AGENT_PAST = [
  'user: tools',
  'tool: Read README.md completed',
  'assistant: Read it.',
  'user: text',
  'assistant: Hello, world. This reply came in chunks.',
];

/** The past chord recorded of a session with an `edit` and a `text` turn. */
const RECORDED_PAST = [
  'user: edit',
  'tool: Edit src/greeting.ts completed with its diff',
  'assistant: Edited.',
  'user: text',
  'assistant: Hello, world. This reply came in chunks.',
];

/** A session with an edit and a reply in it, closed, as chord left it. */
async function earlier(
  place: Place,
  { cwd = place.dir, prompts = ['edit', 'text'] } = {},
): Promise<string> {
  await mkdir(cwd, { recursive: true });

  return await recordSession({
    stateDir: place.stateDir,
    cwd,
    command: place.command,
    prompts,
  });
}

async function only(place: Place): Promise<RecordEntry[]> {
  const [record, ...more] = await readRecords(place.stateDir);

  assert(record !== undefined && more.length === 0, 'one record');

  return await readPast(record.path);
}

test('a session is recorded as the reducer saw it: its id, each prompt, updates whole, usage and what it is on', () =>
  withPlace(async (place) => {
    const id = await earlier(place);
    const entries = await only(place);
    const [header] = entries;

    assert(header?.type === 'session');
    expect({
      sessionId: header.sessionId,
      agent: header.agent,
      cwd: header.cwd,
    }).toStrictEqual({ sessionId: id, agent: 'fake', cwd: place.dir });
    expect(
      entries.flatMap((entry) =>
        entry.type === 'prompt' ? [entry.prompt] : [],
      ),
    ).toStrictEqual(['edit', 'text']);

    // The edit's kind, locations and diff, as the agent sent them.
    const call = entries.find(
      (entry) =>
        entry.type === 'update' && entry.update.sessionUpdate === 'tool_call',
    );
    const diff = entries.find(
      (entry) =>
        entry.type === 'update' &&
        entry.update.sessionUpdate === 'tool_call_update',
    );

    assert(
      call?.type === 'update' && call.update.sessionUpdate === 'tool_call',
    );
    expect(call.update.kind).toStrictEqual('edit');
    expect(call.update.locations).toStrictEqual([
      { path: 'src/greeting.ts', line: 1 },
    ]);
    assert(
      diff?.type === 'update' &&
        diff.update.sessionUpdate === 'tool_call_update',
    );
    expect(diff.update.content?.[0]?.type).toStrictEqual('diff');
    expect(
      diff.update.content?.[0]?.type === 'diff' &&
        diff.update.content[0].newText,
    ).toStrictEqual(EDIT_NEW);
    expect(
      entries
        .filter((entry) => entry.type === 'result')
        .map((entry) => entry.type === 'result' && entry.result.status),
    ).toStrictEqual(['completed', 'completed']);
    expect(
      entries.flatMap((entry) =>
        entry.type === 'usage' ? [entry.usage.totalTokens] : [],
      ),
    ).toStrictEqual([2000, 2000]);
    expect(
      entries.some(
        (entry) =>
          entry.type === 'update' &&
          entry.update.sessionUpdate === 'usage_update',
      ),
    ).toStrictEqual(true);
    expect(entries.find((entry) => entry.type === 'state')).toStrictEqual({
      type: 'state',
      model: 'fake-large',
      mode: 'default',
      options: { effort: 'medium' },
    });
  }));

test('a session nothing was sent in leaves no record', () =>
  withPlace(async (place) => {
    await earlier(place, { prompts: [] });

    expect(await readRecords(place.stateDir)).toStrictEqual([]);
  }));

/** What the agent said in a record, all its message chunks joined. */
function said(entries: readonly RecordEntry[]): string {
  return entries
    .map((entry) =>
      entry.type === 'update' &&
      entry.update.sessionUpdate === 'agent_message_chunk' &&
      entry.update.content.type === 'text'
        ? entry.update.content.text
        : '',
    )
    .join('');
}

test('a prompt with @ mentions is recorded with the links that went, and a reopened session draws it once, as typed', () =>
  withPlace(async (place) => {
    await writeFile(join(place.dir, 'a.ts'), '');

    const id = await recordSession({
      stateDir: place.stateDir,
      cwd: place.dir,
      command: place.command,
      prompts: [
        {
          text: 'look at @a.ts and @nope.ts',
          mentions: ['a.ts', 'nope.ts'],
        },
      ],
    });
    const entries = await only(place);
    const uri = pathToFileURL(join(place.dir, 'a.ts')).href;

    expect(
      entries
        .flatMap((entry) => (entry.type === 'prompt' ? [entry] : []))
        .map(({ prompt, images, links }) => ({ prompt, images, links })),
    ).toStrictEqual([
      {
        prompt: 'look at @a.ts and @nope.ts',
        images: 0,
        links: [{ type: 'resource_link', name: 'a.ts', uri }],
      },
    ]);
    expect(
      said(entries).includes(`Received a link: a.ts, ${uri}`),
    ).toBeTruthy();

    const resume = latestSession(await readRecords(place.stateDir), {
      agent: 'fake',
      cwd: place.dir,
    });

    expect(resume.sessionId).toStrictEqual(id);

    const session = await open(place, place.resuming, resume);

    try {
      expect(
        replayed(session.history()).filter((line) => line.startsWith('user')),
      ).toStrictEqual(['user: look at @a.ts and @nope.ts']);
    } finally {
      await session.close();
    }
  }));

test('a prompt interrupted while its mentions are found never went, and the record has no trace of it', () =>
  withPlace(async (place) => {
    await writeFile(join(place.dir, 'a.ts'), '');
    await recordSession({
      stateDir: place.stateDir,
      cwd: place.dir,
      command: place.command,
      prompts: [
        { text: 'look at @a.ts', mentions: ['a.ts'], interrupt: true },
        'text',
      ],
    });

    const entries = await only(place);

    expect(
      entries.flatMap((entry) =>
        entry.type === 'prompt' ? [entry.prompt] : [],
      ),
    ).toStrictEqual(['text']);
    expect(
      entries.flatMap((entry) =>
        entry.type === 'result' ? [entry.result.status] : [],
      ),
    ).toStrictEqual(['completed']);
    expect(!said(entries).includes('Received a link')).toBeTruthy();
  }));

test("a reopened session folds its commands' terminals as they were live: Codex's streamed output and Claude's whole", () =>
  withPlace(async (place) => {
    const live: ConversationEvent[] = [];
    const id = await recordSession({
      stateDir: place.stateDir,
      cwd: place.dir,
      command: place.command,
      prompts: ['shell', 'bash'],
      heard: (event) => live.push(event),
    });
    const terminals = (actions: readonly TranscriptAction[]) =>
      actions
        .reduce(reduceTranscript, emptyTranscript)
        .entries.flatMap((entry) =>
          entry.kind === 'tool' ? (entry.call.terminals ?? []) : [],
        );
    const liveTerminals = terminals(
      live.filter(
        (event): event is TranscriptAction =>
          event.type === 'prompt' ||
          event.type === 'update' ||
          event.type === 'result',
      ),
    );

    expect(
      liveTerminals.map(({ output, exitCode }) => ({ output, exitCode })),
    ).toStrictEqual([
      { output: plainText(SHELL_OUTPUT.join('')), exitCode: 1 },
      {
        output: BASH_OUTPUT,
        exitCode: 0,
      },
    ]);

    const records = await readRecords(place.stateDir);
    // The state keeps plain text; the record keeps every delta as it came,
    // escapes included, so the colours stay to be read again.
    const deltas = (await readPast(records[0]!.path)).flatMap((entry) => {
      const meta =
        entry.type === 'update' &&
        entry.update.sessionUpdate === 'tool_call_update'
          ? (entry.update._meta?.terminal_output_delta as
              { data?: string } | undefined)
          : undefined;

      return meta?.data === undefined ? [] : [meta.data];
    });

    expect(deltas).toStrictEqual([...SHELL_OUTPUT, BASH_OUTPUT]);

    const resume = sessionById(records, id, {
      agent: 'fake',
      cwd: place.dir,
    });
    const session = await open(place, place.resuming, resume);

    try {
      expect(
        terminals(
          session
            .history()
            .filter(
              (action): action is TranscriptAction => action.type !== 'usage',
            ),
        ),
      ).toStrictEqual(liveTerminals);
    } finally {
      await session.close();
    }
  }));

test('a call after a resume in a fresh agent is a new call under the new prompt, live and reopened', () =>
  withPlace(async (place) => {
    const id = await earlier(place, { prompts: ['shell'] });
    const [record] = await readRecords(place.stateDir);

    assert(record !== undefined);

    const resume = { sessionId: id, cwd: place.dir, record: record.path };
    const live: ConversationEvent[] = [];

    // A fresh process, through `session/resume`, which replays nothing: it
    // has no count of the calls the first one numbered.
    await recordSession({
      stateDir: place.stateDir,
      cwd: place.dir,
      command: place.resuming,
      prompts: ['shell'],
      resume,
      heard: (event) => live.push(event),
    });

    /** Each call, the prompt it came under, its terminals and their output. */
    const calls = (entries: readonly Entry[]) => {
      let prompt = 0;

      return entries.flatMap((entry) => {
        prompt += entry.kind === 'user' ? 1 : 0;

        return entry.kind === 'tool'
          ? [
              {
                prompt,
                id: entry.call.id,
                terminals: (entry.call.terminals ?? []).map(
                  ({ id, output, exitCode }) => ({ id, output, exitCode }),
                ),
              },
            ]
          : [];
      });
    };

    const seen = calls(
      live.reduce(reduceApp, initialAppState).transcript.entries,
    );
    const [first, second] = seen;

    expect(seen.map(({ prompt }) => prompt)).toStrictEqual([1, 2]);
    assert(first !== undefined && second !== undefined);
    expect(first.id !== second.id, `${first.id} came again`).toBeTruthy();
    expect(first.terminals[0]?.id !== second.terminals[0]?.id).toBeTruthy();

    for (const { terminals } of seen) {
      expect(
        terminals.map(({ output, exitCode }) => ({ output, exitCode })),
      ).toStrictEqual([
        { output: plainText(SHELL_OUTPUT.join('')), exitCode: 1 },
      ]);
    }

    const session = await open(place, place.resuming, resume);

    try {
      expect(
        calls(
          session
            .history()
            .filter(
              (action): action is TranscriptAction => action.type !== 'usage',
            )
            .reduce(reduceTranscript, emptyTranscript).entries,
        ),
      ).toStrictEqual(seen);
    } finally {
      await session.close();
    }
  }));

test('--continue reopens the latest session here, and draws its past from the record when the agent replays none', () =>
  withPlace(async (place) => {
    await earlier(place, { prompts: ['/echo older'] });

    const id = await earlier(place);

    await earlier(place, { cwd: join(place.dir, 'x'), prompts: ['text'] });

    const resume = latestSession(await readRecords(place.stateDir), {
      agent: 'fake',
      cwd: place.dir,
    });

    expect(resume.sessionId).toStrictEqual(id);

    const session = await open(place, place.resuming, resume);

    try {
      expect(session.id).toStrictEqual(id);
      expect(replayed(session.history())).toStrictEqual(RECORDED_PAST);
    } finally {
      await session.close();
    }
  }));

test('a reopened session tells the window first that it resumed, when it was last used and its first prompt', () =>
  withPlace(async (place) => {
    const id = await earlier(place);
    const resume = latestSession(await readRecords(place.stateDir), {
      agent: 'fake',
      cwd: place.dir,
    });
    const events: ConversationEvent[] = [];

    await recordSession({
      stateDir: place.stateDir,
      cwd: place.dir,
      command: place.resuming,
      prompts: [],
      resume,
      heard: (event) => events.push(event),
    });

    const [record] = await readRecords(place.stateDir);

    expect(resume.sessionId).toStrictEqual(id);
    expect(events[0]).toStrictEqual({
      type: 'resumed',
      lastUsedAt: record?.lastUsedAt ?? 0,
      prompt: 'edit',
    });
    expect(
      events.reduce(reduceApp, initialAppState).resumed?.prompt,
    ).toStrictEqual('edit');
  }));

test('--continue with nothing here, or only another agent here, says so', () =>
  withPlace(async (place) => {
    await earlier(place, { cwd: join(place.dir, 'x') });

    const records = await readRecords(place.stateDir);

    for (const find of [
      { agent: 'fake', cwd: place.dir },
      {
        agent: 'claude',
        cwd: join(place.dir, 'x'),
      },
    ]) {
      expect(
        (() => {
          try {
            return latestSession(records, find);
          } catch (error) {
            return (error as Error).message;
          }
        })(),
      ).toStrictEqual(
        `No earlier ${find.agent} session in ${find.cwd} to continue.`,
      );
    }
  }));

test('a recorded session the agent loads is drawn from the record, not its replay, and only once', () =>
  withPlace(async (place) => {
    const id = await earlier(place);
    const resume = sessionById(await readRecords(place.stateDir), id, {
      agent: 'fake',
      cwd: place.dir,
    });
    // The fake agent offers only `session/load` here, which replays its own
    // short past rather than what chord recorded.
    const session = await open(place, place.command, resume);

    try {
      expect(replayed(session.history())).toStrictEqual(RECORDED_PAST);
    } finally {
      await session.close();
    }
  }));

test('a reopened session goes on in its record, and one only looked at leaves it as it was', () =>
  withPlace(async (place) => {
    const id = await earlier(place);
    const [record] = await readRecords(place.stateDir);

    assert(record !== undefined);

    const before = await readFile(record.path, 'utf8');

    await recordSession({
      stateDir: place.stateDir,
      cwd: place.dir,
      command: place.resuming,
      prompts: [],
      resume: { sessionId: id, cwd: place.dir, record: record.path },
    });
    expect(await readFile(record.path, 'utf8')).toStrictEqual(before);

    await recordSession({
      stateDir: place.stateDir,
      cwd: place.dir,
      command: place.resuming,
      prompts: ['/echo NEW-TURN'],
      resume: { sessionId: id, cwd: place.dir, record: record.path },
    });

    const records = await readRecords(place.stateDir);

    expect(records.map(({ path }) => path)).toStrictEqual([record.path]);

    const session = await open(place, place.resuming, {
      sessionId: id,
      cwd: place.dir,
      record: record.path,
    });

    try {
      expect(replayed(session.history())).toStrictEqual([
        ...RECORDED_PAST,
        'user: /echo NEW-TURN',
        'assistant: NEW-TURN',
      ]);
    } finally {
      await session.close();
    }
  }));

test('a message steered into a turn is recorded where it went, and a reopened session draws it there', () =>
  withPlace(async (place) => {
    const steering = fakeAgentCommand(undefined, '--steering', 'claude');
    const events: ConversationEvent[] = [];
    const failures: string[] = [];
    const conversation = new Conversation(
      () =>
        openSession({ agent: 'fake', cwd: place.dir, agentCommand: steering }),
      (event) => events.push(event),
      Date.now,
      {},
      new FileRecording(place.stateDir, (message) => failures.push(message)),
    );
    const until = async (check: () => boolean) => {
      while (!check()) {
        await new Promise((resolve) => setTimeout(resolve, 0));
      }
    };

    try {
      conversation.start();
      await until(() => events.some((event) => event.type === 'connected'));
      conversation.send('permission');
      await until(() =>
        events.some((event) => event.type === 'permission_requested'),
      );
      conversation.tell({ name: 'main', reachable: true }, 'Then the docs.');

      const asked = events.find(
        (event) => event.type === 'permission_requested',
      );

      assert(asked?.type === 'permission_requested');
      conversation.choose(asked.permission.id, 'allow');
      await until(() => events.some((event) => event.type === 'result'));
    } finally {
      await conversation.close();
    }

    expect(failures).toStrictEqual([]);

    const live = drawn(
      events
        .filter((event): event is TranscriptAction =>
          ['prompt', 'update', 'result'].includes(event.type),
        )
        .reduce(reduceTranscript, emptyTranscript).entries,
    );
    const [record] = await readRecords(place.stateDir);

    assert(record !== undefined);

    const into = (await readPast(record.path)).find(
      (entry) => entry.type === 'prompt' && entry.into !== undefined,
    );
    const connected = events.find((event) => event.type === 'connected');

    assert(connected?.type === 'connected');

    const session = await open(place, place.resuming, {
      sessionId: connected.sessionId,
      cwd: place.dir,
      record: record.path,
    });

    try {
      expect(into).toMatchObject({ from: { name: 'main' } });
      expect(replayed(session.history())).toStrictEqual(live);
    } finally {
      await session.close();
    }

    expect(live).toStrictEqual([
      'user: permission',
      'tool: Write notes.txt completed',
      'message',
      'assistant: Read the message from main.\n\nPermission: allow.',
    ]);
  }));

test('--resume by an id chord has a record of opens it in its own directory', () =>
  withPlace(async (place) => {
    const id = await earlier(place);
    const records = await readRecords(place.stateDir);
    const resume = sessionById(records, id, {
      agent: 'fake',
      cwd: '/elsewhere',
    });

    expect(resume).toStrictEqual({
      sessionId: id,
      cwd: place.dir,
      record: records[0]?.path,
      lastUsedAt: records[0]?.lastUsedAt,
      prompt: records[0]?.prompt,
    });
    expect(
      (() => {
        try {
          return sessionById(records, id, { agent: 'codex', cwd: place.dir });
        } catch (error) {
          return (error as Error).message;
        }
      })(),
    ).toStrictEqual(`Session ${id} belongs to another agent (fake).`);
  }));

test('--resume by an id chord never saw goes to the agent, and its replay starts the record', () =>
  withPlace(async (place) => {
    const id = crypto.randomUUID();
    const resume = sessionById([], id, { agent: 'fake', cwd: place.dir });

    expect(resume).toStrictEqual({ sessionId: id, cwd: place.dir });

    const session = await open(place, place.command, resume);

    try {
      expect(session.id).toStrictEqual(id);
      expect(replayed(session.history())).toStrictEqual(AGENT_PAST);

      const actions = await play(session, 'tools');

      expect(actions.at(-1)?.type === 'result').toBeTruthy();
      // A new call in a loaded session does not take an id the past used.
      expect(
        replayed([...session.history(), ...actions]).filter((line) =>
          line.startsWith('tool:'),
        ).length,
      ).toStrictEqual(2);
    } finally {
      await session.close();
    }

    await recordSession({
      stateDir: place.stateDir,
      cwd: place.dir,
      command: place.command,
      prompts: ['/echo after'],
      resume,
    });

    // Opened later through `session/resume`, which replays nothing, the
    // record has the past the agent replayed the first time.
    const again = await open(
      place,
      place.resuming,
      latestSession(await readRecords(place.stateDir), {
        agent: 'fake',
        cwd: place.dir,
      }),
    );

    try {
      expect(replayed(again.history())).toStrictEqual([
        ...AGENT_PAST,
        'user: /echo after',
        'assistant: after',
      ]);
    } finally {
      await again.close();
    }
  }));

test('a session the agent cannot load fails the open with its reason', () =>
  withPlace(async (place) => {
    const resume = sessionById([], 'no-such-session', {
      agent: 'fake',
      cwd: place.dir,
    });

    await expect(open(place, place.command, resume)).rejects.toHaveProperty(
      'message',
      'it cannot resume session no-such-session: Resource not found: no-such-session',
    );
  }));

for (const how of ['load', 'resume'] as const) {
  test(`a recorded session the agent refuses to ${how} fails the open with its reason`, () =>
    withPlace(async (place) => {
      const id = await earlier(place);
      const resume = latestSession(await readRecords(place.stateDir), {
        agent: 'fake',
        cwd: place.dir,
      });

      // The agent is started as the session opens, and inherits this.
      process.env.CHORD_FAKE_REFUSE_LOAD = '1';

      try {
        await expect(
          open(place, how === 'load' ? place.command : place.resuming, resume),
        ).rejects.toHaveProperty(
          'message',
          `it cannot resume session ${id}: Resource not found: ${id}`,
        );
      } finally {
        delete process.env.CHORD_FAKE_REFUSE_LOAD;
      }
    }));
}

test('a reopened session counts the tokens its record kept, once, across a follow-up and another reopen', () =>
  withPlace(async (place) => {
    const id = await earlier(place);
    const total = (state: AppState) => sessionTokens(state.spent)?.totalTokens;

    expect(total(await reopened(place, id))).toStrictEqual(4000);
    expect(
      total(await reopened(place, id, { prompts: ['text'] })),
    ).toStrictEqual(6000);
    expect(total(await reopened(place, id))).toStrictEqual(6000);
  }));

test('a reopened session shows the mode it is in now, not the one its past moved to', () =>
  withPlace(async (place) => {
    // `status` moves the session to plan mode.
    const id = await earlier(place, { prompts: ['status'] });
    const state = await reopened(place, id, {
      starting: { mode: { id: 'acceptEdits', from: '--permission-mode' } },
    });

    expect(state.transcript.mode).toStrictEqual('acceptEdits');
    // Without a starting mode, the one the agent reopened it in.
    expect((await reopened(place, id)).transcript.mode).toStrictEqual(
      'default',
    );
  }));

test("/resume lists every directory's records, and this directory's alone", () =>
  withPlace(async (place) => {
    const other = join(place.dir, 'other');
    const here = await earlier(place, { prompts: ['/echo here'] });
    const there = await earlier(place, {
      cwd: other,
      prompts: ['/echo there'],
    });
    const records = await readRecords(place.stateDir);
    const everywhere = earlierSessions(records, { agent: 'fake' });

    expect(
      everywhere.map(({ resume, prompt }) => [resume.sessionId, prompt]),
    ).toStrictEqual([
      [there, '/echo there'],
      [here, '/echo here'],
    ]);
    expect(everywhere[0]?.resume.cwd).toStrictEqual(other);
    expect(sessionsIn(everywhere, place.dir)).toStrictEqual(
      earlierSessions(records, { agent: 'fake', cwd: place.dir }),
    );
    expect(
      earlierSessions(records, { agent: 'fake' }, there).map(
        ({ prompt }) => prompt,
      ),
    ).toStrictEqual(['/echo here']);
  }));

test('a line cut short by a crash is passed over', () => {
  expect(
    parseRecord('{"type":"usage","turnId":"t","usage":{}}\n{"type":"upd'),
  ).toStrictEqual([{ type: 'usage', turnId: 't', usage: {} }]);
});

test("a turn Codex's adapter started on its own and chord cancelled is recorded, and a reopened session draws it closed, apart from the reply before it", () =>
  withPlace(async (place) => {
    const codex = fakeAgentCommand(
      undefined,
      '--steering',
      'codex',
      '--steer-late',
    );
    const events: ConversationEvent[] = [];
    const failures: string[] = [];
    const conversation = new Conversation(
      () => openSession({ agent: 'fake', cwd: place.dir, agentCommand: codex }),
      (event) => events.push(event),
      Date.now,
      {},
      new FileRecording(place.stateDir, (message) => failures.push(message)),
    );
    const until = async (check: () => boolean) => {
      while (!check()) {
        await new Promise((resolve) => setTimeout(resolve, 0));
      }
    };

    try {
      conversation.start();
      await until(() => events.some((event) => event.type === 'connected'));
      conversation.send('text');
      // Until the prompt has gone, its turn takes no message.
      await new Promise((resolve) => setTimeout(resolve, 0));
      conversation.tell({ name: 'main', reachable: true }, 'Then the docs.');
      await until(
        () => events.filter((event) => event.type === 'result').length === 2,
      );
    } finally {
      await conversation.close();
    }

    expect(failures).toStrictEqual([]);

    const live = drawn(
      events
        .filter((event): event is TranscriptAction =>
          ['prompt', 'update', 'result', 'self_started'].includes(event.type),
        )
        .reduce(reduceTranscript, emptyTranscript).entries,
    );
    const [record] = await readRecords(place.stateDir);

    assert(record !== undefined);

    const connected = events.find((event) => event.type === 'connected');

    assert(connected?.type === 'connected');

    const session = await open(place, place.resuming, {
      sessionId: connected.sessionId,
      cwd: place.dir,
      record: record.path,
    });

    try {
      expect(replayed(session.history())).toStrictEqual(live);
    } finally {
      await session.close();
    }

    expect(live).toContain('self_started');
    expect(live.indexOf('self_started')).toBeLessThan(live.indexOf('message'));
  }));

test("a question form's questions and answer are recorded once answered, and a reopened session draws them", () =>
  withPlace(async (place) => {
    const content = {
      next: 'Review existing work',
      next_note: 'tests first',
      token: 'sk-secret',
    };
    const kept = { next: 'Review existing work', next_note: 'tests first' };
    const id = await recordSession({
      stateDir: place.stateDir,
      cwd: place.dir,
      command: place.command,
      prompts: ['askcodex'],
      answer: { action: 'accept', content },
    });
    const entries = await only(place);
    const asked = entries.find((entry) => entry.type === 'asked');
    const answered = entries.find((entry) => entry.type === 'answered');

    assert(asked?.type === 'asked' && asked.wait.mode === 'form');
    expect(asked.wait.questions?.agent).toStrictEqual('codex');
    // When it came is the live box's alone.
    expect('at' in asked.wait).toStrictEqual(false);
    // The secret token stays out of chord's own lines; the fake agent's reply
    // echoing it is the agent's.
    expect(answered).toMatchObject({
      type: 'answered',
      id: asked.wait.id,
      answer: { type: 'accepted', content: kept },
    });
    expect(
      entries.some(
        (entry) =>
          entry.type !== 'update' &&
          JSON.stringify(entry).includes('sk-secret'),
      ),
    ).toStrictEqual(false);

    const entry = (await reopened(place, id)).transcript.entries.find(
      (each) => each.kind === 'elicitation',
    );

    assert(entry?.kind === 'elicitation' && entry.wait.mode === 'form');
    expect(entry.outcome).toStrictEqual('accepted');
    expect(entry.content).toStrictEqual(kept);
    expect(entry.wait.questions?.questions.map(({ id }) => id)).toStrictEqual([
      'next',
      'token',
    ]);
  }));

test("a form no adapter's marks read is recorded answered, with none of its values", () =>
  withPlace(async (place) => {
    const id = await recordSession({
      stateDir: place.stateDir,
      cwd: place.dir,
      command: place.command,
      prompts: ['form'],
      answer: { action: 'accept', content: { name: 'sk-generic' } },
    });
    const entries = await only(place);
    const answered = entries.find((entry) => entry.type === 'answered');

    expect(answered).toMatchObject({ answer: { type: 'accepted' } });
    expect(
      entries.some(
        (entry) =>
          entry.type !== 'update' &&
          JSON.stringify(entry).includes('sk-generic'),
      ),
    ).toStrictEqual(false);

    const entry = (await reopened(place, id)).transcript.entries.find(
      (each) => each.kind === 'elicitation',
    );

    assert(entry?.kind === 'elicitation');
    expect(entry.outcome).toStrictEqual('accepted');
    expect(entry.content).toBeUndefined();
  }));

test('a record kept before forms were recorded draws as it did, with no form', () => {
  const entries = parseRecord(
    [
      '{"type":"prompt","turnId":"t","at":1,"prompt":"askcodex","images":0}',
      '{"type":"result","turnId":"t","result":{"status":"completed","stopReason":"end_turn"}}',
    ].join('\n'),
  );

  expect(
    recordActions(entries)
      .filter((action): action is TranscriptAction => action.type !== 'usage')
      .reduce(reduceTranscript, emptyTranscript)
      .entries.map((entry) => entry.kind),
  ).toStrictEqual(['user']);
});

test('a form the person interrupted is drawn cancelled when the session is reopened, as it was live', () =>
  withPlace(async (place) => {
    const id = await recordSession({
      stateDir: place.stateDir,
      cwd: place.dir,
      command: place.command,
      prompts: ['askcodex'],
      answer: 'interrupt',
    });
    const forms = (await reopened(place, id)).transcript.entries.flatMap(
      (entry) =>
        entry.kind === 'elicitation' && entry.wait.mode === 'form'
          ? [{ outcome: entry.outcome, agent: entry.wait.questions?.agent }]
          : [],
    );

    expect(forms).toStrictEqual([{ outcome: 'cancelled', agent: 'codex' }]);
  }));

test('a form asked and never answered, as chord was stopped, is not drawn again as waiting', () => {
  const wait = {
    id: 'e-1',
    mode: 'form',
    message: 'Questions',
    schema: { type: 'object', properties: {} },
  };
  const transcript = recordActions(
    parseRecord(
      [
        '{"type":"prompt","turnId":"t","at":1,"prompt":"askcodex","images":0}',
        JSON.stringify({ type: 'asked', turnId: 't', wait }),
      ].join('\n'),
    ),
  )
    .filter((action): action is TranscriptAction => action.type !== 'usage')
    .reduce(reduceTranscript, emptyTranscript);

  expect(transcript.asking).toStrictEqual([]);
  expect(
    transcript.entries.map((entry) =>
      entry.kind === 'elicitation' ? entry.outcome : entry.kind,
    ),
  ).toStrictEqual(['user', 'cancelled']);
});

describe('CHD-1 tester: question record replay', () => {
  const forms = (entries: readonly Entry[]) =>
    entries.filter(
      (entry): entry is Extract<Entry, { kind: 'elicitation' }> =>
        entry.kind === 'elicitation',
    );
  const waitFor = async (check: () => boolean) => {
    const deadline = Date.now() + 10_000;

    while (!check()) {
      if (Date.now() > deadline) {
        throw new Error('timed out waiting for the recorded task form');
      }

      await new Promise((resolve) => setTimeout(resolve, 5));
    }
  };

  for (const action of ['accept', 'decline', 'cancel'] as const) {
    test(`${action}: the reopened form keeps its question and exactly one outcome`, () =>
      withPlace(async (place) => {
        const content = { question_0: 'Python', question_0_custom: 'portable' };
        const id = await recordSession({
          stateDir: place.stateDir,
          cwd: place.dir,
          command: place.command,
          prompts: ['askclaudeone'],
          answer: action === 'accept' ? { action, content } : { action },
        });
        const lines = await only(place);
        const asked = lines.filter((entry) => entry.type === 'asked');
        const answered = lines.filter((entry) => entry.type === 'answered');

        expect(asked.length).toBe(1);
        expect(answered.length).toBe(1);

        const state = await reopened(place, id);
        const recorded = forms(state.transcript.entries);

        expect(recorded.length).toBe(1);
        expect(state.transcript.asking).toStrictEqual([]);
        expect(recorded[0]?.outcome).toBe(
          action === 'accept'
            ? 'accepted'
            : action === 'decline'
              ? 'declined'
              : 'cancelled',
        );
        expect(recorded[0]?.content).toStrictEqual(
          action === 'accept' ? content : undefined,
        );
        expect(
          recorded[0]?.wait.mode === 'form' &&
            recorded[0].wait.questions?.questions[0]?.id,
        ).toBe('question_0');
      }));
  }

  test('an unfinished request followed by an answered one never returns as a pending request', () => {
    const wait = (id: string) => ({
      id,
      mode: 'form' as const,
      message: `Question ${id}`,
      schema: {
        type: 'object' as const,
        properties: { q: { type: 'string' as const } },
      },
    });
    const entries: RecordEntry[] = [
      { type: 'prompt', turnId: 'first', at: 1, prompt: 'first', images: 0 },
      { type: 'asked', turnId: 'first', wait: wait('one') },
      { type: 'cancel', turnId: 'first', at: 2 },
      { type: 'prompt', turnId: 'second', at: 3, prompt: 'second', images: 0 },
      { type: 'asked', turnId: 'second', wait: wait('two') },
      {
        type: 'answered',
        turnId: 'second',
        id: 'two',
        answer: { type: 'accepted', content: { q: 'yes' } },
      },
      {
        type: 'result',
        turnId: 'second',
        result: { status: 'completed', stopReason: 'end_turn' },
      },
    ];
    const transcript = recordActions(
      parseRecord(entries.map((entry) => JSON.stringify(entry)).join('\n')),
    )
      .filter((action): action is TranscriptAction => action.type !== 'usage')
      .reduce(reduceTranscript, emptyTranscript);

    expect(transcript.asking).toStrictEqual([]);
    expect(
      forms(transcript.entries).map((entry) => ({
        id: entry.wait.id,
        outcome: entry.outcome,
        content: entry.content,
      })),
    ).toStrictEqual([
      { id: 'one', outcome: 'cancelled', content: undefined },
      { id: 'two', outcome: 'accepted', content: { q: 'yes' } },
    ]);
  });

  test('a task form and a simultaneous parent form replay under their original owners, with task secrets omitted', () =>
    withPlace(async (place) => {
      const events: ConversationEvent[] = [];
      const failures: string[] = [];
      const parentRecord = new FileRecording(place.stateDir, (message) =>
        failures.push(message),
      );
      const parent = new Conversation(
        () => open(place, place.command),
        (event) => events.push(event),
        Date.now,
        {},
        parentRecord,
      );
      let parentId: string | undefined;
      let child: Conversation | undefined;
      let childRecord: FileRecording | undefined;

      try {
        parent.start();
        await waitFor(() => events.some((event) => event.type === 'connected'));

        const connected = events.find((event) => event.type === 'connected');

        assert(connected?.type === 'connected');

        parentId = connected.sessionId;

        parent.send('form');
        await waitFor(() =>
          events.some((event) => event.type === 'elicitation_requested'),
        );

        const rootAsk = events.find(
          (event) => event.type === 'elicitation_requested',
        );
        const task = new TaskAgent(
          {
            id: 'question-task',
            name: 'Question child',
            runtime: 'fake',
            prompt: 'askcodex',
          },
          parent.taskParent('question-task'),
          Date.now,
        );

        assert(rootAsk?.type === 'elicitation_requested');

        childRecord = new FileRecording(
          place.stateDir,
          (message) => failures.push(message),
          Date.now,
          {
            parent: () => parentId,
            name: 'Question child',
            task: task.id,
          },
        );
        child = new Conversation(
          () => open(place, place.command),
          (event) => task.heard(event),
          Date.now,
          {},
          childRecord,
        );

        parent.adopt(task, child);
        await waitFor(() =>
          events.some(
            (event) =>
              event.type === 'elicitation_requested' &&
              event.elicitation.subagentId === task.id,
          ),
        );

        const childAsk = events.find(
          (event) =>
            event.type === 'elicitation_requested' &&
            event.elicitation.subagentId === task.id,
        );

        assert(childAsk?.type === 'elicitation_requested');
        parent.answer(childAsk.elicitation.id, {
          action: 'accept',
          content: {
            next: 'Review existing work',
            next_note: 'task note',
            token: 'task-secret-unit3',
          },
        });
        await waitFor(() => !task.running);
        parent.answer(rootAsk.elicitation.id, {
          action: 'accept',
          content: {
            name: 'parent-app',
            region: 'eu',
            replicas: 2,
          },
        });
        await waitFor(() => events.some((event) => event.type === 'result'));
      } finally {
        await parent.close();
        await child?.close();
      }

      expect(failures).toStrictEqual([]);
      assert(
        parentId !== undefined &&
          parentRecord.path !== undefined &&
          childRecord?.path !== undefined,
      );

      const parentLines = await readPast(parentRecord.path);
      const childLines = await readPast(childRecord.path);
      const childAnswer = childLines.find((entry) => entry.type === 'answered');

      expect(parentLines.filter((entry) => entry.type === 'asked').length).toBe(
        2,
      );
      expect(childAnswer).toMatchObject({
        type: 'answered',
        answer: {
          type: 'accepted',
          content: { next: 'Review existing work', next_note: 'task note' },
        },
      });
      expect(JSON.stringify(childAnswer)).not.toContain('task-secret-unit3');

      const resumed = await open(place, place.resuming, {
        sessionId: parentId,
        cwd: place.dir,
        record: parentRecord.path,
      });

      try {
        const transcript = resumed
          .history()
          .filter(
            (action): action is TranscriptAction => action.type !== 'usage',
          )
          .reduce(reduceTranscript, emptyTranscript);
        const taskEntry = transcript.entries.find(
          (entry) =>
            entry.kind === 'subagent' && entry.subagent.id === 'question-task',
        );

        assert(taskEntry?.kind === 'subagent');

        // Forms are top-level transcript entries live; the wait keeps their owner.
        const replayForms = forms(transcript.entries);
        const childForms = replayForms.filter(
          (entry) => entry.wait.subagentId === 'question-task',
        );
        const rootForms = replayForms.filter(
          (entry) => entry.wait.subagentId === undefined,
        );
        const liveForms = forms(
          events.reduce(reduceApp, initialAppState).transcript.entries,
        );

        expect(replayForms.map((entry) => entry.wait.subagentId)).toStrictEqual(
          liveForms.map((entry) => entry.wait.subagentId),
        );
        expect(replayForms.length).toBe(2);

        expect(rootForms.length).toBe(1);
        // A generic form's values are not kept, so none comes back.
        expect(rootForms[0]?.outcome).toBe('accepted');
        expect(rootForms[0]?.content).toBeUndefined();
        expect(childForms.length).toBe(1);
        expect(childForms[0]?.outcome).toBe('accepted');
        expect(childForms[0]?.content).toStrictEqual({
          next: 'Review existing work',
          next_note: 'task note',
        });
        expect(
          childForms[0]?.wait.mode === 'form' &&
            childForms[0].wait.questions?.questions.find(
              (question) => question.id === 'token',
            )?.secret,
        ).toBe(true);
        expect(transcript.asking).toStrictEqual([]);
      } finally {
        await resumed.close();
      }
    }));
});

describe('CHD-1 tester: task question tool association', () => {
  const waitFor = async (check: () => boolean) => {
    const deadline = Date.now() + 10_000;

    while (!check()) {
      if (Date.now() > deadline) {
        throw new Error('timed out waiting for Claude task');
      }

      await new Promise((resolve) => setTimeout(resolve, 5));
    }
  };

  for (const action of ['accept', 'cancel'] as const) {
    test(`${action}: a Claude task and parent with colliding call IDs retain both associations live and after reopen`, () =>
      withPlace(async (place) => {
        const events: ConversationEvent[] = [];
        const failures: string[] = [];
        const parentRecord = new FileRecording(place.stateDir, (message) =>
          failures.push(message),
        );
        const parent = new Conversation(
          () => open(place, place.command),
          (event) => events.push(event),
          Date.now,
          {},
          parentRecord,
        );
        let parentId: string | undefined;
        let child: Conversation | undefined;
        let childRecord: FileRecording | undefined;

        try {
          parent.start();
          await waitFor(() =>
            events.some((event) => event.type === 'connected'),
          );

          const connected = events.find((event) => event.type === 'connected');

          assert(connected?.type === 'connected');

          parentId = connected.sessionId;

          parent.send('askclaude');
          await waitFor(() =>
            events.some((event) => event.type === 'elicitation_requested'),
          );

          const rootAsk = events.find(
            (event) => event.type === 'elicitation_requested',
          );
          const task = new TaskAgent(
            {
              id: 'question-task',
              name: 'Question child',
              runtime: 'fake',
              prompt: 'askclaude',
            },
            parent.taskParent('question-task'),
            Date.now,
          );

          assert(rootAsk?.type === 'elicitation_requested');

          childRecord = new FileRecording(
            place.stateDir,
            (message) => failures.push(message),
            Date.now,
            {
              parent: () => parentId,
              name: 'Question child',
              task: task.id,
            },
          );
          child = new Conversation(
            () => open(place, place.command),
            (event) => task.heard(event),
            Date.now,
            {},
            childRecord,
          );

          parent.adopt(task, child);
          await waitFor(() =>
            events.some(
              (event) =>
                event.type === 'elicitation_requested' &&
                event.elicitation.subagentId === task.id,
            ),
          );

          const childAsk = events.find(
            (event) =>
              event.type === 'elicitation_requested' &&
              event.elicitation.subagentId === task.id,
          );

          assert(childAsk?.type === 'elicitation_requested');
          parent.answer(childAsk.elicitation.id, {
            action,
            content: {
              question_0: 'Python',
              question_1: ['Tests'],
            },
          });
          await waitFor(() => !task.running);
          parent.answer(rootAsk.elicitation.id, {
            action: 'accept',
            content: {
              question_0: 'Deno (TypeScript) (Recommended)',
              question_1: ['Types'],
            },
          });
          await waitFor(() => events.some((event) => event.type === 'result'));
        } finally {
          await parent.close();
          await child?.close();
        }

        expect(failures).toStrictEqual([]);
        assert(
          parentId !== undefined &&
            parentRecord.path !== undefined &&
            childRecord?.path !== undefined,
        );

        const parentLines = await readPast(parentRecord.path);

        expect(
          parentLines.filter((entry) => entry.type === 'asked'),
        ).toHaveLength(2);

        const resumed = await open(place, place.resuming, {
          sessionId: parentId,
          cwd: place.dir,
          record: parentRecord.path,
        });

        try {
          const transcript = resumed
            .history()
            .filter(
              (action): action is TranscriptAction => action.type !== 'usage',
            )
            .reduce(reduceTranscript, emptyTranscript);
          const taskEntry = transcript.entries.find(
            (entry) =>
              entry.kind === 'subagent' &&
              entry.subagent.id === 'question-task',
          );

          assert(taskEntry?.kind === 'subagent');

          const live = events.reduce(reduceApp, initialAppState).transcript;

          for (const state of [live, transcript]) {
            const main = state.entries.find((entry) => entry.kind === 'tool');
            const task = state.entries.find(
              (entry) => entry.kind === 'subagent',
            );

            assert(main?.kind === 'tool' && task?.kind === 'subagent');

            const childCall = task.subagent.entries.find(
              (entry) => entry.kind === 'tool',
            );

            assert(childCall?.kind === 'tool');
            expect(main.call.id).toBe('ask-1');
            expect(childCall.call.id).toBe('ask-1');
            expect(main.call.asked).toBe(true);
            expect(childCall.call.asked).toBe(true);
            expect(main.call.status).toBe('completed');
            expect(childCall.call.status).toBe(
              action === 'accept' ? 'completed' : 'failed',
            );

            const answers = [...task.subagent.entries, ...state.entries].filter(
              (entry) => entry.kind === 'elicitation',
            );

            expect(answers).toHaveLength(2);
            expect(
              task.subagent.entries.filter(
                (entry) => entry.kind === 'elicitation',
              ),
            ).toHaveLength(1);
            expect(
              state.entries.filter((entry) => entry.kind === 'elicitation'),
            ).toHaveLength(1);
            expect(task.subagent.entries.indexOf(answers[0]!)).toBeGreaterThan(
              task.subagent.entries.indexOf(childCall),
            );
            expect(
              answers.map((entry) => ({
                owner: entry.wait.subagentId,
                content: entry.content,
              })),
            ).toEqual([
              {
                owner: 'question-task',
                content:
                  action === 'accept'
                    ? { question_0: 'Python', question_1: ['Tests'] }
                    : undefined,
              },
              {
                owner: undefined,
                content: {
                  question_0: 'Deno (TypeScript) (Recommended)',
                  question_1: ['Types'],
                },
              },
            ]);
          }

          expect(transcript.asking).toStrictEqual([]);
        } finally {
          await resumed.close();
        }
      }));
  }
});
