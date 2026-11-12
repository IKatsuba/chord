/**
 * A built chord's self-test, on the fake agent: --version says package.json's
 * version, -p answers, acp answers a prompt and a permission on stdio and goes
 * at EOF, and the window opens, answers a prompt and reads the
 * clipboard on ctrl+v, each of which a native library the binary could not
 * load would stop; a riff turn on each backend, through the hidden
 * --riff-agent, proves libfx is in the binary. The
 * window runs in a tmux of its own, on temporary state
 * and config directories. ARCH x86_64 runs it all under `arch -x86_64`
 * (Rosetta).
 */
import { spawn } from 'node:child_process';
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
} from 'node:fs';
import { writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { setTimeout as sleep } from 'node:timers/promises';
import { join, resolve } from 'node:path';
import type { SessionUpdate } from '@agentclientprotocol/sdk/unstable';
import { type Agent, openAgent } from '../../../src/acp/connection.ts';
import { DONE, NEEDLE, NEEDLE_FILE, serveFakeChat } from './fake_chat.ts';
import { die, type Release, run, said } from './lib.ts';
import { packageVersion } from './preflight.ts';

/**
 * `chord acp`, driven as a client: a prompt, its permission, then EOF. Bound by
 * the clock and not `release.sleep`, which a test may make instant.
 */
async function acpStep(
  release: Release,
  binary: string,
  arch: string | undefined,
  fake: string,
  cwd: string,
): Promise<void> {
  const child = spawn(
    arch === undefined ? binary : 'arch',
    [
      ...(arch === undefined ? [] : [`-${arch}`, binary]),
      'acp',
      'fake',
      '--agent-command',
      fake,
    ],
    { cwd, env: release.env, stdio: ['pipe', 'pipe', 'pipe'] },
  );
  const lines: Record<string, unknown>[] = [];
  let said = '';
  let held = '';
  let asked = false;
  const write = (message: object) =>
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', ...message })}\n`);
  const ended = new Promise<number | null>((done) => {
    child.once('exit', done);
  });

  const answered = new Promise<void>((done, failed) => {
    child.stderr.setEncoding('utf8').on('data', (text: string) => {
      said += text;
    });

    child.stdout.setEncoding('utf8').on('data', (text: string) => {
      held += text;

      const parts = held.split('\n');

      held = parts.pop() ?? '';

      for (const part of parts) {
        try {
          const line = JSON.parse(part) as Record<string, unknown>;

          lines.push(line);

          // A request ahead of `initialize`'s answer is refused.
          if (line['id'] === 1) {
            write({
              id: 2,
              method: 'session/new',
              params: { cwd, mcpServers: [] },
            });
          }

          if (line['id'] === 2 && line['result'] !== undefined) {
            write({
              id: 3,
              method: 'session/prompt',
              params: {
                sessionId: (line['result'] as { sessionId: string }).sessionId,
                prompt: [{ type: 'text', text: 'permission' }],
              },
            });
          }

          if (line['method'] === 'session/request_permission') {
            asked = true;

            write({
              id: line['id'],
              result: { outcome: { outcome: 'selected', optionId: 'allow' } },
            });
          }

          if (line['id'] === 3 && line['method'] === undefined) {
            if (asked && line['result'] !== undefined) {
              done();
            } else {
              failed(new Error(`${binary} acp's prompt answered: ${part}`));
            }
          }
        } catch {
          failed(
            new Error(`${binary} acp wrote a line that is not JSON: ${part}`),
          );
        }
      }
    });

    void ended.then(() =>
      failed(new Error(`${binary} acp exited early; stderr: ${said}`)),
    );
  });

  write({
    id: 1,
    method: 'initialize',
    params: { protocolVersion: 1, clientCapabilities: {} },
  });

  try {
    await Promise.race([
      answered,
      sleep(30_000, undefined, { ref: false }).then(() => {
        throw new Error(`${binary} acp never answered; stderr: ${said}`);
      }),
    ]);
  } catch (error) {
    child.kill('SIGKILL');
    die(error instanceof Error ? error.message : String(error));
  }

  child.stdin.end();

  const code = await Promise.race([
    ended,
    sleep(20_000, undefined, { ref: false }).then(() => -1),
  ]);

  if (code !== 0) {
    child.kill('SIGKILL');
    die(
      `${binary} acp did not leave cleanly at EOF (${code}); stderr: ${said}`,
    );
  }
}

/**
 * One riff turn through the binary's hidden `--riff-agent`, started and
 * driven by chord's own ACP client as the window starts riff, against the
 * fake Chat Completions server: `session/new`, one prompt, then the close,
 * which ends stdin and must see riff exit 0. `wasm` turns the native addon
 * off; the native leg clears it, whatever the caller's environment says.
 */
async function riffTurn(
  release: Release,
  binary: string,
  arch: string | undefined,
  cwd: string,
  url: string,
  wasm: boolean,
): Promise<RiffTurn> {
  let stderr = '';
  let text = '';
  const tools = new Map<string, RiffToolCall>();
  const env = Object.fromEntries(
    Object.entries({
      ...release.env,
      CHORD_RIFF_FAKE_PROVIDER: url,
      CHORD_RIFF_BACKEND: wasm ? 'wasm' : '',
    }).filter((entry): entry is [string, string] => entry[1] !== undefined),
  );
  let agent: Agent;

  try {
    agent = await openAgent({
      command: [
        ...(arch === undefined ? [] : ['arch', `-${arch}`]),
        binary,
        '--riff-agent',
      ],
      env,
      cwd,
      // Long enough for an exit at EOF, which the self-test requires.
      stop: { exitMs: 20_000, termMs: 2000, killMs: 2000 },
      onTraffic: (traffic) => {
        if (traffic.from === 'stderr') {
          stderr += traffic.text;
        } else if (traffic.from === 'agent') {
          const { update } =
            (traffic.message as { params?: { update?: SessionUpdate } })
              .params ?? {};

          if (
            update?.sessionUpdate === 'agent_message_chunk' &&
            update.content.type === 'text'
          ) {
            text += update.content.text;
          } else if (update?.sessionUpdate === 'tool_call') {
            tools.set(update.toolCallId, { title: update.title });
          } else if (
            update?.sessionUpdate === 'tool_call_update' &&
            (update.status === 'completed' || update.status === 'failed')
          ) {
            const [first] = update.content ?? [];

            tools.set(update.toolCallId, {
              ...tools.get(update.toolCallId),
              status: update.status,
              ...(first?.type === 'content' && first.content.type === 'text'
                ? { text: first.content.text }
                : {}),
            });
          }
        }
      },
      onPermission: () =>
        Promise.resolve({ outcome: { outcome: 'cancelled' } }),
      onElicitation: () => Promise.resolve({ action: 'decline' }),
      signal: AbortSignal.timeout(60_000),
    });
  } catch (error) {
    die(
      `${binary} --riff-agent did not start: ${String(error)}; stderr: ${stderr}`,
    );
  }

  let stopReason: string | undefined;

  try {
    const { sessionId } = (await agent.newSession(
      { cwd, mcpServers: [] },
      AbortSignal.timeout(60_000),
    )) as { sessionId: string };

    ({ stopReason } = await agent.prompt(
      { sessionId, prompt: [{ type: 'text', text: 'Say done.' }] },
      AbortSignal.timeout(60_000),
    ));
  } catch (error) {
    await agent.close().catch(() => {});

    die(
      `${binary} --riff-agent's turn failed: ${String(error)}; stderr: ${stderr}`,
    );
  }

  await agent.close();

  const exit = await agent.exited;

  if (exit.code !== 0) {
    die(
      `${binary} --riff-agent did not leave at EOF (${exit.signal ?? exit.code}); stderr: ${stderr}`,
    );
  }

  return {
    backend: /^riff: backend (\S+)$/m.exec(stderr)?.[1],
    stopReason,
    text,
    tools: [...tools.values()],
  };
}

/**
 * A real riff turn through `--riff-agent` on each backend: native, then
 * with native turned off (Wasm), each reported by riff, searching the
 * project for the needle with fff in its Worker, reading the file it is in,
 * and ending `end_turn` with `done` after three model requests.
 */
export async function riffStep(
  release: Release,
  binary: string,
  arch: string | undefined,
  cwd: string,
): Promise<void> {
  // The needle first: a write that fails leaves no server running.
  await writeFile(join(cwd, NEEDLE_FILE), `${NEEDLE}\n`);

  const fake = serveFakeChat();

  try {
    const turns = [
      await riffTurn(release, binary, arch, cwd, fake.url, false),
      await riffTurn(release, binary, arch, cwd, fake.url, true),
    ];
    const wrong = riffProblems(turns, fake.requests());

    if (wrong !== undefined) {
      die(`${binary} --riff-agent ${wrong}: ${JSON.stringify(turns)}`);
    }
  } finally {
    await fake.stop();
  }
}

/** A tool call of a riff turn, as the window would draw it. */
export interface RiffToolCall {
  readonly title?: string;
  readonly status?: string;
  /** The text the window would show under it. */
  readonly text?: string;
}

/** The calls every turn makes, in order: fff's search, then the read. */
export const RIFF_TOOLS: readonly RiffToolCall[] = [
  {
    title: `Search ${NEEDLE}`,
    status: 'completed',
    text: `${NEEDLE_FILE}:1: ${NEEDLE}`,
  },
  { title: `Read ${NEEDLE_FILE}`, status: 'completed', text: NEEDLE },
];

/** The model requests of a turn: one per call, and the answer. */
const TURN_REQUESTS = RIFF_TOOLS.length + 1;

/** What one riff turn did, as the self-test checks it. */
export interface RiffTurn {
  /** The backend riff said on stderr it loaded. */
  readonly backend?: string | undefined;
  readonly stopReason?: string | undefined;
  readonly text?: string;
  readonly tools?: readonly RiffToolCall[];
}

/** What is wrong with the two turns, or undefined when it all holds. */
export function riffProblems(
  turns: readonly RiffTurn[],
  requests: number,
): string | undefined {
  const backends = ['native', 'wasm-jspi'];

  if (turns.length !== backends.length) {
    return `ran ${turns.length} turns, not ${backends.length}`;
  }

  for (const [index, turn] of turns.entries()) {
    if (turn.backend !== backends[index]) {
      return `ran turn ${index + 1} on ${turn.backend}, not ${backends[index]}`;
    }

    if (turn.stopReason !== 'end_turn' || turn.text !== DONE) {
      return `ended its ${turn.backend} turn ${turn.stopReason} with ${JSON.stringify(turn.text)}`;
    }

    if (JSON.stringify(turn.tools) !== JSON.stringify(RIFF_TOOLS)) {
      return `called ${JSON.stringify(turn.tools)} on ${turn.backend}, not ${JSON.stringify(RIFF_TOOLS)}`;
    }
  }

  if (requests !== backends.length * TURN_REQUESTS) {
    return `made ${requests} model requests, not ${backends.length * TURN_REQUESTS}`;
  }

  return undefined;
}

export async function selftest(
  release: Release,
  given: string,
  arch?: string,
): Promise<void> {
  // Absolute, as the runs below start in a directory of their own.
  const binary = resolve(release.root, given);

  if (!statSync(binary, { throwIfNoEntry: false })?.isFile()) {
    die(`no binary at ${given}`);
  }

  if (run(release, 'sh', ['-c', 'command -v tmux']).status !== 0) {
    die('the self-test needs tmux');
  }

  const fake = `bun '${join(release.root, 'tests', 'fixtures', 'fake_agent', 'main.ts')}'`;
  const scratch = mkdtempSync(join(tmpdir(), 'chord-selftest-'));
  const socket = `chord-selftest-${process.pid}`;
  const env = {
    ...release.env,
    XDG_STATE_HOME: join(scratch, 'state'),
    XDG_CONFIG_HOME: join(scratch, 'config'),
  };
  const inScratch = { ...release, env };
  const chord = (args: string[], cwd = release.root) => {
    // stdin stays the terminal's, as it was for the shell step: -p reads a
    // piped stdin as part of its prompt.
    const ran = run(
      inScratch,
      arch === undefined ? binary : 'arch',
      arch === undefined ? args : [`-${arch}`, binary, ...args],
      { cwd, stdio: ['inherit', 'pipe', 'pipe'] },
    );

    return { status: ran.status, said: said(ran.stdout + ran.stderr) };
  };

  const tmux = (...args: string[]) =>
    run(inScratch, 'tmux', ['-L', socket, ...args]);
  const screen = () => {
    const captured = tmux('capture-pane', '-t', 'selftest', '-p');

    return captured.status === 0 ? said(captured.stdout) : '';
  };

  const stderr = () => {
    try {
      return said(readFileSync(join(scratch, 'stderr'), 'utf8'));
    } catch {
      return '';
    }
  };

  // The screen, once it shows what is waited for, or a death with what it
  // showed.
  const waitFor = async (text: string) => {
    for (let attempt = 0; attempt < 60; attempt++) {
      if (screen().includes(text)) {
        return;
      }

      await release.sleep(500);
    }

    die(
      `${binary}'s window never showed "${text}"; stderr: ${stderr()} screen:\n${screen()}`,
    );
  };

  // The tmux server and the scratch directory are this run's: gone however
  // it ends, a signal included, as the shell step's EXIT trap had them.
  let cleaned = false;
  const cleanUp = () => {
    if (!cleaned) {
      cleaned = true;

      tmux('kill-server');
      rmSync(scratch, { recursive: true, force: true });
    }
  };

  const signals = ['SIGINT', 'SIGTERM', 'SIGHUP'] as const;
  const onSignal = (signal: NodeJS.Signals) => {
    cleanUp();

    for (const each of signals) {
      process.removeListener(each, onSignal);
    }

    // Raised again with no listener left, so the run ends by it.
    process.kill(process.pid, signal);
  };

  for (const signal of signals) {
    process.on(signal, onSignal);
  }

  try {
    for (const dir of ['project', 'state', 'config']) {
      mkdirSync(join(scratch, dir));
    }

    const want = packageVersion(release, '.');
    const version = chord(['--version']);

    if (version.status !== 0) {
      die(`${binary} --version failed: ${version.said}`);
    }

    if (!version.said.includes(want)) {
      die(`${binary} --version said ${version.said}, not ${want}`);
    }

    const printed = chord(
      ['fake', '--agent-command', fake, '-p', 'text'],
      join(scratch, 'project'),
    );

    if (printed.status !== 0) {
      die(`${binary} -p failed: ${printed.said}`);
    }

    if (!printed.said.includes('Hello, world.')) {
      die(`${binary} -p answered: ${printed.said}`);
    }

    await acpStep(inScratch, binary, arch, fake, join(scratch, 'project'));
    await riffStep(inScratch, binary, arch, join(scratch, 'project'));

    tmux(
      'new-session',
      '-d',
      '-s',
      'selftest',
      '-x',
      '100',
      '-y',
      '30',
      '-c',
      join(scratch, 'project'),
      `${arch === undefined ? '' : `arch -${arch} `}'${binary}' fake --agent-command "${fake}" 2>'${join(scratch, 'stderr')}'; sleep 60`,
    );
    await waitFor('for shortcuts');
    tmux('send-keys', '-t', 'selftest', 'text', 'Enter');
    await waitFor('Hello, world.');
    tmux('send-keys', '-t', 'selftest', 'C-v');
    await release.sleep(2000);

    if (screen().includes('cannot be read')) {
      die(`${binary} could not load the clipboard:\n${screen()}`);
    }

    if (stderr().includes('dlopen') || stderr().includes('Team IDs')) {
      die(`${binary} failed to load a library: ${stderr()}`);
    }

    release.out(
      `self-tested ${binary}${arch === undefined ? '' : ` under ${arch}`}`,
    );
  } finally {
    for (const signal of signals) {
      process.removeListener(signal, onSignal);
    }

    cleanUp();
  }
}
