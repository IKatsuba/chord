/**
 * The window's state and what keys do to it, kept out of the components so a
 * test reaches it without a terminal. Each feature keeps its own slice in its
 * own folder's `state.ts`; here they are put together into a session's state
 * and the window's, with what more than one feature writes.
 */
import type { ConversationEvent } from '../../session/conversation.ts';
import {
  type AgentModels,
  modelName,
  sameModels,
} from '../../session/models.ts';
import { type AgentMode, nextMode } from '../../session/modes.ts';
import type { EndedMonitor, RunningMonitor } from '../../session/monitors.ts';
import type { EarlierSession } from '../../session/sessions.ts';
import type { EarlierWindow } from '../../session/windows.ts';
import { addTurn, type Spent } from '../../session/usage.ts';
import type { AgentOption } from '../../session/config.ts';
import { reduceTranscript } from '../../session/transcript/reducer.ts';
import {
  emptyTranscript,
  type Transcript,
} from '../../session/transcript/types.ts';
import {
  type Action,
  type Binding,
  bound,
  gotoAction,
  hintKey,
  keystrokeOf,
  layoutKeys,
  type Sequence,
  startsChord,
  TAB_NUMBERS,
  types,
} from '../shortcuts/bindings.ts';
import {
  capital,
  initialShortcuts,
  type KeyCommand,
  type KeyPress,
  reduceShortcuts,
  type ShortcutsAction,
  type ShortcutsState,
} from '../shortcuts/state.ts';
import {
  type BackgroundAction,
  backgroundShown,
  type BackgroundState,
  initialBackground,
  agentsHaveKeys,
  reduceBackground,
} from '../background/state.ts';
import {
  askedInput,
  asksPerson,
  asksWithKeys,
  heldBack,
  type DialogsAction,
  type DialogsState,
  reduceDialogs,
} from '../dialogs/state.ts';
import { askedPermission } from '../dialogs/permission.ts';
import {
  configPickerShown,
  initialPickers,
  mcpShown,
  modelPickerShown,
  type PickersAction,
  type PickersState,
  reducePickers,
  resumePickerShown,
  sessionsPickerShown,
  teamsPickerShown,
  themePickerShown,
} from '../pickers/state.ts';
import {
  commandMenu,
  fileFinder,
  pendingMention,
  initialPrompt,
  type PromptAction,
  type PromptSession,
  type PromptWindow,
  reducePrompt,
  runningShell,
} from '../prompt/state.ts';
import { type Cursor, endOf, textareaDoes } from '../prompt/prompt.ts';
import { mine, started } from '../prompt/queue.ts';
import type { Search } from '../prompt/search.ts';
import { vimKeyNames, vimTakes, vimTakesCharacter } from '../prompt/vim.ts';
import { backfilled, firstMounted, heldMount } from '../transcript/mount.ts';
import {
  copyable,
  type CopyResult,
  NO_SELECTION,
  pressed,
  released,
  scrolled,
  type Selection,
} from './selection.ts';
import {
  reduceScroll,
  type Scroll,
  type ScrollStep,
} from '../transcript/scroll.ts';
import {
  initialView,
  reduceView,
  type ViewAction,
  type ViewSession,
  type ViewWindow,
} from '../transcript/state.ts';
import {
  type KeptSpend,
  sessionParts,
  type SpendKind,
} from '../transcript/spend.ts';

export type Connection =
  | { readonly status: 'starting' }
  | { readonly status: 'ready' }
  | { readonly status: 'failed'; readonly message: string }
  | { readonly status: 'closing' };

/**
 * What belongs to one session: switching to another swaps all of it, and an
 * event from a session behind changes only its own.
 */
export interface SessionState extends PromptSession, ViewSession, DialogsState {
  readonly connection: Connection;
  /** The agent's id for the session, once it is up. */
  readonly sessionId?: string;
  /** When the session came up, epoch milliseconds. */
  readonly since?: number;
  /**
   * The tokens each turn spent, as the agent answered its prompt; none until
   * the agent reported any.
   */
  readonly spent?: Spent;
  readonly transcript: Transcript;
  /** The agent's models and the one it uses, once it has said. */
  readonly models?: AgentModels;
  /**
   * The model the session started on, as the status line named it then; the
   * header says it, and a later change is the status line's and a note's.
   */
  readonly startedModel?: string;
  /**
   * Set for a session opened again from an earlier one, with when that was
   * last used, its first prompt and an agent another started's name, where
   * chord's record says; the header says so.
   */
  readonly resumed?: {
    readonly lastUsedAt?: number;
    readonly prompt?: string;
    readonly name?: string;
  };
  /**
   * The agent's config options other than its mode and model, as last read;
   * `/config` lists them.
   */
  readonly options: readonly AgentOption[];
  /** The modes the agent offers, in its order; shift+tab walks them. */
  readonly modes: readonly AgentMode[];
  /**
   * The last mode asked for while the agent has yet to answer, so a quick
   * second shift+tab walks on from it. Never drawn: the screen shows the mode
   * the agent reports.
   */
  readonly modeAsked?: string;
  /**
   * The monitors the session's agent started that still run, in start
   * order; the agent list draws them.
   */
  readonly monitors: readonly RunningMonitor[];
  /**
   * Those that ended since the session came up, in the order they ended;
   * the background view draws them until the person's next prompt.
   */
  readonly endedMonitors: readonly EndedMonitor[];
}

/**
 * What belongs to the window and the person, whichever session is in front:
 * how it is drawn, how keys work, and what is open over the prompt box.
 */
export interface WindowState
  extends
    PromptWindow,
    ViewWindow,
    PickersState,
    ShortcutsState,
    BackgroundState {
  /**
   * ctrl+c, or ctrl+d or `/exit` with sessions busy, was pressed once, and
   * which, for the line to name it; a second press of either quits.
   */
  readonly quitArmed: false | 'ctrl+c' | 'ctrl+d';
  /**
   * The agents and tabs closed since the window opened, with what they had
   * spent then, which the window's total still counts (CHD-373, Q59).
   */
  readonly keptSpend?: readonly KeptSpend[];
  /**
   * `ctrl+x k` was pressed once on the busy session with this key; a second
   * press while it holds stops and closes it.
   */
  readonly closeArmed?: number;
  /**
   * The list of the session's agents under the prompt has the keys, rather
   * than the box: ↑ ↓ pick, `x` closes.
   */
  readonly agentsFocus?: true;
  /**
   * The background's summary line, the list's last stop, has the `❯`,
   * which picks no agent; none while the `❯` is on the agent picked.
   */
  readonly summaryFocus?: true;
  /**
   * `x` was pressed once on the busy child with this key; a second press
   * while it holds stops and closes it.
   */
  readonly agentCloseArmed?: number;
  /**
   * What a key on the sessions could not do, such as `ctrl+x a` with no
   * session waiting, said in the status line until the draft is touched,
   * another session comes forward, or an armed close or quit takes its place.
   */
  readonly sessionsNote?: string;
  /**
   * OpenTUI's selection as chord follows it (`selection.ts`): the window's,
   * whichever session is in front; none until a drag.
   */
  readonly selection?: Selection;
  /** What the status line says of the last copy, for a while. */
  readonly copied?: Copied;
  /** The notes said so far, so each note's time is its own. */
  readonly notes?: number;
}

