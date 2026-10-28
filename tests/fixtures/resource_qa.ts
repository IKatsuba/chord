/** Reproducible Resources captures: isolated settings/state and an explicit scripted ACP command. */
import { spawnSync } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { quote } from 'shell-quote';
import { chord, qaPlace } from '../../scripts/dev/tools.ts';
import { resourceFixtureCase } from '../../src/platform/resource_fixture.ts';
import { fakeAgentCommand } from './fake.ts';

export async function resourceQa(
  value: string | undefined,
  run: (argv: readonly string[], env: NodeJS.ProcessEnv) => number,
): Promise<number> {
  const scenario = resourceFixtureCase(value);
  const directory = `/tmp/chord-qa.chd533-resources-${scenario}`;
  const config = join(directory, '.config');

  qaPlace(directory);
  await mkdir(join(config, 'chord'), { recursive: true });

  const env = {
    ...process.env,
    XDG_CONFIG_HOME: config,
    XDG_STATE_HOME: join(directory, '.state'),
    CHORD_RESOURCE_FIXTURE: 'true',
    CHORD_FAKE_RESOURCE_CASE: scenario,
  };

  return chord(
    false,
    [
      'codex',
      '--agent-command',
      quote(fakeAgentCommand('resources')),
      '-C',
      directory,
    ],
    (argv) => run(argv, env),
    true,
  );
}

if (import.meta.main) {
  process.exitCode = await resourceQa(
    process.argv[2],
    ([command, ...args], env) => {
      const child = spawnSync(command!, args, {
        cwd: fileURLToPath(new URL('../..', import.meta.url)),
        env,
        stdio: 'inherit',
      });

      return child.status ?? 1;
    },
  );
}
