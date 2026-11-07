/**
 * `chord acp` as a client starts it: spawned, on real pipes, its exit and its
 * agent's process group looked at from outside.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import assert from 'node:assert';
import { type ChildProcess, spawn, spawnSync } from 'node:child_process';
import { closeSync, constants, openSync, readSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { quote } from 'shell-quote';
import { byHandNote } from '../src/acp_agent.ts';
import { execPath } from '../src/platform/process.ts';
import { readRecords } from '../src/session/sessions.ts';
import { AcpClient } from './fixtures/acp_client.ts';
import { until } from './session/conversation_fake.ts';

const MAIN = fileURLToPath(new URL('../src/main.tsx', import.meta.url));
const AGENT = fileURLToPath(
  new URL('./fixtures/pid_agent.ts', import.meta.url),
);
const CRASH = fileURLToPath(
  new URL('./fixtures/crash_preload.ts', import.meta.url),
);
const SESSION = '11111111-2222-4333-8444-555555555555';

interface Chord {
  readonly child: ChildProcess;
  readonly dir: string;
  readonly client: AcpClient;
  readonly stderr: () => string;
  /** How it ended, once it has. */
  readonly ended: Promise<{ code: number | null; signal: string | null }>;
  /** The agent's process group's id, once the agent has started. */
  group(): Promise<number>;
  /** A session on the fake agent; its id. */
  newSession(): Promise<string>;
}

const dirs: string[] = [];
const chords: ChildProcess[] = [];

afterEach(async () => {
  for (const child of chords.splice(0)) {
    child.kill('SIGKILL');
  }

  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

function alive(group: number): boolean {
  try {
    return process.kill(-group, 0);
  } catch (error) {
    // macOS refuses a group of only processes not reaped yet; none is ESRCH.
    return (error as NodeJS.ErrnoException).code === 'EPERM';
  }
}

async function scratch(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), 'chord-acp-process-'));

  dirs.push(dir);

  return dir;
}

/** Starts chord on the fake agent; `stdio` is its stdin, stdout and stderr. */
async function start({
  stdout = 'pipe',
  stderr = 'pipe',
  args = [],
  flags = [],
}: {
  stdout?: 'pipe' | number;
  stderr?: 'pipe' | number;
  args?: readonly string[];
  flags?: readonly string[];
} = {}): Promise<Chord> {
  const dir = await scratch();
  const pidFile = join(dir, 'agent.pid');
  const child = spawn(
    execPath(),
    [
      ...args,
      MAIN,
      'acp',
      'fake',
      '--agent-command',
      quote([execPath(), AGENT, pidFile, '--session-id', SESSION, ...flags]),
    ],
    {
      cwd: dir,
      stdio: ['pipe', stdout, stderr],
      env: {
        ...process.env,
        XDG_STATE_HOME: join(dir, 'state'),
        XDG_CONFIG_HOME: join(dir, 'config'),
      },
    },
  );

  chords.push(child);

  let said = '';

  child.stderr?.setEncoding('utf8').on('data', (text: string) => {
    said += text;
  });

  child.stdin?.on('error', () => {});

  const client = new AcpClient(
    (line) => {
      child.stdin?.write(line);
    },
    (child.stdout ?? (async function* () {})()) as AsyncIterable<Uint8Array>,
  );

  return {
    child,
    dir,
    client,
    stderr: () => said,
    ended: new Promise((resolve) => {
      child.once('exit', (code, signal) => resolve({ code, signal }));
    }),
    group: async () => {
      let pid = 0;

      await until(() => {
        try {
          pid = Number(spawnSync('cat', [pidFile]).stdout.toString());
        } catch {
          pid = 0;
        }

        return pid > 0;
      }, 20_000);

      return pid;
    },
    newSession: async () => {
      await client.request('initialize', {
        protocolVersion: 1,
        clientCapabilities: {},
      });

      const { result } = await client.request('session/new', {
        cwd: dir,
        mcpServers: [],
      });

      return result?.sessionId as string;
    },
  };
}

const promptOf = (sessionId: string, text: string) => ({
  sessionId,
  prompt: [{ type: 'text', text }],
});

