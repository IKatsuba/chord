import { afterEach, beforeEach, expect, test } from 'bun:test';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
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
