import { expect, test } from 'bun:test';
import { RequestError } from '@agentclientprotocol/sdk';
import {
  asSignIn,
  SignInNeeded,
  signInOf,
  waysOf,
} from '../../src/session/sign_in.ts';

const METHODS = [
  {
    id: 'login',
    name: 'Log in',
    description: 'Run `agent login` in the terminal',
  },
  { id: 'sso', name: 'Log in with SSO' },
  { id: 'empty', name: ' ', description: '' },
];

test("authRequired is a sign-in, in the agent's words, with the ways in it offers", () => {
  const refused = RequestError.authRequired(undefined, 'run `agent login`');
  const error = asSignIn(refused, METHODS, false);

  expect(error).toBeInstanceOf(SignInNeeded);
  expect(signInOf(error)).toStrictEqual({
    message: 'Authentication required: run `agent login`',
    ways: [
      { name: 'Log in', description: 'Run `agent login` in the terminal' },
      { name: 'Log in with SSO' },
    ],
  });
  expect((error as Error).cause).toBe(refused);
});

test('an agent that offers no ways in has none', () => {
  expect(
    signInOf(asSignIn(RequestError.authRequired(), undefined, false)),
  ).toStrictEqual({ message: 'Authentication required', ways: [] });
});

test('another failure is not a sign-in, whatever its words say, unless chord cancelled a sign-in link nobody could answer', () => {
  const other = new RequestError(-32603, 'Sign-in was cancelled.');

  expect(asSignIn(other, METHODS, false)).toBe(other);
  expect(signInOf(asSignIn(other, METHODS, true))).toStrictEqual({
    message: 'Sign-in was cancelled.',
    ways: waysOf(METHODS),
  });
});

test('a sign-in is found under the error that wraps it', () => {
  const wrapped = new Error('it cannot resume session s: …', {
    cause: asSignIn(RequestError.authRequired(), [], false),
  });

  expect(signInOf(wrapped)?.message).toStrictEqual('Authentication required');
  expect(signInOf(new Error('boom'))).toBeUndefined();
});
