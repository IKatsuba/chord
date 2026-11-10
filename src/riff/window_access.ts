/** Production selects the system store; fake launches select offline effects. */
import { riffAccess, QA_PROVIDER_ENV } from './qa.ts';
import type { Secrets } from '../platform/secrets.ts';
import { fakeProvider } from './start.ts';
import {
  fixtureSignedIn,
  fixtureSignIn,
  fixtureSignOut,
  QA_SIGN_IN_ENV,
} from './sign_in_fixture.ts';

export function riffWindowAccess(
  env: Record<string, string | undefined>,
  system?: () => Secrets,
) {
  const access = riffAccess(env, system);

  if (fakeProvider(env) === undefined) {
    return { store: access.secrets, fetch: access.fetch };
  }

  return {
    store: access.secrets,
    fetch: fixtureSignOut(access.secrets),
    fixture: true,
    provider:
      env[QA_PROVIDER_ENV] === 'grok' ? ('grok' as const) : ('codex' as const),
    run: fixtureSignIn(env[QA_SIGN_IN_ENV] ?? 'waiting'),
    changed: (provider: 'codex' | 'grok' | undefined) =>
      fixtureSignedIn(env, provider),
  };
}
