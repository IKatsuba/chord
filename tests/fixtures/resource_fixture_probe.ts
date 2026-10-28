/** Source/compiled fixture dispatch proof with an empty PATH and no ACP/model turn. */
import process from 'node:process';
import { createResources } from '../../src/platform/resources.ts';
import { resourceSourceMode } from '../../src/platform/resource_fixture.ts';

const mode = resourceSourceMode(process.env['CHORD_RESOURCE_FIXTURE']);

if (mode !== 'fixture') {
  throw new Error('Fixture mode is required by this probe.');
}

const read = createResources({ collectors: mode });

process.stdout.write(
  JSON.stringify(
    await read(
      undefined,
      { cwd: '/fixture/project', commandOf: () => undefined },
      new AbortController().signal,
    ),
  ),
);
