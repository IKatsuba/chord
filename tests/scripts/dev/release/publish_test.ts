import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  type Package,
  PLATFORMS,
  type Release,
  ReleaseError,
} from '../../../../scripts/dev/release/lib.ts';
import { authenticate } from '../../../../scripts/dev/release/authenticate.ts';
import { preflight } from '../../../../scripts/dev/release/preflight.ts';
import { publish } from '../../../../scripts/dev/release/publish.ts';
import { recordSums } from '../../../../scripts/dev/release/sums.ts';
import { executable } from './scratch.ts';

// The release's publishing, on the resume path, which publishes from the
// packages a stopped run left without building again: npm faked on PATH, the
// repository a scratch one in a clean tree with a bare origin of its own,
// and no waiting.

const VERSION = '9.9.9';
const TAG = `v${VERSION}`;

// npm's registry as files under the state directory: published/NAME is a
// package npm took, late/NAME the views it still misses after that, as one in
// validation does, and fail/NAME a view that fails other than with a 404.
const NPM = `#!/bin/bash
state="$RELEASE_STATE"
printf '%s\\n' "$*" >>"$state/npm.log"
case "$1" in
whoami)
	if [ -f "$state/logged-out" ]; then
		echo 'npm error code ENEEDAUTH' >&2
		exit 1
	fi
	echo owner
	;;
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

const NODE = '#!/bin/bash\nexec /bin/bash "$@"\n';

const GIT_ENV = {
  GIT_AUTHOR_NAME: 'release',
  GIT_AUTHOR_EMAIL: 'release@example.com',
  GIT_COMMITTER_NAME: 'release',
  GIT_COMMITTER_EMAIL: 'release@example.com',
};

let place: string;
let repo: string;
let origin: string;
let state: string;
let bin: string;
let out: string[];
let err: string[];
let sleeps: number[];
let tty: boolean;

beforeEach(() => {
  place = mkdtempSync(join(tmpdir(), 'chord-release-'));
  repo = join(place, 'repo');
  origin = join(place, 'origin.git');
  state = join(place, 'state');
  bin = join(place, 'bin');
  out = [];
  err = [];
  sleeps = [];
  tty = true;

  for (const dir of ['published', 'late', 'fail']) {
    mkdirSync(join(state, dir), { recursive: true });
  }

  mkdirSync(bin);
  // A file of its own, not a link: a test writes a different npm over it.
  writeFileSync(join(bin, 'npm'), NPM);
  chmodSync(join(bin, 'npm'), 0o755);
  // npm runs as `node <npm>`; this node runs the fake npm with bash.
  executable(join(bin, 'node'), NODE);

  mkdirSync(repo);
  writeFileSync(
    join(repo, 'package.json'),
    JSON.stringify({ name: '@chorded/chord', version: VERSION }),
  );
  writeFileSync(join(repo, '.gitignore'), 'dist/\n');

  const tgz = join(repo, 'dist', 'release', 'tgz');
  const files = ['chord', ...PLATFORMS].map(
    (name) => `chorded-${name}-${VERSION}.tgz`,
  );

  mkdirSync(tgz, { recursive: true });

  for (const file of files) {
    writeFileSync(join(tgz, file), file);
  }

  recordSums(tgz, files);

  git(place, 'init', '-q', '--bare', '-b', 'main', origin);
  git(repo, 'init', '-q', '-b', 'main');
  git(repo, 'add', '-A');
  git(repo, 'commit', '-q', '-m', 'release');
  git(repo, 'remote', 'add', 'origin', origin);
  git(repo, 'push', '-q', 'origin', 'main');
  // A run stopped after its first publish, so the rerun resumes.
  publishedAlready('chord-darwin-arm64');
});

afterEach(() => {
  rmSync(place, { recursive: true, force: true });
});

function git(cwd: string, ...args: string[]): string {
  const { status, stdout, stderr } = spawnSync('git', args, {
    cwd,
    env: { ...process.env, ...GIT_ENV },
  });

  expect(String(stderr)).toBe('');
  expect(status).toBe(0);

  return String(stdout).trim();
}

function publishedAlready(name: string): void {
  writeFileSync(join(state, 'published', name), '');
}

function context(): Release {
  return {
    root: repo,
    env: {
      ...process.env,
      ...GIT_ENV,
      PATH: `${bin}:${process.env.PATH ?? ''}`,
      RELEASE_STATE: state,
    },
    sleep: (ms) => {
      sleeps.push(ms);

      return Promise.resolve();
    },
    out: (line) => out.push(line),
    err: (line) => err.push(line),
    tty,
  };
}

/** A release that publishes, as preflight then publish run it. */
async function release(only?: Package): Promise<boolean> {
  const found = preflight(context(), { dryRun: false, publish: true });

  authenticate(context());

  return await publish(context(), { version: found.version, only });
}

/** The message a run died with. */
async function died(run: () => unknown): Promise<string> {
  try {
    await run();
  } catch (error) {
    expect(error).toBeInstanceOf(ReleaseError);

    return (error as ReleaseError).message;
  }

  throw new Error('the run did not die');
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

function tagged(where: string): string {
  return git(where, 'tag', '--list', TAG);
}

const PUBLISH = 'publish --access public ';

describe('a resumed release', () => {
  test('publishes every platform package, then the main one last, and tags', async () => {
    expect(await release()).toBeTrue();
    expect(out).toContain(
      `already published: @chorded/chord-darwin-arm64@${VERSION}`,
    );
    expect(
      [...PLATFORMS, 'chord'].every((name) => isPublished(name)),
    ).toBeTrue();

    const npm = lines('npm.log').filter((line) => line.startsWith(PUBLISH));

    expect(npm.at(-1)).toContain(`chorded-chord-${VERSION}.tgz`);
    expect(npm).toHaveLength(4);
    expect(sleeps).toStrictEqual([]);
    expect(tagged(repo)).toBe(TAG);
    expect(tagged(origin)).toBe(TAG);
    expect(
      git(repo, 'tag', '--list', TAG, '--format=%(contents:subject)'),
    ).toBe(`chord ${TAG}`);
    expect(git(repo, 'cat-file', '-t', TAG)).toBe('tag');
  });

  test('the main package waits for a platform package npm answers for late', async () => {
    writeFileSync(join(state, 'late', 'chord-linux-x64'), '3');

    expect(await release()).toBeTrue();
    expect(err).toContain(
      `release: waiting for @chorded/chord-linux-x64@${VERSION} to answer npm view (3/60)`,
    );
    expect(err.join('\n')).not.toContain('(4/60)');
    expect(sleeps).toStrictEqual([15_000, 15_000, 15_000]);
    expect(isPublished('chord')).toBeTrue();

    const npm = lines('npm.log');
    const answered = npm.lastIndexOf(
      `view @chorded/chord-linux-x64@${VERSION} version`,
    );

    expect(
      npm.findIndex((line) => line.includes(`chorded-chord-${VERSION}`)),
    ).toBeGreaterThan(answered);
  });

  test('a platform package npm never answers for stops the release before the main one', async () => {
    writeFileSync(join(state, 'late', 'chord-linux-x64'), '1000');

    expect(await died(release)).toStartWith(
      `@chorded/chord-linux-x64@${VERSION} did not answer npm view in 15 minutes; @chorded/chord was not published. Rerun \`bun dev release\` once`,
    );
    expect(err.at(-1)).toContain('(60/60)');
    // No sleep after the last miss.
    expect(sleeps).toHaveLength(59);
    expect(isPublished('chord')).toBeFalse();
    expect(tagged(repo)).toBe('');
  });

  test('a rerun after a timeout resumes and publishes the main package', async () => {
    writeFileSync(join(state, 'late', 'chord-linux-x64'), '1000');
    await died(release);
    writeFileSync(join(state, 'late', 'chord-linux-x64'), '0');

    out = [];

    expect(preflight(context(), { dryRun: false, publish: true }).mode).toBe(
      'resume',
    );
    expect(await release()).toBeTrue();

    for (const name of PLATFORMS) {
      expect(out).toContain(`already published: @chorded/${name}@${VERSION}`);
    }

    expect(isPublished('chord')).toBeTrue();
  });

  test('an npm failure other than a 404 while waiting stops at once', async () => {
    writeFileSync(join(state, 'fail', 'chord-darwin-x64'), '');

    expect(await died(release)).toBe(
      `npm view @chorded/chord-darwin-x64@${VERSION} failed: npm error code E500`,
    );
    expect(sleeps).toStrictEqual([]);
    expect(isPublished('chord')).toBeFalse();
  });

  test('the main package npm never answers for is not tagged, and says how to tag it', async () => {
    writeFileSync(join(state, 'late', 'chord'), '1000');

    expect(await died(release)).toBe(
      `@chorded/chord@${VERSION} did not answer npm view in 15 minutes; ${TAG} was not tagged. Once \`npm view @chorded/chord@${VERSION} version\` answers, tag it with: git tag -a ${TAG} -m "chord ${TAG}" && git push origin ${TAG}`,
    );
    expect(isPublished('chord')).toBeTrue();
    expect(tagged(repo)).toBe('');
  });
});

