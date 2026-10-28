/** Compiled public-library characterization; every supplied executable is fake. */
import process from 'node:process';
import { collectCodexResources } from '../../src/session/codex_resources.ts';
import { resolveResourceExecutable } from '../../src/platform/resource_executable.ts';
import { COLLECTOR_BOUNDS } from '../../src/platform/resource_process.ts';

const [path, scenario] = process.argv.slice(2);

if (scenario === 'resolve') {
  process.stdout.write(
    JSON.stringify(
      await resolveResourceExecutable('codex', {
        cwd: process.cwd(),
        signal: new AbortController().signal,
        customCommand: false,
      }),
    ),
  );
} else if (path !== undefined) {
  try {
    const result = await collectCodexResources([path, 'app-server'], {
      cwd: process.cwd(),
      signal:
        scenario === 'abort'
          ? AbortSignal.timeout(1500)
          : new AbortController().signal,
      bounds: {
        ...COLLECTOR_BOUNDS,
        totalMs: 5000,
        initializeMs: scenario === 'abort' ? 4000 : 1500,
        closeMs: 100,
        termMs: 100,
        killMs: 1500,
      },
    });

    process.stdout.write(JSON.stringify(result));
  } catch {
    process.stdout.write(
      JSON.stringify({ unavailable: 'Fixture read failed.' }),
    );

    process.exitCode = 1;
  }
}
