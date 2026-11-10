/** A second process in the late-write lock trial; all credentials are fixtures. */
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import process from 'node:process';
import { check } from 'proper-lockfile';
import { withCredentialLock } from '../../src/riff/credential_lock.ts';

const [, , root, entry] = process.argv;

assert(root !== undefined && entry !== undefined);

const held = await check(join(root, 'riff', 'credentials', 'codex'), {
  realpath: false,
});

process.stdout.write(`held:${String(held)}\n`);
await withCredentialLock(root, 'codex', 'Secret Service', async () => {
  const value: unknown = JSON.parse(await readFile(entry, 'utf8'));

  assert.deepEqual(value, { accessToken: 'next', accountId: 'fixture' });
  await writeFile(
    entry,
    JSON.stringify({ accessToken: 'third', accountId: 'fixture' }),
  );
  process.stdout.write('refreshed\n');
});
