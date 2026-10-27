/** Source/compiled fixture dispatch proof with an empty PATH and no ACP/model turn. */
import process from 'node:process';
import { setImmediate } from 'node:timers/promises';
import { createResources } from '../../src/platform/resources.ts';
import { resourceSourceMode } from '../../src/platform/resource_fixture.ts';

const mode = resourceSourceMode(process.env['CHORD_RESOURCE_FIXTURE']);

if (mode !== 'fixture') {
  throw new Error('Fixture mode is required by this probe.');
}

const resources = createResources({
  stateDirectory: process.argv[2]!,
  collectors: mode,
});

try {
  await resources.start();

  for (const agent of ['codex', 'claude']) {
    resources.retain(
      { agent, cwd: '/fixture/project' },
      new AbortController().signal,
    );
  }

  const deadline = performance.now() + 5000;

  while (
    resources.read().unbound.length !== 2 &&
    performance.now() < deadline
  ) {
    await setImmediate();
  }

  const facts = resources.read();

  if (
    facts.unbound.length !== 2 ||
    facts.unbound.some((source) => source.source !== 'fixture')
  ) {
    throw new Error('Only explicit fixture sources may answer.');
  }

  process.stdout.write(JSON.stringify(facts));
} finally {
  await resources.close();
}