describe('before the first publish', () => {
  test('says npm will ask, once', async () => {
    await release();

    const notices = out.filter((line) => line.startsWith('npm will ask'));

    expect(notices).toStrictEqual([
      'npm will ask to authorise each publish: press Enter when it asks, then approve in the browser',
    ]);
    expect(out.indexOf(notices[0]!)).toBeGreaterThan(
      out.indexOf(`already published: @chorded/chord-darwin-arm64@${VERSION}`),
    );
  });

  test('stops without a terminal, and publishes nothing', async () => {
    tty = false;

    expect(await died(release)).toBe(
      'npm publish asks in the terminal to authorise each publish; run this with stdin and stdout on a terminal',
    );
    expect(lines('npm.log').some((line) => line.startsWith(PUBLISH))).toBe(
      false,
    );
  });

  test('a tarball changed since it was packed is refused, with both sums', async () => {
    const tarball = join(
      repo,
      'dist',
      'release',
      'tgz',
      `chorded-chord-darwin-x64-${VERSION}.tgz`,
    );

    writeFileSync(tarball, 'other bytes');

    const message = await died(release);

    expect(message).toMatch(
      new RegExp(
        `^${tarball} has sha256 [0-9a-f]{64}; SHA256SUMS recorded [0-9a-f]{64}$`,
      ),
    );
    expect(isPublished('chord-darwin-x64')).toBeFalse();
  });

  test('a tarball SHA256SUMS has no sum for is refused', async () => {
    const tgz = join(repo, 'dist', 'release', 'tgz');

    recordSums(tgz, [`chorded-chord-${VERSION}.tgz`]);

    expect(await died(release)).toBe(
      `${join(tgz, 'SHA256SUMS')} has no sum for ${join(tgz, `chorded-chord-darwin-x64-${VERSION}.tgz`)}`,
    );
  });

  test('a tarball that is not there is refused', async () => {
    const tarball = join(
      repo,
      'dist',
      'release',
      'tgz',
      `chorded-chord-darwin-x64-${VERSION}.tgz`,
    );

    rmSync(tarball);

    expect(await died(release)).toBe(
      `no ${tarball} to publish; nothing of this run is left to resume from`,
    );
  });
});

