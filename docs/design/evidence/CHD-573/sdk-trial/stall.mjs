// The agent's stdout held by a pipe nobody reads, for CHD-573's library gate: a
// `sleep` sits on the far end, so nothing in this process can drain it, as
// pausing a child's stream in client.mjs might. `bun stall.mjs <label> <argv
// prefix…>`; one JSON line per case, for each way of making stdout a
// WritableStream (TRIAL_STDOUT in agent.mjs).
import { spawn } from 'node:child_process';
import process from 'node:process';

const [label, ...prefix] = process.argv.slice(2);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const line = (message) => `${JSON.stringify({ jsonrpc: '2.0', ...message })}\n`;
const FLOOD = 256 * 1024 * 1024;

function start(reader, env) {
  const child = spawn('sh', ['-c', `"$@" | ${reader}`, 'sh', ...prefix, 'v1'], {
    stdio: ['pipe', 'pipe', 'pipe'],
    detached: true,
    env: { ...process.env, ...env },
  });
  const seen = { stderr: '', stdout: '' };

  child.stderr.on('data', (data) => {
    seen.stderr += data;
  });
  child.stdout.on('data', (data) => {
    seen.stdout += data;
  });

  const events = () =>
    seen.stderr
      .split('\n')
      .filter(Boolean)
      .flatMap((text) => {
        try {
          return [JSON.parse(text)];
        } catch {
          return [];
        }
      });
  const write = (message) => child.stdin.write(line(message));

  write({
    id: 1,
    method: 'initialize',
    params: { protocolVersion: 1, clientCapabilities: {} },
  });
  write({ id: 2, method: 'session/new', params: { cwd: '/tmp', mcpServers: [] } });

  return {
    child,
    seen,
    events,
    write,
    prompt: (text) =>
      write({
        id: 3,
        method: 'session/prompt',
        params: { sessionId: 's1', prompt: [{ type: 'text', text }] },
      }),
    kill: () => {
      try {
        process.kill(-child.pid, 'SIGKILL');
      } catch {
        // The group has gone already.
      }
    },
  };
}

/** Nobody reads: how far the flood gets, and whether the loop still runs. */
async function held(stdout, what) {
  const run = start('sleep 60', { TRIAL_STDOUT: stdout });

  run.prompt(`${what}:${FLOOD}`);
  await sleep(4000);

  const floods = run.events().filter((e) => /flood/.test(e.ev));

  run.write({ method: '_chord/note', params: { alive: true } });
  await sleep(500);

  const alive = run.events().some((e) => e.ev === '_chord/note');
  const at = performance.now();

  run.child.stdin.end();

  while (
    performance.now() - at < 3000 &&
    !run.events().some((e) => e.ev === 'exit')
  ) {
    await sleep(20);
  }

  const exited = run.events().some((e) => e.ev === 'exit');

  run.kill();
  console.log(
    JSON.stringify({
      target: label,
      case: 'nobody reads',
      stdout,
      what,
      lastFlood: floods.at(-1) ?? 'none: the first writes are held',
      loopAlive: alive,
      afterEofExitMs: exited ? Math.round(performance.now() - at) : 'not within 3s',
    }),
  );
}

/** A slow reader, and an exit straight after the flood: what arrives. */
async function lost(stdout) {
  const run = start('(sleep 1; wc -c)', {
    TRIAL_STDOUT: stdout,
    TRIAL_EXIT_AFTER_FLOOD: '1',
  });
  const size = 16 * 1024 * 1024;

  run.prompt(`flood:${size}`);

  await new Promise((resolve) => run.child.on('exit', resolve));
  await sleep(100);

  const read = Number(run.seen.stdout.trim());

  console.log(
    JSON.stringify({
      target: label,
      case: 'process.exit right after the flood',
      stdout,
      sentPayload: size,
      bytesRead: read,
      lostMost: read < size,
    }),
  );
}

for (const stdout of ['toweb', 'callback', 'bun']) {
  await held(stdout, 'flood');
  await lost(stdout);
}

await held('toweb', 'flood-unawaited');
await held('callback', 'flood-unawaited');
process.exit(0);
