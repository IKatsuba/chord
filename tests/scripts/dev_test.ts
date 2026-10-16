import { describe, expect, test } from 'bun:test';
import { ValidationError } from '@cliffy/command';
import { type DevActions, devCommand } from '../../scripts/dev.ts';

/** Each command `argv` ran, with what it was given; nothing is run. */
async function parsed(argv: string[]): Promise<unknown[][]> {
  const calls: unknown[][] = [];
  const record =
    (name: string) =>
    (...args: unknown[]) => {
      calls.push([name, ...args]);
    };

  const actions: DevActions = {
    compile: record('compile'),
    npm: record('npm'),
    registry: record('registry'),
    mark: record('mark'),
    screenshots: record('screenshots'),
    memory: record('memory'),
    selftest: record('selftest'),
  };

  await devCommand(actions).noExit().throwErrors().parse(argv);

  return calls;
}

describe('compile', () => {
  test("with no flags builds this machine's target into dist/", async () => {
    expect(await parsed(['compile'])).toStrictEqual([
      ['compile', { all: false, install: false }],
    ]);
  });

  test('--all and --install are read', async () => {
    expect(await parsed(['compile', '--all'])).toStrictEqual([
      ['compile', { all: true, install: false }],
    ]);
    expect(await parsed(['compile', '--install'])).toStrictEqual([
      ['compile', { all: false, install: true }],
    ]);
  });

  test('an unknown flag is refused', async () => {
    await expect(parsed(['compile', '--everything'])).rejects.toThrow(
      ValidationError,
    );
  });
});

test('npm, registry and mark take no arguments', async () => {
  expect(await parsed(['npm'])).toStrictEqual([['npm']]);
  expect(await parsed(['registry'])).toStrictEqual([['registry']]);
  expect(await parsed(['mark'])).toStrictEqual([['mark']]);
  await expect(parsed(['mark', 'extra'])).rejects.toThrow(ValidationError);
});

test('screenshots takes the shots to retake, or none for all', async () => {
  expect(await parsed(['screenshots'])).toStrictEqual([['screenshots', []]]);
  expect(await parsed(['screenshots', 'team', 'edit'])).toStrictEqual([
    ['screenshots', ['team', 'edit']],
  ]);
});

describe('memory', () => {
  test('has the defaults the check ran on before', async () => {
    expect(await parsed(['memory'])).toStrictEqual([
      [
        'memory',
        {
          minutes: 10,
          sampleSeconds: 10,
          snapshots: 4,
          stepMs: 5,
          development: false,
        },
      ],
    ]);
  });

  test('reads every flag', async () => {
    expect(
      await parsed([
        'memory',
        '--minutes',
        '30',
        '--sample-seconds',
        '2.5',
        '--snapshots',
        '6',
        '--step-ms',
        '1',
        '--binary',
        'dist/bun-darwin-arm64/chord',
        '--development',
      ]),
    ).toStrictEqual([
      [
        'memory',
        {
          minutes: 30,
          sampleSeconds: 2.5,
          snapshots: 6,
          stepMs: 1,
          binary: 'dist/bun-darwin-arm64/chord',
          development: true,
        },
      ],
    ]);
  });

  test('refuses a number that is not one', async () => {
    await expect(parsed(['memory', '--minutes', 'ten'])).rejects.toThrow(
      ValidationError,
    );
  });
});

test('an unknown command is refused', async () => {
  await expect(parsed(['publish'])).rejects.toThrow(ValidationError);
});

describe('tester: migrated command boundaries', () => {
  test('commands without positional arguments refuse extras', async () => {
    for (const command of ['compile', 'npm', 'registry', 'mark', 'memory']) {
      await expect(parsed([command, 'extra'])).rejects.toThrow(ValidationError);
    }
  });

  test('options stay with the command that declares them', async () => {
    for (const argv of [
      ['npm', '--all'],
      ['registry', '--install'],
      ['mark', '--development'],
      ['compile', '--binary', 'chord'],
      ['memory', '--all'],
      ['--install', 'compile'],
    ]) {
      await expect(parsed(argv)).rejects.toThrow(ValidationError);
    }
  });

  test('every memory value option requires its value', async () => {
    for (const option of [
      '--minutes',
      '--sample-seconds',
      '--snapshots',
      '--step-ms',
      '--binary',
    ]) {
      await expect(parsed(['memory', option])).rejects.toThrow(ValidationError);
    }
  });

  test('every numeric memory option rejects text', async () => {
    for (const option of [
      '--minutes',
      '--sample-seconds',
      '--snapshots',
      '--step-ms',
    ]) {
      await expect(parsed(['memory', option, 'invalid'])).rejects.toThrow(
        ValidationError,
      );
    }
  });

  test('compile retains the combined all and install options', async () => {
    expect(await parsed(['compile', '--all', '--install'])).toStrictEqual([
      ['compile', { all: true, install: true }],
    ]);
  });

  test('an asynchronous action failure reaches the caller', async () => {
    const failure = new Error('fixture action failed');
    const unexpected = () => {
      throw new Error('another command ran');
    };

    const actions: DevActions = {
      compile: unexpected,
      npm: unexpected,
      registry: unexpected,
      mark: async () => {
        await Promise.resolve();

        throw failure;
      },
      screenshots: unexpected,
      memory: unexpected,
      selftest: unexpected,
    };

    await expect(
      devCommand(actions).noExit().throwErrors().parse(['mark']),
    ).rejects.toBe(failure);
  });
});

describe('selftest', () => {
  test('takes the binary, natively by default', async () => {
    expect(
      await parsed(['selftest', 'dist/bun-darwin-arm64/chord']),
    ).toStrictEqual([['selftest', 'dist/bun-darwin-arm64/chord', undefined]]);
  });

  test('--arch runs it under another architecture', async () => {
    expect(
      await parsed([
        'selftest',
        'dist/bun-darwin-x64/chord',
        '--arch',
        'x86_64',
      ]),
    ).toStrictEqual([['selftest', 'dist/bun-darwin-x64/chord', 'x86_64']]);
  });

  test('needs a binary', async () => {
    await expect(parsed(['selftest'])).rejects.toThrow(ValidationError);
  });
});
