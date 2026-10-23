/**
 * A start that failed because the agent needs a login: chord does not sign
 * agents in (CHD-435), so it says so with the agent's own words and the ways
 * in the agent offers, read from the protocol, never from the text.
 */
import type { AuthMethod } from '@agentclientprotocol/sdk';

/** ACP's `authRequired`: the agent needs a login before it opens a session. */
export const AUTH_REQUIRED = -32000;

/** A way in the agent offers, in its own words. */
export interface SignInWay {
  readonly name?: string;
  readonly description?: string;
}

/** Why a start failed for want of a login, and the agent's ways in. */
export interface SignIn {
  /** The agent's own words for the failure. */
  readonly message: string;
  readonly ways: readonly SignInWay[];
}

/** A start that failed for want of a login; its message is the agent's. */
export class SignInNeeded extends Error {
  constructor(
    readonly signIn: SignIn,
    options?: ErrorOptions,
  ) {
    super(signIn.message, options);

    this.name = 'SignInNeeded';
  }
}

/**
 * The ways in `methods` names, each by its name and description; one with
 * neither says nothing and is left out.
 */
export function waysOf(
  methods: readonly AuthMethod[] | null | undefined,
): SignInWay[] {
  return (methods ?? []).flatMap((method) => {
    const name = method.name.trim();
    const description =
      'description' in method ? method.description?.trim() : undefined;
    const way = {
      ...(name === '' ? {} : { name }),
      ...(description === undefined || description === ''
        ? {}
        : { description }),
    };

    return Object.keys(way).length === 0 ? [] : [way];
  });
}

/**
 * `error`, a failed session request of the start, as a `SignInNeeded` when
 * its code is `authRequired`, the protocol's word that the agent needs a
 * login; otherwise `error` as it is.
 */
export function asSignIn(
  error: unknown,
  methods: readonly AuthMethod[] | null | undefined,
): unknown {
  const code =
    typeof error === 'object' && error !== null && 'code' in error
      ? error.code
      : undefined;

  if (code !== AUTH_REQUIRED) {
    return error;
  }

  return new SignInNeeded(
    {
      message: error instanceof Error ? error.message : String(error),
      ways: waysOf(methods),
    },
    { cause: error },
  );
}

/** The sign-in `error` or one of its causes says is needed, if any. */
export function signInOf(error: unknown): SignIn | undefined {
  for (
    let each: unknown = error;
    each instanceof Error;
    each = (each as Error).cause
  ) {
    if (each instanceof SignInNeeded) {
      return each.signIn;
    }
  }

  return undefined;
}

/** chord's own line, the way on: the sign-in is the agent's, outside chord. */
export function wayOn(agent: string): string {
  return `chord does not sign agents in. Sign in with ${agent}'s own CLI in a terminal, or set its API key where it offers one.`;
}

/** The line before the ways `agent` offers, by how many there are. */
export function offersLine(agent: string, count: number): string {
  return `${agent} offers ${count === 1 ? 'this sign-in' : 'these sign-ins'}:`;
}

/** A way in as plain text: its name, then its description in brackets. */
function wayWords(way: SignInWay): string {
  return way.name !== undefined && way.description !== undefined
    ? `${way.name} (${way.description})`
    : (way.name ?? way.description ?? '');
}

/** The ways in, as plain text in a line. */
function offered(ways: readonly SignInWay[]): string {
  return ways.map(wayWords).join(', ');
}

/**
 * What follows a start failure's own line where only plain text goes, as
 * on `-p`'s stderr: the ways `agent` offers, if any, and the way on.
 */
export function signInLines(agent: string, signIn: SignIn): string[] {
  return [
    ...(signIn.ways.length === 0
      ? []
      : [`${agent} offers: ${offered(signIn.ways)}`]),
    wayOn(agent),
  ];
}

/**
 * What an agent that opened `agent` is told after why it did not start:
 * the ways in, and the way on, which is the person's to take, not its own.
 */
export function signInNote(agent: string, signIn: SignIn): string {
  return `${
    signIn.ways.length === 0 ? '' : ` It offers: ${offered(signIn.ways)}.`
  } chord does not sign agents in: the person signs in with ${agent}'s own CLI in a terminal, or sets its API key where it offers one.`;
}
