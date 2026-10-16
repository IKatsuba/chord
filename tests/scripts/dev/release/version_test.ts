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

  test('every requested bump or exact version over a prerelease is refused', () => {
    for (const wanted of [
      'major',
      'minor',
      'patch',
      'fix',
      '1.2.3-rc.1',
      '1.2.2',
      '1.2.3',
      '2.0.0',
    ]) {
      expect(() => releaseVersion('1.2.3-rc.1', wanted)).toThrow(VersionError);
    }
  });
});
