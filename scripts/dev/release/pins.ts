/**
 * chord's own preflight (CHD-622): every agent of this repository chord
 * pins in src/chorded.ts must be on npm at that version before a chord
 * release, as a person's `npx` fetches it from there.
 */
import { CHORDED_AGENTS, type ChordedAgent } from '../../../src/chorded.ts';
import { die, npm, type Release, said } from './lib.ts';

/** The version npm has of `spec` (`name@version`), or undefined. */
export type View = (spec: string) => string | undefined;

/** npm's own answer. */
export function npmView(release: Release): View {
  return (spec) => {
    const viewed = npm(release, ['view', spec, 'version'], {
      stdio: ['ignore', 'pipe', 'ignore'],
    });

    return viewed.status === 0 ? said(viewed.stdout) : undefined;
  };
}

/** Stops on the first pin npm does not have. */
export function pinsOnNpm(
  view: View,
  agents: readonly Pick<ChordedAgent, 'package' | 'version'>[] = CHORDED_AGENTS,
): void {
  for (const { package: name, version } of agents) {
    if (view(`${name}@${version}`) !== version) {
      die(
        `npm has no ${name}@${version}, which src/chorded.ts pins: release ${name} first, or pin a version npm has`,
      );
    }
  }
}
