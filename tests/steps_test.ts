import { expect, test } from 'bun:test';
import steps from '../steps.ts';
import { isPublish } from '../scripts/dev/steps.ts';

test("chord's checks are the six, in order, only the suite not static", () => {
  expect(
    steps.checks.map((check) => [check.name, check.static === true]),
  ).toEqual([
    ['types', true],
    ['covered', true],
    ['eslint', true],
    ['format', true],
    ["lint/'s tests", true],
    ['the suite', false],
  ]);
});

test('no check of chord names packages/, the other packages', () => {
  for (const check of steps.checks) {
    expect(JSON.stringify(check.run)).not.toContain('packages');
  }
});

test("chord's release is today's nine stages, check renamed quality", () => {
  expect(steps.release.map((stage) => stage.name)).toEqual([
    'install',
    'quality',
    'natives',
    'compile',
    'sign',
    'selftest',
    'notarise',
    'pack',
    'publish',
  ]);
});

test('signing stages need the arm64 Mac, and compile carries the version', () => {
  const stages = steps.release.filter((stage) => !isPublish(stage));

  expect(
    stages.filter((stage) => 'machine' in stage).map((stage) => stage.name),
  ).toEqual(['natives', 'sign', 'notarise']);
  expect(
    stages.filter((stage) => 'versioned' in stage).map((stage) => stage.name),
  ).toEqual(['compile']);
});

test("publish sends chord's five npm names, the main one last, with a GitHub release", () => {
  const publish = steps.release.at(-1)!;

  expect(publish).toEqual({
    name: 'publish',
    npm: [
      '@chorded/chord-darwin-arm64',
      '@chorded/chord-darwin-x64',
      '@chorded/chord-linux-arm64',
      '@chorded/chord-linux-x64',
      '@chorded/chord',
    ],
    tag: 'v{version}',
    githubRelease: true,
  });
});
