import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { text } from 'node:stream/consumers';
import {
  collectClaudeResources,
  RESOURCE_WORKER_FLAG,
  resourceWorkerCommand,
} from '../../src/platform/resource_worker.ts';
import { COLLECTOR_BOUNDS } from '../../src/platform/resource_process.ts';
import { spawnGroup } from '../../src/platform/process.ts';
import { buildOptions } from '../../scripts/dev/compile.ts';
import { until } from '../session/conversation_fake.ts';

let directory: string;
let provider: string;
let chord: string;

beforeAll(async () => {
  directory = await mkdtemp(join(tmpdir(), 'chord-claude-worker-'));
  provider = join(directory, 'fake-claude');
  chord = join(directory, 'chord');

  const fake = await Bun.build({
    entrypoints: [
      new URL('../fixtures/claude_resource_provider.ts', import.meta.url)
        .pathname,
    ],
    target: 'bun',
    compile: { outfile: provider },
  });

  expect(fake.success).toBe(true);

  const built = await Bun.build({
    ...buildOptions(new URL('../../src/main.tsx', import.meta.url).pathname, {
      host: true,
      compiled: true,
    }),
    compile: { outfile: chord },
    metafile: true,
  });

  expect(built.success).toBe(true);

  const metadata = built.metafile!;

  expect(
    Object.keys(metadata.inputs).some(
      (input) =>
        input.includes('claude-agent-sdk') && input.endsWith('sdk.mjs'),
    ),
  ).toBe(true);

  expect(
    Object.keys(metadata.inputs).some((input) =>
      /claude-agent-sdk-(darwin|linux|win32)/.test(input),
    ),
  ).toBe(false);
}, 60_000);

afterAll(async () => {
  await rm(directory, { recursive: true, force: true });
});

function dead(pid: number): boolean {
  try {
    process.kill(pid, 0);

    return false;
  } catch {
    return true;
  }
}

async function noProvider(record: string) {
  if (existsSync(record)) {
    const first = JSON.parse(
      (await readFile(record, 'utf8')).split('\n')[0]!,
    ) as { pid: number };

    await until(() => dead(first.pid));
  }
}

async function privateEntry(
  compiled: boolean,
  args: string[],
  record: string,
  scenario = 'normal',
) {
  const command = compiled ? chord : process.execPath;
  const argv = [
    ...(compiled
      ? []
      : [new URL('../../src/main.tsx', import.meta.url).pathname]),
    RESOURCE_WORKER_FLAG,
    ...args,
  ];
  const group = spawnGroup(command, argv, {
    cwd: directory,
    stdin: 'pipe',
    stdout: 'pipe',
    stderr: 'pipe',
    env: {
      CHORD_FAKE_CLAUDE_RECORD: record,
      CHORD_FAKE_CLAUDE_SCENARIO: scenario,
    },
  });

  try {
    await group.started;

    group.child.stdin!.end();

    const output = text(group.child.stdout!);
    const errors = text(group.child.stderr!);
    const exit = await Promise.race([
      group.exit,
      new Promise<never>((_, reject) => {
        const timer = setTimeout(
          () => reject(new Error('Private worker did not exit.')),
          15_000,
        );

        timer.unref();
      }),
    ]);

    expect(exit.code).toBe(0);
    expect(await errors).toBe('');

    return JSON.parse(await output) as {
      agent: string;
      windows?: { name: string; usedPercent: number | null }[];
      unavailable?: unknown;
    };
  } finally {
    if (group.alive()) {
      group.signal('SIGKILL');

      await until(() => !group.alive());
    }

    await noProvider(record);
  }
}

for (const compiled of [false, true]) {
  test(`${compiled ? 'compiled' : 'source'} private entry reads a fake native SDK without CLI/TTY/stderr leakage or inference input`, async () => {
    const record = join(directory, `normal-${compiled}.jsonl`);
    const result = await privateEntry(compiled, [provider], record);

    expect(result.windows?.[0]).toMatchObject({
      name: 'five_hour',
      usedPercent: 0,
    });
    expect(result.windows?.[1]!.usedPercent).toBe(25.125);

    const events = (await readFile(record, 'utf8'))
      .trim()
      .split('\n')
      .slice(1)
      .map(
        (line) =>
          JSON.parse(line) as {
            type: string;
            subtype: string;
            skipBehaviors?: boolean;
          },
      );

    expect(events.some((event) => event.type === 'user')).toBe(false);
    expect(events.map((event) => event.subtype)).toContain('initialize');
    expect(
      events.find((event) => event.subtype === 'get_usage')?.skipBehaviors,
    ).toBe(true);
  }, 30_000);

  test(`${compiled ? 'compiled' : 'source'} private argument caps refuse before starting a provider`, async () => {
    const record = join(directory, `invalid-${compiled}.jsonl`);

    expect(
      await privateEntry(compiled, [provider, 'extra'], record),
    ).toHaveProperty('unavailable');
    expect(existsSync(record)).toBe(false);
  });

  test(`${compiled ? 'compiled' : 'source'} unavailable limits say so, and null windows are none, never zero`, async () => {
    expect(
      await privateEntry(
        compiled,
        [provider],
        join(directory, `unavailable-${compiled}.jsonl`),
        'unavailable',
      ),
    ).toHaveProperty('unavailable');
    expect(
      await privateEntry(
        compiled,
        [provider],
        join(directory, `null-windows-${compiled}.jsonl`),
        'null-windows',
      ),
    ).toEqual({ agent: 'claude', windows: [] });
  }, 30_000);
}

