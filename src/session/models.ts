/**
 * The agent's models: the ones it offers, in its own order, and the one it
 * says it uses. `/model` lists them.
 */
import type { SessionConfigOption } from '@agentclientprotocol/sdk';

export interface AgentModel {
  readonly id: string;
  /** The agent's name for it, such as `Opus 4.6`; its id when it gave none. */
  readonly name: string;
}

export interface AgentModels {
  readonly available: readonly AgentModel[];
  /** The model the agent reports; undefined when it named none. */
  readonly current?: string;
}

/**
 * The agent's models from its `model` config option, or else from the older
 * `models` field `session/new` answers with, which ACP v1 has not made stable
 * and Claude's adapter still sends. Undefined when the agent offers none.
 */
export function modelsFrom(
  configOptions: readonly SessionConfigOption[],
  legacy: unknown,
): AgentModels | undefined {
  const option = modelOption(configOptions);

  if (option !== undefined) {
    const available = option.options
      .flatMap((entry) => ('group' in entry ? entry.options : [entry]))
      .map(({ value, name }) => ({ id: value, name: name || value }));

    return offered(available, option.currentValue);
  }

  if (!isModelState(legacy)) {
    return undefined;
  }

  return offered(
    legacy.availableModels.map(({ modelId, name }) => ({
      id: modelId,
      name: name || modelId,
    })),
    legacy.currentModelId,
  );
}

function offered(
  available: readonly AgentModel[],
  current: string | undefined,
): AgentModels | undefined {
  if (available.length === 0 && !current) {
    return undefined;
  }

  return current ? { available, current } : { available };
}

/**
 * The id of the config option the agent offers its models in; undefined when
 * it offers them the older way, or not at all.
 */
export function modelConfigId(
  configOptions: readonly SessionConfigOption[],
): string | undefined {
  return modelOption(configOptions)?.id;
}

function modelOption(
  configOptions: readonly SessionConfigOption[],
): Extract<SessionConfigOption, { type: 'select' }> | undefined {
  const option = configOptions.find(
    (candidate) =>
      candidate.type === 'select' &&
      (candidate.category === 'model' || candidate.id === 'model'),
  );

  return option?.type === 'select' ? option : undefined;
}

/** ACP's unstable `SessionModelState`, as an agent may send it. */
export interface ModelState {
  readonly currentModelId: string;
  readonly availableModels: readonly {
    readonly modelId: string;
    readonly name: string;
  }[];
}

/** Whether `value` has the shape of ACP's unstable `SessionModelState`. */
export function isModelState(value: unknown): value is ModelState {
  if (typeof value !== 'object' || value === null) {
    return false;
  }

  const { currentModelId, availableModels } = value as Record<string, unknown>;

  return (
    typeof currentModelId === 'string' &&
    Array.isArray(availableModels) &&
    availableModels.every(
      (model) =>
        typeof model === 'object' &&
        model !== null &&
        typeof (model as Record<string, unknown>).modelId === 'string',
    )
  );
}

/**
 * The name of the model the agent uses, as the status line shows it; its id
 * when the agent listed it under no name, and undefined when it named none.
 */
export function modelName(models: AgentModels | undefined): string | undefined {
  const id = models?.current;

  if (id === undefined) {
    return undefined;
  }

  return models?.available.find((model) => model.id === id)?.name ?? id;
}

/** Whether two readings name the same models in the same order. */
export function sameModels(
  a: AgentModels | undefined,
  b: AgentModels | undefined,
): boolean {
  if (a === undefined || b === undefined) {
    return a === b;
  }

  return (
    a.current === b.current &&
    a.available.length === b.available.length &&
    a.available.every(
      (model, index) =>
        model.id === b.available[index]?.id &&
        model.name === b.available[index]?.name,
    )
  );
}
