/**
 * The release's state (CHD-623, the owner's O4): what one package's release
 * has done, written as it does it, so a stopped release resumes from what it
 * recorded rather than from what npm and git suggest. Kept per package in
 * `.release/<package>/state.json`, gitignored, outside `dist/`, which a
 * build may wipe while npm already has part of a release. This module reads,
 * writes and judges it; it runs no process and asks no git.
 */
import {
  closeSync,
  fsyncSync,
  mkdirSync,
  openSync,
  readFileSync,
  renameSync,
  rmSync,
  writeSync,
} from 'node:fs';
import { join } from 'node:path';
import { z } from '@zod/zod';
import { die } from './lib.ts';

export const FORMAT = 1;

const progress = z.enum(['pending', 'made', 'pushed']);

const SCHEMA = z.object({
  format: z.literal(FORMAT),
  package: z.string(),
  version: z.string(),
  channel: z.string().nullable(),
  /** main, or the channel's branch. */
  branch: z.string(),
  /** HEAD when the release began. */
  base: z.string(),
  versionCommit: z
    .object({ state: progress, sha: z.string().optional() })
    .optional(),
  /** The commit the stages build from; the tag points here. */
  built: z.string(),
  /** Done stages, with the sha256 of what each left for later ones. */
  stages: z.record(
    z.string(),
    z.object({ at: z.string(), outputs: z.record(z.string(), z.string()) }),
  ),
  /** Each npm name of the publish stage, in its order. */
  npm: z.record(z.string(), z.enum(['pending', 'sent', 'answered'])),
  tag: z.object({ state: progress }).optional(),
  /** chord only. */
  draft: z
    .object({
      state: z.enum(['pending', 'made']),
      url: z.string().optional(),
    })
    .optional(),
});

/** One package's release in progress, as `.release/<package>/state.json` holds it. */
export type ReleaseState = z.infer<typeof SCHEMA>;

/** The folder of `name`'s state, from the root. */
export function stateDir(name: string): string {
  return join('.release', name);
}

/** What every refusal a state causes says last (owner, S1). */
export function abandon(name: string): string {
  return `rm -r ${stateDir(name)} abandons it`;
}

/** The state file of `name` under `root`. */
function stateFile(root: string, name: string): string {
  return join(root, stateDir(name), 'state.json');
}

/**
 * `name`'s state under `root`, or none. A state of another format, another
 * package or a broken one is refused, naming the file, and left as it is.
 */
export function readState(
  root: string,
  name: string,
): ReleaseState | undefined {
  const file = stateFile(root, name);
  let text: string;

  try {
    text = readFileSync(file, 'utf8');
  } catch (error) {
    if ((error as { code?: string }).code === 'ENOENT') {
      return undefined;
    }

    throw error;
  }

  let data: unknown;

  try {
    data = JSON.parse(text);
  } catch (error) {
    die(`${file} is not JSON: ${(error as Error).message}; ${abandon(name)}`);
  }

  const format = (data as { format?: unknown } | null)?.format;

  if (format !== FORMAT) {
    die(
      `${file} has format ${JSON.stringify(format)}; this release reads format ${FORMAT}; ${abandon(name)}`,
    );
  }

  const parsed = SCHEMA.safeParse(data);

  if (!parsed.success) {
    const [issue] = parsed.error.issues;

    die(
      `${file} is not a release's state: ${issue?.path.join('.') || 'the file'}: ${issue?.message}; ${abandon(name)}`,
    );
  }

  if (parsed.data.package !== name) {
    die(
      `${file} is ${parsed.data.package}'s state, not ${name}'s; ${abandon(name)}`,
    );
  }

  return parsed.data;
}

/** The file calls `writeState` makes, so a test stops one before the rename. */
export interface StateFs {
  readonly rename: (from: string, to: string) => void;
}

/**
 * Writes `state` whole: to a `.tmp` beside the file, fsynced, then renamed
 * over it, so a kill leaves the old state or the new one, never half.
 */
export function writeState(
  root: string,
  state: ReleaseState,
  fs: StateFs = { rename: renameSync },
): void {
  const file = stateFile(root, state.package);
  const temporary = `${file}.tmp`;

  mkdirSync(join(root, stateDir(state.package)), { recursive: true });

  const fd = openSync(temporary, 'w');

  try {
    writeSync(fd, `${JSON.stringify(SCHEMA.parse(state), null, 2)}\n`);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }

  fs.rename(temporary, file);
}

/** Removes `name`'s state, once its release is done. */
export function clearState(root: string, name: string): void {
  rmSync(join(root, stateDir(name)), { recursive: true, force: true });
}

