import { describe, expect, test } from 'bun:test';
import { ValidationError } from '@cliffy/command';
import {
  type ReleaseOptions,
  selectStages as selectOf,
} from '../../../../scripts/dev/release/select.ts';

const STAGES = [
  'install',
  'quality',
  'natives',
  'compile',
  'sign',
  'selftest',
  'notarise',
  'pack',
  'publish',
];

/** chord's stages the options leave. */
const selectStages = (options: ReleaseOptions) =>
  selectOf({ name: 'chord', stages: STAGES }, options);

describe('the stages a run leaves', () => {
  test('every stage, in order, with no options', () => {
    expect(selectStages({})).toStrictEqual([...STAGES]);
  });

  test('a dry run leaves out publish alone', () => {
    expect(selectStages({ dryRun: true })).toStrictEqual(
      STAGES.filter((stage) => stage !== 'publish'),
    );
  });

  test('--skip leaves out the stages named', () => {
    expect(selectStages({ skip: ['quality', 'notarise'] })).toStrictEqual([
      'install',
      'natives',
      'compile',
      'sign',
      'selftest',
      'pack',
      'publish',
    ]);
  });

  test('--only keeps the release order, whatever order it is given in', () => {
    expect(selectStages({ only: ['publish', 'pack'] })).toStrictEqual([
      'pack',
      'publish',
    ]);
  });

  test('--from and --to bound the run, both ends included', () => {
    expect(selectStages({ from: 'sign' })).toStrictEqual([
      'sign',
      'selftest',
      'notarise',
      'pack',
      'publish',
    ]);
    expect(selectStages({ to: 'compile' })).toStrictEqual([
      'install',
      'quality',
      'natives',
      'compile',
    ]);
    expect(selectStages({ from: 'selftest', to: 'pack' })).toStrictEqual([
      'selftest',
      'notarise',
      'pack',
    ]);
  });

  test('--from and --to with --skip', () => {
    expect(
      selectStages({ from: 'compile', to: 'pack', skip: ['notarise'] }),
    ).toStrictEqual(['compile', 'sign', 'selftest', 'pack']);
  });

  test('--dry-run with --skip, as the run without Apple', () => {
    expect(selectStages({ dryRun: true, skip: ['notarise'] })).toStrictEqual([
      'install',
      'quality',
      'natives',
      'compile',
      'sign',
      'selftest',
      'pack',
    ]);
  });
});

describe('refused', () => {
  test("a stage the package does not have, naming the package's stages", () => {
    const one = { name: 'one', stages: ['build', 'pack', 'publish'] };

    for (const options of [
      { skip: ['compile'] },
      { only: ['pack', 'compile'] },
      { from: 'compile' },
      { to: 'compile' },
    ]) {
      expect(() => selectOf(one, options)).toThrow(
        new ValidationError(
          'one has no stage "compile"; its stages are build, pack, publish',
        ),
      );
    }
  });

  test("another package's stages, in its own order", () => {
    const one = { name: 'one', stages: ['build', 'pack', 'publish'] };

    expect(selectOf(one, {})).toStrictEqual(['build', 'pack', 'publish']);
    expect(selectOf(one, { dryRun: true, from: 'pack' })).toStrictEqual([
      'pack',
    ]);
  });

  test('--dry-run with --only publish', () => {
    expect(() => selectStages({ dryRun: true, only: ['publish'] })).toThrow(
      ValidationError,
    );
  });

  test('options that leave no stage', () => {
    expect(() => selectStages({ from: 'pack', to: 'install' })).toThrow(
      ValidationError,
    );
    expect(() =>
      selectStages({ only: ['quality'], skip: ['quality'] }),
    ).toThrow(ValidationError);
  });
});

test('--dry-run refuses publish anywhere in --only', () => {
  expect(() =>
    selectStages({ dryRun: true, only: ['pack', 'publish'] }),
  ).toThrow(ValidationError);
});

describe('tester: stage selection boundaries', () => {
  test('equal range endpoints select exactly one stage', () => {
    for (const stage of STAGES) {
      expect(selectStages({ from: stage, to: stage })).toStrictEqual([stage]);
    }
  });

  test('duplicate stages are run once in release order', () => {
    expect(
      selectStages({ only: ['publish', 'quality', 'publish', 'quality'] }),
    ).toStrictEqual(['quality', 'publish']);
    expect(selectStages({ skip: ['quality', 'quality'] })).toStrictEqual(
      STAGES.filter((stage) => stage !== 'quality'),
    );
  });

  test('removing every selected stage refuses the run', () => {
    expect(() => selectStages({ skip: STAGES })).toThrow(ValidationError);
    expect(() =>
      selectStages({ dryRun: true, from: 'publish', to: 'publish' }),
    ).toThrow(ValidationError);
  });
});
