import {
  askedIds,
  betweenAsked,
  heldBack,
  shownPermission,
} from '../dialogs/state.ts';
import { bashCommand, entersBash, typedText } from '../prompt/bash.ts';
import {
  type ChordCommand,
  completion,
  menuRowLimit,
  submitted,
} from '../prompt/commands.ts';
import {
  type History,
  left,
  newer,
  older,
  recalledImages,
  recorded,
} from '../prompt/history.ts';
import { cutPlaceholder, namesImage, pastedText } from '../prompt/images.ts';
import { insertMention, mentionAt } from '../prompt/mentions.ts';
import {
  broken,
  continued,
  type Cursor,
  endOf,
  START,
  typedTakenBack,
} from '../prompt/prompt.ts';
import { mine, restoredDraft } from '../prompt/queue.ts';
import {
  editedQuery,
  emptySearch,
  matched,
  searched,
  searchedOlder,
} from '../prompt/search.ts';
import {
  commandMenu,
  fileFinder,
  pendingMention,
  runningShell,
} from '../prompt/state.ts';
import {
  typedAt,
  type Vim,
  vimCleared,
  vimEscape,
  vimKey,
  vimKeyNames,
  vimReset,
} from '../prompt/vim.ts';
import { keystrokeOf } from '../shortcuts/bindings.ts';
import type { KeyCommand, KeyPress } from '../shortcuts/state.ts';
import type { ScrollStep } from '../transcript/scroll.ts';
import {
  type AppAction,
  type AppState,
  canSend,
  keyAnswer,
  modeAfter,
  selectionShown,
  takesImagePaste,
} from './state.ts';

/**
 * One thing a key, an Enter or an edit in the box has the window do; `App`
 * plays them in order. The ones that reach past the state, to a session, the
 * terminal or a file, are named here and done by the hooks beside `App`.
 */
export type Step =
  | { readonly type: 'dispatch'; readonly action: AppAction }
  /** The box shows `text` with the cursor at `cursor`, afresh. */
  | {
      readonly type: 'show_draft';
      readonly text: string;
      readonly cursor: Cursor;
    }
  | { readonly type: 'history'; readonly history: History }
  /** The splash gives way to the window before the agent is up. */
  | { readonly type: 'leave_splash' }
  /** Vim's keys read in one go see what the one before left. */
  | { readonly type: 'typed'; readonly typed: Typed }
  /** The input heard one of chord's keys and must not type it. */
  | { readonly type: 'chord_key' }
  /** The box is cut back to a whole placeholder and redrawn. */
  | { readonly type: 'cutting' }
  | { readonly type: 'open_session' }
  | { readonly type: 'next_session' }
  | { readonly type: 'previous_session' }
  | { readonly type: 'goto_session'; readonly number: number }
  | { readonly type: 'close_session' }
  | { readonly type: 'attend_session' }
  /** The pick in the list of agents moves `by` rows. */
  | { readonly type: 'move_agent'; readonly by: number }
  /** `x` in the list: the picked child closes, or asks again. */
  | { readonly type: 'close_agent' }
  /** The `❯` in the background view moves `by` rows. */
  | { readonly type: 'move_background'; readonly by: 1 | -1 }
  /** `x` in the background view: the focused item stops. */
  | { readonly type: 'stop_background' }
  /** Enter in the background view: to the call that started the item. */
  | { readonly type: 'go_to_call' }
  | { readonly type: 'interrupt' }
  | { readonly type: 'reject_permission'; readonly id: string }
  /** A scroll key moves the permission request in its box (CHD-246). */
  | { readonly type: 'scroll_request'; readonly step: ScrollStep }
  /** An error in the background view, taller than its room, a page on. */
  | { readonly type: 'scroll_background_hint'; readonly step: ScrollStep }
  | { readonly type: 'set_mode'; readonly mode: string }
  | { readonly type: 'read_commands' }
  | { readonly type: 'send'; readonly text: string }
  /** Enter on a draft naming image files: they are read before it goes. */
  | { readonly type: 'send_with_paths'; readonly text: string }
  | {
      readonly type: 'take_pasted_paths';
      readonly draft: string;
      readonly end: number;
    }
  | {
      readonly type: 'run_command';
      readonly command: ChordCommand;
      readonly args: string;
    }
  | { readonly type: 'run_shell'; readonly command: string }
  | { readonly type: 'stop_shell' }
  | { readonly type: 'open_editor' }
  /** A quiet one says nothing when the clipboard holds no image. */
  | { readonly type: 'paste_image'; readonly quiet?: boolean }
  | { readonly type: 'quit' }
  /** The selection shown, copied. */
  | { readonly type: 'copy_selection' }
  /** The selection cleared, before the key or the paste does its own. */
  | { readonly type: 'clear_selection' };