/**
 * Every line on stdout is the protocol, read to its end: an exit can come
 * ahead of the pipe's last bytes.
 */
async function parses(client: AcpClient): Promise<void> {
  await until(() => client.closed);

  for (const line of client.lines) {
    expect(() => JSON.parse(line) as unknown).not.toThrow();
  }
}

/** A named pipe opened with nobody reading it, the read end held here. */
function pipeNobodyReads(dir: string): { read: number; write: number } {
  const path = join(dir, 'stdout.fifo');

  expect(spawnSync('mkfifo', [path]).status).toBe(0);

  const read = openSync(path, constants.O_RDONLY | constants.O_NONBLOCK);
  const write = openSync(path, constants.O_WRONLY);

  return { read, write };
}

describe('how it ends', () => {
  test('eof idle: exit 0, group gone', async () => {
    const chord = await start();

    await chord.newSession();

    const group = await chord.group();

    chord.child.stdin?.end();

    expect(await chord.ended).toEqual({ code: 0, signal: null });

    await until(() => !alive(group));
    await parses(chord.client);
  }, 40_000);

  test('eof with an ask: exit 0, the turn in the record, no answer', async () => {
    const chord = await start();
    const sessionId = await chord.newSession();
    const group = await chord.group();
    const prompt = chord.client.send(
      'session/prompt',
      promptOf(sessionId, 'permission'),
    );

    await chord.client.until(
      (message) => message.method === 'session/request_permission',
    );

    chord.child.stdin?.end();

    expect(await chord.ended).toEqual({ code: 0, signal: null });

    await until(() => !alive(group));
    await parses(chord.client);

    expect(
      chord.client.messages.some(
        (message) => message.id === prompt && !message.method,
      ),
    ).toBe(false);

    const [record] = await readRecords(join(chord.dir, 'state', 'chord'));
    const held = record ?? (await readRecords(join(chord.dir, 'state')))[0];

    assert(held !== undefined);
    expect(await readFile(held.path, 'utf8')).toContain('"permission"');
  }, 40_000);

  test('client killed, so both pipes close: chord and group gone', async () => {
    const chord = await start();

    await chord.newSession();

    const group = await chord.group();

    chord.child.stdin?.destroy();
    chord.child.stdout?.destroy();

    await chord.ended;
    await until(() => !alive(group));
  }, 40_000);

  for (const signal of ['SIGTERM', 'SIGINT', 'SIGHUP'] as const) {
    test(`${signal} in a turn: cancelled first, dies by it, group gone`, async () => {
      const chord = await start();
      const sessionId = await chord.newSession();
      const group = await chord.group();
      const prompt = chord.client.send(
        'session/prompt',
        promptOf(sessionId, 'long'),
      );

      await until(() => chord.client.said(sessionId) !== '');

      chord.child.kill(signal);

      expect((await chord.client.answerTo(prompt)).result?.stopReason).toBe(
        'cancelled',
      );
      expect(await chord.ended).toEqual({ code: null, signal });

      await until(() => !alive(group));
      await parses(chord.client);
    }, 40_000);
  }

  test('a signal while stdout is blocked: dies by it inside its bounds', async () => {
    const dir = await scratch();
    const { read, write } = pipeNobodyReads(dir);
    const chord = await start({ stdout: write });

    closeSync(write);

    const client = chord.child.stdin;

    assert(client !== null);

    const send = (message: object) =>
      client.write(`${JSON.stringify({ jsonrpc: '2.0', ...message })}\n`);

    // Read only until the session is up; from then, nobody reads.
    const seen = Buffer.alloc(1 << 16);
    let held = '';
    const answered = (id: number) =>
      until(() => {
        try {
          held += seen.toString('utf8', 0, readSync(read, seen));
        } catch {
          // Nothing to read yet.
        }

        return held.includes(`"id":${id}`);
      }, 20_000);

    send({
      id: 1,
      method: 'initialize',
      params: { protocolVersion: 1, clientCapabilities: {} },
    });
    await answered(1);
    send({
      id: 2,
      method: 'session/new',
      params: { cwd: chord.dir, mcpServers: [] },
    });
    await answered(2);

    const group = await chord.group();

    send({
      id: 3,
      method: 'session/prompt',
      params: promptOf(SESSION, 'flood'),
    });

    await new Promise((resolve) => setTimeout(resolve, 300));

    const killed = performance.now();

    chord.child.kill('SIGTERM');

    expect(await chord.ended).toEqual({ code: null, signal: 'SIGTERM' });
    expect(performance.now() - killed).toBeLessThan(15_000);

    await until(() => !alive(group));
    closeSync(read);
  }, 60_000);

  test('garbage with stdout blocked: input stops, a signal still ends it', async () => {
    const dir = await scratch();
    const { read, write } = pipeNobodyReads(dir);
    const chord = await start({ stdout: write });

    closeSync(write);

    const client = chord.child.stdin;

    assert(client !== null);

    // Each is answered -32700 on a pipe nobody reads, until it holds no more.
    const garbage = `${'x'.repeat(16)}\n`.repeat(40_000);

    client.write(garbage);

    await new Promise((resolve) => setTimeout(resolve, 300));

    chord.child.kill('SIGTERM');

    expect(await chord.ended).toEqual({ code: null, signal: 'SIGTERM' });
    closeSync(read);
  }, 60_000);

  test('stdout closed by the client: exit 1, a stderr line, group gone', async () => {
    const chord = await start();
    const sessionId = await chord.newSession();
    const group = await chord.group();

    chord.child.stdout?.destroy();
    chord.client.send('session/prompt', promptOf(sessionId, 'text'));

    expect((await chord.ended).code).toBe(1);
    expect(chord.stderr()).toContain('chord:');

    await until(() => !alive(group));
  }, 40_000);

  test('a line over 32 MiB: exit 1, a stderr line, group gone', async () => {
    const chord = await start();

    await chord.newSession();

    const group = await chord.group();

    chord.child.stdin?.write(`${'x'.repeat(33 * 1024 * 1024)}\n`);

    expect((await chord.ended).code).toBe(1);
    expect(chord.stderr()).toContain('exceeds');

    await until(() => !alive(group));
  }, 60_000);

  test('a crash of chord: its stack on stderr, the way out runs, exit 1', async () => {
    const chord = await start({ args: ['--preload', CRASH] });

    await chord.newSession();

    const group = await chord.group();

    chord.child.kill('SIGUSR2');

    expect((await chord.ended).code).toBe(1);
    expect(chord.stderr()).toContain('a bug of chord');

    await until(() => !alive(group));
    await parses(chord.client);
  }, 40_000);
});

