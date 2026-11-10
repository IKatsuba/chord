import { describe, expect, test } from 'bun:test';
import {
  credentialNotice,
  riffProvider,
} from '../../src/session/credentials.ts';

test('riff provider metadata accepts only a public plan name', () => {
  expect(riffProvider({ 'chord/riffProvider': 'grok' })).toBe('grok');
  expect(
    riffProvider({ 'chord/riffProvider': 'codex', token: 'fixture' }),
  ).toBe('codex');
  expect(riffProvider({ 'chord/riffProvider': 'fake' })).toBeUndefined();
  expect(riffProvider(undefined)).toBeUndefined();
});

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

describe('CHD-606 tester: malformed credential notices', () => {
  test('rejects wrong envelope and value types without reading credential text', () => {
    for (const params of [
      null,
      false,
      'saved',
      ['grok', 'saved'],
      { provider: 'grok', state: null },
      { provider: 'grok', state: ['saved'] },
      { provider: { accessToken: 'fixture' }, state: 'saved' },
      { provider: 'codex', state: 'SAVED' },
    ]) {
      expect(
        credentialNotice({ method: '_chord/credentials', params }),
      ).toBeUndefined();
    }

    expect(
      credentialNotice(
        JSON.stringify({
          method: '_chord/credentials',
          params: { provider: 'grok', state: 'saved' },
        }),
      ),
    ).toBeUndefined();
  });
});
