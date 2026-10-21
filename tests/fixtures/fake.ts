import { fileURLToPath } from 'node:url';
import { execPath } from '../../src/platform/process.ts';

/**
 * The argv that starts the fake agent from any working directory: the
 * runtime running chord, and the script's absolute path, from which Bun
 * resolves its imports. `flags` go after the script, such as `--no-usage`.
 */
export function fakeAgentCommand(
  scenario?: string,
  ...flags: string[]
): string[] {
  return [
    execPath(),
    fileURLToPath(new URL('./fake_agent/main.ts', import.meta.url)),
    ...(scenario ? ['--scenario', scenario] : []),
    ...flags,
  ];
}

/**
 * `command`, started only once the file `gate` exists, so an agent can be
 * kept starting for as long as a test needs. It gives up once `gate`'s
 * directory is gone or after 30 s: an agent chord never let start is not
 * always stopped with the window, and the loop must not outlive the test.
 */
export function gatedCommand(
  gate: string,
  command: readonly string[],
): string[] {
  return [
    'sh',
    '-c',
    'i=0; while [ ! -e "$0" ]; do ' +
      '[ -d "${0%/*}" ] && [ "$i" -lt 600 ] || exit 1; ' +
      'i=$((i + 1)); sleep 0.05; done; exec "$@"',
    gate,
    ...command,
  ];
}
