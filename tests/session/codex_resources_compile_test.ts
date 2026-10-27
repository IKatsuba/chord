import { expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  chmod,
  mkdtemp,
  readFile,
  realpath,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, delimiter } from 'node:path';
import process from 'node:process';

test('compiled public collector uses a fake native or npm launcher unchanged and drains descendants', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'chord-compiled-resource-'));
  const provider = join(directory, 'fake-provider');
  const collector = join(directory, 'fake-collector');
  const launcher = join(directory, 'codex');

  try {
    for (const [name, outfile] of [
      ['resource_provider.ts', provider],
      ['resource_collector.ts', collector],
    ] as const) {
      const built = await Bun.build({
        entrypoints: [new URL(`../fixtures/${name}`, import.meta.url).pathname],
        target: 'bun',
        compile: { outfile },
        define: { RESOURCE_FIXTURE_COMPILED: 'true' },
      });

      expect(built.success).toBe(true);
    }

    await writeFile(
      launcher,
      await readFile(
        new URL('../fixtures/resource_launcher.mjs', import.meta.url),
      ),
    );
    await chmod(launcher, 0o755);

    const env = {
      ...process.env,
      CHORD_FAKE_RESOURCE_NATIVE: provider,
      PATH: `${directory}${delimiter}${process.env.PATH ?? ''}`,
    };
    const version = spawnSync(launcher, ['--version'], {
      env,
      encoding: 'utf8',
      timeout: 10_000,
    });

    expect(version.status).toBe(0);
    expect(version.stdout.trim()).toBe('codex-cli 0.163.0');

    for (const [command, scenario] of [
      [provider, 'normal'],
      [launcher, 'normal'],
      [launcher, 'stubborn'],
      [launcher, 'abort'],
    ]) {
      const record = join(directory, `events-${scenario}.jsonl`);
      const run = spawnSync(collector, [command!, scenario!], {
        env: {
          ...env,
          CHORD_FAKE_RESOURCE_SCENARIO:
            scenario === 'abort' ? 'timeout' : scenario!,
          CHORD_FAKE_RESOURCE_RECORD: record,
        },
        encoding: 'utf8',
        timeout: 15_000,
      });

      expect(run.error).toBeUndefined();
      expect(run.status).toBe(scenario === 'normal' ? 0 : 1);
      expect(run.stderr).toBe('');

      const events = (await readFile(record, 'utf8'))
        .trim()
        .split('\n')
        .map(
          (line) => JSON.parse(line) as { pid?: number; descendant?: number },
        );

      for (const event of events) {
        const pid = event.pid ?? event.descendant;

        if (pid !== undefined) {
          expect(() => process.kill(pid, 0)).toThrow();
        }
      }
    }

    if (process.platform === 'darwin' && process.arch === 'arm64') {
      const resolved = spawnSync(collector, [launcher, 'resolve'], {
        env,
        encoding: 'utf8',
        timeout: 10_000,
      });

      expect(resolved.status).toBe(0);
      expect(JSON.parse(resolved.stdout)).toEqual({
        path: await realpath(launcher),
        version: '0.163.0',
      });
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}, 60_000);
