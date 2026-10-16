import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  mkdirSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
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

describe('tester: npm executable selection boundaries', () => {
  test('Bun masquerading as npm is skipped as well as Bun masquerading as node', () => {
    symlinkSync(process.execPath, join(bunNode, 'npm'));

    const ran = npm(on([bunNode, at.bin]), ['whoami']);

    expect(ran.status).toBe(0);
    expect(ran.stdout).toBe('npm on bash: whoami\n');
  });

  test('directories and broken symlinks on PATH do not hide valid executables', () => {
    const directory = join(at.place, 'directories');
    const broken = join(at.place, 'broken');

    mkdirSync(directory);
    mkdirSync(broken);

    for (const name of ['node', 'npm']) {
      mkdirSync(join(directory, name));
      symlinkSync(join(at.place, 'missing'), join(broken, name));
    }

    const ran = npm(on([directory, broken, bunNode, at.bin]), ['whoami']);

    expect(ran.status).toBe(0);
    expect(ran.stdout).toBe('npm on bash: whoami\n');
  });

  test('a nonexecutable node is skipped for the next node on PATH', () => {
    const blocked = join(at.place, 'blocked');

    mkdirSync(blocked);
    writeFileSync(join(blocked, 'node'), '#!/bin/bash\nexit 99\n', {
      mode: 0o644,
    });

    const ran = npm(on([blocked, at.bin]), ['whoami']);

    expect(ran.status).toBe(0);
    expect(ran.stdout).toBe('npm on bash: whoami\n');
  });

  test('the selected npm script realpath remains one argument when it has spaces', () => {
    const script = join(at.place, 'npm fixture with spaces');

    writeFileSync(script, '#!/bin/bash\nprintf "<%s>\\n" "$@"\n', {
      mode: 0o755,
    });
    rmSync(join(at.bin, 'npm'));
    symlinkSync(script, join(at.bin, 'npm'));
    at.fake('node', 'printf "script=<%s>\\n" "$1"\nexec /bin/bash "$@"\n');

    const ran = npm(on([bunNode, at.bin]), ['pack', 'package with spaces']);

    expect(ran.status).toBe(0);
    expect(ran.stdout).toBe(
      `script=<${realpathSync(script)}>\n<pack>\n<package with spaces>\n`,
    );
  });

  test('npm receives the specified cwd, environment and literal arguments', () => {
    at.fake('npm', 'printf "<%s>\\n" "$PWD" "$FIXTURE_VALUE" "$@"\n');

    const ctx = on([bunNode, at.bin]);
    const ran = npm(
      { ...ctx, env: { ...ctx.env, FIXTURE_VALUE: 'fixture environment' } },
      ['pack', 'tarball with spaces', '$(must stay literal)'],
      { cwd: at.place },
    );

    expect(ran.status).toBe(0);
    expect(ran.stdout).toBe(
      `<${realpathSync(at.place)}>\n<fixture environment>\n<pack>\n<tarball with spaces>\n<$(must stay literal)>\n`,
    );
  });

  test('npm exit status and both output streams reach the caller', () => {
    at.fake('npm', 'echo fixture-output\necho fixture-error >&2\nexit 7\n');

    const ran = npm(on([bunNode, at.bin]), ['whoami']);

    expect(ran.status).toBe(7);
    expect(ran.stdout).toBe('fixture-output\n');
    expect(ran.stderr).toBe('fixture-error\n');
  });
});
