/**
 * chord's window records: the tabs a window had open when it quit, so
 * `--resume w-…` opens all of them again. One JSON file per window under
 * `windows/` in chord's state directory, beside the session records each tab
 * is read back from.
 */
import { z } from '@zod/zod';
import { join } from 'node:path';
import {
  mkdir,
  readdir,
  readFile,
  rename,
  rm,
  writeFile,
} from 'node:fs/promises';
import { notFound } from '../not_found.ts';
import stringWidth from 'string-width';
import {
  type EarlierSession,
  type ResumableTab,
  type ResumedTab,
  ResumeError,
  sessionById,
  type SessionRecord,
} from './sessions.ts';
import { MAX_TABS } from './tabs.ts';

/** What tells a window's id from a session's on the command line. */
export const WINDOW_PREFIX = 'w-';

/** A window's id as chord makes them; one typed by hand is checked by it. */
const WINDOW_ID = /^w-[0-9a-z]+$/;

/** A tab as the window record keeps it. */
export interface WindowTab {
  /** The agent's own id for the tab's session. */
  readonly sessionId: string;
  /** The agent the tab ran, by the name chord starts it by. */
  readonly agent: string;
  /** The directory the session works in. */
  readonly cwd: string;
}

/** A window as it was when it quit. */
export interface WindowRecord {
  readonly id: string;
  /** When it quit, epoch milliseconds. */
  readonly at: number;
  /** Its tabs, in order. */
  readonly tabs: readonly WindowTab[];
  /** Which of them was in front, by its index. */
  readonly front: number;
}

const WindowSchema = z.object({
  id: z.string().regex(WINDOW_ID),
  at: z.number(),
  tabs: z
    .array(
      z.object({
        sessionId: z.string(),
        agent: z.string(),
        cwd: z.string(),
      }),
    )
    .min(1),
  front: z.int().nonnegative(),
});

/** Whether `--resume` was handed a window's id rather than a session's. */
export function isWindowId(id: string): boolean {
  return id.startsWith(WINDOW_PREFIX);
}

/**
 * A new window's id: short, as it is typed after `--resume`, and long enough
 * that one person's windows do not meet.
 */
export function newWindowId(): string {
  return `${WINDOW_PREFIX}${crypto.randomUUID().slice(0, 8)}`;
}

export function windowsDir(stateDir: string): string {
  return join(stateDir, 'windows');
}

function windowFile(stateDir: string, id: string): string {
  return join(windowsDir(stateDir), `${id}.json`);
}

/** The record's file, as it is written. */
export function windowText(record: WindowRecord): string {
  return `${JSON.stringify(record, null, 2)}\n`;
}

/** A window record read back; none for a file that is not one. */
export function parseWindow(text: string): WindowRecord | undefined {
  let json: unknown;

  try {
    json = JSON.parse(text);
  } catch {
    return undefined;
  }

  const parsed = WindowSchema.safeParse(json);

  return parsed.success && parsed.data.front < parsed.data.tabs.length
    ? parsed.data
    : undefined;
}

/**
 * The window `--resume <id>` names. Refused when chord has no such record,
 * or one it cannot read: there is nothing else it could open.
 */
export async function readWindow(
  stateDir: string,
  id: string,
): Promise<WindowRecord> {
  const missing = new ResumeError(`No window ${id} among chord's records.`);

  // The id goes into a path, so only one chord could have made is looked for.
  if (!WINDOW_ID.test(id)) {
    throw missing;
  }

  let text: string;

  try {
    text = await readFile(windowFile(stateDir, id), 'utf8');
  } catch (error) {
    if (notFound(error)) {
      throw missing;
    }

    throw error;
  }

  const found = parseWindow(text);

  if (found?.id !== id) {
    throw new ResumeError(`Window ${id}'s record cannot be read.`);
  }

  return found;
}

/**
 * Writes `record` whole to a file beside its own that is renamed over it, so
 * a window quit twice, or a crash, cannot leave half of one.
 */
