import { describe, expect, test } from 'bun:test';
import {
  pathView,
  shownDirectory,
  shownFile,
} from '../../../../src/ui/transcript/tools/paths.ts';

// The window's directory reached through a link, as macOS's /tmp is.
const linked = (path: string) => path.replace(/^\/tmp\//u, '/private/tmp/');
const view = pathView('/tmp/qa-home/src/app', '/tmp/qa-home', linked);

describe('paths as the window draws them (CHD-611)', () => {
  test('a view keeps each base as given and as its real path', () => {
    expect(view).toEqual({
      cwds: ['/tmp/qa-home/src/app', '/private/tmp/qa-home/src/app'],
      homes: ['/tmp/qa-home', '/private/tmp/qa-home'],
    });
    expect(pathView('/p', undefined, (path) => path)).toEqual({
      cwds: ['/p'],
      homes: [],
    });
  });

  test('a file is named from the session directory, by either path', () => {
    expect(shownFile('/tmp/qa-home/src/app/greet.ts', view)).toBe('greet.ts');
    expect(shownFile('/private/tmp/qa-home/src/app/src/a.ts', view)).toBe(
      'src/a.ts',
    );
    expect(shownFile('/private/tmp/qa-home/src/app', view)).toBe('.');
  });

  test('outside it, from ~; elsewhere, whole', () => {
    expect(shownFile('/private/tmp/qa-home/notes/todo.md', view)).toBe(
      '~/notes/todo.md',
    );
    expect(shownFile('/etc/hosts', view)).toBe('/etc/hosts');
    // A name that starts with two dots is still inside.
    expect(shownFile('/tmp/qa-home/src/app/..hidden', view)).toBe('..hidden');
    expect(shownFile('/tmp/qa-home/src/application/a.ts', view)).toBe(
      '~/src/application/a.ts',
    );
  });

  test('the session directory through its link reads as the header writes it', () => {
    const outside = pathView('/tmp/qa', '/tmp/qa-elsewhere', linked);

    expect(shownDirectory('/private/tmp/qa', outside)).toBe('/tmp/qa');
    expect(shownDirectory('/private/tmp/qa/src', outside)).toBe('/tmp/qa/src');
    expect(shownDirectory('/private/tmp/other', outside)).toBe(
      '/private/tmp/other',
    );
  });

  test('a directory is named as the header names one', () => {
    expect(shownDirectory('/private/tmp/qa-home/src/app', view)).toBe(
      '~/src/app',
    );
    expect(shownDirectory('/tmp/qa-home', view)).toBe('~');
    expect(shownDirectory('/srv/build', view)).toBe('/srv/build');
  });

  test('a path that came relative is drawn as it came', () => {
    expect(shownFile('src/greeting.ts', view)).toBe('src/greeting.ts');
    expect(shownDirectory('build', view)).toBe('build');
  });

  test('with no view, each path is drawn as it came', () => {
    expect(shownFile('/a/b.ts', undefined)).toBe('/a/b.ts');
    expect(shownDirectory('/a', undefined)).toBe('/a');
  });
});

describe('CHD-611 tester: display path boundaries', () => {
  test('relative spelling is preserved, including parent segments and tilde text', () => {
    for (const path of [
      '',
      '.',
      '..',
      '../notes.txt',
      './src/../a.ts',
      '~/notes.txt',
    ]) {
      expect(shownFile(path, view)).toBe(path);
      expect(shownDirectory(path, view)).toBe(path);
    }
  });

  test('a sibling sharing the home prefix stays absolute', () => {
    const path = '/tmp/qa-home-other/notes.txt';

    expect(shownFile(path, view)).toBe(path);
    expect(shownDirectory(path, view)).toBe(path);
  });

  test('home and session roots have distinct file and directory spellings', () => {
    const same = pathView('/tmp/qa-home', '/tmp/qa-home', (path) => path);

    expect(shownFile('/tmp/qa-home', same)).toBe('.');
    expect(shownDirectory('/tmp/qa-home', same)).toBe('~');
    expect(shownFile('/tmp/qa-home/a.ts', same)).toBe('a.ts');
    expect(shownDirectory('/tmp/qa-home/src', same)).toBe('~/src');
  });

  test('independent session views do not share their bases', () => {
    const first = pathView('/fixture/one', undefined, (path) => path);
    const second = pathView('/fixture/two', undefined, (path) => path);

    expect(shownFile('/fixture/one/a.ts', first)).toBe('a.ts');
    expect(shownFile('/fixture/one/a.ts', second)).toBe('/fixture/one/a.ts');
    expect(shownDirectory('/fixture/two', first)).toBe('/fixture/two');
    expect(first.cwds).toEqual(['/fixture/one']);
    expect(second.cwds).toEqual(['/fixture/two']);
  });

  test('spaces and Unicode remain intact after shortening', () => {
    expect(
      shownFile('/private/tmp/qa-home/src/app/notes/été one.ts', view),
    ).toBe('notes/été one.ts');
    expect(
      shownDirectory('/private/tmp/qa-home/src/app/build output', view),
    ).toBe('~/src/app/build output');
  });
});
