import { afterEach, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { mkdtemp, mkdir, writeFile, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import {
  capturedNamesAllow,
  definesAnyWord,
  CAPTURE_TIMEOUT_MS,
} from '../../../src/riff/commands/captured_names.ts';
import { until } from '../../session/conversation_fake.ts';

const owned: string[] = [];

afterEach(async () => {
  for (const path of owned.splice(0)) {
    await rm(path, { recursive: true, force: true });
  }
});

async function fixture(shell: 'bash' | 'zsh') {
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

  for (const shell of ['/bin/sh', '/missing/bash']) {
    expect(
      await capturedNamesAllow('npm test', {
        cwd: f.root,
        signal: live(),
        environment: { ...f.environment, SHELL: shell },
      }),
    ).toBe(false);
  }
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
