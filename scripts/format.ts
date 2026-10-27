import { spawnSync } from 'node:child_process';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

/** Generated TypeScript laid out by the same native formatter as the tree. */
export function formatModule(source: string): string {
  const child = spawnSync(
    process.execPath,
    ['fmt', '--stdin-filepath', 'src/generated.ts'],
    {
      cwd: fileURLToPath(new URL('../', import.meta.url)),
      input: source,
      encoding: 'utf8',
      maxBuffer: 16 * 1024 * 1024,
    },
  );

  if (child.error !== undefined) {
    throw child.error;
  }

  if (child.status !== 0) {
    throw new Error(`bun fmt failed: ${child.stderr}`);
  }

  return child.stdout;
}
