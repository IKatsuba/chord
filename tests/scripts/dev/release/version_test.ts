import { describe, expect, test } from 'bun:test';
import {
  isVersionArgument,
  releaseVersion,
  VersionError,
} from '../../../../scripts/dev/release/version.ts';

describe('isVersionArgument', () => {
  test.each([
    'major',
    'minor',
    'patch',
    'fix',
    '1.2.3',
    '0.56.0',
    '1.0.0-rc.1',
  ])('takes %s', (word) => {
    expect(isVersionArgument(word)).toBeTrue();
  });

  test.each(['v1.2.3', '=1.2.3', '1.2', '1.2.3+build', 'next', 'Patch', ''])(
    'refuses %p',
    (word) => {
      expect(isVersionArgument(word)).toBeFalse();
    },
  );
});

describe('releaseVersion', () => {
  test("with none given is package.json's", () => {
    expect(releaseVersion('0.55.0', undefined)).toBe('0.55.0');
  });

  test.each([
    ['major', '1.0.0'],
    ['minor', '0.56.0'],
    ['patch', '0.55.1'],
    ['fix', '0.55.1'],
  ])('%s bumps it', (bump, next) => {
    expect(releaseVersion('0.55.0', bump)).toBe(next);
  });

  test("package.json's own version is package.json's", () => {
    expect(releaseVersion('0.55.0', '0.55.0')).toBe('0.55.0');
  });

  test('an exact version above it is taken', () => {
    expect(releaseVersion('0.55.0', '0.55.1')).toBe('0.55.1');
    expect(releaseVersion('0.55.0', '2.0.0')).toBe('2.0.0');
  });

  test.each([
    ["a pre-release package.json's own", '0.56.0-rc.1', '0.56.0-rc.1'],
    ['a version below', '0.55.0', '0.54.9'],
    ['a pre-release', '0.55.0', '0.56.0-rc.1'],
    ['a bump of a pre-release', '0.56.0-rc.1', 'patch'],
    ['a version below a pre-release', '0.56.0-rc.1', '0.55.9'],
    ['a word that is neither', '0.55.0', 'next'],
    ['a version not written as semver writes it', '0.55.0', 'v0.56.0'],
    ["package.json's version that is none", 'latest', 'patch'],
  ])('refuses %s', (_name, current, wanted) => {
    expect(() => releaseVersion(current, wanted)).toThrow(VersionError);
  });

  test('says why', () => {
    expect(() => releaseVersion('0.55.0', '0.54.0')).toThrow(
      "0.54.0 is not above package.json's version 0.55.0",
    );
  });

  test("with none given is package.json's, whatever it holds", () => {
    expect(releaseVersion('1.0.0-next.3', undefined)).toBe('1.0.0-next.3');
    expect(releaseVersion('latest', undefined)).toBe('latest');
  });

  test('an exact version over a pre-release is taken', () => {
    expect(releaseVersion('1.0.0-next.5', '1.0.0')).toBe('1.0.0');
    expect(releaseVersion('1.0.0-next.5', '1.0.1')).toBe('1.0.1');
  });

  test.each(['major', 'minor', 'patch', 'fix'])(
    '%s over a pre-release says to name the version',
    (bump) => {
      expect(() => releaseVersion('1.0.0-next.5', bump)).toThrow(
        'name the version',
      );
    },
  );

  test.each([
    ['1.0.0-next.0', undefined],
    ['1.0.0-next.0', 'next'],
    ['1.0.0-beta.0', 'next'],
    ['0.68.0-rc.1', 'beta'],
  ])('labelled %s on channel %s is refused', (wanted, channel) => {
    expect(() => releaseVersion('0.67.0', wanted, channel)).toThrow(
      `${wanted} has a pre-release label; --channel is the only way to name one`,
    );
  });
});

