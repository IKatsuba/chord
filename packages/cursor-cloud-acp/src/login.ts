/**
 * The package's own sign-in, the one the owner chose over ACP's (CHD-622):
 * `login`, `logout` and `status`, run by a person in a terminal. Results go
 * to stdout; the SDK writes its own lines, the login URL among them, to
 * stderr.
 */
import type { SdkCredentialStore } from '@cursor/sdk';
import { KeychainError, plain } from './errors.ts';
import type { Port } from './port.ts';

/** What the commands reach. */
export interface LoginContext {
  readonly port: Pick<Port, 'login' | 'logout' | 'status'>;
  readonly store: SdkCredentialStore;
  readonly env: Readonly<Record<string, string | undefined>>;
  /** One line of a result, to stdout. */
  readonly print: (line: string) => void;
  /** One line of a failure, to stderr. */
  readonly fail: (line: string) => void;
}

/** "Signed in to Cursor as …; the key expires …." with what the SDK gave. */
function signedIn(email?: string, expiresAtMs?: number): string {
  const who = email === undefined ? '' : ` as ${email}`;
  const until =
    expiresAtMs === undefined
      ? ''
      : `; the key expires ${new Date(expiresAtMs).toISOString().slice(0, 10)}`;

  return `Signed in to Cursor${who}${until}.`;
}

/** The keychain's error behind `error`, through its causes, if any. */
function keychain(error: unknown): KeychainError | undefined {
  for (let at = error; at instanceof Error; at = at.cause) {
    if (at instanceof KeychainError) {
      return at;
    }
  }

  return undefined;
}

/** `error`'s line: no keychain points to the environment, else its message. */
function failed(context: LoginContext, error: unknown): number {
  const missing = keychain(error);

  context.fail(
    missing === undefined
      ? plain(error)
      : `No keychain to keep the key in: ${missing.message.replace(/\.$/, '')}. Set CURSOR_API_KEY instead.`,
  );

  return 1;
}

/**
 * Signs in through Cursor's browser login into the keychain. The keychain
 * is read first, so a machine without one refuses before the browser opens,
 * and no key is ever written to a file (Q2).
 */
export async function login(context: LoginContext): Promise<number> {
  try {
    await context.store.load();

    const result = await context.port.login({ store: context.store });

    context.print(signedIn(result.email, result.apiKeyExpiresAtMs));

    return 0;
  } catch (error) {
    return failed(context, error);
  }
}

/** Removes the key from the keychain; the SDK says nothing of the server. */
export async function logout(context: LoginContext): Promise<number> {
  try {
    await context.port.logout({ store: context.store });
    context.print(
      "Signed out of Cursor: the key is removed from this machine's keychain.",
    );

    return 0;
  } catch (error) {
    return failed(context, error);
  }
}

/** Whether the keychain holds a login, and whether the environment wins. */
export async function status(context: LoginContext): Promise<number> {
  try {
    const answer = await context.port.status({ store: context.store });

    context.print(
      answer.status === 'logged-in'
        ? signedIn(answer.email, answer.apiKeyExpiresAtMs)
        : 'Not signed in to Cursor.',
    );

    if ((context.env.CURSOR_API_KEY ?? '') !== '') {
      context.print('CURSOR_API_KEY is set; it is used instead.');
    }

    return 0;
  } catch (error) {
    return failed(context, error);
  }
}
