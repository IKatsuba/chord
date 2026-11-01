import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { ReleaseError } from '../../../../scripts/dev/release/lib.ts';
import {
  draftRelease,
  fetchedSource,
  fetchSource,
  ghReady,
  namedArchives,
  sourceDir,
} from '../../../../scripts/dev/release/source.ts';
import {
  FFMPEG_URL,
  nativeNotes,
  type Scratch,
  scratch,
  SOURCE_NOTES,
  ZLIB_URL,
} from './scratch.ts';

// The source archives beside a release, curl and gh faked: nothing here reaches
// ffmpeg.org or GitHub.

let at: Scratch;

beforeEach(() => {
  at = scratch();

  nativeNotes(at.root);
});

afterEach(() => {
  rmSync(at.place, { recursive: true, force: true });
});

function died(run: () => unknown): string {
  try {
    run();
  } catch (error) {
    if (error instanceof ReleaseError) {
      return error.message;
    }

    throw error;
  }

  throw new Error('it did not die');
}

describe('reading the archives a native package names', () => {
  test('FFmpeg and zlib with their sums, and not the build tool', () => {
    expect(namedArchives(SOURCE_NOTES).map(({ url }) => url)).toStrictEqual([
      FFMPEG_URL,
      ZLIB_URL,
    ]);
  });

  test('notes that no longer name them stop the release', () => {
    nativeNotes(at.root, '# FFmpeg\n\nGone elsewhere.\n');

    expect(died(() => fetchSource(at.release))).toContain('no longer names');
  });

  test('native packages that disagree stop the release', () => {
    writeFileSync(
      join(
        at.root,
        'node_modules',
        '@opentui',
        'core-linux-x64',
        'FFMPEG-SOURCE.md',
      ),
      `${SOURCE_NOTES}\nA later build.\n`,
    );

    expect(died(() => fetchSource(at.release))).toContain('different');
  });

  test('a missing native package stops the release', () => {
    rmSync(join(at.root, 'node_modules'), { recursive: true });

    expect(died(() => fetchSource(at.release))).toContain('FFMPEG-SOURCE.md');
  });
});

describe('fetching them', () => {
  test('good sums keep both archives', () => {
    fetchSource(at.release);

    expect(
      fetchedSource(at.release).map((file) => file.split('/').at(-1)),
    ).toEqual(['ffmpeg-9.0.2.tar.xz', 'zlib-1.3.2.tar.gz']);
  });

  test('a sum that differs stops the release and keeps nothing that looks good', () => {
    at.fake('curl', 'printf tampered >"${@: -2:1}"\n');

    expect(died(() => fetchSource(at.release))).toContain('names');
    expect(
      existsSync(join(sourceDir(at.release), 'ffmpeg-9.0.2.tar.xz')),
    ).toBeFalse();
    expect(
      existsSync(join(sourceDir(at.release), 'ffmpeg-9.0.2.tar.xz.part')),
    ).toBeFalse();
  });

  test('a failed download stops the release', () => {
    at.fake('curl', "echo 'curl: (22) 404' >&2\nexit 22\n");

    expect(died(() => fetchSource(at.release))).toContain('404');
    expect(fetchedSourceThrows()).toBeTrue();
  });

  test('a signal on the way leaves no archive that passes as fetched', () => {
    at.fake('curl', 'printf half >"${@: -2:1}"\nkill -TERM $$\n');

    expect(died(() => fetchSource(at.release))).toContain('failed');
    expect(fetchedSourceThrows()).toBeTrue();
    expect(
      existsSync(join(sourceDir(at.release), 'ffmpeg-9.0.2.tar.xz')),
    ).toBeFalse();
  });

  test('a rerun starts over from whatever a stopped one left', () => {
    at.fake('curl', 'printf half >"${@: -2:1}"\nkill -TERM $$\n');
    died(() => fetchSource(at.release));
    rmSync(join(at.bin, 'curl'));
    at.fake('curl', 'printf "source of %s" "${@: -1}" >"${@: -2:1}"\n');
    fetchSource(at.release);

    expect(fetchedSource(at.release)).toHaveLength(2);
    expect(
      existsSync(join(sourceDir(at.release), 'ffmpeg-9.0.2.tar.xz.part')),
    ).toBeFalse();
  });

  const fetchedSourceThrows = () => {
    try {
      fetchedSource(at.release);

      return false;
    } catch {
      return true;
    }
  };
});

describe('the draft', () => {
  const log = () => readFileSync(join(at.place, 'gh.log'), 'utf8');

  test('is only ever a draft, on the tag, with what was fetched', () => {
    fetchSource(at.release);
    draftRelease(at.release, '9.9.9', fetchedSource(at.release));

    expect(log()).toStartWith(
      'release create v9.9.9 --draft --verify-tag --title chord v9.9.9 --notes ',
    );
    expect(log()).toContain('ffmpeg-9.0.2.tar.xz');
    expect(log()).not.toContain('edit');
  });

  test('gh signed in passes; signed out or missing stops', () => {
    expect(() => ghReady(at.release)).not.toThrow();

    at.fake('gh', 'echo "not logged in" >&2\nexit 1\n');

    expect(died(() => ghReady(at.release))).toContain('not logged in');
  });
});
