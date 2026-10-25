/**
 * The prompt's part of the state: the draft, its cursor and its images, bash
 * mode and the output it holds, the prompts queued, and, the window's, the
 * slash command list, the `@` file finder, ctrl+r's search and vim mode.
 */
import { shellContext } from '../../session/context.ts';
import type { ConversationEvent } from '../../session/conversation.ts';
import type { ShellRun, Transcript } from '../../session/transcript/types.ts';
import { asksWithKeys } from '../dialogs/state.ts';
import type { Keymap } from '../shortcuts/bindings.ts';
import {
  agentQuery,
  type CommandItem,
  commandItems,
  commandQuery,
  matchAgents,
  matchCommands,
  moveHighlight,
  teamItems,
  teamQuery,
  visibleRange,
} from './commands.ts';
import { imagesIn, type PastedImage } from './images.ts';
import { firstFiles, type Mention, mentionAt } from './mentions.ts';
import { type Cursor, START } from './prompt.ts';
import type { Queued } from './queue.ts';
import type { Search } from './search.ts';
import { startingVim, type Vim } from './vim.ts';

/**
 * A draft ↓ set aside (U10, Q183): the whole of it as it stood, for ↑ to put
 * back as it was.
 */
export interface KeptDraft {
  readonly text: string;
  readonly cursor: Cursor;
  /** The images its placeholders name. */
  readonly images: readonly PastedImage[];
  readonly bash: boolean;
}

/** The session's part of the prompt: switching sessions swaps all of it. */
export interface PromptSession {
  /** Prompts sent while a turn ran, oldest first, until each one's starts. */
  readonly queue: readonly Queued[];
  /** `!` on an empty prompt: the box takes a shell command, not a prompt. */
  readonly bash: boolean;
  /**
   * The finished shell runs, by id, whose output goes to the agent with the
   * next prompt.
   */
  readonly held: readonly string[];
  /** What the prompt box holds, kept across `/clear`. */
  readonly draft: string;
  /**
   * The drafts ↓ set aside, oldest first, which ↑ walks before the history
   * of prompts sent; the agent's own, so another agent's ↑ never brings one,
   * and kept across sending and `/clear` (Q191).
   */
  readonly kept?: readonly KeptDraft[];
  /** Where the box's cursor is in the draft. */
  readonly cursor: Cursor;
  /**
   * The images the draft may hold, by number; a prompt sends the ones whose
   * placeholders are in its text. Kept across `/clear`, as the draft is.
   */
  readonly images: readonly PastedImage[];
  /**
   * The highest image number given out, so a pasted image never takes the
   * number of one a queued or earlier prompt holds.
   */
  readonly imageCount: number;
  /**
   * Whether the agent takes images in a prompt, as its `promptCapabilities`
   * say; unknown until the session is up.
   */
  readonly takesImages?: boolean;
}

/** The window's part of the prompt, whichever session is in front. */
export interface PromptWindow {
  /** The slash command list's highlight and scroll, and whether Esc shut it. */
  readonly menu: MenuState;
  /** The agents `/new` offers by name, as the window can start them. */
  readonly agents?: readonly CommandItem[];
  /**
   * The working directory's files as `@` last found them; none until it has
   * looked.
   */
  readonly files?: readonly string[];
  /** The `@` file finder's highlight and scroll, and whether Esc shut it. */
  readonly finder: MenuState & {
    /** ↑ or ↓ moved the highlight since the list on screen arrived. */
    readonly moved?: true;
  };
  /**
   * The last match that came back for the files walked: the query it was
   * for and the files it found. It stays on screen while the next one runs.
   */
  readonly matched?: {
    readonly files: readonly string[];
    readonly query: string;
    readonly matched: readonly string[];
  };
  /** The query whose match has run longer than `SLOW_MATCH_MS`. */
  readonly matchSlow?: string;
  /**
   * Enter or Tab on an unmoved highlight while a match ran: the mention it
   * was pressed on, picked from once that match comes back, if the draft's
   * mention is still the same, and whether it was Enter.
   */
  readonly awaitedPick?: { readonly mention: Mention; readonly enter: boolean };
  /**
   * The names `/team show`, `edit`, `run` and `stop` offer, as they were
   * read when the draft last came to one; none until then.
   */
  readonly teamNames?: TeamNames;
  /**
   * ctrl+r: the reverse history search, while it is open. The draft stays as
   * it was underneath, for Esc to give back.
   */
  readonly search?: Search;
  /**
   * ctrl+g's editor did not end well, said in the status line until the
   * draft is touched again.
   */
  readonly editorFailed?: string;
  /**
   * ctrl+v or a pasted path found no image to take, said in the status line
   * until the draft is touched again.
   */
  readonly pasteFailed?: string;
  /**
   * `pasteFailed` says the agent has not started yet, which stops being
   * true once it has started, or failed to (CHD-490).
   */
  readonly pasteFailedUntilStarted?: true;
  /**
   * `/vim`: the prompt box edits as vim does, in insert or normal mode;
   * absent while it is off.
   */
  readonly vim?: Vim;
}

