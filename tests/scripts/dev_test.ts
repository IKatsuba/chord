import { describe, expect, spyOn, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { cp, readFile, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ValidationError } from '@cliffy/command';
import {
  type DevActions,
  devCommand,
  type DevPackage,
} from '../../scripts/dev.ts';

/** The workspace's one package, as the repository finds it. */
const STAGES = ['install', 'quality', 'build', 'pack', 'publish'];
const PACKAGES: DevPackage[] = [{ name: 'cursor-cloud-acp', stages: STAGES }];

/** Actions that run nothing, for a command only asked for its help. */
const IDLE: DevActions = {
  quality: () => {},
  lint: () => {},
  release: () => {},
  unclear: () => {},
};

/** Each command `argv` ran, with what it was given; nothing is run. */
async function parsed(
  argv: string[],
  packages: readonly DevPackage[] = PACKAGES,
): Promise<unknown[][]> {
  const calls: unknown[][] = [];
  const record =
    (name: string) =>
    (...args: unknown[]) => {
      calls.push([name, ...args]);
    };

  const actions: DevActions = {
    quality: record('quality'),
    lint: record('lint'),
    release: record('release'),
    unclear: record('unclear'),
  };

  await devCommand(actions, packages).noExit().throwErrors().parse(argv);

  return calls;
}

describe('quality', () => {
  test("runs a package's checks, or only its static ones", async () => {
    expect(await parsed(['quality', 'cursor-cloud-acp'])).toStrictEqual([
      ['quality', 'cursor-cloud-acp', false],
    ]);
    expect(
      await parsed(['quality', 'cursor-cloud-acp', '--static']),
    ).toStrictEqual([['quality', 'cursor-cloud-acp', true]]);
  });

  test('a missing or unknown package is refused, listing the packages', async () => {
    await expect(parsed(['quality'])).rejects.toThrow(
      'Missing argument(s): package',
    );
    await expect(parsed(['quality', 'x'])).rejects.toThrow(
      'Argument "package" must be of type "package", but got "x". Expected values: "cursor-cloud-acp"',
    );
  });

  test('refuses extra arguments and unknown options', async () => {
    for (const argv of [
      ['quality', 'cursor-cloud-acp', 'tests/'],
      ['quality', 'cursor-cloud-acp', '--fix'],
      ['quality', 'cursor-cloud-acp', '--static', 'extra'],
    ]) {
      await expect(parsed(argv)).rejects.toThrow(ValidationError);
    }
  });

  test("an action's failure reaches the caller", async () => {
    const failure = new Error('fixture action failed');
    const actions = {
      quality: () => Promise.reject(failure),
    } as unknown as DevActions;

    await expect(
      devCommand(actions, PACKAGES)
        .noExit()
        .throwErrors()
        .parse(['quality', 'cursor-cloud-acp']),
    ).rejects.toBe(failure);
  });
});

describe('lint', () => {
  test('passes the rest of the arguments to ESLint as they are', async () => {
    expect(
      await parsed(['lint', 'cursor-cloud-acp', '--fix', 'a b', '--quiet']),
    ).toStrictEqual([
      ['lint', 'cursor-cloud-acp', ['--fix', 'a b', '--quiet']],
    ]);
    expect(
      await parsed(['lint', 'cursor-cloud-acp', '--fix', '--', '--quiet', '']),
    ).toStrictEqual([['lint', 'cursor-cloud-acp', ['--fix', '--quiet', '']]]);
    expect(
      await parsed(['lint', 'cursor-cloud-acp', '--fix', '']),
    ).toStrictEqual([['lint', 'cursor-cloud-acp', ['--fix']]]);
    expect(
      await parsed(['lint', 'cursor-cloud-acp', '--', '--help']),
    ).toStrictEqual([['lint', 'cursor-cloud-acp', ['--help']]]);
  });

  test('a missing or unknown package is refused', async () => {
    await expect(parsed(['lint'])).rejects.toThrow(ValidationError);
    await expect(parsed(['lint', '--fix'])).rejects.toThrow(ValidationError);
    await expect(parsed(['lint', 'x', '--fix'])).rejects.toThrow(
      'Expected values: "cursor-cloud-acp"',
    );
  });
});

test('--help lists every command, and names the packages', () => {
  const help = Bun.stripANSI(devCommand(IDLE, PACKAGES).getHelp());

  expect(help.replace(/\s+/g, ' ')).toContain(
    "runs that package's steps from its steps.ts and nothing else: cursor-cloud-acp, its npm name without the scope.",
  );

  for (const name of ['quality', 'lint', 'release']) {
    expect(help).toMatch(new RegExp(`^  ${name} `, 'm'));
  }

  for (const name of ['chord', 'test', 'compile', 'selftest', 'memory']) {
    expect(help).not.toMatch(new RegExp(`^  ${name} `, 'm'));
  }
});

test('an unknown command is refused', async () => {
  for (const command of ['publish', 'chord', 'test', 'compile', 'selftest']) {
    await expect(parsed([command])).rejects.toThrow(ValidationError);
  }
});

describe('tester: CHD-411 forwarding boundaries', () => {
  test('quoted and dash-prefixed values retain their boundaries', async () => {
    const args = ['-t', 'a stop with spaces', '--unknown=value'];

    expect(await parsed(['lint', 'cursor-cloud-acp', ...args])).toStrictEqual([
      ['lint', 'cursor-cloud-acp', args],
    ]);
  });
});

describe('release', () => {
  /** The stages, options and bump `argv` gives cursor-cloud-acp's release. */
  async function released(argv: string[]) {
    const [call] = await parsed(['release', 'cursor-cloud-acp', ...argv]);

    expect(call?.slice(0, 2)).toStrictEqual(['release', 'cursor-cloud-acp']);

    return { stages: call?.[2], options: call?.[3], bump: call?.[4] };
  }

  test('with no options runs every stage of the package', async () => {
    expect(await released([])).toStrictEqual({
      stages: STAGES,
      options: {},
      bump: undefined,
    });
  });

  test('--dry-run runs every stage but publish', async () => {
    const { stages, options } = await released(['--dry-run']);

    expect(stages).toStrictEqual(STAGES.slice(0, -1));
    expect(options).toStrictEqual({ dryRun: true });
  });

  test('--skip takes a comma-separated list', async () => {
    expect(await released(['--skip', 'install,quality'])).toStrictEqual({
      stages: STAGES.slice(2),
      options: { skip: ['install', 'quality'] },
      bump: undefined,
    });
  });

  test("--only, --from and --to over the package's own stages", async () => {
    expect((await released(['--only', 'pack,build'])).stages).toStrictEqual([
      'build',
      'pack',
    ]);
    expect(
      (await released(['--from', 'quality', '--to', 'build'])).stages,
    ).toStrictEqual(['quality', 'build']);
    expect((await released(['--from', 'build'])).stages).toStrictEqual([
      'build',
      'pack',
      'publish',
    ]);
  });

  test("a stage the package does not have is refused, naming the package's stages", async () => {
    // A second package whose stage cursor-cloud-acp lacks, so Cliffy's
    // stage type lets it through to the package's own check.
    const two = [
      ...PACKAGES,
      { name: 'other', stages: ['install', 'compile', 'publish'] },
    ];

    await expect(
      parsed(['release', 'cursor-cloud-acp', '--skip', 'compile'], two),
    ).rejects.toThrow(
      new ValidationError(
        'cursor-cloud-acp has no stage "compile"; its stages are install, quality, build, pack, publish',
      ),
    );
    await expect(
      parsed(['release', 'other', '--only', 'build'], two),
    ).rejects.toThrow('other has no stage "build"');
  });

  test.each([
    ['an unknown stage', ['--skip', 'tests']],
    ['an unknown stage in a list', ['--only', 'pack,tests']],
    ['the old check stage', ['--skip', 'check']],
    ['--package, which is gone', ['--package', 'cursor-cloud-acp']],
    ['--npm, which never was', ['--npm', '@chorded/cursor-cloud-acp']],
    ['--only with --skip', ['--only', 'publish', '--skip', 'quality']],
    ['--only with --from', ['--only', 'publish', '--from', 'pack']],
    ['--only with --to', ['--only', 'pack', '--to', 'pack']],
    ['--dry-run with --only publish', ['--dry-run', '--only', 'publish']],
    ['options that leave no stage', ['--from', 'pack', '--to', 'quality']],
    ['a second argument', ['now']],
    ['a version as an argument', ['1.0.0']],
  ])('refuses %s', async (_name, argv) => {
    await expect(
      parsed(['release', 'cursor-cloud-acp', ...argv]),
    ).rejects.toThrow(ValidationError);
  });

  test('an unknown package is refused, listing the packages', async () => {
    await expect(parsed(['release', 'x'])).rejects.toThrow(
      'Expected values: "cursor-cloud-acp"',
    );
  });
});

describe('a bare release', () => {
  const line =
    'release: not clear which package to release: bun dev release <package> (cursor-cloud-acp)';

  test('releases nothing and says so, whatever options it is given', async () => {
    for (const argv of [
      [],
      ['--dry-run'],
      ['--bump', 'minor', '--channel', 'next'],
      ['--only', 'publish'],
      ['--skip', 'build'],
    ]) {
      expect(await parsed(['release', ...argv])).toStrictEqual([
        ['unclear', line],
      ]);
    }
  });

  test("checks that need the package's stages do not run without one", async () => {
    expect(
      await parsed(['release', '--dry-run', '--only', 'publish']),
    ).toStrictEqual([['unclear', line]]);
  });

  test("Cliffy's own refusals still come first: conflicts, values, unknown flags", async () => {
    for (const argv of [
      ['--only', 'publish', '--skip', 'quality'],
      ['--skip', 'tests'],
      ['--bump', 'v1'],
      ['--package', 'cursor-cloud-acp'],
    ]) {
      await expect(parsed(['release', ...argv])).rejects.toThrow(
        ValidationError,
      );
    }
  });

  test('says it on stderr and exits 1, running nothing', () => {
    const result = spawnSync(
      process.execPath,
      [
        new URL('../../scripts/dev.ts', import.meta.url).pathname,
        'release',
        '--dry-run',
      ],
      { encoding: 'utf8', timeout: 10_000 },
    );

    expect(result.stderr).toBe(`${line}\n`);
    expect(result.stdout).toBe('');
    expect(result.status).toBe(1);
  });
});

describe('release --bump', () => {
  test('takes an exact version or a bump', async () => {
    for (const version of ['1.0.0', 'major', 'minor', 'patch', 'fix']) {
      const [call] = await parsed([
        'release',
        'cursor-cloud-acp',
        '--bump',
        version,
        '--dry-run',
      ]);

      expect(call?.[4]).toBe(version);
      expect(call?.[3]).toStrictEqual({ dryRun: true });
    }
  });

  test.each([['v1.0.0'], ['1.0'], ['next'], ['1.0.0+build']])(
    'refuses %s',
    async (version) => {
      await expect(
        parsed(['release', 'cursor-cloud-acp', '--bump', version]),
      ).rejects.toThrow(ValidationError);
    },
  );

  test('needs a value', async () => {
    await expect(
      parsed(['release', 'cursor-cloud-acp', '--bump']),
    ).rejects.toThrow(ValidationError);
  });

  test('is parsed whatever the stages; the release judges it', async () => {
    const [call] = await parsed([
      'release',
      'cursor-cloud-acp',
      '--bump',
      'patch',
      '--only',
      'publish',
    ]);

    expect(call?.[2]).toEqual(['publish']);
    expect(call?.[4]).toBe('patch');
  });
});

describe('release --channel', () => {
  test('passes on the name, the release judges it', async () => {
    for (const name of ['next', 'latest', 'Next']) {
      const [call] = await parsed([
        'release',
        'cursor-cloud-acp',
        '--bump',
        'major',
        '--channel',
        name,
      ]);

      expect(call?.[3]).toMatchObject({ channel: name });
      expect(call?.[4]).toBe('major');
    }
  });

  test('takes no --bump', async () => {
    const [call] = await parsed([
      'release',
      'cursor-cloud-acp',
      '--channel',
      'next',
    ]);

    expect(call?.[3]).toMatchObject({ channel: 'next' });
    expect(call?.[4]).toBeUndefined();
  });

  test('needs a name', async () => {
    await expect(
      parsed(['release', 'cursor-cloud-acp', '--channel']),
    ).rejects.toThrow(ValidationError);
  });
});

test("release's help lists each package's stages", async () => {
  const shown: string[] = [];
  const log = spyOn(console, 'log').mockImplementation((text: string) => {
    shown.push(text);
  });

  try {
    await devCommand(IDLE, PACKAGES).noExit().parse(['release', '--help']);
  } finally {
    log.mockRestore();
  }

  const help = Bun.stripANSI(shown.join('\n')).replace(/ +$/gm, '');

  expect(help).toContain(
    '  Stages:\n    cursor-cloud-acp  install, quality, build, pack, publish\n',
  );
  expect(help).toContain('--bump');
  expect(help).not.toContain('--package');
});

describe('tester: release parsing boundaries', () => {
  test('conflicts are refused with the arguments in either order', async () => {
    for (const pair of [
      [
        ['--only', 'publish'],
        ['--skip', 'quality'],
      ],
      [
        ['--only', 'pack'],
        ['--from', 'build'],
      ],
      [
        ['--only', 'pack'],
        ['--to', 'pack'],
      ],
      [['--package', 'cursor-cloud-acp'], ['--dry-run']],
    ]) {
      for (const parts of [pair, [...pair].reverse()]) {
        await expect(
          parsed(['release', 'cursor-cloud-acp', ...parts.flat()]),
        ).rejects.toThrow(ValidationError);
      }
    }
  });

  test('publish is refused anywhere in a dry-run only list', async () => {
    for (const stages of [
      'pack,publish',
      'publish,pack',
      'quality,publish,pack',
    ]) {
      await expect(
        parsed(['release', 'cursor-cloud-acp', '--dry-run', '--only', stages]),
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
      ['--to', 'compile'],
      ['--skip', 'quality,unknown'],
    ]) {
      await expect(
        parsed(['release', 'cursor-cloud-acp', ...argv]),
      ).rejects.toThrow(ValidationError);
    }
  });

  test('the removed package flag stays refused when publish is not selected', async () => {
    for (const argv of [
      ['--skip', 'publish'],
      ['--only', 'quality'],
      ['--from', 'install', '--to', 'pack'],
    ]) {
      await expect(
        parsed([
          'release',
          'cursor-cloud-acp',
          ...argv,
          '--package',
          'cursor-cloud-acp',
        ]),
      ).rejects.toThrow(ValidationError);
    }
  });
});

test('CHD-531 release help discloses mandatory authentication and dry-run effects', () => {
  const result = spawnSync(
    process.execPath,
    [
      new URL('../../scripts/dev.ts', import.meta.url).pathname,
      'release',
      '--help',
    ],
    { encoding: 'utf8', timeout: 10_000 },
  );

  expect(result.status).toBe(0);

  const help = Bun.stripANSI(result.stdout).replace(/\s+/g, ' ');

  for (const text of [
    'mandatory npm authentication runs for every invocation',
    'including dry runs and runs without publish',
    'stdin and stdout must be terminals',
    'plain npm login once with inherited stdio',
    'then rechecks npm whoami',
    'npm may open a browser and save credentials or registry settings',
    'Stage selection cannot skip authentication',
  ]) {
    expect(help).toContain(text);
  }
});

describe('tester: CHD-577 channel argument boundaries', () => {
  test('channel before the version and an equals value preserve the release selection', async () => {
    for (const argv of [
      [
        'release',
        'cursor-cloud-acp',
        '--channel',
        'beta',
        '--bump',
        '1.0.0',
        '--only',
        'build,quality',
      ],
      [
        'release',
        'cursor-cloud-acp',
        '--bump',
        '1.0.0',
        '--channel=beta',
        '--only',
        'build,quality',
      ],
    ]) {
      const [call] = await parsed(argv);

      expect(call?.slice(2)).toEqual([
        ['quality', 'build'],
        { channel: 'beta', only: ['build', 'quality'] },
        '1.0.0',
      ]);
    }
  });

  test('a channel does not allow publish in a dry run', async () => {
    await expect(
      parsed([
        'release',
        'cursor-cloud-acp',
        '--channel',
        'next',
        '--dry-run',
        '--only',
        'publish',
      ]),
    ).rejects.toThrow(ValidationError);
  });
});

describe('tester: direct lint process boundaries', () => {
  test('fix flags, literal empty arguments and ESLint failure status reach the package caller', async () => {
    const root = join(import.meta.dir, '..', '..');
    const dir = mkdtempSync(join(tmpdir(), 'chord-lint-tester-'));

    try {
      await cp(join(root, 'scripts'), join(dir, 'scripts'), {
        recursive: true,
      });
      await symlink(join(root, 'node_modules'), join(dir, 'node_modules'));
      await writeFile(
        join(dir, 'package.json'),
        JSON.stringify({
          name: 'chord-workspace',
          type: 'module',
          workspaces: ['packages/acp'],
          scripts: { dev: 'bun scripts/dev.ts', eslint: 'bun eslint.ts' },
        }),
      );
      await cp(
        join(dir, 'package.json'),
        join(dir, 'packages/acp/package.json'),
      );
      await writeFile(
        join(dir, 'packages/acp/package.json'),
        JSON.stringify({ name: '@chorded/cursor-cloud-acp', type: 'module' }),
      );
      await writeFile(
        join(dir, 'packages/acp/steps.ts'),
        `export default {
  checks: [],
  lint: [process.execPath, 'run', 'eslint', '.'],
  release: [{ name: 'publish', npm: ['@chorded/cursor-cloud-acp'], tag: 'v{version}' }],
};\n`,
      );
      await writeFile(
        join(dir, 'eslint.ts'),
        [
          "import { writeFileSync } from 'node:fs';",
          "writeFileSync('arguments.json', JSON.stringify(process.argv.slice(2)));",
          'process.exit(Number(process.env.LINT_FIXTURE_STATUS));',
        ].join('\n'),
      );

      for (const status of [0, 23]) {
        const result = spawnSync(
          process.execPath,
          ['dev', 'lint', 'cursor-cloud-acp', '--fix', '--', 'a b.ts', ''],
          {
            cwd: dir,
            encoding: 'utf8',
            timeout: 10_000,
            env: { ...process.env, LINT_FIXTURE_STATUS: String(status) },
          },
        );

        expect(result.error).toBeUndefined();
        expect(result.status, result.stdout + result.stderr).toBe(status);
        expect(
          JSON.parse(await readFile(join(dir, 'arguments.json'), 'utf8')),
        ).toEqual(['.', '--fix', 'a b.ts', '']);
      }
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe('tester: CHD-623 package command boundaries', () => {
  test('ESLint option names stay with lint after the selected package', async () => {
    const args = ['--static', '--bump', 'minor', '--package', 'x'];

    expect(await parsed(['lint', 'cursor-cloud-acp', ...args])).toEqual([
      ['lint', 'cursor-cloud-acp', args],
    ]);
    expect(
      await parsed(['lint', 'cursor-cloud-acp', '--', '', '--help']),
    ).toEqual([['lint', 'cursor-cloud-acp', ['', '--help']]]);
  });

  test('quality never interprets an npm scope or a folder as a package name', async () => {
    for (const name of [
      '@chorded/cursor-cloud-acp',
      'packages/cursor-cloud-acp',
    ]) {
      await expect(parsed(['quality', name])).rejects.toThrow(
        'Expected values: "cursor-cloud-acp"',
      );
    }
  });

  async function checkout() {
    const dir = mkdtempSync(join(tmpdir(), 'chord-package-command-'));
    const root = join(import.meta.dir, '..', '..');

    await cp(join(root, 'scripts'), join(dir, 'scripts'), { recursive: true });
    await symlink(join(root, 'node_modules'), join(dir, 'node_modules'));
    await writeFile(
      join(dir, 'package.json'),
      JSON.stringify({
        name: 'chord-workspace',
        type: 'module',
        workspaces: ['packages/*'],
        scripts: { dev: 'bun scripts/dev.ts' },
      }),
    );
    await cp(join(dir, 'package.json'), join(dir, 'workspace-manifest.json'));

    return dir;
  }

  function invoked(dir: string, args: string[]) {
    return spawnSync(process.execPath, ['dev', ...args], {
      cwd: dir,
      encoding: 'utf8',
      timeout: 20_000,
    });
  }

  test('quality runs only the selected package, preserves status and stops before later checks', async () => {
    const dir = await checkout();

    try {
      const writePackage = async (folder: string, name: string) => {
        const here = join(dir, folder);

        await cp(
          join(dir, 'workspace-manifest.json'),
          join(here, 'package.json'),
        );
        await writeFile(
          join(here, 'package.json'),
          JSON.stringify({ name: `@chorded/${name}`, type: 'module' }),
        );

        const checks = [
          { name: 'static', static: true, status: 0 },
          { name: 'dynamic', status: 17 },
          { name: 'after', status: 0 },
        ].map(({ name: step, static: only, status }) => ({
          name: step,
          static: only,
          run: [
            process.execPath,
            '-e',
            `import { appendFileSync } from 'node:fs'; appendFileSync('ran.log', ${JSON.stringify(`${name}:${step}\n`)}); process.exit(${status});`,
          ],
        }));

        await writeFile(
          join(here, 'steps.ts'),
          `export default ${JSON.stringify({
            checks,
            lint: [],
            release: [
              { name: 'publish', npm: [`@chorded/${name}`], tag: 'v{version}' },
            ],
          })};\n`,
        );
      };

      // cp creates the workspace's parents; the runner must still use the root cwd.
      await writePackage('packages/acp', 'cursor-cloud-acp');
      await writePackage('packages/other', 'other');

      for (const name of ['other', 'cursor-cloud-acp']) {
        const result = invoked(dir, ['quality', name, '--static']);

        expect(result.error).toBeUndefined();
        expect(result.status, result.stdout + result.stderr).toBe(0);
      }

      const result = invoked(dir, ['quality', 'cursor-cloud-acp']);

      expect(result.error).toBeUndefined();
      expect(result.status, result.stdout + result.stderr).toBe(17);
      expect(result.stderr).toContain(
        'quality cursor-cloud-acp: dynamic failed with status 17',
      );
      expect(await readFile(join(dir, 'ran.log'), 'utf8')).toBe(
        'other:static\ncursor-cloud-acp:static\ncursor-cloud-acp:static\ncursor-cloud-acp:dynamic\n',
      );
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test('a broken workspace steps file stops even help before any check runs', async () => {
    const dir = await checkout();

    try {
      await cp(
        join(dir, 'workspace-manifest.json'),
        join(dir, 'packages/acp/package.json'),
      );
      await writeFile(
        join(dir, 'packages/acp/package.json'),
        '{"name":"@chorded/cursor-cloud-acp"}',
      );
      await writeFile(
        join(dir, 'packages/acp/steps.ts'),
        "throw new Error('fixture steps failed');\n",
      );

      for (const args of [['--help'], ['release', '--help']]) {
        const result = invoked(dir, args);

        expect(result.error).toBeUndefined();
        expect(result.status).toBe(1);
        expect(result.stderr).toContain(
          'bun dev: packages/acp/steps.ts: fixture steps failed',
        );
        expect(result.stdout).toBe('');
      }
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
