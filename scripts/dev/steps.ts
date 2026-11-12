/**
 * A package's steps (CHD-623): the types its `steps.ts` satisfies, the
 * discovery of the repository's packages, and the one runner of their
 * checks that `bun dev quality` and the release's quality stage share. A
 * steps file imports this module's types only.
 */
import { spawn as spawnChild } from 'node:child_process';
import { once } from 'node:events';
import { existsSync, readFileSync } from 'node:fs';
import { constants } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { z } from '@zod/zod';
import { globby } from 'globby';
import type { Release } from './release/lib.ts';

/** Where a step runs and what it reaches, so a test runs one in a scratch root. */
export interface StepContext {
  /** The repository's root, every argv step's cwd. */
  readonly root: string;
  readonly env: NodeJS.ProcessEnv;
  /** Runs `argv` to its end and answers its status; a signal is 128 + its number. */
  readonly spawn: (
    argv: readonly string[],
    options: { readonly cwd: string; readonly env: NodeJS.ProcessEnv },
  ) => Promise<number>;
  /** Where the runner's own lines go: stderr. */
  readonly output: (line: string) => void;
}

/** One check: an argv run from the repository's root, or a function answering a status. */
export interface Check {
  readonly name: string;
  /** Run by `--static` too; the suite, a build and a smoke are not. */
  readonly static?: boolean;
  readonly run: readonly string[] | ((context: StepContext) => Promise<number>);
}

/** One release stage, in the package's order. */
export interface Stage {
  readonly name: string;
  /** The line `bun dev release --help` lists it with. */
  readonly about: string;
  /** Refused elsewhere, before preflight, when selected (chord's natives, sign, notarise). */
  readonly machine?: { readonly platform: string; readonly arch: string };
  /** Found ready before any stage runs (a signing identity, notary credentials). */
  readonly ready?: (release: Release) => Promise<void>;
  /** Puts the version into what is published: a new version needs it selected. */
  readonly versioned?: boolean;
  /** The paths whose sha256 the release's state records once the stage is done. */
  readonly outputs?: (release: Release, version: string) => readonly string[];
  readonly run: (release: Release, version: string) => Promise<void>;
}

/** The publish stage: data the release's one publish implementation runs. */
export interface Publish {
  readonly name: 'publish';
  /** Full npm names in publish order; the last is the package's main one. */
  readonly npm: readonly string[];
  /** The git tag, `{version}` standing for the version. */
  readonly tag: string;
  /** chord only: recheck the source archives, then a draft GitHub release with them. */
  readonly githubRelease?: true;
}

export interface PackageSteps {
  readonly checks: readonly Check[];
  /** ESLint's argv for this package, before `bun dev lint`'s own arguments. */
  readonly lint: readonly string[];
  /** In order; exactly one `publish`, and it is last. */
  readonly release: readonly (Stage | Publish)[];
  /** A package's own preflight (chord: its agent pins on npm, CHD-622). */
  readonly preflight?: (release: Release, version: string) => Promise<void>;
}

/** A package of the repository, found by `packages`. */
export interface FoundPackage {
  /** Its npm name without the scope: `chord`. */
  readonly name: string;
  /** Its folder from the root, `.` for the root's own. */
  readonly folder: string;
  readonly steps: PackageSteps;
}

/** A package or steps file `bun dev` cannot use; the message names the folder. */
export class StepsError extends Error {
  override name = 'StepsError';
}

const SCOPE = '@chorded/';

export function isPublish(stage: Stage | Publish): stage is Publish {
  return 'npm' in stage;
}

/**
 * The root's package and its workspaces', in that order, each with its
 * `steps.ts` imported; anything `bun dev` could not tell apart or run
 * stops here, naming the folder.
 */
export async function packages(root: string): Promise<FoundPackage[]> {
  const manifest = readManifest(root, '.');
  const patterns = Array.isArray(manifest.workspaces)
    ? manifest.workspaces
    : (manifest.workspaces?.packages ?? []);
  const folders = [
    '.',
    ...(
      await globby(patterns, {
        cwd: root,
        onlyDirectories: true,
        expandDirectories: false,
      })
    ).toSorted(),
  ];
  const found: FoundPackage[] = [];

  for (const folder of folders) {
    const npmName = readManifest(root, folder).name ?? '';

    if (!npmName.startsWith(SCOPE)) {
      throw new StepsError(
        `${folder}: its package.json names "${npmName}", which is not in the ${SCOPE} scope`,
      );
    }

    const name = npmName.slice(SCOPE.length);
    const same = found.find((other) => other.name === name);

    if (same !== undefined) {
      throw new StepsError(
        `${folder}: ${npmName} is also ${same.folder}'s name`,
      );
    }

    found.push({ name, folder, steps: await readSteps(root, folder) });
  }

  return found;
}

