/**
 * How chord starts riff: itself, as it starts its resource worker, with a
 * hidden flag (CHD-485, "The parts"). One riff session per process, so a
 * fault in libfx's native core costs that session and not the window.
 */
import { fileURLToPath } from 'node:url';
import type { AgentStart } from '../agents.ts';
import { execPath } from '../platform/process.ts';
import type { FakeProvider } from './adapter.ts';

declare const CHORD_RESOURCE_COMPILED: boolean;

/** The flag `main.tsx` reads before Cliffy, so no help lists it. */
export const RIFF_AGENT_FLAG = '--riff-agent';

/** riff's name, as `agentStart` and libfx's agent take it. */
export const RIFF = 'riff';

/**
 * The fake Chat Completions server's base URL. Only tests, selftest, --fake
 * and --qa set it, never settings: it is the one provider riff has until it
 * can sign in (CHD-485 part 4).
 */
export const FAKE_PROVIDER_ENV = 'CHORD_RIFF_FAKE_PROVIDER';

export function fakeProvider(
  env: Readonly<Record<string, string | undefined>>,
): FakeProvider | undefined {
  const baseUrl = env[FAKE_PROVIDER_ENV];

  return baseUrl === undefined || baseUrl === '' ? undefined : { baseUrl };
}

/**
 * Whether chord lists and offers riff: only on its fake provider, as a
 * listed riff could not yet sign in anywhere else (CHD-607).
 */
export function riffOffered(
  env: Readonly<Record<string, string | undefined>>,
): boolean {
  return fakeProvider(env) !== undefined;
}

/** The binary alone when compiled; from source, Bun with `main.tsx`. */
export function riffAgentStart(): AgentStart {
  const compiled =
    typeof CHORD_RESOURCE_COMPILED !== 'undefined' && CHORD_RESOURCE_COMPILED;

  return {
    command: [
      execPath(),
      ...(compiled
        ? []
        : [fileURLToPath(new URL('../main.tsx', import.meta.url))]),
      RIFF_AGENT_FLAG,
    ],
    env: {},
  };
}
