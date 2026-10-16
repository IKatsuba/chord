/**
 * The release's build: dependencies as locked, every check, every
 * platform's native packages, and every binary, built on this arm64 Mac.
 */
import { join } from 'node:path';
import { die, type Release, run } from './lib.ts';
import { natives as signNatives } from './sign.ts';

const loud = { stdio: 'inherit' } as const;

export function install(release: Release): void {
  if (
    run(release, process.execPath, ['install', '--frozen-lockfile'], loud)
      .status !== 0
  ) {
    die('bun install --frozen-lockfile failed');
  }
}

export function check(release: Release): void {
  if (run(release, process.execPath, ['run', 'check'], loud).status !== 0) {
    die('bun run check failed');
  }
}

/** Every platform's packages installed, and their macOS libraries signed. */
export function natives(release: Release): void {
  if (
    run(
      release,
      process.execPath,
      ['install', '--frozen-lockfile', '--os=*', '--cpu=*'],
      loud,
    ).status !== 0
  ) {
    die("installing every platform's packages failed");
  }

  signNatives(release);
}

/** What file(1) says each target's binary is. */
export const KINDS = {
  'bun-darwin-arm64': 'Mach-O 64-bit executable arm64',
  'bun-darwin-x64': 'Mach-O 64-bit executable x86_64',
  'bun-linux-arm64': 'ELF 64-bit LSB executable, ARM aarch64',
  'bun-linux-x64': 'ELF 64-bit LSB executable, x86-64',
} as const;

/** Every binary built, each checked to be the kind its target builds. */
export function compile(release: Release): void {
  if (
    run(release, process.execPath, ['scripts/dev.ts', 'compile', '--all'], loud)
      .status !== 0
  ) {
    die('compile --all failed');
  }

  for (const [target, want] of Object.entries(KINDS)) {
    checkKind(release, target, want);
  }
}

export function checkKind(release: Release, target: string, want: string) {
  const binary = join('dist', target, 'chord');
  const kind = run(release, 'file', [binary]).stdout.replace(/\n$/, '');

  if (!kind.includes(want)) {
    die(`${binary} is ${kind}`);
  }
}
