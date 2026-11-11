import { describe, expect, test } from 'bun:test';
import {
  pathView,
  shownDirectory,
  shownFile,
} from '../../../../src/ui/transcript/tools/paths.ts';

// The window's directory reached through a link, as macOS's /tmp is.
const linked = (path: string) => path.replace(/^\/tmp\//u, '/private/tmp/');
const view = pathView('/tmp/home/src/app', '/tmp/home', linked);

describe('paths as the window draws them (CHD-611)', () => {
  test('a view keeps each base as given and as its real path', () => {
    expect(view).toEqual({
      cwds: ['/tmp/home/src/app', '/private/tmp/home/src/app'],
      homes: ['/tmp/home', '/private/tmp/home'],
    });
    expect(pathView('/p', undefined, (path) => path)).toEqual({
      cwds: ['/p'],
      homes: [],
    });
  });

  test('a file is named from the session directory, by either path', () => {
    expect(shownFile('/tmp/home/src/app/greet.ts', view)).toBe('greet.ts');
    expect(shownFile('/private/tmp/home/src/app/src/a.ts', view)).toBe(
      'src/a.ts',
    );
    expect(shownFile('/private/tmp/home/src/app', view)).toBe('.');
  });

  test('outside it, from ~; elsewhere, whole', () => {
    expect(shownFile('/private/tmp/home/notes/todo.md', view)).toBe(
      '~/notes/todo.md',
    );
    expect(shownFile('/etc/hosts', view)).toBe('/etc/hosts');
    // A name that starts with two dots is still inside.
    expect(shownFile('/tmp/home/src/app/..hidden', view)).toBe('..hidden');
    expect(shownFile('/tmp/home/src/application/a.ts', view)).toBe(
      '~/src/application/a.ts',
    );
  });

  test('a directory is named as the header names one', () => {
    expect(shownDirectory('/private/tmp/home/src/app', view)).toBe('~/src/app');
    expect(shownDirectory('/tmp/home', view)).toBe('~');
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
