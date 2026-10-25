/**
 * Every key chord answers, as the shortcuts panel lists it. Key handling is
 * tested against this list, so a key that does something and is missing here
 * fails a test rather than going unlisted.
 */
import stringWidth from 'string-width';
import {
  type Action,
  DEFAULT_KEYMAP,
  isDefault,
  type Keymap,
  keysOf,
  sequencePanel,
} from './bindings.ts';
import type { KeyCommand } from './state.ts';
import { NORMAL_KEYS } from '../prompt/vim.ts';

export interface Shortcut {
  /** The key as the panel names it, in Claude Code's spelling: `ctrl + o`. */
  readonly key: string;
  /** The rest of the line after the key: `to quit`. */
  readonly does: string;
  /**
   * What `keyCommand` answers this key with. Empty for a key a widget handles
   * itself (Enter in the prompt, digits in the permission prompt).
   */
  readonly commands: readonly KeyCommand[];
  /**
   * The presses `commands` answer, named as the key test names them, when
   * `key` is more than one of them; `key` itself otherwise.
   */
  readonly presses?: readonly string[];
  /**
   * The presses the permission prompt's ink-select-input and the pickers'
   * list answer for this entry, named as the key test names them. The test
   * presses every key on the real lists, so one they answer that no entry
   * names fails it.
   */
  readonly choices?: readonly string[];
  /**
   * The presses an agent's form answers for this entry, besides typing and
   * editing in a text field, named as the key test names them.
   */
  readonly form?: readonly string[];
  /**
   * The presses the question box answers for this entry, besides typing and
   * editing a text row and the keys it shares with the permission prompt's
   * list, named as the key test names them.
   */
  readonly questions?: readonly string[];
  /**
   * The presses the prompt's textarea sends the draft on, breaks its line on,
   * walks history on, or moves its cursor by word or to the line's ends on
   * with option or cmd, named the same way. Typing and editing the draft
   * (ctrl+a, ctrl+e, ctrl+k, ctrl+u, ctrl+w, ctrl+z, ctrl+y) are not listed,
   * as in Claude Code.
   */
  readonly prompt?: readonly string[];
  /**
   * The actions whose keys `key` names, in its order; a key bound elsewhere
   * by the keybindings file is named as bound. None for a key that is fixed.
   */
  readonly actions?: readonly Action[];
  /** Written before the bound keys when `actions` are named as bound. */
  readonly before?: string;
  /**
   * An action whose first key, after `before`, is named after `actions`'
   * own as another way to it, `or` between them: the backslash newline's
   * send key beside the newline's.
   */
  readonly after?: Action;
  /**
   * What also does it, such as the wheel, which no key binding moves: named
   * after the bound keys, and alone when none is bound.
   */
  readonly also?: string;
  /**
   * Only the first key bound is named, where two long ones beside `also`
   * would widen the panel's column past 80 columns' two.
   */
  readonly first?: boolean;
}

