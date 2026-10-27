import { expect, test } from 'bun:test';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import type { Transcript } from '../../../src/session/transcript/types.ts';
import { recordedSelection } from '../../../src/session/team_selection.ts';
import { recordedReceipts } from '../../../src/ui/teams/recorded_receipts.ts';
import { fakeAgentCommand, gatedCommand } from '../../fixtures/fake.ts';
import { ready, send, until, withWindow } from './render.tsx';

test('actual selected receipt revises before its genuine delayed ACP link replaces it once', async () => {
  const server = serveChord();
  let transcript: Transcript | undefined;
  let gatePath = '';
  const receipts = () =>
    transcript === undefined ? [] : recordedReceipts(transcript);
  const receipt = () => {
    const call = receipts()[0];

    return call === undefined ? undefined : recordedSelection(call);
  };

  try {
    await withWindow(
      async (window) => {
        await ready(window);

        const gates = join(window.dir, '.fake-gate');

        await mkdir(gates, { recursive: true });

        gatePath = join(gates, 'start');

        await send(window, 'selectedlate');
        await until(
          'actual planned receipt',
          () => receipt()?.roles[0]?.state === 'planned',
        );
        expect(receipts()).toHaveLength(1);
        await until('owned planned receipt mounted', () =>
          window.mounted('Recorded Team receipt (fixture)'),
        );

        const id = receipt()!.runId;

        await writeFile(join(gates, 'start'), '');
        await until(
          'actual confirmed revision',
          () => receipt()?.roles[0]?.state === 'confirmed',
        );
        expect(receipts()).toHaveLength(1);
        expect(receipt()!.runId).toBe(id);
        await writeFile(join(gates, 'link'), '');
        await until('provider delayed link finished', () =>
          window.mounted('Late ACP link completed.'),
        );
        expect(receipts()).toHaveLength(0);
        await until(
          'owned receipt replaced in render',
          () => !window.mounted('Recorded Team receipt (fixture)'),
        );

        const linked = transcript?.entries.filter(
          (entry) => entry.kind === 'tool' && entry.call.chord?.asked === id,
        );

        expect(linked).toHaveLength(1);
      },
      {
        server,
        teams: {
          fixture:
            '---\ndescription: Delayed linkage fixture\nlead:\n  agent: fake\nmembers:\n  - name: reviewer\n    role: Review only\n    agent: fake\n    instructions: Preserve review scope.\n---\nPreserve exact instructions.\n',
        },
        runtimes: ['fake', 'codex'],
        startupOf: (agent) => ({
          agentCommand:
            agent === 'codex'
              ? gatedCommand(gatePath, fakeAgentCommand())
              : fakeAgentCommand(),
        }),
        onState: (state) => {
          transcript = state.sessions[state.front]?.transcript;
        },
      },
    );
  } finally {
    await server.close();
  }
});
