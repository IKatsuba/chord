/**
 * The release's stages, and which of them a run's options leave. Apart from
 * the stages themselves, so parsing `bun run dev release` loads none of them.
 */
import { ValidationError } from '@cliffy/command';
import type { Package } from './lib.ts';

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

/** `bun run dev release`'s options, as parsed. */
export interface ReleaseOptions {
  readonly dryRun?: boolean | undefined;
  readonly skip?: readonly Stage[] | undefined;
  readonly only?: readonly Stage[] | undefined;
  readonly from?: Stage | undefined;
  readonly to?: Stage | undefined;
  readonly package?: Package | undefined;
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