test('source worker launch names the source entry instead of treating Bun as compiled Chord', () => {
  const command = resourceWorkerCommand(provider);

  expect(command[0]).toBe(process.execPath);
  expect(command[1]).toBe(
    new URL('../../src/main.tsx', import.meta.url).pathname,
  );
  expect(command[2]).toBe(RESOURCE_WORKER_FLAG);
  expect(buildOptions('fixture').define).not.toHaveProperty(
    'CHORD_RESOURCE_COMPILED',
  );
  expect(buildOptions('fixture', { compiled: true }).define).toHaveProperty(
    'CHORD_RESOURCE_COMPILED',
    'true',
  );
});

test('source parent collects normalized SDK facts and drains its whole owned worker group', async () => {
  const result = await collectClaudeResources(provider, {
    cwd: directory,
    signal: new AbortController().signal,
  });

  expect('windows' in result && result.windows[0]!.usedPercent).toBe(0);
});

for (const scenario of [
  'init-hang',
  'getter-hang',
  'stubborn',
  'late',
  'getter-deadline',
]) {
  test(`${scenario} is bounded by the parent and drains the worker plus native SDK child`, async () => {
    const record = join(directory, `${scenario}.jsonl`);
    const priorScenario = process.env.CHORD_FAKE_CLAUDE_SCENARIO;
    const priorRecord = process.env.CHORD_FAKE_CLAUDE_RECORD;

    process.env.CHORD_FAKE_CLAUDE_SCENARIO =
      scenario === 'getter-deadline' ? 'getter-hang' : scenario;
    process.env.CHORD_FAKE_CLAUDE_RECORD = record;

    try {
      const controller = new AbortController();
      let published = false;
      const result = collectClaudeResources(provider, {
        cwd: directory,
        signal: controller.signal,
        bounds: {
          ...COLLECTOR_BOUNDS,
          totalMs: scenario === 'getter-deadline' ? 2500 : 5000,
        },
      }).then((value) => {
        published = true;

        return value;
      });

      result.catch(() => {});

      await until(
        () =>
          existsSync(record) &&
          readFileSync(record, 'utf8').includes(
            scenario.startsWith('getter') || scenario === 'late'
              ? 'get_usage'
              : 'initialize',
          ),
      );

      if (scenario !== 'getter-deadline') {
        controller.abort();
      }

      await expect(result).rejects.toThrow(
        scenario === 'getter-deadline' ? 'deadline' : 'cancelled',
      );
      expect(published).toBe(false);
      await noProvider(record);

      if (scenario === 'late') {
        expect(await readFile(record, 'utf8')).toContain('lateResponse');
      }
    } finally {
      if (priorScenario === undefined) {
        delete process.env.CHORD_FAKE_CLAUDE_SCENARIO;
      } else {
        process.env.CHORD_FAKE_CLAUDE_SCENARIO = priorScenario;
      }

      if (priorRecord === undefined) {
        delete process.env.CHORD_FAKE_CLAUDE_RECORD;
      } else {
        process.env.CHORD_FAKE_CLAUDE_RECORD = priorRecord;
      }
    }
  }, 30_000);
}

describe('tester: private usage worker argument boundaries', () => {
  for (const compiled of [false, true]) {
    test(`${compiled ? 'compiled' : 'source'} missing, empty and oversized paths start no provider`, async () => {
      for (const [index, args] of [[], [''], ['x'.repeat(4097)]].entries()) {
        const record = join(
          directory,
          `tester-invalid-${compiled}-${index}.jsonl`,
        );

        expect(await privateEntry(compiled, args, record)).toEqual({
          agent: 'claude',
          unavailable: 'Invalid isolated collector arguments.',
        });
        expect(existsSync(record)).toBe(false);
      }
    });
  }
});
