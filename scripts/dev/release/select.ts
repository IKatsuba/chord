/**
 * The release's stages, which of them a run's options leave, and what its
 * positional may be. Apart from the stages themselves and the version logic,
 * so parsing any `bun dev` command loads neither, nor src/.
 */
import { ValidationError } from '@cliffy/command';
import { valid } from 'semver';
import type { Package } from './lib.ts';

/** The bumps the positional takes; `fix` is `patch`'s other name. */
export const BUMPS = ['major', 'minor', 'patch', 'fix'] as const;

export type Bump = (typeof BUMPS)[number];

export function isBump(word: string): word is Bump {
  return (BUMPS as readonly string[]).includes(word);
}

/**
 * Whether `word` can be the positional: a bump, or a version written as
 * semver writes it, so `v1.2.3` or `1.2.3+build` is not taken for another.
 */
export function isVersionArgument(word: string): boolean {
  return isBump(word) || valid(word) === word;
}

export const STAGES = [
  'install',
  'check',
  'natives',
  'compile',
  'sign',
  'selftest',
  'notarise',
  'pack',
  'publish',
] as const;

export type Stage = (typeof STAGES)[number];

/** `bun dev release`'s options, as parsed. */
export interface ReleaseOptions {
  readonly dryRun?: boolean | undefined;
  readonly skip?: readonly Stage[] | undefined;
  readonly only?: readonly Stage[] | undefined;
  readonly from?: Stage | undefined;
  readonly to?: Stage | undefined;
  readonly package?: Package | undefined;
  readonly channel?: string | undefined;
}

/**
 * The stages a run's options leave, in the release's order. What Cliffy's
 * declarations cannot say of the values themselves is refused here, as a
 * ValidationError the parser shows with the help.
 */
export function selectStages(options: ReleaseOptions): Stage[] {
  if (options.dryRun && options.only?.includes('publish')) {
    throw new ValidationError(
      '--dry-run stops before publish, so --only publish has nothing to run.',
    );
  }

  const from = STAGES.indexOf(options.from ?? 'install');
  const to = STAGES.indexOf(options.to ?? 'publish');
  const stages = STAGES.filter(
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

  if (options.package !== undefined && !stages.includes('publish')) {
    throw new ValidationError('--package needs publish among the stages.');
  }

  return stages;
}
