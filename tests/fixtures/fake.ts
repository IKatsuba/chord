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
