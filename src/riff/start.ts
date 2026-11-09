/**
 * How chord starts riff: itself, as it starts its resource worker, with a
 * hidden flag (CHD-485, "The parts"). One riff session per process, so a
 * fault in libfx's native core costs that session and not the window.
 */
import { fileURLToPath } from 'node:url';
import type { AgentStart } from '../agents.ts';
import { execPath } from '../platform/process.ts';

declare const CHORD_RESOURCE_COMPILED: boolean;

/** The flag `main.tsx` reads before Cliffy, so no help lists it. */
export const RIFF_AGENT_FLAG = '--riff-agent';

/** riff's name, as `agentStart` and libfx's agent take it. */
export const RIFF = 'riff';

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
