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

  test('an exact version above it is taken', () => {
    expect(releaseVersion('0.55.0', '0.55.1')).toBe('0.55.1');
    expect(releaseVersion('0.55.0', '2.0.0')).toBe('2.0.0');
  });

  test.each([
    ['the same version', '0.55.0', '0.55.0'],
    ['a version below', '0.55.0', '0.54.9'],
    ['a pre-release', '0.55.0', '0.56.0-rc.1'],
    ['a bump of a pre-release', '0.56.0-rc.1', 'patch'],
    ['an exact version over a pre-release', '0.56.0-rc.1', '0.56.0'],
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
});
