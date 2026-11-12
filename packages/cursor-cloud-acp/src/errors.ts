/**
 * The adapter's own error kinds and how each answers over ACP: the code and
 * the words (CHD-622, "Errors"). cursor.ts turns the SDK's errors into
 * `CursorError`s by class and code; nothing here reads a message's words.
 */
import { RequestError } from '@agentclientprotocol/sdk';

/** What kind of failure an SDK error was, as cursor.ts tells them apart. */
export type Kind =
  | 'auth'
  | 'integration'
  | 'rate-limit'
  | 'busy'
  | 'not-found'
  | 'archived'
  | 'network'
  | 'other';

/** An SDK error in the adapter's kinds, keeping the SDK's message. */
export class CursorError extends Error {
  override name = 'CursorError';
  readonly kind: Kind;
  readonly code: string | undefined;
  readonly requestId: string | undefined;
  /** Where to connect the repository's provider, for `integration`. */
  readonly helpUrl: string | undefined;

  constructor(
    kind: Kind,
    message: string,
    options: {
      readonly code?: string | undefined;
      readonly requestId?: string | undefined;
      readonly helpUrl?: string | undefined;
      readonly cause?: unknown;
    } = {},
  ) {
    super(message, { cause: options.cause });

    this.kind = kind;
    this.code = options.code;
    this.requestId = options.requestId;
    this.helpUrl = options.helpUrl;
  }
}

/** ACP's codes the adapter answers with. */
export const AUTH_REQUIRED = -32000;
export const RESOURCE_NOT_FOUND = -32002;
export const INVALID_PARAMS = -32602;
export const INTERNAL_ERROR = -32603;

/** No key: neither `CURSOR_API_KEY` nor a usable keychain entry. */
export function signedOut(): RequestError {
  return new RequestError(AUTH_REQUIRED, 'Not signed in to Cursor.');
}

/**
 * A start refused before Cursor is asked (not a work tree, no remote,
 * detached, not pushed), `message` carrying its own way on. Never -32601,
 * which chord words as "it does not serve ACP sessions".
 */
export function refused(message: string): RequestError {
  return new RequestError(INVALID_PARAMS, message);
}

/**
 * How `error` answers a request: a `CursorError` by its kind, anything else
 * as an internal error with its message. `link` is the agent's page, which
 * a busy agent's answer names.
 */
export function toAcp(error: unknown, link?: string): RequestError {
  if (error instanceof RequestError) {
    return error;
  }

  if (!(error instanceof CursorError)) {
    return new RequestError(
      INTERNAL_ERROR,
      error instanceof Error ? error.message : String(error),
    );
  }

  switch (error.kind) {
    case 'auth':
      return new RequestError(AUTH_REQUIRED, error.message);
    case 'not-found':
      return new RequestError(RESOURCE_NOT_FOUND, error.message);
    case 'archived':
      return new RequestError(INVALID_PARAMS, error.message);
    case 'integration':
      return new RequestError(
        INTERNAL_ERROR,
        joined(error.message, error.helpUrl),
      );
    case 'busy':
      return new RequestError(INTERNAL_ERROR, joined(error.message, link));
    case 'rate-limit':
    case 'network':
      return new RequestError(INTERNAL_ERROR, error.message);
    case 'other':
      return new RequestError(
        INTERNAL_ERROR,
        error.message,
        error.code === undefined && error.requestId === undefined
          ? undefined
          : { code: error.code, requestId: error.requestId },
      );
  }
}

/** The words a turn ends with when the run's stream is lost mid-run. */
export function lostConnection(link: string): string {
  return `Lost the connection to Cursor; the agent keeps running there: ${link}. Reopen the session to see where it got to.`;
}

/** The SDK's message, then a link on a line of its own, when there is one. */
function joined(message: string, link: string | undefined): string {
  return link === undefined ? message : `${message}\n${link}`;
}
