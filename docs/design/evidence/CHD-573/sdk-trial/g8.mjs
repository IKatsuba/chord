// Whether the way out stands with stdout blocked and a garbage line read, for
// CHD-573: SDK's ndJsonStream awaits its error write inside its read loop. A
// case is an own process tree. `bun g8.mjs <label> <argv prefix…>`; one JSON line
// per case. Mode `holder` is the client of the killed case, killed by SIGKILL.
import { spawn } from 'node:child_process';
import { closeSync, openSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const line = (message) => `${JSON.stringify({ jsonrpc: '2.0', ...message })}\n`;
const ENV = {
  ...process.env,
  TRIAL_STDOUT: 'callback',
  TRIAL_STDIN_WATCH: '1',
};
const OPENING = [
  line({
    id: 1,
    method: 'initialize',
    params: { protocolVersion: 1, clientCapabilities: {} },
  }),
  line({ id: 2, method: 'session/new', params: { cwd: '/tmp', mcpServers: [] } }),
  line({
    id: 3,
    method: 'session/prompt',
    params: {
      sessionId: 's1',
      prompt: [{ type: 'text', text: `flood:${64 * 1024 * 1024}` }],
    },
  }),
].join('');
const NOTE = line({ method: '_chord/note', params: { alive: true } });

if (process.argv[2] === 'holder') {
  // A client that reads nothing, whose death closes both pipes. Its stderr is
  // the log the parent reads.
  const [, , , log, garbage, ...argv] = process.argv;
  const fd = openSync(log, 'a');
  const child = spawn(argv[0], [...argv.slice(1), 'v1'], {
    stdio: ['pipe', 'pipe', fd],
    env: ENV,
    detached: true,
  });

  child.stdout.pause();
  child.stdin.on('error', () => {});
  child.stdin.write(OPENING);
  await sleep(700);

  if (garbage === 'garbage') {
    child.stdin.write('not json\n');
  }

  await sleep(300);
  child.stdin.write(NOTE);
  await new Promise(() => {});
}

const [label, ...prefix] = process.argv.slice(2);

function events(log) {
  return readFileSync(log, 'utf8')
    .split('\n')
    .filter(Boolean)
    .flatMap((text) => {
      try {
        return [JSON.parse(text)];
      } catch {
        return [];
      }
    });
}

const seen = (log, name) => events(log).some((e) => e.ev === name);

async function until(log, name, ms) {
  const at = performance.now();

  while (performance.now() - at < ms) {
    if (seen(log, name)) {
      return Math.round(performance.now() - at);
    }

    await sleep(10);
  }

  return `not within ${ms} ms`;
}

function report(name, garbage, log, more) {
  const list = events(log);

  console.log(
    JSON.stringify({
      target: label,
      case: name,
      garbageLine: garbage,
      blocked: !list.some((e) => e.ev === 'flood.done'),
      laterInputHandled: list.some((e) => e.ev === '_chord/note'),
      ...more,
      saw: list
        .map((e) => e.ev)
        .filter((ev) => /stdin|leave|closed|SIG|after|exit/.test(ev)),
    }),
  );
}

async function pgroupKill(pid) {
  try {
    process.kill(-pid, 'SIGKILL');
  } catch {
    // The group has gone already.
  }
}

/** The client alive and holding stdout's far end through a `sleep`. */
async function held(name, garbage, act, env = {}) {
  const log = join(tmpdir(), `chd573-g8-${process.pid}-${name}-${garbage}.log`);

  closeSync(openSync(log, 'w'));

  const fd = openSync(log, 'a');
  const child = spawn('sh', ['-c', '"$@" | sleep 60', 'sh', ...prefix, 'v1'], {
    stdio: ['pipe', 'ignore', fd],
    detached: true,
    env: { ...ENV, ...env },
  });

  child.stdin.on('error', () => {});
  child.stdin.write(OPENING);
  await sleep(700);

  if (garbage) {
    child.stdin.write('not json\n');
  }

  await sleep(300);
  child.stdin.write(NOTE);
  await sleep(300);

  const more = await act(child, log);

  report(name, garbage, log, more);
  await pgroupKill(child.pid);
}

/** The agent's own pid, among the pipeline's: not the sh, not the sleep. */
async function agentPid(shell) {
  const read = (argv) =>
    new Promise((resolve) => {
      const child = spawn(argv[0], argv.slice(1), {
        stdio: ['ignore', 'pipe', 'ignore'],
      });
      let out = '';

      child.stdout.on('data', (data) => {
        out += data;
      });
      child.on('exit', () => setTimeout(() => resolve(out), 50));
    });
  const pids = (await read(['pgrep', '-g', String(shell)]))
    .trim()
    .split('\n')
    .join(',');
  const row = (await read(['ps', '-o', 'pid=,comm=', '-p', pids]))
    .trim()
    .split('\n')
    .map((each) => each.trim().split(/\s+/))
    .find(
      ([pid, comm]) => Number(pid) !== shell && !/sleep|sh$/.test(comm),
    );

  return Number(row[0]);
}

const eof = async (child, log) => {
  child.stdin.end();

  const exitMs = await until(log, 'exit', 5000);

  return { action: 'stdin EOF', exitMs, closedSeen: seen(log, 'closed') };
};

const term = async (child, log) => {
  process.kill(await agentPid(child.pid), 'SIGTERM');

  return { action: 'SIGTERM', exitMs: await until(log, 'exit', 5000) };
};

const eofThenTerm = async (child, log) => {
  child.stdin.end();

  const exitMs = await until(log, 'exit', 3000);

  process.kill(await agentPid(child.pid), 'SIGTERM');

  return {
    action: 'stdin EOF, then SIGTERM',
    eofExitMs: exitMs,
    termExitMs: await until(log, 'exit', 3000),
  };
};

const readerGone = async (child, log) => {
  // The far end of stdout closes while the client keeps stdin open.
  const read = spawn('pkill', ['-g', String(child.pid), '-x', 'sleep']);

  await new Promise((resolve) => read.on('exit', resolve));

  return { action: 'stdout reader gone', exitMs: await until(log, 'exit', 5000) };
};

async function killed(garbage) {
  const log = join(tmpdir(), `chd573-g8-${process.pid}-killed-${garbage}.log`);

  closeSync(openSync(log, 'w'));

  const holder = spawn(
    process.execPath,
    [
      fileURLToPath(import.meta.url),
      'holder',
      log,
      garbage ? 'garbage' : 'none',
      ...prefix,
    ],
    { stdio: 'ignore' },
  );

  await sleep(1500);
  holder.kill('SIGKILL');

  report('the client killed', garbage, log, {
    action: 'SIGKILL of the client, both pipes close',
    exitMs: await until(log, 'exit', 5000),
  });
}

await held('eof', false, eof);
await held('eof', true, eof);
await held('eof-seen-on-stdin', true, eof, { TRIAL_LEAVE_ON_END: '1' });
await held('sigterm', true, term);
await held('eof-then-sigterm', true, eofThenTerm);
await held('reader-gone', true, readerGone);
await killed(false);
await killed(true);
process.exit(0);
