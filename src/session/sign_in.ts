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
 * it says the agent needs a login: its code is `authRequired`, or chord
 * itself cancelled a sign-in link the agent asked while nobody could answer
 * it (`linkUnheard`, droid's case); otherwise `error` as it is.
 */
export function asSignIn(
  error: unknown,
  methods: readonly AuthMethod[] | null | undefined,
  linkUnheard: boolean,
): unknown {
  const code =
    typeof error === 'object' && error !== null && 'code' in error
      ? error.code
      : undefined;

  if (code !== AUTH_REQUIRED && !linkUnheard) {
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
