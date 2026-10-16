import { afterEach, beforeEach, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { type Scratch, scratch } from './scratch.ts';

// holdVersion's signal handling beside another listener registered after
// it, as selftest's cleanup is during a stage: both must run.

const GIT_ENV = {
  GIT_AUTHOR_NAME: 'release',
  GIT_AUTHOR_EMAIL: 'release@example.com',
  GIT_COMMITTER_NAME: 'release',
  GIT_COMMITTER_EMAIL: 'release@example.com',
};
const bump = join(import.meta.dir, '../../../../scripts/dev/release/bump.ts');

let at: Scratch;

beforeEach(() => {
  at = scratch();

  writeFileSync(join(at.root, 'package.json'), '{"version":"1.0.0"}\n');
  git('init', '-q', '-b', 'main');
  git('add', '-A');
  git('commit', '-q', '-m', 'start');
});

afterEach(() => {
  rmSync(at.place, { recursive: true, force: true });
});

function git(...args: string[]): string {
  const ran = spawnSync('git', args, {
    cwd: at.root,
    env: { ...process.env, ...GIT_ENV },
    encoding: 'utf8',
  });

  expect(ran.status).toBe(0);

  return ran.stdout.trim();
}

test.each(['SIGINT', 'SIGTERM', 'SIGHUP'])(
  '%s drops the commit and still runs a later cleanup listener',
  (signal) => {
    const head = git('rev-parse', 'HEAD');
    const cleaned = join(at.place, 'cleaned');
    const script = join(at.place, 'hold.ts');

    writeFileSync(
      script,
      `import { writeFileSync } from 'node:fs';
import { commitVersion, holdVersion } from ${JSON.stringify(bump)};

const release = {
  root: ${JSON.stringify(at.root)},
  env: process.env,
  sleep: () => Promise.resolve(),
  out: () => {},
  err: (line) => console.error(line),
  tty: true,
};

holdVersion(release, commitVersion(release, '1.1.0'));

// selftest's cleanup, as it registers it: clean up, remove, raise again.
const signals = ['SIGINT', 'SIGTERM', 'SIGHUP'];
const onSignal = (signal) => {
  writeFileSync(${JSON.stringify(cleaned)}, signal);

  for (const each of signals) {
    process.removeListener(each, onSignal);
  }

  process.kill(process.pid, signal);
};

for (const each of signals) {
  process.on(each, onSignal);
}

process.kill(process.pid, ${JSON.stringify(signal)});
await new Promise((resolve) => setTimeout(resolve, 5000));
`,
    );

    const child = spawnSync(process.execPath, [script], {
      cwd: at.root,
      env: { ...process.env, ...GIT_ENV },
      encoding: 'utf8',
    });

    expect(child.stderr).toBe('');
    expect(child.signal).toBe(signal);
    expect(existsSync(cleaned) && readFileSync(cleaned, 'utf8')).toBe(signal);
    expect(git('rev-parse', 'HEAD')).toBe(head);
    expect(git('status', '--porcelain')).toBe('');
  },
);
