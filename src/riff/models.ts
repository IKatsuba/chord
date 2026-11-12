/**
 * riff's models, efforts and modes, as its config options offer them
 * (CHD-485, "Models and effort"). libfx has no model list for plans, so riff
 * carries one per provider, each model with its context window and efforts,
 * the plan's default first, as other agents carry theirs in their own config
 * options.
 */
import type { SessionConfigOption } from '@agentclientprotocol/sdk/unstable';

/** Where riff's turns run: a plan, or the fake provider of tests. */
export type RiffPlan = 'codex' | 'grok' | 'fake';

export interface RiffModel {
  readonly id: string;
  /** Its context window in tokens: `usage_update`'s `size`. */
  readonly window: number;
  /** The efforts it takes besides riff's own `default`, lowest first. */
  readonly levels: readonly RiffLevel[];
}

const UP_TO_ULTRA = ['low', 'medium', 'high', 'xhigh', 'max', 'ultra'] as const;
const UP_TO_MAX = ['low', 'medium', 'high', 'xhigh', 'max'] as const;
const UP_TO_XHIGH = ['low', 'medium', 'high', 'xhigh'] as const;

/**
 * Checked against the plans' own `/models` on 2026-11-12 (CHD-611): the
 * models a plan lists, in its order, with their windows and levels. The
 * comment on each is the plan's default effort, which riff's `default`
 * leaves to the plan.
 */
const PLAN_MODELS: Readonly<Record<RiffPlan, readonly RiffModel[]>> = {
  codex: [
    { id: 'gpt-6.1-sol', window: 500_000, levels: UP_TO_ULTRA }, // low
    { id: 'gpt-6-astra', window: 272_000, levels: UP_TO_ULTRA }, // medium
    { id: 'gpt-6.1-terra', window: 500_000, levels: UP_TO_ULTRA }, // low
    { id: 'gpt-6-sol', window: 272_000, levels: UP_TO_ULTRA }, // medium
    { id: 'gpt-6-luna', window: 272_000, levels: UP_TO_MAX }, // medium
    { id: 'gpt-5.6-sol', window: 272_000, levels: UP_TO_ULTRA }, // low
    { id: 'gpt-5.6-terra', window: 272_000, levels: UP_TO_ULTRA }, // medium
    { id: 'gpt-5.6-luna', window: 272_000, levels: UP_TO_MAX }, // medium
  ],
  // The plan lists windows of 256,000 and 500,000; riff's turns run on the
  // first.
  grok: [
    { id: 'grok-4.7', window: 256_000, levels: UP_TO_XHIGH }, // high
    { id: 'grok-4.7-build-fast', window: 256_000, levels: UP_TO_XHIGH }, // high
    { id: 'grok-4.6', window: 256_000, levels: UP_TO_XHIGH }, // high
    { id: 'grok-4.5', window: 256_000, levels: ['low', 'medium', 'high'] }, // high
  ],
  // The fake Chat Completions server's one model, for tests, selftest,
  // --fake and --qa alone.
  fake: [{ id: 'fake', window: 128_000, levels: UP_TO_XHIGH }],
};

/** Every effort a model can take, and riff's `default`: what a sidecar holds. */
export const EFFORTS = ['default', ...UP_TO_ULTRA] as const;

export type RiffEffort = (typeof EFFORTS)[number];

type RiffLevel = Exclude<RiffEffort, 'default'>;

/**
 * `ask` asks before every call; `auto` reviews outside reads, sensitive or
 * outside mutations and ungranted shell calls. Grants hold in either mode.
 */
export const MODES = ['ask', 'auto'] as const;

export type RiffMode = (typeof MODES)[number];

/** What a session runs its next turn on. */
export interface RiffConfig {
  readonly model: string;
  readonly effort: RiffEffort;
  readonly mode: RiffMode;
}

export function planModels(plan: RiffPlan): readonly RiffModel[] {
  return PLAN_MODELS[plan];
}

/** A new session's: the plan's default model, `default` effort, `auto`. */
export function defaultConfig(plan: RiffPlan): RiffConfig {
  const [first] = PLAN_MODELS[plan];

  return { model: first?.id ?? '', effort: 'default', mode: 'auto' };
}

/** The model, or the plan default for a model not listed. */
function modelOf(plan: RiffPlan, model: string): RiffModel | undefined {
  const models = PLAN_MODELS[plan];

  return models.find(({ id }) => id === model) ?? models[0];
}

/** The model's window, or the plan default's for a model not listed. */
export function windowOf(plan: RiffPlan, model: string): number {
  return modelOf(plan, model)?.window ?? 0;
}

/** `default` first, then the levels the model takes. */
function effortsOf(plan: RiffPlan, model: string): readonly RiffEffort[] {
  return ['default', ...(modelOf(plan, model)?.levels ?? [])];
}

export function configOptions(
  plan: RiffPlan,
  config: RiffConfig,
): SessionConfigOption[] {
  return [
    {
      id: 'model',
      name: 'Model',
      category: 'model',
      type: 'select',
      currentValue: config.model,
      options: PLAN_MODELS[plan].map(({ id }) => ({ value: id, name: id })),
    },
    {
      id: 'effort',
      name: 'Effort',
      category: 'thought_level',
      type: 'select',
      currentValue: config.effort,
      options: effortsOf(plan, config.model).map((effort) => ({
        value: effort,
        name: effort,
      })),
    },
    {
      id: 'mode',
      name: 'Mode',
      category: 'mode',
      type: 'select',
      currentValue: config.mode,
      options: MODES.map((mode) => ({ value: mode, name: mode })),
    },
  ];
}

/**
 * `config` with option `id` set to `value`, or undefined for an option or a
 * value riff does not offer.
 */
export function setOption(
  plan: RiffPlan,
  config: RiffConfig,
  id: string,
  value: unknown,
): RiffConfig | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }

  if (id === 'model' && PLAN_MODELS[plan].some((model) => model.id === value)) {
    // A model without the effort set runs on its own default instead.
    const effort = effortsOf(plan, value).includes(config.effort)
      ? config.effort
      : 'default';

    return { ...config, model: value, effort };
  }

  if (
    id === 'effort' &&
    (effortsOf(plan, config.model) as readonly string[]).includes(value)
  ) {
    return { ...config, effort: value as RiffEffort };
  }

  if (id === 'mode' && (MODES as readonly string[]).includes(value)) {
    return { ...config, mode: value as RiffMode };
  }

  return undefined;
}
