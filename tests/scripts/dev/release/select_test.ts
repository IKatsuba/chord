import { describe, expect, test } from 'bun:test';
import { ValidationError } from '@cliffy/command';
import {
  selectStages,
  STAGES,
} from '../../../../scripts/dev/release/select.ts';

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
    expect(selectStages({ skip: ['check', 'notarise'] })).toStrictEqual([
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
      'check',
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
      'check',
      'natives',
      'compile',
      'sign',
      'selftest',
      'pack',
    ]);
  });

  test('--package with publish in the run', () => {
    expect(
      selectStages({ only: ['publish'], package: 'chord-linux-x64' }),
    ).toStrictEqual(['publish']);
  });
});

describe('refused', () => {
  test('--dry-run with --only publish', () => {
    expect(() => selectStages({ dryRun: true, only: ['publish'] })).toThrow(
      ValidationError,
    );
  });

  test('--package without publish in the run', () => {
    expect(() =>
      selectStages({ to: 'pack', package: 'chord-linux-x64' }),
    ).toThrow(ValidationError);
    expect(() => selectStages({ skip: ['publish'], package: 'chord' })).toThrow(
      ValidationError,
    );
  });

  test('options that leave no stage', () => {
    expect(() => selectStages({ from: 'pack', to: 'install' })).toThrow(
      ValidationError,
    );
    expect(() => selectStages({ only: ['check'], skip: ['check'] })).toThrow(
      ValidationError,
    );
  });
});
