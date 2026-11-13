/**
 * A choice made in `/model` or `/effort` with one Enter (CHD-626): the model,
 * if it changed, then the effort, if the person moved it. Each step is one
 * ACP call, read against the option set as the agent last sent it; this
 * module says what the next step is and what the transcript says after.
 * Pure.
 */
import { type AgentEfforts, effortsFrom } from './efforts.ts';

export interface ModelChoice {
  /** The model to switch to, when it is not the one in use. */
  readonly model?: { readonly id: string; readonly name: string };
  /**
   * The effort the person moved to, as asked: the option's and the value's
   * ids, and the value's name to say it by.
   */
  readonly effort?: {
    readonly option: string;
    readonly value: string;
    readonly name: string;
  };
}

/** The effort call to make: an option, one of its values. */
export interface EffortStep {
  readonly option: string;
  readonly value: string;
  /** The option's name, such as `Effort`, as notes say it. */
  readonly name: string;
}

/**
 * The effort call for `choice` after its model step, from `options`, the set
 * as it is now; undefined when it is not offered there. After a switch the
 * new set's `thought_level` option is asked for the same value id, matched
 * by id and never by meaning; without one, the option asked for must still
 * be the effort option. A value not listed is not asked for, as
 * `askStarting` does.
 */
export function effortStep(
  choice: ModelChoice,
  options: unknown,
): EffortStep | undefined {
  const asked = choice.effort;
  const efforts = effortsFrom(options);

  if (
    asked === undefined ||
    efforts === undefined ||
    (choice.model === undefined && efforts.option !== asked.option) ||
    !efforts.available.some((each) => each.id === asked.value)
  ) {
    return undefined;
  }

  return {
    option: efforts.option,
    value: asked.value,
    name: optionName(options, efforts.option),
  };
}

/** The transcript row while `choice`'s first step waits for its answer. */
export function pendingText(choice: ModelChoice, options: unknown): string {
  if (choice.model !== undefined) {
    return `Switching to ${choice.model.name}…`;
  }

  const option = choice.effort?.option ?? '';

  return `Setting ${optionName(options, option)} to ${choice.effort?.name ?? ''}…`;
}

/** How a choice's steps ended. */
export type ChoiceResult =
  | { readonly model: 'refused'; readonly reason: string }
  | {
      readonly model?: 'switched';
      readonly effort: 'unmoved' | 'set' | 'not_offered';
    }
  | {
      readonly model?: 'switched';
      readonly effort: 'refused';
      /** The option asked, by its name. */
      readonly option: string;
      readonly reason: string;
    };

export interface ChoiceNote {
  readonly text: string;
  readonly failed: boolean;
}

/**
 * The note that replaces the pending row: `after` is the set once the last
 * step was answered, `inUse` the name of the model the choice began on. The
 * model stays when its effort is refused or not offered: the person asked for
 * it, and undoing it is another call that may fail.
 */
export function choiceNote(
  choice: ModelChoice,
  result: ChoiceResult,
  after: unknown,
  inUse: string,
): ChoiceNote {
  const asked = choice.effort?.name ?? '';
  const model = choice.model?.name;
  const efforts = effortsFrom(after);

  if (result.model === 'refused') {
    return {
      text: `Could not switch to ${model ?? ''}: ${result.reason}`,
      failed: true,
    };
  }

  switch (result.effort) {
    case 'unmoved':
      return { text: `Switched to ${model ?? ''}`, failed: false };
    case 'set':
      return model === undefined
        ? {
            text: `${optionName(after, efforts?.option ?? '')} set to ${currentName(efforts) ?? asked}`,
            failed: false,
          }
        : {
            text: `Switched to ${model} · ${currentName(efforts) ?? asked} effort`,
            failed: false,
          };
    case 'refused':
      return model === undefined
        ? {
            text: `Could not set ${result.option} to ${asked}: ${result.reason}`,
            failed: true,
          }
        : {
            text: `Switched to ${model}; could not set ${result.option} to ${asked}: ${result.reason}`,
            failed: true,
          };
    case 'not_offered': {
      const on = currentName(efforts);

      return model === undefined
        ? {
            text: `${asked} effort was not sent: ${inUse} no longer offers it${
              on === undefined ? '.' : `; it is on ${on}.`
            }`,
            failed: false,
          }
        : {
            text: `Switched to ${model}; it offers no ${asked} effort${
              on === undefined ? '.' : `, it is on ${on}.`
            }`,
            failed: false,
          };
    }
  }
}

function currentName(efforts: AgentEfforts | undefined): string | undefined {
  return efforts?.available.find((each) => each.id === efforts.current)?.name;
}

/** The agent's name for option `id`; the id when it gives none. */
function optionName(options: unknown, id: string): string {
  const found: unknown = Array.isArray(options)
    ? (options as unknown[]).find(
        (option) =>
          typeof option === 'object' &&
          option !== null &&
          (option as { id?: unknown }).id === id,
      )
    : undefined;
  const name =
    typeof found === 'object' && found !== null
      ? (found as { name?: unknown }).name
      : undefined;

  return typeof name === 'string' && name !== '' ? name : id;
}
