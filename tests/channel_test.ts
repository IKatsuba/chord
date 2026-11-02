import { describe, expect, test } from 'bun:test';
import { channelOf, checkChannel, VersionError } from '../src/channel.ts';

describe('channelOf', () => {
  test.each(['0.67.0', '1.0.0', '1.0.0+build'])('%s is stable', (version) => {
    expect(channelOf(version)).toBeNull();
  });

  test.each(['latest', '', '1.0', '1.0.0-next.01', '1.0.0-next.', '1.0.0-'])(
    '%p is no version, and is refused rather than taken for stable',
    (version) => {
      expect(() => channelOf(version)).toThrow(`${version} is no version`);
      expect(() => channelOf(version)).toThrow(VersionError);
    },
  );

  test.each([
    ['1.0.0-next.0', 'next'],
    ['1.0.0-next.12', 'next'],
    ['2.3.4-beta.0', 'beta'],
    ['1.0.0-release-candidate.1', 'release-candidate'],
  ])('%s is on %s', (version, channel) => {
    expect(channelOf(version)).toBe(channel);
  });

  test.each([
    ['no number', '1.0.0-next'],
    ['a word for a number', '1.0.0-next.one'],
    ['too many identifiers', '1.0.0-next.0.1'],
    ['a number for a label', '1.0.0-1.0'],
    ['build metadata', '1.0.0-next.0+build'],
    ['a leading v', 'v1.0.0-next.0'],
    ['the label latest', '1.0.0-latest.0'],
    ['the label main', '1.0.0-main.0'],
    ['a label npm takes for a range', '1.0.0-x.0'],
    ['a label with capitals', '1.0.0-Next.0'],
  ])('refuses %s', (_name, version) => {
    expect(() => channelOf(version)).toThrow(VersionError);
  });

  test('says how a pre-release is written', () => {
    expect(() => channelOf('1.0.0-next')).toThrow(
      '1.0.0-next is not a release of a channel: a pre-release is written <x.y.z>-<channel>.<n>',
    );
  });
});

describe('checkChannel', () => {
  test.each(['next', 'beta', 'rc', 'release-candidate', 'rc2'])(
    'takes %s',
    (name) => {
      expect(() => checkChannel(name)).not.toThrow();
    },
  );

  test.each([
    ['', 'lower-case letter'],
    ['Next', 'lower-case letter'],
    ['1next', 'lower-case letter'],
    ['next.1', 'lower-case letter'],
    ['-next', 'lower-case letter'],
    ['next/1', 'lower-case letter'],
    ['x', 'version range'],
    ['v1', 'version range'],
    ['latest', "npm's latest"],
    ['main', 'stable branch'],
  ])('refuses %p', (name, why) => {
    expect(() => checkChannel(name)).toThrow(VersionError);
    expect(() => checkChannel(name)).toThrow(why);
  });
});