/** A copy's note on the status line. */
export interface Copied {
  /** Counts the notes, so a newer one's time starts again. */
  readonly id: number;
  readonly result: CopyResult;
  /** Release copied it, rather than the copy key. */
  readonly auto: boolean;
}

/** The window as the session in front fills it: what is drawn, and keys read. */
export interface AppState extends WindowState, SessionState {}

export type AppAction =
  | ConversationEvent
  | ViewAction
  | PromptAction
  | PickersAction
  | ShortcutsAction
  | BackgroundAction
  | DialogsAction
  /** ctrl+c, or with `by` ctrl+d or `/exit`, asks for a second press. */
  | { readonly type: 'quit_armed'; readonly by?: 'ctrl+d' }
  | { readonly type: 'quit_disarmed' }
  /** `ctrl+x k` on the busy session `key` asks for a second press. */
  | { readonly type: 'close_armed'; readonly key: number }
  | { readonly type: 'close_disarmed' }
  /** ↓ on an empty prompt moved the keys into the list, or they went back. */
  | { readonly type: 'agents_focused'; readonly focused: boolean }
  /** The `❯` went on to the summary line, or off it. */
  | { readonly type: 'summary_focused'; readonly focused: boolean }
  /** `x` on the busy child `key` asks for a second press. */
  | { readonly type: 'agent_close_armed'; readonly key: number }
  | { readonly type: 'agent_close_disarmed' }
  /**
   * Its read came back: the picker opens on `sessions` and `windows`, every
   * directory's, showing `cwd`'s, or, with none anywhere, `otherwise` is said
   * in the transcript under `/resume`.
   */
  | {
      readonly type: 'resume_listed';
      readonly asked: string;
      readonly sessions: readonly EarlierSession[];
      readonly windows: readonly EarlierWindow[];
      readonly cwd: string;
      readonly otherwise: string;
    }
  /** ctrl+c cleared a draft, which also takes back an earlier first press. */
  | { readonly type: 'draft_cleared' }
  /** ctrl+r opened the search or moved it on; undefined closes it. */
  | { readonly type: 'searched'; readonly search: Search | undefined }
  /** ctrl+g: the window has gone and the editor has the draft. */
  | { readonly type: 'editor_opened' }
  | { readonly type: 'sessions_noted'; readonly message: string }
  /** A step of the wheel, which scrolls as the line keys do. */
  | { readonly type: 'wheeled'; readonly step: 'line_up' | 'line_down' }
  /**
   * The view neared the top of the entries mounted from `from`: the next
   * older chunk mounts.
   */
  | { readonly type: 'backfilled'; readonly from: number }
  /** A press on a selectable text started a drag (`selection.ts`). */
  | { readonly type: 'selection_started' }
  /** The drag ended with `text` selected, none for a click. */
  | { readonly type: 'selection_released'; readonly text: string }
  /** The selection went: OpenTUI's own clear seen, or one of chord's. */
  | { readonly type: 'selection_gone' }
  | { readonly type: 'copy_started' }
  /** The latest copy came back. */
  | {
      readonly type: 'copy_noted';
      readonly result: CopyResult;
      readonly auto: boolean;
    }
  /** The note `id` has been said long enough. */
  | { readonly type: 'copied_gone'; readonly id: number };

export const initialAppState: AppState = {
  connection: { status: 'starting' },
  transcript: emptyTranscript,
  quitArmed: false,
  modes: [],
  options: [],
  monitors: [],
  endedMonitors: [],
  ...initialPrompt,
  ...initialView,
  ...initialPickers,
  ...initialShortcuts,
  ...initialBackground,
};

/**
 * The session quitting or closing leaves to resume, once a prompt or a
 * message has gone to it, as the first of a child reopened through
 * `/resume` was its parent's. One with nothing in it is not worth coming
 * back to.
 */
export function resumableSession(
  state: Pick<SessionState, 'transcript' | 'sessionId'>,
): string | undefined {
  return state.transcript.entries.some(
    (entry) => entry.kind === 'user' || entry.kind === 'message',
  )
    ? state.sessionId
    : undefined;
}

/** How long the first ctrl+c waits for the second, as in Claude Code. */
export const QUIT_WINDOW_MS = 2000;

/** How long the status line says what a copy did (owner, CHD-172). */
export const COPIED_NOTE_MS = 3000;

/**
 * The selection gone, and with it a failed copy's note, which says how to
 * try again on a selection there is no more. One gone mid-drag, which no
 * release will end, lets go of the view as a release would.
 */
function withoutSelection(state: AppState): AppState {
  if (
    state.selection === undefined &&
    state.copied?.result.kind !== 'failed' &&
    !state.scroll.held
  ) {
    return state;
  }

  const { selection, ...rest } = state;
  const { copied, ...uncopied } = rest;
  const left = copied?.result.kind === 'failed' ? uncopied : rest;

  if (!left.scroll.held) {
    return left;
  }

  const freed = reduceApp(left, { type: 'scroll_released' });

  return selection?.kind === 'dragging' &&
    selection.wasFollowing &&
    !selection.moved
    ? reduceApp(freed, { type: 'scrolled', step: 'bottom' })
    : freed;
}

/**
 * `/team`'s `› /team` row stands for its picker while it is open, as the
 * other pickers leave nothing behind, so it goes when the picker does.
 */
function listedGone(before: AppState, after: AppState): AppState {
  if (before.teamsPicker === undefined || after.teamsPicker !== undefined) {
    return after;
  }

  const entries = after.transcript.entries.filter(
    (entry) => entry.kind !== 'team' || entry.shown.kind !== 'listed',
  );

  return { ...after, transcript: { ...after.transcript, entries } };
}

export function reduceApp(state: AppState, action: AppAction): AppState {
  const after = moved(state, reduceStep(state, action), action);
  const mounted = heldMount(
    state,
    after,
    action.type === 'scrolled' && action.step === 'top',
  );

  if (mounted === after.mounted) {
    return after;
  }

  if (mounted === undefined) {
    const { mounted: _, ...rest } = after;

    return rest;
  }

  return { ...after, mounted };
}

/** A scroll while the button is down: the view stays where it was left. */
function moved(before: AppState, after: AppState, action: AppAction) {
  return action.type === 'scrolled' &&
    after.scroll !== before.scroll &&
    after.selection?.kind === 'dragging'
    ? { ...after, selection: scrolled(after.selection) }
    : after;
}

