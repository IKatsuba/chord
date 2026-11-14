/**
 * The values a new session is asked to open on, sent as `session/new`'s
 * initial `configOptions` where the agent takes them (CHD-629): a value the
 * agent takes at setup then costs no request after the session is up.
 */
import type {
  InitialSessionConfigOption,
  InitializeResponse,
} from '@agentclientprotocol/sdk/unstable';

/** The starting values chord was asked for, by the agent's id for each. */
export interface InitialValues {
  readonly model?: string | undefined;
  readonly effort?: string | undefined;
  readonly mode?: string | undefined;
}

/**
 * The config ids an adapter takes as initial `configOptions` (CHD-629), by
 * the name its `initialize` answer gives, read from its source and rechecked
 * at a pin bump beside `agents.ts`'s `FAST_OPTIONS`: asking `session/options`
 * first makes Claude run a throwaway Claude Code and the person's
 * SessionStart hooks (CHD-624). A renamed id costs only a request after the
 * session is up (the owner's Q8 a).
 */
const INITIAL_CONFIG_IDS: ReadonlyMap<
  string,
  Readonly<Record<keyof InitialValues, string>>
> = new Map([
  [
    '@agentclientprotocol/claude-agent-acp',
    { model: 'model', effort: 'effort', mode: 'mode' },
  ],
]);

/** The order entries go in: a model decides which efforts and modes follow. */
const ORDER = ['model', 'effort', 'mode'] as const;

/**
 * `session/new`'s initial entries for `values`: one per value named, model,
 * effort, mode, only where the agent advertises `sessionCapabilities.options`
 * and the table knows it; none otherwise. chord adds no value of its own.
 */
export function initialEntries(
  init: InitializeResponse,
  values: InitialValues,
): InitialSessionConfigOption[] {
  const ids =
    init.agentInfo?.name === undefined
      ? undefined
      : INITIAL_CONFIG_IDS.get(init.agentInfo.name);

  if (
    ids === undefined ||
    !init.agentCapabilities?.sessionCapabilities?.options
  ) {
    return [];
  }

  return ORDER.flatMap((key) => {
    const value = values[key];

    return value === undefined ? [] : [{ configId: ids[key], value }];
  });
}

/** A starting value as chord holds it, by the agent's id. */
interface Named {
  readonly id: string;
}

/** The ids of the starting values named, as `Starting` and `-p` hold them. */
export function initialValuesOf(starting: {
  readonly model?: Named | undefined;
  readonly effort?: Named | undefined;
  readonly mode?: Named | undefined;
}): InitialValues {
  return {
    ...(starting.model === undefined ? {} : { model: starting.model.id }),
    ...(starting.effort === undefined ? {} : { effort: starting.effort.id }),
    ...(starting.mode === undefined ? {} : { mode: starting.mode.id }),
  };
}
