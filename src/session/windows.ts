/**
 * The window records chord wrote before 0.58.0, when a window held several
 * sessions as tabs, read so `--resume w-…` can say what each held: chord
 * opens one session per run now and never writes them again (CHD-493). One
 * JSON file per window under `windows/` in chord's state directory.
 */
import { z } from '@zod/zod';
import { join } from 'node:path';
import { readFile } from 'node:fs/promises';
import { notFound } from '../not_found.ts';
import { ResumeError, resumeCommand } from './sessions.ts';

/** What tells a window's id from a session's on the command line. */
export const WINDOW_PREFIX = 'w-';

/** A window's id as chord makes them; one typed by hand is checked by it. */
export const WINDOW_ID = /^w-[0-9a-z]+$/;

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

export const WindowSchema = z.object({
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

export function windowsDir(stateDir: string): string {
  return join(stateDir, 'windows');
}

export function windowFile(stateDir: string, id: string): string {
  return join(windowsDir(stateDir), `${id}.json`);
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
 * What `--resume w-…` says of a window: chord opens one session per run, so
 * each of its sessions is said back as a command of its own, in its tab
 * order, in its own directory, whether chord still has its record or not:
 * an id it has none of goes to the agent, which may still know it.
 */
export function windowGone(record: WindowRecord): string {
  const count = record.tabs.length;

  return [
    `${record.id} was a window of ${count} ${
      count === 1 ? 'session' : 'sessions'
    }; chord opens one session per run now. Resume ${
      count === 1 ? 'it' : 'each'
    } with:`,
    ...record.tabs.map((tab) =>
      resumeCommand(tab.agent, tab.sessionId, undefined, tab.cwd),
    ),
  ].join('\n');
}