describe('stderr', () => {
  test("an agent's stderr goes to neither stream", async () => {
    const chord = await start();
    const sessionId = await chord.newSession();

    await chord.client.answerTo(
      chord.client.send('session/prompt', promptOf(sessionId, 'crash')),
    );

    // Its last words are that prompt's error, and nowhere else.
    expect(chord.stderr()).toBe('');
    expect(
      chord.client.updates().filter((update) => {
        const content = update.content as { text?: string } | undefined;

        return content?.text?.includes('Killed: 9') === true;
      }),
    ).toEqual([]);
  }, 40_000);

  test('a stderr closed: prompts still answered', async () => {
    const chord = await start();

    chord.child.stderr?.destroy();

    const sessionId = await chord.newSession();

    expect(
      (
        await chord.client.request(
          'session/prompt',
          promptOf(sessionId, 'text'),
        )
      ).result?.stopReason,
    ).toBe('end_turn');
  }, 40_000);

  test('a stderr nobody reads: prompts still answered', async () => {
    const dir = await scratch();
    const { read, write } = pipeNobodyReads(dir);
    const chord = await start({
      stderr: write,
      flags: ['--dimcode-permission', 'full-access'],
    });

    closeSync(write);

    const sessionId = await chord.newSession();

    expect(
      (
        await chord.client.request(
          'session/prompt',
          promptOf(sessionId, 'text'),
        )
      ).result?.stopReason,
    ).toBe('end_turn');
    closeSync(read);
  }, 40_000);

  test('a client sees no note', async () => {
    const chord = await start();

    await chord.newSession();

    expect(chord.stderr()).toBe('');
  }, 40_000);

  test('the note is for a terminal, fits 80 columns, with no escape bytes', () => {
    const note = byHandNote(true);

    expect(byHandNote(false)).toEqual([]);
    expect(note).toEqual([
      'chord: acp serves ACP on stdin and stdout, for a client that starts it.',
      'chord: nothing to press here. Ctrl-D or Ctrl-C leaves; `chord` opens a window.',
    ]);

    for (const line of note) {
      expect(line.length).toBeLessThanOrEqual(80);
      expect(line).not.toContain('\u001b');
    }
  });
});

