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