describe('releaseVersion on a channel', () => {
  const stable = () => '0.67.0';

  test.each([
    ['major', '1.0.0-next.0'],
    ['minor', '0.68.0-next.0'],
    ['patch', '0.67.1-next.0'],
    ['fix', '0.67.1-next.0'],
  ])('%s from stable starts at 0', (bump, version) => {
    expect(releaseVersion('0.67.0', bump, 'next', stable)).toBe(version);
  });

  test('the same bump again goes up by one, from npm and not package.json', () => {
    expect(releaseVersion('1.0.0-next.0', 'major', 'next', stable)).toBe(
      '1.0.0-next.1',
    );
    expect(releaseVersion('1.0.0-next.9', 'major', 'next', stable)).toBe(
      '1.0.0-next.10',
    );
  });

  test('an exact version gives the same two numbers', () => {
    expect(releaseVersion('0.67.0', '1.0.0', 'next', stable)).toBe(
      '1.0.0-next.0',
    );
    expect(releaseVersion('1.0.0-next.0', '1.0.0', 'next', stable)).toBe(
      '1.0.0-next.1',
    );
  });

  test('any channel works the same way', () => {
    expect(releaseVersion('0.67.0', 'major', 'beta', stable)).toBe(
      '1.0.0-beta.0',
    );
    expect(releaseVersion('1.0.0-beta.0', '1.0.0', 'beta', stable)).toBe(
      '1.0.0-beta.1',
    );
  });

  test('a new base starts at 0', () => {
    expect(releaseVersion('1.0.0-next.4', '1.1.0', 'next', stable)).toBe(
      '1.1.0-next.0',
    );
  });

  test("another channel's pre-release of the base starts at 0 when above it", () => {
    expect(releaseVersion('1.0.0-beta.4', '1.0.0', 'next', stable)).toBe(
      '1.0.0-next.0',
    );
  });

  test.each([
    ['1.0.0-next.4', '1.0.0', 'beta', 'it sorts below'],
    ['1.0.0', '1.0.0', 'next', 'a release is above its pre-release'],
    ['1.0.0-next.4', '0.9.0', 'next', 'a lower base'],
    ['1.0.0-next.4', 'minor', 'next', 'a bump of npm below it'],
  ])('%s to %s on %s is refused: %s', (current, wanted, channel) => {
    expect(() => releaseVersion(current, wanted, channel, stable)).toThrow(
      'is not above',
    );
  });

  test('stable is asked only for a bump', () => {
    const never = () => {
      throw new Error('npm was asked');
    };

    expect(releaseVersion('0.67.0', '1.0.0', 'next', never)).toBe(
      '1.0.0-next.0',
    );
    expect(releaseVersion('1.0.0-next.0', undefined, 'next', never)).toBe(
      '1.0.0-next.0',
    );
    expect(releaseVersion('0.67.0', 'minor', undefined, never)).toBe('0.68.0');
    expect(() => releaseVersion('0.67.0', 'major', 'next', never)).toThrow(
      'npm was asked',
    );
  });

  test.each(['latest', '1.0.0-next.0', ''])(
    "refuses npm's latest %p, which is no stable version to bump",
    (latest) => {
      expect(() =>
        releaseVersion('0.67.0', 'major', 'next', () => latest),
      ).toThrow(VersionError);
    },
  );

  test('with no version finishes that channel only', () => {
    expect(releaseVersion('1.0.0-next.3', undefined, 'next', stable)).toBe(
      '1.0.0-next.3',
    );

    for (const current of ['1.0.0-beta.3', '0.67.0']) {
      expect(() => releaseVersion(current, undefined, 'next', stable)).toThrow(
        `package.json's version ${current} is not on channel next`,
      );
    }
  });

  test.each(['latest', 'main', 'x', 'v1', 'Next', ''])(
    'refuses channel %p, with or without a version',
    (channel) => {
      for (const wanted of [undefined, '1.0.0', 'major']) {
        expect(() => releaseVersion('0.67.0', wanted, channel, stable)).toThrow(
          VersionError,
        );
      }
    },
  );

  test("refuses package.json's version that is none", () => {
    expect(() => releaseVersion('latest', '1.0.0', 'next', stable)).toThrow(
      "package.json's version latest is no version",
    );
  });
});

