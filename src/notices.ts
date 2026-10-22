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
 */
export class NoticeWatch {
  readonly #atRisk = new Set<string>();

  /**
   * Hears session `id`, of `agent`, with its options now `options`; whether
   * the notice came due: the session is at risk now and was not before.
   */
  heard(id: string, agent: string, options: readonly AgentOption[]): boolean {
    const was = this.#atRisk.has(id);
    const now = dimcodeAtRisk(agent, options);

    if (now) {
      this.#atRisk.add(id);
    } else {
      this.#atRisk.delete(id);
    }

    return now && !was;
  }

  /** Forgets session `id`, which has closed: it is at risk no longer. */
  gone(id: string): void {
    this.#atRisk.delete(id);
  }

  /** Whether session `id` is at risk now, as last heard. */
  atRisk(id: string): boolean {
    return this.#atRisk.has(id);
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
