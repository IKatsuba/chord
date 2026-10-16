import { describe, expect, test } from 'bun:test';
import { ValidationError } from '@cliffy/command';
import stripAnsi from 'strip-ansi';
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
    release: record('release'),
    chord: record('chord'),
    test: record('test'),
    check: record('check'),
    fmt: record('fmt'),
    lint: record('lint'),
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

describe('chord', () => {
  test('passes every argument on to chord', async () => {
    expect(await parsed(['chord'])).toStrictEqual([['chord', false, []]]);
    expect(await parsed(['chord', '-p', 'hi'])).toStrictEqual([
      ['chord', false, ['-p', 'hi']],
    ]);
    expect(await parsed(['chord', 'codex', '--resume'])).toStrictEqual([
      ['chord', false, ['codex', '--resume']],
    ]);
  });

  test("--fake before chord's arguments is its own", async () => {
    expect(await parsed(['chord', '--fake'])).toStrictEqual([
      ['chord', true, []],
    ]);
    expect(await parsed(['chord', '--fake', '-p', 'hi'])).toStrictEqual([
      ['chord', true, ['-p', 'hi']],
    ]);
  });

  test("--fake after chord's first word is chord's", async () => {
    expect(await parsed(['chord', 'codex', '--fake'])).toStrictEqual([
      ['chord', false, ['codex', '--fake']],
    ]);
  });

  test('words after -- reach chord, without the --', async () => {
    expect(await parsed(['chord', '--', '--help'])).toStrictEqual([
      ['chord', false, ['--help']],
    ]);
    expect(
      await parsed(['chord', '--fake', '-p', 'hi', '--', '--fake']),
    ).toStrictEqual([['chord', true, ['-p', 'hi', '--fake']]]);
  });
});

describe('test', () => {
  test('passes every argument on to bun test', async () => {
    expect(await parsed(['test'])).toStrictEqual([['test', []]]);
    expect(
      await parsed(['test', './tests/x_test.ts', '-t', 'a stop']),
    ).toStrictEqual([['test', ['./tests/x_test.ts', '-t', 'a stop']]]);
  });

  test("--update-timings is bun test's", async () => {
    expect(await parsed(['test', '--update-timings'])).toStrictEqual([
      ['test', ['--update-timings']],
    ]);
  });

  test('words after -- follow, without the --', async () => {
    expect(await parsed(['test', '--changed', '--', '--bail'])).toStrictEqual([
      ['test', ['--changed', '--bail']],
    ]);
  });
});

describe('check', () => {
  test('runs everything, or only the static steps', async () => {
    expect(await parsed(['check'])).toStrictEqual([
      ['check', { static: false }],
    ]);
    expect(await parsed(['check', '--static'])).toStrictEqual([
      ['check', { static: true }],
    ]);
  });

  test('takes no arguments and no other option', async () => {
    await expect(parsed(['check', 'tests/'])).rejects.toThrow(ValidationError);
    await expect(parsed(['check', '--fix'])).rejects.toThrow(ValidationError);
  });
});

test('fmt takes no arguments', async () => {
  expect(await parsed(['fmt'])).toStrictEqual([['fmt']]);
  await expect(parsed(['fmt', 'src/'])).rejects.toThrow(ValidationError);
});

test('lint passes every argument on to ESLint', async () => {
  expect(await parsed(['lint'])).toStrictEqual([['lint', []]]);
  expect(await parsed(['lint', '--fix'])).toStrictEqual([['lint', ['--fix']]]);
  expect(await parsed(['lint', '--fix', '--', '--quiet'])).toStrictEqual([
    ['lint', ['--fix', '--quiet']],
  ]);
});

