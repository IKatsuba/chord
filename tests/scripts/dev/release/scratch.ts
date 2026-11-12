import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { loadedNative } from '../../../../scripts/dev/compile.ts';
import { TARGETS } from '../../../../scripts/targets.ts';
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  renameSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Release } from '../../../../scripts/dev/release/lib.ts';

/**
 * The environment of every git a release test runs, and of the release under
 * test: its own identity, and never the person's or the machine's git config.
 * A CI runner has no identity, and a global commit.gpgsign would sign every
 * scratch commit with the person's key.
 */
export const GIT_ENV = {
  GIT_CONFIG_GLOBAL: '/dev/null',
  GIT_CONFIG_NOSYSTEM: '1',
  GIT_AUTHOR_NAME: 'release',
  GIT_AUTHOR_EMAIL: 'release@example.com',
  GIT_COMMITTER_NAME: 'release',
  GIT_COMMITTER_EMAIL: 'release@example.com',
};

/**
 * What git prints for `args` in `cwd`, under GIT_ENV, trimmed. A git that
 * fails throws with its stderr: a read that failed would print nothing, and an
 * assertion that expects nothing would pass on it.
 */
export function gitRead(cwd: string, ...args: string[]): string {
  const child = spawnSync('git', args, {
    cwd,
    env: { ...process.env, ...GIT_ENV },
    encoding: 'utf8',
  });

  if (child.status !== 0) {
    throw new Error(`git ${args.join(' ')}: ${child.stderr}`);
  }

  return child.stdout.trim();
}

/** Where each executable a test fakes is written once, by its content. */
const EXECUTABLES = join(tmpdir(), 'chord-test-executables');

/**
 * An executable at `path` that runs `body`: a link to the one copy of
 * those bytes, written once per machine. macOS checks an executable the first
 * time it runs, about a quarter of a second each, and a test that wrote its
 * fakes afresh paid that for each of them; a link to one already run is not
 * checked again. Each test keeps its own directory (CHD-501).
 */
export function executable(path: string, body: string): void {
  const file = join(
    EXECUTABLES,
    createHash('sha256').update(body).digest('hex').slice(0, 32),
  );

  if (!existsSync(file)) {
    mkdirSync(EXECUTABLES, { recursive: true });

    // Whole or not there: the test workers write it side by side.
    const temporary = `${file}.${process.pid}.${crypto.randomUUID()}`;

    // Read-only: a write through a link fails rather than changing every test's copy.
    writeFileSync(temporary, body, { mode: 0o555 });
    chmodSync(temporary, 0o555);
    renameSync(temporary, file);
  }

  // A fake made again in the same test takes the place of the one before.
  rmSync(path, { force: true });
  symlinkSync(file, path);
}

/** The archives the native packages name here, and what curl fetches of them. */
export const FFMPEG_URL = 'https://ffmpeg.example/releases/ffmpeg-9.0.2.tar.xz';
export const ZLIB_URL = 'https://zlib.example/fossils/zlib-1.3.2.tar.gz';

const fetched = (url: string) => `source of ${url}`;
const hash = (text: string) => createHash('sha256').update(text).digest('hex');

/** FFMPEG-SOURCE.md as OpenTUI's native packages lay it out. */
export const SOURCE_NOTES = `# FFmpeg

- Source: ${FFMPEG_URL}
- SHA-256: \`${hash(fetched(FFMPEG_URL))}\`
- License: LGPL-2.1-or-later (\`COPYING.LGPLv2.1\`)
- zlib 1.3.2: ${ZLIB_URL}
- zlib SHA-256: \`${hash(fetched(ZLIB_URL))}\`
- NASM 3.02 (not linked): https://nasm.example/nasm-3.02.tar.xz
`;

/** Every target's native package under `root`, with `notes`. */
export function nativeNotes(root: string, notes = SOURCE_NOTES): void {
  for (const target of TARGETS) {
    const dir = join(
      root,
      'node_modules',
      loadedNative(target.os, target.cpu, undefined),
    );

    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'FFMPEG-SOURCE.md'), notes);
  }
}

/** What a pack run leaves in dist/release/source/ under `root`. */
export function fetchedArchives(root: string): void {
  const dir = join(root, 'dist', 'release', 'source');

  mkdirSync(dir, { recursive: true });

  for (const url of [FFMPEG_URL, ZLIB_URL]) {
    writeFileSync(join(dir, url.slice(url.lastIndexOf('/') + 1)), fetched(url));
  }
}

/**
 * A release on a scratch directory: its root, a bin directory first on PATH
 * for the commands a test fakes, and what it printed and slept.
 */
export interface Scratch {
  readonly place: string;
  readonly root: string;
  readonly bin: string;
  readonly out: string[];
  readonly err: string[];
  readonly sleeps: number[];
  readonly release: Release;
  /** Puts a bash script on PATH as `name`. */
  fake(name: string, body: string): void;
}

export function scratch(): Scratch {
  const place = mkdtempSync(join(tmpdir(), 'chord-release-'));
  const root = join(place, 'root');
  const bin = join(place, 'bin');
  const out: string[] = [];
  const err: string[] = [];
  const sleeps: number[] = [];

  mkdirSync(root);
  mkdirSync(bin);
  // npm runs as `node <npm>`: this node runs a faked npm with bash.
  executable(join(bin, 'node'), '#!/bin/bash\nexec /bin/bash "$@"\n');
  // Nothing here reaches GitHub or the network: `gh` logs what it was asked,
  // `curl` writes what the notes' sums expect.
  executable(
    join(bin, 'gh'),
    `#!/bin/bash\nprintf '%s\\n' "$*" >>'${join(place, 'gh.log')}'\necho https://github.example/draft\n`,
  );
  executable(
    join(bin, 'curl'),
    `#!/bin/bash\nprintf 'source of %s' "\${@: -1}" >"\${@: -2:1}"\n`,
  );

  return {
    place,
    root,
    bin,
    out,
    err,
    sleeps,
    release: {
      root,
      env: { ...process.env, PATH: `${bin}:${process.env.PATH ?? ''}` },
      sleep: (ms) => {
        sleeps.push(ms);

        return Promise.resolve();
      },
      out: (line) => out.push(line),
      err: (line) => err.push(line),
      tty: true,
    },
    fake(name, body) {
      executable(join(bin, name), `#!/bin/bash\n${body}`);
    },
  };
}
