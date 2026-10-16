import { afterEach, beforeEach, expect, test } from 'bun:test';
import { rmSync } from 'node:fs';
import { checkKind } from '../../../../scripts/dev/release/build.ts';
import { ReleaseError } from '../../../../scripts/dev/release/lib.ts';
import { type Scratch, scratch } from './scratch.ts';

// file(1) faked: what it says of each binary is what the test sets.

let at: Scratch;

beforeEach(() => {
  at = scratch();

  at.fake('file', 'echo "$1: $KIND"\n');
});

afterEach(() => {
  rmSync(at.place, { recursive: true, force: true });
});

function kind(said: string) {
  return { ...at.release, env: { ...at.release.env, KIND: said } };
}

test('a binary of the kind its target builds passes', () => {
  expect(() =>
    checkKind(
      kind('Mach-O 64-bit executable arm64'),
      'bun-darwin-arm64',
      'Mach-O 64-bit executable arm64',
    ),
  ).not.toThrow();
});

test('a binary of another kind dies with what file said', () => {
  expect(() =>
    checkKind(
      kind('Mach-O 64-bit executable x86_64'),
      'bun-darwin-arm64',
      'Mach-O 64-bit executable arm64',
    ),
  ).toThrow(
    new ReleaseError(
      'dist/bun-darwin-arm64/chord is dist/bun-darwin-arm64/chord: Mach-O 64-bit executable x86_64',
    ),
  );
});
