import { afterEach, beforeEach, expect, test } from 'bun:test';
import { mkdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { npm, ReleaseError } from '../../../../scripts/dev/release/lib.ts';
import { type Scratch, scratch } from './scratch.ts';

// npm run on node, past the `node` Bun puts first on PATH under `bun run`:
// here a symlink to the Bun running the tests, as Bun's own is.

let at: Scratch;
let bunNode: string;

beforeEach(() => {
  at = scratch();
  bunNode = join(at.place, 'bun-node');

  mkdirSync(bunNode);
  symlinkSync(process.execPath, join(bunNode, 'node'));
  at.fake('npm', 'echo "npm on bash: $*"\n');
});

afterEach(() => {
  rmSync(at.place, { recursive: true, force: true });
});

function on(path: string[]) {
  return { ...at.release, env: { ...at.release.env, PATH: path.join(':') } };
}

test("runs npm's script on the first node that is not Bun", () => {
  const ran = npm(on([bunNode, at.bin]), ['whoami']);

  expect(ran.status).toBe(0);
  expect(ran.stdout).toBe('npm on bash: whoami\n');
});

test("dies when the only node on PATH is Bun's", () => {
  writeFileSync(join(bunNode, 'npm'), '#!/bin/bash\n', { mode: 0o755 });

  expect(() => npm(on([bunNode]), ['whoami'])).toThrow(
    new ReleaseError(
      "no node other than Bun's on PATH; npm runs on node (bun run dev puts Bun first as node, docs/decisions.md)",
    ),
  );
});

test('dies when no npm is on PATH', () => {
  rmSync(join(at.bin, 'npm'));

  expect(() => npm(on([bunNode, at.bin]), ['whoami'])).toThrow(
    new ReleaseError(
      "no npm other than Bun's on PATH; npm runs on node (bun run dev puts Bun first as node, docs/decisions.md)",
    ),
  );
});
