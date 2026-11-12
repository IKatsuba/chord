import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, realpath, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { cursorUrl, type Git, repository } from '../src/repo.ts';

// The person's git configuration stays out: a global pushDefault would
// change every answer here.
const saved = {
  global: process.env.GIT_CONFIG_GLOBAL,
  system: process.env.GIT_CONFIG_NOSYSTEM,
};
let root = '';

beforeAll(async () => {
  process.env.GIT_CONFIG_GLOBAL = '/dev/null';
  process.env.GIT_CONFIG_NOSYSTEM = '1';
  root = await realpath(await mkdtemp(join(tmpdir(), 'cursor-cloud-repo-')));
});

afterAll(async () => {
  for (const [name, value] of [
    ['GIT_CONFIG_GLOBAL', saved.global],
    ['GIT_CONFIG_NOSYSTEM', saved.system],
  ] as const) {
    if (value === undefined) {
      delete process.env[name];
    } else {
      process.env[name] = value;
    }
  }

  await rm(root, { recursive: true, force: true });
});

/** git in `cwd`, which must succeed. */
function sh(cwd: string, ...args: string[]) {
  const result = spawnSync('git', args, { cwd, encoding: 'utf8' });

  expect(result.status, result.stderr).toBe(0);

  return result.stdout.trim();
}

let count = 0;

/** A new repository on branch `main` with one commit. */
async function repo() {
  const dir = join(root, `r${(count += 1)}`);

  await mkdir(dir);
  sh(dir, 'init', '-q', '-b', 'main');
  sh(
    dir,
    '-c',
    'user.name=t',
    '-c',
    'user.email=t@e',
    'commit',
    '-q',
    '--allow-empty',
    '-m',
    'a',
  );

  return dir;
}

/** A repository with origin at `url` and main's remote-tracking ref at HEAD. */
async function pushed(url = 'git@github.com:acme/web.git') {
  const dir = await repo();

  sh(dir, 'remote', 'add', 'origin', url);
  sh(dir, 'update-ref', 'refs/remotes/origin/main', 'HEAD');

  return dir;
}

const refusal = async (cwd: string, run?: Git) => {
  const error = await repository(cwd, run).catch((caught: unknown) => caught);

  return {
    code: (error as { code?: number }).code,
    message: (error as Error).message,
  };
};

