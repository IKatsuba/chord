import { expect, test } from 'bun:test';
import steps from '../steps.ts';
import { isPublish } from '../../../scripts/dev/steps.ts';

const bun = process.execPath;
const here = 'packages/cursor-cloud-acp';

test('its checks, in order: the five static ones, then its tests, build and smoke', () => {
  expect(
    steps.checks.map((check) => [check.name, check.static === true]),
  ).toEqual([
    ['types', true],
    ['tooling types', true],
    ['covered', true],
    ['eslint', true],
    ['format', true],
    ['tests', false],
    ['build', false],
    ['smoke', false],
  ]);
});

test('each argv check reaches this folder alone', () => {
  expect(
    steps.checks.flatMap((check) =>
      Array.isArray(check.run) ? [check.run] : [],
    ),
  ).toEqual([
    [bun, 'check', '-p', here],
    [bun, 'check', '-p', `${here}/tsconfig.tools.json`],
    [bun, 'scripts/dev/covered.ts', here],
    [bun, 'run', 'eslint', '--config', `${here}/eslint.config.ts`, here],
    [bun, 'fmt', '--check', here],
    [bun, 'test', `./${here}/tests/`],
  ]);
  expect(steps.lint).toEqual([
    bun,
    'run',
    'eslint',
    '--config',
    `${here}/eslint.config.ts`,
    here,
  ]);
});

test('its release: install, quality, build (versioned), pack, then publish with its own tag', () => {
  expect(steps.release.map((stage) => stage.name)).toEqual([
    'install',
    'quality',
    'build',
    'pack',
    'publish',
  ]);

  const publish = steps.release.at(-1)!;

  expect(isPublish(publish) && publish).toEqual({
    name: 'publish',
    npm: ['@chorded/cursor-cloud-acp'],
    tag: 'cursor-cloud-acp-v{version}',
  });
  expect(
    steps.release
      .filter((stage) => !isPublish(stage) && stage.versioned === true)
      .map((stage) => stage.name),
  ).toEqual(['build']);
});
