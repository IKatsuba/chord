import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { secrets, SECRET_TIMEOUT } from '../../src/platform/secrets.ts';
import {
  CredentialStoreBusy,
  withCredentialLock,
} from '../../src/riff/credential_lock.ts';
import {
  credentialCell,
  type CredentialState,
} from '../../src/riff/credentials.ts';

describe('riff cross-process credential lock', () => {
  test(
    'late write holds its heartbeat and mutex; second process refreshes only after completion',
    async () => {
      const root = await mkdtemp(join(tmpdir(), 'chord-lock-test-'));
      const entry = join(root, 'fixture.json');
      const started = Promise.withResolvers<void>();
      const finish = Promise.withResolvers<void>();
      const states: CredentialState[] = [];
      const store = secrets(
        {
          get: () => readFile(entry, 'utf8'),
          set: async ({ value }) => {
            started.resolve();
            await finish.promise;
            await writeFile(entry, value);
          },
          delete: () => Promise.resolve(true),
        },
        'Secret Service',
      );
      const cell = credentialCell(store, root, 'codex', (state) =>
        states.push(state),
      );
      let child: ReturnType<typeof spawn> | undefined;

      try {
        await writeFile(
          entry,
          JSON.stringify({ accessToken: 'first', accountId: 'fixture' }),
        );

        const rotation = cell.locked(async (lease) => {
          await lease.read();
          await lease.save({ accessToken: 'next', accountId: 'fixture' });
        });

        await started.promise;

        const waiting = withCredentialLock(root, 'codex', store.name, () => {
          throw new Error('expired waiter must never enter');
        }).catch((error: unknown) => error);

        await rotation;
        expect(states).toEqual(['unsaved']);
        expect(await waiting).toBeInstanceOf(CredentialStoreBusy);

        child = spawn(
          process.execPath,
          [
            fileURLToPath(
              new URL('./credential_lock_child.ts', import.meta.url),
            ),
            root,
            entry,
          ],
          { stdio: ['ignore', 'pipe', 'pipe'] },
        );

        assert(child.stdout !== null);
        assert(child.stderr !== null);

        const stopped = once(child, 'exit');
        const observed = Promise.withResolvers<void>();
        let output = '';
        let errors = '';

        child.stdout.on('data', (chunk: Buffer) => {
          output += chunk.toString();

          if (output.includes('\n')) {
            observed.resolve();
          }
        });

        child.stderr.on('data', (chunk: Buffer) => {
          errors += chunk.toString();
        });

        await Promise.race([
          observed.promise,
          stopped.then(() => {
            throw new Error(`child exited: ${errors}`);
          }),
          new Promise<never>((_, reject) => {
            const timer = setTimeout(
              () => reject(new Error('child did not observe lock')),
              5000,
            );

            timer.unref();
          }),
        ]);
        expect(output).toBe('held:true\n');
        finish.resolve();

        const [code] = await stopped;

        expect(errors).toBe('');
        expect(code).toBe(0);
        expect(output).toBe('held:true\nrefreshed\n');
        expect(states).toEqual(['unsaved', 'saved']);
        expect(JSON.parse(await readFile(entry, 'utf8'))).toEqual({
          accessToken: 'third',
          accountId: 'fixture',
        });
      } finally {
        finish.resolve();

        if (child !== undefined && child.exitCode === null) {
          const stopped = once(child, 'exit');

          child.kill();
          await stopped;
        }

        await withCredentialLock(root, 'codex', store.name, () =>
          Promise.resolve(),
        );
        await rm(root, { recursive: true, force: true });
      }
    },
    SECRET_TIMEOUT + 15_000,
  );
});
