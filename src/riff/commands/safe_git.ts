/**
 * Adapted from vercel-labs/fx v0.0.16,
 * src/core/shell_command/safe_git.zig, Apache-2.0.
 * chord delegates repository config parsing to trusted git (see git_config.ts),
 * uses node process APIs and separates preparation from the pure command plan.
 */
import { Buffer } from 'node:buffer';
import { execFile } from 'node:child_process';
import { stat, realpath } from 'node:fs/promises';
import process from 'node:process';
import { TextDecoder } from 'node:util';
import type { DirectStage } from './effect.ts';
import type { DirectInvocation } from './direct.ts';
import { discoverRepository, repositoryFilters } from './git_config.ts';

export type GitRefusal =
  | 'git_missing'
  | 'git_version_unknown'
  | 'git_too_old'
  | 'repo_config_unavailable'
  | 'unsupported_filter_name'
  | 'repository_mismatch';
export type SafeGit = {
  executable: string;
  filterNames: readonly string[];
  environment: Record<string, string>;
};
export type GitPreparation =
  { kind: 'ready'; ready: SafeGit } | { kind: 'refused'; reason: GitRefusal };

/** Only the user's config locations cross the fixed execution boundary. */
export function gitEnvironment(
  source: NodeJS.ProcessEnv = process.env,
): Record<string, string> {
  const env: Record<string, string> = {
    PATH: '/usr/bin:/bin',
    LC_ALL: 'C',
    LANG: 'C',
    GIT_OPTIONAL_LOCKS: '0',
    GIT_TERMINAL_PROMPT: '0',
    GIT_PAGER: 'cat',
    PAGER: 'cat',
  };

  for (const key of [
    'HOME',
    'XDG_CONFIG_HOME',
    'GIT_CONFIG_GLOBAL',
    'GIT_CONFIG_SYSTEM',
    'GIT_CONFIG_NOSYSTEM',
  ]) {
    if (source[key] !== undefined) {
      env[key] = source[key];
    }
  }

  return env;
}

export function classifyGitVersion(
  output: string,
): 'supported' | 'too_old' | 'unknown' {
  const match = /^git version (\d+)\.(\d+)/.exec(output);

  if (!match) {
    return 'unknown';
  }

  const major = Number(match[1]);
  const minor = Number(match[2]);

  if (
    !Number.isSafeInteger(major) ||
    !Number.isSafeInteger(minor) ||
    major > 0xffffffff ||
    minor > 0xffffffff
  ) {
    return 'unknown';
  }

  return major > 2 || (major === 2 && minor >= 25) ? 'supported' : 'too_old';
}

const checkedVersions = new Map<string, 'supported' | 'too_old' | 'unknown'>();

async function trustedExecutable(): Promise<string | null> {
  for (const path of [
    '/usr/bin/git',
    '/bin/git',
    '/usr/local/bin/git',
    '/opt/homebrew/bin/git',
    '/opt/local/bin/git',
    '/run/current-system/sw/bin/git',
  ]) {
    try {
      if ((await stat(path)).isFile()) {
        return path;
      }
    } catch {
      /* Try the next fixed location. */
    }
  }

  return null;
}

function captured(
  executable: string,
  args: readonly string[],
  cwd: string,
  env: Record<string, string>,
  maxBuffer = 4096,
  input?: Buffer,
  signal?: AbortSignal,
): Promise<string | null> {
  return new Promise((resolve) => {
    const child = execFile(
      executable,
      args,
      {
        cwd,
        env,
        maxBuffer,
        encoding: 'buffer',
        ...(signal === undefined ? {} : { signal }),
      },
      (error, stdout) => {
        if (error) {
          return resolve(null);
        }

        try {
          resolve(new TextDecoder('utf-8', { fatal: true }).decode(stdout));
        } catch {
          resolve(null);
        }
      },
    );

    child.stdin?.on('error', () => {});

    child.stdin?.end(input);
  });
}

