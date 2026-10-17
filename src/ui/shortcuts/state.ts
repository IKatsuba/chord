/**
 * The shortcuts' part of the window's state: the panel, the keymap and a
 * chord's first keys; and the words the window's keys are read in, a press
 * and what it asks for.
 */
import {
  DEFAULT_KEYMAP,
  type Keymap,
  type Sequence,
  type TabNumber,
} from './bindings.ts';
import type { ScrollStep } from '../transcript/scroll.ts';

export interface ShortcutsState {
  /** `?` on an empty prompt: the shortcuts panel is open. */
  readonly help: boolean;
  /** Which key does what: the defaults, or as the keybindings file has it. */
  readonly keys: Keymap;
  /** The first keys of a chord, while the next is waited for. */
  readonly pendingKeys?: Sequence;
  /**
   * What was wrong in the keybindings file, said in the status line until
   * the draft is first touched.
   */
  readonly keysFailed?: string;
}

export type ShortcutsAction =
  | { readonly type: 'help_toggled' }
  | { readonly type: 'help_closed' }
  /** `/help`: the panel opens, whatever it was. */
  | { readonly type: 'help_opened' }
  /** The first keys of a chord were pressed; none once it ended or lapsed. */
  | { readonly type: 'keys_pending'; readonly keys?: Sequence };

export const initialShortcuts: ShortcutsState = {
  help: false,
  keys: DEFAULT_KEYMAP,
};

export function reduceShortcuts(
  state: ShortcutsState,
  action: ShortcutsAction,
): ShortcutsState {
  switch (action.type) {
    case 'keys_pending': {
      if (action.keys !== undefined) {
        return { ...state, pendingKeys: action.keys };
      }

      if (state.pendingKeys === undefined) {
        return state;
      }

      const { pendingKeys: _, ...rest } = state;

      return rest;
    }
    case 'help_toggled':
      return { ...state, help: !state.help };
    case 'help_closed':
      return state.help ? { ...state, help: false } : state;
    case 'help_opened':
      return state.help ? state : { ...state, help: true };
  }
}

/**
 * A key press as chord's own keys read it; a test or a reducer's own
 * default may leave out what it does not press.
 */
export interface KeyPress {
  readonly ctrl: boolean;
  readonly escape: boolean;
  readonly shift?: boolean;
  readonly upArrow?: boolean;
  readonly downArrow?: boolean;
  readonly pageUp?: boolean;
  readonly pageDown?: boolean;
  readonly home?: boolean;
  readonly end?: boolean;
  readonly tab?: boolean;
  readonly backspace?: boolean;
  readonly return?: boolean;
  readonly leftArrow?: boolean;
  readonly rightArrow?: boolean;
  readonly delete?: boolean;
  readonly meta?: boolean;
  /** cmd, which only a terminal speaking kitty's keyboard protocol reports. */
  readonly super?: boolean;
  /**
   * The key in the same place on the base layout, where the press is on
   * another and a terminal speaking kitty's keyboard protocol says so:
   * `press.ts` reads it from OpenTUI's `baseCode`.
   */
  readonly base?: string;
}

/** A press as `usePress` hands it on, every modifier and key said. */
export type Press = Required<Omit<KeyPress, 'base'>> & Pick<KeyPress, 'base'>;

