import { describe, expect, test } from 'bun:test';
import assert from 'node:assert';
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { type AcpRun, runAcp } from '../src/acp_agent.ts';
import { killSpawnedGroups } from '../src/platform/process.ts';
import { serveChord } from '../src/server/server.ts';
import type { LeaveExit } from '../src/session/leaving.ts';
import {
  openSession,
  type OpenSessionOptions,
  type Session,
} from '../src/session/session.ts';
import { type AcpClient, clientOverStreams } from './fixtures/acp_client.ts';
import { fakeAgentCommand } from './fixtures/fake.ts';
import { until } from './session/conversation_fake.ts';

interface Report {
  readonly sessionId: string;
  readonly title: string;
  readonly state: { state: string; stopReason?: string };
  readonly _meta: { 'chord/agent': Record<string, unknown> };
}

function reportOf(client: AcpClient, parent: string, title: string) {
  return client
    .updates(parent)
    .filter((update) => update.sessionUpdate === 'subagent_update')
    .map((update) => update as unknown as Report)
    .findLast((update) => update.title === title);
}

async function reported(
  client: AcpClient,
  parent: string,
  title: string,
  holds: (report: Report) => boolean,
): Promise<Report> {
  await until(() => {
    const report = reportOf(client, parent, title);

    return report !== undefined && holds(report);
  });

  return reportOf(client, parent, title)!;
}

function groupAlive(pid: number): boolean {
  try {
    return process.kill(-pid, 0);
  } catch {
    return false;
  }
}

async function withChildren(
  body: (
    client: AcpClient,
    newSession: () => Promise<string>,
    lines: readonly string[],
    context: { cwd: string; run: AcpRun; exits: readonly LeaveExit[] },
  ) => Promise<void>,
  open: (options: OpenSessionOptions) => Promise<Session> = openSession,
  exitCode = 0,
): Promise<void> {
  const cwd = await mkdtemp(join(tmpdir(), 'chord-children-tester-'));
  const { client, input, output, end } = clientOverStreams();
  const exits: LeaveExit[] = [];
  const pids: number[] = [];
  const lines: string[] = [];

  const run = runAcp({
    input,
    output,
    stderr: (line) => lines.push(line),
    exit: (how) => exits.push(how),
    agent: 'fake',
    version: '1.2.3',
    home: cwd,
    configHome: join(cwd, 'config'),
    stateDir: join(cwd, 'state'),
    server: serveChord(),
    open: async (options) => {
      const session = await open(options);

      pids.push(...session.agentPids);

      return session;
    },
    place: () =>
      Promise.resolve({
        cwd,
        startupOf: () => ({ agentCommand: fakeAgentCommand() }),
        mcpServers: [],
        mcpIgnored: [],
        runtimes: ['fake'],
      }),
  });

  try {
    await client.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: { subagents: {} },
    });
    await body(
      client,
      async () => {
        const answer = await client.request('session/new', {
          cwd,
          mcpServers: [],
        });

        expect(answer.error).toBeUndefined();
        assert(typeof answer.result?.sessionId === 'string');

        return answer.result.sessionId;
      },
      lines,
      { cwd, run, exits },
    );
  } finally {
    end();

    try {
      await until(() => exits.length > 0, 20_000);
      await until(() => !pids.some(groupAlive));

      expect(exits).toEqual([{ code: exitCode }]);
    } finally {
      // Rescue only after observing cleanup; it cannot turn a leak green.
      killSpawnedGroups();
      await rm(cwd, { recursive: true, force: true });
    }
  }
}

const prompt = (client: AcpClient, sessionId: string, text: string) =>
  client.send('session/prompt', {
    sessionId,
    prompt: [{ type: 'text', text }],
  });

