/**
 * The session's repository, from git in its cwd: the branch a cloud agent
 * starts from, its push remote and that remote's URL in Cursor's form. Local
 * and first, so a refusal needs no key, keychain or network. "Pushed" reads
 * the local remote-tracking ref (Q4): a ref fetched before a force-push or a
 * deletion passes, and Cursor's own refusal has the last word.
 */
import { spawn } from 'node:child_process';
import hostedGitInfo from 'hosted-git-info';
import { refused } from './errors.ts';

/** How one git command ended. */
export interface GitResult {
  /** null when it was stopped: the bound passed. */
  readonly status: number | null;
  readonly stdout: string;
  readonly stderr: string;
}

/** Runs git with `args` in `cwd`; rejects only when git cannot be started. */
export type Git = (args: readonly string[], cwd: string) => Promise<GitResult>;

/** What a cloud agent starts from. */
export interface Repository {
  /** The push remote's URL in Cursor's form. */
  readonly url: string;
  readonly branch: string;
  readonly remote: string;
}

export const BOUND_MS = 10_000;

/**
 * git itself, with no terminal: stdin ignored and git's own prompts off, so
 * a passphrase it would ask for fails it rather than hanging the start.
 */
export const git: Git = (args, cwd) =>
  new Promise((resolve, reject) => {
    const child = spawn('git', args, {
      cwd,
      env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: BOUND_MS,
    });
    let stdout = '';
    let stderr = '';

    child.stdout.setEncoding('utf8').on('data', (chunk) => (stdout += chunk));
    child.stderr.setEncoding('utf8').on('data', (chunk) => (stderr += chunk));
    child.on('error', reject);
    child.on('close', (status) => resolve({ status, stdout, stderr }));
  });

/**
 * A repository URL in Cursor's form: `https://host/owner/repo` for the
 * hosts `hosted-git-info` knows, any other as git has it.
 */
export function cursorUrl(url: string): string {
  return hostedGitInfo.fromUrl(url)?.browse({ noCommittish: true }) ?? url;
}

/**
 * The repository a session in `cwd` starts from, or a refusal (-32602)
 * saying why and what to do.
 */
export async function repository(
  cwd: string,
  run: Git = git,
): Promise<Repository> {
  /** git's answer, its output trimmed; any failure refuses naming it. */
  const ask = async (
    args: readonly string[],
    ok: readonly number[] = [0],
  ): Promise<{ status: number; out: string }> => {
    let result: GitResult;

    try {
      result = await run(args, cwd);
    } catch (error) {
      throw failed(
        args,
        cwd,
        error instanceof Error ? error.message : String(error),
      );
    }

    if (result.status === null || !ok.includes(result.status)) {
      throw failed(
        args,
        cwd,
        result.status === null
          ? `it did not answer within ${BOUND_MS / 1000} s`
          : (result.stderr.trim().split('\n').at(-1) ?? ''),
      );
    }

    return { status: result.status, out: result.stdout.trim() };
  };

  // Outside a repository git answers 128; inside its .git, false.
  const inside = await ask(['rev-parse', '--is-inside-work-tree'], [0, 128]);

  if (inside.out !== 'true') {
    throw refused(
      `${cwd} is not in a git work tree. A cloud agent starts from a pushed branch: start chord in a repository, then start again.`,
    );
  }

  const head = await ask(
    ['symbolic-ref', '--quiet', '--short', 'HEAD'],
    [0, 1],
  );

  if (head.status === 1) {
    throw refused(
      'HEAD is detached. A cloud agent starts from a pushed branch: run git switch <branch>, then start again.',
    );
  }

  const branch = head.out;
  const remote = await pushRemote(branch, ask);

  if (remote === undefined || remote === '.') {
    throw refused(
      `Branch ${branch} has no remote to push to. A cloud agent starts from a pushed branch: run git remote add origin <url> and git push -u origin ${branch}, then start again.`,
    );
  }

  const tracking = `refs/remotes/${remote}/${branch}`;
  const known = await ask(
    ['rev-parse', '--verify', '--quiet', tracking],
    [0, 1],
  );
  const pushed =
    known.status === 0 &&
    (await ask(['merge-base', '--is-ancestor', 'HEAD', tracking], [0, 1]))
      .status === 0;

  if (!pushed) {
    throw refused(
      `Branch ${branch} is not pushed to ${remote}. A cloud agent starts from a pushed branch: run git push -u ${remote} ${branch}, then start again.`,
    );
  }

  const url = await ask(['remote', 'get-url', '--push', remote]);

  return { url: cursorUrl(url.out), branch, remote };
}

/**
 * Where git pushes `branch`: its pushRemote, remote.pushDefault or its
 * remote, as git's own `push:remotename` gives them, else origin when there
 * is one, as `git push` falls back to it; none without either.
 */
async function pushRemote(
  branch: string,
  ask: (args: readonly string[]) => Promise<{ out: string }>,
): Promise<string | undefined> {
  const named = await ask([
    'for-each-ref',
    '--format=%(push:remotename)',
    `refs/heads/${branch}`,
  ]);

  if (named.out !== '') {
    return named.out;
  }

  const remotes = (await ask(['remote'])).out.split('\n');

  return remotes.includes('origin') ? 'origin' : undefined;
}

function failed(args: readonly string[], cwd: string, line: string) {
  return refused(`git ${args.join(' ')} failed in ${cwd}: ${line}`);
}