export const SHORTCUTS: readonly Shortcut[] = [
  {
    key: 'enter',
    does: 'to send',
    commands: [],
    prompt: ['enter'],
    actions: ['chat:submit'],
  },
  {
    key: 'tab',
    does: 'to send into the running turn',
    commands: ['steer'],
    actions: ['chat:steer'],
  },
  // Both newlines on one line, so the panel takes a line less at 80x24
  // (the owner's Q80): shift+enter, and the terminal-proof \ + enter for the
  // terminals that do not report it. That one is two presses, so the key
  // test cannot press it alone; the second is whatever sends, as the
  // backslash is read on send.
  {
    key: 'shift or \\ + enter',
    does: 'for a newline',
    commands: [],
    // ctrl+j is the line feed some terminals send for shift+enter, and
    // option+enter the newline macOS users reach for; one line covers them.
    prompt: ['shift + enter', 'alt + enter', 'ctrl + j'],
    actions: ['chat:newline'],
    before: '\\ + ',
    after: 'chat:submit',
    first: true,
  },
  {
    key: 'ctrl + g',
    does: 'to edit in $EDITOR',
    commands: ['open_editor'],
    actions: ['chat:externalEditor'],
  },
  {
    key: 'ctrl + v',
    does: 'to paste an image',
    commands: ['paste_image'],
    actions: ['chat:imagePaste'],
  },
  // The textarea's own moves, which macOS users reach for with option and
  // cmd (CHD-386); alt+b and alt+f are option+← and → as some terminals send
  // them. ctrl+a and ctrl+e stay off the panel, readline's as in Claude Code.
  {
    key: 'alt + ← →',
    does: 'to move by word',
    commands: [],
    prompt: ['alt + ←', 'alt + →', 'alt + b', 'alt + f'],
  },
  {
    key: 'cmd + ← →',
    does: 'to line start or end',
    commands: [],
    prompt: ['cmd + ←', 'cmd + →'],
  },
  // ↓ past the newest prompt, on an empty draft, goes into the list under
  // the prompt of the session's agents, while a child is open, and on to
  // the background's summary line; there ↑ ↓ or j k move, enter and esc go
  // back, which the status line names as a picker's last line does, and in
  // the background view ↑ ↓ or j k move between its rows. The panel still
  // fits 80x24 with the lines for x and enter.
  {
    key: '↑ ↓',
    does: 'for prompts, agents, background',
    commands: [
      'agents_up',
      'agents_down',
      'agents_leave',
      'background_up',
      'background_down',
      // From one picked code block to the next (CHD-394).
      'code_block_up',
      'code_block_down',
    ],
    presses: ['↑', '↓', 'j', 'k', 'esc'],
    prompt: ['↑', '↓'],
    actions: ['history:previous', 'history:next'],
  },
  // One action on the focused row, whichever kind it is, in the list or in
  // the background view: a rebinding moves both.
  {
    key: 'x',
    does: 'to close an agent, stop background',
    commands: ['close_agent', 'stop_background'],
    actions: ['agents:close'],
  },
  // Enter on the summary line opens the background view; on a row its
  // details, and in them the call that started it (CHD-481, CHD-487); not
  // rebindable, as a picker's
  // Enter is not. The key test presses no bare Enter on the window, so its
  // own test does (`open_background`, `go_to_call`).
  {
    key: 'enter',
    does: 'for background, details, a call',
    commands: [],
  },
  // Again while it is open, the next older match.
  {
    key: 'ctrl + r',
    does: 'to search prompts',
    commands: ['search_history', 'search_older'],
    actions: ['history:search'],
  },
  // Enter takes it too; the key test presses no bare Enter on the window.
  {
    key: 'tab enter',
    does: 'to take a match',
    commands: ['accept_search'],
    presses: ['tab'],
    actions: ['historySearch:accept'],
  },
  {
    key: 'esc',
    does: 'to cancel a search',
    commands: ['cancel_search'],
    presses: ['esc', 'ctrl + c'],
    actions: ['historySearch:cancel'],
  },
  {
    key: 'pgup pgdn or wheel',
    does: 'to scroll',
    also: 'wheel',
    // A permission request taller than its box scrolls by them (CHD-246),
    // and so does the panel itself where it overflows (CHD-378).
    commands: [
      'scroll_page_up',
      'scroll_page_down',
      'request_page_up',
      'request_page_down',
      'panel_page_up',
      'panel_page_down',
      // An error taller than the background frame's room (CHD-473).
      'background_page_up',
      'background_page_down',
    ],
    // Terminal.app passes these on only with shift held.
    presses: ['pgup', 'pgdn', 'shift + pgup', 'shift + pgdn'],
    actions: ['scroll:pageUp', 'scroll:pageDown'],
  },
  {
    key: 'shift + ↑ ↓',
    does: 'to scroll a line',
    commands: [
      'scroll_line_up',
      'scroll_line_down',
      'request_line_up',
      'request_line_down',
      'panel_line_up',
      'panel_line_down',
    ],
    presses: ['shift + ↑', 'shift + ↓'],
    actions: ['scroll:lineUp', 'scroll:lineDown'],
  },
  {
    key: 'home end',
    does: 'for the top and the bottom',
    commands: [
      'scroll_top',
      'scroll_bottom',
      'request_top',
      'request_bottom',
      'panel_top',
      'panel_bottom',
      // A detail and an error in the background frame (CHD-481).
      'background_top',
      'background_bottom',
    ],
    presses: ['home', 'end', 'shift + home', 'shift + end'],
    actions: ['scroll:top', 'scroll:bottom'],
  },
  // ctrl+c copies while a selection is shown, as the widget's key, and the
  // copy key does too; the default, ctrl+shift+c, arrives as ctrl+c without
  // kitty's protocol, so the line names ctrl+c alone (CHD-172).
  {
    key: 'ctrl + c',
    does: 'to copy',
    commands: ['copy_selection'],
    presses: ['ctrl + c'],
    actions: ['selection:copy'],
    also: 'ctrl + c',
    first: true,
  },
  // Typing either opens its list; it is the draft's, so no key command
  // answers. The commands and the files share their lines so the panel fits
  // 80x24 (CHD-386).
  { key: '/ @ @@', does: 'for commands, files or agents', commands: [] },
  {
    key: '↑ ↓',
    does: 'to pick a completion',
    commands: ['menu_up', 'menu_down', 'finder_up', 'finder_down'],
    presses: ['↑', '↓'],
    actions: ['autocomplete:previous', 'autocomplete:next'],
  },
  {
    key: 'tab',
    does: 'to complete a command',
    commands: ['complete_command'],
    actions: ['autocomplete:accept'],
  },
  // Enter picks too, through the prompt's own submit.
  {
    key: 'tab enter',
    does: 'to add a file or agent',
    commands: ['complete_mention'],
    presses: ['tab'],
    actions: ['autocomplete:accept'],
  },
  // One line for both lists, so the panel fits 80x24.
  {
    key: 'esc',
    does: 'to close completions',
    commands: ['close_menu', 'close_finder'],
    actions: ['autocomplete:dismiss'],
  },
  // Typing it on an empty prompt starts the mode; it is the draft's.
  { key: '!', does: 'for bash mode', commands: [] },
  {
    key: 'backspace',
    does: 'to leave bash mode',
    commands: ['leave_bash'],
    // Shift held or not, as the textarea deletes either way.
    presses: ['backspace', 'shift + backspace'],
  },
  // One line for a turn and a shell command, as one action stops either, so
  // the panel fits 80x24.
  {
    key: 'esc',
    does: 'to interrupt or stop a command',
    commands: ['interrupt', 'stop_shell'],
    actions: ['chat:cancel'],
  },
  {
    key: 'shift + tab',
    does: 'to cycle modes',
    commands: ['cycle_mode'],
    actions: ['chat:cycleMode'],
  },
  // Claude Code's words: thinking and tool output in full.
  {
    key: 'ctrl + o',
    does: 'for verbose output',
    commands: ['toggle_expanded'],
    actions: ['app:toggleTranscript'],
  },
  { key: 'ctrl + c', does: 'to clear input', commands: ['clear_draft'] },
  // One line for both, so the panel still fits 80x24; neither key can be
  // rebound. On a draft ctrl+d does nothing.
  {
    key: 'ctrl + d or ctrl + c',
    does: 'twice to quit',
    commands: ['arm_quit', 'quit'],
    presses: ['ctrl + d', 'ctrl + c'],
  },
  {
    key: 'ctrl + x a',
    does: 'for what waits on you',
    commands: ['key_pending', 'attend_session'],
    presses: ['ctrl + x', 'a'],
    actions: ['session:attention'],
  },
  // A code block picked through the leader, then copied or put in the
  // prompt; ↑ ↓ move between blocks and esc ends it (CHD-394).
  {
    key: 'ctrl + x b',
    does: 'to pick a code block',
    commands: ['key_pending', 'pick_code_block'],
    presses: ['ctrl + x', 'b'],
    actions: ['codeBlock:pick'],
  },
  {
    key: 'c r',
    does: 'to copy or put in the prompt',
    commands: ['copy_code_block', 'prompt_code_block'],
    presses: ['c', 'r'],
    actions: ['codeBlock:copy', 'codeBlock:prompt'],
  },
  {
    key: '1–9',
    does: 'to pick a choice',
    commands: [],
    choices: [...'123456789'],
  },
  {
    key: '↑ ↓ or j k',
    does: 'to move between choices',
    commands: [],
    // ink-select-input does not look at ctrl, so ctrl+k moves up as k does,
    // and the pickers follow it; a side effect of the widget, not a key
    // worth a line of its own.
    choices: ['↑', '↓', 'j', 'k', 'ctrl + k'],
  },
  {
    key: 'enter',
    does: 'to pick the highlighted choice',
    commands: [],
    // ink-select-input reads any Enter, whatever is held with it.
    choices: ['enter', 'shift + enter', 'alt + enter'],
  },
  {
    key: 'esc',
    does: 'to reject a permission',
    commands: ['reject_permission'],
    actions: ['confirm:no'],
  },
  // One line for both, the background view counting as a picker, so the
  // panel keeps to 40 lines, 20 rows a column at 80x24; ← leaves a
  // monitor's detail as esc does (CHD-481).
  {
    key: 'esc ←',
    does: 'to leave a picker or shortcuts',
    commands: [
      'close_help',
      'close_background',
      'background_back',
      'close_model_picker',
      'close_resume_picker',
      'close_config_picker',
      'close_theme_picker',
      'close_mcp',
      'close_teams_picker',
      'close_notice',
      'end_code_pick',
    ],
    presses: ['esc', '←'],
    actions: ['select:cancel', 'help:dismiss'],
  },
  // Claude Code's key and words in its own /resume.
  {
    key: 'ctrl + a',
    does: 'to show all directories',
    commands: ['toggle_resume_scope'],
    actions: ['select:toggleScope'],
  },
  // Forms and questions: what an agent asks for in the prompt box's place.
  // One line for all their keys, which their own hint lines name as they
  // apply, so the panel still fits 80x24; the permission prompt's keys pick
  // a question's option.
  {
    key: 'tab ← → ↑ ↓ space',
    does: 'to answer forms',
    commands: [],
    questions: ['tab', 'shift + tab', '←', '→', ' ', 'esc'],
    form: [
      'tab',
      'shift + tab',
      '↑',
      '↓',
      ' ',
      '←',
      '→',
      'backspace',
      'enter',
      'esc',
    ],
  },
  {
    key: 'ctrl + c',
    does: 'to stop the turn and its form',
    commands: ['interrupt'],
  },
  // Vim mode's keys are vim's, which a vim user knows; one line names the
  // command that turns them on, so the panel still fits 80x24.
  {
    key: '/vim',
    does: 'for vim mode',
    commands: ['vim_normal', 'vim_clear', 'vim_key'],
    presses: [
      'esc',
      ...NORMAL_KEYS,
      '↑',
      '↓',
      'backspace',
      'shift + backspace',
    ],
  },
  {
    key: '?',
    does: 'for shortcuts',
    commands: ['toggle_help'],
    actions: ['help:toggle'],
  },
  // The crash screen's (CHD-468): the panel cannot be opened there, but
  // names its key where every key is; keys_test presses every key on it.
  {
    key: 'any key',
    does: 'to quit the crash screen',
    commands: [],
  },
];

