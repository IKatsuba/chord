/**
 * The pickers' part of the window's state: which of the model, resume,
 * sessions, config, theme and teams pickers and `/mcp`'s list is open and
 * where it stands, and the theme in use.
 */
import type { AgentOption } from '../../session/config.ts';
import type { AgentEfforts } from '../../session/efforts.ts';
import type { EarlierSession } from '../../session/sessions.ts';
import type { TeamListing } from '../../session/team_command.ts';
import type { Transcript } from '../../session/transcript/types.ts';
import { asksPerson } from '../dialogs/state.ts';
import type { ThemeSetting } from '../theme/theme.ts';

export interface PickersState {
  /** `/model`: the model picker is open. */
  readonly modelPicker: boolean;
  /**
   * `/model`: the effort moved with ←/→ and not sent yet, kept as asked
   * until Enter, whatever the agent sends meanwhile (CHD-626).
   */
  readonly modelEffort?: PendingEffort;
  /** `/effort`: the picker of the model in use's efforts is open. */
  readonly effortPicker?: true;
  /** `/resume`: the session picker is open. */
  readonly resumePicker?: ResumePicker;
  /**
   * The `/resume` whose read of the session records is still out. Only its
   * list may open the picker; `/clear` and quitting forget it.
   */
  readonly resumeAsked?: string;
  /**
   * `/config`: the picker is open, on the list of options or, once one is
   * chosen, on that option's values.
   */
  readonly configPicker?: ConfigPicker;
  /** The `theme` setting in use: chosen with `/theme`, kept across `/clear`. */
  readonly theme: ThemeSetting;
  /** `/theme`: the picker is open, the window drawn in the one highlighted. */
  readonly themePicker?: { readonly previewing: ThemeSetting };
  /** `/mcp`: the list of MCP servers chord passed to the agent is open. */
  readonly mcpPanel: boolean;
  /** `/team`: the teams picker is open on the teams and runs it read. */
  readonly teamsPicker?: TeamListing;
}

/** An effort as the person asked for it: the option's and value's ids. */
export interface PendingEffort {
  readonly option: string;
  readonly value: string;
  /** The agent's name for the value, as notes say it. */
  readonly name: string;
}

export interface ConfigPicker {
  /** The option whose values are listed; absent on the list of options. */
  readonly option?: string;
  /** On the list of options, the one Esc came back from, highlighted. */
  readonly from?: string;
}

/**
 * `/resume`'s picker: the sessions it read, which directories it shows them
 * from, and the working directory that the narrow scope keeps to.
 */
export interface ResumePicker {
  /** Every directory's earlier sessions, newest first. */
  readonly sessions: readonly EarlierSession[];
  /** The window's working directory, resolved. */
  readonly cwd: string;
  /** Whether every directory's sessions are shown, or only `cwd`'s. */
  readonly everywhere: boolean;
}

export type PickersAction =
  /** `/model` opens the model picker. */
  | { readonly type: 'model_picker_opened' }
  /** Esc, or a model picked, closes it. */
  | { readonly type: 'model_picker_closed' }
  /**
   * ← or → in it: the effort one down or up `efforts`, the agent's order,
   * stopping at either end.
   */
  /** `/effort` opens its picker; Esc, or an effort picked, closes it. */
  | { readonly type: 'effort_picker_opened' }
  | { readonly type: 'effort_picker_closed' }
  | {
      readonly type: 'model_effort_moved';
      readonly efforts: AgentEfforts;
      readonly by: -1 | 1;
    }
  /** `/resume` went to read the sessions. */
  | { readonly type: 'resume_asked'; readonly asked: string }
  /** ctrl+a: the picker shows every directory's sessions, or this one's again. */
  | { readonly type: 'resume_scope_toggled' }
  /** Esc, or a session picked, closes it. */
  | { readonly type: 'resume_picker_closed' }
  /** `/config` opens its picker on the list of options. */
  | { readonly type: 'config_picker_opened' }
  /** Enter on an option lists its values. */
  | { readonly type: 'config_option_opened'; readonly id: string }
  /** Esc backs out one level: from the values to the options, then shut. */
  | { readonly type: 'config_picker_back' }
  /** A value picked closes the picker. */
  | { readonly type: 'config_picker_closed' }
  /** `/theme` opens its picker on the theme in use. */
  | { readonly type: 'theme_picker_opened' }
  /** The picker's highlight moved: the window previews that theme. */
  | { readonly type: 'theme_previewed'; readonly theme: ThemeSetting }
  /** Esc: the theme in use before `/theme` comes back. */
  | { readonly type: 'theme_picker_closed' }
  /** Enter: the theme highlighted is the one in use. */
  | { readonly type: 'theme_chosen'; readonly theme: ThemeSetting }
  /** `/mcp` opens the list of MCP servers. */
  | { readonly type: 'mcp_opened' }
  /** Esc closes it. */
  | { readonly type: 'mcp_closed' }
  /** `/team`'s read came back: the picker opens on what it found. */
  | { readonly type: 'teams_picker_opened'; readonly listing: TeamListing }
  /** Esc, or a team picked, closes it. */
  | { readonly type: 'teams_picker_closed' };