describe('CHD-581 tester: children across session boundaries', () => {
  test('a crash cancels a command blocked reading teams, and exits uncleanly', () =>
    withChildren(
      async (client, newSession, _lines, { cwd, run, exits }) => {
        const main = await newSession();
        const pipe = join(cwd, '.chord', 'teams', 'held.md');

        await mkdir(join(cwd, '.chord', 'teams'), { recursive: true });

        expect(spawnSync('mkfifo', [pipe]).status).toBe(0);

        const command = prompt(client, main, '/team');

        await client.request('session/list', {});
        void run.leave({ kind: 'crash' });

        expect((await client.answerTo(command)).result?.stopReason).toBe(
          'cancelled',
        );

        await until(() => exits.length > 0);
        await writeFile(pipe, '---\n');

        expect(
          client.messages.filter(
            (message) => message.id === command && message.method === undefined,
          ),
        ).toHaveLength(1);
        expect(client.said(main)).toBe('');
      },
      openSession,
      1,
    ));

  test('a task of a child cannot ask as that child, while a genuine main ask still works', async () => {
    await withChildren(
      async (client, newSession, lines) => {
        const main = await newSession();

        await client.answerTo(prompt(client, main, 'team'));
        await until(() => lines.some((line) => line.includes('does not know')));

        expect(
          client.messages.some(
            (message) => message.method === 'session/request_permission',
          ),
        ).toBe(false);

        const other = await newSession();
        const turn = prompt(client, other, 'permission');
        const ask = await client.until(
          (message) =>
            message.method === 'session/request_permission' &&
            message.params?.sessionId === other,
        );

        client.respond(ask.id!, {
          outcome: { outcome: 'selected', optionId: 'allow' },
        });

        expect((await client.answerTo(turn)).result?.stopReason).toBe(
          'end_turn',
        );
        expect(client.said(other)).toContain('Permission: allow');
      },
      async (options) => {
        await mkdir(join(options.cwd, '.chord', 'teams'), { recursive: true });
        await writeFile(
          join(options.cwd, '.chord', 'teams', 'bugfix.md'),
          await readFile(
            new URL('./fixtures/teams/fake/bugfix.md', import.meta.url),
          ),
        );

        return openSession({
          ...options,
          agentCommand: fakeAgentCommand(
            undefined,
            '--tester-plays',
            'taskaskas',
          ),
        });
      },
    );
  });

  test('closing one main leaves the other same-named child running and cancellable', () =>
    withChildren(async (client, newSession) => {
      const first = await newSession();
      const second = await newSession();

      await Promise.all([
        client.answerTo(prompt(client, first, 'agentcost')),
        client.answerTo(prompt(client, second, 'agentcost')),
      ]);

      const running = (report: Report) => report.state.state === 'running';
      const a = await reported(client, first, 'parser', running);
      const b = await reported(client, second, 'parser', running);

      expect(a.sessionId).not.toBe(b.sessionId);
      expect(a.sessionId.startsWith(`${first}/`)).toBe(true);
      expect(b.sessionId.startsWith(`${second}/`)).toBe(true);
      expect(
        (await client.request('session/close', { sessionId: first })).error,
      ).toBeUndefined();

      await reported(
        client,
        first,
        'parser',
        (report) => report._meta['chord/agent']['closed'] === true,
      );

      expect(reportOf(client, second, 'parser')?.state.state).toBe('running');
      client.notify('session/cancel', { sessionId: b.sessionId });

      const stopped = await reported(
        client,
        second,
        'parser',
        (report) => report.state.stopReason === 'cancelled',
      );

      expect(stopped._meta['chord/agent']['closed']).toBeUndefined();
      expect(
        (await client.answerTo(prompt(client, second, 'hello'))).error,
      ).toBeUndefined();
    }));

  test("a late answer after child cancel cannot settle another session's identical ask", () =>
    withChildren(async (client, newSession) => {
      const first = await newSession();
      const second = await newSession();
      const turns = [
        prompt(client, first, 'agentsquiet'),
        prompt(client, second, 'agentsquiet'),
      ];
      const askFor = (parent: string) =>
        client.until(
          (message) =>
            message.method === 'session/request_permission' &&
            String(message.params?.sessionId).startsWith(`${parent}/`),
        );
      const [a, b] = await Promise.all([askFor(first), askFor(second)]);

      expect(a.id).not.toBe(b.id);
      expect(a.params?.toolCall).toEqual(b.params?.toolCall);

      const child = String(a.params?.sessionId);

      client.notify('session/cancel', { sessionId: child });
      await client.until(
        (message) =>
          message.method === '$/cancel_request' &&
          message.params?.requestId === a.id,
      );
      await reported(
        client,
        first,
        'docs',
        (report) => report.state.stopReason === 'cancelled',
      );
      client.respond(a.id!, {
        outcome: { outcome: 'selected', optionId: 'allow' },
      });

      expect(reportOf(client, second, 'docs')?.state.state).toBe(
        'requires_action',
      );
      expect(client.said(child)).not.toContain('Permission: allow');
      client.respond(b.id!, {
        outcome: { outcome: 'selected', optionId: 'deny' },
      });

      await Promise.all(turns.map((id) => client.answerTo(id)));
      await until(() =>
        client.said(String(b.params?.sessionId)).includes('Permission: deny'),
      );

      expect(client.said(child)).not.toContain('Permission: allow');
    }));

  test('clear after a failed child start removes its failure without changing identity', async () => {
    let opens = 0;

    await withChildren(
      async (client, newSession) => {
        const main = await newSession();

        await client.answerTo(prompt(client, main, 'agentcost'));

        const failed = await reported(
          client,
          main,
          'parser',
          (report) => typeof report._meta['chord/agent']['failed'] === 'string',
        );

        await client.answerTo(prompt(client, main, 'agentclearonly'));

        const fresh = await reported(
          client,
          main,
          'parser',
          (report) =>
            report.state.state === 'idle' &&
            report._meta['chord/agent']['failed'] === undefined,
        );

        expect(fresh.sessionId).toBe(failed.sessionId);
        expect(fresh._meta['chord/agent']['gone']).toBeUndefined();
      },
      (options) => {
        opens += 1;

        return openSession(
          opens === 2
            ? { ...options, agentCommand: ['chord-missing-fixture-command'] }
            : options,
        );
      },
    );
  });

  test('closing main stops a child whose fake agent never answers startup', async () => {
    let opens = 0;
    let pidFile = '';

    await withChildren(
      async (client, newSession) => {
        const main = await newSession();
        const turn = prompt(client, main, 'agentcost');

        await until(() => pidFile !== '' && existsSync(pidFile));

        const pid = Number(await readFile(pidFile, 'utf8'));

        expect(groupAlive(pid)).toBe(true);
        expect(
          (await client.request('session/close', { sessionId: main })).error,
        ).toBeUndefined();

        await client.answerTo(turn);
        await until(() => !groupAlive(pid));
        await reported(
          client,
          main,
          'parser',
          (report) => report._meta['chord/agent']['closed'] === true,
        );
      },
      async (options) => {
        opens += 1;

        if (opens !== 2) {
          return openSession(options);
        }

        pidFile = join(options.cwd, 'starting.pid');

        const wrapper = join(options.cwd, 'starting.ts');
        const [bun, fake] = fakeAgentCommand();

        await writeFile(
          wrapper,
          `import { writeFileSync } from 'node:fs';\n` +
            `writeFileSync(${JSON.stringify(pidFile)}, String(process.pid));\n` +
            `await import(${JSON.stringify(fake)});\n`,
        );

        return openSession({
          ...options,
          agentCommand: [bun!, wrapper, '--hang', 'start'],
        });
      },
    );
  });
});