/** What a key press asks the window to do; text editing is the input's. */
export type KeyCommand =
  /**
   * ctrl+c, or a key bound to `selection:copy`, while a selection is shown:
   * copy it, and nothing else.
   */
  | 'copy_selection'
  | 'interrupt'
  /** Esc while the agent asks permission: reject it, the turn goes on. */
  | 'reject_permission'
  | 'arm_quit'
  | 'quit'
  /** ctrl+c on a draft: clear it rather than move a step closer to quitting. */
  | 'clear_draft'
  /** ctrl+o: show thoughts and tool output in full, or summarise them again. */
  | 'toggle_expanded'
  /** `?` on an empty prompt: open the shortcuts panel, or close it. */
  | 'toggle_help'
  /** Esc while the shortcuts panel is open closes it before anything else. */
  | 'close_help'
  /** shift+tab: ask the agent for its next mode. */
  | 'cycle_mode'
  /** Tab in the slash command list: the highlighted name into the prompt. */
  | 'complete_command'
  /** ↑ and ↓ in the slash command list move its highlight, not history. */
  | 'menu_up'
  | 'menu_down'
  /** Esc puts the slash command list away before anything else it does. */
  | 'close_menu'
  /** Esc closes the model picker rather than interrupting the turn. */
  | 'close_model_picker'
  /** Esc closes the session picker, and the session on screen stays. */
  | 'close_resume_picker'
  /** ctrl+a in the session picker: this directory's sessions or every one's. */
  | 'toggle_resume_scope'
  /** Esc backs `/config`'s picker out one level: values, options, shut. */
  | 'close_config_picker'
  /** Esc closes `/theme`'s picker, and the theme in use before it comes back. */
  | 'close_theme_picker'
  /** Esc closes `/mcp`'s list. */
  | 'close_mcp'
  /** Esc closes `/team`'s picker. */
  | 'close_teams_picker'
  /** Tab in the `@` file finder: the highlighted path into the prompt. */
  | 'complete_mention'
  /** ↑ and ↓ in the `@` file finder move its highlight, not history. */
  | 'finder_up'
  | 'finder_down'
  /** Esc puts the `@` file finder away and keeps what was typed. */
  | 'close_finder'
  /** Backspace on an empty prompt in bash mode turns the mode off. */
  | 'leave_bash'
  /** Esc while a shell command runs stops it. */
  | 'stop_shell'
  /** ctrl+r: open the reverse history search. */
  | 'search_history'
  /** ctrl+r again: the next older prompt that matches. */
  | 'search_older'
  /** Enter or Tab: the match into the box, to edit. */
  | 'accept_search'
  /** Esc or ctrl+c: the search closes and the draft is as it was. */
  | 'cancel_search'
  /** ctrl+g: the draft in `$VISUAL` or `$EDITOR`, and back. */
  | 'open_editor'
  /** ctrl+v: the clipboard's image into the draft, as `[Image #N]`. */
  | 'paste_image'
  /** Esc in vim's insert mode: normal mode. */
  | 'vim_normal'
  /** A key vim's normal mode takes: a motion, an operator, an edit. */
  | 'vim_key'
  /** Esc on a command half typed in normal mode drops it. */
  | 'vim_clear'
  /** Enter in normal mode sends, as it does from insert mode. */
  | 'vim_send'
  /** A key bound to `chat:submit` that the prompt's textarea does not send on. */
  | 'submit'
  /** A key bound to `chat:newline` that the textarea does not break on. */
  | 'newline'
  /** A key bound to `history:previous` or `history:next` other than ↑ and ↓. */
  | 'history_older'
  | 'history_newer'
  /** ctrl+x c: a new session of the front one's agent, in front. */
  | 'new_session'
  /** ctrl+x n and ctrl+x p: the next or previous tab, round the ends. */
  | 'next_session'
  | 'previous_session'
  /** ctrl+x 1 to 9: that tab, if there is one. */
  | `goto_session_${TabNumber}`
  /** ctrl+x w: the sessions picker. */
  | 'list_sessions'
  /** Esc closes the sessions picker, and the session in front stays. */
  | 'close_sessions_picker'
  /** ctrl+x a: the session behind that has waited longest for the person. */
  | 'attend_session'
  /** ctrl+x k: closes the front session, or asks again while it is busy. */
  | 'close_session'
  /** ↑ and ↓, or k and j, in the list of agents: pick the row above or below. */
  | 'agents_up'
  | 'agents_down'
  /** Enter or Esc in the list: back to the box, the pick kept. */
  | 'agents_leave'
  /** x in the list: closes the picked child, or asks again while it is busy. */
  | 'close_agent'
  /** Enter on the background's summary line: its view opens. */
  | 'open_background'
  /** ↑ and ↓, or k and j, in the background view: the row above or below. */
  | 'background_up'
  | 'background_down'
  /** x in the background view: the focused item stops at once. */
  | 'stop_background'
  /** Esc in the background view: back to the summary line. */
  | 'close_background'
  /** The first keys of a chord: the next is waited for. */
  | 'key_pending'
  /** A key after a chord's first that finishes no chord: both go. */
  | 'key_dropped'
  /** pgup, pgdn, shift+↑/↓, home and end move the transcript's view. */
  | `scroll_${ScrollStep}`
  /** The same keys while a permission request overflows its box: they move it. */
  | `request_${ScrollStep}`;

/** A key named at the start of a sentence: `Esc`, `Ctrl+x`. */
export function capital(key: string): string {
  return key.charAt(0).toUpperCase() + key.slice(1);
}