/** What vim's keys work on, kept ahead of the render. */
export interface Typed {
  readonly vim: Vim | undefined;
  readonly draft: string;
  readonly cursor: Cursor;
}

/** What a key is read against. */
export interface KeyContext {
  /** The session in front, as the window was last drawn. */
  readonly state: AppState;
  readonly history: History;
  /** The window's height, which the lists' pages are cut to. */
  readonly rows: number;
  /** Vim's view of the box, ahead of the render. */
  readonly typed: Typed;
  /** The front session's Enter is still reading typed image paths. */
  readonly submitting: boolean;
  /** The home directory a `~/` path starts in. */
  readonly home: string | undefined;
  /**
   * The list under the prompt is drawn: the session's agents, as it has a
   * child, or the background's summary line, or both.
   */
  readonly agents?: boolean;
  /** The summary line is the list's one stop, with no agents drawn. */
  readonly summaryOnly?: boolean;
  /** The startup splash holds the screen in front of the window. */
  readonly splash?: boolean;
}

/**
 * The commands that set the draft themselves, after a key that would also
 * have typed; any other puts back the draft the key typed into.
 */
const DRAFT_COMMANDS: ReadonlySet<KeyCommand> = new Set<KeyCommand>([
  'toggle_help',
  'submit',
  'newline',
  'history_older',
  'history_newer',
  'complete_command',
  'complete_mention',
  'clear_draft',
  'open_editor',
  'paste_image',
]);

const dispatch = (action: AppAction): Step => ({ type: 'dispatch', action });

const show = (text: string, cursor: Cursor): Step => ({
  type: 'show_draft',
  text,
  cursor,
});

/** The box emptied by what Enter did: vim mode starts again in insert. */
const vimEmptied = (state: AppState): Step[] =>
  state.vim
    ? [dispatch({ type: 'vim_changed', vim: vimReset(state.vim) })]
    : [];

/**
 * A prompt from history into the box, in bash mode when it is a command,
 * with the images it sent.
 */
function recall(history: History, text: string): Step[] {
  const command = bashCommand(text);

  return [
    dispatch({ type: 'bash_mode', on: command !== undefined }),
    dispatch({ type: 'images_added', images: recalledImages(history, text) }),
    show(command ?? text, endOf(command ?? text)),
  ];
}

/**
 * The highlighted file into the draft in place of the `@` being typed. A
 * highlight not moved since the list came, while the mention's own match
 * runs, waits for that match and picks its first file (`awaitedSteps`).
 */
function mention({ state }: KeyContext, enter: boolean): Step[] {
  const finder = fileFinder(state, state.draft, state.cursor);
  // With no list on screen yet, after an empty one, it waits all the same.
  const waiting = pendingMention(state, state.draft, state.cursor);

  if (waiting !== undefined && (finder === undefined || !state.finder.moved)) {
    return [dispatch({ type: 'pick_awaited', mention: waiting, enter })];
  }

  const path = finder?.files[finder.highlighted];

  if (finder && path !== undefined) {
    const next = insertMention(state.draft, state.cursor, finder.mention, path);

    return [show(next.text, next.cursor)];
  }

  return [];
}