describe('--package', () => {
  test('publishes only the platform package named, and leaves the tag while one is missing', async () => {
    expect(await release('chord-linux-arm64')).toBeFalse();
    expect(isPublished('chord-linux-arm64')).toBeTrue();
    expect(isPublished('chord-darwin-x64')).toBeFalse();
    expect(isPublished('chord')).toBeFalse();
    expect(err).toStrictEqual([
      `not tagged: @chorded/chord-darwin-x64@${VERSION} does not answer npm view yet; ${TAG} is tagged by the run that publishes the last of the five`,
    ]);
    expect(tagged(repo)).toBe('');
  });

  test('tags once the package published is the last of the five', async () => {
    for (const name of ['chord-darwin-x64', 'chord-linux-arm64', 'chord']) {
      publishedAlready(name);
    }

    // The main package on npm stops preflight, so publish runs alone.
    expect(
      await publish(context(), { version: VERSION, only: 'chord-linux-x64' }),
    ).toBeTrue();
    expect(tagged(origin)).toBe(TAG);
  });

  test('chord waits for every platform package before it publishes', async () => {
    expect(await died(() => release('chord'))).toStartWith(
      `@chorded/chord-darwin-x64@${VERSION} did not answer npm view in 15 minutes; @chorded/chord was not published.`,
    );
    expect(isPublished('chord')).toBeFalse();
  });

  test('chord, once the platform packages answer, publishes and tags', async () => {
    for (const name of PLATFORMS) {
      publishedAlready(name);
    }

    expect(await release('chord')).toBeTrue();
    expect(isPublished('chord')).toBeTrue();
    expect(tagged(origin)).toBe(TAG);
  });
});

