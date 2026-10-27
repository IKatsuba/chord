import { describe, expect, test } from 'bun:test';
import {
  resolveResourceExecutable,
  type ExecutableInspection,
} from '../../src/platform/resource_executable.ts';

const options = {
  cwd: '/project',
  signal: new AbortController().signal,
  customCommand: false,
};
const inspection: ExecutableInspection = {
  platform: 'darwin',
  arch: 'arm64',
  lookup: () => Promise.resolve('/fixture/codex'),
  native: () => Promise.resolve(true),
  version: () => Promise.resolve('codex-cli 0.163.0'),
};

describe('official native collector resolution', () => {
  test('resolves evaluated native versions, without using an ACP command as the provider path', async () => {
    expect(
      await resolveResourceExecutable('codex', options, inspection),
    ).toEqual({ path: '/fixture/codex', version: '0.163.0' });

    let lookups = 0;
    const result = await resolveResourceExecutable(
      'codex',
      { ...options, customCommand: true },
      {
        ...inspection,
        lookup: () => {
          lookups++;

          return Promise.resolve('/wrapper');
        },
      },
    );

    expect(result).toHaveProperty('unavailable');
    expect(lookups).toBe(0);
  });

  test('official Codex launcher uses its existing Node; Claude remains native-only', async () => {
    const launcher = { ...inspection, native: () => Promise.resolve(false) };

    expect(await resolveResourceExecutable('codex', options, launcher)).toEqual(
      { path: '/fixture/codex', version: '0.163.0' },
    );
    expect(
      await resolveResourceExecutable('claude', options, launcher),
    ).toHaveProperty('unavailable');
    expect(
      await resolveResourceExecutable('codex', options, {
        ...launcher,
        lookup: (name) =>
          Promise.resolve(name === 'node' ? undefined : '/fixture/codex'),
      }),
    ).toHaveProperty('unavailable');
  });

  test('missing, unverified-version and unsupported targets are advisory', async () => {
    for (const override of [
      { lookup: () => Promise.resolve(undefined) },
      { version: () => Promise.resolve('codex-cli 0.164.0') },
      { platform: 'linux' },
    ]) {
      expect(
        await resolveResourceExecutable('codex', options, {
          ...inspection,
          ...override,
        }),
      ).toHaveProperty('unavailable');
    }
  });
});
