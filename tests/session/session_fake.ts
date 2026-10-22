/**
 * The session on the fake agent, and the steps its tests share:
 * `session_test.ts` and the file split from it (CHD-501).
 */
import { execFile } from 'node:child_process';
import { expect } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { openSession, type Session } from '../../src/session/session.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { run } from '../fixtures/recorder.ts';

export function isAlive(pid: number): Promise<boolean> {
  return new Promise((resolve) => {
    execFile('ps', ['-p', String(pid)], (error) => resolve(error === null));
  });
}

/**
 * Opens a session on the fake agent, hands it to `body`, then closes it and
 * proves the agent process is gone, whatever `body` did.
 */
export async function withSession(
  body: (session: Session) => Promise<void>,
  scenario?: string,
  ...flags: string[]
) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-session-'));
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand(scenario, ...flags),
  });
  const pids = [...session.agentPids];

  try {
    expect(pids.length).toStrictEqual(1);
    await body(session);
  } finally {
    await session.close();
    expect(session.agentPids.size).toStrictEqual(0);

    for (const pid of pids) {
      expect(!(await isAlive(pid)), `agent ${pid} still running`).toBeTruthy();
    }

    await rm(dir, { recursive: true });
  }
}

/** The updates a prompt brought until the agent answered it. */
export async function collect(session: Session, text: string) {
  return (await run(session, text)).updates;
}

/** The tool calls and updates to them among `updates`. */
export function calls(updates: readonly SessionUpdate[]) {
  return updates.flatMap((update) =>
    update.sessionUpdate === 'tool_call' ||
    update.sessionUpdate === 'tool_call_update'
      ? [update]
      : [],
  );
}