export interface PromptState extends PromptSession, PromptWindow {}

/** The saved teams by name, a broken file marked, and the runs open. */
export interface TeamNames {
  readonly teams: readonly {
    readonly name: string;
    readonly broken: boolean;
  }[];
  readonly runs: readonly string[];
}

export interface MenuState {
  /** Index into the items the draft matches. */
  readonly highlighted: number;
  /** The first item shown, when there are more than fit. */
  readonly top: number;
  /** Esc put the list away; the next edit to the draft brings it back. */
  readonly dismissed: boolean;
}

const initialMenu: MenuState = { highlighted: 0, top: 0, dismissed: false };

export type PromptAction =
  | Extract<ConversationEvent, { type: 'queued' | 'prompt_capabilities' }>
  /**
   * ↑ or ↓ in the slash command list; `count` is how many items the draft
   * matches and `rows` how many the list shows.
   */
  | {
      readonly type: 'menu_moved';
      readonly step: 1 | -1;
      readonly count: number;
      readonly rows: number;
    }
  /** Esc, or a recalled prompt, puts the list away until the next edit. */
  | { readonly type: 'menu_dismissed' }
  /** The working directory's files, walked as an `@` opened the finder. */
  | { readonly type: 'files_listed'; readonly files: readonly string[] }
  /** The team files and runs, read as the draft came to a team's name. */
  | { readonly type: 'team_names_listed'; readonly names: TeamNames }
  /** ↑ or ↓ in the `@` file finder, counted as `menu_moved` counts. */
  | {
      readonly type: 'finder_moved';
      readonly step: 1 | -1;
      readonly count: number;
      readonly rows: number;
    }
  /** Esc puts the finder away, keeping the text, until the next edit. */
  | { readonly type: 'finder_dismissed' }
  /** A match came back, for `query` over `files`, still the current one. */
  | {
      readonly type: 'files_matched';
      readonly files: readonly string[];
      readonly query: string;
      readonly matched: readonly string[];
    }
  /** The match for `query` has run longer than `SLOW_MATCH_MS`. */
  | { readonly type: 'match_slow'; readonly query: string }
  /** Enter or Tab waits for the match running, to pick its first file. */
  | {
      readonly type: 'pick_awaited';
      readonly mention: Mention;
      readonly enter: boolean;
    }
  /** The awaited pick was made, or the mention changed under it. */
  | { readonly type: 'pick_settled' }
  /** The draft was typed in; the list starts again from its first item. */
  | { readonly type: 'draft_edited' }
  /**
   * The box holds `text`, or has its cursor at `cursor`, or both; what it
   * means to the lists is `draft_edited`'s.
   */
  | {
      readonly type: 'draft_set';
      readonly text?: string;
      readonly cursor?: Cursor;
    }
  /** `!` on an empty prompt, or a recalled command, turns bash mode on. */
  | { readonly type: 'bash_mode'; readonly on: boolean }
  /** ↓ set the draft aside: it is kept whole, and the box empties. */
  | { readonly type: 'draft_kept' }
  /** Kept draft `index` left the stack: sent, or emptied while shown. */
  | { readonly type: 'kept_taken'; readonly index: number }
  /**
   * The walk moves off kept draft `index`, shown: it keeps the box as it
   * stands, edited or not, in its place on the stack (Q195).
   */
  | { readonly type: 'kept_edited'; readonly index: number }
  /** A prompt took the output of the `held` runs to the agent. */
  | { readonly type: 'context_sent'; readonly held: readonly string[] }
  /** The editor exited with an error, and the draft is as it was. */
  | { readonly type: 'editor_failed'; readonly message: string }
  /**
   * Images went into the draft, pasted or read from paths, or came back
   * with a recalled prompt.
   */
  | { readonly type: 'images_added'; readonly images: readonly PastedImage[] }
  /** ctrl+v found no image to take, or the agent takes none. */
  | {
      readonly type: 'paste_failed';
      readonly message: string;
      /** It says the agent has not started yet. */
      readonly untilStarted?: true;
    }
  /**
   * A prompt took the draft's images; the box starts again without them,
   * but for those `keeping`, a draft typed while the prompt waited, holds.
   */
  | { readonly type: 'images_sent'; readonly keeping?: string }
  /** `/vim` turned vim mode on, in insert mode, or off. */
  | { readonly type: 'vim_toggled'; readonly on: boolean }
  /** A key in vim mode moved it on: its mode, a command half typed, `u`'s past. */
  | { readonly type: 'vim_changed'; readonly vim: Vim };

