import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  mkdtempSync,
  readlinkSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { executable } from './scratch.ts';

describe('CHD-501 tester: cached executable isolation', () => {
  test('cold and warm links share bytes while each invocation keeps its own environment and cwd', () => {
    const dir = mkdtempSync(join(tmpdir(), 'chord-cache-test-'));
    const body = `#!/bin/sh\n# ${crypto.randomUUID()}\nprintf '%s:%s' "$MARK" "$PWD"\n`;
    const first = join(dir, 'first');
    const second = join(dir, 'second');

    try {
      executable(first, body);

      const cached = readlinkSync(first);
      const before = statSync(cached);

      executable(second, body);
      expect(readlinkSync(second)).toBe(cached);
      expect(statSync(cached).mtimeMs).toBe(before.mtimeMs);
      expect(statSync(cached).mode & 0o777).toBe(0o555);

      for (const [path, mark, cwd] of [
        [first, 'one', dir],
        [second, 'two', tmpdir()],
      ] as const) {
        const run = spawnSync(path, [], {
          cwd,
          env: { ...process.env, MARK: mark },
          encoding: 'utf8',
        });

        expect(run.status).toBe(0);
        expect(run.stdout).toBe(`${mark}:${realpathSync(cwd)}`);
      }
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test('replacing a plain file or a link changes only that scratch path', () => {
    const dir = mkdtempSync(join(tmpdir(), 'chord-cache-test-'));
    const first = join(dir, 'first');
    const second = join(dir, 'second');
    const original = `#!/bin/sh\n# ${crypto.randomUUID()}\nprintf old\n`;

    try {
      writeFileSync(first, 'not executable');
      executable(first, original);
      executable(second, original);

      const shared = readlinkSync(second);

      executable(first, '#!/bin/sh\nprintf new\n');
      expect(readlinkSync(first)).not.toBe(shared);
      expect(readlinkSync(second)).toBe(shared);
      expect(spawnSync(first, [], { encoding: 'utf8' }).stdout).toBe('new');
      expect(spawnSync(second, [], { encoding: 'utf8' }).stdout).toBe('old');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
