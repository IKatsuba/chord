/**
 * Shared by the release's stages: every check dies with what it read.
 */
import { spawnSync, type SpawnSyncOptions } from 'node:child_process';
import { accessSync, constants, realpathSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { delimiter, join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';

/**
 * A check the release died on. `bun dev release` prints its message as
 * `release: …` on stderr and exits 1; a test reads it where it is thrown.
 */
export class ReleaseError extends Error {
  override name = 'ReleaseError';
}

export function die(message: string): never {
  throw new ReleaseError(message);
}

/**
 * Where a release runs and what it reaches outside itself, so a test runs
 * one against a scratch repository, a faked npm and no waiting.
 */
export interface Release {
  /** The repository's root. */
  readonly root: string;
  /** The environment every command runs in, PATH included. */
  readonly env: NodeJS.ProcessEnv;
  readonly sleep: (ms: number) => Promise<void>;
  readonly out: (line: string) => void;
  readonly err: (line: string) => void;
  /** Whether stdin and stdout are both a terminal, as npm's prompt needs. */
  readonly tty: boolean;
}

/** The release of the tree this file is in, on this process's terminal. */
export function release(): Release {
  return {
    root: new URL('../../..', import.meta.url).pathname,
    env: process.env,
    sleep: async (ms) => {
      await sleep(ms);
    },
    out: (line) => process.stdout.write(`${line}\n`),
    err: (line) => process.stderr.write(`${line}\n`),
    tty: Boolean(process.stdin.isTTY && process.stdout.isTTY),
  };
}

/** A command's exit status and output, its output as text. */
export interface Ran {
  readonly status: number | null;
  readonly stdout: string;
  readonly stderr: string;
}

/** Runs `command` in the release's root and environment and waits for it. */
export function run(
  release: Release,
  command: string,
  args: readonly string[],
  options: SpawnSyncOptions = {},
): Ran {
  const { status, stdout, stderr, error } = spawnSync(command, args, {
    cwd: release.root,
    env: release.env,
    ...options,
  });

  return {
    status: error === undefined ? status : null,
    stdout: String(stdout ?? ''),
    stderr: String(stderr ?? error?.message ?? ''),
  };
}

/**
 * Runs npm with `args` on node, as `<node> <npm's script>`. Under `bun run
 * dev`, bunfig.toml's `[run] bun = true` puts Bun first on PATH as `node`,
 * and npm on Bun fails (docs/decisions.md, 2026-10-16), so npm's own
 * `#!/usr/bin/env node` cannot be trusted to find node.
 */
export function npm(
  release: Release,
  args: readonly string[],
  options: SpawnSyncOptions = {},
): Ran {
  return run(
    release,
    notBun(release, 'node'),
    [notBun(release, 'npm'), ...args],
    options,
  );
}

/** The first `name` on PATH that is not Bun itself, by its realpath. */
function notBun(release: Release, name: string): string {
  const bun = realpathSync(process.execPath);

  for (const dir of (release.env['PATH'] ?? '').split(delimiter)) {
    if (dir === '') {
      continue;
    }

    const path = join(dir, name);

    try {
      accessSync(path, constants.X_OK);

      const real = realpathSync(path);

      if (statSync(real).isFile() && real !== bun) {
        return real;
      }
    } catch {
      // Not there, or not runnable: the next directory.
    }
  }

  die(
    `no ${name} other than Bun's on PATH; npm runs on node (bun dev puts Bun first as node, docs/decisions.md)`,
  );
}

/** A command's output as `$(…)` gives it: trailing newlines cut. */
export function said(text: string): string {
  return text.replace(/\n+$/, '');
}

/**
 * The packages, in the order they are published: the platform packages,
 * then the main one, whose exact-version optionalDependencies must resolve.
 */
export const PLATFORMS = [
  'chord-darwin-arm64',
  'chord-darwin-x64',
  'chord-linux-arm64',
  'chord-linux-x64',
] as const;
export const PACKAGES = [...PLATFORMS, 'chord'] as const;

export type Package = (typeof PACKAGES)[number];

/**
 * The one Developer ID Application identity of the team, found by team in
 * the login keychain so a renewed certificate is picked up; none or several
 * stop.
 */
export const TEAM = 'YQ8ZD2KZ3T';

export function identity(release: Release): string {
  const found = said(
    run(release, 'security', [
      'find-identity',
      '-v',
      '-p',
      'codesigning',
      join(homedir(), 'Library', 'Keychains', 'login.keychain-db'),
    ]).stdout,
  );
  const matches = found
    .split('\n')
    .filter(
      (line) =>
        line.includes(`Developer ID Application: `) &&
        line.includes(`(${TEAM})`),
    );

  if (matches.length !== 1) {
    die(
      `expected one Developer ID Application identity of team ${TEAM}, found ${matches.length}; security find-identity said:\n${found}`,
    );
  }

  const hash = /^ *[0-9]+\) ([0-9A-F]{40}) /.exec(matches[0]!)?.[1];

  return hash ?? matches[0]!;
}

/**
 * Whether @chorded/NAME has VERSION on npm: yes, no (a 404, or the package
 * without that version), or a failure to ask, which stops the release.
 */
export function published(
  release: Release,
  name: string,
  version: string,
): boolean {
  // Only stdout is the answer; npm's warnings go to stderr.
  const view = npm(release, ['view', `@chorded/${name}@${version}`, 'version']);

  if (view.status === 0) {
    const answer = said(view.stdout);

    if (answer === version) {
      return true;
    }

    if (answer === '') {
      return false;
    }

    die(`npm view @chorded/${name}@${version} answered "${answer}"`);
  }

  if (view.stderr.includes('code E404')) {
    return false;
  }

  die(`npm view @chorded/${name}@${version} failed: ${said(view.stderr)}`);
}

/** How many times waitPublished asks, and how long apart. */
export const WAIT_ATTEMPTS = 60;
export const WAIT_MS = 15_000;

/**
 * Waits until @chorded/NAME answers npm view at VERSION: npm can hold a
 * package it accepted in validation for minutes, and a main package published
 * in that window installs with no binary, as board's 1.0.0 did. 60 attempts
 * 15 seconds apart, a guess at how long validation takes; each miss is said on
 * stderr, and it answers false when they run out. A registry failure other
 * than a 404 still stops, as in published.
 */
export async function waitPublished(
  release: Release,
  name: string,
  version: string,
): Promise<boolean> {
  for (let attempt = 1; attempt <= WAIT_ATTEMPTS; attempt++) {
    if (published(release, name, version)) {
      return true;
    }

    release.err(
      `release: waiting for @chorded/${name}@${version} to answer npm view (${attempt}/${WAIT_ATTEMPTS})`,
    );

    if (attempt < WAIT_ATTEMPTS) {
      await release.sleep(WAIT_MS);
    }
  }

  return false;
}

/** Runs `work`, and a death in it as `release: …` on stderr, exit 1. */
export async function dying(work: () => Promise<void>): Promise<void> {
  try {
    await work();
  } catch (error) {
    if (!(error instanceof ReleaseError)) {
      throw error;
    }

    process.stderr.write(`release: ${error.message}\n`);
    // A turn of the event loop first, so a signal that failed the stage
    // exits with its own status (`holdVersion`).
    await new Promise((resolve) => setImmediate(resolve));
    process.exit(1);
  }
}
