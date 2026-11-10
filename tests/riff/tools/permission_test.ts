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
const edit = { tool: 'edit', real: '/p/app/src/a.ts' } as const;
const write = { tool: 'write', real: edit.real } as const;
const shell = { tool: 'shell', command: 'ls' } as const;

describe('when riff asks', () => {
  test('in ask every call asks', () => {
    for (const reach of [inside, outside, list, search, edit, write, shell]) {
      expect(asks('ask', reach, '/p/app', new Set())).toBe(true);
    }
  });

  test('auto admits ordinary inside mutations, asks on sensitive or outside paths and every shell', () => {
    for (const tool of ['edit', 'write'] as const) {
      expect(asks('auto', { tool, real: edit.real }, '/p/app', new Set())).toBe(
        false,
      );

      for (const real of [
        '/p/app/.env.local',
        '/p/app/.git/config',
        '/p/elsewhere/a.ts',
      ]) {
        expect(asks('auto', { tool, real }, '/p/app', new Set())).toBe(true);
      }
    }

    expect(asks('auto', shell, '/p/app', new Set())).toBe(true);
  });

  test('edit and write share an exact real-path grant; shell commands are exact', () => {
    const grants = new Set([
      grantKey(edit, '/p/app'),
      grantKey(shell, '/p/app'),
    ]);

    expect(grantKey(edit, '/p/app')).toBe(grantKey(write, '/p/app'));
    expect(grantKey(shell, '/p/app')).toBe('shell:ls');

    for (const mode of ['ask', 'auto'] as const) {
      expect(asks(mode, edit, '/p/app', grants)).toBe(false);
      expect(asks(mode, write, '/p/app', grants)).toBe(false);
      expect(asks(mode, shell, '/p/app', grants)).toBe(false);
      expect(
        asks(mode, { tool: 'edit', real: '/outside/a.ts' }, '/p/app', grants),
      ).toBe(true);
      expect(
        asks(mode, { tool: 'shell', command: 'ls -la' }, '/p/app', grants),
      ).toBe(true);
    }

    expect(asks('ask', inside, '/p/app', grants)).toBe(true);
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

  test('mutation and command grants say what they cover', () => {
    expect(names(edit)[1]).toEqual([
      'Allow edits to src/a.ts for this session',
      'allow_always',
    ]);
    expect(names(write)[1]).toEqual([
      'Allow edits to src/a.ts for this session',
      'allow_always',
    ]);
    expect(names(shell)[1]).toEqual([
      'Allow this exact command for this session',
      'allow_always',
    ]);
  });

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

describe('CHD-605 tester: grants cover only the approved reach', () => {
  test('a shell grant covers neither a shorter nor a longer command string', () => {
    const command = 'printf hello';
    const grants = new Set([grantKey({ tool: 'shell', command }, '/p/app')]);

    for (const mode of ['ask', 'auto'] as const) {
      expect(asks(mode, { tool: 'shell', command }, '/p/app', grants)).toBe(
        false,
      );

      for (const other of [
        'printf',
        'printf hell',
        'printf hello world',
        'printf hello\n',
        ' printf hello',
        'printf  hello',
      ]) {
        expect(
          asks(mode, { tool: 'shell', command: other }, '/p/app', grants),
        ).toBe(true);
      }
    }
  });

  test('an outside mutation grant covers both operations on that file alone', () => {
    const real = '/outside/notes.txt';
    const grants = new Set([grantKey({ tool: 'write', real }, '/p/app')]);

    for (const mode of ['ask', 'auto'] as const) {
      for (const tool of ['edit', 'write'] as const) {
        expect(asks(mode, { tool, real }, '/p/app', grants)).toBe(false);

        for (const other of ['/outside', `${real}.bak`, `${real}/child`]) {
          expect(asks(mode, { tool, real: other }, '/p/app', grants)).toBe(
            true,
          );
        }
      }

      expect(asks(mode, { tool: 'read', real }, '/p/app', grants)).toBe(true);
    }
  });

  test('a grant in one session cannot admit the same reach in another', () => {
    const reach = { tool: 'write', real: '/p/app/.env.local' } as const;
    const first = new Set([grantKey(reach, '/p/app')]);
    const second = new Set<string>();

    for (const mode of ['ask', 'auto'] as const) {
      expect(asks(mode, reach, '/p/app', first)).toBe(false);
      expect(asks(mode, reach, '/p/app', second)).toBe(true);
    }
  });
});