/**
 * What an awaited pick does once the state moves: nothing while its match
 * runs; dropped if the draft's mention is no longer the one Enter or Tab
 * was pressed on; else the match's first file in its place, or, with none,
 * Enter sends the draft as typed and Tab does nothing.
 */
export function awaitedSteps(context: KeyContext): Step[] {
  const { state } = context;
  const pick = state.awaitedPick;

  if (pick === undefined) {
    return [];
  }

  const now = mentionAt(state.draft, state.cursor);
  const settled = dispatch({ type: 'pick_settled' });

  if (
    now === undefined ||
    now.query !== pick.mention.query ||
    now.line !== pick.mention.line ||
    now.column !== pick.mention.column ||
    state.finder.dismissed
  ) {
    return [settled];
  }

  const done =
    state.matched?.files === state.files &&
    state.matched?.query === pick.mention.query;

  if (!done) {
    return [];
  }

  const path = state.matched?.matched[0];

  if (path === undefined) {
    return pick.enter
      ? [settled, ...submitSteps(state.draft, context)]
      : [settled];
  }

  const next = insertMention(state.draft, state.cursor, now, path);

  return [settled, show(next.text, next.cursor)];
}

/** ↑ on the first line, or `k` there in normal mode: an older prompt. */
export function olderSteps(context: KeyContext): Step[] {
  const { state, history } = context;
  const { draft, cursor } = state;
  const step =
    !commandMenu(state, draft) &&
    !fileFinder(state, draft, cursor) &&
    older(history, typedText(state.bash, draft));

  // A recalled `/command` is history's, not the list's.
  return step
    ? [
        { type: 'history', history: step.history },
        dispatch({ type: 'menu_dismissed' }),
        ...recall(history, step.text),
      ]
    : [];
}

/**
 * ↓ on the last line, or `j` there in normal mode: a newer one; or, on an
 * empty draft that is not walking history, into the list of the session's
 * agents, where ↓ did nothing before there was one.
 */
export function newerSteps(context: KeyContext): Step[] {
  const { state, history } = context;
  const { draft, cursor } = state;
  const listed =
    !commandMenu(state, draft) && !fileFinder(state, draft, cursor);
  const step = listed && newer(history);

  if (step) {
    return [
      { type: 'history', history: step.history },
      dispatch({ type: 'menu_dismissed' }),
      ...recall(history, step.text),
    ];
  }

  return listed && context.agents && draft === '' && history.index === undefined
    ? [
        dispatch({ type: 'agents_focused', focused: true }),
        ...(context.summaryOnly
          ? [dispatch({ type: 'summary_focused', focused: true })]
          : []),
      ]
    : [];
}

/**
 * Enter on the draft, from the textarea or from vim's normal mode: a file
 * picked, a line continued, a command run, or the prompt sent.
 */
export function submitSteps(value: string, context: KeyContext): Step[] {
  const { state, history, home } = context;
  const { draft, cursor } = state;

  // Enter in the finder picks, as Tab does, rather than sending; a match
  // still running waits to pick, list or none.
  if (
    fileFinder(state, draft, cursor) ||
    pendingMention(state, draft, cursor)
  ) {
    return mention(context, true);
  }

  // In normal mode the cursor is on a character, not after a `\`.
  const next =
    state.vim?.mode === 'normal' ? undefined : continued(value, cursor);

  if (next) {
    return [show(next.text, next.cursor)];
  }

  if (state.bash) {
    // One command at a time: Enter waits for the last to end.
    if (value.trim() === '' || runningShell(state) !== undefined) {
      return [];
    }

    // As in Claude Code, the box is a prompt again once it has run.
    return [
      { type: 'history', history: recorded(history, typedText(true, value)) },
      dispatch({ type: 'bash_mode', on: false }),
      show('', START),
      ...vimEmptied(state),
      { type: 'run_shell', command: value },
    ];
  }

  const menu = commandMenu(state, draft);
  const action = submitted(value, menu?.items[menu.highlighted]);

  if (action.type === 'send' && context.submitting) {
    return [];
  }

  if (action.type === 'complete') {
    return [show(action.text, endOf(action.text))];
  }

  if (action.type === 'chord') {
    return [
      {
        type: 'history',
        history: recorded(
          history,
          [`/${action.name}`, action.args].filter(Boolean).join(' '),
        ),
      },
      show('', START),
      ...vimEmptied(state),
      { type: 'run_command', command: action.name, args: action.args },
    ];
  }

  if (
    state.takesImages === true &&
    canSend(state, action.text) &&
    namesImage(action.text, home)
  ) {
    return [{ type: 'send_with_paths', text: action.text }];
  }

  return [{ type: 'send', text: action.text }];
}