describe('tester: CHD-412 version boundaries', () => {
  test('major and minor reset subordinate components, and fix equals patch', () => {
    expect(releaseVersion('2.9.8', 'major')).toBe('3.0.0');
    expect(releaseVersion('2.9.8', 'minor')).toBe('2.10.0');
    expect(releaseVersion('2.9.8', 'fix')).toBe(
      releaseVersion('2.9.8', 'patch'),
    );
    expect(releaseVersion('0.0.0', 'fix')).toBe('0.0.1');
  });

  test('exact versions compare numerically across multi-digit components', () => {
    expect(releaseVersion('1.9.9', '1.10.0')).toBe('1.10.0');
    expect(releaseVersion('1.10.0', '1.10.0')).toBe('1.10.0');
    expect(() => releaseVersion('1.10.0', '1.9.99')).toThrow(VersionError);
  });

  test('noncanonical spellings are refused before version resolution', () => {
    for (const wanted of [
      ' 1.2.3',
      '1.2.3 ',
      '01.2.3',
      '1.02.3',
      '1.2.03',
      '=1.2.3',
      '1.2.3+build.1',
      '^1.2.3',
      '*',
      'FIX',
    ]) {
      expect(isVersionArgument(wanted)).toBeFalse();
      expect(() => releaseVersion('1.0.0', wanted)).toThrow(VersionError);
    }
  });

  test('a prerelease accepts unlabelled higher versions and refuses bumps', () => {
    for (const wanted of [
      'major',
      'minor',
      'patch',
      'fix',
      '1.2.3-rc.1',
      '1.2.2',
    ]) {
      expect(() => releaseVersion('1.2.3-rc.1', wanted)).toThrow(VersionError);
    }

    for (const wanted of ['1.2.3', '2.0.0']) {
      expect(releaseVersion('1.2.3-rc.1', wanted)).toBe(wanted);
    }
  });
});

describe('tester: CHD-577 version boundaries', () => {
  test.each(['next', 'beta'])(
    '%s increments minor, patch and fix from npm stable across counter digits',
    (channel) => {
      for (const [bump, base] of [
        ['minor', '2.10.0'],
        ['patch', '2.9.9'],
        ['fix', '2.9.9'],
      ]) {
        expect(releaseVersion('2.9.8', bump, channel, () => '2.9.8')).toBe(
          `${base}-${channel}.0`,
        );
        expect(
          releaseVersion(`${base}-${channel}.9`, bump, channel, () => '2.9.8'),
        ).toBe(`${base}-${channel}.10`);
      }
    },
  );

  test('a newer npm stable selects a new base and restarts the counter', () => {
    expect(
      releaseVersion('1.0.0-next.12', 'major', 'next', () => '1.0.0'),
    ).toBe('2.0.0-next.0');
  });

  test('explicit bases and resume do not depend on registry availability', () => {
    const unavailable = () => {
      throw new Error('registry unavailable');
    };

    expect(releaseVersion('1.0.0-beta.9', '1.0.0', 'beta', unavailable)).toBe(
      '1.0.0-beta.10',
    );
    expect(releaseVersion('1.0.0-beta.9', undefined, 'beta', unavailable)).toBe(
      '1.0.0-beta.9',
    );
    expect(() =>
      releaseVersion('1.0.0-beta.9', 'major', 'beta', unavailable),
    ).toThrow('registry unavailable');
  });

  test('a malformed current label cannot become a channel release', () => {
    for (const current of ['1.0.0-next', '1.0.0-next.one', '1.0.0-latest.0']) {
      expect(() => releaseVersion(current, '2.0.0', 'next')).toThrow(
        VersionError,
      );
    }
  });
});
