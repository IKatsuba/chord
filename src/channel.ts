/**
 * The release channel a version is on (CHD-577), worked out from the version
 * alone: the npm tag, the branch and the GitHub pre-release mark all come from
 * here, so a labelled version cannot be published without its tag. It holds no
 * release code, as the running chord asks it which tag to follow.
 */
import { prerelease, valid, validRange } from 'semver';

/** Why a version cannot be released, said as the release dies with it. */
export class VersionError extends Error {}

/** Refuses a name that cannot be a channel, which is an npm tag and a branch. */
export function checkChannel(name: string): void {
  if (!/^[a-z][a-z0-9-]*$/.test(name)) {
    throw new VersionError(
      `${name} is no channel name: a lower-case letter, then lower-case letters, digits and hyphens`,
    );
  }

  if (validRange(name) !== null) {
    throw new VersionError(
      `${name} is no channel name: npm refuses a tag that is a version range`,
    );
  }

  if (name === 'latest') {
    throw new VersionError(
      "latest is no channel name: it would publish over npm's latest",
    );
  }

  if (name === 'main') {
    throw new VersionError(
      'main is no channel name: main is the stable branch',
    );
  }
}

/**
 * The channel of `version`, its first pre-release identifier; null for a
 * stable version and for what is no version at all, which npm refuses to
 * publish under any tag. A pre-release not shaped `<x.y.z>-<channel>.<n>`
 * throws, so a package.json edited by hand cannot publish past the channel
 * rules.
 */
export function channelOf(version: string): string | null {
  const label = prerelease(version);

  if (label === null) {
    return null;
  }

  const [channel, number, ...rest] = label;

  if (
    valid(version) !== version ||
    typeof channel !== 'string' ||
    typeof number !== 'number' ||
    rest.length > 0
  ) {
    throw new VersionError(
      `${version} is not a release of a channel: a pre-release is written <x.y.z>-<channel>.<n>`,
    );
  }

  checkChannel(channel);

  return channel;
}
