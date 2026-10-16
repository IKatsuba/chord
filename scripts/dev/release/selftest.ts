/**
 * A built chord's self-test, on the fake agent: --version says package.json's
 * version, -p answers, and the window opens, answers a prompt and reads the
 * clipboard on ctrl+v, each of which a native library the binary could not
 * load would stop. The window runs in a tmux of its own, on temporary state
 * and config directories. ARCH x86_64 runs it all under `arch -x86_64`
 * (Rosetta).
 */
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { die, type Release, run, said } from './lib.ts';
import { packageVersion } from './preflight.ts';

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
    tmux('kill-server');
    rmSync(scratch, { recursive: true, force: true });
  }
}
