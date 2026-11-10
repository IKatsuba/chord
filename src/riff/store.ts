/**
 * Where riff keeps its sessions (CHD-485, "Sessions and resume"): libfx's
 * `local()` store under chord's state directory, and beside it a JSON
 * sidecar per session with what `session/resume` does not carry: the
 * provider, account, model, effort and mode. chord's record stays what was
 * shown; this is what the model knows.
 */
import { z } from '@zod/zod';
import type { Durability } from 'libfx/node';
// Imported statically: libfx's default store loads by `new URL`, which a
// compiled binary does not hold, and lives in the temporary directory.
import { local } from 'libfx/durable-local';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { notFound } from '../not_found.ts';
import { EFFORTS, MODES, type RiffConfig, type RiffPlan } from './models.ts';

const SIDECAR = z.object({
  provider: z.enum(['codex', 'grok', 'fake']),
  /** libfx's accountId for a plan, null for the fixture provider. */
  account: z.string().nullable(),
  model: z.string().min(1),
  effort: z.enum(EFFORTS),
  mode: z.enum(MODES),
});

/** A session's sidecar. */
export type Sidecar = RiffConfig & {
  readonly provider: RiffPlan;
  readonly account: string | null;
};

/** libfx's session ids are `wrun_` and letters and digits; nothing else names a file. */
const SESSION_ID = /^[A-Za-z0-9_-]{1,128}$/;

/** riff's store under `stateDir`, chord's state directory. */
export interface RiffStore {
  readonly durability: Durability;
  /** The session's sidecar, or undefined when it has none or none readable. */
  read(sessionId: string): Promise<Sidecar | undefined>;
  /** Writes the sidecar whole, atomically. */
  write(sessionId: string, sidecar: Sidecar): Promise<void>;
}

export function riffStore(stateDir: string): RiffStore {
  const root = join(stateDir, 'riff');
  const sidecars = join(root, 'sidecars');
  const file = (sessionId: string) => {
    if (!SESSION_ID.test(sessionId)) {
      throw new Error(`Not a riff session id: ${sessionId}`);
    }

    return join(sidecars, `${sessionId}.json`);
  };

  return {
    durability: local({ dir: join(root, 'sessions') }),
    read: async (sessionId) => {
      if (!SESSION_ID.test(sessionId)) {
        return undefined;
      }

      let text: string;

      try {
        text = await readFile(file(sessionId), 'utf8');
      } catch (error) {
        if (notFound(error)) {
          return undefined;
        }

        throw error;
      }

      try {
        const parsed = SIDECAR.safeParse(JSON.parse(text));

        return parsed.success ? parsed.data : undefined;
      } catch {
        return undefined;
      }
    },
    write: async (sessionId, sidecar) => {
      const target = file(sessionId);
      const temporary = `${target}.${crypto.randomUUID()}.tmp`;

      await mkdir(sidecars, { recursive: true });

      try {
        await writeFile(temporary, `${JSON.stringify(sidecar, null, 2)}\n`);
        await rename(temporary, target);
      } catch (error) {
        await rm(temporary).catch(() => {});

        throw error;
      }
    },
  };
}
