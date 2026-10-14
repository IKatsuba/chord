/**
 * The agent's session modes: the ones it offers, in its own order, and the one
 * it says it is in. shift+tab walks that order.
 */
import type {
  SessionConfigOption,
  SessionModeState,
} from '@agentclientprotocol/sdk';

export interface AgentMode {
  readonly id: string;
  /** The agent's name for it, such as `Accept edits`. */
  readonly name: string;
}

export interface AgentModes {
  readonly available: readonly AgentMode[];
  /** The mode the agent reports; undefined when it named none of its own. */
  readonly current?: string;
}

/**
 * The agent's modes: those in its `mode` config option, or else the older
 * `modes` that `session/new` answers with. Undefined when it offers none.
 */
export function modesFrom(
  options: unknown,
  legacy?: SessionModeState | undefined,
): AgentModes | undefined {
  const option = modeOption(options);

  if (option === undefined) {
    if (legacy === undefined || legacy.availableModes.length === 0) {
      return undefined;
    }

    return {
      available: legacy.availableModes.map(({ id, name }) => ({ id, name })),
      current: legacy.currentModeId,
    };
  }

  // Grouped options are walked group by group, in the order the agent gave.
  const available = option.options
    .flatMap((entry) => ('group' in entry ? entry.options : [entry]))
    .map(({ value, name }) => ({ id: value, name }));

  if (available.length === 0) {
    return undefined;
  }

  return { available, current: option.currentValue };
}

/**
 * The id of the config option the agent offers its modes in; undefined when
 * it offers them the older way, or not at all.
 */
export function modeConfigId(options: unknown): string | undefined {
  return modeOption(options)?.id;
}

function modeOption(
  options: unknown,
): Extract<SessionConfigOption, { type: 'select' }> | undefined {
  if (!Array.isArray(options)) {
    return undefined;
  }

  const option = (options as SessionConfigOption[]).find(
    (candidate) =>
      candidate.type === 'select' &&
      (candidate.category === 'mode' || candidate.id === 'mode'),
  );

  return option?.type === 'select' ? option : undefined;
}

/**
 * The mode after `current` in the agent's order, wrapping round to the first;
 * the first when `current` is none of them. Undefined when there is nowhere to
 * go.
 */
export function nextMode(
  available: readonly AgentMode[],
  current: string | undefined,
): string | undefined {
  if (available.length < 2) {
    return undefined;
  }

  const at = available.findIndex((mode) => mode.id === current);

  return available[(at + 1) % available.length]?.id;
}

/** Whether two readings name the same modes in the same order. */
export function sameModes(
  a: AgentModes | undefined,
  b: AgentModes | undefined,
): boolean {
  if (a === undefined || b === undefined) {
    return a === b;
  }

  return (
    a.current === b.current &&
    a.available.length === b.available.length &&
    a.available.every(
      (mode, index) =>
        mode.id === b.available[index]?.id &&
        mode.name === b.available[index]?.name,
    )
  );
}
