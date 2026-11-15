/**
 * The account an agent's connection is signed in to (CHD-629): its answer
 * to `auth/status` as `--auth-status` plays it, the push `--auth-push` sends
 * after `initialize`, and another account mid-turn.
 */
import * as acp from '@agentclientprotocol/sdk/unstable';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
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
 * Two accounts, neither marked active, the first's parts together longer
 * than an 80-column row, for `--auth-status several`.
 */
export const SEVERAL: acp.AuthStatusResponse = {
  state: 'authenticated',
  accounts: [
    {
      label: 'Claude Max',
      email: 'a.very.long.address.for.the.capture@engineering.example.com',
      organization: 'Example Organisation of Long Names',
    },
    { label: 'Anthropic API key', description: 'ANTHROPIC_API_KEY' },
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
    : AUTH_STATUS === 'several'
      ? SEVERAL
      : SIGNED_IN;
}

/**
 * Answers `auth/status` as `--auth-status` says, with `--auth-race`'s push
 * of an API key's account just before the answer or just after it.
 */
export async function authStatus(
  client: Client,
): Promise<acp.AuthStatusResponse> {
  if (AUTH_RACE === 'push-first') {
    await client.notify('auth/status_update', API_KEY);
  } else if (AUTH_RACE === 'answer-first') {
    setTimeout(
      () => void client.notify('auth/status_update', API_KEY).catch(() => {}),
    );
  }

  if (AUTH_STATUS === 'error') {
    throw new acp.RequestError(-32603, 'The fake agent cannot tell.');
  }

  if (AUTH_STATUS === 'hang') {
    await new Promise<never>(() => {});
  }

  if (AUTH_STATUS === 'held') {
    await released();
  }

  return statusOf();
}

/**
 * Until `<cwd>/.fake-gate/release` exists in the agent's own directory, the
 * session's, or 10 s on the monotonic clock.
 */
async function released(): Promise<void> {
  const at = join(process.cwd(), '.fake-gate', 'release');
  const deadline = performance.now() + 10_000;

  while (!existsSync(at) && performance.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
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