function reduceStep(state: AppState, action: AppAction): AppState {
  // A feature's reducer spreads the state it is handed, so what comes back is
  // the whole window with only that feature's slice changed.
  switch (action.type) {
    case 'queued':
    case 'prompt_capabilities':
    case 'menu_moved':
    case 'menu_dismissed':
    case 'files_listed':
    case 'team_names_listed':
    case 'finder_moved':
    case 'finder_dismissed':
    case 'files_matched':
    case 'match_slow':
    case 'pick_awaited':
    case 'pick_settled':
    case 'draft_set':
    case 'bash_mode':
    case 'context_sent':
    case 'editor_failed':
    case 'paste_failed':
    case 'images_sent':
    case 'vim_toggled':
    case 'vim_changed':
      return reducePrompt(state, action) as AppState;
    case 'model_picker_opened':
    case 'model_picker_closed':
    case 'resume_asked':
    case 'resume_scope_toggled':
    case 'resume_picker_closed':
    case 'sessions_picker_closed':
    case 'config_picker_opened':
    case 'config_option_opened':
    case 'config_picker_back':
    case 'config_picker_closed':
    case 'theme_picker_opened':
    case 'theme_previewed':
    case 'theme_picker_closed':
    case 'theme_chosen':
    case 'mcp_opened':
    case 'mcp_closed':
    case 'teams_picker_opened':
    case 'teams_picker_closed':
    case 'sessions_picker_opened':
      return listedGone(state, reducePickers(state, action) as AppState);
    case 'help_toggled':
    case 'help_closed':
    case 'help_opened':
    case 'keys_pending':
      return reduceShortcuts(state, action) as AppState;
    case 'background_cleared':
    case 'background_opened':
    case 'background_closed':
    case 'background_resized':
    case 'background_focused':
    case 'background_stop_asked':
    case 'background_hinted':
      return reduceBackground(state, action) as AppState;
    case 'expanded_toggled':
      // Rewrapped, its cells would hold other characters.
      return reduceView(withoutSelection(state), action) as AppState;
    case 'scroll_measured':
    case 'scrolled':
    case 'scroll_held':
    case 'scroll_released':
    case 'jump_done':
      return reduceView(state, action) as AppState;
    case 'jumped_to':
      // Its entry mounted, with every one after it.
      return {
        ...(reduceView(state, action) as AppState),
        mounted: Math.min(firstMounted(state), action.entry),
      };
    case 'form_filled':
    case 'questions_answered':
    case 'request_overflowed':
      return reduceDialogs(state, action) as AppState;
    case 'request_attended': {
      // The keys go into the request from wherever they were: the list of
      // agents, a search and the sessions picker let go of them, the draft
      // staying as it is (CHD-158).
      const attended = [
        { type: 'agents_focused', focused: false },
        { type: 'sessions_picker_closed' },
      ].reduce<AppState>(
        (next, step) => reduceApp(next, step as AppAction),
        reduceDialogs(state, action) as AppState,
      );
      const { search: _, ...rest } = attended;

      return rest;
    }
    case 'connected':
      return state.connection.status === 'starting'
        ? {
            ...state,
            connection: { status: 'ready' },
            sessionId: action.sessionId,
            ...(action.at === undefined ? {} : { since: action.at }),
          }
        : state;
    case 'resumed': {
      const { type: _, ...resumed } = action;

      return { ...state, resumed };
    }
    case 'connect_failed':
      return state.connection.status === 'starting'
        ? {
            ...state,
            connection: { status: 'failed', message: action.message },
          }
        : state;
    case 'closing': {
      const {
        search: _,
        resumePicker: __,
        resumeAsked: ___,
        configPicker: ____,
        themePicker: _____,
        closeArmed: ______,
        sessionsPicker: _______,
        agentsFocus: ________,
        agentCloseArmed: _________,
        summaryFocus: __________,
        teamsPicker: ___________,
        backgroundView: ____________,
        ...rest
      } = state;

      return {
        ...rest,
        connection: { status: 'closing' },
        quitArmed: false,
        help: false,
        modelPicker: false,
        mcpPanel: false,
      };
    }
    case 'model': {
      if (sameModels(action.models, state.models)) {
        return state;
      }

      const { models: _, ...rest } = state;
      const name = modelName(action.models);
      const started =
        state.startedModel === undefined && name !== undefined
          ? { ...rest, startedModel: name }
          : rest;

      return action.models === undefined
        ? started
        : { ...started, models: action.models };
    }
    // An earlier session's, which the window keeps where it was let go.
    case 'retired_usage':
    case 'retired_update':
      return state;
    case 'usage': {
      const { type: _, turnId, usage, model: __, ...cost } = action;

      return { ...state, spent: addTurn(state.spent, turnId, usage, cost) };
    }
    case 'options':
      return { ...state, options: action.options };
    case 'resume_listed': {
      // A read that outlived its `/resume`, or a newer one, opens nothing.
      if (state.resumeAsked !== action.asked) {
        return state;
      }

      const { resumeAsked: _, ...rest } = state;
      // A turn may have started while the records were read.
      const said =
        resumeRefusal(rest) ??
        (action.sessions.length === 0 && action.windows.length === 0
          ? action.otherwise
          : undefined);

      // It opens on this directory's, as Claude Code's does, even on none, so
      // that ctrl+a is there to reach the others.
      return said === undefined
        ? {
            ...rest,
            resumePicker: {
              sessions: action.sessions,
              windows: action.windows,
              cwd: action.cwd,
              everywhere: false,
            },
          }
        : reduceApp(rest, {
            type: 'reported',
            turnId: action.asked,
            command: 'resume',
            rows: [{ text: said }],
          });
    }
    case 'modes': {
      const { modes } = action;
      const current = modes?.current;

      return {
        ...state,
        modes: modes?.available ?? [],
        transcript:
          current === undefined || current === state.transcript.mode
            ? state.transcript
            : { ...state.transcript, mode: current },
      };
    }
    case 'agent_closed':
      // For the record; the list reads the tabs.
      return state;
    case 'run_typed':
      // For the record; the command drew it.
      return state;
    case 'monitors':
      return {
        ...state,
        monitors: action.monitors,
        endedMonitors: action.ended,
      };
    case 'cleared':
      // A new session: only what is the window's own stays, and the draft
      // with its images.
      return {
        ...initialAppState,
        // Every tab's, which another tab's clear leaves be.
        backgroundCleared: state.backgroundCleared,
        // What closed agents and let-go sessions spent, which still counts.
        ...(state.keptSpend === undefined
          ? {}
          : { keptSpend: state.keptSpend }),
        expanded: state.expanded,
        theme: state.theme,
        draft: state.draft,
        cursor: state.cursor,
        images: state.images,
        imageCount: state.imageCount,
      };
    case 'images_added': {
      const added = reducePrompt(state, action) as AppState;

      return added === state ? state : withoutFailure(added);
    }
    case 'sessions_noted':
      return { ...state, sessionsNote: action.message };
    case 'commands':
      return {
        ...state,
        transcript: { ...state.transcript, commands: action.commands },
      };
    case 'queue_withdrawn': {
      const taken = mine(state.queue);

      if (taken.length === 0) {
        return state;
      }

      // The prompts go back to the box unsent, and their output is held again
      // to go with them, ahead of anything run since; their images come back
      // with their placeholders. Messages stay queued: they are not the
      // person's.
      const back = taken.flatMap(({ held }) => held ?? []);
      const images = taken.flatMap(({ images }) => images ?? []);
      const withdrawn = {
        ...state,
        queue: state.queue.filter((queued) => queued.from !== undefined),
        held:
          back.length === 0
            ? state.held
            : [...back, ...state.held.filter((id) => !back.includes(id))],
      };

      return reduceApp(withdrawn, { type: 'images_added', images });
    }
    case 'mode_asked':
      return { ...state, modeAsked: action.id };
    case 'mode_answered': {
      if (state.modeAsked !== action.id) {
        return state;
      }

      const { modeAsked: _, ...rest } = state;

      return rest;
    }
    case 'quit_armed': {
      // The warning is drawn where the panel is, and takes the place of a
      // note of the sessions for good: a note back after it is stale.
      const { sessionsNote: _, ...rest } = state;

      return { ...rest, quitArmed: action.by ?? 'ctrl+c', help: false };
    }
    case 'quit_disarmed':
      return { ...state, quitArmed: false };
    case 'close_armed': {
      const { sessionsNote: _, ...rest } = state;

      return { ...rest, closeArmed: action.key, help: false };
    }
    case 'close_disarmed': {
      if (state.closeArmed === undefined) {
        return state;
      }

      const { closeArmed: _, ...rest } = state;

      return rest;
    }
    case 'agents_focused': {
      const {
        agentsFocus: _,
        agentCloseArmed: __,
        summaryFocus: ___,
        ...rest
      } = state;

      // The panel would sit where the list's hint is.
      return action.focused
        ? { ...rest, agentsFocus: true, help: false }
        : rest;
    }
    case 'summary_focused': {
      const { summaryFocus: _, ...rest } = state;

      return action.focused ? { ...rest, summaryFocus: true } : rest;
    }
    case 'agent_close_armed': {
      const { sessionsNote: _, ...rest } = state;

      return { ...rest, agentCloseArmed: action.key };
    }
    case 'agent_close_disarmed': {
      if (state.agentCloseArmed === undefined) {
        return state;
      }

      const { agentCloseArmed: _, ...rest } = state;

      return rest;
    }
    case 'draft_cleared':
      return withoutFailure({ ...state, quitArmed: false });
    case 'draft_edited':
      return withoutFailure(reducePrompt(state, action) as AppState);
    case 'editor_opened':
      // The panel would cover the draft that comes back, and the terminal
      // is handed over with nothing selected.
      return withoutSelection(
        withoutFailure(state.help ? { ...state, help: false } : state),
      );
    case 'searched': {
      if (action.search === undefined) {
        const { search: _, ...rest } = state;

        return rest;
      }

      // The search line takes the panel's row.
      return { ...state, search: action.search, help: false };
    }
    case 'wheeled':
      // As the keys, which mean nothing once the window is closing.
      return state.connection.status === 'closing'
        ? state
        : reduceApp(state, { type: 'scrolled', step: action.step });
    case 'backfilled': {
      const mounted = backfilled(state, action.from);

      return mounted === undefined ? state : { ...state, mounted };
    }
    case 'selection_started': {
      // A new drag replaces the selection there was and any note of its
      // copy, whose time running out must not clear this one.
      const { copied: _, ...left } = withoutSelection(state);

      return reduceApp(
        { ...left, selection: pressed(left.scroll.following) },
        { type: 'scroll_held' },
      );
    }
    case 'selection_released': {
      const { selection, follow } = released(
        state.selection ?? NO_SELECTION,
        action.text,
      );
      // The view is the person's again, followed where the press found it so.
      const free = reduceApp(state, { type: 'scroll_released' });
      const left =
        selection.kind === 'none'
          ? withoutSelection(free)
          : { ...free, selection };

      return follow
        ? reduceApp(left, { type: 'scrolled', step: 'bottom' })
        : left;
    }
    case 'selection_gone':
      return withoutSelection(state);
    case 'copy_started':
      return state.selection === undefined || !copyable(state.selection)
        ? state
        : { ...state, selection: { kind: 'copying' } };
    case 'copy_noted': {
      if (state.selection?.kind !== 'copying') {
        return state;
      }

      const shown: AppState = { ...state, selection: { kind: 'shown' } };
      const copied = {
        id: (state.notes ?? 0) + 1,
        result: action.result,
        auto: action.auto,
      };

      // The copy key's selection has done its work; release's stays
      // after its note goes, until a key or a click clears it, as Claude
      // Code's does, and a failure's for the copy key to try again.
      return action.auto || action.result.kind === 'failed'
        ? { ...shown, copied, notes: copied.id }
        : { ...withoutSelection(state), copied, notes: copied.id };
    }
    case 'copied_gone': {
      if (state.copied?.id !== action.id) {
        return state;
      }

      const { copied: _, ...rest } = state;

      return rest;
    }
    default: {
      const transcript = reduceTranscript(state.transcript, action);

      // The person asked to see it, as they ask to see a reply.
      if (action.type === 'prompt' || action.type === 'reported') {
        return {
          ...state,
          transcript,
          scroll: reduceScroll(state.scroll, {
            type: 'scrolled',
            step: 'bottom',
          }),
          ...(action.type === 'prompt'
            ? { queue: started(state.queue, action.turnId) }
            : {}),
        };
      }

      const next = {
        ...state,
        transcript,
        scroll: withNews(
          state.scroll,
          transcript.entries !== state.transcript.entries,
        ),
        // A run `/clear` let go leaves the transcript as it was.
        ...(action.type === 'shell_ended' && transcript !== state.transcript
          ? { held: [...state.held, action.turnId] }
          : {}),
      };

      // A permission asked while a search is open takes the keys: the search
      // closes rather than share them, and the draft is back in the box.
      if (
        next.search !== undefined &&
        asksPerson(transcript) &&
        !heldBack(next)
      ) {
        const { search: _, ...rest } = next;

        return rest;
      }

      return next;
    }
  }
}