export const initialPickers: PickersState = {
  modelPicker: false,
  mcpPanel: false,
  theme: 'auto',
};

export function reducePickers(
  state: PickersState,
  action: PickersAction,
): PickersState {
  switch (action.type) {
    case 'mcp_opened':
      return state.mcpPanel ? state : { ...state, mcpPanel: true };
    case 'mcp_closed':
      return state.mcpPanel ? { ...state, mcpPanel: false } : state;
    case 'teams_picker_opened':
      return { ...state, teamsPicker: action.listing };
    case 'teams_picker_closed': {
      const { teamsPicker: _, ...rest } = state;

      return state.teamsPicker === undefined ? state : rest;
    }
    case 'model_picker_opened':
      return state.modelPicker ? state : { ...state, modelPicker: true };
    case 'model_picker_closed': {
      const { modelEffort: _, ...rest } = state;

      return state.modelPicker ? { ...rest, modelPicker: false } : state;
    }
    case 'effort_picker_opened':
      return { ...state, effortPicker: true };
    case 'effort_picker_closed': {
      const { effortPicker: _, ...rest } = state;

      return state.effortPicker === undefined ? state : rest;
    }
    case 'model_effort_moved':
      return state.modelPicker ? movedEffort(state, action) : state;
    case 'config_picker_opened':
      return { ...state, configPicker: {} };
    case 'config_option_opened':
      return state.configPicker === undefined
        ? state
        : { ...state, configPicker: { option: action.id } };
    case 'config_picker_back': {
      const from = state.configPicker?.option;

      if (from !== undefined) {
        return { ...state, configPicker: { from } };
      }

      const { configPicker: _, ...rest } = state;

      return state.configPicker === undefined ? state : rest;
    }
    case 'config_picker_closed': {
      const { configPicker: _, ...rest } = state;

      return state.configPicker === undefined ? state : rest;
    }
    case 'theme_picker_opened':
      return { ...state, themePicker: { previewing: state.theme } };
    case 'theme_previewed':
      return state.themePicker === undefined
        ? state
        : { ...state, themePicker: { previewing: action.theme } };
    case 'theme_picker_closed': {
      const { themePicker: _, ...rest } = state;

      return state.themePicker === undefined ? state : rest;
    }
    case 'theme_chosen': {
      const { themePicker: _, ...rest } = state;

      return { ...rest, theme: action.theme };
    }
    case 'resume_asked':
      return { ...state, resumeAsked: action.asked };
    case 'resume_scope_toggled':
      return state.resumePicker === undefined
        ? state
        : {
            ...state,
            resumePicker: {
              ...state.resumePicker,
              everywhere: !state.resumePicker.everywhere,
            },
          };
    case 'resume_picker_closed': {
      const { resumePicker: _, ...rest } = state;

      return state.resumePicker === undefined ? state : rest;
    }
  }
}

/**
 * `state` with its pending effort one step from where it stands: the one
 * asked, while the agent still lists it, else the one in use. Back on the
 * one in use, nothing is pending.
 */
