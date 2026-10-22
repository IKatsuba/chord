import { describe, expect, test } from 'bun:test';
import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { runOneshot } from '../../src/session/oneshot.ts';
import type { ElicitationWait } from '../../src/session/transcript/types.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { said } from '../fixtures/recorder.ts';

describe('CHD-1 tester: oneshot elicitation lifecycle', () => {
  test('a Claude tool-call form waits for its async diagnostic, then declines and completes', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-oneshot-question-'));
    const updates: SessionUpdate[] = [];
    const offered =
      Promise.withResolvers<Extract<ElicitationWait, { mode: 'form' }>>();
    const release = Promise.withResolvers<void>();
    let completed = false;
    const work = runOneshot({
      agent: 'fake',
      cwd: dir,
      prompt: 'askclaude',
      agentCommand: fakeAgentCommand(),
      onUpdate: (update) => {
        updates.push(update);
      },
      onRefused: () => {},
      onDeclined: async (form) => {
        offered.resolve(form);
        await release.promise;
      },
    }).then((result) => {
      completed = true;

      return result;
    });

    try {
      const form = await offered.promise;

      expect(form.questions?.agent).toBe('claude');
      expect(form.questions?.questions.length).toBe(2);
      expect(completed).toBe(false);
      expect(said(updates).join('')).not.toContain('Elicitation answer:');
      release.resolve();

      const result = await work;

      expect(result.result).toMatchObject({
        status: 'completed',
        stopReason: 'end_turn',
      });
      expect(said(updates).join('')).toBe('Elicitation answer: decline');
      expect(
        updates.some((update) => update.sessionUpdate === 'tool_call'),
      ).toBe(true);
      expect(
        updates.some(
          (update) =>
            update.sessionUpdate === 'tool_call_update' &&
            update.status === 'completed',
        ),
      ).toBe(true);
    } finally {
      release.resolve();
      await work;
      await rm(dir, { recursive: true });
    }
  });

  test('without a diagnostic callback a generic form still declines, and a parallel link cancels', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-oneshot-question-'));

    try {
      const results = await Promise.all(
        ['form', 'link'].map(async (prompt) => {
          const updates: SessionUpdate[] = [];
          const result = await runOneshot({
            agent: 'fake',
            cwd: dir,
            prompt,
            agentCommand: fakeAgentCommand(),
            onUpdate: (update) => {
              updates.push(update);
            },
            onRefused: () => {},
          });

          return { result: result.result, text: said(updates).join('') };
        }),
      );

      expect(results).toStrictEqual([
        {
          result: expect.objectContaining({
            status: 'completed',
            stopReason: 'end_turn',
          }),
          text: 'Elicitation answer: decline',
        },
        {
          result: expect.objectContaining({
            status: 'completed',
            stopReason: 'end_turn',
          }),
          text: 'Elicitation answer: cancel',
        },
      ]);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});

test('-p puts no plan to anyone, so cursor and grok hear cancelled, never a yes (CHD-437, CHD-457)', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-oneshot-plan-'));

  try {
    for (const prompt of ['cursorplan', 'grokplan']) {
      const updates: SessionUpdate[] = [];

      await runOneshot({
        agent: 'fake',
        cwd: dir,
        prompt,
        agentCommand: fakeAgentCommand(),
        onUpdate: (update) => {
          updates.push(update);
        },
        onRefused: () => {},
        onDeclined: () => {},
      });
      expect(said(updates).join('')).toBe(
        'Plan answer: {"outcome":"cancelled"}',
      );
    }
  } finally {
    await rm(dir, { recursive: true });
  }
});

test("-p says dimcode's notice once when its permission leaves read-only, and only then (CHD-434)", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-oneshot-notice-'));
  const noticed = async (agent: string, permission: string, prompt: string) => {
    const said: (readonly string[])[] = [];

    await runOneshot({
      agent,
      cwd: dir,
      prompt,
      agentCommand: fakeAgentCommand(
        undefined,
        '--dimcode-permission',
        permission,
      ),
      onUpdate: () => {},
      onRefused: () => {},
      onNotice: (paragraphs) => {
        said.push(paragraphs);
      },
    });

    return said;
  };

  try {
    // At its start already, or moved there in the turn: once either way.
    expect(await noticed('dimcode', 'workspace-write', 'text')).toHaveLength(1);
    expect(await noticed('dimcode', 'read-only', 'fullaccess')).toHaveLength(1);
    expect(await noticed('dimcode', 'read-only', 'text')).toHaveLength(0);
    // Another agent's option of that name is not dimcode's.
    expect(await noticed('fake', 'full-access', 'text')).toHaveLength(0);
    expect((await noticed('dimcode', 'full-access', 'text'))[0]?.[0]).toMatch(
      /^With its permission option at full-access, dimcode may start/,
    );
  } finally {
    await rm(dir, { recursive: true });
  }
});