export async function writeWindow(
  stateDir: string,
  record: WindowRecord,
): Promise<void> {
  const file = windowFile(stateDir, record.id);
  const temporary = `${file}.${crypto.randomUUID()}.tmp`;

  await mkdir(windowsDir(stateDir), { recursive: true });

  try {
    await writeFile(temporary, windowText(record));
    await rename(temporary, file);
  } catch (error) {
    await rm(temporary).catch(() => {});

    throw error;
  }
}

/**
 * The record a window quitting leaves: its resumable tabs, in order, and the
 * one in front, under `id` — the record it was opened from, so quitting it
 * again rewrites that one. None with fewer than two, as one session resumes
 * by its own id.
 */
export function windowOnQuit(
  tabs: readonly ResumableTab[],
  front: number,
  { id, at }: { readonly id: string; readonly at: number },
): WindowRecord | undefined {
  if (tabs.length < 2) {
    return undefined;
  }

  return {
    id,
    at,
    tabs: tabs.map(({ sessionId, agent, cwd }) => ({ sessionId, agent, cwd })),
    front: Math.min(Math.max(front, 0), tabs.length - 1),
  };
}

/** What is printed on quit in place of a command for each session. */
export function windowMessage(id: string): string {
  return `Resume this window with:\nchord --resume ${id}`;
}

/** The refusal of a window's id among other ids. */
export function mixedRefusal(id: string): ResumeError {
  return new ResumeError(
    `Window ${id} opens on its own; --resume takes it without session ids.`,
  );
}

/** The tabs a window record opens, and what it could not. */
export interface WindowTabs {
  /** Those whose session chord still has a record of, in order. */
  readonly tabs: readonly ResumedTab[];
  /** Which of them goes in front, by its index. */
  readonly front: number;
  /**
   * What the status line says of the tabs left out, as their sessions'
   * records are gone; none when every one opened.
   */
  readonly note?: string;
}

/**
 * The tabs `--resume w-…` opens: each of the window's, on the agent it ran,
 * read back from its session's record, as `-r <id> -r <id>` opens them. A
 * tab whose session record is gone is left out and the rest open; the
 * front goes to the recorded one, or the first when that one was left out.
 * An agent named on the command line must be every tab's, as with several
 * session ids.
 */
export function windowTabs(
  records: readonly SessionRecord[],
  window: WindowRecord,
  { agent, named }: { readonly agent: string; readonly named: boolean },
): WindowTabs {
  const opened: ResumedTab[] = [];
  const missing: number[] = [];
  let front = 0;

  for (const [index, tab] of window.tabs.entries()) {
    if (!records.some((record) => record.sessionId === tab.sessionId)) {
      missing.push(index + 1);
      continue;
    }

    if (named && tab.agent !== agent) {
      throw new ResumeError(
        `Session ${tab.sessionId} belongs to another agent (${tab.agent}).`,
      );
    }

    if (index === window.front) {
      front = opened.length;
    }

    opened.push({
      agent: tab.agent,
      resume: sessionById(records, tab.sessionId, {
        agent: tab.agent,
        cwd: tab.cwd,
      }),
    });
  }

  if (opened.length === 0) {
    throw new ResumeError(
      `None of window ${window.id}'s sessions is among chord's records.`,
    );
  }

  return {
    tabs: opened,
    front,
    ...(missing.length === 0 ? {} : { note: missingNote(window, missing) }),
  };
}

// Named by agent and short id, not by number: the tab bar numbers the window
// as it opened, so the recorded tab number would name another tab.
function missingNote(window: WindowRecord, missing: readonly number[]) {
  const tabs = missing.map((number) => window.tabs[number - 1]!);
  const short = (tab: WindowTab) => tab.sessionId.slice(0, 8);

  if (tabs.length === 1) {
    const [tab] = tabs as [WindowTab];

    return `Not reopened: ${tab.agent} tab ${short(tab)}, its record is gone`;
  }

  return `Not reopened: ${tabs.length} tabs whose records are gone (${tabs
    .map((tab) => `${tab.agent} ${short(tab)}`)
    .join(', ')})`;
}

/**
 * Every window record in `stateDir`, in no order; a file that is not one is
 * left out, as a list has nothing to say of it.
 */