describe('the command', () => {
  const ran = (args: readonly string[]) =>
    spawnSync(execPath(), [MAIN, ...args], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env, NO_COLOR: '1' },
    });

  test('--help describes it', () => {
    const { status, stdout } = ran(['acp', '--help']);

    expect(status).toBe(0);
    expect(stdout).toContain('Serve ACP on stdin and stdout');
  });

  test('a usage error goes to stderr, stdout empty', () => {
    const { status, stdout, stderr } = ran(['acp', 'no-such-agent']);

    expect(status).toBe(2);
    expect(stdout).toBe('');
    expect(stderr).toContain('Unknown agent "no-such-agent"');
  });

  // Cliffy reads an unknown flag as [agent]: pinned, as stdout stays clean.
  test('an unknown flag exits 2, stdout empty', () => {
    const { status, stdout, stderr } = ran(['acp', '--nope']);

    expect(status).toBe(2);
    expect(stdout).toBe('');
    expect(stderr).toContain('"--nope"');
  });

  test('a flag missing its value goes to stderr, stdout empty', () => {
    const { status, stdout, stderr } = ran(['acp', '--agent-command']);

    expect(status).toBe(2);
    expect(stdout).toBe('');
    expect(stderr.startsWith('chord: ')).toBe(true);
  });
});

describe('CHD-574 tester: real client loss and several live agents', () => {
  test('SIGKILL of the actual client closes chord and flushes its record', async () => {
    const dir = await scratch();
    const pidFile = join(dir, 'agent.pid');
    const fixture = fileURLToPath(
      new URL('./fixtures/acp_client.ts', import.meta.url),
    );
    const command = quote([execPath(), AGENT, pidFile]);
    const driver = spawn(
      execPath(),
      [
        '-e',
        `
import { spawn } from 'node:child_process';
import process from 'node:process';
import { AcpClient } from ${JSON.stringify(fixture)};
const child = spawn(process.execPath, ${JSON.stringify([MAIN, 'acp', 'fake', '--agent-command', command])}, {
  cwd: ${JSON.stringify(dir)}, stdio: ['pipe', 'pipe', 'ignore']
});
process.stdout.write(String(child.pid) + '\\n');
const client = new AcpClient(line => child.stdin.write(line), child.stdout);
await client.request('initialize', { protocolVersion: 1, clientCapabilities: {} });
const opened = await client.request('session/new', { cwd: ${JSON.stringify(dir)}, mcpServers: [] });
client.send('session/prompt', { sessionId: opened.result.sessionId, prompt: [{ type: 'text', text: 'permission' }] });
await client.until(message => message.method === 'session/request_permission');
process.stdout.write('ready\\n');
setInterval(() => {}, 1000);
`,
      ],
      {
        stdio: ['ignore', 'pipe', 'ignore'],
        env: {
          ...process.env,
          XDG_STATE_HOME: join(dir, 'state'),
          XDG_CONFIG_HOME: join(dir, 'config'),
        },
      },
    );

    chords.push(driver);

    let status = '';
    let chordPid = 0;
    let group = 0;

    driver.stdout?.setEncoding('utf8').on('data', (chunk: string) => {
      status += chunk;
      chordPid = Number(status.split('\n')[0]);
    });

    const exited = new Promise((resolve) => driver.once('exit', resolve));

    try {
      await until(() => status.includes('ready\n'), 20_000);

      group = Number(await readFile(pidFile, 'utf8'));

      expect(group).toBeGreaterThan(0);
      driver.kill('SIGKILL');

      await exited;
      await until(() => {
        try {
          process.kill(chordPid, 0);

          return false;
        } catch {
          return true;
        }
      }, 20_000);
      await until(() => !alive(group));

      const records = await readRecords(join(dir, 'state', 'chord'));

      expect(records).toHaveLength(1);
      expect(await readFile(records[0]?.path ?? '', 'utf8')).toContain(
        '"permission"',
      );
    } finally {
      driver.kill('SIGKILL');

      for (const pid of [chordPid, -group]) {
        if (pid === 0) {
          continue;
        }

        try {
          process.kill(pid, 'SIGKILL');
        } catch {
          // Already reaped, as the assertions require on the clean path.
        }
      }
    }
  }, 60_000);

  test('one signal settles both sessions once and stops both process groups', async () => {
    const chord = await start();
    const first = await chord.newSession();
    const firstGroup = await chord.group();
    const second = await chord.client.request('session/new', {
      cwd: chord.dir,
      mcpServers: [],
    });
    const secondId = second.result?.sessionId;

    assert(typeof secondId === 'string');
    expect(secondId).toBe(`${first}~2`);

    const secondGroup = await chord.group();

    expect(secondGroup).not.toBe(firstGroup);

    const requests = [first, secondId].map((sessionId) =>
      chord.client.send('session/prompt', promptOf(sessionId, 'permission')),
    );

    for (const sessionId of [first, secondId]) {
      await chord.client.until(
        (message) =>
          message.method === 'session/request_permission' &&
          message.params?.sessionId === sessionId,
      );
    }

    chord.child.kill('SIGTERM');

    for (const id of requests) {
      expect((await chord.client.answerTo(id)).result?.stopReason).toBe(
        'cancelled',
      );
    }

    expect(await chord.ended).toEqual({ code: null, signal: 'SIGTERM' });

    await until(() => !alive(firstGroup) && !alive(secondGroup));
    await parses(chord.client);

    for (const id of requests) {
      expect(
        chord.client.messages.filter(
          (message) => message.id === id && message.method === undefined,
        ),
      ).toHaveLength(1);
    }
  }, 40_000);
});