test('--help lists every command', () => {
  const help = stripAnsi(devCommand().getHelp());

  for (const name of [
    'chord',
    'test',
    'check',
    'fmt',
    'lint',
    'compile',
    'npm',
    'registry',
    'mark',
    'screenshots',
    'memory',
    'selftest',
    'release',
  ]) {
    expect(help).toMatch(new RegExp(`^  ${name} `, 'm'));
  }
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
      release: unexpected,
      chord: unexpected,
      test: unexpected,
      check: unexpected,
      fmt: unexpected,
      lint: unexpected,
    };

    await expect(
      devCommand(actions).noExit().throwErrors().parse(['mark']),
    ).rejects.toBe(failure);
  });
});

describe('tester: CHD-411 forwarding boundaries', () => {
  test('quoted and dash-prefixed values retain their boundaries', async () => {
    const args = ['-t', 'a stop with spaces', '--unknown=value'];

    expect(await parsed(['test', ...args])).toStrictEqual([['test', args]]);
    expect(await parsed(['lint', ...args])).toStrictEqual([['lint', args]]);
    expect(await parsed(['chord', '--fake', ...args])).toStrictEqual([
      ['chord', true, args],
    ]);
  });

  test('empty arguments survive only after the literal boundary', async () => {
    expect(await parsed(['test', '-t', ''])).toStrictEqual([['test', ['-t']]]);
    expect(await parsed(['test', '--', '-t', ''])).toStrictEqual([
      ['test', ['-t', '']],
    ]);
  });

  test('fake is forwarded after the first chord argument or literal boundary', async () => {
    for (const args of [
      ['-p', 'text', '--fake'],
      ['--', '--fake'],
    ]) {
      expect(await parsed(['chord', ...args])).toStrictEqual([
        ['chord', false, args.filter((arg) => arg !== '--')],
      ]);
    }
  });

  test('strict commands refuse options meant for forwarded tools', async () => {
    for (const argv of [
      ['fmt', '--fix'],
      ['check', '--update-timings'],
      ['check', '--static', 'extra'],
    ]) {
      await expect(parsed(argv)).rejects.toThrow(ValidationError);
    }
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

describe('release', () => {
  /** The stages and options `argv` gives the release, or the error. */
  async function released(argv: string[]) {
    const [call] = await parsed(['release', ...argv]);

    expect(call?.[0]).toBe('release');

    return { stages: call?.[1], options: call?.[2] };
  }

  test('with no options runs every stage', async () => {
    expect(await released([])).toStrictEqual({
      stages: [
        'install',
        'check',
        'natives',
        'compile',
        'sign',
        'selftest',
        'notarise',
        'pack',
        'publish',
      ],
      options: {},
    });
  });

  test('--dry-run runs every stage but publish', async () => {
    const { stages, options } = await released(['--dry-run']);

    expect(stages).not.toContain('publish');
    expect(stages).toHaveLength(8);
    expect(options).toStrictEqual({ dryRun: true });
  });

  test('--skip takes a comma-separated list', async () => {
    expect(await released(['--skip', 'install,check'])).toStrictEqual({
      stages: [
        'natives',
        'compile',
        'sign',
        'selftest',
        'notarise',
        'pack',
        'publish',
      ],
      options: { skip: ['install', 'check'] },
    });
  });

  test('--dry-run --skip notarise, the run without Apple', async () => {
    expect(
      (await released(['--dry-run', '--skip', 'notarise'])).stages,
    ).toStrictEqual([
      'install',
      'check',
      'natives',
      'compile',
      'sign',
      'selftest',
      'pack',
    ]);
  });

  test('--only runs the stages named', async () => {
    expect((await released(['--only', 'publish'])).stages).toStrictEqual([
      'publish',
    ]);
    expect((await released(['--only', 'pack,sign'])).stages).toStrictEqual([
      'sign',
      'pack',
    ]);
  });

  test('--from and --to', async () => {
    expect((await released(['--from', 'selftest'])).stages).toStrictEqual([
      'selftest',
      'notarise',
      'pack',
      'publish',
    ]);
    expect(
      (await released(['--from', 'natives', '--to', 'sign'])).stages,
    ).toStrictEqual(['natives', 'compile', 'sign']);
  });

  test('--package names one of the five packages', async () => {
    expect(
      await released(['--only', 'publish', '--package', 'chord-linux-x64']),
    ).toStrictEqual({
      stages: ['publish'],
      options: { only: ['publish'], package: 'chord-linux-x64' },
    });
    expect((await released(['--package', 'chord'])).stages).toContain(
      'publish',
    );
  });

  test.each([
    ['an unknown stage', ['--skip', 'tests']],
    ['an unknown stage in a list', ['--only', 'pack,tests']],
    ['an unknown stage for --from', ['--from', 'build']],
    ['an unknown package', ['--package', 'chord-windows-x64']],
    ['--only with --skip', ['--only', 'publish', '--skip', 'check']],
    ['--only with --from', ['--only', 'publish', '--from', 'pack']],
    ['--only with --to', ['--only', 'pack', '--to', 'pack']],
    ['--package with --dry-run', ['--package', 'chord', '--dry-run']],
    ['--dry-run with --only publish', ['--dry-run', '--only', 'publish']],
    ['--package without publish', ['--to', 'pack', '--package', 'chord']],
    ['options that leave no stage', ['--from', 'pack', '--to', 'check']],
    ['an argument', ['now']],
  ])('refuses %s', async (_name, argv) => {
    await expect(parsed(['release', ...argv])).rejects.toThrow(ValidationError);
  });
});

describe('release [version]', () => {
  test('takes an exact version or a bump', async () => {
    for (const version of ['1.0.0', 'major', 'minor', 'patch', 'fix']) {
      const [call] = await parsed(['release', version, '--dry-run']);

      expect(call?.[3]).toBe(version);
    }

    expect((await parsed(['release']))[0]?.[3]).toBeUndefined();
  });

  test.each([['v1.0.0'], ['1.0'], ['next'], ['1.0.0+build']])(
    'refuses %s',
    async (version) => {
      await expect(parsed(['release', version])).rejects.toThrow(
        ValidationError,
      );
    },
  );

  test('is parsed whatever the stages; the release judges it', async () => {
    const [call] = await parsed(['release', 'patch', '--only', 'publish']);

    expect(call?.[1]).toEqual(['publish']);
    expect(call?.[3]).toBe('patch');
  });
});

describe('tester: release parsing boundaries', () => {
  test('conflicts are refused with the arguments in either order', async () => {
    for (const pair of [
      [
        ['--only', 'publish'],
        ['--skip', 'check'],
      ],
      [
        ['--only', 'pack'],
        ['--from', 'sign'],
      ],
      [
        ['--only', 'pack'],
        ['--to', 'pack'],
      ],
      [['--package', 'chord'], ['--dry-run']],
    ]) {
      for (const parts of [pair, [...pair].reverse()]) {
        await expect(parsed(['release', ...parts.flat()])).rejects.toThrow(
          ValidationError,
        );
      }
    }
  });

  test('publish is refused anywhere in a dry-run only list', async () => {
    for (const stages of [
      'pack,publish',
      'publish,pack',
      'check,publish,pack',
    ]) {
      await expect(
        parsed(['release', '--dry-run', '--only', stages]),
      ).rejects.toThrow(ValidationError);
    }
  });

  test('missing values and invalid list elements never run an action', async () => {
    for (const argv of [
      ['--skip'],
      ['--only'],
      ['--from'],
      ['--to'],
      ['--package'],
      ['--to', 'build'],
      ['--skip', 'check,unknown'],
    ]) {
      await expect(parsed(['release', ...argv])).rejects.toThrow(
        ValidationError,
      );
    }
  });

  test('a package cannot survive a selection that removes publish', async () => {
    for (const argv of [
      ['--skip', 'publish'],
      ['--only', 'check'],
      ['--from', 'install', '--to', 'pack'],
    ]) {
      await expect(
        parsed(['release', ...argv, '--package', 'chord-linux-arm64']),
      ).rejects.toThrow(ValidationError);
    }
  });
});
