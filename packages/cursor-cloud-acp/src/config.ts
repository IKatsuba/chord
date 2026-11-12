/**
 * A session's config options (CHD-622, "Modes and models"): the mode, one
 * model option per model `Cursor.models.list()` gives, and one option per
 * parameter of the chosen model, each offering only the values some variant
 * holds together with the other parameters' chosen values. Pure.
 */
import type { SessionConfigOption } from '@agentclientprotocol/sdk/unstable';
import type {
  AgentModeOption,
  ModelListItem,
  ModelSelection,
} from '@cursor/sdk';

export const MODE = 'mode';
export const MODEL = 'model';
/** The model option's value for leaving `model` out: Cursor's default. */
export const CURSORS_DEFAULT = 'cursor-default';
/** A parameter's option id, apart from the mode's and the model's. */
const PARAMETER = 'parameter:';

/** The only kind of option the adapter offers: a choice among values. */
export type SelectOption = Extract<SessionConfigOption, { type: 'select' }>;

/** What a session has chosen. */
export interface Choice {
  /** ACP's `default` is the SDK's `agent`, so chord's words for modes apply. */
  readonly mode: 'default' | 'plan';
  /** Unset: Cursor's default. */
  readonly model?: {
    readonly id: string;
    readonly params: Readonly<Record<string, string>>;
  };
}

/** The SDK's mode for `choice`. */
export function sdkMode(choice: Choice): AgentModeOption {
  return choice.mode === 'plan' ? 'plan' : 'agent';
}

/** The SDK's selection for `choice`, undefined for Cursor's default. */
export function selection(choice: Choice): ModelSelection | undefined {
  if (choice.model === undefined) {
    return undefined;
  }

  const params = Object.entries(choice.model.params).map(([id, value]) => ({
    id,
    value,
  }));

  return params.length === 0
    ? { id: choice.model.id }
    : { id: choice.model.id, params };
}

/** A selection the SDK gave back (`agent.model`, `RunResult.model`) as a choice's model. */
export function chosen(model: ModelSelection): NonNullable<Choice['model']> {
  return {
    id: model.id,
    params: Object.fromEntries(
      (model.params ?? []).map(({ id, value }) => [id, value]),
    ),
  };
}

/** A newly chosen model's parameters: its `isDefault` variant's, else its first's. */
export function startingParams(
  model: ModelListItem,
): Readonly<Record<string, string>> {
  const variant =
    model.variants?.find((each) => each.isDefault === true) ??
    model.variants?.[0];

  return Object.fromEntries(
    (variant?.params ?? []).map(({ id, value }) => [id, value]),
  );
}

/** Values of `parameter` some variant of `model` holds with the others' chosen ones. */
function offered(
  model: ModelListItem,
  parameter: string,
  params: Readonly<Record<string, string>>,
): Set<string> {
  const values = new Set<string>();

  for (const variant of model.variants ?? []) {
    const has = new Map(variant.params.map(({ id, value }) => [id, value]));
    const together = Object.entries(params).every(
      ([id, value]) => id === parameter || has.get(id) === value,
    );
    const value = has.get(parameter);

    if (together && value !== undefined) {
      values.add(value);
    }
  }

  return values;
}

/**
 * The options for `choice` over `models`; `defaultOffered` while the
 * agent's model is unset, as the SDK has no way back to its default.
 */
export function configOptions(
  choice: Choice,
  models: readonly ModelListItem[],
  defaultOffered: boolean,
): SelectOption[] {
  const current = choice.model;
  const listed = models.find((each) => each.id === current?.id);
  const modelValues = [
    ...(defaultOffered
      ? [{ value: CURSORS_DEFAULT, name: "Cursor's default" }]
      : []),
    ...models.map((each) => ({ value: each.id, name: each.displayName })),
    // A model Cursor ran that the list does not hold, under its own id.
    ...(current !== undefined && listed === undefined
      ? [{ value: current.id, name: current.id }]
      : []),
  ];
  const options: SelectOption[] = [
    {
      id: MODE,
      name: 'Mode',
      category: 'mode',
      type: 'select',
      currentValue: choice.mode,
      options: [
        { value: 'default', name: 'Agent' },
        { value: 'plan', name: 'Plan' },
      ],
    },
    {
      id: MODEL,
      name: 'Model',
      category: 'model',
      type: 'select',
      currentValue: current?.id ?? CURSORS_DEFAULT,
      options: modelValues,
    },
  ];

  if (current === undefined || listed === undefined) {
    return options;
  }

  for (const parameter of listed.parameters ?? []) {
    const value = current.params[parameter.id];

    if (value === undefined) {
      continue;
    }

    const allowed = offered(listed, parameter.id, current.params);

    // No category: the ids Cursor gives are not recorded yet, and a guessed
    // one would misname the parameter.
    options.push({
      id: `${PARAMETER}${parameter.id}`,
      name: parameter.displayName ?? parameter.id,
      type: 'select',
      currentValue: value,
      options: parameter.values
        .filter((each) => allowed.has(each.value))
        .map((each) => ({
          value: each.value,
          name: each.displayName ?? each.value,
        })),
    });
  }

  return options;
}

/**
 * `choice` with option `id` set to `value`, or undefined when `value` is
 * not one the option offers.
 */
export function choose(
  choice: Choice,
  models: readonly ModelListItem[],
  defaultOffered: boolean,
  id: string,
  value: string,
): Choice | undefined {
  const option = configOptions(choice, models, defaultOffered).find(
    (each) => each.id === id,
  );

  if (
    option === undefined ||
    !(option.options as readonly { value: string }[]).some(
      (each) => each.value === value,
    )
  ) {
    return undefined;
  }

  if (id === MODE) {
    return { ...choice, mode: value as Choice['mode'] };
  }

  if (id === MODEL) {
    if (value === CURSORS_DEFAULT) {
      return { mode: choice.mode };
    }

    if (value === choice.model?.id) {
      return choice;
    }

    const model = models.find((each) => each.id === value);

    return {
      ...choice,
      model: {
        id: value,
        params: model === undefined ? {} : startingParams(model),
      },
    };
  }

  // A parameter: any value it offers holds with the others' chosen ones.
  return {
    ...choice,
    model: {
      id: choice.model!.id,
      params: { ...choice.model!.params, [id.slice(PARAMETER.length)]: value },
    },
  };
}
