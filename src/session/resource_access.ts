/** Explicit window injection: test and capture windows never fall back to official readers. */
import type { Budgets } from './budgets.ts';

/** Where a window's agents start, which decides how their limits are read. */
export interface LimitsPlace {
  readonly cwd: string;
  /** The custom ACP command a runtime starts with, if any. */
  commandOf(agent: string): string | readonly string[] | undefined;
}

/** Reads each named provider, or claude and codex when none are named. */
export type ReadLimits = (
  agents: readonly string[] | undefined,
  place: LimitsPlace,
  signal: AbortSignal,
) => Promise<Budgets>;
