import { describe, expect, test } from 'bun:test';
import { CHORDED_AGENTS } from '../../../../src/chorded.ts';
import { pinsOnNpm } from '../../../../scripts/dev/release/pins.ts';
import steps from '../../../../steps.ts';

test('every pin npm has passes, each asked by its exact version', () => {
  const asked: string[] = [];

  pinsOnNpm(
    (spec) => {
      asked.push(spec);

      return spec.split('@').at(-1);
    },
    [
      { package: '@chorded/cursor-cloud-acp', version: '0.1.0' },
      { package: '@chorded/other-acp', version: '1.2.3' },
    ],
  );
  expect(asked).toEqual([
    '@chorded/cursor-cloud-acp@0.1.0',
    '@chorded/other-acp@1.2.3',
  ]);
});

test('a pin npm lacks stops the release, naming it and the way on', () => {
  expect(() =>
    pinsOnNpm(
      () => undefined,
      [{ package: '@chorded/cursor-cloud-acp', version: '0.1.0' }],
    ),
  ).toThrow(
    'npm has no @chorded/cursor-cloud-acp@0.1.0, which src/chorded.ts pins: release @chorded/cursor-cloud-acp first, or pin a version npm has',
  );
});

test("chord's pins are src/chorded.ts's, and chord's steps ask for them", () => {
  expect(
    CHORDED_AGENTS.map((agent) => `${agent.package}@${agent.version}`),
  ).toEqual(['@chorded/cursor-cloud-acp@0.1.0']);
  expect(steps.preflight).toBeFunction();
});

describe('CHD-622 tester: release pin refusal', () => {
  test('a different published version refuses the first pin before checking later agents', () => {
    const asked: string[] = [];

    expect(() =>
      pinsOnNpm(
        (spec) => {
          asked.push(spec);

          return '0.1.1';
        },
        [
          { package: '@chorded/cursor-cloud-acp', version: '0.1.0' },
          { package: '@chorded/other-acp', version: '1.2.3' },
        ],
      ),
    ).toThrow('release @chorded/cursor-cloud-acp first');
    expect(asked).toEqual(['@chorded/cursor-cloud-acp@0.1.0']);
  });
});
