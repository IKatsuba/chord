import { describe, expect, test } from 'bun:test';
import { riffWindowAccess } from '../../src/riff/window_access.ts';
import { memorySecrets } from '../../src/platform/secrets.ts';

describe('riff window access boundary', () => {
  test.each(['', '1'])(
    'fake and QA (%s) never select the system store',
    async (qa) => {
      const access = riffWindowAccess(
        {
          CHORD_RIFF_FAKE_PROVIDER: 'http://127.0.0.1:23456',
          CHORD_RIFF_QA: qa,
          CHORD_RIFF_QA_STATE: 'signed-out',
        },
        () => {
          throw new Error('must not reach system store');
        },
      );

      expect(access.fixture).toBe(true);
      expect(access.run).toBeDefined();
      expect(await access.store.get('codex')).toBeNull();
      expect(
        await access.fetch('https://auth.x.ai/oauth2/revoke', {}),
      ).toBeInstanceOf(Response);
      await expect(
        access.fetch('https://example.invalid/unlisted', {}),
      ).rejects.toThrow('Unexpected fixture');
    },
  );

  test('production selects only the explicitly injected system backend', () => {
    const store = memorySecrets();
    const access = riffWindowAccess({}, () => store);

    expect(access.store).toBe(store);
    expect(access.fixture).toBeUndefined();
    expect(access.run).toBeUndefined();
  });
});