/**
 * Every field of `SessionState`, checked complete by the compiler, so a field
 * added to a session cannot be left with the window by mistake.
 */
const SESSION_FIELDS: Readonly<Record<keyof SessionState, true>> = {
  overflowing: true,
  attended: true,
  connection: true,
  sessionId: true,
  since: true,
  spent: true,
  transcript: true,
  scroll: true,
  mounted: true,
  jump: true,
  models: true,
  startedModel: true,
  resumed: true,
  options: true,
  modes: true,
  modeAsked: true,
  monitors: true,
  endedMonitors: true,
  queue: true,
  bash: true,
  held: true,
  draft: true,
  cursor: true,
  images: true,
  imageCount: true,
  takesImages: true,
  filling: true,
  answering: true,
};

/** A session's own part of the window as `state` fills it. */
export function sessionOf(state: AppState): SessionState {
  return Object.fromEntries(
    Object.entries(state).filter(([field]) => field in SESSION_FIELDS),
  ) as unknown as SessionState;
}

/** The window's own part of `state`, whichever session fills the rest. */
export function windowOf(state: AppState): WindowState {
  return Object.fromEntries(
    Object.entries(state).filter(([field]) => !(field in SESSION_FIELDS)),
  ) as unknown as WindowState;
}

/** A session as it starts: nothing said, nothing typed. */
export const initialSession: SessionState = sessionOf(initialAppState);

/**
 * The window with every open session's state, by its tab's key, and the one
 * in front, whose state fills the window.
 */
export interface WindowedState {
  readonly window: WindowState;
  readonly sessions: Readonly<Record<number, SessionState>>;
  readonly front: number;
  /**
   * The sessions closing, by key, as their last events leave them, with
   * where their spend is kept once the close settles (CHD-373).
   */
  readonly closing?: Readonly<Record<number, Closing>>;
}

