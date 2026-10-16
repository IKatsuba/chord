/**
 * The tarballs' sha256 sums, recorded in SHA256SUMS beside them when they are
 * packed, in sha256sum's own format, so that only a tarball with the same
 * bytes is published, whichever run packed it.
 */
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { die } from './lib.ts';

export const SUMS = 'SHA256SUMS';

export function sha256(file: string): string {
  return createHash('sha256').update(readFileSync(file)).digest('hex');
}

/** Writes SHA256SUMS in `dir` for `files`, each a name in `dir`. */
export function recordSums(dir: string, files: readonly string[]): void {
  writeFileSync(
    join(dir, SUMS),
    files.map((file) => `${sha256(join(dir, file))}  ${file}\n`).join(''),
  );
}

/** Stops unless SHA256SUMS beside `tarball` records its sum as it is. */
export function checkSum(tarball: string): void {
  const sums = join(dirname(tarball), SUMS);
  let recorded: string | undefined;

  try {
    recorded = readFileSync(sums, 'utf8')
      .split('\n')
      .map((line) => /^([0-9a-f]{64}) [ *](.+)$/.exec(line))
      .find((match) => match?.[2] === basename(tarball))?.[1];
  } catch {
    recorded = undefined;
  }

  if (recorded === undefined) {
    die(`${sums} has no sum for ${tarball}`);
  }

  const actual = sha256(tarball);

  if (actual !== recorded) {
    die(`${tarball} has sha256 ${actual}; ${SUMS} recorded ${recorded}`);
  }
}