export const initialPrompt: PromptState = {
  menu: initialMenu,
  finder: initialMenu,
  queue: [],
  bash: false,
  held: [],
  draft: '',
  cursor: START,
  images: [],
  imageCount: 0,
};

export function reducePrompt(
  state: PromptState,
  action: PromptAction,
): PromptState {
  switch (action.type) {
    case 'prompt_capabilities':
      return state.takesImages === action.image
        ? state
        : { ...state, takesImages: action.image };
    case 'images_added': {
      if (action.images.length === 0) {
        return state;
      }

      const ids = action.images.map(({ id }) => id);

      return {
        ...state,
        images: [
          ...state.images.filter(({ id }) => !ids.includes(id)),
          ...action.images,
        ],
        imageCount: Math.max(state.imageCount, ...ids),
      };
    }
    case 'paste_failed': {
      const { pasteFailedUntilStarted: _, ...rest } = state;

      return {
        ...rest,
        pasteFailed: action.message,
        ...(action.untilStarted ? { pasteFailedUntilStarted: true } : {}),
      };
    }
    case 'images_sent': {
      const kept = imagesIn(action.keeping ?? '', state.images);

      return kept.length === state.images.length
        ? state
        : { ...state, images: kept };
    }
    case 'vim_toggled': {
      if (!action.on) {
        const { vim: _, ...rest } = state;

        return rest;
      }

      return { ...state, vim: state.vim ?? startingVim };
    }
    case 'vim_changed':
      return state.vim === undefined ? state : { ...state, vim: action.vim };
    case 'queued': {
      // Not the person's: nothing of the box went with it. A monitor's
      // message is reported again in its place as batches join it.
      if (action.from !== undefined) {
        const queued = {
          turnId: action.turnId,
          text: action.text,
          from: action.from,
          ...(action.afterAnswer ? { afterAnswer: action.afterAnswer } : {}),
          ...(action.afterCalls ? { afterCalls: action.afterCalls } : {}),
        };

        return {
          ...state,
          queue: state.queue.some((item) => item.turnId === action.turnId)
            ? state.queue.map((item) =>
                item.turnId === action.turnId ? queued : item,
              )
            : [...state.queue, queued],
        };
      }

      // Told again once what it waited for changed: only that changes.
      if (state.queue.some((item) => item.turnId === action.turnId)) {
        return {
          ...state,
          queue: state.queue.map((item) => {
            if (item.turnId !== action.turnId) {
              return item;
            }

            const { afterAnswer: _, afterCalls: __, ...rest } = item;

            return {
              ...rest,
              ...(action.afterAnswer ? { afterAnswer: true as const } : {}),
              ...(action.afterCalls ? { afterCalls: true as const } : {}),
            };
          }),
        };
      }

      // Queued just before its `context_sent` and `images_sent`, so what is
      // held and the draft's images went with it.
      const images = imagesIn(action.text, state.images);

      return {
        ...state,
        queue: [
          ...state.queue,
          {
            turnId: action.turnId,
            text: action.text,
            ...(state.held.length > 0 ? { held: state.held } : {}),
            ...(images.length > 0 ? { images } : {}),
            ...(action.afterAnswer ? { afterAnswer: action.afterAnswer } : {}),
            ...(action.afterCalls ? { afterCalls: action.afterCalls } : {}),
          },
        ],
      };
    }
    case 'menu_moved':
      return { ...state, menu: moved(state.menu, action) };
    case 'menu_dismissed':
      return state.menu.dismissed
        ? state
        : { ...state, menu: { ...state.menu, dismissed: true } };
    case 'files_listed':
      return { ...state, files: action.files };
    case 'team_names_listed':
      return { ...state, teamNames: action.names };
    case 'finder_moved':
      return {
        ...state,
        finder: { ...moved(state.finder, action), moved: true },
      };
    case 'files_matched': {
      if (action.files !== state.files) {
        return state;
      }

      const { matchSlow, ...left } = state;

      return {
        ...left,
        ...(matchSlow === undefined || matchSlow === action.query
          ? {}
          : { matchSlow }),
        matched: {
          files: action.files,
          query: action.query,
          matched: action.matched,
        },
        // The highlight goes to the first row of the list that came.
        finder: { ...initialMenu, dismissed: state.finder.dismissed },
      };
    }
    case 'match_slow':
      return { ...state, matchSlow: action.query };
    case 'pick_awaited':
      return {
        ...state,
        awaitedPick: { mention: action.mention, enter: action.enter },
      };
    case 'pick_settled': {
      const { awaitedPick: _, ...left } = state;

      return left;
    }
    case 'finder_dismissed':
      return state.finder.dismissed
        ? state
        : { ...state, finder: { ...state.finder, dismissed: true } };
    case 'draft_edited':
      return state.menu === initialMenu && state.finder === initialMenu
        ? state
        : { ...state, menu: initialMenu, finder: initialMenu };
    case 'draft_set': {
      const draft = action.text ?? state.draft;
      const cursor = action.cursor ?? state.cursor;

      return draft === state.draft && sameCursor(cursor, state.cursor)
        ? state
        : { ...state, draft, cursor };
    }
    case 'editor_failed':
      return { ...state, editorFailed: action.message };
    case 'bash_mode':
      return state.bash === action.on ? state : { ...state, bash: action.on };
    case 'draft_kept':
      return state.draft === ''
        ? state
        : {
            ...state,
            kept: [
              ...(state.kept ?? []),
              {
                text: state.draft,
                cursor: state.cursor,
                images: imagesIn(state.draft, state.images),
                bash: state.bash,
              },
            ],
            draft: '',
            cursor: START,
            images: [],
            bash: false,
          };
    case 'kept_edited': {
      const kept = state.kept ?? [];

      if (kept[action.index] === undefined) {
        return state;
      }

      return {
        ...state,
        kept: kept.with(action.index, {
          text: state.draft,
          cursor: state.cursor,
          images: imagesIn(state.draft, state.images),
          bash: state.bash,
        }),
      };
    }
    case 'kept_taken': {
      const kept = (state.kept ?? []).filter(
        (_, index) => index !== action.index,
      );

      return kept.length === (state.kept ?? []).length
        ? state
        : { ...state, kept };
    }
    case 'context_sent': {
      // Only what went: a run that ended since stays for the next prompt.
      const held = state.held.filter((id) => !action.held.includes(id));

      return held.length === state.held.length ? state : { ...state, held };
    }
  }
}