/** Where a closing session's spend goes, and what it is under. */
export type KeptPlace = Omit<KeptSpend, 'part' | 'sessionId'> & {
  readonly name: string;
  readonly kind: SpendKind;
  /** The agent a tab's own session is. */
  readonly agent?: string | undefined;
};

/** A closing session, and where what it spent is kept. */
interface Closing {
  readonly session: SessionState;
  readonly place: KeptPlace;
  /** The tab `/clear` or a resume let it go from, whose key goes on. */
  readonly from?: number;
}

/** Whether `session` had turn `turnId`: drawn, or running. */
function hadTurn(session: SessionState, turnId: string): boolean {
  const { transcript } = session;

  return (
    (transcript.turn.status !== 'idle' && transcript.turn.turnId === turnId) ||
    transcript.entries.some(
      (entry) => 'turnId' in entry && entry.turnId === turnId,
    )
  );
}

/** What `session` spent, kept at `place` (CHD-373, Q59). */
export function keptSpend(
  session: SessionState | undefined,
  place: KeptPlace,
): KeptSpend {
  const { name, kind, agent, ...where } = place;
  const [own, ...tasks] = sessionParts(name, kind, session, agent);

  return {
    ...where,
    ...(session?.sessionId === undefined
      ? {}
      : { sessionId: session.sessionId }),
    part: {
      ...own!,
      ended: true,
      ...(tasks.length === 0 ? {} : { parts: tasks }),
    },
  };
}

export type WindowedAction =
  /** An action on the session in front, and on the window. */
  | AppAction
  /** An action on the session `key`, in front or not: its events. */
  | {
      readonly type: 'in_session';
      readonly key: number;
      readonly action: AppAction;
    }
  /** A session opened under `key`, as it starts, and comes to the front. */
  | { readonly type: 'session_opened'; readonly key: number }
  /** An agent or tab closing: what it spent is kept for the window's total (CHD-373). */
  | { readonly type: 'spend_kept'; readonly kept: KeptSpend }
  /**
   * Session `key` is closing: it is held as it is, its last events still
   * taken in, until its close settles (CHD-373).
   */
  | {
      readonly type: 'spend_closing';
      readonly key: number;
      readonly place: KeptPlace;
      /**
       * The tab whose session it is, when that tab goes on with another:
       * `key` is then the closing's own (CHD-373 S3c).
       */
      readonly from?: number;
    }
  /**
   * What a session `/clear` or a resume let go from tab `from` said of a
   * turn of its after: to the one of those that had the turn.
   */
  | {
      readonly type: 'retired_heard';
      readonly from: number;
      readonly event: AppAction & { readonly turnId: string };
    }
  /** An event a closing session reported after it left the window. */
  | {
      readonly type: 'closing_heard';
      readonly key: number;
      readonly event: AppAction;
    }
  /** Session `key`'s close settled: what it spent is kept. */
  | { readonly type: 'spend_closed'; readonly key: number }
  /**
   * A long-lived agent opened under `key`, as it starts; it stays behind
   * until the person picks it.
   */
  | { readonly type: 'agent_opened'; readonly key: number }
  /** The session `key` comes to the front, as it was left. */
  | { readonly type: 'session_shown'; readonly key: number }
  /** The session `key` closed, and `front` is the one in front now. */
  | {
      readonly type: 'session_closed';
      readonly key: number;
      readonly front: number;
    };

/** A window of one session, `key`, as `state` fills it. */
export function windowed(state: AppState, key: number): WindowedState {
  return {
    window: windowOf(state),
    sessions: { [key]: sessionOf(state) },
    front: key,
  };
}

/** The window as the session in front fills it. */
export function frontState(state: WindowedState): AppState {
  return {
    ...state.window,
    ...(state.sessions[state.front] ?? initialSession),
  };
}

export function reduceWindowed(
  state: WindowedState,
  action: WindowedAction,
): WindowedState {
  switch (action.type) {
    case 'session_opened': {
      // It comes forward as a switch does, so a note of the sessions goes,
      // and the selection with what drew it.
      const left = letGo(state);
      // A pick Enter waits on belongs to the draft it was pressed in.
      const {
        sessionsNote: _,
        selection: __,
        awaitedPick: ___,
        ...window
      } = left.window;

      return {
        ...left,
        window,
        sessions: { ...left.sessions, [action.key]: initialSession },
        front: action.key,
      };
    }
    case 'spend_kept':
      return {
        ...state,
        window: {
          ...state.window,
          keptSpend: [...(state.window.keptSpend ?? []), action.kept],
        },
      };
    case 'spend_closing': {
      const session = state.sessions[action.from ?? action.key];

      return session === undefined
        ? state
        : {
            ...state,
            closing: {
              ...state.closing,
              [action.key]: {
                session,
                place: action.place,
                ...(action.from === undefined ? {} : { from: action.from }),
              },
            },
          };
    }
    case 'retired_heard': {
      const key = Object.entries(state.closing ?? {}).find(
        ([, closing]) =>
          closing.from === action.from &&
          hadTurn(closing.session, action.event.turnId),
      )?.[0];

      return key === undefined
        ? state
        : reduceWindowed(state, {
            type: 'closing_heard',
            key: Number(key),
            event: action.event,
          });
    }
    case 'closing_heard': {
      const closing = state.closing?.[action.key];

      return closing === undefined
        ? state
        : {
            ...state,
            closing: {
              ...state.closing,
              [action.key]: {
                ...closing,
                session: sessionOf(
                  reduceApp(
                    { ...state.window, ...closing.session },
                    action.event,
                  ),
                ),
              },
            },
          };
    }
    case 'spend_closed': {
      const { [action.key]: closing, ...rest } = state.closing ?? {};

      return closing === undefined
        ? state
        : {
            ...state,
            closing: rest,
            window: {
              ...state.window,
              keptSpend: [
                ...(state.window.keptSpend ?? []),
                keptSpend(closing.session, closing.place),
              ],
            },
          };
    }
    case 'agent_opened':
      return {
        ...state,
        sessions: { ...state.sessions, [action.key]: initialSession },
      };
    case 'session_shown': {
      if (action.key === state.front || !(action.key in state.sessions)) {
        return state;
      }

      const left = letGo(state);
      const {
        sessionsNote: _,
        selection: __,
        awaitedPick: ___,
        ...window
      } = left.window;

      return { ...left, window, front: action.key };
    }
    case 'session_closed': {
      const { [action.key]: _, ...sessions } = state.sessions;
      const { closeArmed: __, agentCloseArmed: ___, ...window } = state.window;
      const left = { ...state, window, sessions };

      // Shown as switching shows it, so a note of the sessions goes too.
      return action.front === state.front
        ? left
        : reduceWindowed(left, { type: 'session_shown', key: action.front });
    }
    case 'in_session':
      return reduceIn(state, action.key, action.action);
    default:
      return reduceIn(state, state.front, action);
  }
}

/**
 * The session in front let go of its selection before another comes
 * forward: a drag cut short frees the view it held there.
 */
