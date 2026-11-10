import { afterEach, describe, expect, test } from 'bun:test';
import { constants, readFileSync } from 'node:fs';
import {
  access,
  mkdtemp,
  mkdir,
  writeFile,
  rm,
  readFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import {
  capturedNamesAllow,
  definesAnyWord,
  CAPTURE_TIMEOUT_MS,
  parseCapturedNames,
} from '../../../src/riff/commands/captured_names.ts';
import { until } from '../../session/conversation_fake.ts';

const owned: string[] = [];

afterEach(async () => {
  for (const path of owned.splice(0)) {
    await rm(path, { recursive: true, force: true });
  }
});

async function fixture(shell: 'bash' | 'zsh') {
  if (shell === 'zsh') {
    await access('/bin/zsh', constants.X_OK).catch((cause: unknown) => {
      throw new Error('zsh tests require the executable shell /bin/zsh', {
        cause,
      });
    });
  }

  const root = await mkdtemp(join(tmpdir(), 'chord-capture-'));

  owned.push(root);

  const home = join(root, 'home');

  await mkdir(home);

  const startup = join(home, shell === 'bash' ? 'bashenv' : '.zshenv');

  await writeFile(startup, '');

  const environment = {
    SHELL: `/bin/${shell}`,
    HOME: home,
    ZDOTDIR: home,
    BASH_ENV: startup,
    XDG_CONFIG_HOME: home,
    PATH: '/usr/bin:/bin',
    CHORD_RESOURCE_FIXTURE: 'true',
  };

  return { root, startup, environment };
}

const live = () => new AbortController().signal;

test.each([
  ['ll -a', true],
  ['git status && ll', true],
  ['echo $(ll)', true],
  ['ls -l', false],
  ['llama --help', false],
])('fx alias/function word matching: %s', (command, expected) => {
  expect(definesAnyWord(String(command), new Set(['ll']))).toBe(
    Boolean(expected),
  );
});

test('fx matching includes quoted arguments and all its delimiter characters', () => {
  for (const delimiter of [
    ' ',
    '\t',
    '\r',
    '\n',
    ';',
    '|',
    '&',
    '(',
    ')',
    '<',
    '>',
    "'",
    '"',
    '`',
    '$',
    '\\',
    '{',
    '}',
    '!',
  ]) {
    expect(
      definesAnyWord(`prefix${delimiter}ll${delimiter}suffix`, new Set(['ll'])),
    ).toBe(true);
  }

  expect(definesAnyWord('npm run build', new Set(['build']))).toBe(true);
});

for (const shell of ['bash', 'zsh'] as const) {
  test(`${shell} captures fixture aliases and functions in any command word`, async () => {
    const f = await fixture(shell);

    await writeFile(f.startup, "alias ll='ls -l'\nhelper() { :; }\n");

    for (const command of ['ll -a', 'npm run helper', "npm run 'helper'"]) {
      expect(
        await capturedNamesAllow(command, {
          cwd: f.root,
          signal: live(),
          environment: f.environment,
        }),
      ).toBe(false);
    }

    expect(
      await capturedNamesAllow('node --version', {
        cwd: f.root,
        signal: live(),
        environment: f.environment,
      }),
    ).toBe(true);
  });

  test(`${shell} captures fresh startup names before every reversible admission`, async () => {
    const f = await fixture(shell);
    const options = { cwd: f.root, signal: live(), environment: f.environment };

    expect(await capturedNamesAllow('npm test', options)).toBe(true);
    await writeFile(f.startup, "alias npm='false'\n");
    expect(await capturedNamesAllow('npm test', options)).toBe(false);
    await writeFile(f.startup, '');
    expect(await capturedNamesAllow('npm test', options)).toBe(true);
  });

  test(`${shell} startup failure defers to review`, async () => {
    const f = await fixture(shell);

    await writeFile(f.startup, 'exit 7\n');
    expect(
      await capturedNamesAllow('npm test', {
        cwd: f.root,
        signal: live(),
        environment: f.environment,
      }),
    ).toBe(false);
  });
}

test('unknown shell and failed executable defer to review', async () => {
  const f = await fixture('bash');

  for (const shell of ['/bin/sh', '/missing/bash', '/missing/zsh']) {
    expect(
      await capturedNamesAllow('npm test', {
        cwd: f.root,
        signal: live(),
        environment: { ...f.environment, SHELL: shell },
      }),
    ).toBe(false);
  }
});

test('non-executable zsh defers to review', async () => {
  const f = await fixture('bash');
  const shell = join(f.root, 'zsh');

  await writeFile(shell, '#!/bin/sh\nexit 0\n', { mode: 0o600 });
  expect(
    await capturedNamesAllow('npm test', {
      cwd: f.root,
      signal: live(),
      environment: { ...f.environment, SHELL: shell },
    }),
  ).toBe(false);
});

test('turn cancellation stops a capture and its startup child', async () => {
  const f = await fixture('bash');
  const pidFile = join(f.root, 'child');

  await writeFile(
    f.startup,
    '/bin/sleep 60 &\nprintf "%s" "$!" > "$CHORD_CAPTURE_PID"\nwait\n',
  );

  const controller = new AbortController();
  const reason = new Error('cancel captured names');
  const job = capturedNamesAllow('npm test', {
    cwd: f.root,
    signal: controller.signal,
    environment: { ...f.environment, CHORD_CAPTURE_PID: pidFile },
  });
  const settled = Promise.allSettled([job]);
  let pid = 0;

  try {
    await until(() => {
      try {
        pid = Number(readFileSync(pidFile, 'utf8'));

        return pid > 0;
      } catch {
        return false;
      }
    });

    controller.abort(reason);
    await expect(job).rejects.toBe(reason);
    expect(() => process.kill(pid, 0)).toThrow();
  } finally {
    controller.abort();
    await settled;
  }
});

test('fx ten-second capture timeout defers to review and reaps startup children', async () => {
  const f = await fixture('bash');
  const pidFile = join(f.root, 'child');

  await writeFile(
    f.startup,
    '/bin/sleep 60 &\nprintf "%s" "$!" > "$CHORD_CAPTURE_PID"\nwait\n',
  );

  const controller = new AbortController();
  const job = capturedNamesAllow('npm test', {
    cwd: f.root,
    signal: controller.signal,
    environment: { ...f.environment, CHORD_CAPTURE_PID: pidFile },
  });

  try {
    const started = performance.now();

    expect(await job).toBe(false);
    expect(performance.now() - started).toBeGreaterThanOrEqual(
      CAPTURE_TIMEOUT_MS - 100,
    );

    const pid = Number(await readFile(pidFile, 'utf8'));

    expect(() => process.kill(pid, 0)).toThrow();
  } finally {
    controller.abort();
    await Promise.allSettled([job]);
  }
});

test('capture output beyond its bound defers to review', async () => {
  const f = await fixture('bash');

  await writeFile(f.startup, "printf '%70000s' x\n");
  expect(
    await capturedNamesAllow('npm test', {
      cwd: f.root,
      signal: live(),
      environment: f.environment,
    }),
  ).toBe(false);
});

test('already cancelled capture reads no startup file', async () => {
  const f = await fixture('bash');
  const controller = new AbortController();
  const reason = new Error('cancel before capture');

  controller.abort(reason);
  await expect(
    capturedNamesAllow('npm test', {
      cwd: f.root,
      signal: controller.signal,
      environment: f.environment,
    }),
  ).rejects.toBe(reason);
});

for (const shell of ['bash', 'zsh'] as const) {
  test(`${shell} startup text without a newline cannot hide a captured name`, async () => {
    const f = await fixture(shell);

    await writeFile(f.startup, 'alias node=false\nprintf prefix\n');
    expect(
      await capturedNamesAllow('node --version', {
        cwd: f.root,
        signal: live(),
        environment: f.environment,
      }),
    ).toBe(false);
  });

  test(`${shell} redirected startup stdout cannot appear to be a complete capture`, async () => {
    const f = await fixture(shell);

    await writeFile(f.startup, 'alias node=false\nexec >/dev/null\n');
    expect(
      await capturedNamesAllow('node --version', {
        cwd: f.root,
        signal: live(),
        environment: f.environment,
      }),
    ).toBe(false);
  });

  test(`${shell} startup chatter is outside the nonce-framed names`, async () => {
    const f = await fixture(shell);

    await writeFile(f.startup, 'printf prefix\nalias builtin=false\n');
    expect(
      await capturedNamesAllow('node --version', {
        cwd: f.root,
        signal: live(),
        environment: f.environment,
      }),
    ).toBe(true);
  });
}

test.each(['-g', '-s'])('zsh captures %s aliases as fx does', async (flag) => {
  const f = await fixture('zsh');

  await writeFile(f.startup, `alias ${flag} helper=false\n`);
  expect(
    await capturedNamesAllow('npm run helper', {
      cwd: f.root,
      signal: live(),
      environment: f.environment,
    }),
  ).toBe(false);
});

test('nonce frames require completion and reject duplicate or trailing payload', () => {
  const nonce = '0123456789abcdef';
  const start = `FXSNAP:${nonce}:NAMES\0`;
  const end = `\0FXSNAP:${nonce}:END\0`;
  const valid = `${start}node\0helper\0${end}`;

  expect([
    ...parseCapturedNames('startup-without-newline' + valid, nonce)!,
  ]).toEqual(['node', 'helper']);

  for (const malformed of [
    '',
    start + 'node\0',
    valid + 'trailing',
    start + valid,
    valid.replaceAll(nonce, 'another-nonce'),
  ]) {
    expect(parseCapturedNames(malformed, nonce)).toBeUndefined();
  }
});

test('successful capture reaps a startup background child with detached stdio', async () => {
  const f = await fixture('bash');
  const pidFile = join(f.root, 'child');
  const readyFile = join(f.root, 'ready');

  await writeFile(
    f.startup,
    `/bin/sh -c 'trap "" TERM; printf ready > "$CHORD_CAPTURE_READY"; exec /bin/sleep 60' </dev/null >/dev/null 2>&1 &
printf "%s" "$!" > "$CHORD_CAPTURE_PID"
while ! test -e "$CHORD_CAPTURE_READY"; do /bin/sleep 0.01; done
`,
  );

  const controller = new AbortController();
  const job = capturedNamesAllow('npm test', {
    cwd: f.root,
    signal: controller.signal,
    environment: {
      ...f.environment,
      CHORD_CAPTURE_PID: pidFile,
      CHORD_CAPTURE_READY: readyFile,
    },
  });
  let pid = 0;

  try {
    const started = performance.now();

    expect(await job).toBe(true);

    pid = Number(await readFile(pidFile, 'utf8'));

    expect(pid).toBeGreaterThan(0);
    expect(() => process.kill(pid, 0)).toThrow();
    expect(performance.now() - started).toBeGreaterThanOrEqual(700);
  } finally {
    controller.abort();
    await Promise.allSettled([job]);

    if (pid === 0) {
      pid = Number(await readFile(pidFile, 'utf8').catch(() => '0'));
    }

    if (pid > 0) {
      try {
        process.kill(pid, 'SIGKILL');
      } catch {
        /* Already reaped. */
      }
    }
  }
});

for (const shell of ['bash', 'zsh'] as const) {
  test.each([':', 'e'])(
    `${shell} custom IFS %s cannot split or merge captured names`,
    async (ifs) => {
      const f = await fixture(shell);

      await writeFile(
        f.startup,
        `alias helper=false\nalias node=false\nIFS=${ifs}\n`,
      );
      expect(
        await capturedNamesAllow('node --version', {
          cwd: f.root,
          signal: live(),
          environment: f.environment,
        }),
      ).toBe(false);
    },
  );
}

test('ambiguous captured names defer to review', () => {
  const nonce = '0123456789abcdef';

  for (const name of ['helper\nnode', 'he lper', 'he;lper']) {
    expect(
      parseCapturedNames(
        `FXSNAP:${nonce}:NAMES\0${name}\0\0FXSNAP:${nonce}:END\0`,
        nonce,
      ),
    ).toBeUndefined();
  }
});

test('bash capture does not let glob options hide other names', async () => {
  const f = await fixture('bash');

  await writeFile(
    f.startup,
    "alias node=false\nalias '*missingglob*'=false\nshopt -s failglob\n",
  );
  expect(
    await capturedNamesAllow('node --version', {
      cwd: f.root,
      signal: live(),
      environment: f.environment,
    }),
  ).toBe(false);
});

test('bash capture establishes its required compgen builtin', async () => {
  const f = await fixture('bash');

  await writeFile(f.startup, 'alias node=false\nenable -n compgen\n');
  expect(
    await capturedNamesAllow('node --version', {
      cwd: f.root,
      signal: live(),
      environment: f.environment,
    }),
  ).toBe(false);
});

test('zsh global aliases cannot replace fixed listing builtins or arguments', async () => {
  const f = await fixture('zsh');

  await writeFile(
    f.startup,
    'alias -g printf=false\nalias -g zmodload=false\nalias -g set=false\nalias node=false\n',
  );
  expect(
    await capturedNamesAllow('node --version', {
      cwd: f.root,
      signal: live(),
      environment: f.environment,
    }),
  ).toBe(false);
});

describe('CHD-609 tester: capture completion and session isolation', () => {
  test('foreign prefix frames do not replace the actual nonce frame', () => {
    const nonce = 'tester-actual';
    const prefix = 'FXSNAP:foreign:NAMES\0ignored\0\0FXSNAP:foreign:END\0';
    const result = parseCapturedNames(
      prefix + `FXSNAP:${nonce}:NAMES\0node\0\0FXSNAP:${nonce}:END\0`,
      nonce,
    );

    expect(result).toEqual(new Set(['node']));
    expect(definesAnyWord('node --version', result!)).toBe(true);
  });

  test.each(['\0', '\n', 'FXSNAP:tester:END\0'])(
    'a payload after the end marker prevents admission: %s',
    (tail) => {
      expect(
        parseCapturedNames(
          'FXSNAP:tester:NAMES\0node\0\0FXSNAP:tester:END\0' + tail,
          'tester',
        ),
      ).toBeUndefined();
    },
  );

  test.each([
    'FXSNAP:unexpected',
    'bad\ufffdname',
    'helper\tname',
    'helper\\name',
  ])('an ambiguous framed name prevents admission: %s', (name) => {
    expect(
      parseCapturedNames(
        `FXSNAP:tester:NAMES\0${name}\0\0FXSNAP:tester:END\0`,
        'tester',
      ),
    ).toBeUndefined();
  });

  for (const shell of ['bash', 'zsh'] as const) {
    test(`${shell} startup exit output cannot follow a complete frame`, async () => {
      const f = await fixture(shell);

      await writeFile(f.startup, "trap 'printf trailing-output' EXIT\n");
      expect(
        await capturedNamesAllow('node --version', {
          cwd: f.root,
          signal: live(),
          environment: f.environment,
        }),
      ).toBe(false);
    });

    test(`${shell} a readonly IFS that prevents setup falls back to review`, async () => {
      const f = await fixture(shell);

      await writeFile(f.startup, 'readonly IFS=:\n');
      expect(
        await capturedNamesAllow('node --version', {
          cwd: f.root,
          signal: live(),
          environment: f.environment,
        }),
      ).toBe(false);
    });
  }

  test('cancelling one capture does not stop another session capture', async () => {
    const fixtures = await Promise.all([fixture('bash'), fixture('bash')]);
    const controllers = [new AbortController(), new AbortController()];
    const pids = [0, 0];
    const reason = new Error('cancel first capture only');

    for (const f of fixtures) {
      await writeFile(
        f.startup,
        `
/bin/sleep 60 &
child=$!
printf '%s' "$child" > "$CHORD_TESTER_PID"
while ! test -e "$CHORD_TESTER_RELEASE"; do /bin/sleep 0.01; done
kill "$child"
wait "$child" 2>/dev/null
:
`,
      );
    }

    const jobs = fixtures.map((f, index) =>
      capturedNamesAllow('node --version', {
        cwd: f.root,
        signal: controllers[index]!.signal,
        environment: {
          ...f.environment,
          CHORD_TESTER_PID: join(f.root, 'pid'),
          CHORD_TESTER_RELEASE: join(f.root, 'release'),
        },
      }),
    );
    const settled = Promise.allSettled(jobs);
    let secondEnded = false;

    void jobs[1]!.then(
      () => {
        secondEnded = true;
      },
      () => {
        secondEnded = true;
      },
    );

    try {
      await until(() =>
        fixtures.every((f, index) => {
          try {
            pids[index] = Number(readFileSync(join(f.root, 'pid'), 'utf8'));

            return pids[index]! > 0;
          } catch {
            return false;
          }
        }),
      );
      controllers[0]!.abort(reason);
      await expect(jobs[0]!).rejects.toBe(reason);
      expect(() => process.kill(pids[0]!, 0)).toThrow();
      expect(secondEnded).toBe(false);
      expect(process.kill(pids[1]!, 0)).toBe(true);
      await writeFile(join(fixtures[1]!.root, 'release'), '');
      expect(await jobs[1]!).toBe(true);
      expect(() => process.kill(pids[1]!, 0)).toThrow();
    } finally {
      for (const controller of controllers) {
        controller.abort();
      }

      await settled;
    }
  });
});