interface Manifest {
  readonly name?: string;
  readonly workspaces?: string[] | { readonly packages?: string[] };
}

function readManifest(root: string, folder: string): Manifest {
  return JSON.parse(
    readFileSync(join(root, folder, 'package.json'), 'utf8'),
  ) as Manifest;
}

async function readSteps(root: string, folder: string): Promise<PackageSteps> {
  const file = join(folder, 'steps.ts');
  const path = join(root, file);

  if (!existsSync(path)) {
    throw new StepsError(`${folder}: no steps.ts`);
  }

  let steps: unknown;

  try {
    steps = ((await import(pathToFileURL(path).href)) as { default?: unknown })
      .default;
  } catch (error) {
    throw new StepsError(
      `${file}: ${error instanceof Error ? error.message : String(error)}`,
    );
  }

  const shape = SHAPE.safeParse(steps);

  if (!shape.success) {
    const [issue] = shape.error.issues;

    throw new StepsError(
      `${file}: its default export is not a package's steps: ${issue?.path.join('.') || 'the export'}: ${issue?.message}`,
    );
  }

  const problem = releaseProblem((steps as PackageSteps).release);

  if (problem !== undefined) {
    throw new StepsError(`${file}: ${problem}`);
  }

  return steps as PackageSteps;
}

const runs = z.custom<(...args: never[]) => unknown>(
  (value) => typeof value === 'function',
  'expected a function',
);

/**
 * What a steps file's default export must hold for discovery to read it;
 * the types check the rest where the file is checked.
 */
const SHAPE = z.object({
  checks: z.array(
    z.object({ name: z.string(), run: z.union([z.array(z.string()), runs]) }),
  ),
  lint: z.array(z.string()),
  release: z.array(
    z.union([
      z.object({
        name: z.literal('publish'),
        npm: z.array(z.string()).min(1),
        tag: z.string(),
      }),
      z.object({ name: z.string(), about: z.string(), run: runs }),
    ]),
  ),
});

/** What breaks the release list's rules, if anything. */
function releaseProblem(
  release: readonly (Stage | Publish)[],
): string | undefined {
  const names = release.map((stage) => stage.name);
  const twice = names.find((name, at) => names.indexOf(name) !== at);
  const publishes = release.filter(isPublish).length;

  if (publishes === 0) {
    return 'its release has no publish stage';
  }

  if (publishes > 1) {
    return 'its release has two publish stages';
  }

  if (!isPublish(release.at(-1)!)) {
    return 'publish is not the last stage of its release';
  }

  if (twice !== undefined) {
    return `its release has two stages named "${twice}"`;
  }

  return undefined;
}

/**
 * `found`'s checks in order, only the static ones if `only.static`; the
 * first that fails stops the run, named on the context's output (CHD-467),
 * and its status is the answer.
 */
export async function run(
  found: FoundPackage,
  context: StepContext,
  only: { readonly static?: boolean } = {},
): Promise<number> {
  for (const check of found.steps.checks) {
    if (only.static === true && check.static !== true) {
      continue;
    }

    const status = Array.isArray(check.run)
      ? await context.spawn(check.run as readonly string[], {
          cwd: context.root,
          env: context.env,
        })
      : await (check.run as (context: StepContext) => Promise<number>)(context);

    if (status !== 0) {
      context.output(
        `quality ${found.name}: ${check.name} failed with status ${status}`,
      );

      return status;
    }
  }

  return 0;
}

/** ESLint with `found`'s argv, `args` passed on. */
export function lint(
  found: FoundPackage,
  args: readonly string[],
  context: StepContext,
): Promise<number> {
  return context.spawn([...found.steps.lint, ...args], {
    cwd: context.root,
    env: context.env,
  });
}

/** `argv` on this terminal to its end; a signal is 128 + its number. */
export const spawnStep: StepContext['spawn'] = async (
  [command, ...args],
  { cwd, env },
) => {
  const child = spawnChild(command ?? '', args, { cwd, env, stdio: 'inherit' });
  const [status, signal] = (await once(child, 'exit')) as [
    number | null,
    NodeJS.Signals | null,
  ];

  return signal === null ? (status ?? 1) : 128 + constants.signals[signal];
};

/** The context of a run from `root` on this process's terminal. */
export function stepContext(root: string): StepContext {
  return {
    root,
    env: process.env,
    spawn: spawnStep,
    output: (line) => void process.stderr.write(`${line}\n`),
  };
}
