import { expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildOptions } from '../../../scripts/dev/compile.ts';

const FIXTURE = fileURLToPath(
  new URL('../../fixtures/boundary/main.tsx', import.meta.url),
);

test("built as the binary is, OpenTUI's ErrorBoundary paints the error rather than throwing jsxDEV (CHD-468)", async () => {
  const out = await mkdtemp(join(tmpdir(), 'chord-boundary-'));

  try {
    const built = await Bun.build({ ...buildOptions(FIXTURE), outdir: out });

    expect(built.success).toBe(true);

    // From its own directory, where the bundle looks for OpenTUI's library.
    const run = spawnSync(process.execPath, [join(out, 'main.js')], {
      cwd: out,
      encoding: 'utf8',
    });

    expect(run.stderr).not.toContain('jsxDEV');
    expect(run.stdout).toContain('Error: the boundary caught this');
    expect(run.status).toBe(0);
  } finally {
    await rm(out, { recursive: true });
  }
}, 60_000);
