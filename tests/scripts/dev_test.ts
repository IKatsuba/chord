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
