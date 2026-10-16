import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { join } from 'node:path';
import {
  PLATFORMS,
  type Release,
  ReleaseError,
  TEAM,
} from '../../../../scripts/dev/release/lib.ts';
import {
  type ReleaseOptions,
  selectStages,
} from '../../../../scripts/dev/release/select.ts';
import { runRelease } from '../../../../scripts/dev/release/stages.ts';
import { recordSums } from '../../../../scripts/dev/release/sums.ts';
import { type Scratch, scratch } from './scratch.ts';

// A whole run's guards and their order, on a scratch repository with a bare
// origin: npm, bun, security and xcrun faked, each logging what it was asked,
// so a test sees what ran before a run died.

const VERSION = '9.9.9';
const MAC = { platform: 'darwin', arch: 'arm64' };
const GIT_ENV = {
  GIT_AUTHOR_NAME: 'release',
  GIT_AUTHOR_EMAIL: 'release@example.com',
  GIT_COMMITTER_NAME: 'release',
  GIT_COMMITTER_EMAIL: 'release@example.com',
};
const IDENTITY = `  1) ${'A'.repeat(40)} "Developer ID Application: Chorded (${TEAM})"`;

let at: Scratch;

beforeEach(() => {
  at = scratch();

  mkdirSync(join(at.place, 'published'));
  writeFileSync(
    join(at.root, 'package.json'),
    JSON.stringify({ version: VERSION }),
  );
  writeFileSync(join(at.root, '.gitignore'), 'dist/\n');

  const origin = join(at.place, 'origin.git');

  git(at.place, 'init', '-q', '--bare', origin);
  git(at.root, 'init', '-q', '-b', 'main');
  git(at.root, 'add', '-A');
  git(at.root, 'commit', '-q', '-m', 'release');
  git(at.root, 'remote', 'add', 'origin', origin);
  git(at.root, 'push', '-q', 'origin', 'main');

  at.fake(
    'npm',
    `echo "npm $*" >>"$STATE/ran.log"
case "$1" in
whoami) echo owner ;;
view)
	spec=\${2#@chorded/}
	if [ -f "$STATE/published/\${spec%@*}" ]; then echo "\${spec##*@}"; exit 0; fi
	echo 'npm error code E404' >&2
	exit 1
	;;
publish)
	file=$(basename "$4")
	name=\${file#chorded-}
	touch "$STATE/published/\${name%-*.tgz}"
	;;
esac
`,
  );
  at.fake('bun', 'echo "bun $*" >>"$STATE/ran.log"\n');
  at.fake(
    'security',
    'echo "security $*" >>"$STATE/ran.log"\necho "$IDENTITIES"\n',
  );
  at.fake(
    'xcrun',
    'echo "xcrun $*" >>"$STATE/ran.log"\n[ -z "$NO_NOTARY" ] || { echo "No Keychain password item found" >&2; exit 1; }\n',
  );
});

afterEach(() => {
  rmSync(at.place, { recursive: true, force: true });
});

function git(cwd: string, ...args: string[]): void {
  const { status, stderr } = spawnSync('git', args, {
    cwd,
    env: { ...process.env, ...GIT_ENV },
  });

  expect(String(stderr)).toBe('');
  expect(status).toBe(0);
}

function context(env: Record<string, string> = {}): Release {
  return {
    ...at.release,
    env: {
      ...at.release.env,
      ...GIT_ENV,
      STATE: at.place,
      IDENTITIES: IDENTITY,
      ...env,
    },
  };
}

/** Runs the release `options` select, on `machine`. */
async function released(
  options: ReleaseOptions,
  env: Record<string, string> = {},
  machine = MAC,
): Promise<void> {
  await runRelease(context(env), selectStages(options), options, machine);
}

async function died(run: Promise<void>): Promise<string> {
  try {
    await run;
  } catch (error) {
    expect(error).toBeInstanceOf(ReleaseError);

    return (error as ReleaseError).message;
  }

  throw new Error('the release did not die');
}

/** What the faked commands were asked, in order, each as `tool args`. */
function ran(): string[] {
  const log = join(at.place, 'ran.log');

  return existsSync(log)
    ? readFileSync(log, 'utf8').split('\n').filter(Boolean)
    : [];
}

test('signing anywhere but an arm64 Mac is refused before anything else', async () => {
  for (const options of [
    {},
    { only: ['sign' as const] },
    { only: ['notarise' as const] },
  ]) {
    expect(
      await died(released(options, {}, { platform: 'linux', arch: 'x64' })),
    ).toBe(
      'natives, sign and notarise run only on an arm64 Mac; this is linux-x64',
    );
  }

  expect(
    await died(released({}, {}, { platform: 'darwin', arch: 'x64' })),
  ).toEndWith('this is darwin-x64');
  expect(ran()).toStrictEqual([]);
});

test('a run without signing or notarisation runs anywhere', async () => {
  await released({ only: ['install'] }, {}, { platform: 'linux', arch: 'x64' });

  expect(ran().at(-1)).toBe('bun install --frozen-lockfile');
});

test('preflight runs on every run, whatever is left out', async () => {
  writeFileSync(join(at.root, 'stray'), '');

  expect(await died(released({ only: ['install'] }))).toBe(
    'the tree is not clean:\n?? stray',
  );
  expect(ran()).toStrictEqual([]);
});

test('the identity is found before anything builds', async () => {
  expect(
    await died(released({ skip: ['notarise'] }, { IDENTITIES: '' })),
  ).toStartWith('expected one Developer ID Application identity');
  expect(ran().some((line) => line.startsWith('bun '))).toBeFalse();
});