/**
 * Keys in vim's normal mode, each played on what the last one left. Once
 * one goes to insert mode, the rest of the read is typed.
 */
function vimSteps(names: readonly string[], context: KeyContext): Step[] {
  const steps: Step[] = [];
  let typed = context.typed;

  for (const [index, name] of names.entries()) {
    const { vim, draft, cursor } = typed;

    if (vim === undefined) {
      return steps;
    }

    if (vim.mode === 'insert') {
      const rest = names.slice(index).filter((each) => !each.startsWith('<'));
      const next = typedAt(draft, cursor, rest.join(''));

      typed = { vim, draft: next.text, cursor: next.cursor };

      return [
        ...steps,
        { type: 'typed', typed },
        dispatch({ type: 'draft_edited' }),
        show(next.text, next.cursor),
      ];
    }

    const step = vimKey(vim, draft, cursor, name, (before, after) =>
      cutPlaceholder(before, after, context.state.images),
    );

    steps.push(dispatch({ type: 'vim_changed', vim: step.vim }));

    if ('history' in step) {
      typed = { ...typed, vim: step.vim };

      return [
        ...steps,
        { type: 'typed', typed },
        ...(step.history === 'older'
          ? olderSteps(context)
          : newerSteps(context)),
      ];
    }

    typed = { vim: step.vim, draft: step.text, cursor: step.cursor };

    steps.push({ type: 'typed', typed });

    if (step.text !== draft) {
      steps.push(dispatch({ type: 'draft_edited' }));
    }

    steps.push(show(step.text, step.cursor));
  }

  return steps;
}

/** What a key press has the window do, from the state it was pressed in. */
export function keySteps(
  input: string,
  key: KeyPress,
  context: KeyContext,
): Step[] {
  const { state } = context;

  // Esc is the splash's one way into the window early, and the window never
  // hears it; every other key goes to the window behind it, as typed there.
  if (context.splash && key.escape) {
    return [{ type: 'leave_splash' }];
  }

  const { draft, cursor } = state;
  // `read` is the US key in the press's place where only it asks for
  // something; text goes on being typed as `input`.
  const { command, input: read } = keyAnswer(input, key, state, draft, cursor);
  const stroke = keystrokeOf(read, key);
  // A key clears a selection before it does its own, so the textarea never
  // replaces selected text; the copy, a chord's first keys and the
  // transcript's scrolling keep it (CHD-172).
  const steps: Step[] =
    selectionShown(state) &&
    command !== 'copy_selection' &&
    command !== 'key_pending' &&
    !command?.startsWith('scroll_')
      ? [{ type: 'clear_selection' }]
      : [];

  // A key bound to one of chord's actions that would also type, such as
  // `?`, or ctrl+j where it is no line break: the input hears it too, and
  // what it typed is taken back.
  if (typedTakenBack(input, key, state.keys, command !== undefined)) {
    steps.push({ type: 'chord_key' });

    if (command === undefined || !DRAFT_COMMANDS.has(command)) {
      steps.push(show(draft, cursor));
    }
  }

  if (command === 'key_pending' && stroke !== undefined) {
    return [
      ...steps,
      dispatch({
        type: 'keys_pending',
        keys: [...(state.pendingKeys ?? []), stroke],
      }),
    ];
  }

  if (state.pendingKeys !== undefined) {
    steps.push(dispatch({ type: 'keys_pending' }));
  }

  // An armed close is taken back by any key but its own, its chord's
  // first keys aside.
  if (state.closeArmed !== undefined && command !== 'close_session') {
    steps.push(dispatch({ type: 'close_disarmed' }));
  }

  if (state.agentCloseArmed !== undefined && command !== 'close_agent') {
    steps.push(dispatch({ type: 'agent_close_disarmed' }));
  }

  return [...steps, ...commandSteps(command, input, read, key, context)];
}

