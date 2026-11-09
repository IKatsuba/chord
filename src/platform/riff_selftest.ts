/**
 * The hidden `--riff-selftest <base url>`: `bun dev selftest` proves a built
 * binary loads libfx on both backends and fff, before riff exists (CHD-603).
 * One libfx turn with one tool against the fake Chat Completions server the
 * self-test serves, once on native and once with native turned off (Wasm),
 * then one fff grep on a temporary tree; it prints what each did as JSON.
 *
 * Part 2 (CHD-604) replaces this with a real riff turn through
 * --riff-agent and removes the flag and this module.
 */
import { FileFinder } from '@ff-labs/fff-bun';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import {
  createFxEngine,
  getBackendInfo,
  type FxNodeBackendOptions,
} from 'libfx/node';
import { libfxBackend } from './libfx.ts';

export const RIFF_SELFTEST_FLAG = '--riff-selftest';

/** The fake server's one model; it exists only for this path. */
export const SELFTEST_MODEL = 'selftest';

/** The line the grep looks for in the tree it makes. */
export const SELFTEST_NEEDLE = 'chord riff selftest needle';

/** What one turn did, as the self-test checks it. */
export interface SelftestTurn {
  readonly backend: string;
  readonly stopReason: string;
  readonly text: string;
  /** How many times `echo` ran, and what it was given. */
  readonly echoed: readonly string[];
}

/** The flag's whole report, one JSON line on stdout. */
export interface SelftestReport {
  readonly turns: readonly SelftestTurn[];
  readonly grep: readonly string[];
}

export async function runRiffSelftest(args: readonly string[]): Promise<void> {
  const [baseUrl] = args;

  if (baseUrl === undefined) {
    throw new Error(`${RIFF_SELFTEST_FLAG} takes the fake server's base URL`);
  }

  const options = await libfxBackend();
  const report: SelftestReport = {
    turns: [
      await turn(baseUrl, { ...options, backend: 'native' }),
      await turn(baseUrl, { ...options, nativeAddon: false }),
    ],
    grep: await grep(),
  };

  process.stdout.write(`${JSON.stringify(report)}\n`);
}

async function turn(
  baseUrl: string,
  backend: FxNodeBackendOptions,
): Promise<SelftestTurn> {
  const info = await getBackendInfo(backend);
  const echoed: string[] = [];
  const engine = await createFxEngine({
    ...backend,
    provider: {
      name: 'selftest',
      baseUrl,
      models: {
        [SELFTEST_MODEL]: { contextWindow: 128_000, supportsToolUse: true },
      },
    },
    model: SELFTEST_MODEL,
    tools: [
      {
        name: 'echo',
        description: 'Says its text back.',
        inputSchema: {
          type: 'object',
          properties: { text: { type: 'string' } },
          required: ['text'],
        },
        idempotent: true,
        execute: (input: unknown) => {
          const { text } = input as { text: string };

          echoed.push(text);

          return `echo: ${text}`;
        },
      },
    ],
  });

  try {
    const running = engine.prompt('Call echo, then say done.');
    let text = '';

    for await (const event of running) {
      if (event.type === 'text_delta') {
        text += event.delta;
      }
    }

    const { stopReason } = await running.result;

    return { backend: info.backend, stopReason, text, echoed };
  } finally {
    await engine.close();
  }
}

async function grep(): Promise<string[]> {
  const tree = await mkdtemp(join(tmpdir(), 'chord-riff-selftest-'));

  try {
    await writeFile(join(tree, 'needle.txt'), `before\n${SELFTEST_NEEDLE}\n`);

    const created = FileFinder.create({ basePath: tree });

    if (!created.ok) {
      throw new Error(`fff: ${created.error}`);
    }

    const finder = created.value;

    try {
      await finder.waitForScan(5000);

      const found = finder.grep(SELFTEST_NEEDLE, { mode: 'plain' });

      if (!found.ok) {
        throw new Error(`fff: ${found.error}`);
      }

      return found.value.items.map(
        (match) =>
          `${match.relativePath}:${match.lineNumber}: ${match.lineContent}`,
      );
    } finally {
      finder.destroy();
    }
  } finally {
    await rm(tree, { recursive: true, force: true });
  }
}
