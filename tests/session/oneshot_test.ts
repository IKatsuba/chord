import { describe, expect, test } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
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
