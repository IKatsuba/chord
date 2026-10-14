/**
 * What the agent has said about a session besides its turns: its config
 * options, its modes and models the older way, and its slash commands, from
 * the answer that opened the session, the updates since, and the answers to
 * the changes chord asked for. Pure; the session folds into it as each comes.
 */
import type {
  AvailableCommand,
  SessionConfigOption,
  SessionModeState,
  SessionUpdate,
} from '@agentclientprotocol/sdk';
import { type AgentOption, optionsFromConfigOptions } from './config.ts';
import { type AgentEfforts, effortsFrom } from './efforts.ts';
import { type AgentModels, modelsFrom } from './models.ts';
import { type AgentModes, modeConfigId, modesFrom } from './modes.ts';

export interface AgentState {
  readonly configOptions: readonly SessionConfigOption[];
  /** `modes` as `session/new` gave them, for an agent with no mode option. */
  readonly modes?: SessionModeState;
  /** `models` as `session/new` gave them, unchecked: not stable in ACP v1. */
  readonly models?: unknown;
  readonly commands: readonly AvailableCommand[];
}

/** The fields of `session/new`'s answer, and its kin's, that state comes from. */
export interface SessionAnswer {
  readonly configOptions?: readonly SessionConfigOption[] | null;
  readonly modes?: SessionModeState | null;
  readonly models?: unknown;
}

export function stateOf(answer: SessionAnswer): AgentState {
  return {
    configOptions: answer.configOptions ?? [],
    ...(answer.modes ? { modes: answer.modes } : {}),
    ...(answer.models === undefined || answer.models === null
      ? {}
      : { models: answer.models }),
    commands: [],
  };
}

/** `state` after one of the agent's updates; most leave it as it was. */
export function foldUpdate(
  state: AgentState,
  update: SessionUpdate,
): AgentState {
  switch (update.sessionUpdate) {
    case 'config_option_update':
      return withOptions(state, update.configOptions);
    case 'current_mode_update':
      return withMode(state, update.currentModeId);
    case 'available_commands_update':
      return Array.isArray(update.availableCommands)
        ? { ...state, commands: update.availableCommands }
        : state;
    default:
      return state;
  }
}

/**
 * `state` with the config options an agent answered or sent. An answer that
 * carries none, as some do, leaves the options as they were.
 */
export function withOptions(
  state: AgentState,
  configOptions: readonly SessionConfigOption[] | null | undefined,
): AgentState {
  return Array.isArray(configOptions) ? { ...state, configOptions } : state;
}

/**
 * `state` in the mode the agent reports, in its mode config option too, so
 * the option it last sent does not undo a `current_mode_update`.
 */
function withMode(state: AgentState, id: string): AgentState {
  const key = modeConfigId(state.configOptions);

  return {
    ...state,
    configOptions: state.configOptions.map((option) =>
      option.id === key && option.type === 'select'
        ? { ...option, currentValue: id }
        : option,
    ),
    ...(state.modes ? { modes: { ...state.modes, currentModeId: id } } : {}),
  };
}

export function modesOf(state: AgentState): AgentModes | undefined {
  return modesFrom(state.configOptions, state.modes);
}

export function modelsOf(state: AgentState): AgentModels | undefined {
  return modelsFrom(state.configOptions, state.models);
}

export function optionsOf(state: AgentState): AgentOption[] {
  return optionsFromConfigOptions(state.configOptions);
}

export function effortsOf(state: AgentState): AgentEfforts | undefined {
  return effortsFrom(state.configOptions);
}
