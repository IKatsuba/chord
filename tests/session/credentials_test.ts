import { describe, expect, test } from 'bun:test';
import { credentialNotice } from '../../src/session/credentials.ts';

describe('riff credential status boundary', () => {
  test('keeps only provider and state, never credential fields', () => {
    expect(
      credentialNotice({
        method: '_chord/credentials',
        params: {
          provider: 'codex',
          state: 'unsaved',
          accessToken: 'private fixture',
        },
      }),
    ).toEqual({ provider: 'codex', state: 'unsaved' });
  });

  test('ignores malformed and unrelated notifications', () => {
    for (const message of [
      undefined,
      {},
      {
        method: 'session/update',
        params: { provider: 'grok', state: 'saved' },
      },
      {
        method: '_chord/credentials',
        params: { provider: 'other', state: 'saved' },
      },
      {
        method: '_chord/credentials',
        params: { provider: 'grok', state: 'other' },
      },
    ]) {
      expect(credentialNotice(message)).toBeUndefined();
    }
  });
});
