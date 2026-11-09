import { describe, expect, test } from 'bun:test';
import { homedir } from 'node:os';
import { join } from 'node:path';
import {
  asks,
  grantKey,
  permissionOptions,
} from '../../../src/riff/tools/permission.ts';

const inside = { tool: 'read', real: '/p/app/src/a.ts' } as const;
const outside = { tool: 'read', real: '/etc/hosts' } as const;
const list = { tool: 'list' } as const;
const search = { tool: 'search' } as const;

describe('when riff asks', () => {
  test('in ask every call asks', () => {
    for (const reach of [inside, outside, list, search]) {
      expect(asks('ask', reach, '/p/app', new Set())).toBe(true);
    }
  });

  test('in auto only a read outside the directory asks', () => {
    expect(asks('auto', inside, '/p/app', new Set())).toBe(false);
    expect(asks('auto', list, '/p/app', new Set())).toBe(false);
    expect(asks('auto', search, '/p/app', new Set())).toBe(false);
    expect(asks('auto', outside, '/p/app', new Set())).toBe(true);
    expect(
      asks('auto', { tool: 'read', real: '/p/app2/a.ts' }, '/p/app', new Set()),
    ).toBe(true);
  });

  test('a grant holds in both modes, for its own reach alone', () => {
    const grants = new Set([
      grantKey(outside, '/p/app'),
      grantKey(list, '/p/app'),
    ]);

    for (const mode of ['ask', 'auto'] as const) {
      expect(asks(mode, outside, '/p/app', grants)).toBe(false);
      expect(asks(mode, list, '/p/app', grants)).toBe(false);
    }

    // A list grant does not cover search, nor one file's another.
    expect(asks('ask', search, '/p/app', grants)).toBe(true);
    expect(
      asks('ask', { tool: 'read', real: '/etc/passwd' }, '/p/app', grants),
    ).toBe(true);
  });

  test("a grant is kept on a read's real path, or the directory", () => {
    expect(grantKey(outside, '/p/app')).toBe('read:/etc/hosts');
    expect(grantKey(list, '/p/app')).toBe('list:/p/app');
    expect(grantKey(search, '/p/app')).toBe('search:/p/app');
  });
});

describe('what an ask offers', () => {
  const names = (reach: Parameters<typeof permissionOptions>[0]) =>
    permissionOptions(reach, '/p/app').map(({ name, kind }) => [name, kind]);

  test('a read names its real path: relative inside, ~ under home, else absolute', () => {
    expect(names(inside)).toStrictEqual([
      ['Allow', 'allow_once'],
      ['Allow reads of src/a.ts for this session', 'allow_always'],
      ['Deny', 'reject_once'],
    ]);
    expect(
      names({ tool: 'read', real: join(homedir(), 'notes', 'todo.md') })[1],
    ).toStrictEqual([
      'Allow reads of ~/notes/todo.md for this session',
      'allow_always',
    ]);
    expect(names(outside)[1]?.[0]).toBe(
      'Allow reads of /etc/hosts for this session',
    );
  });

  test('list and search say every one in this directory', () => {
    expect(names(list)[1]?.[0]).toBe(
      'Allow every list in this directory for this session',
    );
    expect(names(search)[1]?.[0]).toBe(
      'Allow every search in this directory for this session',
    );
  });
});
