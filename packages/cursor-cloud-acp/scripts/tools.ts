/**
 * cursor-cloud-acp's own tooling, run by `bun dev` through its steps.ts: the
 * build. Bun's tooling, never shipped and outside the package's Node project.
 */
import { rm } from 'node:fs/promises';
import { isAbsolute, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { StepContext } from '../../../scripts/dev/steps.ts';

/** The package's folder. */
export const here = fileURLToPath(new URL('..', import.meta.url));

/**
 * The inputs of a build that are not the package's own source: a
 * dependency bundled in, which `--packages=external` should never allow.
 * `inputs` are the metafile's paths, relative to `cwd`.
 */
export function foreign(
  inputs: readonly string[],
  cwd: string,
  folder = here,
): string[] {
  const source = join(folder, 'src') + sep;

  return inputs.filter((input) => {
    const path = isAbsolute(input) ? input : join(cwd, input);

    return !path.startsWith(source);
  });
}

/**
 * `src/bin.ts` built for Node into `dist/`: JavaScript, as Node 22.13 runs
 * no TypeScript, with every package left an import. Split, so `bin.js`
 * checks Node's version before `main`'s chunk imports a dependency.
 */
export async function build(
  context: Pick<StepContext, 'output'>,
  outdir = join(here, 'dist'),
): Promise<number> {
  await rm(outdir, { recursive: true, force: true });

  const built = await Bun.build({
    entrypoints: [join(here, 'src', 'bin.ts')],
    outdir,
    target: 'node',
    packages: 'external',
    splitting: true,
    naming: { chunk: '[name].[ext]' },
    metafile: true,
  });

  if (!built.success) {
    for (const log of built.logs) {
      context.output(String(log));
    }

    return 1;
  }

  const bundled = foreign(
    Object.keys(built.metafile?.inputs ?? {}),
    process.cwd(),
  );

  if (bundled.length > 0) {
    context.output(
      `build: dist/ bundles files outside src/: ${bundled.map((input) => relative(here, input)).join(', ')}`,
    );

    return 1;
  }

  return 0;
}
