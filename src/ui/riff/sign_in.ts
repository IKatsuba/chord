/** The words and choices of CHD-485 A–G, without terminal effects. */
import type { SecretProvider } from '../../platform/secrets.ts';
import {
  signInChoices,
  signInMinutes,
  type SignInChoice,
  type SignInStep,
} from '../../riff/sign_in.ts';
import type { Choice } from '../dialogs/permission.ts';
import { providerName, type RiffState } from './state.ts';

export interface SignInView {
  readonly title: string;
  readonly body?: string;
  readonly tone?: 'error' | 'warning';
  readonly address?: string;
  readonly code?: string;
  readonly foot?: string;
  readonly choices: readonly Choice[];
  readonly hint: string;
  readonly working?: string;
}

const labels = (step: SignInStep): Record<SignInChoice, string> => ({
  retry: 'Try again',
  browser:
    step.kind === 'port_taken'
      ? 'Try the browser again'
      : 'Sign in in the browser instead',
  code: 'Use a code instead',
  another_plan: 'Choose another plan',
  new_code: 'Get a new code',
  retry_store: 'Try the store again',
  open:
    step.kind === 'browser'
      ? 'Open it again'
      : 'Open the address in the browser',
  copy_address: 'Copy the address',
  copy_code: 'Copy the code',
});

const numbered = (
  choices: readonly { value: string; label: string }[],
): Choice[] =>
  choices.map((choice, at) => ({
    key: String(at + 1),
    ...choice,
    label: choice.label,
  }));

export function signInView(
  state: RiffState,
  store: string,
  now: number,
  narrow = false,
): SignInView | undefined {
  const elapsed = Math.max(0, Math.floor((now - state.since) / 1000));

  if (state.logout !== undefined) {
    const logout = state.logout;
    const name = providerName(logout.provider);

    return {
      title: `Sign out of ${name}?`,
      body:
        logout.message ??
        (logout.provider === 'codex'
          ? `chord forgets the sign-in in the ${store} and ends this session. OpenAI's tokens are not revoked: OpenAI offers chord no way to; they expire on their own.`
          : `chord forgets the sign-in in the ${store} and ends this session, then asks xAI to revoke the sign-in.`),
      ...(logout.message === undefined ? {} : { tone: 'error' as const }),
      choices: logout.pending
        ? []
        : numbered([
            {
              value: 'logout',
              label: logout.message === undefined ? 'Sign out' : 'Try again',
            },
            { value: 'keep', label: 'Keep the sign-in' },
          ]),
      hint: logout.pending ? 'Esc to close' : 'Enter to choose · Esc to cancel',
      ...(logout.pending
        ? { working: `Signing out of ${name}… (${elapsed}s)` }
        : {}),
    };
  }

  const step = state.flow?.step;

  if (
    step === undefined ||
    step.kind === 'success' ||
    step.kind === 'cancelled'
  ) {
    return undefined;
  }

  const provider = 'provider' in step ? step.provider : undefined;
  const name = provider === undefined ? 'riff' : providerName(provider);
  const choices = signInChoices(step);
  const view: SignInView = {
    title: `Sign in to ${name}`,
    choices: numbered(
      choices.map((value) => ({ value, label: labels(step)[value] })),
    ),
    hint: 'Enter to choose · Esc to cancel',
  };

  switch (step.kind) {
    case 'provider':
      return {
        ...view,
        choices: numbered(
          (['codex', 'grok'] as const).map((plan) => ({
            value: plan,
            label: providerLabel(
              plan,
              state.signedOut ? undefined : state.provider,
            ),
          })),
        ),
      };
    case 'way':
      return {
        ...view,
        choices: numbered([
          {
            value: 'browser',
            label: `In the browser · chord opens ${provider === 'codex' ? "OpenAI's page and listens on localhost:1455 for its answer" : "xAI's page and listens on a free port on 127.0.0.1 for its answer"}`,
          },
          {
            value: 'code',
            label: `With a code · enter a short code on ${provider === 'codex' ? "OpenAI's" : "xAI's"} page, in any browser, on any device`,
          },
        ]),
        hint: 'Enter to choose · Esc to go back',
      };
    case 'browser':
      return {
        ...view,
        title: `${view.title} in the browser`,
        body: `chord opened this address. Sign in there; chord goes on when ${provider === 'codex' ? 'OpenAI sends the browser back to localhost:1455.' : 'xAI sends the browser back to chord.'}`,
        address: step.address,
        hint: 'Enter to choose · Esc to give up',
        working: `Waiting for the browser… (${elapsed}s)`,
      };
    case 'code':
      return {
        ...view,
        title: `${view.title} with a code`,
        body: narrow
          ? 'Open the address, sign in, and enter the code.'
          : 'Open the address, sign in, and enter the code. chord goes on once you have.',
        address: step.address,
        code: step.code,
        foot: `The code expires ${step.expiresAt - now < 60_000 ? 'in less than a minute' : `in ${signInMinutes(step.expiresAt, now)} minutes`}.${provider === 'codex' ? (narrow ? " If OpenAI's page says device code sign-in is off, turn it on in ChatGPT's security settings." : " If OpenAI's page says device code sign-in is off, turn it on in ChatGPT's security settings, or ask your workspace admin.") : ''}`,
        hint: 'Enter to choose · Esc to give up',
        working: `Waiting for the code… (${elapsed}s)`,
      };
    case 'port_taken':
      return {
        ...view,
        title: `${view.title} in the browser`,
        body: 'localhost:1455 is taken by another program. OpenAI sends the browser back only there, so chord cannot sign in in the browser while it is. Sign in with a code, or close that program and try again.',
        tone: 'warning',
        hint: 'Enter to choose · Esc to go back',
      };
    case 'failure':
      return {
        ...view,
        title: `${view.title} ${step.way === 'code' ? 'with a code' : 'in the browser'}`,
        body: `The sign-in failed: ${step.message}`,
        tone: 'error',
        ...(step.provider === 'codex' &&
        step.code === 'LIBFX_CHATGPT_DEVICE_CODE_UNAVAILABLE'
          ? {
              foot: "ChatGPT accounts and workspaces must turn device code sign-in on in ChatGPT's security settings first.",
            }
          : {}),
      };
    case 'expired':
      return {
        ...view,
        title: `${view.title} ${step.way === 'code' ? 'with a code' : 'in the browser'}`,
        body: step.message,
        tone: 'error',
        hint: 'Enter to choose · Esc to go back',
      };
    case 'no_store':
    case 'store_slow':
      return { ...view, body: step.message, tone: 'warning' };
    case 'reading_store':
      return {
        ...view,
        ...('message' in step
          ? { body: step.message, tone: 'warning' as const }
          : {}),
        hint: 'Esc to cancel',
        working: `Reading the sign-in from the ${step.store}… (${elapsed}s)`,
      };
    case 'starting':
    case 'finishing':
    case 'saving':
      return {
        ...view,
        hint: 'Esc to cancel',
        working:
          step.kind === 'starting'
            ? 'Starting the sign-in…'
            : 'Finishing the sign-in…',
      };
  }
}

function providerLabel(
  provider: SecretProvider,
  active: SecretProvider | undefined,
): string {
  const name = providerName(provider);

  return `${name}\x1b[2m · a ${name} plan\x1b[22m${active === provider ? ' ✔' : ''}`;
}