describe('repository', () => {
  test('a pushed branch: its push remote, and the URL in Cursor’s form', async () => {
    expect(await repository(await pushed())).toEqual({
      url: 'https://github.com/acme/web',
      branch: 'main',
      remote: 'origin',
    });
  });

  test('behind its remote-tracking ref is pushed', async () => {
    const dir = await pushed();

    sh(
      dir,
      '-c',
      'user.name=t',
      '-c',
      'user.email=t@e',
      'commit',
      '-q',
      '--allow-empty',
      '-m',
      'b',
    );
    sh(dir, 'update-ref', 'refs/remotes/origin/main', 'HEAD');
    sh(dir, 'reset', '-q', '--hard', 'HEAD~1');
    expect((await repository(dir)).branch).toBe('main');
  });

  test('a host hosted-git-info does not know is passed as git has it', async () => {
    expect(
      (await repository(await pushed('https://git.example.com/acme/web.git')))
        .url,
    ).toBe('https://git.example.com/acme/web.git');
  });

  test("the push remote is git's: remote.pushDefault over origin", async () => {
    const dir = await pushed();

    sh(dir, 'remote', 'add', 'fork', 'https://gitlab.com/me/web.git');
    sh(dir, 'config', 'remote.pushDefault', 'fork');
    expect(await refusal(dir)).toEqual({
      code: -32602,
      message:
        'Branch main is not pushed to fork. A cloud agent starts from a pushed branch: run git push -u fork main, then start again.',
    });
    sh(dir, 'update-ref', 'refs/remotes/fork/main', 'HEAD');
    expect(await repository(dir)).toEqual({
      url: 'https://gitlab.com/me/web',
      branch: 'main',
      remote: 'fork',
    });
  });

  test('not pushed: no remote-tracking ref', async () => {
    const dir = await repo();

    sh(dir, 'remote', 'add', 'origin', 'git@github.com:acme/web.git');
    expect(await refusal(dir)).toEqual({
      code: -32602,
      message:
        'Branch main is not pushed to origin. A cloud agent starts from a pushed branch: run git push -u origin main, then start again.',
    });
  });

  test('not pushed: ahead of its remote-tracking ref', async () => {
    const dir = await pushed();

    sh(
      dir,
      '-c',
      'user.name=t',
      '-c',
      'user.email=t@e',
      'commit',
      '-q',
      '--allow-empty',
      '-m',
      'b',
    );
    expect((await refusal(dir)).message).toStartWith(
      'Branch main is not pushed to origin.',
    );
  });

  test('no remote', async () => {
    expect(await refusal(await repo())).toEqual({
      code: -32602,
      message:
        'Branch main has no remote to push to. A cloud agent starts from a pushed branch: run git remote add origin <url> and git push -u origin main, then start again.',
    });
  });

  test('the remote `.`', async () => {
    const dir = await repo();

    sh(dir, 'config', 'branch.main.remote', '.');
    expect((await refusal(dir)).message).toStartWith(
      'Branch main has no remote to push to.',
    );
  });

  test('a detached HEAD', async () => {
    const dir = await pushed();

    sh(dir, 'checkout', '-q', '--detach');
    expect(await refusal(dir)).toEqual({
      code: -32602,
      message:
        'HEAD is detached. A cloud agent starts from a pushed branch: run git switch <branch>, then start again.',
    });
  });

  test('not a repository, and inside .git', async () => {
    const outside = join(root, 'plain');

    await mkdir(outside);
    expect(await refusal(outside)).toEqual({
      code: -32602,
      message: `${outside} is not in a git work tree. A cloud agent starts from a pushed branch: start chord in a repository, then start again.`,
    });

    const dir = await repo();

    expect((await refusal(join(dir, '.git'))).message).toStartWith(
      `${join(dir, '.git')} is not in a git work tree.`,
    );
  });
});

describe('git failing', () => {
  test("names the command, the cwd and git's last line", async () => {
    const run: Git = () =>
      Promise.resolve({
        status: 129,
        stdout: '',
        stderr: 'warning: a\nfatal: bad config line 1\n',
      });

    expect(await refusal('/w', run)).toEqual({
      code: -32602,
      message:
        'git rev-parse --is-inside-work-tree failed in /w: fatal: bad config line 1',
    });
  });

  test('stopped at the bound', async () => {
    const run: Git = () =>
      Promise.resolve({ status: null, stdout: '', stderr: '' });

    expect((await refusal('/w', run)).message).toBe(
      'git rev-parse --is-inside-work-tree failed in /w: it did not answer within 10 s',
    );
  });

  test('not started at all', async () => {
    const run: Git = () => Promise.reject(new Error('spawn git ENOENT'));

    expect((await refusal('/w', run)).message).toBe(
      'git rev-parse --is-inside-work-tree failed in /w: spawn git ENOENT',
    );
  });
});

test('cursorUrl: the known hosts as https://host/owner/repo, others as given', () => {
  expect(
    [
      'git@github.com:acme/web.git',
      'https://user:token@github.com/acme/web.git',
      'ssh://git@gitlab.com/acme/sub/web.git',
      'git@bitbucket.org:acme/web.git',
      'git@git.sr.ht:~acme/web',
      'https://git.example.com/acme/web.git',
    ].map(cursorUrl),
  ).toEqual([
    'https://github.com/acme/web',
    'https://github.com/acme/web',
    'https://gitlab.com/acme/sub/web',
    'https://bitbucket.org/acme/web',
    'https://git.sr.ht/~acme/web',
    'https://git.example.com/acme/web.git',
  ]);
});
