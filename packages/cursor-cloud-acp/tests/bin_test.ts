import { expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const BIN = fileURLToPath(new URL('../src/bin.ts', import.meta.url));

/** bin.ts run as if on Node `version`: its status and stderr. */
function runOn(version: string) {
  const child = spawnSync(
    process.execPath,
    [
      '-e',
      `Object.defineProperty(process.versions, 'node', { value: ${JSON.stringify(version)} }); await import(${JSON.stringify(BIN)});`,
    ],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
  );

  return { status: child.status, stderr: child.stderr, stdout: child.stdout };
}

test.each(['22.12.0', '21.9.0', '18.20.4', '8.0.0'])(
  'Node %s gets one line and status 1, before main is imported',
  (version) => {
    expect(runOn(version)).toEqual({
      status: 1,
      stderr: `cursor-cloud-acp needs Node 22.13 or newer; this is Node ${version}.\n`,
      stdout: '',
    });
  },
);

test.each(['22.13.0', '22.20.1', '24.0.0'])(
  'Node %s passes the gate to main',
  (version) => {
    expect(runOn(version).stderr).not.toContain('needs Node');
  },
);
