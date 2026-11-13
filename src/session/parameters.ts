/**
 * A model's parameters as `/model` shows them (CHD-626): its effort, its
 * `model_config` options (ACP's "context size or speed/quality trade-off"),
 * its fast option, and the one line of text under the model list. Options
 * are recognised by what ACP and chord's `_meta` say, never by their words.
 * Pure.
 */
import type { SessionConfigOption } from '@agentclientprotocol/sdk/unstable';
import cliTruncate from 'cli-truncate';
import stringWidth from 'string-width';
import {
  type AgentOption,
  optionsFromConfigOptions,
  valueName,
} from './config.ts';
import { effortsFrom } from './efforts.ts';
import { modelConfigId } from './models.ts';

/** The `_meta` key chord's own adapters name a parameter with. */
const PARAMETER_KEY = 'chord/parameter';

/** The options of category `model_config`, in the agent's order. */
export function modelConfigOptions(options: unknown): AgentOption[] {
  const ids = new Set(
    selects(options)
      .filter((option) => option.category === 'model_config')
      .map((option) => option.id),
  );

  return optionsFromConfigOptions(options).filter((option) =>
    ids.has(option.id),
  );
}

/**
 * The fast option: the one `_meta["chord/parameter"]` names `fast`, else the
 * one with the id chord's agent entry records for the agent (`recorded`).
 * ACP has no category telling speed from other `model_config` options.
 */
export function fastOption(
  options: unknown,
  recorded?: string,
): AgentOption | undefined {
  const marked = selects(options).find(
    (option) => parameterOf(option) === 'fast',
  );
  const id = marked?.id ?? recorded;

  return id === undefined
    ? undefined
    : optionsFromConfigOptions(options).find((option) => option.id === id);
}

/**
 * Whether the agent offers settable options besides the mode, the model, the
 * effort and the `model_config` ones: `/config` then has more to show.
 */
export function hasOtherOptions(options: unknown): boolean {
  const effort = effortsFrom(options)?.option;
  const shown = new Set(modelConfigOptions(options).map((option) => option.id));

  return optionsFromConfigOptions(options).some(
    (option) => option.id !== effort && !shown.has(option.id),
  );
}

/** What `/model`'s settings line is drawn from. */
export interface SettingsLineInput {
  /** The agent's config options, as it last sent them. */
  readonly options: unknown;
  /** The name of the model in use. */
  readonly inUse: string;
  /** The highlighted model's name, when it is not the one in use. */
  readonly highlighted?: string;
  /** The effort value id the person moved to and has not yet sent. */
  readonly pending?: string;
  /** The cells the line may take. */
  readonly width: number;
  /** The keys that move the effort, as the hint names them; `←/→` unbound. */
  readonly keys?: string;
}

export interface SettingsLine {
  readonly text: string;
  /** Q4's line: nothing to change, drawn dim. */
  readonly dim: boolean;
  /** Whether the narrow text was taken, which the hint follows (N1). */
  readonly narrow: boolean;
}

/**
 * `/model`'s line under the list (CHD-626, Q1 and Q4): the wide text when it
 * fits, else the narrow one, else the narrow one cut with `…` from the right,
 * so the effort, first, is the last to go. Undefined when the agent gives
 * its models the older way and nothing else to set (M5).
 */
export function settingsLine(
  input: SettingsLineInput,
): SettingsLine | undefined {
  const { options } = input;
  const effort = effortsFrom(options);
  const configs = modelConfigOptions(options);
  const others = hasOtherOptions(options);

  if (effort === undefined && configs.length === 0) {
    if (modelConfigId(selects(options)) === undefined && !others) {
      return undefined;
    }

    return others
      ? fitted(['/config for all settings'], ['/config…'], input.width)
      : {
          text: cliTruncate(
            `${input.inUse} has no effort or settings to change`,
            input.width,
          ),
          dim: true,
          narrow: false,
        };
  }

  const pending =
    effort !== undefined &&
    input.pending !== undefined &&
    input.pending !== effort.current
      ? effort.available.find((each) => each.id === input.pending)
      : undefined;
  const shown =
    pending ?? effort?.available.find((each) => each.id === effort.current);
  const name = shown?.name ?? effort?.current ?? '';
  const mark = pending === undefined ? '' : ' •';
  const keys = input.keys ?? '←/→';
  const wide: string[] =
    effort === undefined ? [] : [`${name} effort${mark}  ${keys} to adjust`];
  const narrow: string[] =
    effort === undefined ? [] : [`${name} effort${mark} ${keys}`];

  if (input.highlighted !== undefined) {
    // Another model's parameters are unknown until the session is on it; the
    // model in use's own values would be read as its.
    if (pending !== undefined) {
      wide.push(
        `asked for once ${input.highlighted} is in use, if it offers ${pending.name}`,
      );
      narrow.push(`asked for on ${input.highlighted}, if offered`);
    }

    return fitted(wide, narrow, input.width);
  }

  for (const option of configs) {
    const value = valueName(option, option.current);

    wide.push(`${option.name}  ${value}`);
    narrow.push(`${option.name} ${value}`);
  }

  if (others) {
    wide.push('/config for all settings');
    narrow.push('/config…');
  }

  return fitted(wide, narrow, input.width);
}

function fitted(
  wide: readonly string[],
  narrow: readonly string[],
  width: number,
): SettingsLine {
  const long = wide.join(' · ');
  const short = narrow.join(' · ');

  const fits = stringWidth(long) <= width;

  return {
    text: fits ? long : cliTruncate(short, Math.max(1, width)),
    dim: false,
    narrow: !fits,
  };
}

function selects(
  options: unknown,
): Extract<SessionConfigOption, { type: 'select' }>[] {
  return Array.isArray(options)
    ? (options as SessionConfigOption[]).filter(
        (option) => option.type === 'select',
      )
    : [];
}

function parameterOf(option: SessionConfigOption): unknown {
  const meta: unknown = option._meta;

  return typeof meta === 'object' && meta !== null
    ? (meta as Record<string, unknown>)[PARAMETER_KEY]
    : undefined;
}