function letGo(state: WindowedState): WindowedState {
  return state.window.selection === undefined
    ? state
    : reduceIn(state, state.front, { type: 'selection_gone' });
}

/**
 * `action` on the session `key`, read with the window as `reduceApp` reads
 * it; the window takes what it changed only from the session in front, so a
 * session behind never closes a picker or a search the person has open.
 */
function reduceIn(
  state: WindowedState,
  key: number,
  action: AppAction,
): WindowedState {
  const session = state.sessions[key];

  if (session === undefined) {
    return state;
  }

  const before = { ...state.window, ...session };
  const after = reduceApp(before, action);

  if (after === before) {
    return state;
  }

  return {
    ...state,
    window: key === state.front ? windowOf(after) : state.window,
    sessions: { ...state.sessions, [key]: sessionOf(after) },
  };
}

/**
 * Sending a prompt brings the view back to the bottom, to see the reply;
 * anything else added to the transcript is news while scrolled back.
 */
function withNews(scroll: Scroll, changed: boolean): Scroll {
  return changed && !scroll.following && !scroll.news
    ? { ...scroll, news: true }
    : scroll;
}

/**
 * The draft was touched: what the status line said of ctrl+g, ctrl+v or the
 * keybindings file goes.
 */
function withoutFailure(state: AppState): AppState {
  if (
    state.editorFailed === undefined &&
    state.pasteFailed === undefined &&
    state.keysFailed === undefined &&
    state.sessionsNote === undefined
  ) {
    return state;
  }

  const {
    editorFailed: _,
    pasteFailed: __,
    keysFailed: ___,
    sessionsNote: ____,
    ...rest
  } = state;

  return rest;
}

/** True while a turn is in flight, whatever it is waiting on. */
export function isBusy(state: AppState): boolean {
  return state.transcript.turn.status !== 'idle';
}

/**
 * Whether Enter would send `draft` now; while a turn runs, it queues behind
 * that turn.
 */
export function canSend(state: AppState, draft: string): boolean {
  return state.connection.status === 'ready' && draft.trim() !== '';
}

/**
 * The permission prompt, a form or a picker is on screen and takes the keys;
 * one asked between turns only once the person has taken them into it.
 */
function listHasKeys(state: AppState): boolean {
  return asksWithKeys(state) || pickerShown(state);
}

/** The form or link on screen, when it has the keys. */
function inputWithKeys(state: AppState) {
  return heldBack(state) ? undefined : askedInput(state.transcript);
}

/** One of chord's pickers or panels is open over the prompt. */
function pickerShown(state: AppState): boolean {
  return (
    sessionsPickerShown(state) ||
    modelPickerShown(state) ||
    resumePickerShown(state) ||
    configPickerShown(state) ||
    themePickerShown(state) ||
    mcpShown(state) ||
    teamsPickerShown(state)
  );
}

/**
 * Whether a pasted image would go into the draft now: ctrl+v's, and an empty
 * bracketed paste's. An image is a prompt's, not a shell command's.
 */
export function takesImagePaste(state: AppState): boolean {
  return state.search === undefined && !state.bash && !listHasKeys(state);
}

export function keyCommand(
  input: string,
  key: KeyPress,
  state: AppState,
  draft: string,
  cursor: Cursor = endOf(draft),
): KeyCommand | undefined {
  return keyAnswer(input, key, state, draft, cursor).command;
}

/** What a press asks for, and the input it was read as to ask it. */
export interface KeyAnswer {
  readonly command: KeyCommand | undefined;
  /**
   * The press's own input, or, where it asks for nothing and the key in its
   * place on the base layout or a US one does, that key's.
   */
  readonly input: string;
}

/**
 * What a press asks for. A press that asks for nothing is read again as the
 * key in the same place on the base layout, which a terminal speaking kitty's
 * keyboard protocol names for any layout, and then as the US key in its place
 * on a Russian one, so that `ctrl+ч` is `ctrl+x` with either; one that asks
 * for something, a key bound as typed included, is never read again, and nor
 * is what types into a form or the search line. Text typed in the prompt
 * stays as typed, as only a bound key is taken back from it.
 */
export function keyAnswer(
  input: string,
  key: KeyPress,
  state: AppState,
  draft: string,
  cursor: Cursor = endOf(draft),
): KeyAnswer {
  const command = pressCommand(input, key, state, draft, cursor, false);
  // Vim takes any key after an operator's `i` or `a`, but only a US one
  // names a text object; after `f` or `r` the key is the character itself.
  const vimObject = command === 'vim_key' && !vimTakesCharacter(state.vim!);

  if (command !== undefined && command !== 'key_dropped' && !vimObject) {
    return { command, input };
  }

  // The terminal's base-layout key first, as it knows where the key is and
  // the table only guesses.
  const readings = [
    ...(key.base === undefined ? [] : [key.base]),
    ...layoutKeys(input),
  ];

  for (const translated of readings) {
    const instead = pressCommand(translated, key, state, draft, cursor, true);

    if (instead !== undefined && instead !== 'key_dropped') {
      return { command: instead, input: translated };
    }
  }

  return { command, input };
}

function pressCommand(
  input: string,
  key: KeyPress,
  state: AppState,
  draft: string,
  cursor: Cursor,
  translated: boolean,
): KeyCommand | undefined {
  if (state.connection.status === 'closing') {
    return undefined;
  }

  const stroke = keystrokeOf(input, key);

  // The copy key is heard before every context, a form's and the search
  // line's typing included, as a chord begun on it is (CHD-172).
  if (stroke !== undefined && selectionShown(state)) {
    const keys = [...(state.pendingKeys ?? []), stroke];
    const copying = state.keys.bindings
      .filter(({ action }) => action === 'selection:copy')
      .map((binding) => binding.keys);

    if (bound(state.keys, 'selection:copy', keys)) {
      return 'copy_selection';
    }

    if (startsChord(copying, keys)) {
      return 'key_pending';
    }
  }

  // A form and the search line take what types, whatever is bound to it, as
  // Claude Code's text fields do; a chord already begun still finishes. A
  // form waits while the list of agents has the keys, and while the
  // background view stands over it (CHD-462).
  const typed =
    stroke !== undefined &&
    state.pendingKeys === undefined &&
    types(stroke) &&
    ((inputWithKeys(state) !== undefined &&
      !agentsHaveKeys(state) &&
      !backgroundShown(state)) ||
      state.search !== undefined);
  const pressed =
    stroke === undefined || typed
      ? undefined
      : [...(state.pendingKeys ?? []), stroke];
  const command = boundCommand(
    input,
    key,
    state,
    draft,
    cursor,
    pressed,
    translated,
  );

  if (command !== undefined) {
    return command;
  }

  if (
    pressed !== undefined &&
    startsChord(liveChords(state, draft, cursor), pressed)
  ) {
    return 'key_pending';
  }

  return state.pendingKeys === undefined ? undefined : 'key_dropped';
}

/** A key press that is no key in particular, to ask what a sequence does. */
const NO_KEY: KeyPress = { ctrl: false, escape: false };

/**
 * The chords whose action would run now, the only ones waited for: a chord
 * bound in a context not on screen, such as a closed panel, or to an action
 * the state does not allow, such as the editor while the search line is
 * open, would take the keys and do nothing with them.
 */