function commandSteps(
  command: KeyCommand | undefined,
  input: string,
  read: string,
  key: KeyPress,
  context: KeyContext,
): Step[] {
  const { state, history, rows } = context;
  const { draft, cursor } = state;
  const menu = commandMenu(state, draft);
  const finder = fileFinder(state, draft, cursor);
  const menuRows = menuRowLimit(rows);

  switch (command) {
    case 'copy_selection':
      return [{ type: 'copy_selection' }];
    case 'new_session':
      return [{ type: 'open_session' }];
    case 'next_session':
      return [{ type: 'next_session' }];
    case 'previous_session':
      return [{ type: 'previous_session' }];
    case 'goto_session_1':
    case 'goto_session_2':
    case 'goto_session_3':
    case 'goto_session_4':
    case 'goto_session_5':
    case 'goto_session_6':
    case 'goto_session_7':
    case 'goto_session_8':
    case 'goto_session_9':
      return [
        {
          type: 'goto_session',
          number: Number(command.slice('goto_session_'.length)),
        },
      ];
    case 'close_session':
      return [{ type: 'close_session' }];
    case 'attend_session': {
      // The front session's own request between turns is what needs the
      // person first: the keys go into its box (CHD-158).
      const id = heldBack(state) ? betweenAsked(state.transcript) : undefined;
      // From the background view, which it closes first, the keys going
      // where they would from the prompt (CHD-462).
      const closing = state.backgroundView
        ? [
            dispatch({ type: 'background_closed' }),
            dispatch({ type: 'agents_focused', focused: false }),
          ]
        : [];

      return id === undefined
        ? [...closing, { type: 'attend_session' }]
        : [...closing, dispatch({ type: 'request_attended', id })];
    }
    case 'agents_up':
      return [{ type: 'move_agent', by: -1 }];
    case 'agents_down':
      return [{ type: 'move_agent', by: 1 }];
    case 'agents_leave':
      return [dispatch({ type: 'agents_focused', focused: false })];
    case 'close_agent':
      return [{ type: 'close_agent' }];
    case 'open_background':
      return [
        dispatch({
          type: 'background_opened',
          over: askedIds(state.transcript),
        }),
      ];
    case 'background_up':
      return [{ type: 'move_background', by: -1 }];
    case 'background_down':
      return [{ type: 'move_background', by: 1 }];
    case 'background_page_up':
      return [{ type: 'scroll_background_hint', step: 'page_up' }];
    case 'background_page_down':
      return [{ type: 'scroll_background_hint', step: 'page_down' }];
    case 'stop_background':
      return [{ type: 'stop_background' }];
    case 'go_to_call':
      return [{ type: 'go_to_call' }];
    case 'close_background':
      return [dispatch({ type: 'background_closed' })];
    case 'list_sessions':
      return [dispatch({ type: 'sessions_picker_opened' })];
    case 'close_sessions_picker':
      return [dispatch({ type: 'sessions_picker_closed' })];
    case 'interrupt': {
      // The queued prompts back into the box, ahead of what is typed there.
      const text =
        mine(state.queue).length > 0
          ? restoredDraft(state.queue, draft)
          : undefined;

      return [
        ...(text === undefined ? [] : [show(text, endOf(text))]),
        { type: 'interrupt' },
      ];
    }
    case 'reject_permission': {
      const asked = shownPermission(state.transcript);

      return asked ? [{ type: 'reject_permission', id: asked.id }] : [];
    }
    case 'arm_quit':
      return [dispatch({ type: 'quit_armed' })];
    case 'clear_draft':
      return [dispatch({ type: 'draft_cleared' }), show('', START)];
    case 'cycle_mode': {
      const mode = modeAfter(state);

      return mode ? [{ type: 'set_mode', mode }] : [];
    }
    case 'toggle_expanded':
      return [dispatch({ type: 'expanded_toggled' })];
    case 'toggle_help':
      // The input saw the ? too and may have moved its cursor past it.
      return [dispatch({ type: 'help_toggled' }), show(draft, cursor)];
    case 'close_help':
      return [dispatch({ type: 'help_closed' })];
    case 'complete_command': {
      const item = menu?.items[menu.highlighted];

      if (!item) {
        return [];
      }

      const text = completion(item);

      return [show(text, endOf(text))];
    }
    case 'menu_up':
    case 'menu_down':
      return menu
        ? [
            dispatch({
              type: 'menu_moved',
              step: command === 'menu_up' ? -1 : 1,
              count: menu.items.length,
              rows: menuRows,
            }),
          ]
        : [];
    case 'close_menu':
      return [dispatch({ type: 'menu_dismissed' })];
    case 'close_model_picker':
      return [dispatch({ type: 'model_picker_closed' })];
    case 'close_resume_picker':
      return [dispatch({ type: 'resume_picker_closed' })];
    case 'toggle_resume_scope':
      return [dispatch({ type: 'resume_scope_toggled' })];
    case 'close_config_picker':
      return [dispatch({ type: 'config_picker_back' })];
    case 'close_theme_picker':
      return [dispatch({ type: 'theme_picker_closed' })];
    case 'close_mcp':
      return [dispatch({ type: 'mcp_closed' })];
    case 'close_teams_picker':
      return [dispatch({ type: 'teams_picker_closed' })];
    case 'complete_mention':
      return mention(context, false);
    case 'finder_up':
    case 'finder_down':
      return finder
        ? [
            dispatch({
              type: 'finder_moved',
              step: command === 'finder_up' ? -1 : 1,
              count: finder.files.length,
              rows: menuRows,
            }),
          ]
        : [];
    case 'close_finder':
      return [dispatch({ type: 'finder_dismissed' })];
    case 'leave_bash':
      return [dispatch({ type: 'bash_mode', on: false })];
    case 'stop_shell':
      return [{ type: 'stop_shell' }];
    case 'search_history':
      return [dispatch({ type: 'searched', search: emptySearch })];
    case 'search_older':
      return state.search
        ? [
            dispatch({
              type: 'searched',
              search: searchedOlder(state.search, history.prompts),
            }),
          ]
        : [];
    case 'accept_search': {
      const text = state.search && matched(state.search, history.prompts);
      const ended = dispatch({ type: 'searched', search: undefined });

      if (text === undefined) {
        return [ended, show(draft, cursor)];
      }

      // A taken `/command` is the search's, not the list's.
      return [
        ended,
        { type: 'history', history: left(history) },
        dispatch({ type: 'menu_dismissed' }),
        ...recall(history, text),
      ];
    }
    case 'cancel_search':
      // The box showed the match; the draft comes back as it was left.
      return [
        dispatch({ type: 'searched', search: undefined }),
        show(draft, cursor),
      ];
    case 'open_editor':
      return [{ type: 'open_editor' }];
    case 'paste_image':
      return [{ type: 'paste_image' }];
    case 'quit':
      return [{ type: 'quit' }];
    case 'vim_normal': {
      if (state.vim === undefined) {
        return [];
      }

      const left = vimEscape(state.vim, draft, cursor);

      return [
        dispatch({ type: 'vim_changed', vim: left.vim }),
        show(draft, left.cursor),
      ];
    }
    case 'vim_clear':
      return state.vim
        ? [dispatch({ type: 'vim_changed', vim: vimCleared(state.vim) })]
        : [];
    case 'vim_key':
      return vimSteps(vimKeyNames(read, key), context);
    case 'vim_send':
    case 'submit':
      return submitSteps(draft, context);
    case 'newline': {
      const next = broken(draft, cursor);

      return [dispatch({ type: 'draft_edited' }), show(next.text, next.cursor)];
    }
    case 'history_older':
      return olderSteps(context);
    case 'history_newer':
      return newerSteps(context);
    case 'scroll_page_up':
      return [dispatch({ type: 'scrolled', step: 'page_up' })];
    case 'scroll_page_down':
      return [dispatch({ type: 'scrolled', step: 'page_down' })];
    case 'scroll_line_up':
      return [dispatch({ type: 'scrolled', step: 'line_up' })];
    case 'scroll_line_down':
      return [dispatch({ type: 'scrolled', step: 'line_down' })];
    case 'scroll_top':
      return [dispatch({ type: 'scrolled', step: 'top' })];
    case 'scroll_bottom':
      return [dispatch({ type: 'scrolled', step: 'bottom' })];
    case 'request_page_up':
      return [{ type: 'scroll_request', step: 'page_up' }];
    case 'request_page_down':
      return [{ type: 'scroll_request', step: 'page_down' }];
    case 'request_line_up':
      return [{ type: 'scroll_request', step: 'line_up' }];
    case 'request_line_down':
      return [{ type: 'scroll_request', step: 'line_down' }];
    case 'request_top':
      return [{ type: 'scroll_request', step: 'top' }];
    case 'request_bottom':
      return [{ type: 'scroll_request', step: 'bottom' }];
    case undefined: {
      const query = state.search && editedQuery(state.search.query, input, key);

      return state.search && query !== undefined
        ? [
            dispatch({
              type: 'searched',
              search: searched(state.search, history.prompts, query),
            }),
          ]
        : [];
    }
    default:
      return [];
  }
}

