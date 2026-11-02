/**
 * The version `bun dev release [version]` releases (CHD-412, CHD-577):
 * package.json's when none is given or the one given is it, else an exact
 * version above it or a bump of it. On a channel, a pre-release of that
 * version numbered from package.json's. A bump there counts from npm's latest
 * stable, as package.json holds a pre-release. A version with a label is never
 * given: `--channel` is the only way to name one, so the label and the channel
 * cannot disagree.
 */
import { gt, inc, prerelease, valid } from 'semver';
import { channelOf, checkChannel, VersionError } from '../../../src/channel.ts';
import { BUMPS, type Bump, isBump, isVersionArgument } from './select.ts';

export { isVersionArgument, VersionError };

/**
 * The version a release of `wanted` makes of `current`, package.json's, on
 * `channel` if any. `stable` answers npm's latest stable, and is asked only
 * for a bump on a channel, the one case that needs the registry.
 */
export function releaseVersion(
  current: string,
  wanted: string | undefined,
  channel?: string,
  stable: () => string = () => {
    throw new VersionError("a bump on a channel needs npm's latest stable");
  },
): string {
  if (channel !== undefined) {
    checkChannel(channel);
  }

  if (wanted === undefined) {
    if (channel !== undefined && channelOf(current) !== channel) {
      throw new VersionError(
        `package.json's version ${current} is not on channel ${channel}; name a version or a bump`,
      );
    }

    return current;
  }

  if (!isVersionArgument(wanted)) {
    throw new VersionError(
      `${wanted} is neither a version nor one of ${BUMPS.join(', ')}`,
    );
  }

  if (prerelease(wanted) !== null) {
    throw new VersionError(
      `${wanted} has a pre-release label; --channel is the only way to name one`,
    );
  }

  if (valid(current) === null) {
    throw new VersionError(`package.json's version ${current} is no version`);
  }

  if (channel !== undefined) {
    return channelVersion(current, wanted, channel, stable);
  }

  if (isBump(wanted)) {
    if (prerelease(current) !== null) {
      throw new VersionError(
        `package.json's version ${current} is a pre-release, so a bump would not say which release it means; name the version`,
      );
    }

    // Never null: `current` is a valid version.
    return inc(current, bumped(wanted)) ?? current;
  }

  // package.json's own, so a rerun after a failed publish can name it.
  if (wanted === current) {
    return current;
  }

  if (!gt(wanted, current)) {
    throw new VersionError(
      `${wanted} is not above package.json's version ${current}`,
    );
  }

  return wanted;
}

/** The pre-release of `wanted` on `channel`, the one after package.json's. */
function channelVersion(
  current: string,
  wanted: string,
  channel: string,
  stable: () => string,
): string {
  const base = isBump(wanted) ? bumpStable(stable(), wanted) : wanted;

  if (channelOf(current) === channel && current.startsWith(`${base}-`)) {
    // Never null: `current` is a valid version, shaped as channelOf requires.
    return inc(current, 'prerelease', channel) ?? current;
  }

  const first = `${base}-${channel}.0`;

  if (!gt(first, current)) {
    throw new VersionError(
      `${first} is not above package.json's version ${current}`,
    );
  }

  return first;
}

function bumpStable(stable: string, bump: Bump): string {
  if (valid(stable) === null || prerelease(stable) !== null) {
    throw new VersionError(`npm's latest ${stable} is no stable version`);
  }

  // Never null: `stable` is a valid version.
  return inc(stable, bumped(bump)) ?? stable;
}

function bumped(bump: Bump): 'major' | 'minor' | 'patch' {
  return bump === 'fix' ? 'patch' : bump;
}
