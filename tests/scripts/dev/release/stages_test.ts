import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { basename, join } from 'node:path';
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
import { holdRelease } from '../../../../scripts/dev/release/lock.ts';
import { runRelease } from '../../../../scripts/dev/release/stages.ts';
import { KINDS } from '../../../../scripts/dev/release/build.ts';
import type { FoundPackage } from '../../../../scripts/dev/steps.ts';
import chordSteps from '../../../../steps.ts';

import { recordSums } from '../../../../scripts/dev/release/sums.ts';
import { tarball, tarballs } from '../../../../scripts/dev/release/publish.ts';
import {
  executable,
  fetchedArchives,
  nativeNotes,
  type Scratch,
  scratch,
} from './scratch.ts';

/** chord's steps.ts, for a release run in a child. */
const STEPS = new URL('../../../../steps.ts', import.meta.url).pathname;

// A whole run's guards and their order, on a scratch repository with a bare
// origin: npm, bun, security and xcrun faked, each logging what it was asked,
// so a test sees what ran before a run died. A file in published/ names a
// package npm has at any version, or one name@version.

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
  nativeNotes(at.root);

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
whoami)
  if [ -n "$AUTH_FAIL" ] && [ ! -f "$STATE/authenticated" ]; then exit 1; fi
  echo owner
  ;;
login)
  if [ "$LOGIN_RESULT" = signal ]; then kill -TERM $$; fi
  if [ -n "$LOGIN_RESULT" ]; then exit "$LOGIN_RESULT"; fi
  if [ -z "$RECHECK_FAIL" ]; then touch "$STATE/authenticated"; fi
  ;;
view)
	spec=\${2#@chorded/}
	if [ -f "$STATE/published/\${spec%@*}" ] || [ -f "$STATE/published/$spec" ]; then echo "\${spec##*@}"; exit 0; fi
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

/** chord as discovery finds it, its stages from its steps.ts. */
const CHORD: FoundPackage = { name: 'chord', folder: '.', steps: chordSteps };

/** The stages of chord's release `options` select. */
function select(options: ReleaseOptions): string[] {
  return selectStages(
    { name: 'chord', stages: chordSteps.release.map((stage) => stage.name) },
    options,
  );
}

/** Runs chord's release `options` select, on `machine`. */
async function released(
  options: ReleaseOptions,
  env: Record<string, string> = {},
  machine = MAC,
): Promise<void> {
  await runRelease(context(env), CHORD, select(options), options, machine);
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

describe('CHD-561 tester: source fetch interrupts the release parent', () => {
  test('SIGTERM during curl drops a local version commit before npm packing or a draft', () => {
    writeFileSync(join(at.place, 'published', `chord@${VERSION}`), '');
    at.fake('file', `echo "$1: ${Object.values(KINDS).join(' ')}"\n`);
    at.fake('curl', 'printf half >"${@: -2:1}"\nkill -TERM $PPID\nexit 22\n');

    const lib = join(import.meta.dir, '../../../../scripts/dev/release');
    const script = join(at.place, 'source-interrupted.ts');
    const readGit = (...args: string[]) => {
      const result = spawnSync('git', args, { cwd: at.root, encoding: 'utf8' });

      expect(result.status).toBe(0);

      return result.stdout.trim();
    };

    const head = readGit('rev-parse', 'HEAD');

    writeFileSync(
      script,
      `
import { dying } from ${JSON.stringify(join(lib, 'lib.ts'))};
import { selectStages } from ${JSON.stringify(join(lib, 'select.ts'))};
import { runRelease } from ${JSON.stringify(join(lib, 'stages.ts'))};
import steps from ${JSON.stringify(STEPS)};
const chord = { name: 'chord', folder: '.', steps };
const options = { dryRun: true, only: ['compile', 'pack'] };
const release = {
  root: ${JSON.stringify(at.root)}, env: process.env,
  sleep: () => Promise.resolve(), out: console.log, err: console.error, tty: true,
};
await dying(() => runRelease(release, chord, selectStages({ name: 'chord', stages: steps.release.map((stage) => stage.name) }, options), options,
  { platform: 'darwin', arch: 'arm64' }, 'patch'));
`,
    );

    const child = spawnSync(process.execPath, [script], {
      cwd: at.root,
      env: context().env,
      encoding: 'utf8',
      timeout: 10_000,
    });

    expect(child.signal, child.stdout + child.stderr).toBe('SIGTERM');
    expect(readGit('rev-parse', 'HEAD')).toBe(head);
    expect(readGit('status', '--porcelain')).toBe('');
    expect(ran()).toContain('npm whoami');
    expect(
      ran().some(
        (line) => line.startsWith('npm pack') || line.startsWith('npm publish'),
      ),
    ).toBe(false);
    expect(existsSync(join(at.place, 'gh.log'))).toBe(false);
    expect(
      existsSync(
        join(at.root, 'dist', 'release', 'source', 'ffmpeg-9.0.2.tar.xz'),
      ),
    ).toBe(false);
    expect(
      JSON.parse(readFileSync(join(at.root, 'package.json'), 'utf8')).version,
    ).toBe(VERSION);
  });
});

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
  await released({ to: 'quality' }, { NO_NOTARY: 'yes', IDENTITIES: '' });

  expect(ran().filter((line) => !line.startsWith('npm '))).toStrictEqual([
    'bun install --frozen-lockfile',
    'bun scripts/dev.ts quality chord',
  ]);
});

test('a dry run that did not pack says what it ran, and publishes nothing', async () => {
  await released({ dryRun: true, only: ['install', 'quality'] });

  expect(at.out.at(-1)).toBe(
    `dry run: @chorded/chord ${VERSION}, ran install, quality; not published`,
  );
  expect(ran().some((line) => line.startsWith('npm publish'))).toBeFalse();
});

test('a dry run that packs fetches and checks the archives, and makes no release', async () => {
  // Past the archives it fails on what this scratch has not built.
  await died(released({ dryRun: true, only: ['pack'] }));

  expect(
    existsSync(join(at.root, 'dist', 'release', 'source', 'zlib-1.3.2.tar.gz')),
  ).toBeTrue();
  expect(existsSync(join(at.place, 'gh.log'))).toBeFalse();
});

test('a bad archive stops a dry run before it packs anything', async () => {
  at.fake('curl', 'printf tampered >"${@: -2:1}"\n');

  expect(await died(released({ dryRun: true, only: ['pack'] }))).toContain(
    'FFMPEG-SOURCE.md names',
  );
  expect(ran().some((line) => line.startsWith('npm pack'))).toBeFalse();
});

