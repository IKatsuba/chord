import { afterEach, beforeEach, expect, test } from 'bun:test';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { join } from 'node:path';
import { ReleaseError } from '../../../../scripts/dev/release/lib.ts';
import { notarise } from '../../../../scripts/dev/release/notarise.ts';
import { type Scratch, scratch } from './scratch.ts';

// Apple faked: xcrun's notarytool answers what the test sets in the
// environment, a binary's cdhash is its own content, and ditto only makes
// the zip.

const ARM = 'dist/bun-darwin-arm64/chord';
const X64 = 'dist/bun-darwin-x64/chord';
const ACCEPTED = '{"id":"sub-1","status":"Accepted"}';

let at: Scratch;
let out: string;

beforeEach(() => {
  at = scratch();
  out = join(at.root, 'dist', 'release');

  for (const [binary, cdhash] of [
    [ARM, 'aa11'],
    [X64, 'bb22'],
  ] as const) {
    mkdirSync(join(at.root, binary, '..'), { recursive: true });
    writeFileSync(join(at.root, binary), cdhash);
  }

  at.fake('ditto', 'touch "${@: -1}"\n');
  at.fake('codesign', 'echo "CDHash=$(cat "$2")" >&2\n');
  at.fake(
    'xcrun',
    `case "$2" in
submit)
	echo "$SUBMIT"
	echo 'submit diagnostics' >&2
	exit "\${SUBMIT_STATUS:-0}"
	;;
log)
	tries=$(( $(cat "$STATE/log-tries" 2>/dev/null || echo 0) + 1 ))
	echo "$tries" >"$STATE/log-tries"
	if [ "$tries" -le "\${LOG_FAILS:-0}" ]; then
		echo 'log unavailable' >&2
		exit 1
	fi
	echo "$LOG" >"$6"
	;;
esac
`,
  );
});

afterEach(() => {
  rmSync(at.place, { recursive: true, force: true });
});

function apple(env: Record<string, string>) {
  return {
    ...at.release,
    env: {
      ...at.release.env,
      STATE: at.place,
      SUBMIT: ACCEPTED,
      LOG: '{"ticketContents":[{"cdhash":"aa11"},{"cdhash":"bb22"}]}',
      ...env,
    },
  };
}

async function died(run: Promise<void>): Promise<string> {
  try {
    await run;
  } catch (error) {
    expect(error).toBeInstanceOf(ReleaseError);

    return (error as ReleaseError).message;
  }

  throw new Error('notarise did not die');
}

test('an accepted submission listing both binaries notarises them', async () => {
  await notarise(apple({}), out, [ARM, X64]);

  expect(at.out).toStrictEqual([
    `notarised ${ARM}: aa11`,
    `notarised ${X64}: bb22`,
  ]);
  expect(existsSync(join(out, 'chord.zip'))).toBeTrue();
  expect(readFileSync(join(out, 'notarytool.json'), 'utf8')).toBe(
    `${ACCEPTED}\n`,
  );
  expect(readFileSync(join(out, 'notarytool-submit.stderr'), 'utf8')).toBe(
    'submit diagnostics\n',
  );
});

test('a verdict other than Accepted dies, with the log kept', async () => {
  const invalid = '{"id":"sub-1","status":"Invalid"}';

  expect(await died(notarise(apple({ SUBMIT: invalid }), out, [ARM]))).toBe(
    `notarisation of ${join(out, 'chord.zip')} ended Invalid: ${invalid}`,
  );
  expect(existsSync(join(out, 'notarytool-log.json'))).toBeTrue();
});

test('a submit that fails dies with what it said', async () => {
  expect(await died(notarise(apple({ SUBMIT_STATUS: '1' }), out, [ARM]))).toBe(
    `notarytool submit exited 1: ${ACCEPTED} submit diagnostics`,
  );
});

test('the log is asked for three times, 10 s apart, then dies', async () => {
  expect(await died(notarise(apple({ LOG_FAILS: '3' }), out, [ARM]))).toBe(
    'the notarisation log of sub-1 could not be fetched: log unavailable',
  );
  expect(at.sleeps).toStrictEqual([10_000, 10_000]);
});

test('a log fetched on the third try is enough', async () => {
  await notarise(apple({ LOG_FAILS: '2' }), out, [ARM]);

  expect(at.out).toStrictEqual([`notarised ${ARM}: aa11`]);
});

test('a binary Apple has no ticket for dies, with what the log lists', async () => {
  expect(
    await died(
      notarise(apple({ LOG: '{"ticketContents":[{"cdhash":"aa11"}]}' }), out, [
        ARM,
        X64,
      ]),
    ),
  ).toBe(
    `Apple's log has no ticket for ${X64} (cdhash bb22); it lists: "cdhash":"aa11"`,
  );
});
