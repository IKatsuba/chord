import { describe, expect, test } from 'bun:test';
import process from 'node:process';
import { killSpawnedGroups, spawnGroup } from '../../src/platform/process.ts';
import { until } from '../session/conversation_fake.ts';

const NO_PIPES = {
  stdin: 'ignore',
  stdout: 'ignore',
  stderr: 'ignore',
} as const;

function group(script: string) {
  return spawnGroup('sh', ['-c', script], {
    cwd: process.cwd(),
    ...NO_PIPES,
  });
}

describe('the registry of spawned groups', () => {
  test('holds a running group and kills it', async () => {
    const running = group('sleep 60');

    await running.started;

    expect(killSpawnedGroups()).toContain(running.pid ?? -1);

    await running.exit;
    await until(() => !running.alive());

    expect(killSpawnedGroups()).not.toContain(running.pid ?? -1);
  });

  test('drops a group once its leader exited and nothing is left', async () => {
    const short = group('exit 0');

    await short.exit;
    await until(() => !short.alive());

    expect(killSpawnedGroups()).not.toContain(short.pid ?? -1);
  });

  test('keeps a group whose leader left a process behind', async () => {
    const leader = group('sleep 60 & exit 0');

    await leader.exit;

    expect(leader.alive()).toBe(true);
    expect(killSpawnedGroups()).toContain(leader.pid ?? -1);

    await until(() => !leader.alive());

    expect(killSpawnedGroups()).not.toContain(leader.pid ?? -1);
  });

  test('a program that did not start is never held', async () => {
    const before = killSpawnedGroups().length;
    const none = spawnGroup('/no/such/program', [], {
      cwd: process.cwd(),
      ...NO_PIPES,
    });

    await expect(none.started).rejects.toThrow();

    expect(killSpawnedGroups().length).toBe(before);
  });
});