test('skipping pack leaves publish to stop before npm takes anything', async () => {
  packed();
  rmSync(join(at.root, 'dist', 'release', 'source'), {
    recursive: true,
    force: true,
  });
  writeFileSync(join(at.place, 'published', 'chord-darwin-arm64'), '');

  expect(await died(released({ skip: ['pack'] }))).toContain(
    'fetched by the pack stage',
  );
  expect(ran().some((line) => line.startsWith('npm publish'))).toBeFalse();
});

test('a run without publish prints no version', async () => {
  await released({ only: ['install'] });

  expect(at.out).toStrictEqual([]);
});

/** Tarballs a stopped run left, their sums recorded. */
function packed(): void {
  fetchedArchives(at.root);

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
    `resuming ${VERSION}: a package before @chorded/chord is published, @chorded/chord is not`,
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

describe('tester: CHD-547 explicit version eligibility', () => {
  test.each([false, true])(
    'an explicit new version with only compile cannot skip the publication guard (dry run: %s)',
    async (dryRun) => {
      const options: ReleaseOptions = { dryRun, only: ['compile'] };
      const before = readFileSync(join(at.root, 'package.json'), 'utf8');

      expect(
        await died(
          runRelease(
            context({ AUTH_FAIL: 'yes' }),
            CHORD,
            select(options),
            options,
            MAC,
            '9.9.10',
          ),
        ),
      ).toBe(
        '@chorded/chord@9.9.9 is not published yet; `bun dev release chord` without --bump finishes it',
      );
      expect(ran()).toEqual(['npm view @chorded/chord@9.9.9 version']);
      expect(readFileSync(join(at.root, 'package.json'), 'utf8')).toBe(before);
      expect(
        String(
          spawnSync('git', ['status', '--porcelain'], { cwd: at.root }).stdout,
        ).trim(),
      ).toBe('');
    },
  );
});

describe('tester: CHD-412 release transaction boundaries', () => {
  function output(cwd: string, ...args: string[]): string {
    const child = spawnSync('git', args, { cwd, encoding: 'utf8' });

    expect(child.status).toBe(0);

    return child.stdout.trim();
  }

  function versioned(wanted: string, options: ReleaseOptions) {
    return runRelease(context(), CHORD, select(options), options, MAC, wanted);
  }

  test('a successful local run drops its version commit without a dry-run flag', async () => {
    writeFileSync(join(at.place, 'published', `chord@${VERSION}`), '');

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
    writeFileSync(join(at.place, 'published', `chord@${VERSION}`), '');

    const head = output(at.root, 'rev-parse', 'HEAD');

    at.fake(
      'bun',
      `echo "bun $*" >>"$STATE/ran.log"
if [ "$2" = 'quality' ]; then echo 'stage-output/' >> .gitignore; exit 2; fi
`,
    );

    expect(
      await died(versioned('patch', { only: ['quality', 'compile'] })),
    ).toBe('bun dev quality chord failed');
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
      'bun scripts/dev.ts quality chord',
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
  test('quality selected alone calls the dev entry point without install', async () => {
    await released({ only: ['quality'] });

    expect(ran().filter((line) => line.startsWith('bun '))).toStrictEqual([
      'bun scripts/dev.ts quality chord',
    ]);
    expect(at.out).toEqual([]);
  });

  test('a failed install never reaches the migrated quality command', async () => {
    at.fake(
      'bun',
      `echo "bun $*" >>"$STATE/ran.log"
if [ "$1" = 'install' ]; then exit 7; fi
`,
    );

    expect(await died(released({ to: 'quality' }))).toBe(
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

  test('preflight guards quality, compile, pack and publish selected alone', async () => {
    writeFileSync(join(at.root, 'untracked-fixture'), '');

    for (const stage of ['quality', 'compile', 'pack', 'publish'] as const) {
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
if [ "$2" = 'quality' ]; then exit 2; fi
`,
    );

    expect(
      await died(
        released({ dryRun: true, only: ['install', 'quality', 'compile'] }),
      ),
    ).toBe('bun dev quality chord failed');
    expect(ran().filter((line) => line.startsWith('bun '))).toStrictEqual([
      'bun install --frozen-lockfile',
      'bun scripts/dev.ts quality chord',
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
rev-parse) if [ "$2" = --git-common-dir ]; then echo .git; else echo fixture-commit; fi ;;
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
      CHORD,
      select(options),
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
    // The last release reached npm, so a new version may follow it.
    writeFileSync(join(at.place, 'published', `chord@${VERSION}`), '');
    // The bun faked records the version package.json had when check ran.
    at.fake(
      'bun',
      `echo "bun $*" >>"$STATE/ran.log"
if [ "$2" = 'quality' ]; then cat package.json >"$STATE/checked.json"; fi
if [ -n "$FAIL_CHECK" ] && [ "$2" = 'quality' ]; then exit 2; fi
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
      only: ['install', 'quality', 'compile'],
    });

    expect(checked()).toBe('9.10.0');
    expect(at.out.at(-1)).toBe(
      'dry run: @chorded/chord 9.10.0, ran install, quality, compile; not published',
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
    ).toBe('bun dev quality chord failed');
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
    rmSync(join(at.place, 'published', `chord@${VERSION}`));

    const head = out(at.root, 'rev-parse', 'HEAD');

    await releasedAt(VERSION, { to: 'quality' });

    expect(checked()).toBe(VERSION);
    expect(out(at.root, 'rev-parse', 'HEAD')).toBe(head);
  });

  test.each([
    ['--only publish', { only: ['publish' as const] }],
    [
      '--only quality,pack,publish',
      { only: ['quality', 'pack', 'publish'] as const },
    ],
    ['--from pack', { from: 'pack' as const }],
    ['--skip compile', { skip: ['compile' as const] }],
    ['--to quality', { to: 'quality' as const }],
  ])('a new version without compile is refused: %s', async (_name, options) => {
    const head = out(at.root, 'rev-parse', 'HEAD');

    expect(await died(releasedAt('patch', options))).toBe(
      "a new version needs the compile stage: 9.9.10 is not package.json's 9.9.9",
    );
    expect(out(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(ran()).toStrictEqual([]);
  });

  test("package.json's own version needs no compile", async () => {
    rmSync(join(at.place, 'published', `chord@${VERSION}`));
    await releasedAt(VERSION, { dryRun: true, only: ['quality'] });

    expect(checked()).toBe(VERSION);
  });

  test("a new version is refused while package.json's is unpublished, before authentication", async () => {
    rmSync(join(at.place, 'published', `chord@${VERSION}`));

    const head = out(at.root, 'rev-parse', 'HEAD');

    for (const options of [{}, { dryRun: true }]) {
      expect(await died(releasedAt('minor', options))).toBe(
        '@chorded/chord@9.9.9 is not published yet; `bun dev release chord` without --bump finishes it',
      );
    }

    expect(
      ran().some((line) => line === 'npm whoami' || line === 'npm login'),
    ).toBeFalse();
    expect(ran().some((line) => line.startsWith('bun '))).toBeFalse();
    expect(out(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(version()).toBe(VERSION);
  });

  test("a run without a version needs no published package.json's version", async () => {
    rmSync(join(at.place, 'published', `chord@${VERSION}`));

    await released({ dryRun: true, only: ['quality'] });
    await releasedAt(VERSION, { dryRun: true, only: ['quality'] });

    expect(checked()).toBe(VERSION);
  });
});

describe('a channel', () => {
  const NEXT = '10.0.0-next.3';

  beforeEach(() => {
    // A registry that knows versions, as a pre-release's tarball name has a
    // hyphen of its own, and answers npm's latest from LATEST.
    at.fake(
      'npm',
      `echo "npm $*" >>"$STATE/ran.log"
case "$1" in
whoami) echo owner ;;
view)
  if [ "$3" = dist-tags.latest ]; then
    if [ -n "$NPM_DOWN" ]; then echo 'npm error code E500' >&2; exit 1; fi
    echo "\${LATEST-9.9.9}"
    exit 0
  fi
  spec=\${2#@chorded/}
  if [ -f "$STATE/published/$spec" ]; then echo "\${spec##*@}"; exit 0; fi
  echo 'npm error code E404' >&2
  exit 1
  ;;
publish)
  file=$(basename "$4" .tgz)
  file=\${file#chorded-}
  name=\${file%%-[0-9]*}
  touch "$STATE/published/$name@\${file#"$name"-}"
  ;;
esac
`,
    );
    at.fake(
      'bun',
      `echo "bun $*" >>"$STATE/ran.log"
if [ "$2" = 'quality' ]; then cat package.json >"$STATE/checked.json"; exit 2; fi
`,
    );
    onNpm('chord', VERSION);
  });

  function onNpm(name: string, version: string): void {
    writeFileSync(join(at.place, 'published', `${name}@${version}`), '');
  }

  /** `branch` checked out and on origin, package.json at `version`. */
  function onBranch(branch: string, version = VERSION): void {
    git(at.root, 'checkout', '-q', '-b', branch);

    if (version !== VERSION) {
      writeFileSync(join(at.root, 'package.json'), JSON.stringify({ version }));
      git(at.root, 'commit', '-q', '-am', `chore: chord v${version}`);
    }

    git(at.root, 'push', '-q', 'origin', branch);
  }

  function read(cwd: string, ...args: string[]): string {
    return String(spawnSync('git', args, { cwd }).stdout).trim();
  }

  const origin = () => join(at.place, 'origin.git');

  /** A publishing run at `wanted`, stopped by the check that follows the push. */
  function publishing(
    wanted: string | undefined,
    channel: string | undefined,
    env: Record<string, string> = {},
  ): Promise<void> {
    const options = {
      channel,
      skip: ['natives', 'sign', 'selftest', 'notarise', 'pack'] as const,
    };

    return runRelease(
      context(env),
      CHORD,
      select(options),
      options,
      MAC,
      wanted,
    );
  }

  test('a bump counts from npm, starts at 0, and pushes to the branch of the channel', async () => {
    onBranch('next');

    const main = read(at.root, 'rev-parse', 'main');

    expect(await died(publishing('major', 'next'))).toBe(
      'bun dev quality chord failed',
    );
    expect(read(at.root, 'log', '-1', '--format=%s')).toBe(
      'chore: chord v10.0.0-next.0',
    );
    expect(read(origin(), 'rev-parse', 'next')).toBe(
      read(at.root, 'rev-parse', 'HEAD'),
    );
    expect(read(origin(), 'rev-parse', 'main')).toBe(main);
    expect(ran()).toContain('npm view @chorded/chord dist-tags.latest');
  });

  test('the same bump again goes up by one', async () => {
    onBranch('next', NEXT);
    onNpm('chord', NEXT);

    await died(publishing('major', 'next'));

    expect(read(at.root, 'log', '-1', '--format=%s')).toBe(
      'chore: chord v10.0.0-next.4',
    );
  });

  test('an exact version gives the same numbers, without asking npm for latest', async () => {
    onBranch('beta');

    await died(publishing('10.0.0', 'beta'));

    expect(read(at.root, 'log', '-1', '--format=%s')).toBe(
      'chore: chord v10.0.0-beta.0',
    );
    expect(read(origin(), 'rev-parse', 'beta')).toBe(
      read(at.root, 'rev-parse', 'HEAD'),
    );
    expect(ran()).not.toContain('npm view @chorded/chord dist-tags.latest');
  });

  test('a stable release never asks npm for latest', async () => {
    await died(publishing('patch', undefined));

    expect(read(at.root, 'log', '-1', '--format=%s')).toBe(
      'chore: chord v9.9.10',
    );
    expect(ran()).not.toContain('npm view @chorded/chord dist-tags.latest');
  });

  test('a failed read of npm latest stops the release', async () => {
    onBranch('next');

    const head = read(at.root, 'rev-parse', 'HEAD');

    expect(await died(publishing('major', 'next', { NPM_DOWN: 'yes' }))).toBe(
      'npm view @chorded/chord dist-tags.latest failed: npm error code E500',
    );
    expect(read(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(ran()).toStrictEqual(['npm view @chorded/chord dist-tags.latest']);
  });

  test('an npm latest that is no stable version stops the release', async () => {
    onBranch('next');

    expect(await died(publishing('major', 'next', { LATEST: '' }))).toBe(
      "npm's latest  is no stable version",
    );
  });

  test.each([
    ['main', 'main'],
    ['another channel', 'beta'],
  ])('from %s it is refused', async (_name, branch) => {
    if (branch !== 'main') {
      onBranch(branch);
    }

    const head = read(at.root, 'rev-parse', 'HEAD');

    expect(await died(publishing('major', 'next'))).toBe(
      `a release on channel next publishes only from branch next; HEAD is ${branch}`,
    );
    expect(read(at.root, 'rev-parse', 'HEAD')).toBe(head);
    expect(ran().some((line) => line.startsWith('bun '))).toBeFalse();
  });

  test('a stable release from its branch is refused', async () => {
    onBranch('next');

    expect(await died(publishing('patch', undefined))).toBe(
      'a release that publishes runs from main; HEAD is next',
    );
  });

  test('a stable release over its pre-release is refused from its branch and taken from main', async () => {
    onBranch('next', NEXT);
    onNpm('chord', NEXT);

    expect(await died(publishing('10.0.0', undefined))).toBe(
      'a release that publishes runs from main; HEAD is next',
    );

    // next merged into main, as it ends.
    git(at.root, 'checkout', '-q', 'main');
    git(at.root, 'merge', '-q', '--ff-only', 'next');
    git(at.root, 'push', '-q', 'origin', 'main');

    await died(publishing('10.0.0', undefined));

    expect(read(at.root, 'log', '-1', '--format=%s')).toBe(
      'chore: chord v10.0.0',
    );
    expect(read(origin(), 'rev-parse', 'main')).toBe(
      read(at.root, 'rev-parse', 'HEAD'),
    );
  });

  test('its version without a version given is refused from main', async () => {
    onBranch('next', NEXT);
    git(at.root, 'checkout', '-q', 'main');
    git(at.root, 'merge', '-q', '--ff-only', 'next');
    git(at.root, 'push', '-q', 'origin', 'main');

    expect(await died(publishing(undefined, undefined))).toBe(
      'a release on channel next publishes only from branch next; HEAD is main',
    );
  });

  test('a branch not level with origin is refused', async () => {
    onBranch('next');

    const behind = read(at.root, 'rev-parse', 'HEAD');

    git(at.root, 'commit', '-q', '--allow-empty', '-m', 'ahead');

    const head = read(at.root, 'rev-parse', 'HEAD');

    expect(await died(publishing('major', 'next'))).toBe(
      `next is not origin/next: next is ${head}, origin/next is ${behind}`,
    );
  });

  test('a branch not on origin is refused', async () => {
    git(at.root, 'checkout', '-q', '-b', 'next');

    expect(await died(publishing('major', 'next'))).toStartWith(
      'git rev-parse origin/next failed:',
    );
  });

  test('a push that fails names the branch and drops the commit', async () => {
    onBranch('next');

    const head = read(at.root, 'rev-parse', 'HEAD');

    executable(
      join(origin(), 'hooks', 'pre-receive'),
      '#!/bin/sh\necho refused >&2\nexit 1\n',
    );

    expect(await died(publishing('major', 'next'))).toStartWith(
      'git push origin next failed, so chore: chord v10.0.0-next.0 is dropped:',
    );
    expect(read(at.root, 'rev-parse', 'HEAD')).toBe(head);
  });

  describe('a dry run', () => {
    const tgz = (name: string, version: string) =>
      join(at.root, 'dist', 'release', 'tgz', `chorded-${name}-${version}.tgz`);

    function shown(): string[] {
      return at.out.filter((line) => line.startsWith('dry run: '));
    }

    test.each(['next', 'beta'])(
      'on %s shows the stages and every package with its tag, in publish order',
      async (channel) => {
        const version = `10.0.0-${channel}.0`;
        const options = {
          channel,
          dryRun: true,
          only: ['install', 'compile'] as const,
        };

        onBranch(channel);
        at.fake('file', `echo "$1: ${Object.values(KINDS).join(' ')}"\n`);

        const head = read(at.root, 'rev-parse', 'HEAD');

        await runRelease(
          context(),
          CHORD,
          select(options),
          options,
          MAC,
          'major',
        );

        expect(shown()).toStrictEqual([
          'dry run: ran install, compile',
          ...[...PLATFORMS, 'chord'].map(
            (name) =>
              `dry run: npm publish --access public ${tgz(name, version)} --tag ${channel}`,
          ),
          `dry run: @chorded/chord ${version}, ran install, compile; not published`,
        ]);
        expect(read(at.root, 'rev-parse', 'HEAD')).toBe(head);
      },
    );

    test("of package.json's version shows the same without --channel", async () => {
      onBranch('next', NEXT);

      await released({ dryRun: true, only: ['install'] });

      expect(shown()).toContain(
        `dry run: npm publish --access public ${tgz('chord', NEXT)} --tag next`,
      );
      expect(ran().some((line) => line.startsWith('npm publish'))).toBeFalse();
    });

    test('of a stable version says what it said', async () => {
      rmSync(join(at.place, 'published', `chord@${VERSION}`));

      await released({ dryRun: true, only: ['install'] });

      expect(shown()).toStrictEqual([
        `dry run: @chorded/chord ${VERSION}, ran install; not published`,
      ]);
    });
  });

  describe('a stopped publish', () => {
    beforeEach(() => {
      onBranch('next', NEXT);
      fetchedArchives(at.root);

      const tgz = join(at.root, 'dist', 'release', 'tgz');
      const files = ['chord', ...PLATFORMS].map(
        (name) => `chorded-${name}-${NEXT}.tgz`,
      );

      mkdirSync(tgz, { recursive: true });

      for (const file of files) {
        writeFileSync(join(tgz, file), file);
      }

      recordSums(tgz, files);
      onNpm('chord-darwin-arm64', NEXT);
    });

    test.each([
      ['with no version', undefined],
      ['with its channel', 'next'],
    ])('resumes %s, building nothing', async (_name, channel) => {
      await publishing(undefined, channel);

      expect(at.out[0]).toBe(
        `resuming ${NEXT}: a package before @chorded/chord is published, @chorded/chord is not`,
      );
      expect(at.out.at(-1)).toBe(NEXT);
      expect(ran().some((line) => /^(bun|security|xcrun) /.test(line))).toBe(
        false,
      );
      expect(read(origin(), 'tag', '--list', `v${NEXT}`)).toBe(`v${NEXT}`);
    });

    test('refuses another channel', async () => {
      expect(await died(publishing(undefined, 'beta'))).toBe(
        `package.json's version ${NEXT} is not on channel beta; name a version or a bump`,
      );
    });

    test.each([
      ['an exact version', '10.0.0'],
      ['a bump', 'major'],
    ])('refuses %s, as it is not on npm', async (_name, wanted) => {
      expect(await died(publishing(wanted, 'next'))).toBe(
        `@chorded/chord@${NEXT} is not published yet; \`bun dev release chord\` without --bump finishes it`,
      );
    });

    test('is refused from another branch', async () => {
      git(at.root, 'checkout', '-q', '-b', 'topic');

      expect(await died(publishing(undefined, undefined))).toBe(
        'a release on channel next publishes only from branch next; HEAD is topic',
      );
    });
  });

  test.each([
    ['a labelled version', '10.0.0-next.0', undefined],
    ['a labelled version on a channel', '10.0.0-next.0', 'next'],
  ])('%s is refused before anything runs', async (_name, wanted, channel) => {
    expect(await died(publishing(wanted, channel))).toBe(
      `${wanted} has a pre-release label; --channel is the only way to name one`,
    );
    expect(ran()).toStrictEqual([]);
  });

  test.each(['latest', 'main', 'x', 'v1', 'Next'])(
    'channel %s is refused before anything runs',
    async (channel) => {
      expect(await died(publishing('major', channel))).toContain(
        `${channel} is no channel name`,
      );
      expect(ran()).toStrictEqual([]);
    },
  );

  test.each([
    ['1.0.0-next', 'a pre-release is written <x.y.z>-<channel>.<n>'],
    ['1.0.0-latest.0', "npm's latest"],
    ['1.0.0-next.01', 'is no version'],
    ['latest', 'is no version'],
  ])(
    'a package.json at %s is refused before anything runs',
    async (version, why) => {
      writeFileSync(join(at.root, 'package.json'), JSON.stringify({ version }));
      git(at.root, 'commit', '-q', '-am', 'edited by hand');

      expect(await died(publishing(undefined, undefined))).toContain(why);
      expect(ran()).toStrictEqual([]);
    },
  );
});

describe('a signal while the version commit is held', () => {
  const lib = join(import.meta.dir, '../../../../scripts/dev/release');

  /**
   * A release at `version` in a process of its own, whose check stage
   * sends that process `signal`, as Ctrl+C reaches a stage's child and
   * chord's release together, then fails.
   */
  function interrupted(signal: string, options: ReleaseOptions) {
    writeFileSync(join(at.place, 'published', `chord@${VERSION}`), '');
    at.fake(
      'bun',
      `echo "bun $*" >>"$STATE/ran.log"
if [ "$2" = 'quality' ]; then kill -${signal} $PPID; exit 2; fi
`,
    );

    const script = join(at.place, 'run.ts');

    writeFileSync(
      script,
      `import { dying } from ${JSON.stringify(join(lib, 'lib.ts'))};
import { selectStages } from ${JSON.stringify(join(lib, 'select.ts'))};
import { runRelease } from ${JSON.stringify(join(lib, 'stages.ts'))};
import steps from ${JSON.stringify(STEPS)};

const chord = { name: 'chord', folder: '.', steps };
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
  runRelease(release, chord, selectStages({ name: 'chord', stages: steps.release.map((stage) => stage.name) }, options), options, { platform: 'darwin', arch: 'arm64' }, 'patch'),
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

describe('CHD-531 mandatory authentication preparation', () => {
  const auth: ('npm whoami' | 'npm login')[] = [
    'npm whoami',
    'npm login',
    'npm whoami',
  ];

  test.each([
    { only: ['install'] },
    { from: 'install', to: 'install' },
    { skip: ['quality'], to: 'install' },
    { dryRun: true, skip: ['notarise'], to: 'install' },
  ] satisfies ReleaseOptions[])(
    'stage selection %j retains auth for fresh nonpublishing runs',
    async (options) => {
      await released(options, { AUTH_FAIL: 'yes' });

      expect(
        ran().filter((line) => line === 'npm whoami' || line === 'npm login'),
      ).toEqual(auth);
      expect(ran().at(-1)).toBe('bun install --frozen-lockfile');
      expect(at.out.slice(0, 2)).toEqual([
        'npm whoami failed; npm login will use this terminal and may open a browser.',
        'npm may save credentials and registry settings, including during a dry run.',
      ]);
    },
  );

  test('a resumed publish authenticates before publishing without rebuilding', async () => {
    packed();
    writeFileSync(join(at.place, 'published', 'chord-darwin-arm64'), '');
    await released({}, { AUTH_FAIL: 'yes' });

    const log = ran();
    const login = log.indexOf('npm login');

    expect(log.slice(login - 1, login + 2)).toEqual(auth);
    expect(
      log.findIndex((line) => line.startsWith('npm publish')),
    ).toBeGreaterThan(login + 1);
    expect(log.some((line) => /^(bun|security|xcrun) /.test(line))).toBe(false);
    expect(at.out.at(-1)).toBe(VERSION);
  });

  test.each([
    { LOGIN_RESULT: '2' },
    { LOGIN_RESULT: '130' },
    { LOGIN_RESULT: 'signal' },
    { RECHECK_FAIL: 'yes' },
  ])(
    'authentication failure %j precedes Apple checks, version mutation and all stages',
    async (failure) => {
      writeFileSync(join(at.place, 'published', `chord@${VERSION}`), '');

      const before = readFileSync(join(at.root, 'package.json'), 'utf8');
      const head = String(
        spawnSync('git', ['rev-parse', 'HEAD'], { cwd: at.root }).stdout,
      );
      const options = {
        only: ['install', 'compile', 'sign', 'notarise', 'publish'],
      } satisfies ReleaseOptions;
      const error = await died(
        runRelease(
          context({ AUTH_FAIL: 'yes', ...failure }),
          CHORD,
          select(options),
          options,
          MAC,
          'patch',
        ),
      );

      expect(error).toBe(
        failure.RECHECK_FAIL
          ? 'npm whoami still failed after login; release stopped'
          : 'npm login did not complete; release stopped',
      );
      expect(ran().filter((line) => line === 'npm login')).toHaveLength(1);
      expect(
        ran().some((line) => /^(bun|security|xcrun|npm publish) /.test(line)),
      ).toBe(false);
      expect(readFileSync(join(at.root, 'package.json'), 'utf8')).toBe(before);
      expect(
        String(
          spawnSync('git', ['rev-parse', 'HEAD'], { cwd: at.root }).stdout,
        ),
      ).toBe(head);
      expect(
        String(
          spawnSync('git', ['rev-parse', 'origin/main'], { cwd: at.root })
            .stdout,
        ),
      ).toBe(head);
    },
  );

  test('failed identity without a terminal stops before any stage', async () => {
    const options = { only: ['install'] } satisfies ReleaseOptions;

    expect(
      await died(
        runRelease(
          { ...context({ AUTH_FAIL: 'yes' }), tty: false },
          CHORD,
          select(options),
          options,
          MAC,
        ),
      ),
    ).toBe(
      'npm login needs stdin and stdout on a terminal; rerun this release in a terminal.',
    );
    expect(ran().includes('npm login')).toBe(false);
    expect(ran().some((line) => line.startsWith('bun '))).toBe(false);
  });

  test.each([
    [
      'platform',
      { only: ['sign'] },
      undefined,
      { platform: 'linux', arch: 'x64' },
    ],
    ['new version', { only: ['install'] }, 'patch', MAC],
    ['dry resume', { dryRun: true, only: ['compile'] }, undefined, MAC],
    ['nonpublishing resume', { only: ['compile'] }, undefined, MAC],
  ] satisfies [string, ReleaseOptions, string | undefined, typeof MAC][])(
    '%s eligibility rejects before authentication',
    async (guard, options, wanted, machine) => {
      if (guard.endsWith('resume')) {
        writeFileSync(join(at.place, 'published', 'chord-darwin-arm64'), '');
      }

      const message = await died(
        runRelease(
          context({ AUTH_FAIL: 'yes' }),
          CHORD,
          select(options),
          options,
          machine,
          wanted,
        ),
      );

      expect(message).toMatch(
        /^(natives, sign|a new version needs|--dry-run does not resume|a run without publish does not resume)/,
      );
      expect(
        ran().some((line) => line === 'npm whoami' || line === 'npm login'),
      ).toBe(false);
    },
  );

  test.each([
    'dirty',
    'published',
    'registry',
    'branch',
    'ahead',
    'local tag',
    'remote tag',
    'resume version',
  ])('%s eligibility failure never starts authentication', async (guard) => {
    let wanted: string | undefined;
    const options = { only: ['compile', 'publish'] } satisfies ReleaseOptions;

    if (guard === 'dirty') {
      writeFileSync(join(at.root, 'stray'), '');
    } else if (guard === 'published') {
      writeFileSync(join(at.place, 'published', 'chord'), '');
    } else if (guard === 'registry') {
      at.fake(
        'npm',
        'echo "npm $*" >>"$STATE/ran.log"; echo "npm error code E500" >&2; exit 1',
      );
    } else if (guard === 'branch') {
      git(at.root, 'checkout', '-q', '-b', 'topic');
    } else if (guard === 'ahead') {
      git(at.root, 'commit', '-q', '--allow-empty', '-m', 'ahead');
    } else if (guard === 'local tag' || guard === 'remote tag') {
      git(at.root, 'tag', `v${VERSION}`);

      if (guard === 'remote tag') {
        git(at.root, 'push', '-q', 'origin', `v${VERSION}`);
        git(at.root, 'tag', '-d', `v${VERSION}`);
      }
    } else {
      writeFileSync(join(at.place, 'published', `chord@${VERSION}`), '');
      writeFileSync(join(at.place, 'published', 'chord-darwin-arm64'), '');

      wanted = 'patch';
    }

    expect(
      await died(
        runRelease(
          context({ AUTH_FAIL: 'yes' }),
          CHORD,
          select(options),
          options,
          MAC,
          wanted,
        ),
      ),
    ).not.toBe('npm login did not complete; release stopped');
    expect(
      ran().some((line) => line === 'npm whoami' || line === 'npm login'),
    ).toBe(false);
  });
});

describe('tester: CHD-577 branch and cleanup boundaries', () => {
  function read(...args: string[]): string {
    const result = spawnSync('git', args, { cwd: at.root, encoding: 'utf8' });

    expect(result.status).toBe(0);

    return result.stdout.trim();
  }

  function publishing(): Promise<void> {
    const options = { channel: 'beta', only: ['compile', 'publish'] as const };

    return runRelease(
      context(),
      CHORD,
      select(options),
      options,
      MAC,
      '10.0.0',
    );
  }

  beforeEach(() => {
    writeFileSync(join(at.place, 'published', `chord@${VERSION}`), '');
    git(at.root, 'checkout', '-q', '-b', 'beta');
    git(at.root, 'push', '-q', 'origin', 'beta');
  });

  test('detached HEAD is refused before authentication or a version commit', async () => {
    const head = read('rev-parse', 'HEAD');

    git(at.root, 'checkout', '-q', '--detach');

    expect(await died(publishing())).toContain(
      'a release on channel beta publishes only from branch beta; HEAD is',
    );
    expect(read('rev-parse', 'HEAD')).toBe(head);
    expect(
      ran().some((line) => /^(bun |npm (whoami|login|publish))/.test(line)),
    ).toBeFalse();
  });

  test('a channel behind its origin is refused before authentication', async () => {
    const head = read('rev-parse', 'HEAD');

    git(at.root, 'commit', '-q', '--allow-empty', '-m', 'remote ahead');

    const remote = read('rev-parse', 'HEAD');

    git(at.root, 'push', '-q', 'origin', 'beta');
    git(at.root, 'reset', '-q', '--hard', head);

    expect(await died(publishing())).toBe(
      `beta is not origin/beta: beta is ${head}, origin/beta is ${remote}`,
    );
    expect(read('rev-parse', 'HEAD')).toBe(head);
    expect(ran()).not.toContain('npm whoami');
  });

  test('a failed nonpublishing channel run restores its version and local commit', async () => {
    const head = read('rev-parse', 'HEAD');

    git(at.root, 'checkout', '-q', '-b', 'topic');
    at.fake('bun', 'echo "bun $*" >>"$STATE/ran.log"\nexit 2\n');

    const options = {
      channel: 'beta',
      dryRun: true,
      only: ['quality', 'compile'] as const,
    };

    expect(
      await died(
        runRelease(context(), CHORD, select(options), options, MAC, '10.0.0'),
      ),
    ).toBe('bun dev quality chord failed');
    expect(read('rev-parse', 'HEAD')).toBe(head);
    expect(
      JSON.parse(readFileSync(join(at.root, 'package.json'), 'utf8')),
    ).toEqual({ version: VERSION });
    expect(read('status', '--porcelain')).toBe('');
    expect(read('rev-parse', 'origin/beta')).toBe(head);
    expect(ran()).toContain('npm whoami');
    expect(ran().some((line) => /^npm (login|publish)/.test(line))).toBeFalse();
  });

  test('a prerelease latest answer fails before authentication or stages', async () => {
    at.fake('npm', 'echo "npm $*" >>"$STATE/ran.log"\necho 10.0.0-next.1\n');

    const options = { channel: 'beta', only: ['compile', 'publish'] as const };

    expect(
      await died(
        runRelease(context(), CHORD, select(options), options, MAC, 'major'),
      ),
    ).toBe("npm's latest 10.0.0-next.1 is no stable version");
    expect(ran()).toEqual(['npm view @chorded/chord dist-tags.latest']);
  });
});

describe.each([
  {
    name: 'five',
    folder: '.',
    npm: [
      '@chorded/five-a',
      '@chorded/five-b',
      '@chorded/five-c',
      '@chorded/five-d',
      '@chorded/five',
    ],
    tag: 'v{version}',
    githubRelease: true as const,
  },
  {
    name: 'one',
    folder: 'packages/one',
    npm: ['@chorded/one'],
    tag: 'one-v{version}',
  },
])(
  "a fixture package's release: $name (CHD-623)",
  ({ name, folder, npm, tag, githubRelease }) => {
    const NEXT = '9.9.10';
    const main = npm.at(-1)!;
    const tagged = (version: string) => tag.replace('{version}', version);
    const publish = {
      name: 'publish' as const,
      npm,
      tag,
      ...(githubRelease ? { githubRelease } : {}),
    };
    /** A stage that logs its name, as the fake commands log theirs. */
    const logged = (stage: string) => async () => {
      await Promise.resolve();
      writeFileSync(join(at.place, 'ran.log'), `stage ${stage}\n`, {
        flag: 'a',
      });
    };

    const found: FoundPackage = {
      name,
      folder,
      steps: {
        checks: [],
        lint: [],
        release: [
          { name: 'build', about: 'b', versioned: true, run: logged('build') },
          {
            name: 'sign',
            about: 's',
            machine: { platform: 'darwin', arch: 'arm64' },
            run: logged('sign'),
          },
          {
            name: 'pack',
            about: 'p',
            run: async (release, version) => {
              await logged('pack')();

              const dir = tarballs(release, folder);

              mkdirSync(dir, { recursive: true });

              const files = npm.map((each) =>
                basename(tarball(release, folder, each, version)),
              );

              for (const file of files) {
                writeFileSync(join(dir, file), file);
              }

              recordSums(dir, files);
            },
          },
          publish,
        ],
      },
    };
    const stages = found.steps.release.map((stage) => stage.name);

    beforeEach(() => {
      // Its package.json and bun.lock, as a workspace has them, committed and
      // on origin; dist/ and the release's output are ignored.
      if (folder !== '.') {
        mkdirSync(join(at.root, folder), { recursive: true });
        writeFileSync(
          join(at.root, folder, 'package.json'),
          JSON.stringify({ name: main, version: VERSION }),
        );
      }

      writeFileSync(join(at.root, 'bun.lock'), '{}\n');
      writeFileSync(join(at.root, '.gitignore'), 'dist/\n*/*/dist/\n');
      git(at.root, 'add', '-A');
      git(at.root, 'commit', '-q', '-m', 'the package');
      git(at.root, 'push', '-q', 'origin', 'main');
      // The version npm has, so a new one may follow it.
      writeFileSync(
        join(
          at.place,
          'published',
          `${main.slice('@chorded/'.length)}@${VERSION}`,
        ),
        '',
      );
      // Bun's lockfile install records a workspace package's version.
      at.fake(
        'bun',
        `echo "bun $*" >>"$STATE/ran.log"
if [ "$1 $2" = 'install --lockfile-only' ]; then echo "$(cat packages/one/package.json)" >bun.lock; fi
`,
      );
      at.fake(
        'npm',
        `echo "npm $*" >>"$STATE/ran.log"
case "$1" in
whoami) echo owner ;;
view)
  if [ "$3" = dist-tags.latest ]; then echo "\${LATEST-9.9.9}"; exit 0; fi
  spec=\${2#@chorded/}
  if [ -f "$STATE/published/$spec" ]; then echo "\${spec##*@}"; exit 0; fi
  echo 'npm error code E404' >&2
  exit 1
  ;;
publish)
  file=$(basename "$4" .tgz)
  name=\${file#chorded-}
  touch "$STATE/published/\${name%-*}@\${name##*-}"
  ;;
esac
`,
      );
      fetchedArchives(at.root);
    });

    function run(
      options: ReleaseOptions,
      bump?: string,
      machine = MAC,
    ): Promise<void> {
      return runRelease(
        context(),
        found,
        selectStages({ name, stages }, options),
        options,
        machine,
        bump,
      );
    }

    function git_(...args: string[]): string {
      return String(
        spawnSync('git', args, { cwd: at.root, encoding: 'utf8' }).stdout,
      ).trim();
    }

    test('a bump commits its package.json as chore: <package> v<version>, and publishes its npm names, the main one last, then tags', async () => {
      await run({}, 'patch');

      expect(git_('log', '-1', '--format=%s', 'origin/main')).toBe(
        `chore: ${name} v${NEXT}`,
      );
      expect(
        git_('show', '--name-only', '--format=', 'origin/main').split('\n'),
      ).toStrictEqual(
        folder === '.'
          ? ['package.json']
          : ['bun.lock', `${folder}/package.json`],
      );
      expect(
        ran()
          .filter((line) => line.startsWith('npm publish'))
          .map((line) => line.split(' ').at(-1)!.split('/').at(-1)),
      ).toStrictEqual(
        npm.map(
          (each) => `${each.replace('@', '').replace('/', '-')}-${NEXT}.tgz`,
        ),
      );
      // On origin, and on the version commit.
      expect(git_('ls-remote', '--tags', 'origin', tagged(NEXT))).toEndWith(
        `refs/tags/${tagged(NEXT)}`,
      );
      expect(git_('rev-parse', `${tagged(NEXT)}^{commit}`)).toBe(
        git_('rev-parse', 'origin/main'),
      );
      expect(at.out.at(-1)).toBe(NEXT);
    });

    test('a GitHub release, and gh at all, only for a package that has one', async () => {
      await run({}, 'patch');

      const gh = existsSync(join(at.place, 'gh.log'))
        ? readFileSync(join(at.place, 'gh.log'), 'utf8').trim().split('\n')
        : [];

      // The draft's archives after --notes are pack's, checked elsewhere.
      expect(gh.map((line) => line.split(' --notes')[0])).toStrictEqual(
        githubRelease
          ? [
              'auth status',
              `release create ${tagged(NEXT)} --draft --verify-tag --title ${name} ${tagged(NEXT)}`,
            ]
          : [],
      );
    });

    test('a second release in the checkout is refused before anything runs, naming the first', async () => {
      const unlock = await holdRelease(context());

      try {
        expect(await died(run({}, 'patch'))).toStartWith(
          `another release runs in this checkout (pid ${process.pid}); if it was killed, remove `,
        );
        expect(ran()).toStrictEqual([]);
      } finally {
        await unlock();
      }

      await run({ dryRun: true }, 'patch');
      expect(ran()).toContain('stage pack');
    });

    /** `found` with its own preflight: logged, refusing if `refuse`. */
    function guarded(refuse: boolean): FoundPackage {
      return {
        ...found,
        steps: {
          ...found.steps,
          preflight: async (release, version) => {
            await logged(`preflight ${version}`)();

            if (refuse) {
              throw new ReleaseError(`${name} refuses ${version}`);
            }
          },
        },
      };
    }

    test("the package's own preflight runs after the release's and before npm authentication", async () => {
      const options = { dryRun: true, skip: ['sign'] };

      await runRelease(
        context(),
        guarded(false),
        selectStages({ name, stages }, options),
        options,
        MAC,
        'patch',
      );

      const order = ran().filter(
        (line) =>
          line.startsWith(`npm view ${main}@${NEXT}`) ||
          line.startsWith('stage ') ||
          line === 'npm whoami',
      );

      expect(order).toStrictEqual([
        `npm view ${main}@${NEXT} version`,
        `stage preflight ${NEXT}`,
        'npm whoami',
        'stage build',
        'stage pack',
      ]);
    });

    test('a refusing package preflight stops before npm authentication or any stage, resuming too', async () => {
      expect(
        await died(
          runRelease(
            context(),
            guarded(true),
            selectStages({ name, stages }, {}),
            {},
            MAC,
            'patch',
          ),
        ),
      ).toBe(`${name} refuses ${NEXT}`);

      if (npm.length > 1) {
        // A stopped publish: a package before the main one has the version.
        rmSync(join(at.place, 'published'), { recursive: true });
        mkdirSync(join(at.place, 'published'));
        writeFileSync(
          join(
            at.place,
            'published',
            `${npm[0]!.slice('@chorded/'.length)}@${VERSION}`,
          ),
          '',
        );

        expect(
          await died(
            runRelease(
              context(),
              guarded(true),
              selectStages({ name, stages }, {}),
              {},
              MAC,
            ),
          ),
        ).toBe(`${name} refuses ${VERSION}`);
      }

      expect(
        ran().filter(
          (line) => line === 'npm whoami' || line.startsWith('npm login'),
        ),
      ).toStrictEqual([]);
      expect(
        ran().filter(
          (line) =>
            line.startsWith('stage ') && !line.startsWith('stage preflight'),
        ),
      ).toStrictEqual([]);
    });

    test('a new version needs its versioned stage', async () => {
      expect(await died(run({ skip: ['build'] }, 'patch'))).toBe(
        `a new version needs the build stage: ${NEXT} is not package.json's ${VERSION}`,
      );
    });

    test('a stage bound to a machine is refused elsewhere only when selected', async () => {
      const linux = { platform: 'linux', arch: 'x64' };

      expect(await died(run({ only: ['sign'] }, undefined, linux))).toBe(
        'sign runs only on an arm64 Mac; this is linux-x64',
      );
      await run({ skip: ['sign'], dryRun: true }, 'patch', linux);
      expect(ran()).toContain('stage pack');
    });

    test('CHD-547: a new version waits for npm to have the main npm name at the current one', async () => {
      rmSync(join(at.place, 'published'), { recursive: true });
      mkdirSync(join(at.place, 'published'));

      expect(await died(run({}, 'patch'))).toBe(
        `${main}@${VERSION} is not published yet; \`bun dev release ${name}\` without --bump finishes it`,
      );
    });

    test("a channel's bump counts from its main npm name's latest stable, and its dry run shows each npm name's arguments", async () => {
      git(at.root, 'checkout', '-q', '-b', 'next');

      await runRelease(
        context({ LATEST: '9.9.9' }),
        found,
        selectStages({ name, stages }, { dryRun: true, skip: ['sign'] }),
        { dryRun: true, skip: ['sign'], channel: 'next' },
        MAC,
        'major',
      );

      expect(ran()).toContain(`npm view ${main} dist-tags.latest`);
      expect(
        at.out.filter((line) => line.startsWith('dry run: npm ')),
      ).toStrictEqual(
        npm.map(
          (each) =>
            `dry run: npm publish --access public ${tarball(at.release, folder, each, '10.0.0-next.0')} --tag next`,
        ),
      );
    });
  },
);

describe('tester: CHD-623 selected stage readiness', () => {
  test('shared readiness is awaited once before selected stages run in package order', async () => {
    const events: string[] = [];
    const ready = async () => {
      await Promise.resolve();
      events.push('ready');
    };

    const stage = (name: string) => ({
      name,
      about: name,
      ready,
      run: () => {
        events.push(name);

        return Promise.resolve();
      },
    });
    const found: FoundPackage = {
      ...CHORD,
      steps: {
        ...CHORD.steps,
        release: [
          {
            name: 'unselected',
            about: 'must stay idle',
            ready: () => Promise.reject(new Error('unselected readiness ran')),
            run: () => Promise.reject(new Error('unselected stage ran')),
          },
          stage('first'),
          stage('second'),
          CHORD.steps.release.at(-1)!,
        ],
      },
    };

    await runRelease(context(), found, ['second', 'first'], {}, MAC);

    expect(events).toEqual(['ready', 'first', 'second']);
    expect(ran()).toContain('npm whoami');
  });

  test('a failed readiness stops later readiness and every selected stage', async () => {
    const failure = new Error('fixture readiness failed');
    const events: string[] = [];
    const found: FoundPackage = {
      ...CHORD,
      steps: {
        ...CHORD.steps,
        release: [
          {
            name: 'first',
            about: 'first',
            ready: () => Promise.reject(failure),
            run: () => {
              events.push('first');

              return Promise.resolve();
            },
          },
          {
            name: 'second',
            about: 'second',
            ready: () => {
              events.push('second ready');

              return Promise.resolve();
            },
            run: () => {
              events.push('second');

              return Promise.resolve();
            },
          },
          CHORD.steps.release.at(-1)!,
        ],
      },
    };

    await expect(
      runRelease(context(), found, ['first', 'second'], {}, MAC),
    ).rejects.toBe(failure);
    expect(events).toEqual([]);
    expect(ran()).toContain('npm whoami');
  });
});