function sameCursor(one: Cursor, other: Cursor): boolean {
  return one[0] === other[0] && one[1] === other[1];
}

/** A list's highlight one step on, and the window onto it kept round it. */
function moved(
  menu: MenuState,
  {
    step,
    count,
    rows,
  }: {
    readonly step: 1 | -1;
    readonly count: number;
    readonly rows: number;
  },
): MenuState {
  const highlighted = moveHighlight(
    Math.min(menu.highlighted, count - 1),
    count,
    step,
  );
  const { start } = visibleRange(count, highlighted, rows, menu.top);

  return { ...menu, highlighted, top: start };
}

/** What the prompt reads of the session: its transcript. */
interface Said {
  readonly transcript: Transcript;
}

/**
 * What the lists read of the session besides: whether the window is closing,
 * when neither opens.
 */
interface Open extends Said {
  readonly connection: { readonly status: string };
  /** The keys, by which a request between turns is held or not. */
  readonly keys: Keymap;
  /** The request between turns the keys were taken into, if one was. */
  readonly attended?: string;
}

/** The shell run still going, if there is one; one runs at a time. */
export function runningShell(state: Said): string | undefined {
  return state.transcript.entries.find(
    (entry) => entry.kind === 'shell' && entry.run.running,
  )?.turnId;
}

/** The held runs' output as it goes ahead of the next prompt. */
export function heldContext(state: PromptSession & Said): string {
  const runs = state.held.flatMap((id): ShellRun[] => {
    const entry = state.transcript.entries.find(
      (entry) => entry.kind === 'shell' && entry.turnId === id,
    );

    return entry?.kind === 'shell' ? [entry.run] : [];
  });

  return shellContext(runs);
}

