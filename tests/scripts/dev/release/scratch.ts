import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Release } from '../../../../scripts/dev/release/lib.ts';

/**
 * A release on a scratch directory: its root, a bin directory first on PATH
 * for the commands a test fakes, and what it printed and slept.
 */
export interface Scratch {
  readonly place: string;
  readonly root: string;
  readonly bin: string;
  readonly out: string[];
  readonly err: string[];
  readonly sleeps: number[];
  readonly release: Release;
  /** Puts a bash script on PATH as `name`. */
  fake(name: string, body: string): void;
}

export function scratch(): Scratch {
  const place = mkdtempSync(join(tmpdir(), 'chord-release-'));
  const root = join(place, 'root');
  const bin = join(place, 'bin');
  const out: string[] = [];
  const err: string[] = [];
  const sleeps: number[] = [];

  mkdirSync(root);
  mkdirSync(bin);
  // npm runs as `node <npm>`: this node runs a faked npm with bash.
  writeFileSync(join(bin, 'node'), '#!/bin/bash\nexec /bin/bash "$@"\n');
  chmodSync(join(bin, 'node'), 0o755);

  return {
    place,
    root,
    bin,
    out,
    err,
    sleeps,
    release: {
      root,
      env: { ...process.env, PATH: `${bin}:${process.env.PATH ?? ''}` },
      sleep: (ms) => {
        sleeps.push(ms);

        return Promise.resolve();
      },
      out: (line) => out.push(line),
      err: (line) => err.push(line),
      tty: true,
    },
    fake(name, body) {
      writeFileSync(join(bin, name), `#!/bin/bash\n${body}`);
      chmodSync(join(bin, name), 0o755);
    },
  };
}
