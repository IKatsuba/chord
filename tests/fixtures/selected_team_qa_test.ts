import { expect, test } from 'bun:test';
import { readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { selectedTeamQa } from './selected_team_qa.ts';
import { fakeAgentCommand } from './fake.ts';

for (const scenario of ['normal', 'members', 'refused', 'soft', 'long']) {
  test(`selection QA ${scenario} explicitly isolates every candidate runtime and collector`, async () => {
    const directory = `/tmp/chord-qa.chd533-selection-${scenario}`;

    try {
      let launches = 0;
      const result = await selectedTeamQa(scenario, (argv, env) => {
        launches++;
        expect(argv).toContain('process.env.CHORD_RESOURCE_FIXTURE:"true"');
        expect(env.CHORD_RESOURCE_FIXTURE).toBe('true');
        expect(env.XDG_CONFIG_HOME).toBe(join(directory, '.config'));
        expect(env.XDG_STATE_HOME).toBe(join(directory, '.state'));
        expect(env.CHORD_FAKE_SELECTION_CASE).toBe(scenario);

        return 0;
      });

      expect(result).toBe(0);
      expect(launches).toBe(1);

      const settings = JSON.parse(
        await readFile(join(directory, '.config/chord/settings.json'), 'utf8'),
      );

      for (const runtime of ['fake', 'codex', 'claude']) {
        expect(settings.agents[runtime].command.slice(0, 2)).toEqual(
          fakeAgentCommand().slice(0, 2),
        );
      }
    } finally {
      await rm(directory, { recursive: true });
    }
  });
}
