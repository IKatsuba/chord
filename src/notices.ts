/**
 * chord's one-time notices (docs/design/CHD-434.md): dimcode's, that it can
 * start other agents with their approvals bypassed once its `permission`
 * option leaves `read-only`; what it says, when it is due, and the record of
 * its dismissal in chord's user directory, beside the user settings file,
 * per machine.
 */
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { z } from '@zod/zod';
import { notFound } from './not_found.ts';
import type { AgentOption } from './session/config.ts';

/** The notice's id in the record, once dismissed. */
export const DIMCODE_NOTICE = 'dimcode-agents';

/** What the notice says: its title, then its two paragraphs. */
export const DIMCODE_WORDS = {
  title: 'dimcode can start other agents',
  paragraphs: [
    'With its permission option at full-access, dimcode may start other ' +
      'agent CLIs it finds on your PATH, such as claude, codex and cursor, ' +
      'as subagents of its own, with their approvals bypassed and on your ' +
      'own accounts. At workspace-write it asks you first, and once you ' +
      "allow it, the same holds. Nothing those agents do reaches chord's " +
      'permission box.',
    'To turn a CLI off, set externalAgents.<type>.enabled to false in ' +
      '~/.dimcode/v2/config.json (claude-code, codex, cursor, …), or use ' +
      "/external-agents in dimcode's own TUI. Or keep the permission option " +
      'at read-only in /config, where dimcode refuses its agent tool.',
  ],
} as const;

/** The notice's two answers: dismissed for good on this machine, or later. */
export const NOTICE_CHOICES = [
  { key: 'dismiss', label: "Got it, don't show this again", value: 'dismiss' },
  { key: 'later', label: 'Show it again next time', value: 'later' },
] as const;

/** dimcode's config option that says what its `agent` tool may do. */
const PERMISSION = 'permission';

/** The one value at which dimcode refuses its `agent` tool without asking. */
const READ_ONLY = 'read-only';

/**
 * Whether a session of `agent`, by the name chord runs it as, has dimcode's
 * `permission` option at anything but `read-only`: the moment the notice
 * is about (W2). None from any other agent, or with no such option yet.
 */
export function dimcodeAtRisk(
  agent: string,
  options: readonly AgentOption[],
): boolean {
  const permission = options.find((option) => option.id === PERMISSION);

  return (
    agent === 'dimcode' &&
    permission !== undefined &&
    permission.current !== READ_ONLY
  );
}

/**
 * Which sessions the notice's moment holds for, by an id of chord's for each,
 * kept apart, so one session's options leaving `read-only` makes it due
 * whatever any other is at, and a session at it still says so after the
 * person answered "show it again" for another (docs/design/CHD-434.md).
 * Each time one comes due it is given a ticket, which the record's read
 * then shows for only while that session is still at risk: not once it went
 * back to `read-only`, closed, or was cleared for a session of its own
 * under the same id.
 */
export class NoticeWatch {
  /** The ticket of each session at risk now. */
  readonly #atRisk = new Map<string, number>();
  #tickets = 0;

  /**
   * Hears session `id`, of `agent`, with its options now `options`; when
   * the notice came due, as it is at risk now and was not before, its
   * ticket.
   */
  heard(
    id: string,
    agent: string,
    options: readonly AgentOption[],
  ): number | undefined {
    if (!dimcodeAtRisk(agent, options)) {
      this.#atRisk.delete(id);

      return undefined;
    }

    if (this.#atRisk.has(id)) {
      return undefined;
    }

    this.#tickets += 1;

    this.#atRisk.set(id, this.#tickets);

    return this.#tickets;
  }

  /**
   * Forgets session `id`, closed or cleared: it is at risk no longer, and a
   * session after it under the same id comes due of its own.
   */
  gone(id: string): void {
    this.#atRisk.delete(id);
  }

  /** Whether the session `ticket` was given to is still at risk as it was. */
  holds(id: string, ticket: number): boolean {
    return this.#atRisk.get(id) === ticket;
  }
}

/**
 * Where a window's notices come due and are dismissed, so the record's
 * reads and its write never cross: one dismissed in the window shows no
 * more from that moment, whatever a read begun before it, or before the
 * write lands, finds; one whose write failed is given back, to show the
 * next time it comes due, the side a failure errs on.
 */
export class NoticeGate {
  readonly #read: () => Promise<ReadonlySet<string>>;
  readonly #write: (id: string) => Promise<void>;
  readonly #dismissed = new Set<string>();
  // Moves on each dismissal, so a read begun before one shows nothing.
  #generation = 0;

  constructor(
    read: () => Promise<ReadonlySet<string>>,
    write: (id: string) => Promise<void>,
  ) {
    this.#read = read;
    this.#write = write;
  }

  /**
   * Whether notice `id`, come due, is to show: the record read, a record
   * that does not read showing it, and `holds` still true once it is.
   */
  async due(id: string, holds: () => boolean): Promise<boolean> {
    const generation = this.#generation;
    const recorded = await this.#read().catch(() => new Set<string>());

    return (
      generation === this.#generation &&
      !this.#dismissed.has(id) &&
      !recorded.has(id) &&
      holds()
    );
  }

  /** Dismisses notice `id` for good: at once here, then in the record. */
  async dismiss(id: string): Promise<void> {
    this.#dismissed.add(id);

    this.#generation += 1;

    try {
      await this.#write(id);
    } catch {
      this.#dismissed.delete(id);
    }
  }
}

/** The record of dismissed notices, beside the user settings file. */
export function noticesFile(
  configHome: string | undefined,
): string | undefined {
  return configHome === undefined
    ? undefined
    : join(configHome, 'chord', 'notices.json');
}

const NOTICES = z.object({ dismissed: z.array(z.string()) });

/**
 * The notices dismissed on this machine, as `file` records them; none when
 * there is no file, or one that does not read, which is shown again rather
 * than lost.
 */
export async function dismissedNotices(
  file: string | undefined,
): Promise<ReadonlySet<string>> {
  if (file === undefined) {
    return new Set();
  }

  try {
    const read = NOTICES.safeParse(JSON.parse(await readFile(file, 'utf8')));

    return new Set(read.success ? read.data.dismissed : []);
  } catch (error) {
    if (notFound(error) || error instanceof SyntaxError) {
      return new Set();
    }

    throw error;
  }
}

/** Records notice `id` dismissed in `file`, beside any others there. */
export async function dismissNotice(file: string, id: string): Promise<void> {
  const dismissed = new Set([...(await dismissedNotices(file)), id]);
  const temporary = `${file}.${crypto.randomUUID()}.tmp`;

  await mkdir(dirname(file), { recursive: true });

  try {
    await writeFile(
      temporary,
      `${JSON.stringify({ dismissed: [...dismissed] }, null, 2)}\n`,
    );
    await rename(temporary, file);
  } catch (error) {
    await rm(temporary).catch(() => {});

    throw error;
  }
}