export function liveChords(
  state: AppState,
  draft: string,
  cursor: Cursor = endOf(draft),
): Sequence[] {
  return liveBindings(state, draft, cursor).map(({ keys }) => keys);
}

function liveBindings(
  state: AppState,
  draft: string,
  cursor: Cursor,
): Binding[] {
  return state.keys.bindings.filter(
    ({ keys }) =>
      keys.length > 1 &&
      boundCommand('', NO_KEY, state, draft, cursor, keys, false) !== undefined,
  );
}

/**
 * The chords that would run now and start with the keys held, for the
 * leader line to name what can follow; none while no chord is begun.
 */
export function pendingBindings(
  state: AppState,
  draft: string,
  cursor: Cursor = endOf(draft),
): Binding[] {
  const held = state.pendingKeys;

  if (held === undefined) {
    return [];
  }

  return liveBindings(state, draft, cursor).filter(({ keys }) =>
    startsChord([keys], held),
  );
}

/** Whether a selection is on screen, being copied or not. */
export function selectionShown(state: AppState): boolean {
  return (
    state.selection?.kind === 'shown' || state.selection?.kind === 'copying'
  );
}

/** What `pressed`, the keys of a chord so far and this one, asks for. */
function boundCommand(
  input: string,
  key: KeyPress,
  state: AppState,
  draft: string,
  cursor: Cursor,
  pressed: Sequence | undefined,
  translated: boolean,
): KeyCommand | undefined {
  const on = (action: Action) => bound(state.keys, action, pressed);
  // The textarea hears the press as it came, so a key read again as the US
  // one, ctrl+о as ctrl+j, is chord's to act on even where it is the
  // textarea's own.
  const textareaDid = (action: Action) =>
    !translated && textareaDoes(pressed, action);

  // The background view is modal: it takes every key, the window's
  // sessions' and the pickers' too, which wait until Esc closes it.
  if (backgroundShown(state)) {
    return backgroundCommand(input, key, state, on);
  }

  const session = sessionCommand(on);

  // A selection shown takes its copy key first, and ctrl+c with no chord
  // begun, in front of every context: the highlight says what ctrl+c does.
  if (selectionShown(state)) {
    if (
      on('selection:copy') ||
      (state.pendingKeys === undefined && key.ctrl && input === 'c')
    ) {
      return 'copy_selection';
    }
  }

  // The window's sessions come first, over a form, a permission and every
  // list, so that a digit after the leader never picks a choice.
  if (session !== undefined) {
    return session;
  }

  // The sessions picker stands in front of a form or a permission, so their
  // keys wait behind it; only the window's own get past.
  if (sessionsPickerShown(state)) {
    if (on('select:cancel')) {
      return 'close_sessions_picker';
    }

    if (key.ctrl && input === 'c') {
      return draft !== ''
        ? 'clear_draft'
        : state.quitArmed
          ? 'quit'
          : 'arm_quit';
    }

    if (key.ctrl && input === 'd' && draft === '') {
      return 'quit';
    }

    if (on('app:toggleTranscript')) {
      return 'toggle_expanded';
    }

    const step = scrollStep(on);

    return step && `scroll_${step}`;
  }

  // The list of agents takes ↑ ↓, j k, Enter, Esc and `x`; every other
  // letter does nothing, so a stray key never lands in a child's prompt. A
  // permission or form of the agent picked waits until Enter or Esc goes
  // back to it, so moving through the list never answers one.
  if (agentsHaveKeys(state) && !pickerShown(state)) {
    return agentsCommand(input, key, state, on);
  }

  // A form takes every key but these: ctrl+c stops the turn, which takes the
  // form with it, ctrl+o, and the transcript's scrolling keys. Esc is the
  // form's, as it answers `cancel`.
  if (inputWithKeys(state) !== undefined) {
    if (key.ctrl && input === 'c') {
      return 'interrupt';
    }

    if (on('app:toggleTranscript')) {
      return 'toggle_expanded';
    }

    // home and end move in the field being typed in, not the transcript.
    const step = key.home || key.end ? undefined : scrollStep(on);

    return step && `scroll_${step}`;
  }

  // The search line takes typing, so only these keys and the window's below
  // mean anything while it is open.
  if (state.search !== undefined) {
    if (on('historySearch:next')) {
      return 'search_older';
    }

    if (on('historySearch:cancel') || (key.ctrl && input === 'c')) {
      return 'cancel_search';
    }

    if (on('historySearch:accept')) {
      return 'accept_search';
    }
  } else if (on('history:search') && !listHasKeys(state)) {
    return 'search_history';
  }

  // The draft is the prompt box's; a picker or a permission has the keys, and
  // the search shows a match in its place. During a turn the draft is the
  // next prompt, so it opens then too.
  if (
    on('chat:externalEditor') &&
    state.search === undefined &&
    !listHasKeys(state)
  ) {
    return 'open_editor';
  }

  if (on('chat:imagePaste') && takesImagePaste(state)) {
    return 'paste_image';
  }

  if (key.ctrl && input === 'c') {
    if (draft !== '') {
      return 'clear_draft';
    }

    return state.quitArmed ? 'quit' : 'arm_quit';
  }

  // On a draft ctrl+d does nothing, rather than quit with the draft unsent.
  if (key.ctrl && input === 'd' && draft === '') {
    return 'quit';
  }

  if (on('app:toggleTranscript')) {
    return 'toggle_expanded';
  }

  if (on('chat:cycleMode') && modeAfter(state) !== undefined) {
    return 'cycle_mode';
  }

  const step = scrollStep(on);

  // A permission request taller than its box takes the view's keys, as the
  // person reads it before answering (CHD-246).
  if (step) {
    return state.overflowing !== undefined &&
      !heldBack(state) &&
      state.overflowing === askedPermission(state.transcript.turn)?.id
      ? `request_${step}`
      : `scroll_${step}`;
  }

  const finder = fileFinder(state, draft, cursor);

  if (
    (finder || pendingMention(state, draft, cursor)) &&
    on('autocomplete:accept')
  ) {
    return 'complete_mention';
  }

  if (finder && on('autocomplete:previous')) {
    return 'finder_up';
  }

  if (finder && on('autocomplete:next')) {
    return 'finder_down';
  }

  const menu = !finder && commandMenu(state, draft);

  if (menu && on('autocomplete:accept')) {
    return 'complete_command';
  }

  if (menu && on('autocomplete:previous')) {
    return 'menu_up';
  }

  if (menu && on('autocomplete:next')) {
    return 'menu_down';
  }

  if (state.search !== undefined) {
    return undefined;
  }

  if (key.backspace && state.bash && draft === '') {
    return 'leave_bash';
  }

  // Anywhere but an empty prompt, ? is text.
  if (on('help:toggle') && draft === '') {
    return 'toggle_help';
  }

  if (on('help:dismiss') && state.help) {
    return 'close_help';
  }

  if (on('autocomplete:dismiss') && finder) {
    return 'close_finder';
  }

  if (on('autocomplete:dismiss') && menu) {
    return 'close_menu';
  }

  if (
    on('confirm:no') &&
    state.transcript.turn.status === 'awaiting_permission' &&
    !heldBack(state)
  ) {
    return 'reject_permission';
  }

  const closing = on('select:cancel');

  if (closing && modelPickerShown(state)) {
    return 'close_model_picker';
  }

  if (closing && resumePickerShown(state)) {
    return 'close_resume_picker';
  }

  if (on('select:toggleScope') && resumePickerShown(state)) {
    return 'toggle_resume_scope';
  }

  if (closing && configPickerShown(state)) {
    return 'close_config_picker';
  }

  if (closing && themePickerShown(state)) {
    return 'close_theme_picker';
  }

  if (closing && mcpShown(state)) {
    return 'close_mcp';
  }

  if (closing && teamsPickerShown(state)) {
    return 'close_teams_picker';
  }

  // Vim's keys come after every list's Esc, so Esc still closes them, and
  // before the turn's: in insert mode Esc goes to normal, and only there a
  // second one stops a command or the turn, as in Claude Code.
  const vim = vimCommand(input, key, state, on);

  if (vim !== undefined) {
    return vim;
  }

  const typing = !listHasKeys(state) && state.vim?.mode !== 'normal';

  // The textarea sends, breaks the line and walks history on its own keys;
  // these are the keys a file gave those actions instead.
  if (typing && on('chat:submit') && !textareaDid('chat:submit')) {
    return 'submit';
  }

  if (typing && on('chat:newline') && !textareaDid('chat:newline')) {
    return 'newline';
  }

  if (
    !listHasKeys(state) &&
    on('history:previous') &&
    !textareaDid('history:previous')
  ) {
    return 'history_older';
  }

  if (
    !listHasKeys(state) &&
    on('history:next') &&
    !textareaDid('history:next')
  ) {
    return 'history_newer';
  }

  // Before the turn's interrupt: the command is the nearer thing to stop, and
  // a second Esc still reaches the turn.
  if (on('chat:cancel') && runningShell(state) !== undefined) {
    return 'stop_shell';
  }

  if (on('chat:cancel') && isBusy(state)) {
    return 'interrupt';
  }

  return undefined;
}

