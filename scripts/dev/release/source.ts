/**
 * The source of what every binary statically links through OpenTUI's native
 * library, FFmpeg and zlib, offered beside a release as their licences ask:
 * fetched and checked against the sums the native package names when the
 * release is packed, so a dry run checks them too, then attached by publish to
 * a draft GitHub release, which the owner fills in and publishes.
 */
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
} from 'node:fs';
import { basename, join } from 'node:path';
import { loadedNative } from '../compile.ts';
import { TARGETS } from '../../targets.ts';
import { quote } from 'shell-quote';
import { channelOf } from '../../../src/channel.ts';
import { die, type Release, run, said } from './lib.ts';
import { sha256 } from './sums.ts';

/** Where the fetched archives are. */
export function sourceDir(release: Release): string {
  return join(release.root, 'dist', 'release', 'source');
}

/** One archive to fetch, and the sum its bytes must have. */
export interface SourceArchive {
  readonly url: string;
  readonly sha256: string;
}

/** The archives a native package's FFMPEG-SOURCE.md names, or none it can't. */
export function namedArchives(notes: string): readonly SourceArchive[] {
  const ffmpeg = /^- Source: (\S+)\n- SHA-256: `([0-9a-f]{64})`/m.exec(notes);
  const zlib = /^- zlib [^:\n]+: (\S+)\n- zlib SHA-256: `([0-9a-f]{64})`/m.exec(
    notes,
  );

  return [ffmpeg, zlib].flatMap((found) =>
    found === null ? [] : [{ url: found[1]!, sha256: found[2]! }],
  );
}

/**
 * What every target's native package names, which must be one and the same:
 * each binary embeds its own target's, and one archive stands for them all.
 */
function archives(release: Release): readonly SourceArchive[] {
  const notes = TARGETS.map((target) => {
    const path = join(
      release.root,
      'node_modules',
      loadedNative(target.os, target.cpu, undefined),
      'FFMPEG-SOURCE.md',
    );

    if (!existsSync(path)) {
      die(`no ${path} to read the source archives from`);
    }

    return readFileSync(path, 'utf8');
  });

  const named = namedArchives(notes[0]!);

  if (named.length !== 2) {
    die('FFMPEG-SOURCE.md no longer names the FFmpeg and zlib archives');
  }

  if (notes.some((each) => each !== notes[0])) {
    die('the native packages name different source archives');
  }

  return named;
}

/** Where an archive lies once fetched, by the name in its address. */
function archivePath(release: Release, { url }: SourceArchive): string {
  return join(sourceDir(release), basename(new URL(url).pathname));
}

/**
 * Fetches the archives. Each stays under a name of its own until its sum holds,
 * so a stop on the way leaves none that looks good.
 */
export function fetchSource(release: Release): void {
  const dir = sourceDir(release);
  const named = archives(release);

  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });

  for (const archive of named) {
    const { url, sha256: wanted } = archive;
    const path = archivePath(release, archive);
    const part = `${path}.part`;
    const fetched = run(release, 'curl', [
      '--fail',
      '--silent',
      '--show-error',
      '--location',
      '--output',
      part,
      url,
    ]);

    if (fetched.status !== 0) {
      die(`fetching ${url} failed: ${said(fetched.stderr)}`);
    }

    const sum = sha256(part);

    if (sum !== wanted) {
      rmSync(part, { force: true });
      die(`${url} has sha256 ${sum}; FFMPEG-SOURCE.md names ${wanted}`);
    }

    renameSync(part, path);
  }
}

/**
 * The archives a packed release holds: every one the native packages name now,
 * with the sum they name, whatever an earlier run left beside them.
 */
export function fetchedSource(release: Release): readonly string[] {
  return archives(release).map((archive) => {
    const path = archivePath(release, archive);

    if (!existsSync(path)) {
      die(`no ${path}: the source archives are fetched by the pack stage`);
    }

    const sum = sha256(path);

    if (sum !== archive.sha256) {
      die(
        `${path} has sha256 ${sum}; FFMPEG-SOURCE.md names ${archive.sha256}`,
      );
    }

    return path;
  });
}

/**
 * Stops unless `gh` can make the draft: found, and signed in. Asked before
 * anything irreversible, as the draft comes only after npm and the tag.
 */
export function ghReady(release: Release): void {
  const status = run(release, 'gh', ['auth', 'status']);

  if (status.status !== 0) {
    die(
      `\`gh auth status\` failed, and publishing makes a draft GitHub release with it: ${said(status.stderr)}`,
    );
  }
}

/**
 * A draft GitHub release of the tag with the archives attached. Never more
 * than a draft: the owner writes the notes and publishes it. A channel's is
 * marked a pre-release, so it cannot become the repository's latest release.
 * By then npm has the version and origin the tag, so a failure says how to
 * finish by hand.
 */
export function draftRelease(
  release: Release,
  version: string,
  files: readonly string[],
): void {
  const tag = `v${version}`;
  const args = [
    'release',
    'create',
    tag,
    '--draft',
    ...(channelOf(version) === null ? [] : ['--prerelease']),
    '--verify-tag',
    '--title',
    `chord ${tag}`,
    '--notes',
    '',
    ...files,
  ];
  const made = run(release, 'gh', args);

  if (made.status !== 0) {
    die(
      `${tag} is on npm and tagged, but its draft release failed: ${said(made.stderr)}\nFinish it with: ${quote(['gh', ...args])}`,
    );
  }

  release.out(`drafted ${tag}, with its source archives: ${said(made.stdout)}`);
}
