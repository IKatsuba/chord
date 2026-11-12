/**
 * The package's wiring: the real Port, the keychain, git and the terminal,
 * and the command line's word to what serves it. The only module that
 * imports cursor.ts and keyring.ts.
 */
import { createRequire } from 'node:module';
import { cursorPort } from './cursor.ts';
import { keyringStore } from './keyring.ts';
import { type LoginContext, login, logout, status } from './login.ts';
import { git } from './repo.ts';
import { serveStdio } from './serve.ts';

const COMMANDS = { login, logout, status } as const;

/** The package's version, for the sign-in line naming this very version. */
function version(): string {
  return (
    createRequire(import.meta.url)('../package.json') as { version: string }
  ).version;
}

/** Runs the command `args` names and answers its exit status. */
export function main(args: readonly string[]): Promise<number> {
  const [word, ...rest] = args;

  if (word === undefined) {
    const store = keyringStore();

    return serveStdio({
      port: cursorPort(),
      git,
      credentials: () => ({ env: process.env, store, now: Date.now }),
      version: version(),
    });
  }

  if (!Object.hasOwn(COMMANDS, word) || rest.length > 0) {
    process.stderr.write('Usage: cursor-cloud-acp [login | logout | status]\n');

    return Promise.resolve(2);
  }

  const context: LoginContext = {
    port: cursorPort(),
    store: keyringStore(),
    env: process.env,
    print: (line) => void process.stdout.write(`${line}\n`),
    fail: (line) => void process.stderr.write(`${line}\n`),
  };

  return COMMANDS[word as keyof typeof COMMANDS](context);
}
