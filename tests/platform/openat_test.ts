import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import {
  closeSync,
  constants,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { constants as system, tmpdir } from 'node:os';
import { join } from 'node:path';
import { openAt } from '../../src/platform/openat.ts';

describe('openAt', () => {
  function inDirectory(run: (dir: number, path: string) => void) {
    const path = mkdtempSync(join(tmpdir(), 'chord-openat-'));
    const dir = openSync(path, constants.O_RDONLY | constants.O_DIRECTORY);

    try {
      run(dir, path);
    } finally {
      closeSync(dir);
      rmSync(path, { recursive: true });
    }
  }

  const NOFOLLOW = constants.O_RDONLY | constants.O_NOFOLLOW;

  test('this platform has it', () => {
    expect(openAt()).toBeDefined();
  });

  test('opens a name inside the directory handle', () => {
    inDirectory((dir, path) => {
      writeFileSync(join(path, 'f'), 'held');

      const opened = openAt()!(dir, 'f', NOFOLLOW);

      assert('fd' in opened);
      expect(readFileSync(opened.fd, 'utf8')).toBe('held');
      closeSync(opened.fd);
    });
  });

  test('a name with no file says ENOENT, a link ELOOP', () => {
    inDirectory((dir, path) => {
      symlinkSync(join(path, 'elsewhere'), join(path, 'l'));

      expect(openAt()!(dir, 'none', NOFOLLOW)).toStrictEqual({
        errno: system.errno.ENOENT,
      });
      expect(openAt()!(dir, 'l', NOFOLLOW)).toStrictEqual({
        errno: system.errno.ELOOP,
      });
    });
  });

  test('a name is taken inside the handle, not through a moved path', () => {
    inDirectory((dir, path) => {
      mkdirSync(join(path, 'sub'));

      const sub = openSync(join(path, 'sub'), constants.O_RDONLY);

      writeFileSync(join(path, 'sub', 'f'), 'inside');
      writeFileSync(join(path, 'f'), 'outside');

      const opened = openAt()!(sub, 'f', NOFOLLOW);

      assert('fd' in opened);
      expect(readFileSync(opened.fd, 'utf8')).toBe('inside');
      closeSync(opened.fd);
      closeSync(sub);
    });
  });
});