function movedEffort(
  state: PickersState,
  { efforts, by }: { readonly efforts: AgentEfforts; readonly by: -1 | 1 },
): PickersState {
  const { available } = efforts;
  const asked = state.modelEffort;
  const from = available.findIndex(
    (each) =>
      each.id ===
      (asked?.option === efforts.option ? asked.value : efforts.current),
  );
  const start =
    from >= 0
      ? from
      : available.findIndex((each) => each.id === efforts.current);
  const to = available[Math.min(available.length - 1, Math.max(0, start + by))];
  const { modelEffort: _, ...rest } = state;

  if (to === undefined || start < 0 || to.id === efforts.current) {
    return start < 0 ? state : rest;
  }

  return {
    ...state,
    modelEffort: { option: efforts.option, value: to.id, name: to.name },
  };
}

/**
 * What a picker reads of the session under it to know whether it is shown:
 * whether the session is up or closing, and whether the turn asks the person.
 */
interface Under {
  readonly connection: { readonly status: string };
  readonly transcript: Transcript;
}

/**
 * Whether the model picker is on screen: opened, and the session up. A
 * permission asked meanwhile takes its place until it is answered, so the
 * digits and Enter answer one list, not two.
 */
export function modelPickerShown(state: PickersState & Under): boolean {
  return (
    state.modelPicker &&
    state.connection.status === 'ready' &&
    !asksPerson(state.transcript)
  );
}

/**
 * Whether `/effort`'s picker is on screen: opened, and the session up, as
 * the model picker is; a permission asked meanwhile takes its place.
 */
export function effortPickerShown(state: PickersState & Under): boolean {
  return (
    state.effortPicker === true &&
    state.connection.status === 'ready' &&
    !asksPerson(state.transcript)
  );
}

/** The sessions the picker lists, newest first, for the scope it is on. */
export function resumeChoices(picker: ResumePicker): EarlierSession[] {
  return picker.everywhere
    ? [...picker.sessions]
    : picker.sessions.filter((session) => session.resume.cwd === picker.cwd);
}

/**
 * Whether the session picker is on screen: opened, and not closing. Unlike
 * the model picker it needs no session up, as a session that failed to start
 * can be left for an earlier one. A permission asked meanwhile takes its
 * place, as it does the model picker's.
 */
export function resumePickerShown(state: PickersState & Under): boolean {
  return (
    state.resumePicker !== undefined &&
    state.connection.status !== 'closing' &&
    !asksPerson(state.transcript)
  );
}

/**
 * Whether `/config`'s picker is on screen: opened, and the session up, as the
 * model picker is; a permission asked meanwhile takes its place.
 */
export function configPickerShown(state: PickersState & Under): boolean {
  return (
    state.configPicker !== undefined &&
    state.connection.status === 'ready' &&
    !asksPerson(state.transcript)
  );
}

/**
 * Whether `/theme`'s picker is on screen: opened, and not closing. Like the
 * session picker it needs no session up, as colours are chord's own; a
 * permission asked meanwhile takes its place, and the theme in use with it.
 */
export function themePickerShown(state: PickersState & Under): boolean {
  return (
    state.themePicker !== undefined &&
    state.connection.status !== 'closing' &&
    !asksPerson(state.transcript)
  );
}

/**
 * Whether `/mcp`'s list is on screen: opened, and not closing. It needs no
 * session up, as the servers are what chord passed, not what the agent says;
 * a permission asked meanwhile takes its place.
 */
export function mcpShown(state: PickersState & Under): boolean {
  return (
    state.mcpPanel &&
    state.connection.status !== 'closing' &&
    !asksPerson(state.transcript)
  );
}

/**
 * Whether `/team`'s picker is on screen: opened, and not closing. It needs
 * no session up, as the teams are files; a permission asked meanwhile takes
 * its place.
 */
export function teamsPickerShown(state: PickersState & Under): boolean {
  return (
    state.teamsPicker !== undefined &&
    state.connection.status !== 'closing' &&
    !asksPerson(state.transcript)
  );
}

/** The theme the window is drawn in: the one previewed, else the one in use. */
export function shownTheme(state: PickersState & Under): ThemeSetting {
  return themePickerShown(state) && state.themePicker
    ? state.themePicker.previewing
    : state.theme;
}

/**
 * The option `/config`'s picker lists the values of; none on the list of
 * options, or once the agent stops offering the one chosen.
 */
export function configOption(
  state: PickersState & { readonly options: readonly AgentOption[] },
): AgentOption | undefined {
  const id = state.configPicker?.option;

  return id === undefined
    ? undefined
    : state.options.find((option) => option.id === id);
}
