import { describe, expect, test } from 'bun:test';
import { credentialWords } from '../../../src/ui/status/credentials.ts';

describe('riff credential notice words', () => {
  for (const provider of ['codex', 'grok'] as const) {
    test(`${provider} uses the design's display name and outcome`, () => {
      const name = provider === 'codex' ? 'ChatGPT' : 'Grok';

      expect(credentialWords({ provider, state: 'unsaved' })).toBe(
        `${name} sign-in refreshed but not saved; will retry.`,
      );
      expect(credentialWords({ provider, state: 'saved' })).toBe(
        `${name} sign-in saved.`,
      );
      expect(credentialWords({ provider, state: 'signed_out' })).toBe(
        `${name} sign-in removed. This session is signed out.`,
      );
      expect(credentialWords({ provider, state: 'account_changed' })).toBe(
        `${name} account changed. This session is signed out.`,
      );
    });
  }
});
