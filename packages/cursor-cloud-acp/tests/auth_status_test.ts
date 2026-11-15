import { describe, expect, test } from 'bun:test';
import { authenticated } from '../src/auth_status.ts';

const USER = { apiKeyName: 'chord', createdAt: '2026-11-01' };

describe('authenticated', () => {
  test('joins the names sent, leaving out what is empty or missing', () => {
    const found = { apiKey: 'key_x', source: 'env' } as const;

    expect(
      authenticated(found, { ...USER, userFirstName: 'Ada', userEmail: '' }),
    ).toEqual({
      state: 'authenticated',
      accounts: [
        {
          label: 'Cursor',
          description: 'CURSOR_API_KEY',
          active: true,
          name: 'Ada',
        },
      ],
    });
    expect(
      authenticated(found, { ...USER, userLastName: 'Lovelace' }).accounts,
    ).toEqual([
      {
        label: 'Cursor',
        description: 'CURSOR_API_KEY',
        active: true,
        name: 'Lovelace',
      },
    ]);
  });

  test("the keychain entry's expiry as its UTC day; the key never appears", () => {
    const status = authenticated(
      {
        apiKey: 'key_secret',
        source: 'keychain',
        expiresAtMs: Date.UTC(2027, 1, 13, 23, 59),
      },
      { ...USER, userEmail: 'ada@example.com' },
    );

    expect(status.accounts?.[0]?.description).toBe(
      'keychain, expires 2027-02-13',
    );
    expect(JSON.stringify(status)).not.toContain('key_secret');
    expect(JSON.stringify(status)).not.toContain('chord');
  });
});
