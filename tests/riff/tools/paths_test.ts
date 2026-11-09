import { describe, expect, test } from 'bun:test';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { isInside, shown } from '../../../src/riff/tools/paths.ts';

describe('where a path is', () => {
  test('inside is the directory itself or under it, never a sibling', () => {
    expect(isInside('/p/app', '/p/app')).toBe(true);
    expect(isInside('/p/app', '/p/app/src/a.ts')).toBe(true);
    expect(isInside('/p/app', '/p/app2/a.ts')).toBe(false);
    expect(isInside('/p/app', '/p/a.ts')).toBe(false);
    expect(isInside('/p/app', '/p/app/..x')).toBe(true);
  });

  test('shown relative inside, ~-shortened under home, absolute otherwise', () => {
    expect(shown('/p/app', '/p/app/src/a.ts')).toBe('src/a.ts');
    expect(shown('/p/app', '/p/app')).toBe('.');
    expect(shown('/p/app', join(homedir(), 'notes', 'todo.md'))).toBe(
      '~/notes/todo.md',
    );
    expect(shown('/p/app', '/etc/hosts')).toBe('/etc/hosts');
  });
});
