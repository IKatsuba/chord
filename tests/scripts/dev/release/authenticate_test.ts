import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { authenticate } from '../../../../scripts/dev/release/authenticate.ts';
import {
  type Release,
  ReleaseError,
} from '../../../../scripts/dev/release/lib.ts';
import { type Scratch, scratch } from './scratch.ts';

let at: Scratch;

beforeEach(() => {
  at = scratch();

  at.fake(
    'npm',
    `printf '%s\\n' "$*" >>"$STATE/ran.log"
case "$1" in
whoami)
  if [ -f "$STATE/logged-out" ]; then
    echo fixture-whoami-output
    echo fixture-whoami-error >&2
    exit "\${WHO_STATUS:-1}"
  fi
  echo fixture-owner
  ;;
login)
  if [ -n "$READ_LOGIN" ]; then
    read -r line
    printf 'login stdin=<%s>\\n' "$line" >"$STATE/input.log"
    echo fixture-login-output
    echo fixture-login-error >&2
  fi
  if [ "$LOGIN_RESULT" = signal ]; then kill -TERM $$; fi
  if [ -n "$LOGIN_RESULT" ]; then exit "$LOGIN_RESULT"; fi
  if [ -z "$RECHECK_FAIL" ]; then rm "$STATE/logged-out"; fi
  ;;
esac
`,
  );
});

afterEach(() => {
  rmSync(at.place, { recursive: true, force: true });
});

function context(env: Record<string, string> = {}, tty = true): Release {
  return {
    ...at.release,
    tty,
    env: { ...at.release.env, STATE: at.place, ...env },
  };
}

function loggedOut(): void {
  writeFileSync(join(at.place, 'logged-out'), '');
}

function ran(): string[] {
  const path = join(at.place, 'ran.log');

  return existsSync(path) ? readFileSync(path, 'utf8').trim().split('\n') : [];
}

test.each([true, false])(
  'an existing identity needs no login, tty=%s',
  (tty) => {
    authenticate(context({}, tty));

    expect(ran()).toEqual(['whoami']);
    expect(at.out).toEqual([]);
  },
);

test.each(['1', '7'])(
  'a failed identity check with status %s gets one plain login and recheck',
  (status) => {
    loggedOut();
    authenticate(context({ WHO_STATUS: status }));

    expect(ran()).toEqual(['whoami', 'login', 'whoami']);
    expect(at.out).toEqual([
      'npm whoami failed; npm login will use this terminal and may open a browser.',
      'npm may save credentials and registry settings, including during a dry run.',
    ]);
    expect(at.err).toEqual([]);
  },
);

test('a failed identity check without a terminal never starts login', () => {
  loggedOut();

  expect(() => authenticate(context({}, false))).toThrow(
    new ReleaseError(
      'npm login needs stdin and stdout on a terminal; rerun this release in a terminal.',
    ),
  );
  expect(ran()).toEqual(['whoami']);
  expect(at.out).toEqual([]);
});

test.each(['2', '130', 'signal'])(
  'login outcome %s stops without a recheck or retry',
  (result) => {
    loggedOut();

    expect(() => authenticate(context({ LOGIN_RESULT: result }))).toThrow(
      new ReleaseError('npm login did not complete; release stopped'),
    );
    expect(ran()).toEqual(['whoami', 'login']);
  },
);

test('successful login still requires a successful identity recheck', () => {
  loggedOut();

  expect(() => authenticate(context({ RECHECK_FAIL: 'yes' }))).toThrow(
    new ReleaseError('npm whoami still failed after login; release stopped'),
  );
  expect(ran()).toEqual(['whoami', 'login', 'whoami']);
});

test('login inherits stdin, stdout and stderr without copying npm prompts', () => {
  loggedOut();

  const script = join(at.place, 'authenticate.ts');
  const module = new URL(
    '../../../../scripts/dev/release/authenticate.ts',
    import.meta.url,
  ).pathname;

  writeFileSync(
    script,
    `import { authenticate } from ${JSON.stringify(module)};
authenticate({
  root: ${JSON.stringify(at.root)}, env: process.env, tty: true,
  sleep: () => Promise.resolve(), out: (line) => console.log(line),
  err: (line) => console.error(line),
});
`,
  );

  const child = spawnSync(process.execPath, [script], {
    env: context({ READ_LOGIN: 'yes' }).env,
    input: 'fixture-input\n',
    encoding: 'utf8',
    timeout: 10_000,
  });

  expect(child.status).toBe(0);
  expect(readFileSync(join(at.place, 'input.log'), 'utf8')).toBe(
    'login stdin=<fixture-input>\n',
  );
  expect(child.stdout).toBe(
    'npm whoami failed; npm login will use this terminal and may open a browser.\n' +
      'npm may save credentials and registry settings, including during a dry run.\n' +
      'fixture-login-output\n',
  );
  expect(child.stderr).toBe('fixture-login-error\n');
  expect(ran()).toEqual(['whoami', 'login', 'whoami']);
});

describe('CHD-531 tester: interrupted identity checks and later invocations', () => {
  test.each([false, true])(
    'a signal-terminated identity check cannot bypass authentication, tty=%s',
    (tty) => {
      at.fake(
        'npm',
        `printf '%s\\n' "$*" >>"$STATE/ran.log"
case "$1" in
whoami)
  if [ ! -f "$STATE/recovered" ]; then kill -TERM $$; fi
  ;;
login) touch "$STATE/recovered" ;;
esac`,
      );

      if (tty) {
        authenticate(context({}, true));
        expect(ran()).toEqual(['whoami', 'login', 'whoami']);
      } else {
        expect(() => authenticate(context({}, false))).toThrow(
          'npm login needs stdin and stdout on a terminal',
        );
        expect(ran()).toEqual(['whoami']);
      }
    },
  );

  test('a signal-terminated recheck stops after one login', () => {
    at.fake(
      'npm',
      `printf '%s\\n' "$*" >>"$STATE/ran.log"
case "$1" in
whoami) kill -TERM $$ ;;
esac`,
    );

    expect(() => authenticate(context())).toThrow(
      'npm whoami still failed after login; release stopped',
    );
    expect(ran()).toEqual(['whoami', 'login', 'whoami']);
  });

  test('a later invocation may recover after the first login was cancelled', () => {
    loggedOut();
    expect(() => authenticate(context({ LOGIN_RESULT: '130' }))).toThrow(
      'npm login did not complete; release stopped',
    );
    authenticate(context());
    expect(ran()).toEqual(['whoami', 'login', 'whoami', 'login', 'whoami']);
  });
});
