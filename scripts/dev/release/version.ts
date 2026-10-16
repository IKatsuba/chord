/**
 * The version `bun dev release [version]` releases (CHD-412): package.json's
 * when none is given, else an exact version or a bump of package.json's.
 * Pre-releases are refused: chord publishes none, and a bump of one would
 * not say which release it means.
 */
import { gt, inc, prerelease, valid } from 'semver';

/** The bumps the positional takes; `fix` is `patch`'s other name. */
export const BUMPS = ['major', 'minor', 'patch', 'fix'] as const;

export type Bump = (typeof BUMPS)[number];

/** Why a version cannot be released, said as the release dies with it. */
export class VersionError extends Error {}

function isBump(word: string): word is Bump {
  return (BUMPS as readonly string[]).includes(word);
}

/**
 * Whether `word` can be the positional: a bump, or a version written as
 * semver writes it, so `v1.2.3` or `1.2.3+build` is not taken for another.
 */
export function isVersionArgument(word: string): boolean {
  return isBump(word) || valid(word) === word;
}

/** The version a release of `wanted` makes of `current`, package.json's. */
export function releaseVersion(
  current: string,
  wanted: string | undefined,
): string {
  if (wanted === undefined) {
    return current;
  }

  if (!isVersionArgument(wanted)) {
    throw new VersionError(
      `${wanted} is neither a version nor one of ${BUMPS.join(', ')}`,
    );
  }

  if (prerelease(wanted) !== null) {
    throw new VersionError(`${wanted} is a pre-release; chord publishes none`);
  }

  if (valid(current) === null) {
    throw new VersionError(`package.json's version ${current} is no version`);
  }

  if (prerelease(current) !== null) {
    throw new VersionError(
      `package.json's version ${current} is a pre-release; a release starts from a release`,
    );
  }

  if (isBump(wanted)) {
    // Never null: `current` is a valid version.
    return inc(current, wanted === 'fix' ? 'patch' : wanted) ?? current;
  }

  if (!gt(wanted, current)) {
    throw new VersionError(
      `${wanted} is not above package.json's version ${current}`,
    );
  }

  return wanted;
}