describe('a place per session', () => {
  test("a command a session's directory refuses fails that session alone", async () => {
    const here = await scratch();
    const there = await scratch();
    const config = join(here, 'config');
    const pidFile = join(here, 'agent.pid');

    await mkdir(join(config, 'chord'), { recursive: true });
    await writeFile(
      join(config, 'chord', 'settings.json'),
      JSON.stringify({
        agents: { fake: { command: [execPath(), AGENT, pidFile] } },
      }),
    );
    await mkdir(join(there, '.chord'));
    await writeFile(
      join(there, '.chord', 'settings.json'),
      JSON.stringify({ agents: { fake: { command: 5 } } }),
    );

    const child = spawn(execPath(), [MAIN, 'acp', 'fake'], {
      cwd: here,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: {
        ...process.env,
        XDG_STATE_HOME: join(here, 'state'),
        XDG_CONFIG_HOME: config,
      },
    });

    chords.push(child);
    child.stderr.resume();

    const client = new AcpClient((line) => {
      child.stdin.write(line);
    }, child.stdout as AsyncIterable<Uint8Array>);

    await client.request('initialize', {
      protocolVersion: 1,
      clientCapabilities: {},
    });

    const refused = await client.request('session/new', {
      cwd: there,
      mcpServers: [],
    });

    expect(refused.error?.code).toBe(-32603);
    expect(refused.error?.message).toContain('fake');
    expect(refused.error?.message).toContain('.chord/settings.json');

    const { result } = await client.request('session/new', {
      cwd: here,
      mcpServers: [],
    });

    expect(result?.sessionId).toBeString();
  }, 30_000);

  test('a problem in a directory is said once, however many sessions read it', async () => {
    const chord = await start();
    const there = await scratch();

    await writeFile(join(there, '.mcp.json'), 'not json');

    await chord.newSession();

    for (const _ of [1, 2]) {
      const { result } = await chord.client.request('session/new', {
        cwd: there,
        mcpServers: [],
      });

      expect(result?.sessionId).toBeString();
    }

    const said = chord.stderr().split('\n');

    expect(said.filter((line) => line.includes('.mcp.json'))).toHaveLength(1);
  }, 30_000);
});
