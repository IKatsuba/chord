import { afterEach, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { execFileSync } from 'node:child_process';
import {
  mkdtemp,
  mkdir,
  rm,
  writeFile,
  symlink,
  readFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  discoverRepository,
  repositoryFilters,
} from '../../../src/riff/commands/git_config.ts';
import { commandEffect } from '../../../src/riff/commands/effect.ts';
import {
  prepareGit,
  gitInvocation,
  gitEnvironment,
  classifyGitVersion,
  parseGitConfig,
} from '../../../src/riff/commands/safe_git.ts';

const owned: string[] = [];

afterEach(async () => {
  for (const path of owned.splice(0)) {
    await rm(path, { recursive: true, force: true });
  }
});

async function repository() {
  const root = await mkdtemp(join(tmpdir(), 'chord-safe-git-'));

  owned.push(root);

  const home = join(root, 'home');
  const cwd = join(root, 'repo');

  await mkdir(home);
  await mkdir(cwd);

  const env = { HOME: home, XDG_CONFIG_HOME: home, GIT_CONFIG_NOSYSTEM: '1' };
  const git = (...args: string[]) =>
    execFileSync('/usr/bin/git', args, {
      cwd,
      env: gitEnvironment(env),
      encoding: 'utf8',
    });

  git('init', '-q');

  return { root, cwd, home, env, git };
}

test.each([
  ['git version 2.50.1 (Apple Git-155)\n', 'supported'],
  ['git version 2.36.0', 'supported'],
  ['git version 2.34.1', 'supported'],
  ['git version 2.25.0', 'supported'],
  ['git version 2.39.3.windows.1', 'supported'],
  ['git version 3.0.0', 'supported'],
  ['git version 2.24.4', 'too_old'],
  ['git version 1.9.5', 'too_old'],
  ['hub version 2.14', 'unknown'],
  ['git version x.y', 'unknown'],
])('fx git version: %s', (output, expected) => {
  expect(String(classifyGitVersion(output!))).toBe(expected);
});

test('safe environment keeps only config locations and fixed values', () => {
  const env = gitEnvironment({
    HOME: '/fixture-home',
    GIT_DIR: 'other',
    GIT_CONFIG_PARAMETERS: 'unsafe',
    PATH: 'unsafe',
    GIT_CONFIG_NOSYSTEM: '1',
  });

  expect(env).toEqual({
    HOME: '/fixture-home',
    GIT_CONFIG_NOSYSTEM: '1',
    PATH: '/usr/bin:/bin',
    LC_ALL: 'C',
    LANG: 'C',
    GIT_OPTIONAL_LOCKS: '0',
    GIT_TERMINAL_PROMPT: '0',
    GIT_PAGER: 'cat',
    PAGER: 'cat',
  });
});

test('trusted executable, fixed overrides and canonical git command run safely', async () => {
  const r = await repository();
  const marker = join(r.root, 'marker');

  r.git(
    '-c',
    'user.name=Fixture',
    '-c',
    'user.email=fixture@example.invalid',
    'commit',
    '--allow-empty',
    '-qm',
    'Fixture',
  );
  r.git('config', 'core.fsmonitor', `touch ${marker}`);
  r.git('config', 'core.hooksPath', r.root);
  r.git('config', 'filter.probe.clean', `touch ${marker}`);
  r.git('config', 'filter.probe.smudge', `touch ${marker}`);
  r.git('config', 'filter.probe.process', `touch ${marker}`);

  const prepared = await prepareGit(r.cwd, {
    ...r.env,
    PATH: r.root,
    GIT_DIR: r.root,
  });

  assert.equal(prepared.kind, 'ready');
  expect(prepared.ready.executable).toBe('/usr/bin/git');
  expect(prepared.ready.filterNames).toEqual(['probe']);

  for (const command of ['git status -s', 'git diff --stat', 'git log -n 2']) {
    const effect = commandEffect(command);

    assert.equal(effect.kind, 'direct');

    const invocation = gitInvocation(prepared.ready, effect.stages[0]!);

    expect(invocation.argv).toContain('core.fsmonitor=false');
    expect(invocation.argv).toContain('filter.probe.clean=');
    expect(invocation.argv).toContain('filter.probe.smudge=');
    expect(invocation.argv).toContain('filter.probe.process=');
    execFileSync(invocation.executable, invocation.argv.slice(1), {
      cwd: r.cwd,
      env: invocation.environment,
      stdio: 'pipe',
    });
  }

  expect(await readFile(marker).catch(() => null)).toBeNull();
});

test('every conditional include and config.worktree contributes filter names', async () => {
  const r = await repository();

  await writeFile(
    join(r.cwd, '.git', 'hidden'),
    '[filter "hidden.Driver"]\n clean = malicious\n',
  );
  await writeFile(
    join(r.cwd, '.git', 'config.worktree'),
    '[filter "worktree"]\n process = malicious\n',
  );
  await writeFile(
    join(r.cwd, '.git', 'config'),
    '[core]\n repositoryformatversion = 0\n[includeIf "onbranch:never-matches"]\n path = hidden\n',
  );

  const prepared = await prepareGit(r.cwd, r.env);

  assert.equal(prepared.kind, 'ready');
  expect([...prepared.ready.filterNames].sort()).toEqual([
    'hidden.Driver',
    'worktree',
  ]);
});

test('filter names containing equals cannot be blanked', async () => {
  const r = await repository();

  r.git('config', 'filter.a=b.clean', 'malicious');
  expect(await prepareGit(r.cwd, r.env)).toEqual({
    kind: 'refused',
    reason: 'unsupported_filter_name',
  });
});

test.each(['malformed', 'oversize', 'cycle', 'symlink'])(
  'unavailable config refuses: %s',
  async (kind) => {
    const r = await repository();
    const config = join(r.cwd, '.git', 'config');

    if (kind === 'malformed') {
      await writeFile(config, '[unterminated');
    }

    if (kind === 'oversize') {
      await writeFile(config, '#'.repeat(1024 * 1024 + 1));
    }

    if (kind === 'cycle') {
      await writeFile(config, '[include]\n path = config\n');
    }

    if (kind === 'symlink') {
      await rm(config);
      await symlink(join(r.home, 'absent'), config);
    }

    expect(await prepareGit(r.cwd, r.env)).toEqual({
      kind: 'refused',
      reason: 'repo_config_unavailable',
    });
  },
);

test('bare git directory cannot bypass repository discovery', async () => {
  const r = await repository();
  const bare = join(r.root, 'bare');

  r.git('init', '--bare', '-q', bare);
  expect(await prepareGit(bare, r.env)).toEqual({
    kind: 'refused',
    reason: 'repository_mismatch',
  });
});

test('non-repository is safe to invoke git, relative cwd refuses', async () => {
  const r = await repository();

  expect((await prepareGit(r.home, r.env)).kind).toBe('ready');
  expect(await prepareGit('relative', r.env)).toEqual({
    kind: 'refused',
    reason: 'repo_config_unavailable',
  });
});

test('linked worktree reads common config and its own config.worktree', async () => {
  const r = await repository();

  r.git(
    '-c',
    'user.name=Fixture',
    '-c',
    'user.email=fixture@example.invalid',
    'commit',
    '--allow-empty',
    '-qm',
    'Fixture',
  );

  const worktree = join(r.root, 'linked');

  r.git('worktree', 'add', '--detach', '-q', worktree);
  r.git('config', 'filter.common.clean', 'malicious');

  const prepared = await prepareGit(worktree, r.env);

  assert.equal(prepared.kind, 'ready');
  expect(prepared.ready.filterNames).toEqual(['common']);
});

test('total bytes and file-count limits include every conditional file', async () => {
  const r = await repository();
  const config = join(r.cwd, '.git', 'config');
  const included = join(r.cwd, '.git', 'large');

  await writeFile(included, '#'.repeat(700000));
  await writeFile(config, '#'.repeat(400000) + '\n[include]\n path = large\n');
  expect(await prepareGit(r.cwd, r.env)).toEqual({
    kind: 'refused',
    reason: 'repo_config_unavailable',
  });
  await writeFile(
    config,
    '[include]\n' +
      Array.from({ length: 65 }, () => ' path = missing\n').join(''),
  );
  expect(await prepareGit(r.cwd, r.env)).toEqual({
    kind: 'refused',
    reason: 'repo_config_unavailable',
  });
});

test('a replaced config pathname cannot change the exact bounded parser input', async () => {
  const r = await repository();
  const config = join(r.cwd, '.git', 'config');

  await writeFile(config, '[filter "bounded"]\n clean = malicious\n');

  const layout = await discoverRepository(r.cwd);
  const controller = new AbortController();
  const deadline = setTimeout(() => controller.abort(), 2000);
  let replaced = false;

  try {
    const names = await repositoryFilters(
      layout,
      r.home,
      async (path, bytes) => {
        if (path === config) {
          await rm(config);
          await symlink('/dev/zero', config);

          replaced = true;
        }

        return parseGitConfig(
          '/usr/bin/git',
          bytes,
          gitEnvironment(r.env),
          controller.signal,
        );
      },
    );

    expect(replaced).toBe(true);
    expect(names).toEqual(['bounded']);
  } finally {
    clearTimeout(deadline);
    controller.abort();
  }
});

test('malformed bounded bytes fail git parsing without reopening any config', async () => {
  const r = await repository();

  expect(
    await parseGitConfig(
      '/usr/bin/git',
      Buffer.from('[bad'),
      gitEnvironment(r.env),
    ),
  ).toBeNull();
});

test('already cancelled git preparation launches no probe', async () => {
  const r = await repository();
  const controller = new AbortController();
  const reason = new Error('cancel preparation');

  controller.abort(reason);
  await expect(prepareGit(r.cwd, r.env, controller.signal)).rejects.toBe(
    reason,
  );
});
