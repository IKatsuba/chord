/**
 * A built chord's self-test, on the fake agent: --version says package.json's
 * version, -p answers, acp answers a prompt and a permission on stdio and goes
 * at EOF, and the window opens, answers a prompt and reads the
 * clipboard on ctrl+v, each of which a native library the binary could not
 * load would stop. The window runs in a tmux of its own, on temporary state
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
import { tmpdir } from 'node:os';
import { setTimeout as sleep } from 'node:timers/promises';
import { join, resolve } from 'node:path';
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

    const want = packageVersion(release);
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