describe('CHD-434 U1 tester: headless diagnostic completion', () => {
  test('a repeated at-risk option does not duplicate the diagnostic, and completion awaits its asynchronous delivery', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-notice-delivery-'));
    const offered = Promise.withResolvers<void>();
    const release = Promise.withResolvers<void>();
    const notices: (readonly string[])[] = [];
    let complete = false;
    const work = runOneshot({
      agent: 'dimcode',
      cwd: dir,
      prompt: 'fullaccess',
      agentCommand: fakeAgentCommand(
        undefined,
        '--dimcode-permission',
        'full-access',
      ),
      onUpdate: () => {},
      onRefused: () => {},
      onNotice: async (paragraphs) => {
        notices.push(paragraphs);
        offered.resolve();
        await release.promise;
      },
    }).then((result) => {
      complete = true;

      return result;
    });

    try {
      await offered.promise;
      expect(complete).toBe(false);
      release.resolve();
      expect((await work).result.status).toBe('completed');
      expect(notices).toHaveLength(1);
      expect(notices[0]).toHaveLength(2);
      expect(notices[0]![1]).toContain('externalAgents.<type>.enabled');
    } finally {
      release.resolve();
      await work;
      await rm(dir, { recursive: true });
    }
  });

  test('simultaneous headless invocations each warn once and leave no dismissal record', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-notice-parallel-'));
    const notices = [0, 0];

    try {
      const results = await Promise.all(
        ['workspace-write', 'full-access'].map((permission, index) =>
          runOneshot({
            agent: 'dimcode',
            cwd: dir,
            prompt: 'fullaccess',
            agentCommand: fakeAgentCommand(
              undefined,
              '--dimcode-permission',
              permission,
            ),
            onUpdate: () => {},
            onRefused: () => {},
            onNotice: () => {
              notices[index]! += 1;
            },
          }),
        ),
      );

      expect(results.map((result) => result.result.status)).toEqual([
        'completed',
        'completed',
      ]);
      expect(notices).toEqual([1, 1]);
      expect(await readdir(dir)).toEqual([]);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});

describe('CHD-434 U1 tester: agent exit after eligibility', () => {
  test('a crashing fake preserves the once-only warning and yields failure, not a second notice', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-notice-crash-'));
    const notices: (readonly string[])[] = [];

    try {
      const outcome = await runOneshot({
        agent: 'dimcode',
        cwd: dir,
        prompt: 'crash',
        agentCommand: fakeAgentCommand(
          undefined,
          '--dimcode-permission',
          'full-access',
        ),
        onUpdate: () => {},
        onRefused: () => {},
        onNotice: (paragraphs) => {
          notices.push(paragraphs);
        },
      });

      expect(outcome.result.status).toBe('failed');
      expect(notices).toHaveLength(1);
      expect(notices[0]).toHaveLength(2);
      expect(await readdir(dir)).toEqual([]);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});

test("-p reads a result sent only as rawOutput as the call's content, its reply still the agent's words alone (CHD-440)", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-oneshot-raw-'));
  const updates: SessionUpdate[] = [];

  try {
    const outcome = await runOneshot({
      agent: 'fake',
      cwd: dir,
      prompt: 'rawoutputs',
      agentCommand: fakeAgentCommand(),
      onUpdate: (update) => {
        updates.push(update);
      },
      onRefused: () => {},
      onDeclined: () => {},
    });
    const ended = updates.flatMap((update) =>
      update.sessionUpdate === 'tool_call_update' &&
      update.status !== 'in_progress'
        ? [
            {
              status: update.status,
              text: update.content?.map((each) =>
                each.type === 'content' && each.content.type === 'text'
                  ? each.content.text
                  : '',
              ),
            },
          ]
        : [],
    );

    expect(outcome.result).toMatchObject({ status: 'completed' });
    expect(ended).toStrictEqual([
      { status: 'completed', text: ['Thu Oct 22 12:00:00 UTC 2026\n'] },
      { status: 'completed', text: ['ok 1\nok 2'] },
      { status: 'failed', text: ['src/a.ts:3 unused x'] },
      { status: 'completed', text: ['const x = 1;'] },
      { status: 'completed', text: ['built 3 targets'] },
      {
        status: 'completed',
        text: [
          '{\n  "matches": 2,\n  "files": [\n    "a.ts",\n    "b.ts"\n  ]\n}',
        ],
      },
    ]);
    expect(said(updates).join('')).toBe('Ran them.');
  } finally {
    await rm(dir, { recursive: true });
  }
});
