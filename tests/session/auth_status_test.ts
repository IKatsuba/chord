import { expect, test } from 'bun:test';
import {
  type AccountEvent,
  foldAccount,
  NO_ACCOUNT,
} from '../../src/session/auth_status.ts';

const fold = (...events: AccountEvent[]) =>
  events.reduce(foldAccount, NO_ACCOUNT);

const SIGNED_IN = {
  state: 'authenticated',
  accounts: [{ label: 'Claude Max', email: 'name@example.com', active: true }],
};

test('none until asked, pending once asked, and the last status heard', () => {
  expect(fold()).toStrictEqual({ phase: 'none' });
  expect(fold({ type: 'asked' })).toStrictEqual({ phase: 'pending' });
  expect(
    fold(
      { type: 'asked' },
      { type: 'heard', status: SIGNED_IN },
      { type: 'heard', status: { state: 'unauthenticated' } },
    ),
  ).toStrictEqual({ phase: 'heard', status: { state: 'unauthenticated' } });
});

test('a push after a failed request is heard; a request failing after a push keeps the push', () => {
  expect(
    fold(
      { type: 'asked' },
      { type: 'failed' },
      { type: 'heard', status: SIGNED_IN },
    ),
  ).toStrictEqual({ phase: 'heard', status: SIGNED_IN });
  expect(
    fold(
      { type: 'asked' },
      { type: 'heard', status: SIGNED_IN },
      { type: 'failed' },
    ),
  ).toStrictEqual({ phase: 'heard', status: SIGNED_IN });
  expect(fold({ type: 'asked' }, { type: 'failed' })).toStrictEqual({
    phase: 'failed',
  });
});

test('a state word the schema leaves open reads unknown, the rest kept', () => {
  expect(
    fold({ type: 'heard', status: { state: 'expired', accounts: [] } }),
  ).toStrictEqual({
    phase: 'heard',
    status: { state: 'unknown', accounts: [] },
  });
  expect(
    fold({ type: 'heard', status: { state: 'not_required' } }),
  ).toStrictEqual({ phase: 'heard', status: { state: 'not_required' } });
});
