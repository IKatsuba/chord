import { expect, test } from 'bun:test';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';
import { NATIVE_NOTICES } from '../../../scripts/dev/npm.ts';
import { loadedNative } from '../../../scripts/dev/compile.ts';

test('the native library a binary embeds carries every notice its npm package passes on', () => {
  const native = join(
    'node_modules',
    loadedNative(process.platform, process.arch, process.env['OPENTUI_LIBC']),
  );

  for (const notice of NATIVE_NOTICES) {
    expect(existsSync(join(native, notice))).toBe(true);
  }
});
