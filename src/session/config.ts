/**
 * The agent's session config options other than its mode and its model, such
 * as Claude's effort: each one's values and the one it is set to. `/config`
 * lists them; the mode and the model have keys and pickers of their own.
 */
import type { SessionConfigOption } from '@agentclientprotocol/sdk';

export interface AgentOptionValue {
  readonly value: string;
  /** The agent's name for it, such as `High`. */
  readonly name: string;
}

export interface AgentOption {
  readonly id: string;
  /** The agent's name for it, such as `Effort`. */
  readonly name: string;
  readonly values: readonly AgentOptionValue[];
  /** The value the agent reports. */
  readonly current: string;
}

/**
 * The select options among the agent's config options, as the agent last
 * sent them, in its order, leaving out the mode and the model. A select is
 * the only kind ACP has a list of values for.
 */
export function optionsFromConfigOptions(options: unknown): AgentOption[] {
  if (!Array.isArray(options)) {
    return [];
  }

  return (options as SessionConfigOption[]).flatMap((option) => {
    if (
      option.type !== 'select' ||
      isModeOrModel(option.category) ||
      isModeOrModel(option.id)
    ) {
      return [];
    }

    // Grouped values are listed group by group, in the order the agent gave.
    const values = option.options
      .flatMap((entry) => ('group' in entry ? entry.options : [entry]))
      .map(({ value, name }) => ({ value, name }));

    return values.length === 0
      ? []
      : [
          {
            id: option.id,
            name: option.name,
            values,
            current: option.currentValue,
          },
        ];
  });
}

function isModeOrModel(name: string | null | undefined): boolean {
  return name === 'mode' || name === 'model';
}

/** The agent's name for `value` of `option`; the value itself when it has none. */
export function valueName(option: AgentOption, value: string): string {
  return option.values.find((entry) => entry.value === value)?.name ?? value;
}

/** Whether two readings list the same options, set the same way. */
export function sameOptions(
  a: readonly AgentOption[],
  b: readonly AgentOption[],
): boolean {
  return (
    a.length === b.length &&
    a.every((option, index) => {
      const other = b[index];

      return (
        other !== undefined &&
        option.id === other.id &&
        option.name === other.name &&
        option.current === other.current &&
        option.values.length === other.values.length &&
        option.values.every(
          (entry, at) =>
            entry.value === other.values[at]?.value &&
            entry.name === other.values[at]?.name,
        )
      );
    })
  );
}
