import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  realpath,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { cursorUrl, type Git, gitRunner, repository } from '../src/repo.ts';

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

  test("a push URL's user and password never leave repository()", async () => {
    expect(
      (await repository(await pushed('https://u:tok@git.example.com/a/b.git')))
        .url,
    ).toBe('https://git.example.com/a/b.git');
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

describe('the git runner', () => {
  test('answers git’s status and output, with no terminal for it', async () => {
    const dir = await pushed();
    const run = gitRunner();

    expect(await run(['rev-parse', '--abbrev-ref', 'HEAD'], dir)).toEqual({
      status: 0,
      stdout: 'main\n',
      stderr: '',
    });
    expect((await run(['config', 'core.no-such-key'], dir)).status).toBe(1);
  });

  test('kills a git that ignores SIGTERM at the bound, and reaps it', async () => {
    const dir = join(root, 'stubborn');
    const fake = join(dir, 'git');
    const pidFile = join(dir, 'pid');

    await mkdir(dir);
    // exec keeps the pid and the ignored SIGTERM: one process to find.
    await writeFile(
      fake,
      `#!/bin/sh\necho $$ > '${pidFile}'\ntrap '' TERM\nexec sleep 30\n`,
    );
    await chmod(fake, 0o755);

    const started = performance.now();
    // Long enough for macOS to admit a new executable, which takes a moment.
    const result = await gitRunner(fake, 3000)(['status'], dir);

    expect(result.status).toBeNull();
    expect(performance.now() - started).toBeLessThan(10_000);

    const pid = Number(await readFile(pidFile, 'utf8'));

    expect(Number.isSafeInteger(pid) && pid > 0).toBe(true);
    expect(() => process.kill(pid, 0)).toThrow(
      expect.objectContaining({ code: 'ESRCH' }),
    );
  });

  test('rejects when git cannot be started', async () => {
    await expect(
      gitRunner(join(root, 'no-such-git'))(['status'], root),
    ).rejects.toThrow('ENOENT');
  });
});

test('cursorUrl: the known hosts as https://host/owner/repo, others as given without user or password', () => {
  expect(
    [
      'git@github.com:acme/web.git',
      'https://user:token@github.com/acme/web.git',
      'ssh://git@gitlab.com/acme/sub/web.git',
      'git@bitbucket.org:acme/web.git',
      'git@git.sr.ht:~acme/web',
      'https://git.example.com/acme/web.git',
      'https://u:tok@git.example.com/a/b.git',
      'https://tok@git.example.com/a/b.git',
      'ssh://git@git.example.com:2222/a/b.git',
      'git@git.example.com:a/b.git',
      'example.com:a/b.git',
    ].map(cursorUrl),
  ).toEqual([
    'https://github.com/acme/web',
    'https://github.com/acme/web',
    'https://gitlab.com/acme/sub/web',
    'https://bitbucket.org/acme/web',
    'https://git.sr.ht/~acme/web',
    'https://git.example.com/acme/web.git',
    'https://git.example.com/a/b.git',
    'https://git.example.com/a/b.git',
    'ssh://git.example.com:2222/a/b.git',
    'git@git.example.com:a/b.git',
    'example.com:a/b.git',
  ]);
});

describe('CHD-622 tester: repository selection boundaries', () => {
  test('the runner disables Git prompts and closes stdin while preserving failure output', async () => {
    const dir = join(root, 'runner-stdin');
    const fake = join(dir, 'git');

    await mkdir(dir);
    await writeFile(
      fake,
      '#!/bin/sh\nprintf "%s\\n" "$GIT_TERMINAL_PROMPT"\nif read value; then exit 9; fi\nprintf "stdin closed\\n" >&2\nexit 7\n',
    );
    await chmod(fake, 0o755);
    expect(await gitRunner(fake)([], dir)).toEqual({
      status: 7,
      stdout: '0\n',
      stderr: 'stdin closed\n',
    });
  });

  test('branch pushRemote wins over pushDefault and reads its push URL', async () => {
    const dir = await pushed();

    sh(dir, 'remote', 'add', 'fork', 'https://github.com/upstream/web.git');
    sh(dir, 'remote', 'set-url', '--push', 'fork', 'git@gitlab.com:me/web.git');
    sh(dir, 'config', 'remote.pushDefault', 'origin');
    sh(dir, 'config', 'branch.main.pushRemote', 'fork');
    sh(dir, 'update-ref', 'refs/remotes/fork/main', 'HEAD');
    expect(await repository(dir)).toEqual({
      url: 'https://gitlab.com/me/web',
      branch: 'main',
      remote: 'fork',
    });
  });

  test('a configured missing push remote cannot fall back to a pushed origin', async () => {
    const dir = await pushed();

    sh(dir, 'config', 'branch.main.pushRemote', 'missing');
    expect((await refusal(dir)).code).toBe(-32602);
  });

  test('an upstream with a different branch name does not prove this branch pushed', async () => {
    const dir = await pushed();

    sh(dir, 'config', 'branch.main.remote', 'origin');
    sh(dir, 'config', 'branch.main.merge', 'refs/heads/other');
    sh(dir, 'update-ref', 'refs/remotes/origin/other', 'HEAD');
    sh(dir, 'update-ref', '-d', 'refs/remotes/origin/main');
    expect((await refusal(dir)).message).toStartWith(
      'Branch main is not pushed to origin.',
    );
  });

  test('concurrent repositories keep their cwd, branch and remote separate', async () => {
    const a = await pushed('git@github.com:acme/first.git');
    const b = await pushed('git@gitlab.com:acme/second.git');

    sh(b, 'branch', '-m', 'feature/nested');
    sh(b, 'update-ref', 'refs/remotes/origin/feature/nested', 'HEAD');
    expect(await Promise.all([repository(a), repository(b)])).toEqual([
      {
        url: 'https://github.com/acme/first',
        branch: 'main',
        remote: 'origin',
      },
      {
        url: 'https://gitlab.com/acme/second',
        branch: 'feature/nested',
        remote: 'origin',
      },
    ]);
  });
});
