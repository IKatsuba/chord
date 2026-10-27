import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import process from 'node:process';
import {
  fixtureResourceRead,
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

  test('all capture cases are normalized advisory facts or an explicitly cancelled pending read', async () => {
    const source = { sourceRef: 'fixture', sessionRef: 'session' };

    for (const scenario of ['normal', 'partial', 'long'] as const) {
      expect(
        await fixtureResourceRead(
          'codex',
          source,
          scenario,
          new AbortController().signal,
        ),
      ).toHaveProperty('facts.observation');
    }

    expect(
      await fixtureResourceRead(
        'codex',
        source,
        'unavailable',
        new AbortController().signal,
      ),
    ).toHaveProperty('facts.unavailable');

    const controller = new AbortController();
    const pending = fixtureResourceRead(
      'codex',
      source,
      'pending',
      controller.signal,
    );

    controller.abort(new Error('Fixture cancelled.'));

    await expect(pending).rejects.toThrow('Fixture cancelled.');
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
        const result = spawnSync(
          command[0],
          [
            ...command.slice(1),
            join(directory, command.length === 1 ? 'compiled' : 'source'),
          ],
          {
            env: { ...process.env, PATH: '', CHORD_RESOURCE_FIXTURE: 'true' },
            encoding: 'utf8',
            timeout: 10000,
          },
        );

        expect(result.status, result.stderr).toBe(0);
        expect(result.stderr).toBe('');
        expect(
          JSON.parse(result.stdout).unbound.map(
            (source: { source: string }) => source.source,
          ),
        ).toEqual(['fixture', 'fixture']);
      }
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });
});
