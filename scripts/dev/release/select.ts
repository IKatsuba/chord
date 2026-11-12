/**
 * Which of a package's release stages a run's options leave, and what
 * `--bump` may be. Apart from the stages themselves and the version logic,
 * so parsing any `bun dev` command loads neither, nor src/.
 */
import { ValidationError } from '@cliffy/command';
import { valid } from 'semver';

/** The bumps `--bump` takes; `fix` is `patch`'s other name. */
export const BUMPS = ['major', 'minor', 'patch', 'fix'] as const;

export type Bump = (typeof BUMPS)[number];

export function isBump(word: string): word is Bump {
  return (BUMPS as readonly string[]).includes(word);
}

/**
 * Whether `word` can be `--bump`'s value: a bump, or a version written as
 * semver writes it, so `v1.2.3` or `1.2.3+build` is not taken for another.
 */
export function isVersionArgument(word: string): boolean {
  return isBump(word) || valid(word) === word;
}

/** `bun dev release`'s options, as parsed. */
export interface ReleaseOptions {
  readonly dryRun?: boolean | undefined;
  readonly skip?: readonly string[] | undefined;
  readonly only?: readonly string[] | undefined;
  readonly from?: string | undefined;
  readonly to?: string | undefined;
  readonly channel?: string | undefined;
}

/** A package's name and its release's stage names, in order. */
export interface Stages {
  readonly name: string;
  readonly stages: readonly string[];
}

/**
 * The stages of `of` a run's options leave, in the package's order. What
 * Cliffy's declarations cannot say of the values themselves is refused here,
 * as a ValidationError the parser shows with the help: a stage the package
 * does not have, as the stage type takes every package's.
 */
export function selectStages(of: Stages, options: ReleaseOptions): string[] {
  const named = [
    ...(options.skip ?? []),
    ...(options.only ?? []),
    ...(options.from === undefined ? [] : [options.from]),
    ...(options.to === undefined ? [] : [options.to]),
  ];
  const missing = named.find((stage) => !of.stages.includes(stage));

  if (missing !== undefined) {
    throw new ValidationError(
      `${of.name} has no stage "${missing}"; its stages are ${of.stages.join(', ')}`,
    );
  }

  if (options.dryRun && options.only?.includes('publish')) {
    throw new ValidationError(
      '--dry-run stops before publish, so --only publish has nothing to run.',
    );
  }

  const from = of.stages.indexOf(options.from ?? of.stages[0]!);
  const to = of.stages.indexOf(options.to ?? of.stages.at(-1)!);
  const stages = of.stages.filter(
    (stage, at) =>
      (options.only === undefined
        ? at >= from && at <= to
        : options.only.includes(stage)) &&
      !(options.skip ?? []).includes(stage) &&
      !(options.dryRun && stage === 'publish'),
  );

  if (stages.length === 0) {
    throw new ValidationError('The options leave no stage to run.');
  }

  return stages;
}
