/**
 * Signing with the team's Developer ID: the macOS native libraries chord
 * embeds, and the built chords themselves.
 */
import { copyFileSync, renameSync, statSync, utimesSync } from 'node:fs';
import { join } from 'node:path';
import { die, identity, type Release, run, said } from './lib.ts';

/**
 * Signs every macOS native library in node_modules that `bun build
 * --compile` may embed: OpenTUI's renderer and the clipboard's addon. A
 * compiled chord writes an embedded library to a temporary file and loads it
 * from there, and the hardened runtime loads only a library signed by the
 * binary's own team, so OpenTUI's and the clipboard's own signatures would
 * leave the window unable to start. Only the signature changes; the
 * release's self-test opens the window and reads the clipboard on each
 * signed binary, which a library left out fails.
 */
export function natives(release: Release): void {
  const id = identity(release);
  const found = run(release, 'find', [
    'node_modules',
    '-path',
    '*darwin*',
    '(',
    '-name',
    '*.dylib',
    '-o',
    '-name',
    '*.node',
    ')',
    '-type',
    'f',
    '-print0',
  ])
    .stdout.split('\0')
    .filter(Boolean);

  for (const library of found) {
    // Signed as a copy and renamed over the original, so a chord running from
    // source keeps the library it mapped rather than one changed under it.
    const path = join(release.root, library);
    const signed = `${path}.signing`;
    const { atime, mtime } = statSync(path);

    copyFileSync(path, signed);
    utimesSync(signed, atime, mtime);

    if (
      run(
        release,
        'codesign',
        ['--force', '--sign', id, '--timestamp', signed],
        {
          stdio: 'inherit',
        },
      ).status !== 0
    ) {
      die(`codesign failed for ${library}`);
    }

    if (
      run(release, 'codesign', ['--verify', '--strict', signed], {
        stdio: 'inherit',
      }).status !== 0
    ) {
      die(`${library} does not verify`);
    }

    renameSync(signed, path);
    release.out(`signed ${library}`);
  }

  if (found.length === 0) {
    die(
      "no macOS native library found under node_modules; was bun install --os='*' --cpu='*' run?",
    );
  }
}

/**
 * Signs built chords: hardened runtime, secure timestamp, the one
 * entitlement, then --verify --strict and the signed entitlements read back
 * and compared with scripts/macos/chord.entitlements, since a binary without
 * its entitlement still passes a quick look.
 */
export function sign(release: Release, binaries: readonly string[]): void {
  const entitlements = join(
    release.root,
    'scripts',
    'macos',
    'chord.entitlements',
  );

  const id = identity(release);

  for (const binary of binaries) {
    if (
      !statSync(join(release.root, binary), { throwIfNoEntry: false })?.isFile()
    ) {
      die(`no binary at ${binary}`);
    }

    if (
      run(
        release,
        'codesign',
        [
          '--force',
          '--sign',
          id,
          '--options',
          'runtime',
          '--timestamp',
          '--entitlements',
          entitlements,
          '--identifier',
          'dev.katsuba.chord',
          binary,
        ],
        { stdio: 'inherit' },
      ).status !== 0
    ) {
      die(`codesign failed for ${binary}`);
    }

    if (
      run(
        release,
        'codesign',
        ['--verify', '--strict', '--verbose=2', binary],
        {
          stdio: 'inherit',
        },
      ).status !== 0
    ) {
      die(`${binary} does not verify`);
    }

    const signed = run(release, 'codesign', [
      '-d',
      '--entitlements',
      '-',
      '--xml',
      binary,
    ]);

    if (signed.status !== 0) {
      die(`the entitlements of ${binary} could not be read back`);
    }

    const read = run(release, 'plutil', ['-convert', 'json', '-o', '-', '-'], {
      input: signed.stdout,
    });
    const got = said(read.stdout + read.stderr);
    const want = said(
      run(release, 'plutil', ['-convert', 'json', '-o', '-', entitlements])
        .stdout,
    );

    if (got !== want) {
      die(
        `entitlements of ${binary} differ from scripts/macos/chord.entitlements: got ${got}, want ${want}`,
      );
    }

    release.out(`signed ${binary}: ${got}`);
  }
}
