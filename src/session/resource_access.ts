/** Explicit window injection: test and capture windows never fall back to official readers. */
import type { ActiveRun, BudgetSnapshot, TeamSelection } from './budgets.ts';

export interface ResourceInterest {
  readonly agent: string;
  readonly cwd: string;
  readonly command?: string | readonly string[];
}

export interface ResourceAccess {
  readonly processRef: string;
  start(): Promise<void>;
  retain(
    interest: ResourceInterest,
    signal: AbortSignal,
    valid?: () => boolean,
  ): () => void;
  read(preferences?: TeamSelection): BudgetSnapshot;
  active(runs: readonly ActiveRun[]): void;
  close(): Promise<readonly string[]>;
}
