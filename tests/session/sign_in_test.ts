import { describe, expect, test } from 'bun:test';
import { RequestError } from '@agentclientprotocol/sdk';
import {
  asSignIn,
  offersLine,
  SignInNeeded,
  signInLines,
  signInNote,
  signInOf,
  wayOn,
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
  const error = asSignIn(refused, METHODS);

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
    signInOf(asSignIn(RequestError.authRequired(), undefined)),
  ).toStrictEqual({ message: 'Authentication required', ways: [] });
});

test('another failure is not a sign-in, whatever its words say', () => {
  const other = new RequestError(-32603, 'Sign-in was cancelled.');

  expect(asSignIn(other, METHODS)).toBe(other);
  expect(signInOf(other)).toBeUndefined();
});

test('a sign-in is found under the error that wraps it', () => {
  const wrapped = new Error('it cannot resume session s: …', {
    cause: asSignIn(RequestError.authRequired(), []),
  });

  expect(signInOf(wrapped)?.message).toStrictEqual('Authentication required');
  expect(signInOf(new Error('boom'))).toBeUndefined();
});

const SIGN_IN = {
  message: 'Authentication required',
  ways: [
    {
      name: 'Kilo login',
      description: 'Run `kilo auth login` in the terminal',
    },
  ],
};

test("the way on is chord's own line, and the ways in are counted", () => {
  expect(wayOn('kilo')).toStrictEqual(
    "chord does not sign agents in. Sign in with kilo's own CLI in a terminal, or set its API key where it offers one.",
  );
  expect(offersLine('kilo', 1)).toStrictEqual('kilo offers this sign-in:');
  expect(offersLine('droid', 2)).toStrictEqual('droid offers these sign-ins:');
});

test('as plain text, the ways in are a line, names only when that is all there is', () => {
  expect(signInLines('kilo', SIGN_IN)).toStrictEqual([
    'kilo offers: Kilo login (Run `kilo auth login` in the terminal)',
    wayOn('kilo'),
  ]);
  expect(
    signInLines('droid', {
      message: 'm',
      ways: [{ name: 'device-pairing' }, { name: 'factory-api-key' }],
    }),
  ).toStrictEqual([
    'droid offers: device-pairing, factory-api-key',
    wayOn('droid'),
  ]);
  expect(signInLines('kimi', { message: 'm', ways: [] })).toStrictEqual([
    wayOn('kimi'),
  ]);
});

test('an agent that opened one is told the person signs in, not it', () => {
  expect(signInNote('kilo', SIGN_IN)).toStrictEqual(
    " It offers: Kilo login (Run `kilo auth login` in the terminal). chord does not sign agents in: the person signs in with kilo's own CLI in a terminal, or sets its API key where it offers one.",
  );
  expect(signInNote('kimi', { message: 'm', ways: [] })).toStrictEqual(
    " chord does not sign agents in: the person signs in with kimi's own CLI in a terminal, or sets its API key where it offers one.",
  );
});

describe('CHD-435 tester: structured sign-in classification', () => {
  test('message words and a string code never classify a failure as authRequired', () => {
    for (const failure of [
      new Error('Authentication required: Sign-in was cancelled.'),
      Object.assign(new Error('Authentication required'), { code: '-32000' }),
      Object.assign(new Error('Sign-in was cancelled.'), { code: -32603 }),
      null,
      'Authentication required',
    ]) {
      expect(asSignIn(failure, METHODS)).toBe(failure);
      expect(signInOf(failure)).toBeUndefined();
    }
  });

  test('nested wrappers retain exact sign-in identity and description-only methods stay ordered', () => {
    const methods = [
      { id: 'description', name: '  ', description: '  Run `agent login`  ' },
      { id: 'empty', name: '', description: ' ' },
      { id: 'named', name: '  SSO  ' },
    ];
    const before = structuredClone(methods);
    const needed = asSignIn(RequestError.authRequired(), methods);
    const wrapped = new Error('outer', {
      cause: new Error('inner', { cause: needed }),
    });

    expect(waysOf(methods)).toStrictEqual([
      { description: 'Run `agent login`' },
      { name: 'SSO' },
    ]);
    expect(methods).toStrictEqual(before);
    expect(signInOf(wrapped)).toBe(signInOf(needed));
  });
});
