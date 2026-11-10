import { expect, test } from 'bun:test';
import { execFile } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { currentBranch } from '../../../src/riff/review/current_branch.ts';

test('git supplies the current branch and non-repositories supply none', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'chord-review-branch-'));
  const signal = new AbortController().signal;

  try {
    expect(await currentBranch(directory, signal)).toBeUndefined();

    await promisify(execFile)('git', [
      'init',
      '--initial-branch=review-fixture',
      directory,
    ]);

    expect(await currentBranch(directory, signal)).toBe('review-fixture');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
