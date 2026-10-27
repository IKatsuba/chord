/** Isolated selected-team captures; every candidate command is explicitly fake. */
import { spawnSync } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { quote } from 'shell-quote';
import { chord, qaPlace } from '../../scripts/dev/tools.ts';
import { fakeAgentCommand } from './fake.ts';

export const SELECTION_CASES = [
  'normal',
  'members',
  'refused',
  'soft',
  'long',
  'receipt',
] as const;

export async function selectedTeamQa(
  value: string | undefined,
  run: (argv: readonly string[], env: NodeJS.ProcessEnv) => number,
): Promise<number> {
  const scenario =
    SELECTION_CASES.find((scenario) => scenario === value) ?? 'normal';
  const directory = `/tmp/chord-qa.chd533-selection-${scenario}`;
  const config = join(directory, '.config');

  qaPlace(directory);
  await mkdir(join(config, 'chord'), { recursive: true });
  await mkdir(join(directory, '.chord/teams'), { recursive: true });
  await writeFile(
    join(config, 'chord/settings.json'),
    JSON.stringify({
      agents: {
        fake: { command: fakeAgentCommand() },
        codex: { command: fakeAgentCommand('selectedteam') },
        claude: {
          command: fakeAgentCommand(
            undefined,
            ...(scenario === 'refused'
              ? ['--no-modes']
              : scenario === 'soft'
                ? ['--refuse-config']
                : []),
          ),
        },
      },
      teamSelection: { intent: 'balanced' },
    }),
  );
  await writeFile(
    join(directory, '.chord/teams/fixture.md'),
    `---
description: Selected composition visual fixture
lead:
  agent: codex
  model: fake-large
  mode: default
members:
  - name: reviewer
    role: Review the selected work
    agent: claude
    instructions: Preserve the review scope and exact permission requirements.
---
Keep all instructions and project handoffs unchanged.
`,
  );

  if (scenario === 'receipt') {
    const { selectedReceiptFixture } = await import('./selected_receipt.ts');

    await selectedReceiptFixture(directory, join(directory, '.state/chord'));
  }

  const env = {
    ...process.env,
    XDG_CONFIG_HOME: config,
    XDG_STATE_HOME: join(directory, '.state'),
    CHORD_RESOURCE_FIXTURE: 'true',
    CHORD_FAKE_RESOURCE_CASE: scenario === 'long' ? 'long' : 'partial',
    CHORD_FAKE_SELECTION_CASE: scenario,
  };

  return chord(
    false,
    [
      'codex',
      '--agent-command',
      quote(fakeAgentCommand('selectedteam')),
      '-C',
      directory,
    ],
    (argv) => run(argv, env),
    true,
  );
}

if (import.meta.main) {
  process.exitCode = await selectedTeamQa(
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
