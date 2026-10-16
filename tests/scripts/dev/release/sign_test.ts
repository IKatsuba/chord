import { afterEach, beforeEach, expect, test } from 'bun:test';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  identity,
  ReleaseError,
  TEAM,
} from '../../../../scripts/dev/release/lib.ts';
import { natives, sign } from '../../../../scripts/dev/release/sign.ts';
import { type Scratch, scratch } from './scratch.ts';

// The keychain and codesign faked: security lists what the test sets,
// codesign logs what it was asked and reads back the entitlements the test
// sets, and plutil passes what it reads through unchanged.

const HASH = 'A'.repeat(40);
const ONE = `  1) ${HASH} "Developer ID Application: Chorded (${TEAM})"\n     1 valid identities found`;
const BINARY = 'dist/bun-darwin-arm64/chord';
const ENTITLEMENTS = '<plist>the one entitlement</plist>';

let at: Scratch;

beforeEach(() => {
  at = scratch();

  mkdirSync(join(at.root, 'scripts', 'macos'), { recursive: true });
  writeFileSync(
    join(at.root, 'scripts', 'macos', 'chord.entitlements'),
    ENTITLEMENTS,
  );
  mkdirSync(join(at.root, 'dist', 'bun-darwin-arm64'), { recursive: true });
  writeFileSync(join(at.root, BINARY), 'binary');
  at.fake('security', 'echo "$IDENTITIES"\n');
  at.fake(
    'codesign',
    `echo "$*" >>"$STATE/codesign.log"
case "$1" in
-d) echo "$SIGNED" ;;
--verify) [ -z "$UNVERIFIED" ] ;;
esac
`,
  );
  at.fake('plutil', 'cat "$5"\n');
});

afterEach(() => {
  rmSync(at.place, { recursive: true, force: true });
});

function keychain(env: Record<string, string> = {}) {
  return {
    ...at.release,
    env: {
      ...at.release.env,
      STATE: at.place,
      IDENTITIES: ONE,
      SIGNED: ENTITLEMENTS,
      UNVERIFIED: '',
      ...env,
    },
  };
}

function codesigned(): string[] {
  return readFileSync(join(at.place, 'codesign.log'), 'utf8')
    .split('\n')
    .filter(Boolean);
}

test("the team's one identity is found by its hash", () => {
  expect(identity(keychain())).toBe(HASH);
});

test('no identity of the team, or two, dies with what security said', () => {
  const other = `  1) ${'B'.repeat(40)} "Developer ID Application: Someone (OTHERTEAM1)"`;

  expect(() => identity(keychain({ IDENTITIES: other }))).toThrow(
    new ReleaseError(
      `expected one Developer ID Application identity of team ${TEAM}, found 0; security find-identity said:\n${other}`,
    ),
  );
  expect(() => identity(keychain({ IDENTITIES: `${ONE}\n${ONE}` }))).toThrow(
    /found 2; security find-identity said/,
  );
});

test('a binary is signed with the runtime and the entitlement, then checked', () => {
  sign(keychain(), [BINARY]);

  expect(codesigned()).toStrictEqual([
    `--force --sign ${HASH} --options runtime --timestamp --entitlements ${join(at.root, 'scripts', 'macos', 'chord.entitlements')} --identifier dev.katsuba.chord ${BINARY}`,
    `--verify --strict --verbose=2 ${BINARY}`,
    `-d --entitlements - --xml ${BINARY}`,
  ]);
  expect(at.out).toStrictEqual([`signed ${BINARY}: ${ENTITLEMENTS}`]);
});

test('entitlements read back other than the file die with both', () => {
  expect(() => sign(keychain({ SIGNED: '<plist/>' }), [BINARY])).toThrow(
    new ReleaseError(
      `entitlements of ${BINARY} differ from scripts/macos/chord.entitlements: got <plist/>, want ${ENTITLEMENTS}`,
    ),
  );
});

test('a binary that does not verify dies', () => {
  expect(() => sign(keychain({ UNVERIFIED: 'yes' }), [BINARY])).toThrow(
    new ReleaseError(`${BINARY} does not verify`),
  );
});

test('a binary that is not there dies', () => {
  expect(() => sign(keychain(), ['dist/nowhere/chord'])).toThrow(
    new ReleaseError('no binary at dist/nowhere/chord'),
  );
});

test("natives signs every macOS library under node_modules and nothing else's", () => {
  const darwin = join(at.root, 'node_modules', '@opentui', 'core-darwin-arm64');
  const linux = join(at.root, 'node_modules', '@opentui', 'core-linux-x64');

  mkdirSync(darwin, { recursive: true });
  mkdirSync(linux, { recursive: true });
  writeFileSync(join(darwin, 'libopentui.dylib'), 'lib');
  writeFileSync(join(darwin, 'README.md'), 'not a library');
  writeFileSync(join(linux, 'libopentui.so'), 'lib');

  natives(keychain());

  const library = 'node_modules/@opentui/core-darwin-arm64/libopentui.dylib';

  expect(at.out).toStrictEqual([`signed ${library}`]);
  expect(codesigned()).toStrictEqual([
    `--force --sign ${HASH} --timestamp ${join(at.root, library)}.signing`,
    `--verify --strict ${join(at.root, library)}.signing`,
  ]);
  expect(readFileSync(join(at.root, library), 'utf8')).toBe('lib');
});

test('natives with no macOS library to sign dies', () => {
  mkdirSync(join(at.root, 'node_modules'));

  expect(() => natives(keychain())).toThrow(
    new ReleaseError(
      "no macOS native library found under node_modules; was bun install --os='*' --cpu='*' run?",
    ),
  );
});