/** What a key means while the background view is open. */
function backgroundCommand(
  input: string,
  key: KeyPress,
  state: AppState,
  on: (action: Action) => boolean,
): KeyCommand | undefined {
  if (key.ctrl && input === 'c') {
    return state.quitArmed ? 'quit' : 'arm_quit';
  }

  if (key.ctrl && input === 'd') {
    return 'quit';
  }

  if (on('agents:close')) {
    return 'stop_background';
  }

  // The one chord it begins: what the status line names to answer a
  // request held between turns, which closes it on the way (CHD-462).
  if (on('session:attention')) {
    return 'attend_session';
  }

  // shift+↑ ↓ scroll the transcript elsewhere; the view has none.
  if (
    (key.upArrow && !key.shift) ||
    (input === 'k' && !key.ctrl && !key.meta)
  ) {
    return 'background_up';
  }

  if (
    (key.downArrow && !key.shift) ||
    (input === 'j' && !key.ctrl && !key.meta)
  ) {
    return 'background_down';
  }

  if (key.return) {
    return 'go_to_call';
  }

  return on('select:cancel') ? 'close_background' : undefined;
}

/** What a key means while the list of the session's agents has the keys. */
function agentsCommand(
  input: string,
  key: KeyPress,
  state: AppState,
  on: (action: Action) => boolean,
): KeyCommand | undefined {
  if (key.ctrl && input === 'c') {
    return state.quitArmed ? 'quit' : 'arm_quit';
  }

  if (key.ctrl && input === 'd') {
    return 'quit';
  }

  if (on('app:toggleTranscript')) {
    return 'toggle_expanded';
  }

  const step = scrollStep(on);

  if (step) {
    return `scroll_${step}`;
  }

  // The summary line is no item: `x` there stops nothing.
  if (on('agents:close')) {
    return state.summaryFocus ? undefined : 'close_agent';
  }

  if (key.upArrow || (input === 'k' && !key.ctrl && !key.meta)) {
    return 'agents_up';
  }

  if (key.downArrow || (input === 'j' && !key.ctrl && !key.meta)) {
    return 'agents_down';
  }

  if (key.return && state.summaryFocus) {
    return 'open_background';
  }

  return key.return || key.escape ? 'agents_leave' : undefined;
}

/** What a key bound to a `session:` action asks for. */
function sessionCommand(
  on: (action: Action) => boolean,
): KeyCommand | undefined {
  if (on('session:new')) {
    return 'new_session';
  }

  if (on('session:next')) {
    return 'next_session';
  }

  if (on('session:previous')) {
    return 'previous_session';
  }

  if (on('session:list')) {
    return 'list_sessions';
  }

  if (on('session:attention')) {
    return 'attend_session';
  }

  if (on('session:close')) {
    return 'close_session';
  }

  const n = TAB_NUMBERS.find((n) => on(gotoAction(n)));

  return n && `goto_session_${n}`;
}

/** What a key means to vim mode, while it is on and the box has the keys. */
function vimCommand(
  input: string,
  key: KeyPress,
  state: AppState,
  on: (action: Action) => boolean,
): KeyCommand | undefined {
  const { vim } = state;

  if (vim === undefined || listHasKeys(state)) {
    return undefined;
  }

  if (vim.mode === 'insert') {
    return key.escape ? 'vim_normal' : undefined;
  }

  if (key.escape) {
    return vim.pending.length === 0 ? undefined : 'vim_clear';
  }

  if (on('chat:submit')) {
    return 'vim_send';
  }

  const [first] = vimKeyNames(input, key);

  return first !== undefined && vimTakes(vim, first) ? 'vim_key' : undefined;
}

/**
 * Why `/resume` does not open now, as a sentence for the transcript; none
 * when it may. A turn running would be cut off by the session going, so it
 * is left to end or be interrupted first, by the person, not by `/resume`.
 */
export function resumeRefusal(state: AppState): string | undefined {
  if (isBusy(state)) {
    const key = hintKey(state.keys, 'chat:cancel');

    return key === undefined
      ? 'A turn is running. Wait for it to end, then /resume.'
      : `A turn is running. Wait for it to end, or press ${capital(key)} ` +
          'to interrupt it, then /resume.';
  }

  return undefined;
}

/**
 * The mode shift+tab asks for: the one after the mode the agent last
 * reported, or after the one still being asked for, in the agent's order.
 * Undefined until the session is up and the agent offers two modes or more.
 */
export function modeAfter(state: AppState): string | undefined {
  return state.connection.status === 'ready'
    ? nextMode(state.modes, state.modeAsked ?? state.transcript.mode)
    : undefined;
}

/** The view's keys, as the keymap binds them. */
function scrollStep(on: (action: Action) => boolean): ScrollStep | undefined {
  return on('scroll:pageUp')
    ? 'page_up'
    : on('scroll:pageDown')
      ? 'page_down'
      : on('scroll:top')
        ? 'top'
        : on('scroll:bottom')
          ? 'bottom'
          : on('scroll:lineUp')
            ? 'line_up'
            : on('scroll:lineDown')
              ? 'line_down'
              : undefined;
}