/** Whether everything of the release is done: npm, the tag and the draft. */
export function finished(state: ReleaseState, githubRelease: boolean): boolean {
  return (
    Object.values(state.npm).every((each) => each === 'answered') &&
    state.tag?.state === 'pushed' &&
    (!githubRelease || state.draft?.state === 'made')
  );
}

/** How a refusal names a state's progress: its version, done stages and npm. */
export function described(state: ReleaseState): string {
  const done = Object.keys(state.stages);
  const npm = Object.values(state.npm);
  const answered = npm.filter((each) => each === 'answered').length;

  return `${state.package} ${state.version} is in progress (done: ${done.length === 0 ? 'nothing' : done.join(', ')}; npm ${answered} of ${npm.length})`;
}

/** A run's selection, as the release judges it against a state. */
export interface Selection {
  /** The package's stage names, in order, publish last. */
  readonly stages: readonly string[];
  /** The stages the options selected, in order. */
  readonly selected: readonly string[];
  /** Whether `--only` or `--from` named them, so a done one runs again. */
  readonly named: boolean;
  readonly dryRun: boolean;
  readonly bump: string | undefined;
  readonly channel: string | undefined;
  readonly githubRelease: boolean;
}

/** What a run with a state does. */
export interface Left {
  /** The done stages cleared before the first runs: rerun, and every done one after. */
  readonly cleared: readonly string[];
  /** The stages to run, publish left out, in order. */
  readonly stages: readonly string[];
  /** What is left of publish, when it is selected. */
  readonly publish?: {
    readonly npm: readonly string[];
    readonly tag: boolean;
    readonly draft: boolean;
  };
}

/**
 * What a run with `state` does under `selection`: the selected stages not
 * done, then, when publish is selected, the npm names not answered, the tag
 * not pushed and the draft not made. Refusals name the state's way out.
 */
export function left(state: ReleaseState, selection: Selection): Left {
  const name = state.package;
  const refuse = (why: string): never => die(`${why}; ${abandon(name)}`);

  if (selection.dryRun) {
    refuse(
      `--dry-run is refused while ${described(state)}: \`bun dev release ${name}\` continues it`,
    );
  }

  if (selection.bump !== undefined && selection.bump !== state.version) {
    refuse(
      `--bump ${selection.bump} is refused while ${described(state)}: \`bun dev release ${name}\` continues it`,
    );
  }

  if (selection.channel !== undefined && selection.channel !== state.channel) {
    refuse(
      `--channel ${selection.channel} is not ${described(state)}'s channel, ${state.channel ?? 'none'}`,
    );
  }

  const publish = selection.selected.includes('publish');
  const built = selection.selected.filter((stage) => stage !== 'publish');
  const done = (stage: string) => stage in state.stages;
  const again = selection.named ? built.filter(done) : [];
  const first = again[0];
  const cleared =
    first === undefined
      ? []
      : selection.stages
          .slice(selection.stages.indexOf(first))
          .filter((stage) => stage !== 'publish' && done(stage));

  if (
    cleared.length > 0 &&
    Object.values(state.npm).some((each) => each !== 'pending')
  ) {
    refuse(
      `${listed(cleared)} cannot run again: npm has ${name} ${state.version}'s bytes from ${described(state)}`,
    );
  }

  const stages = built.filter(
    (stage) => cleared.includes(stage) || !done(stage),
  );

  if (publish) {
    // The stage before publish leaves what it sends (chord's and every
    // package's pack: the tarballs).
    const before = selection.stages[selection.stages.indexOf('publish') - 1];

    if (
      before !== undefined &&
      (!done(before) || cleared.includes(before)) &&
      !stages.includes(before)
    ) {
      refuse(
        `publish needs ${before}'s output; ${before} is not done in ${name} ${state.version}`,
      );
    }
  }

  return {
    cleared,
    stages,
    ...(publish
      ? {
          publish: {
            npm: Object.entries(state.npm)
              .filter(([, each]) => each !== 'answered')
              .map(([npm]) => npm),
            tag: state.tag?.state !== 'pushed',
            draft: selection.githubRelease && state.draft?.state !== 'made',
          },
        }
      : {}),
  };
}

/** `state` with `stages` no longer done. */
export function cleared(
  state: ReleaseState,
  stages: readonly string[],
): ReleaseState {
  return {
    ...state,
    stages: Object.fromEntries(
      Object.entries(state.stages).filter(([stage]) => !stages.includes(stage)),
    ),
  };
}

/** `a`, `a and b`, `a, b and c`. */
function listed(names: readonly string[]): string {
  return names.length < 2
    ? names.join('')
    : `${names.slice(0, -1).join(', ')} and ${names.at(-1)}`;
}
