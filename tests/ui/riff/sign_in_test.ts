import { describe, expect, test } from 'bun:test';
import { initialSignIn } from '../../../src/riff/sign_in.ts';
import { signInView } from '../../../src/ui/riff/sign_in.ts';
import { initialRiff } from '../../../src/ui/riff/state.ts';

describe('riff sign-in box words', () => {
  test('the active plan has a check independent from selection', () => {
    const state = {
      ...initialRiff(),
      provider: 'grok' as const,
      flow: initialSignIn(),
    };
    const view = signInView(state, 'fixture store', 0);

    expect(view?.choices[0]?.label).not.toContain('✔');
    expect(view?.choices[1]?.label).toContain('Grok');
    expect(view?.choices[1]?.label).toContain('✔');
  });

  test('the last partial minute is worded as less than a minute', () => {
    const state = {
      ...initialRiff(),
      flow: {
        attempt: 4,
        step: {
          kind: 'code' as const,
          provider: 'codex' as const,
          way: 'code' as const,
          code: 'WXYZ-1234',
          address: 'https://example.invalid',
          expiresAt: 50_000,
        },
      },
    };

    expect(signInView(state, 'fixture store', 0)?.foot).toContain(
      'in less than a minute.',
    );
    expect(
      signInView(state, 'fixture store', 0)?.choices.map(
        (choice) => choice.value,
      ),
    ).toEqual(['open', 'copy_code', 'copy_address']);
  });

  test('the slow store retry keeps the cause visible with no active choices', () => {
    const state = {
      ...initialRiff(),
      flow: {
        attempt: 3,
        step: {
          kind: 'reading_store' as const,
          provider: undefined,
          store: 'macOS Keychain',
          message: 'The macOS Keychain did not answer in 20 s.',
        },
      },
    };
    const view = signInView(state, 'macOS Keychain', 4000);

    expect(view?.body).toBe('The macOS Keychain did not answer in 20 s.');
    expect(view?.working).toBe(
      'Reading the sign-in from the macOS Keychain… (4s)',
    );
    expect(view?.choices).toEqual([]);
    expect(view?.hint).toBe('Esc to cancel');
  });
});
