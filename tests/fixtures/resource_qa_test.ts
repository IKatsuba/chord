import { expect, test } from 'bun:test';
import { rm } from 'node:fs/promises';
import { resourceQa } from './resource_qa.ts';

test('Resources capture launcher isolates fixture state and supplies only the scripted ACP command', async () => {
  const directory = '/tmp/chord-qa.chd533-resources-timeout';
  let argv: readonly string[] = [];
  let env: NodeJS.ProcessEnv = {};

  try {
    expect(
      await resourceQa('timeout', (command, environment) => {
        argv = command;
        env = environment;

        return 7;
      }),
    ).toBe(7);
    expect(argv).toContain('process.env.CHORD_RESOURCE_FIXTURE:"true"');
    expect(argv).toContain('--agent-command');
    expect(
      argv.some((argument) => argument.includes('fake_agent/main.ts')),
    ).toBe(true);
    expect(env['XDG_STATE_HOME']).toBe(`${directory}/.state`);
    expect(env['CHORD_RESOURCE_FIXTURE']).toBe('true');
    expect(env['CHORD_FAKE_RESOURCE_CASE']).toBe('timeout');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
