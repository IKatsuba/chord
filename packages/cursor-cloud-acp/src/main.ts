/**
 * The package's wiring: the real Port, the keychain and the terminal, and
 * the command line's word to what serves it. The only module that imports
 * cursor.ts and keyring.ts.
 */
import { cursorPort } from './cursor.ts';
import { keyringStore } from './keyring.ts';
import { type LoginContext, login, logout, status } from './login.ts';

const COMMANDS = { login, logout, status } as const;

/** Runs the command `args` names and answers its exit status. */
export function main(args: readonly string[]): Promise<number> {
  const [word, ...rest] = args;

  if (word === undefined) {
    // Serving ACP lands with serve.ts (CHD-622, U6).
    process.stderr.write('cursor-cloud-acp: serving ACP is not built yet\n');

    return Promise.resolve(1);
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
