import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { rm } from 'node:fs/promises';
import { join } from 'node:path';
import { readPast } from '../../../src/session/record.ts';
import { openSession } from '../../../src/session/session.ts';
import {
  readRecords,
  type SessionRecord,
} from '../../../src/session/sessions.ts';
import { reduceTranscript } from '../../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type TranscriptAction,
} from '../../../src/session/transcript/types.ts';
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  CTRL_O,
  ESC,
  leader,
  ready,
  send,
  until,
  withWindow,
} from './render.tsx';

test("each session gets chord's server with a token of its own, good until its agent goes, and its tools read the window", async () => {
  const server = serveChord();
  let token: string | undefined;

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'mcp');
        await window.shows(server.url);

        token = /Bearer ([0-9a-f-]{36})/.exec(window.frame())?.[1];

        expect(
          token !== undefined,
          'no token in the servers given',
        ).toBeTruthy();

        await send(window, 'chordtools');
        await window.shows('list_sessions:');
        await window.shows('"you": true');

        const frame = window.frame();

        expect(frame).toContain('"name": "fake"');
        expect(frame).toContain('"name": "Fake Large with a 1M context');
        expect(frame).toContain('"name": "Fake Small"');
        expect(frame).toContain(`"id": "${window.session()?.id}"`);
        expect(frame).toContain('"model": "fake-large"');
        expect(frame).toContain('"tab": 1');
      },
      { server, runtimes: ['fake'], rows: 80, columns: 120 },
    );

    const refused = await fetch(server.url, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}` },
      body: '{}',
    });

    expect(refused.status).toStrictEqual(401);
    await refused.body?.cancel();
  } finally {
    await server.close();
  }
});

test('an agent that does not take HTTP gets no chord server', async () => {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'chordtools');
        await window.shows('No chord server in this session.');
      },
      { server, agentCommand: fakeAgentCommand(undefined, '--no-http') },
    );
  } finally {
    await server.close();
  }
});

test("a user's server named chord keeps its place, and chord's tools answer beside it", async () => {
  const server = serveChord();
  const theirs = {
    type: 'http' as const,
    name: 'chord',
    url: server.url,
    headers: [{ name: 'Authorization', value: 'Bearer user-server-token' }],
  };

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'mcp');
        await window.shows('user-server-token');
        await window.shows('"name": "chord-2"');
        await send(window, 'chordtools');
        await window.shows('list_sessions:');
        await window.shows('"you": true');
      },
      {
        server,
        runtimes: ['fake'],
        mcpServers: [{ server: theirs, from: '.mcp.json' }],
        rows: 80,
        columns: 120,
      },
    );
  } finally {
    await server.close();
  }
});

test("a task agent works nested in its parent's turn, asks the person in the parent's tab, messages it and reports", async () => {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'task');
        await window.shows('Agent(Fix the tokenizer) · fake · fake-small');
        // Its block stands in place of the call, which never draws.
        expect(!window.frame().includes('mcp__chord__spawn_task')).toBeTruthy();
        await window.shows('Agent(Fix the tokenizer) · fake asks');
        await window.shows('· waiting for permission');
        await window.press('\r');
        await window.shows('← from Fix the tokenizer · fake');
        await window.shows(
          'Received the message from Fix the tokenizer · fake.',
        );
        await window.shows('← from Fix the tokenizer · fake · report');
        await window.shows('Done (5 tool uses');
        await window.shows(
          'Received the message from Fix the tokenizer · fake · report.',
        );
        expect(window.frame()).toContain('deno task test passes.');
      },
      { server, runtimes: ['fake'], rows: 60, columns: 120 },
    );
  } finally {
    await server.close();
  }
});

/** The task blocks a session's past draws: each one's ending and work. */
async function resumedTasks(
  record: SessionRecord,
): Promise<
  { state: string; work: string[]; lost: boolean; queued: boolean[] }[]
> {
  const session = await openSession({
    agent: 'fake',
    cwd: record.cwd,
    agentCommand: fakeAgentCommand(undefined, '--resume-only'),
    resume: {
      sessionId: record.sessionId,
      cwd: record.cwd,
      record: record.path,
    },
  });

  try {
    return session
      .history()
      .filter((action): action is TranscriptAction => action.type !== 'usage')
      .reduce(reduceTranscript, emptyTranscript)
      .entries.flatMap((entry) =>
        entry.kind === 'subagent'
          ? [
              {
                state: entry.subagent.state,
                lost: entry.subagent.task?.workLost === true,
                work: entry.subagent.entries.flatMap((each) =>
                  each.kind === 'tool' ? [each.call.title ?? ''] : [],
                ),
                // Whether each message it sent went queued, as its row says.
                queued: entry.subagent.entries.flatMap((each) =>
                  each.kind === 'tool' &&
                  each.call.chord?.tool === 'send_message'
                    ? [each.call.chord.queued === true]
                    : [],
                ),
              },
            ]
          : [],
      );
  } finally {
    await session.close();
  }
}

test("a resumed parent draws its task's work from the task's own record, and the bare block once that record has gone", async () => {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'task');
        await window.shows('· waiting for permission');
        await window.press('\r');
        await window.shows('Done (5 tool uses');

        const stateDir = join(window.dir, 'state');
        let records: SessionRecord[] = [];

        await until('both records', async () => {
          records = await readRecords(stateDir);

          return records.length === 2;
        });

        const parent = records.find((record) => record.parent === undefined);
        const child = records.find((record) => record.parent !== undefined);

        assert(parent !== undefined && child !== undefined);
        expect(child.parent).toStrictEqual(parent.sessionId);
        // The parent keeps the block's start and end; the work is the task's.
        expect(
          (await readPast(parent.path)).every(
            (entry) =>
              entry.type !== 'update' || entry.subagentId === undefined,
          ),
        ).toBeTruthy();

        const [kept] = await resumedTasks(parent);

        assert(kept !== undefined);
        expect(kept.state).toStrictEqual('completed');
        expect(!kept.lost).toBeTruthy();
        expect(
          kept.work.includes('Edit src/parse/tokenize.ts'),
          kept.work.join(),
        ).toBeTruthy();

        await rm(child.path);

        expect(await resumedTasks(parent)).toStrictEqual([
          { state: 'completed', lost: true, work: [], queued: [] },
        ]);
      },
      { server, runtimes: ['fake'], rows: 60, columns: 120 },
    );
  } finally {
    await server.close();
  }
});

test("a task's message that goes as its parent's next turn after the task has ended marks the task's row queued, live and resumed", async () => {
  const server = serveChord();
  // Its steer is answered only once the parent's turn ends, after the task
  // has reported, and the agent took it as a turn of its own.
  const late = fakeAgentCommand(
    undefined,
    '--steering',
    'codex',
    '--steer-late',
    '--step-ms',
    '5',
  );

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'task');
        await window.shows('· waiting for permission');
        await window.press('1');
        await window.shows('Done (5 tool uses');
        await window.shows('the agent started this on its own');
        await window.shows(
          'Received the message from Fix the tokenizer · fake.',
        );
        await window.press(CTRL_O);
        await window.shows('→ to @main · queued');

        const stateDir = join(window.dir, 'state');
        let parent: SessionRecord | undefined;

        await until('the queued row kept', async () => {
          const records = await readRecords(stateDir);

          parent = records.find((record) => record.parent === undefined);

          return parent !== undefined && records.length === 2
            ? (await resumedTasks(parent)).some((task) =>
                task.queued.includes(true),
              )
            : false;
        });

        assert(parent !== undefined);

        const [kept] = await resumedTasks(parent);

        expect(kept?.queued).toStrictEqual([true]);
      },
      {
        server,
        runtimes: ['fake'],
        agentCommand: late,
        startupOf: () => ({ agentCommand: late }),
        rows: 100,
        columns: 120,
      },
    );
  } finally {
    await server.close();
  }
});

test('a task agent whose turn fails reports as failed, with the error', async () => {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'task');
        await window.shows('Agent(Fix the tokenizer) · fake asks');
        await window.press('2');
        await window.shows('← from Fix the tokenizer · fake · failed');
        await window.shows('was denied, so the tokenizer is not fixed.');
        expect(!window.frame().includes('· report')).toBeTruthy();
      },
      { server, runtimes: ['fake'], rows: 60, columns: 120 },
    );
  } finally {
    await server.close();
  }
});

test('a task started on an effort its runtime offers runs on it, and its block and the answer say so', async () => {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'taskeffort');
        await window.shows('Started on high.');
        expect(window.frame()).toContain(
          'Agent(Tune the parser) · fake · fake-small · high',
        );
        expect(!window.frame().includes('Could not')).toBeTruthy();
      },
      { server, runtimes: ['fake'], rows: 60, columns: 160 },
    );
  } finally {
    await server.close();
  }
});

test("a task started on an effort its runtime refuses runs on the runtime's own, and the answer and the transcript say so", async () => {
  const server = serveChord();
  const refusal =
    'Could not start on max effort, asked by spawn_task: the agent offers ' +
    'low, medium, high';

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'taskmaxeffort');
        await window.shows(`Started on medium. ${refusal}.`);
        expect(window.frame()).toContain(`Tune the parser: ${refusal}`);
        expect(window.frame()).toContain(
          'Agent(Tune the parser) · fake · fake-small · medium',
        );
      },
      { server, runtimes: ['fake'], rows: 60, columns: 160 },
    );
  } finally {
    await server.close();
  }
});

test("chord's own calls draw by what chord served: the lists, and a task refused", async () => {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'chordcalls');
        await window.shows('chord knows no fakx.');

        const frame = window.frame();

        expect(frame).toContain('List agents\n');
        expect(frame).toContain('1 runtime · fake');
        expect(frame).toContain('List agents(fake)');
        expect(frame).toContain('2 models · fake-large, fake-small');
        expect(frame).toContain('List sessions');
        expect(frame).toContain('1 open · 1 fake (you)');
        expect(frame).toContain('Agent(Fix the tokenizer) · fakx · fake-small');
        expect(frame).toContain('No agent named fakx; chord knows fake');
        expect(!frame.includes('mcp__chord__')).toBeTruthy();
      },
      { server, runtimes: ['fake'], rows: 60, columns: 120 },
    );
  } finally {
    await server.close();
  }
});

test("chord's own calls as Codex sends them draw as Claude's do; another server's with the same arguments does not tie", async () => {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'codexchordcalls');
        await window.shows('Listed as Codex.');

        const frame = window.frame();

        // The rows a Claude session draws for the same calls (chordcalls).
        expect(frame).toContain('List agents\n');
        expect(frame).toContain('1 runtime · fake');
        expect(frame).toContain('List sessions');
        expect(frame).toContain('1 open · 1 fake (you)');
        expect(!frame.includes('mcp.chord.')).toBeTruthy();
        // The other server's call is drawn as an MCP call, untied (CHD-419).
        expect(frame).toContain('notes - list_notes (MCP)\n');
        expect(frame).toContain('no notes');
      },
      { server, runtimes: ['fake'], rows: 60, columns: 120 },
    );
  } finally {
    await server.close();
  }
});

test('Esc stops a running task agent, which sends no report, takes the queued prompt back, and its message goes at once', async () => {
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'task');
        await window.shows('Agent(Fix the tokenizer) · fake asks');
        await window.press('\r');
        await window.shows('← from Fix the tokenizer · fake:');
        await send(window, 'text');
        await window.press(ESC);
        await window.shows('Cancelled (');
        // The message is the next turn, with no prompt from the person,
        // whose own is back in the draft and never ran.
        await window.shows(
          'Received the message from Fix the tokenizer · fake.',
        );
        expect(window.frame()).toContain('› text');
        expect(!window.frame().includes('· report')).toBeTruthy();
        expect(
          !window.frame().includes('came in chunks'),
          window.frame(),
        ).toBeTruthy();
      },
      { server, runtimes: ['fake'], rows: 60, columns: 120 },
    );
  } finally {
    await server.close();
  }
});

describe('CHD-377 tester: Codex call session isolation', () => {
  test('two fake sessions with reused call ids keep their own served results', async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await send(window, 'codexchordcalls');
          await window.shows('Listed as Codex.');
          await window.shows('1 open · 1 fake (you)');
          await leader(window, 'c');
          await ready(window);
          await send(window, 'codexchordcalls');
          await window.shows('Listed as Codex.');
          await window.shows('2 open');
          expect(window.frame()).not.toContain('Bash(mcp.chord.');
          await leader(window, '1');
          await window.shows('1 open · 1 fake (you)');
          expect(window.frame()).not.toContain('2 open');
          expect(window.frame().match(/Listed as Codex\./g)).toHaveLength(1);
        },
        { server, runtimes: ['fake'], rows: 40, columns: 80 },
      );
    } finally {
      await server.close();
    }
  });
});