test("Apple's credentials are checked before anything builds", async () => {
  expect(
    await died(released({ only: ['notarise'] }, { NO_NOTARY: 'yes' })),
  ).toBe(
    'xcrun notarytool history --keychain-profile roost-notary failed: No Keychain password item found',
  );
  expect(ran().some((line) => line.startsWith('bun '))).toBeFalse();
});

test('the credentials and the identity are asked only for the stages that need them', async () => {
  await released({ to: 'check' }, { NO_NOTARY: 'yes', IDENTITIES: '' });

  expect(ran().filter((line) => !line.startsWith('npm '))).toStrictEqual([
    'bun install --frozen-lockfile',
    'bun run check',
  ]);
});

test('a dry run that did not pack says what it ran, and publishes nothing', async () => {
  await released({ dryRun: true, only: ['install', 'check'] });

  expect(at.out.at(-1)).toBe(
    `dry run: @chorded/chord ${VERSION}, ran install, check; not published`,
  );
  expect(ran().some((line) => line.startsWith('npm publish'))).toBeFalse();
});

test('a run without publish prints no version', async () => {
  await released({ only: ['install'] });

  expect(at.out).toStrictEqual([]);
});

/** Tarballs a stopped run left, their sums recorded. */
function packed(): void {
  const tgz = join(at.root, 'dist', 'release', 'tgz');
  const files = ['chord', ...PLATFORMS].map(
    (name) => `chorded-${name}-${VERSION}.tgz`,
  );

  mkdirSync(tgz, { recursive: true });

  for (const file of files) {
    writeFileSync(join(tgz, file), file);
  }

  recordSums(tgz, files);
}

test('a stopped publish resumes without building, and prints the version last', async () => {
  packed();
  writeFileSync(join(at.place, 'published', 'chord-darwin-arm64'), '');

  await released({});

  expect(at.out[0]).toBe(
    `resuming ${VERSION}: a platform package is published, @chorded/chord is not`,
  );
  expect(at.out.at(-1)).toBe(VERSION);
  expect(ran().some((line) => /^(bun|security|xcrun) /.test(line))).toBe(false);
});

test('a stopped publish found by a run without publish stops it', async () => {
  writeFileSync(join(at.place, 'published', 'chord-darwin-arm64'), '');

  expect(await died(released({ to: 'pack' }))).toBe(
    `a run without publish does not resume a stopped publish: @chorded/chord-darwin-arm64@${VERSION} is published; include publish`,
  );
});

test('--package publishes the one package, and prints no version while others are missing', async () => {
  packed();

  await released({ only: ['publish'], package: 'chord-linux-x64' });

  expect(existsSync(join(at.place, 'published', 'chord-linux-x64'))).toBe(true);
  expect(existsSync(join(at.place, 'published', 'chord'))).toBeFalse();
  expect(at.out).not.toContain(VERSION);
  expect(at.err.at(-1)).toStartWith('not tagged: ');
});

describe('tester: release orchestration boundaries', () => {
  test('natives alone refuses an unsupported host before preflight', async () => {
    expect(
      await died(
        released(
          { only: ['natives'] },
          {},
          { platform: 'linux', arch: 'arm64' },
        ),
      ),
    ).toBe(
      'natives, sign and notarise run only on an arm64 Mac; this is linux-arm64',
    );
    expect(ran()).toEqual([]);
  });

  test('preflight guards check, compile, pack and publish selected alone', async () => {
    writeFileSync(join(at.root, 'untracked-fixture'), '');

    for (const stage of ['check', 'compile', 'pack', 'publish'] as const) {
      expect(await died(released({ only: [stage] }))).toBe(
        'the tree is not clean:\n?? untracked-fixture',
      );
    }

    expect(ran()).toEqual([]);
  });

  test('a failed stage stops later stages and suppresses the dry-run summary', async () => {
    at.fake(
      'bun',
      `echo "bun $*" >>"$STATE/ran.log"
if [ "$1 $2" = 'run check' ]; then exit 2; fi
`,
    );

    expect(
      await died(
        released({ dryRun: true, only: ['install', 'check', 'compile'] }),
      ),
    ).toBe('bun run check failed');
    expect(ran().filter((line) => line.startsWith('bun '))).toStrictEqual([
      'bun install --frozen-lockfile',
      'bun run check',
    ]);
    expect(at.out).toEqual([]);
  });

  test('credential failure retains stdout and stderr before any stage runs', async () => {
    at.fake(
      'xcrun',
      "echo 'fixture credential output'\necho 'fixture credential error' >&2\nexit 2\n",
    );

    expect(await died(released({ only: ['install', 'notarise'] }))).toBe(
      'xcrun notarytool history --keychain-profile roost-notary failed: fixture credential output\nfixture credential error',
    );
    expect(ran().some((line) => line.startsWith('bun '))).toBeFalse();
    expect(at.out).toEqual([]);
  });

  test('a failed tag never prints the final version or pushes', async () => {
    packed();
    at.fake(
      'git',
      `echo "git $*" >>"$STATE/ran.log"
case "$1" in
symbolic-ref) echo main ;;
rev-parse) echo fixture-commit ;;
tag) if [ "$2" = '-a' ]; then echo 'fixture tag denied' >&2; exit 2; fi ;;
esac
`,
    );

    expect(await died(released({ only: ['publish'] }))).toBe(
      `git tag -a v${VERSION} failed: fixture tag denied`,
    );
    expect(existsSync(join(at.place, 'published', 'chord'))).toBeTrue();
    expect(at.out).not.toContain(VERSION);
    expect(ran().some((line) => line.startsWith('git push'))).toBeFalse();
  });
});