/**
 * The panel's entries for `keymap`: each as listed above while its actions
 * keep their default keys, named by the keys bound to them otherwise, and
 * gone when none is.
 */
export function shortcuts(keymap: Keymap = DEFAULT_KEYMAP): Shortcut[] {
  return SHORTCUTS.flatMap((shortcut) => {
    const { actions } = shortcut;

    if (
      actions === undefined ||
      [
        ...actions,
        ...(shortcut.after === undefined ? [] : [shortcut.after]),
      ].every((action) => isDefault(keymap, action))
    ) {
      return [shortcut];
    }

    const key = actions
      // Two keys an action at most, so a line still fits a column.
      .flatMap((action) =>
        keysOf(keymap, action)
          .slice(0, shortcut.first ? 1 : 2)
          .map(sequencePanel),
      )
      .filter((name, index, all) => all.indexOf(name) === index)
      .join(' ');

    if (shortcut.also !== undefined) {
      return [
        {
          ...shortcut,
          key: key === '' ? shortcut.also : `${key} or ${shortcut.also}`,
        },
      ];
    }

    if (shortcut.after !== undefined) {
      const [then] = keysOf(keymap, shortcut.after).map(sequencePanel);
      const keys = [
        ...(key === '' ? [] : [key]),
        ...(then === undefined ? [] : [`${shortcut.before ?? ''}${then}`]),
      ];

      return keys.length === 0 ? [] : [{ ...shortcut, key: keys.join(' or ') }];
    }

    if (key === '') {
      return [];
    }

    if (shortcut.before === undefined) {
      return [{ ...shortcut, key }];
    }

    // One key after the prefix, as `\\ + enter ctrl + s` would read as two.
    const [first] = keysOf(keymap, actions[0]!).map(sequencePanel);

    return [{ ...shortcut, key: `${shortcut.before}${first}` }];
  });
}