export async function readWindows(stateDir: string): Promise<WindowRecord[]> {
  const dir = windowsDir(stateDir);
  const names: string[] = [];

  try {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.endsWith('.json')) {
        names.push(entry.name);
      }
    }
  } catch (error) {
    if (notFound(error)) {
      return [];
    }

    throw error;
  }

  const read = await Promise.all(
    names.map(async (name) => {
      try {
        const found = parseWindow(await readFile(join(dir, name), 'utf8'));

        // Named for its id, as `readWindow` finds it by that.
        return found?.id === name.slice(0, -'.json'.length) ? found : undefined;
      } catch {
        return undefined;
      }
    }),
  );

  return read.filter((window) => window !== undefined);
}

/** A saved window `/resume` offers, and what its row says of it. */
export interface EarlierWindow {
  readonly id: string;
  /** When it quit: an ISO timestamp, as a session's last use is. */
  readonly lastUsedAt: string;
  /** Its tabs as the record names them, in order. */
  readonly tabs: readonly WindowTab[];
  /** Which of them was in front, by its index. */
  readonly front: number;
  /** What Enter opens: the tabs whose records are there, as `--resume w-…`. */
  readonly opening: WindowTabs;
  /** Its front tab's first prompt, on one line, as that session's row has it. */
  readonly prompt: string;
}

/**
 * The windows `/resume` offers, newest first, whatever their agents: one
 * holds several by nature. One none of whose sessions has a record left is
 * not offered, as Enter would open nothing.
 */
export function earlierWindows(
  windows: readonly WindowRecord[],
  records: readonly SessionRecord[],
): EarlierWindow[] {
  return windows
    .toSorted((a, b) => b.at - a.at)
    .flatMap((window) => {
      let opening: WindowTabs;

      try {
        opening = windowTabs(records, window, { agent: '', named: false });
      } catch {
        return [];
      }

      return [
        {
          id: window.id,
          lastUsedAt: new Date(window.at).toISOString(),
          tabs: window.tabs,
          front: window.front,
          opening,
          prompt: opening.tabs[opening.front]?.resume.prompt ?? '',
        },
      ];
    });
}

/** One row of `/resume`'s list: a session, or a saved window. */
export type ResumeEntry =
  | { readonly kind: 'session'; readonly session: EarlierSession }
  | { readonly kind: 'window'; readonly window: EarlierWindow };

/**
 * `/resume`'s one list, newest first: a person remembers when, not whether it
 * was a window. A window quits after its sessions' last prompts, so each sits
 * just above its own sessions; on a tie the window goes first all the same.
 */
export function resumeEntries(
  sessions: readonly EarlierSession[],
  windows: readonly EarlierWindow[],
): ResumeEntry[] {
  const entries: ResumeEntry[] = [
    ...windows.map((window) => ({ kind: 'window' as const, window })),
    ...sessions.map((session) => ({ kind: 'session' as const, session })),
  ];
  const time = (entry: ResumeEntry) =>
    Date.parse(
      entry.kind === 'window'
        ? entry.window.lastUsedAt
        : entry.session.lastUsedAt,
    );

  // Stable, so windows, listed first, stay ahead of sessions at the same time.
  return entries.toSorted((a, b) => time(b) - time(a));
}

/**
 * Whether `window` is this directory's: every one of its tabs works in `cwd`,
 * as only those open here from `/resume`.
 */
export function windowIn(
  window: Pick<EarlierWindow, 'tabs'>,
  cwd: string,
): boolean {
  return window.tabs.every((tab) => tab.cwd === cwd);
}

/** Those of `entries` that work in `cwd`, in the order they came. */
export function entriesIn(
  entries: readonly ResumeEntry[],
  cwd: string,
): ResumeEntry[] {
  return entries.filter((entry) =>
    entry.kind === 'window'
      ? windowIn(entry.window, cwd)
      : entry.session.resume.cwd === cwd,
  );
}

/**
 * The most columns a window row's agents take, as the directory column
 * does; past it they are counted.
 */
export const AGENTS_WIDTH = 30;

/**
 * A window's agents as its row names them: in tab order with repeats, as the
 * strip had them; past `width`, each once with how many, in the order they
 * first came; and past that too, those at the end counted rather than named,
 * `+1`. A name is never cut.
 */
