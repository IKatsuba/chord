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
import { KINDS } from '../../../../scripts/dev/release/build.ts';
import { recordSums } from '../../../../scripts/dev/release/sums.ts';
import { executable, type Scratch, scratch } from './scratch.ts';

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
    'bun quality',
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

describe('tester: CHD-412 release transaction boundaries', () => {
  function output(cwd: string, ...args: string[]): string {
    const child = spawnSync('git', args, { cwd, encoding: 'utf8' });

    expect(child.status).toBe(0);

    return child.stdout.trim();
  }

  function versioned(wanted: string, options: ReleaseOptions) {
    return runRelease(context(), selectStages(options), options, MAC, wanted);
  }

  test('a successful local run drops its version commit without a dry-run flag', async () => {
    const head = output(at.root, 'rev-parse', 'HEAD');

    at.fake('file', `echo "$1: ${Object.values(KINDS).join(' ')}"\n`);
    await versioned('fix', { only: ['compile'] });

    expect(output(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(output(join(at.place, 'origin.git'), 'rev-parse', 'main')).toBe(
      head,
    );
    expect(output(at.root, 'status', '--porcelain')).toBe('');
    expect(at.out).toEqual([]);
  });

  test('dropping a failed local version preserves unrelated tracked stage edits', async () => {
    const head = output(at.root, 'rev-parse', 'HEAD');

    at.fake(
      'bun',
      `echo "bun $*" >>"$STATE/ran.log"
if [ "$2" = 'check' ]; then echo 'stage-output/' >> .gitignore; exit 2; fi
`,
    );

    expect(await died(versioned('patch', { only: ['check', 'compile'] }))).toBe(
      'bun scripts/dev.ts check failed',
    );
    expect(output(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(readFileSync(join(at.root, '.gitignore'), 'utf8')).toBe(
      'dist/\nstage-output/\n',
    );
    expect(
      JSON.parse(readFileSync(join(at.root, 'package.json'), 'utf8')),
    ).toEqual({
      version: VERSION,
    });
    expect(ran().filter((line) => line.startsWith('bun '))).toEqual([
      'bun scripts/dev.ts check',
    ]);
  });

  test('an equal exact version can publish packed fixtures without a new commit', async () => {
    const head = output(at.root, 'rev-parse', 'HEAD');

    packed();
    await versioned(VERSION, { only: ['publish'] });

    expect(output(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(output(join(at.place, 'origin.git'), 'rev-parse', 'main')).toBe(
      head,
    );
    expect(at.out.at(-1)).toBe(VERSION);
    expect(ran().some((line) => line.startsWith('bun '))).toBeFalse();
  });
});

describe('tester: CHD-411 release check caller', () => {
  test('check selected alone calls the dev entry point without install', async () => {
    await released({ only: ['check'] });

    expect(ran().filter((line) => line.startsWith('bun '))).toStrictEqual([
      'bun scripts/dev.ts check',
    ]);
    expect(at.out).toEqual([]);
  });

  test('a failed install never reaches the migrated check command', async () => {
    at.fake(
      'bun',
      `echo "bun $*" >>"$STATE/ran.log"
if [ "$1" = 'install' ]; then exit 7; fi
`,
    );

    expect(await died(released({ to: 'check' }))).toBe(
      'bun install --frozen-lockfile failed',
    );
    expect(ran().filter((line) => line.startsWith('bun '))).toStrictEqual([
      'bun install --frozen-lockfile',
    ]);
    expect(at.out).toEqual([]);
  });
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
if [ "$2" = 'check' ]; then exit 2; fi
`,
    );

    expect(
      await died(
        released({ dryRun: true, only: ['install', 'check', 'compile'] }),
      ),
    ).toBe('bun scripts/dev.ts check failed');
    expect(ran().filter((line) => line.startsWith('bun '))).toStrictEqual([
      'bun install --frozen-lockfile',
      'bun scripts/dev.ts check',
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

describe('a version given', () => {
  /** Runs the release `options` select at `version`. */
  async function releasedAt(
    version: string,
    options: ReleaseOptions,
    env: Record<string, string> = {},
  ): Promise<void> {
    await runRelease(
      context(env),
      selectStages(options),
      options,
      MAC,
      version,
    );
  }

  function out(cwd: string, ...args: string[]): string {
    return String(spawnSync('git', args, { cwd }).stdout).trim();
  }

  const origin = () => join(at.place, 'origin.git');
  const version = () =>
    (
      JSON.parse(readFileSync(join(at.root, 'package.json'), 'utf8')) as {
        version: string;
      }
    ).version;

  beforeEach(() => {
    // The bun faked records the version package.json had when check ran.
    at.fake(
      'bun',
      `echo "bun $*" >>"$STATE/ran.log"
if [ "$1" = 'quality' ]; then cat package.json >"$STATE/checked.json"; fi
if [ -n "$FAIL_CHECK" ] && [ "$1" = 'quality' ]; then exit 2; fi
`,
    );
    // Every binary the compile faked is every kind it should be.
    at.fake('file', `echo "$1: ${Object.values(KINDS).join(' ')}"\n`);
  });

  const checked = () =>
    (
      JSON.parse(readFileSync(join(at.place, 'checked.json'), 'utf8')) as {
        version: string;
      }
    ).version;

  test('a dry run builds the new version, then drops its commit', async () => {
    const head = out(at.root, 'rev-parse', 'HEAD');

    await releasedAt('minor', {
      dryRun: true,
      only: ['install', 'check', 'compile'],
    });

    expect(checked()).toBe('9.10.0');
    expect(at.out.at(-1)).toBe(
      'dry run: @chorded/chord 9.10.0, ran install, check, compile; not published',
    );
    expect(out(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(version()).toBe(VERSION);
    expect(out(at.root, 'status', '--porcelain')).toBe('');
    expect(out(origin(), 'rev-parse', 'main')).toBe(head);
  });

  test('a run without publish that fails drops the commit too', async () => {
    const head = out(at.root, 'rev-parse', 'HEAD');

    expect(
      await died(
        releasedAt('9.9.10', { to: 'compile' }, { FAIL_CHECK: 'yes' }),
      ),
    ).toBe('bun quality failed');
    expect(checked()).toBe('9.9.10');
    expect(out(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(version()).toBe(VERSION);
    expect(out(origin(), 'rev-parse', 'main')).toBe(head);
  });

  test('a run that publishes commits package.json alone and pushes it before any stage', async () => {
    const head = out(at.root, 'rev-parse', 'HEAD');

    // Nothing is packed, so publish dies; the commit stays where it went.
    await died(
      releasedAt(
        'patch',
        {
          skip: ['natives', 'sign', 'selftest', 'notarise', 'pack'],
        },
        { FAIL_CHECK: 'yes' },
      ),
    );

    expect(checked()).toBe('9.9.10');
    expect(out(at.root, 'log', '-1', '--format=%s')).toBe(
      'chore: chord v9.9.10',
    );
    expect(out(at.root, 'rev-parse', 'HEAD~1')).toBe(head);
    expect(out(at.root, 'show', '--name-only', '--format=', 'HEAD')).toBe(
      'package.json',
    );
    expect(out(origin(), 'rev-parse', 'main')).toBe(
      out(at.root, 'rev-parse', 'HEAD'),
    );
    expect(version()).toBe('9.9.10');
  });

  test('preflight checks the new version, before anything is committed', async () => {
    git(at.root, 'tag', 'v9.9.10');

    const head = out(at.root, 'rev-parse', 'HEAD');

    expect(await died(releasedAt('fix', {}))).toBe('v9.9.10 is a tag already');
    expect(out(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(ran().some((line) => line.startsWith('bun '))).toBeFalse();
  });

  test("a version not above package.json's dies before preflight", async () => {
    expect(await died(releasedAt('9.9.8', { dryRun: true }))).toBe(
      "9.9.8 is not above package.json's version 9.9.9",
    );
    expect(ran()).toStrictEqual([]);
  });

  test("a stopped publish resumes only package.json's version", async () => {
    writeFileSync(join(at.place, 'published', 'chord-darwin-arm64'), '');

    const head = out(at.root, 'rev-parse', 'HEAD');

    expect(await died(releasedAt('patch', {}))).toBe(
      "a stopped publish resumes package.json's version 9.9.9, not 9.9.10; run it without a version",
    );
    expect(out(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(ran().some((line) => line.startsWith('npm publish'))).toBeFalse();
  });

  test('a push that fails drops the commit and stops before any stage', async () => {
    const head = out(at.root, 'rev-parse', 'HEAD');
    const hook = join(origin(), 'hooks', 'pre-receive');

    executable(hook, '#!/bin/sh\necho refused >&2\nexit 1\n');

    expect(await died(releasedAt('patch', {}))).toStartWith(
      'git push origin main failed, so chore: chord v9.9.10 is dropped:',
    );
    expect(out(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(version()).toBe(VERSION);
    expect(out(at.root, 'status', '--porcelain')).toBe('');
    expect(ran().some((line) => line.startsWith('bun '))).toBeFalse();
  });

  test("package.json's own version makes no commit", async () => {
    const head = out(at.root, 'rev-parse', 'HEAD');

    await releasedAt(VERSION, { to: 'check' });

    expect(checked()).toBe(VERSION);
    expect(out(at.root, 'rev-parse', 'HEAD')).toBe(head);
  });

  test.each([
    ['--only publish', { only: ['publish' as const] }],
    [
      '--only check,pack,publish',
      { only: ['check', 'pack', 'publish'] as const },
    ],
    ['--from pack', { from: 'pack' as const }],
    ['--skip compile', { skip: ['compile' as const] }],
    ['--to check', { to: 'check' as const }],
  ])('a new version without compile is refused: %s', async (_name, options) => {
    const head = out(at.root, 'rev-parse', 'HEAD');

    expect(await died(releasedAt('patch', options))).toBe(
      "a new version needs the compile stage: 9.9.10 is not package.json's 9.9.9",
    );
    expect(out(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(ran()).toStrictEqual([]);
  });

  test("package.json's own version needs no compile", async () => {
    await releasedAt(VERSION, { dryRun: true, only: ['check'] });

    expect(checked()).toBe(VERSION);
  });
});

describe('a signal while the version commit is held', () => {
  const lib = join(import.meta.dir, '../../../../scripts/dev/release');

  /**
   * A release at `version` in a process of its own, whose check stage
   * sends that process `signal`, as Ctrl+C reaches a stage's child and
   * chord's release together, then fails.
   */
  function interrupted(signal: string, options: ReleaseOptions) {
    at.fake(
      'bun',
      `echo "bun $*" >>"$STATE/ran.log"
if [ "$1" = 'quality' ]; then kill -${signal} $PPID; exit 2; fi
`,
    );

    const script = join(at.place, 'run.ts');

    writeFileSync(
      script,
      `import { dying } from ${JSON.stringify(join(lib, 'lib.ts'))};
import { selectStages } from ${JSON.stringify(join(lib, 'select.ts'))};
import { runRelease } from ${JSON.stringify(join(lib, 'stages.ts'))};

const options = ${JSON.stringify(options)};
const release = {
  root: ${JSON.stringify(at.root)},
  env: process.env,
  sleep: () => Promise.resolve(),
  out: (line) => console.log(line),
  err: (line) => console.error(line),
  tty: true,
};

await dying(() =>
  runRelease(release, selectStages(options), options, { platform: 'darwin', arch: 'arm64' }, 'patch'),
);
`,
    );

    return spawnSync(process.execPath, [script], {
      cwd: at.root,
      env: context().env,
      encoding: 'utf8',
    });
  }

  function out(cwd: string, ...args: string[]): string {
    return String(spawnSync('git', args, { cwd }).stdout).trim();
  }

  test.each(['SIGINT', 'SIGTERM', 'SIGHUP'])(
    '%s drops the commit and ends the run by it',
    (signal) => {
      const head = out(at.root, 'rev-parse', 'HEAD');
      const child = interrupted(signal, { dryRun: true, to: 'compile' });

      expect(child.signal).toBe(signal);
      expect(out(at.root, 'rev-parse', 'HEAD')).toBe(head);
      expect(out(at.root, 'status', '--porcelain')).toBe('');
    },
  );

  test('a run that has pushed keeps its commit', () => {
    const child = interrupted('SIGINT', {
      skip: ['natives', 'sign', 'selftest', 'notarise', 'pack'],
    });

    expect(child.status).not.toBe(0);
    expect(out(at.root, 'log', '-1', '--format=%s')).toBe(
      'chore: chord v9.9.10',
    );
    expect(
      out(join(at.place, 'origin.git'), 'log', '-1', '--format=%s', 'main'),
    ).toBe('chore: chord v9.9.10');
  });
});