/** The slash command list as it stands: what the draft matches, and where. */
export interface CommandMenu {
  readonly items: readonly CommandItem[];
  readonly highlighted: number;
  /** The first item shown, when there are more than fit. */
  readonly top: number;
}

/**
 * The slash command list `draft` opens: a `/` and part of a name, `/new `
 * and part of an agent's, or `/team show ` and the like and part of a team's, outside bash mode, while no permission is asked and Esc has not put it away. None when nothing matches,
 * so Enter sends what was typed, as the agent may know a command chord does
 * not list.
 */
export function commandMenu(
  state: PromptState & Open,
  draft: string,
): CommandMenu | undefined {
  const query = commandQuery(draft);
  const named = agentQuery(draft);
  const team = teamQuery(draft);

  if (
    (query === undefined && named === undefined && team === undefined) ||
    state.menu.dismissed ||
    state.bash ||
    state.search !== undefined ||
    state.connection.status === 'closing' ||
    asksWithKeys(state)
  ) {
    return undefined;
  }

  const items =
    team !== undefined
      ? matchAgents(
          teamItems(
            team.form,
            state.teamNames?.teams ?? [],
            state.teamNames?.runs ?? [],
          ),
          team.name,
        )
      : query === undefined
        ? matchAgents(state.agents ?? [], named ?? '')
        : matchCommands(commandItems(state.transcript.commands), query);

  if (items.length === 0) {
    return undefined;
  }

  return {
    items,
    highlighted: Math.min(state.menu.highlighted, items.length - 1),
    top: state.menu.top,
  };
}

/** The `@` file finder as it stands: the mention, its files, and where. */
export interface FileFinder {
  readonly mention: Mention;
  readonly files: readonly string[];
  readonly highlighted: number;
  /** The first file shown, when there are more than fit. */
  readonly top: number;
  /**
   * The mention's own match has not come back yet: `files` are the last
   * match's, kept on screen meanwhile.
   */
  readonly pending: boolean;
  /** It has run longer than `SLOW_MATCH_MS`, which the list says. */
  readonly searching: boolean;
}

/** How long a match runs before the list says it is searching. */
export const SLOW_MATCH_MS = 150;

/**
 * The mention whose own match has not come back yet, whether or not the
 * finder shows a list meanwhile: Enter and Tab wait for it either way.
 * None for an empty query, which waits on nothing, or where the finder
 * could not open.
 */
export function pendingMention(
  state: PromptState & Open,
  draft: string,
  cursor: Cursor,
): Mention | undefined {
  const mention = mentionAt(draft, cursor);

  if (
    mention === undefined ||
    mention.query === '' ||
    state.files === undefined ||
    state.bash ||
    state.search !== undefined ||
    state.finder.dismissed ||
    state.connection.status === 'closing' ||
    asksWithKeys(state)
  ) {
    return undefined;
  }

  const current =
    state.matched?.files === state.files ? state.matched : undefined;

  return current?.query === mention.query ? undefined : mention;
}

/**
 * The `@` file finder the draft opens: the cursor at the end of an `@` and
 * part of a path, once the files are walked, outside bash mode, while no
 * permission is asked and Esc has not put it away. None when nothing matches, so Enter sends what was
 * typed.
 */
export function fileFinder(
  state: PromptState & Open,
  draft: string,
  cursor: Cursor,
): FileFinder | undefined {
  const mention = mentionAt(draft, cursor);

  if (
    mention === undefined ||
    state.files === undefined ||
    state.bash ||
    state.search !== undefined ||
    state.finder.dismissed ||
    state.connection.status === 'closing' ||
    asksWithKeys(state)
  ) {
    return undefined;
  }

  // An empty query shows the walk's first files at once, matching nothing;
  // any other waits for its match, the last one's list kept meanwhile.
  const current =
    state.matched?.files === state.files ? state.matched : undefined;
  const pending = mention.query !== '' && current?.query !== mention.query;
  const files =
    mention.query === ''
      ? firstFiles(state.files)
      : (current?.matched ?? firstFiles(state.files));
  const searching = pending && state.matchSlow === mention.query;

  if (files.length === 0 && !searching) {
    return undefined;
  }

  return {
    mention,
    files,
    highlighted: Math.min(
      state.finder.highlighted,
      Math.max(files.length - 1, 0),
    ),
    top: state.finder.top,
    pending,
    searching,
  };
}