describe('preflight', () => {
  const fresh = { dryRun: false, publish: true };

  test('a fresh version', () => {
    rmSync(join(state, 'published', 'chord-darwin-arm64'));

    expect(preflight(context(), fresh)).toStrictEqual({
      mode: 'fresh',
      version: VERSION,
    });
  });

  test('refuses a tree that is not clean, untracked files included', async () => {
    writeFileSync(join(repo, 'stray'), '');

    expect(await died(() => preflight(context(), fresh))).toBe(
      'the tree is not clean:\n?? stray',
    );
  });

  test('refuses a package.json without a version', async () => {
    writeFileSync(join(repo, 'package.json'), '{}');
    git(repo, 'commit', '-q', '-am', 'no version');

    expect(await died(() => preflight(context(), fresh))).toBe(
      'package.json has no version',
    );
  });

  test('refuses a version the main package has', async () => {
    publishedAlready('chord');

    expect(await died(() => preflight(context(), fresh))).toBe(
      `@chorded/chord@${VERSION} is on npm already`,
    );
  });

  test('a dry run does not resume', async () => {
    expect(
      await died(() => preflight(context(), { dryRun: true, publish: false })),
    ).toBe(
      `--dry-run does not resume a stopped publish: @chorded/chord-darwin-arm64@${VERSION} is published`,
    );
  });

  test('a run without publish does not resume, and says to include it', async () => {
    expect(
      await died(() => preflight(context(), { dryRun: false, publish: false })),
    ).toBe(
      `a run without publish does not resume a stopped publish: @chorded/chord-darwin-arm64@${VERSION} is published; include publish`,
    );
  });

  test('eligibility does not attempt authentication', () => {
    writeFileSync(join(state, 'logged-out'), '');

    expect(preflight(context(), fresh).mode).toBe('resume');
    expect(lines('npm.log').includes('whoami')).toBe(false);
  });

  test('a run without publish asks nothing of main or the tags', () => {
    rmSync(join(state, 'published', 'chord-darwin-arm64'));
    git(repo, 'checkout', '-q', '-b', 'topic');
    git(repo, 'tag', TAG);

    expect(preflight(context(), { dryRun: true, publish: false }).mode).toBe(
      'fresh',
    );
  });

  test('a run that publishes refuses a branch other than main', async () => {
    git(repo, 'checkout', '-q', '-b', 'topic');

    expect(await died(() => preflight(context(), fresh))).toBe(
      'a release that publishes runs from main; HEAD is topic',
    );
  });

  test('a run that publishes refuses main ahead of origin/main', async () => {
    git(repo, 'commit', '-q', '--allow-empty', '-m', 'ahead');

    const main = git(repo, 'rev-parse', 'main');
    const behind = git(repo, 'rev-parse', 'origin/main');

    expect(await died(() => preflight(context(), fresh))).toBe(
      `main is not origin/main: main is ${main}, origin/main is ${behind}`,
    );
  });

  test('a run that publishes fetches origin first', async () => {
    const other = join(place, 'other');

    git(place, 'clone', '-q', origin, other);
    git(other, 'commit', '-q', '--allow-empty', '-m', 'elsewhere');
    git(other, 'push', '-q', 'origin', 'main');

    expect(await died(() => preflight(context(), fresh))).toStartWith(
      'main is not origin/main:',
    );
  });

  test('a run that publishes refuses a version tagged here', async () => {
    git(repo, 'tag', TAG);

    expect(await died(() => preflight(context(), fresh))).toBe(
      `${TAG} is a tag already`,
    );
  });

  test('a run that publishes refuses a version tagged on origin', async () => {
    const other = join(place, 'other');

    // On a commit no branch reaches, so fetching main does not bring it.
    git(place, 'clone', '-q', origin, other);
    git(other, 'commit', '-q', '--allow-empty', '-m', 'elsewhere');
    git(other, 'tag', TAG);
    git(other, 'push', '-q', 'origin', TAG);

    expect(await died(() => preflight(context(), fresh))).toStartWith(
      `${TAG} is a tag on origin already: `,
    );
  });
});

