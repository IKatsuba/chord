import { expect, jest, spyOn, test } from 'bun:test';
import { riffAccess, QA_ENV, QA_STATE_ENV } from '../../src/riff/qa.ts';
import { FAKE_PROVIDER_ENV } from '../../src/riff/start.ts';
import {
  SECRET_TIMEOUT,
  SecretStoreTimeout,
} from '../../src/platform/secrets.ts';

// Own isolated file: a wedged backend intentionally never releases its serial
// slot, as a real wedged system store would not. No real store is touched.
test('QA timeout is bounded with a fake backend and never calls Bun.secrets', async () => {
  const real = spyOn(Bun.secrets, 'get').mockImplementation(() => {
    throw new Error('real store');
  });

  jest.useFakeTimers();

  try {
    const access = riffAccess({
      [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1',
      [QA_ENV]: '1',
      [QA_STATE_ENV]: 'timeout',
    });
    const result = access.secrets.get('codex').catch((error: unknown) => error);

    jest.advanceTimersByTime(SECRET_TIMEOUT);
    expect(await result).toBeInstanceOf(SecretStoreTimeout);
    expect(real).not.toHaveBeenCalled();
  } finally {
    jest.useRealTimers();
    real.mockRestore();
  }
});
