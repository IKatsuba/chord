/** The last successfully signed-in plan; never a credential or account. */
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { notFound } from '../not_found.ts';
import type { SecretProvider } from '../platform/secrets.ts';
import { withCredentialLock } from './credential_lock.ts';

const fileOf = (stateDir: string) => join(stateDir, 'riff', 'provider');

export async function readProvider(
  stateDir: string,
): Promise<SecretProvider | undefined> {
  let value: string;

  try {
    value = await readFile(fileOf(stateDir), 'utf8');
  } catch (error) {
    if (notFound(error)) {
      return undefined;
    }

    throw error;
  }

  return value === 'codex\n'
    ? 'codex'
    : value === 'grok\n'
      ? 'grok'
      : undefined;
}

export async function writeProvider(
  stateDir: string,
  provider: SecretProvider,
): Promise<void> {
  await withCredentialLock(
    stateDir,
    'selection',
    'provider record',
    async () => {
      const file = fileOf(stateDir);
      const temporary = `${file}.${crypto.randomUUID()}.tmp`;

      await mkdir(join(stateDir, 'riff'), { recursive: true });

      try {
        await writeFile(temporary, `${provider}\n`);
        await rename(temporary, file);
      } finally {
        await rm(temporary, { force: true });
      }
    },
  );
}

export async function clearProvider(
  stateDir: string,
  provider: SecretProvider,
): Promise<void> {
  await withCredentialLock(
    stateDir,
    'selection',
    'provider record',
    async () => {
      if ((await readProvider(stateDir)) === provider) {
        await rm(fileOf(stateDir), { force: true });
      }
    },
  );
}