export function windowAgents(
  agents: readonly string[],
  width = AGENTS_WIDTH,
): string {
  const listed = agents.join(', ');

  if (stringWidth(listed) <= width) {
    return listed;
  }

  const counts = new Map<string, number>();

  for (const agent of agents) {
    counts.set(agent, (counts.get(agent) ?? 0) + 1);
  }

  const parts = [...counts].map(([agent, count]) =>
    count === 1 ? agent : `${agent} ×${count}`,
  );
  const counted = parts.join(', ');

  if (stringWidth(counted) <= width) {
    return counted;
  }

  for (let kept = parts.length - 1; kept > 1; kept--) {
    const text = `${parts.slice(0, kept).join(', ')} +${parts.length - kept}`;

    if (stringWidth(text) <= width) {
      return text;
    }
  }

  return `${parts[0]} +${parts.length - 1}`;
}

/**
 * The start of a window's row: `▣ 3 sessions`, how many of them are open in
 * this window, if any, and its agents. The open mark is part of the summary,
 * right after the count, where a cut at the picker's edge never reaches it.
 */
export function windowSummary(
  window: Pick<EarlierWindow, 'tabs'>,
  open: number,
): string {
  const count = window.tabs.length;
  const mark =
    open === 0 ? '' : open >= count ? ', all open' : `, ${open} open`;

  return `▣ ${count} sessions${mark} · ${windowAgents(
    window.tabs.map(({ agent }) => agent),
  )}`;
}

/**
 * The directories a window's tabs work in as its row names them: the front
 * tab's, and ` +n` for how many others; `shown` turns a directory into what
 * the column shows, cut to `width`, and the ` +n` is never what is cut.
 */
export function windowDirectory(
  window: Pick<EarlierWindow, 'tabs' | 'front'>,
  shown: (cwd: string, width: number) => string,
  width: number,
): string {
  const front = window.tabs[window.front]?.cwd ?? window.tabs[0]?.cwd ?? '';
  const others = new Set(window.tabs.map(({ cwd }) => cwd));

  others.delete(front);

  const more = others.size === 0 ? '' : ` +${others.size}`;

  return `${shown(front, width - more.length)}${more}`;
}

/**
 * What opening a window beside the tabs open asks of the cap: the tabs it
 * needs, those not open already, and how many are free, an empty front tab
 * it takes the place of counted free.
 */
export function windowRoom({
  open,
  reused,
  needed,
}: {
  /** How many tabs are open. */
  readonly open: number;
  /** Whether the front tab, never prompted, gives its place to the window. */
  readonly reused: boolean;
  /** How many of the window's tabs are not open already. */
  readonly needed: number;
}): { readonly needs: number; readonly free: number; readonly fits: boolean } {
  const free = Math.max(0, MAX_TABS - open + (reused ? 1 : 0));

  return { needs: needed, free, fits: needed <= free };
}

/**
 * The status line's refusal of a window the cap has no room for: how many
 * tabs it needs, how many are free, and how many to close, with the key
 * that closes one; the shorter wording where the line is too narrow for the
 * longer one beside the model.
 */
export function capNote(
  { needs, free }: { readonly needs: number; readonly free: number },
  closeKey: string | undefined,
  columns: number,
): string {
  const close = needs - free;
  const freeText =
    free === 0
      ? 'none are free'
      : free === 1
        ? '1 is free'
        : `${free} are free`;
  const how = closeKey === undefined ? '' : ` with ${closeKey}`;
  const long = `That window needs ${needs} tabs and ${freeText} · close ${close}${how}, then /resume again`;

  // Room left for the model and the context beside it, as at 120 columns.
  return stringWidth(long) + 4 + 32 <= columns
    ? long
    : `That window needs ${needs} tabs, ${freeText} · close ${close}${how} first`;
}

/**
 * What `/resume` says of a window it does not open in this window, as a
 * session from elsewhere: the directory of a tab that works elsewhere, and
 * the command that opens the window, on a line of its own.
 */
export function windowElsewhereRefusal(id: string, shownCwd: string): string {
  return `That window has a tab in ${shownCwd}. Quit and open it there with:\nchord --resume ${id}`;
}