/**
 * A bracketed paste with nothing in it: what a terminal sends for cmd+V when
 * the clipboard holds an image and no text (Ghostty does), so it reads the
 * clipboard as ctrl+v does. A terminal that sends nothing, or the text, never
 * gets here. Quiet, as an empty paste of an empty clipboard is no failure the
 * person asked to hear of. Halfway through a chord it is no key of the
 * chord's, and is dropped.
 */
export function emptyPasteSteps(text: string, context: KeyContext): Step[] {
  return text === '' &&
    takesImagePaste(context.state) &&
    context.state.pendingKeys === undefined
    ? [{ type: 'paste_image', quiet: true }]
    : [];
}

/**
 * The box changed under the person's typing: the `!` that enters bash mode,
 * half a placeholder taken whole, a pasted image path read, and the panel
 * put away.
 */
export function changeSteps(value: string, context: KeyContext): Step[] {
  const { state, home } = context;
  const { draft } = state;
  const command = entersBash(state.bash, draft, value);

  // The `!` is the mode's, not the command's.
  if (command !== undefined) {
    return [
      dispatch({ type: 'bash_mode', on: true }),
      show(command, endOf(command)),
    ];
  }

  const cut = cutPlaceholder(draft, value, state.images);

  // Half a placeholder stands for nothing: the whole one goes.
  if (cut !== undefined) {
    return [
      dispatch({ type: 'draft_edited' }),
      { type: 'cutting' },
      show(cut.text, cut.cursor),
    ];
  }

  const steps: Step[] = [
    dispatch({ type: 'draft_set', text: value }),
    dispatch({ type: 'draft_edited' }),
  ];
  const pasted = pastedText(draft, value);

  // A path pasted, as a terminal puts a dropped file in, is the image it
  // names.
  if (
    pasted !== undefined &&
    state.takesImages === true &&
    namesImage(pasted.text, home)
  ) {
    steps.push({ type: 'take_pasted_paths', draft: value, end: pasted.end });
  }

  // Typing puts the panel away, as in Claude Code.
  if (value !== '') {
    steps.push(dispatch({ type: 'help_closed' }));
  }

  // The agent may have advertised its commands since they were read.
  if (value === '/') {
    steps.push({ type: 'read_commands' });
  }

  return steps;
}
