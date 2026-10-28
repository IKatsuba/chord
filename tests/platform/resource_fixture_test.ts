import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import process from 'node:process';
import {
  fixtureLimits,
  resourceFixtureCase,
  resourceSourceMode,
} from '../../src/platform/resource_fixture.ts';

describe('explicit fake resource states', () => {
  test('fixture selection is exact and never triggered by unrelated values', () => {
    expect(resourceSourceMode('true')).toBe('fixture');
    expect(resourceSourceMode(undefined)).toBe('official');
    expect(resourceSourceMode('false')).toBe('official');
    expect(resourceFixtureCase('partial')).toBe('partial');
    expect(resourceFixtureCase('unknown')).toBe('normal');
  });

  test('every capture case is windows, unavailable, or a read that waits until cancelled', async () => {
    for (const scenario of ['normal', 'partial'] as const) {
      expect(
        await fixtureLimits('codex', scenario, new AbortController().signal),
      ).toHaveProperty('windows');
    }

    expect(
      await fixtureLimits('codex', 'unavailable', new AbortController().signal),
    ).toHaveProperty('unavailable');

    const controller = new AbortController();
    const waiting = fixtureLimits('codex', 'timeout', controller.signal);

    controller.abort(new Error('Fixture cancelled.'));

    await expect(waiting).rejects.toThrow('Fixture cancelled.');
  });

  test('source and compiled dispatch use only fixtures for provider labels with an empty PATH', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'chord-resource-fixture-'));
    const probe = new URL(
      '../fixtures/resource_fixture_probe.ts',
      import.meta.url,
    ).pathname;
    const binary = join(directory, 'fixture-probe');

    try {
      const built = await Bun.build({
        entrypoints: [probe],
        target: 'bun',
        compile: { outfile: binary },
      });

      expect(built.success).toBe(true);

      for (const command of [
        [
          process.execPath,
          '--define',
          'process.env.CHORD_RESOURCE_FIXTURE:"true"',
          probe,
        ],
        [binary],
      ] as const) {
        const result = spawnSync(command[0], command.slice(1), {
          env: { ...process.env, PATH: '', CHORD_RESOURCE_FIXTURE: 'true' },
          encoding: 'utf8',
          timeout: 10000,
        });

        expect(result.status, result.stderr).toBe(0);
        expect(result.stderr).toBe('');
        expect(
          JSON.parse(result.stdout).providers.map(
            (provider: {
              agent: string;
              windows: { usedPercent: number }[];
            }) => [provider.agent, provider.windows[0]?.usedPercent],
          ),
        ).toEqual([
          ['claude', 12.345],
          ['codex', 12.345],
        ]);
      }
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });
});