/**
 * git parses the same bounded bytes the loader inspected, never reopening a path.
 * Parsing from / avoids discovery of repository metadata unrelated to the input.
 */
export function parseGitConfig(
  executable: string,
  bytes: Buffer,
  environment: Record<string, string>,
  signal?: AbortSignal,
): Promise<string | null> {
  return captured(
    executable,
    ['config', '--file', '-', '--no-includes', '--null', '--list'],
    '/',
    environment,
    2 * 1024 * 1024,
    bytes,
    signal,
  );
}

function prelude(ready: SafeGit): string[] {
  const args = [
    '--no-pager',
    '--no-optional-locks',
    '-c',
    'core.fsmonitor=false',
    '-c',
    'core.hooksPath=/dev/null',
    '-c',
    'log.showSignature=false',
  ];

  for (const name of ready.filterNames) {
    for (const program of ['clean', 'smudge', 'process']) {
      args.push('-c', `filter.${name}.${program}=`);
    }
  }

  return args;
}

/** Applies fx's overrides before a supported command's canonical arguments. */
export function gitInvocation(
  ready: SafeGit,
  stage: DirectStage,
): DirectInvocation {
  const [, sub, ...args] = stage.argv;
  const flags =
    sub === 'status'
      ? ['--ignore-submodules=all']
      : ['--no-ext-diff', '--no-textconv', '--ignore-submodules=all'];

  return {
    executable: ready.executable,
    argv: [ready.executable, ...prelude(ready), sub!, ...flags, ...args],
    environment: ready.environment,
  };
}

/** Refuses rather than falling back to an unprotected git invocation. */
export async function prepareGit(
  cwd: string,
  source: NodeJS.ProcessEnv = process.env,
  signal?: AbortSignal,
): Promise<GitPreparation> {
  signal?.throwIfAborted();

  const executable = await trustedExecutable();

  if (executable === null) {
    return { kind: 'refused', reason: 'git_missing' };
  }

  const environment = gitEnvironment(source);
  let version = checkedVersions.get(executable);

  if (version === undefined) {
    const output = await captured(
      executable,
      ['--version'],
      '/',
      environment,
      4096,
      undefined,
      signal,
    );

    signal?.throwIfAborted();

    version = classifyGitVersion(output ?? '');

    if (output !== null) {
      checkedVersions.set(executable, version);
    }
  }

  if (version !== 'supported') {
    return {
      kind: 'refused',
      reason: version === 'too_old' ? 'git_too_old' : 'git_version_unknown',
    };
  }

  let layout;
  let filterNames;

  try {
    layout = await discoverRepository(cwd);
    filterNames = await repositoryFilters(
      layout,
      environment['HOME'],
      (_path, bytes) => parseGitConfig(executable, bytes, environment, signal),
    );
  } catch {
    signal?.throwIfAborted();

    return { kind: 'refused', reason: 'repo_config_unavailable' };
  }

  if (filterNames.some((name) => name.length === 0 || name.includes('='))) {
    return { kind: 'refused', reason: 'unsupported_filter_name' };
  }

  const ready = { executable, filterNames, environment };
  const reported = await captured(
    executable,
    [...prelude(ready), 'rev-parse', '--absolute-git-dir'],
    cwd,
    environment,
    4096,
    undefined,
    signal,
  );

  signal?.throwIfAborted();

  if (layout === null) {
    return reported === null
      ? { kind: 'ready', ready }
      : { kind: 'refused', reason: 'repository_mismatch' };
  }

  try {
    if (
      reported === null ||
      (await realpath(reported.replace(/[\r\n]+$/, ''))) !==
        (await realpath(layout.gitDir))
    ) {
      return { kind: 'refused', reason: 'repository_mismatch' };
    }
  } catch {
    return { kind: 'refused', reason: 'repository_mismatch' };
  }

  return { kind: 'ready', ready };
}