/** `list` cut into `count` columns read top to bottom, as Claude Code's are. */
export function inColumns<T>(list: readonly T[], count: number): T[][] {
  const height = Math.ceil(list.length / Math.max(1, count));

  if (height === 0) {
    return [];
  }

  const columns: T[][] = [];

  for (let start = 0; start < list.length; start += height) {
    columns.push(list.slice(start, start + height));
  }

  return columns;
}

/** How the panel is laid out: its indent and the gap between columns. */
export const PANEL_PADDING = 2;
export const PANEL_GAP = 3;

/**
 * The panel's lines laid out in `count` columns, a row of the panel each:
 * every column as wide as its widest line, `PANEL_GAP` apart, as rows the
 * panel scrolls by where they do not all fit (CHD-378).
 */
export function panelRows(lines: readonly string[], count: number): string[] {
  const columns = inColumns(lines, count);
  const widths = columns.map((column) =>
    Math.max(...column.map((line) => stringWidth(line))),
  );
  const height = columns[0]?.length ?? 0;

  return Array.from({ length: height }, (_, row) =>
    columns
      .flatMap((column, at) => {
        const line = column[row];

        return line === undefined
          ? []
          : [line + ' '.repeat(widths[at]! - stringWidth(line))];
      })
      .join(' '.repeat(PANEL_GAP))
      .trimEnd(),
  );
}

/**
 * The most columns, up to Claude Code's three, whose lines fit `width` without
 * folding: a folded line has no indent to tell it from the next entry. One
 * column when even that folds, since there is no fewer. The panel is indented
 * on the left alone: its last column may reach the edge, which keeps two
 * columns at 80 with the list's `x` line (CHD-243).
 */
export function columnCount(
  lines: readonly string[],
  width: number,
  most = 3,
): number {
  for (let count = most; count > 1; count--) {
    const columns = inColumns(lines, count);
    const needed =
      PANEL_PADDING +
      PANEL_GAP * (columns.length - 1) +
      columns.reduce(
        (sum, column) =>
          sum + Math.max(...column.map((line) => stringWidth(line))),
        0,
      );

    // Fewer lines than `count` make fewer columns.
    if (needed <= width) {
      return columns.length;
    }
  }

  return 1;
}

/** An entry as the panel prints it. */
export function shortcutLine({ key, does }: Shortcut): string {
  return `${key} ${does}`;
}
