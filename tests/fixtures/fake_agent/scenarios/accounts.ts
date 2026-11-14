/**
 * The account an agent's connection is signed in to (CHD-629): its answer
 * to `auth/status` as `--auth-status` plays it, the push `--auth-push` sends
 * after `initialize`, and another account mid-turn.
 */
import * as acp from '@agentclientprotocol/sdk/unstable';
import process from 'node:process';
import { AUTH_RACE, AUTH_STATUS } from '../options.ts';
import type { Client, Play } from '../turn.ts';

/** A subscription, as Claude's adapter says one. */
export const SIGNED_IN: acp.AuthStatusResponse = {
  state: 'authenticated',
  accounts: [
    {
      label: 'Claude Max',
      email: 'name@example.com',
      organization: 'Example Org',
      active: true,
    },
  ],
};

/** An API key, as Claude's adapter says one. */
export const API_KEY: acp.AuthStatusResponse = {
  state: 'authenticated',
  accounts: [
    {
      label: 'Anthropic API key',
      description: 'ANTHROPIC_API_KEY',
      active: true,
    },
  ],
};

/**
 * What `--auth-status` says: `authenticated` a subscription,
 * `unauthenticated` and `unknown` their state alone; `error` and `hang`
 * answer nothing, and a push says the subscription.
 */
function statusOf(): acp.AuthStatusResponse {
  return AUTH_STATUS === 'unauthenticated' || AUTH_STATUS === 'unknown'
    ? { state: AUTH_STATUS }
    : SIGNED_IN;
}

/**
 * Answers `auth/status` as `--auth-status` says. Under `--auth-race` the
 * answer and an API key's push go in one write, in the order named, so
 * chord reads them in one chunk: the answer is written here, under the
 * request's id, and the SDK's own is never sent.
 */
export async function authStatus(
  requestId: acp.RequestId,
): Promise<acp.AuthStatusResponse> {
  if (AUTH_RACE !== undefined) {
    const answer = { jsonrpc: '2.0', id: requestId, result: statusOf() };
    const push = {
      jsonrpc: '2.0',
      method: 'auth/status_update',
      params: API_KEY,
    };
    const both = AUTH_RACE === 'push-first' ? [push, answer] : [answer, push];

    process.stdout.write(
      both.map((each) => `${JSON.stringify(each)}\n`).join(''),
    );
    await new Promise<never>(() => {});
  }

  if (AUTH_STATUS === 'error') {
    throw new acp.RequestError(-32603, 'The fake agent cannot tell.');
  }

  if (AUTH_STATUS === 'hang') {
    await new Promise<never>(() => {});
  }

  return statusOf();
}

/** Pushes the account, as Claude's adapter does once its probe lands. */
export function pushStatus(client: Client): void {
  setTimeout(
    () => void client.notify('auth/status_update', statusOf()).catch(() => {}),
  );
}

export const ACCOUNTS = {
  // Another account mid-turn, as a prompt's probe finds one.
  authchanged: async (turn) => {
    await turn.say('Checking who is signed in. ');
    await turn.client.notify('auth/status_update', API_KEY);
    await turn.say('Done.');

    return 'end_turn';
  },
} satisfies Record<string, Play>;
