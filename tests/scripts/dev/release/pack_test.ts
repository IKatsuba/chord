import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join } from 'node:path';
import { PACKAGES, ReleaseError } from '../../../../scripts/dev/release/lib.ts';
import { pack } from '../../../../scripts/dev/release/pack.ts';
import { checkSum } from '../../../../scripts/dev/release/sums.ts';
import { type Scratch, scratch } from './scratch.ts';

// Packing on fakes: bun lays out npm/, npm packs each package as its name and
// installs a tarball as the binary built for it, codesign verifies and xattr
// says what the test sets; the self-test only records what it was given.

const VERSION = '9.9.9';

let at: Scratch;
let tested: [string, string | undefined][];

beforeEach(() => {
  at = scratch();
  tested = [];

  writeFileSync(
    join(at.root, 'package.json'),
    JSON.stringify({ version: VERSION }),
  );

  for (const target of [
    'darwin-arm64',
    'darwin-x64',
    'linux-arm64',
    'linux-x64',
  ]) {
    mkdirSync(join(at.root, 'dist', `bun-${target}`), { recursive: true });
    writeFileSync(join(at.root, 'dist', `bun-${target}`, 'chord'), target);
  }

  at.fake(
    'bun',
    `for name in ${PACKAGES.join(' ')}; do mkdir -p "npm/$name"; done\n`,
  );
  at.fake(
    'npm',
    `case "$1" in
pack) echo "$(basename "$PWD")" >"$3/chorded-$(basename "$PWD")-${VERSION}.tgz" ;;
init) echo '{}' >package.json ;;
install)
	for tgz in "$@"; do
		case "$tgz" in *.tgz) ;; *) continue ;; esac
		name=$(cat "$tgz")
		if [ "$name" = chord ]; then
			mkdir -p node_modules/.bin
			echo shim >node_modules/.bin/chord
			continue
		fi
		mkdir -p "node_modules/@chorded/$name/bin"
		cp "$ROOT/dist/bun-\${name#chord-}/chord" "node_modules/@chorded/$name/bin/chord"
	done
	;;
esac
`,
  );
  at.fake('codesign', 'exit 0\n');
  at.fake('xattr', 'echo "$XATTR"\n');
});

afterEach(() => {
  rmSync(at.place, { recursive: true, force: true });
});

function packing(env: Record<string, string> = {}) {
  return pack(
    { ...at.release, env: { ...at.release.env, ROOT: at.root, ...env } },
    (_release, binary, arch) => {
      tested.push([binary, arch]);

      return Promise.resolve();
    },
  );
}

test("records every tarball's sum in the form publish checks", async () => {
  await packing({ XATTR: '' });

  const tgz = join(at.root, 'dist', 'release', 'tgz');
  const sums = readFileSync(join(tgz, 'SHA256SUMS'), 'utf8');

  for (const name of PACKAGES) {
    const tarball = join(tgz, `chorded-${name}-${VERSION}.tgz`);

    expect(sums).toContain(`  chorded-${name}-${VERSION}.tgz\n`);
    expect(() => checkSum(tarball)).not.toThrow();
  }

  expect(sums.split('\n').filter(Boolean)).toHaveLength(5);
  expect(
    tested.map(([binary, arch]) => [
      binary.split('/').slice(-3).join('/'),
      arch,
    ]),
  ).toStrictEqual([
    ['node_modules/.bin/chord', undefined],
    ['chord-darwin-x64/bin/chord', 'x86_64'],
  ]);
  expect(at.out.at(-1)).toBe(
    `packed ${join(at.root, 'dist', 'release', 'packages', 'tgz')}`,
  );
});

test('an installed copy npm quarantined stops the packing, before the self-test', async () => {
  let message = '';

  try {
    await packing({ XATTR: 'com.apple.quarantine' });
  } catch (error) {
    expect(error).toBeInstanceOf(ReleaseError);

    message = (error as ReleaseError).message;
  }

  expect(message).toMatch(
    /^npm quarantined \S+\/node_modules\/@chorded\/chord-darwin-arm64\/bin\/chord$/,
  );
  expect(tested).toStrictEqual([]);
});

describe('tester: package verification failures', () => {
  function sumsWritten(): boolean {
    return existsSync(join(at.root, 'dist', 'release', 'tgz', 'SHA256SUMS'));
  }

  test('a failed layout never packs or records publishable sums', async () => {
    at.fake('bun', 'exit 2\n');
    at.fake('npm', 'echo "$*" >>"$ROOT/npm.log"\n');

    await expect(packing()).rejects.toThrow(
      new ReleaseError('laying out npm/ failed'),
    );
    expect(existsSync(join(at.root, 'npm.log'))).toBeFalse();
    expect(tested).toEqual([]);
    expect(sumsWritten()).toBeFalse();
  });

  test('a failed npm pack stops before installed-copy self-tests and sums', async () => {
    at.fake('npm', 'exit 2\n');

    await expect(packing()).rejects.toThrow(
      new ReleaseError(`npm pack of ${PACKAGES[0]} failed`),
    );
    expect(tested).toEqual([]);
    expect(sumsWritten()).toBeFalse();
  });

  test('changed installed bytes stop before self-tests and sums', async () => {
    const npm = readFileSync(join(at.bin, 'npm'), 'utf8');

    at.fake(
      'npm',
      npm.replace(
        '\n\tdone',
        '\n\t\techo changed >"node_modules/@chorded/$name/bin/chord"\n\tdone',
      ),
    );

    await expect(packing()).rejects.toThrow(
      /the installed .* differs from .*dist\/bun-darwin-arm64\/chord/,
    );
    expect(tested).toEqual([]);
    expect(sumsWritten()).toBeFalse();
  });

  test('a failed installed-copy self-test removes its scratch and records no sums', async () => {
    const failure = new Error('fixture self-test failed');
    let project: string | undefined;

    await expect(
      pack(
        { ...at.release, env: { ...at.release.env, ROOT: at.root } },
        (_release, binary) => {
          project = dirname(dirname(dirname(binary)));

          return Promise.reject(failure);
        },
      ),
    ).rejects.toBe(failure);
    expect(project).toBeDefined();
    expect(existsSync(project!)).toBeFalse();
    expect(sumsWritten()).toBeFalse();
    expect(at.out).toEqual([]);
  });
});
