/**
 * The agent's efforts: the values of its config option of ACP's
 * `thought_level` category, in its own order, and the one it is on. Both
 * Claude's adapter (`effort`) and Codex's (`reasoning_effort`) mark theirs so;
 * the option is found by its category alone, never by an id or a name.
 */
import type { SessionConfigOption } from '@agentclientprotocol/sdk';

export interface AgentEffort {
  readonly id: string;
  /** The agent's name for it, such as `High`; its id when it gave none. */
  readonly name: string;
}

export interface AgentEfforts {
  /** The id of the config option they are set through. */
  readonly option: string;
  readonly available: readonly AgentEffort[];
  /** The effort the agent reports. */
  readonly current: string;
}

/**
 * The agent's efforts, for the model it is on: both adapters offer each
 * model's own and send the option again when the model changes. Undefined
 * when it offers none.
 */
export function effortsFrom(options: unknown): AgentEfforts | undefined {
  if (!Array.isArray(options)) {
    return undefined;
  }

  const option = (options as SessionConfigOption[]).find(
    (candidate) =>
      candidate.type === 'select' && candidate.category === 'thought_level',
  );

  if (option?.type !== 'select') {
    return undefined;
  }

  // Grouped values are listed group by group, in the order the agent gave.
  const available = option.options
    .flatMap((entry) => ('group' in entry ? entry.options : [entry]))
    .map(({ value, name }) => ({ id: value, name: name || value }));

  return available.length === 0
    ? undefined
    : { option: option.id, available, current: option.currentValue };
}
