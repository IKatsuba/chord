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
 * and --qa set it, never settings. Production uses the stored plan sign-in.
 */
export const FAKE_PROVIDER_ENV = 'CHORD_RIFF_FAKE_PROVIDER';

/**
 * The plan whose model list the fake provider presents, `codex` or `grok`,
 * so screenshots show a plan's names; read only beside the fake provider,
 * never settings.
 */
export const FAKE_MODELS_ENV = 'CHORD_RIFF_FAKE_MODELS';

export function fakeProvider(
  env: Readonly<Record<string, string | undefined>>,
): FakeProvider | undefined {
  const baseUrl = env[FAKE_PROVIDER_ENV];

  if (baseUrl === undefined || baseUrl === '') {
    return undefined;
  }

  const models = env[FAKE_MODELS_ENV];

  if (models === undefined || models === '') {
    return { baseUrl };
  }

  if (models !== 'codex' && models !== 'grok') {
    throw new Error(`${FAKE_MODELS_ENV} takes codex or grok, not ${models}`);
  }

  return { baseUrl, models };
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
