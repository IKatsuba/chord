import { afterEach, beforeEach, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// scripts/release.sh's publishing, on the resume path, which publishes from
// the packages a stopped run left without building again: npm, sleep and
// plutil faked on PATH, the repository a copy of the scripts in a clean tree.

const VERSION = '9.9.9';
const PLATFORMS = [
  'chord-darwin-arm64',
  'chord-darwin-x64',
  'chord-linux-arm64',
  'chord-linux-x64',
];
const ROOT = join(import.meta.dir, '..', '..');

// npm's registry as files under the state directory: published/NAME is a
// package npm took, late/NAME the views it still misses after that, as one in
// validation does, and fail/NAME a view that fails other than with a 404.
const NPM = `#!/bin/bash
state="$RELEASE_STATE"
printf '%s\\n' "$*" >>"$state/npm.log"
case "$1" in
whoami) echo owner ;;
view)
	spec=\${2#@chorded/}
	name=\${spec%@*}
	if [ ! -f "$state/published/$name" ]; then
		echo 'npm error code E404' >&2
		exit 1
	fi
	if [ -f "$state/fail/$name" ]; then
		echo 'npm error code E500' >&2
		exit 1
	fi
	late=$(cat "$state/late/$name" 2>/dev/null || echo 0)
	if [ "$late" -gt 0 ]; then
		echo $((late - 1)) >"$state/late/$name"
		echo 'npm error code E404' >&2
		exit 1
	fi
	echo "\${spec##*@}"
	;;
publish)
	file=$(basename "$4")
	name=\${file#chorded-}
	touch "$state/published/\${name%-*.tgz}"
	;;
esac
`;
const SLEEP = `#!/bin/bash
printf '%s\\n' "$*" >>"$RELEASE_STATE/sleep.log"
`;
const PLUTIL = `#!/bin/bash
sed -n 's/.*"version": *"\\([^"]*\\)".*/\\1/p' "$4"
`;

let place: string;
let repo: string;
let state: string;
let bin: string;

beforeEach(() => {
  place = mkdtempSync(join(tmpdir(), 'chord-release-'));
  repo = join(place, 'repo');
  state = join(place, 'state');
  bin = join(place, 'bin');

  for (const dir of ['published', 'late', 'fail']) {
    mkdirSync(join(state, dir), { recursive: true });
  }

  mkdirSync(bin);

  for (const [name, body] of [
    ['npm', NPM],
    ['sleep', SLEEP],
    ['plutil', PLUTIL],
  ] as const) {
    writeFileSync(join(bin, name), body);
    chmodSync(join(bin, name), 0o755);
  }

  mkdirSync(join(repo, 'scripts'), { recursive: true });
  cpSync(
    join(ROOT, 'scripts', 'release.sh'),
    join(repo, 'scripts', 'release.sh'),
  );
  cpSync(join(ROOT, 'scripts', 'release'), join(repo, 'scripts', 'release'), {
    recursive: true,
  });
  writeFileSync(
    join(repo, 'package.json'),
    JSON.stringify({ name: '@chorded/chord', version: VERSION }),
  );
  writeFileSync(join(repo, '.gitignore'), 'dist/\n');

  const tgz = join(repo, 'dist', 'release', 'tgz');

  mkdirSync(tgz, { recursive: true });

  for (const name of [...PLATFORMS, 'chord']) {
    writeFileSync(join(tgz, `chorded-${name}-${VERSION}.tgz`), '');
  }

  git('init', '-q');
  git('add', '-A');
  git('commit', '-q', '-m', 'release');
  // A run stopped after its first publish, so the rerun resumes.
  publishedAlready('chord-darwin-arm64');
});

afterEach(() => {
  rmSync(place, { recursive: true, force: true });
});

function git(...args: string[]): void {
  const { status, stderr } = spawnSync('git', args, {
    cwd: repo,
    env: {
      ...process.env,
      GIT_AUTHOR_NAME: 'release',
      GIT_AUTHOR_EMAIL: 'release@example.com',
      GIT_COMMITTER_NAME: 'release',
      GIT_COMMITTER_EMAIL: 'release@example.com',
    },
  });

  expect(String(stderr)).toBe('');
  expect(status).toBe(0);
}

function publishedAlready(name: string): void {
  writeFileSync(join(state, 'published', name), '');
}

function release(): { status: number | null; stdout: string; stderr: string } {
  const { status, stdout, stderr } = spawnSync(
    'bash',
    [join(repo, 'scripts', 'release.sh')],
    {
      env: {
        ...process.env,
        PATH: `${bin}:${process.env.PATH ?? ''}`,
        RELEASE_STATE: state,
      },
    },
  );

  return { status, stdout: String(stdout), stderr: String(stderr) };
}

function isPublished(name: string): boolean {
  return existsSync(join(state, 'published', name));
}

function lines(file: string): string[] {
  const path = join(state, file);

  return existsSync(path)
    ? readFileSync(path, 'utf8').split('\n').filter(Boolean)
    : [];
}

const PUBLISH = 'publish --access public ';

test('a resumed release publishes every platform package, then the main one last', () => {
  const { status, stdout } = release();

  expect(status).toBe(0);
  expect(stdout.trim().split('\n').at(-1)).toBe(VERSION);
  expect(stdout).toContain(
    `already published: @chorded/chord-darwin-arm64@${VERSION}`,
  );
  expect([...PLATFORMS, 'chord'].every((name) => isPublished(name))).toBeTrue();

  const npm = lines('npm.log');

  expect(npm.at(-1)).toContain(`chorded-chord-${VERSION}.tgz`);
  expect(npm.filter((line) => line.startsWith(PUBLISH))).toHaveLength(4);
  expect(lines('sleep.log')).toStrictEqual([]);
});

test('the main package waits for a platform package npm answers for late', () => {
  writeFileSync(join(state, 'late', 'chord-linux-x64'), '3');

  const { status, stderr } = release();

  expect(status).toBe(0);
  expect(stderr).toContain(
    `release: waiting for @chorded/chord-linux-x64@${VERSION} to answer npm view (3/60)`,
  );
  expect(stderr).not.toContain('(4/60)');
  expect(lines('sleep.log')).toStrictEqual(['15', '15', '15']);
  expect(isPublished('chord')).toBeTrue();

  const npm = lines('npm.log');
  const answered = npm.lastIndexOf(
    `view @chorded/chord-linux-x64@${VERSION} version`,
  );

  expect(
    npm.findIndex((line) => line.includes(`chorded-chord-${VERSION}`)),
  ).toBeGreaterThan(answered);
});

test('a platform package npm never answers for stops the release before the main one', () => {
  writeFileSync(join(state, 'late', 'chord-linux-x64'), '1000');

  const { status, stdout, stderr } = release();

  expect(status).toBe(1);
  expect(stderr).toContain(
    `release: @chorded/chord-linux-x64@${VERSION} did not answer npm view in 15 minutes; @chorded/chord was not published.`,
  );
  expect(stderr).toContain('(60/60)');
  // No sleep after the last miss.
  expect(lines('sleep.log')).toHaveLength(59);
  expect(isPublished('chord')).toBeFalse();
  expect(stdout.trim().split('\n').at(-1)).not.toBe(VERSION);
});

test('a rerun after a timeout resumes and publishes the main package', () => {
  writeFileSync(join(state, 'late', 'chord-linux-x64'), '1000');
  expect(release().status).toBe(1);
  writeFileSync(join(state, 'late', 'chord-linux-x64'), '0');

  const { status, stdout } = release();

  expect(status).toBe(0);
  expect(stdout).toContain(`resuming ${VERSION}`);

  for (const name of PLATFORMS) {
    expect(stdout).toContain(`already published: @chorded/${name}@${VERSION}`);
  }

  expect(isPublished('chord')).toBeTrue();
});

test('an npm failure other than a 404 while waiting stops at once', () => {
  writeFileSync(join(state, 'fail', 'chord-darwin-x64'), '');

  const { status, stderr } = release();

  expect(status).toBe(1);
  expect(stderr).toContain(
    `release: npm view @chorded/chord-darwin-x64@${VERSION} failed: npm error code E500`,
  );
  expect(lines('sleep.log')).toStrictEqual([]);
  expect(isPublished('chord')).toBeFalse();
});