describe('tester: publish guard boundaries', () => {
  test('a fresh run publishes all five in order and announces npm once', async () => {
    rmSync(join(state, 'published', PLATFORMS[0]));

    expect(await release()).toBeTrue();
    expect(
      lines('npm.log')
        .filter((line) => line.startsWith(PUBLISH))
        .map((line) => line.slice(line.lastIndexOf('/') + 1)),
    ).toStrictEqual(
      [...PLATFORMS, 'chord'].map((name) => `chorded-${name}-${VERSION}.tgz`),
    );
    expect(out.filter((line) => line.startsWith('npm will ask'))).toHaveLength(
      1,
    );
    expect(tagged(origin)).toBe(TAG);
  });

  test('the tag stays absent while the main package answers late', async () => {
    for (const name of PLATFORMS) {
      publishedAlready(name);
    }

    writeFileSync(join(state, 'late', 'chord'), '2');

    const ctx = context();

    expect(
      await publish(
        {
          ...ctx,
          sleep: (ms) => {
            expect(isPublished('chord')).toBeTrue();
            expect(tagged(repo)).toBe('');
            expect(tagged(origin)).toBe('');

            return ctx.sleep(ms);
          },
        },
        { version: VERSION, only: 'chord' },
      ),
    ).toBeTrue();
    expect(sleeps).toStrictEqual([15_000, 15_000]);
    expect(tagged(origin)).toBe(TAG);
  });

  test('a missing sums file stops before any publish or tag', async () => {
    rmSync(join(repo, 'dist', 'release', 'tgz', 'SHA256SUMS'));

    expect(await died(release)).toContain('has no sum for');
    expect(lines('npm.log').filter((line) => line.startsWith(PUBLISH))).toEqual(
      [],
    );
    expect(tagged(repo)).toBe('');
    expect(tagged(origin)).toBe('');
  });

  test('a resumed package needs no local tarball or checksum', async () => {
    rmSync(
      join(
        repo,
        'dist',
        'release',
        'tgz',
        `chorded-${PLATFORMS[0]}-${VERSION}.tgz`,
      ),
    );

    tty = false;

    expect(await release(PLATFORMS[0])).toBeFalse();
    expect(lines('npm.log').filter((line) => line.startsWith(PUBLISH))).toEqual(
      [],
    );
    expect(sleeps).toEqual([]);
    expect(out.filter((line) => line.startsWith('npm will ask'))).toEqual([]);
    expect(tagged(repo)).toBe('');
  });

  test('a selected platform that answers late does not wait or tag', async () => {
    for (const name of [...PLATFORMS, 'chord']) {
      if (name !== 'chord-linux-x64') {
        publishedAlready(name);
      }
    }

    writeFileSync(join(state, 'late', 'chord-linux-x64'), '2');

    expect(
      await publish(context(), { version: VERSION, only: 'chord-linux-x64' }),
    ).toBeFalse();
    expect(isPublished('chord-linux-x64')).toBeTrue();
    expect(sleeps).toEqual([]);
    expect(tagged(repo)).toBe('');
    expect(tagged(origin)).toBe('');
  });

  test('a successful npm view with the wrong version stops with its answer', async () => {
    executable(
      join(bin, 'npm'),
      NPM.replace('echo "${spec##*@}"', 'echo "9.9.8"'),
    );

    expect(await died(release)).toBe(
      `npm view @chorded/${PLATFORMS[0]}@${VERSION} answered "9.9.8"`,
    );
    expect(lines('npm.log').filter((line) => line.startsWith(PUBLISH))).toEqual(
      [],
    );
    expect(sleeps).toEqual([]);
  });

  test('preflight command failures retain their diagnostic and stop before publish', async () => {
    const cases = [
      ['status', 'git status failed: fixture status denied'],
      ['fetch', 'git fetch origin failed: fixture fetch denied'],
      [
        'rev-parse origin/main',
        'git rev-parse origin/main failed: fixture rev-parse origin/main denied',
      ],
      ['ls-remote', 'git ls-remote origin failed: fixture ls-remote denied'],
    ];

    for (const [command, message] of cases) {
      executable(
        join(bin, 'git'),
        `#!/bin/sh
case "$*" in
  '${command}'*) echo 'fixture ${command} denied' >&2; exit 2 ;;
  'symbolic-ref --short HEAD') echo main ;;
  'rev-parse main'|'rev-parse origin/main') echo fixture-commit ;;
esac
`,
      );

      expect(
        await died(() =>
          preflight(context(), { dryRun: false, publish: true }),
        ),
      ).toBe(message!);
      expect(
        lines('npm.log').filter((line) => line.startsWith(PUBLISH)),
      ).toEqual([]);
    }
  });

  test('tag and push failures retain their diagnostic after all five answer', async () => {
    for (const name of [...PLATFORMS, 'chord']) {
      publishedAlready(name);
    }

    for (const command of ['tag', 'push']) {
      executable(
        join(bin, 'git'),
        `#!/bin/sh
printf '%s\\n' "$*" >>"$RELEASE_STATE/git.log"
case "$1" in
  ${command}) echo 'fixture ${command} denied' >&2; exit 2 ;;
esac
`,
      );
      rmSync(join(state, 'git.log'), { force: true });

      expect(
        await died(() =>
          publish(context(), { version: VERSION, only: 'chord-linux-x64' }),
        ),
      ).toBe(
        command === 'tag'
          ? `git tag -a ${TAG} failed: fixture tag denied`
          : `git push origin ${TAG} failed: fixture push denied`,
      );
      expect(lines('git.log')).toStrictEqual(
        command === 'tag'
          ? [`tag -a ${TAG} -m chord ${TAG}`]
          : [`tag -a ${TAG} -m chord ${TAG}`, `push origin ${TAG}`],
      );
    }
  });
});
