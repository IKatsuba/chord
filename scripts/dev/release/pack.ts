/**
 * Lays out the five npm packages from the signed binaries in dist/
 * (`bun run dev npm`), packs them, installs the tarballs in scratch projects,
 * and checks the installed copies as a user gets them: the same bytes as
 * built, a macOS one still verifying and not quarantined, and the arm64 one
 * self-tested through the shim, the x64 one under Rosetta. The tarballs then
 * go to dist/release/tgz/ with their sums recorded beside them, for publish.
 */
import type { SpawnSyncOptions } from 'node:child_process';
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { die, npm, PACKAGES, type Release, run } from './lib.ts';
import { packageVersion } from './preflight.ts';
import { tarballs } from './publish.ts';
import { selftest } from './selftest.ts';
import { recordSums } from './sums.ts';

/**
 * Packs the release. `test` self-tests the installed copies; a test passes
 * one that runs no binary.
 */
export async function pack(
  release: Release,
  test: typeof selftest = selftest,
): Promise<void> {
  const out = join(release.root, 'dist', 'release', 'packages');

  await packages(release, out, test);

  const tgz = tarballs(release);
  const version = packageVersion(release);
  const files = PACKAGES.map((name) => `chorded-${name}-${version}.tgz`);

  mkdirSync(tgz, { recursive: true });

  for (const file of files) {
    copyFileSync(join(out, 'tgz', file), join(tgz, file));
  }

  recordSums(tgz, files);
}

async function packages(
  release: Release,
  out: string,
  test: typeof selftest,
): Promise<void> {
  const quiet: SpawnSyncOptions = { stdio: ['inherit', 'ignore', 'inherit'] };

  rmSync(out, { recursive: true, force: true });
  mkdirSync(join(out, 'tgz'), { recursive: true });

  if (run(release, 'bun', ['scripts/dev.ts', 'npm'], quiet).status !== 0) {
    die('laying out npm/ failed');
  }

  for (const name of PACKAGES) {
    if (
      npm(release, ['pack', '--pack-destination', join(out, 'tgz')], {
        ...quiet,
        cwd: join(release.root, 'npm', name),
      }).status !== 0
    ) {
      die(`npm pack of ${name} failed`);
    }
  }

  const version = packageVersion(release);
  const tgz = (name: string) =>
    join(out, 'tgz', `chorded-${name}-${version}.tgz`);
  const scratch = mkdtempSync(join(tmpdir(), 'chord-packages-'));
  const install = (cwd: string, args: string[], output: SpawnSyncOptions) =>
    npm(release, ['init', '-y'], { ...quiet, cwd }).status === 0 &&
    npm(release, ['install', '--no-audit', '--no-fund', ...args], {
      ...output,
      cwd,
    }).status === 0;

  try {
    if (!install(scratch, [tgz('chord'), tgz('chord-darwin-arm64')], quiet)) {
      die('installing the tarballs failed');
    }

    // Every other platform package goes into a scratch project of its own;
    // npm refuses one for another platform unless forced past its os and cpu
    // check, which changes nothing in it.
    const others = ['chord-darwin-x64', 'chord-linux-arm64', 'chord-linux-x64'];

    for (const name of others) {
      mkdirSync(join(scratch, name));

      if (
        !install(join(scratch, name), ['--force', tgz(name)], {
          stdio: ['inherit', 'ignore', 'ignore'],
        })
      ) {
        die(`installing the ${name} tarball failed`);
      }
    }

    const checkInstalled = (installed: string, built: string) => {
      if (!readFileSync(installed).equals(readFileSync(built))) {
        die(`the installed ${installed} differs from ${built}`);
      }

      if (installed.includes('darwin')) {
        if (
          run(release, 'codesign', ['--verify', '--strict', installed], {
            stdio: 'inherit',
          }).status !== 0
        ) {
          die(`the installed ${installed} does not verify`);
        }

        if (
          run(release, 'xattr', [installed]).stdout.includes(
            'com.apple.quarantine',
          )
        ) {
          die(`npm quarantined ${installed}`);
        }
      }
    };

    checkInstalled(
      join(
        scratch,
        'node_modules',
        '@chorded',
        'chord-darwin-arm64',
        'bin',
        'chord',
      ),
      join(release.root, 'dist', 'bun-darwin-arm64', 'chord'),
    );

    for (const name of others) {
      checkInstalled(
        join(scratch, name, 'node_modules', '@chorded', name, 'bin', 'chord'),
        join(
          release.root,
          'dist',
          `bun-${name.replace(/^chord-/, '')}`,
          'chord',
        ),
      );
    }

    await test(release, join(scratch, 'node_modules', '.bin', 'chord'));
    await test(
      release,
      join(
        scratch,
        'chord-darwin-x64',
        'node_modules',
        '@chorded',
        'chord-darwin-x64',
        'bin',
        'chord',
      ),
      'x86_64',
    );
    release.out(`packed ${join(out, 'tgz')}`);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}
