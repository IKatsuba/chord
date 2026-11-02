// What the SDK's write queue retains while nobody reads stdout, for CHD-573's
// finding on the output bound. Always on the callback stdout. `bun queue.mjs
// <label> <argv prefix…>`; one JSON line per case.
import { spawn } from 'node:child_process';
import process from 'node:process';

const [label, ...prefix] = process.argv.slice(2);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const line = (message) => `${JSON.stringify({ jsonrpc: '2.0', ...message })}\n`;

let cases = 0;
const want = (n) =>
  !process.env.QUEUE_ONLY || Number(process.env.QUEUE_ONLY) === n;

function start(shell = '"$@" | sleep 60') {
  const child = spawn('sh', ['-c', shell, 'sh', ...prefix, 'v1'], {
    stdio: ['pipe', 'pipe', 'pipe'],
    detached: true,
    env: { ...process.env, TRIAL_STDOUT: 'callback', TRIAL_TICK: '1' },
  });
  const seen = { stderr: '', stdout: '' };

  child.stderr.on('data', (data) => {
    seen.stderr += data;
  });
  child.stdout.on('data', (data) => {
    seen.stdout += data;
  });
  child.stdin.on('error', () => {});

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
    write,
    events: () =>
      seen.stderr
        .split('\n')
        .filter(Boolean)
        .flatMap((text) => {
          try {
            return [JSON.parse(text)];
          } catch {
            return [];
          }
        }),
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

function report(run, name, more = {}) {
  const ticks = run.events().filter((e) => e.ev === 'tick');
  const last = ticks.at(-1)?.ms;

  console.log(
    JSON.stringify({
      target: label,
      case: name,
      firstRssMiB: ticks[0]?.rssMiB,
      peakRssMiB: Math.max(0, ...ticks.map((e) => e.rssMiB)),
      lastTickMs: last,
      ...more,
    }),
  );
  run.kill();
}

/** Writes `count` lines from `make`, waiting on the pipe as a client would. */
async function pour(run, count, make) {
  for (let i = 0; i < count; i++) {
    if (!run.child.stdin.write(make(i))) {
      await new Promise((resolve) => run.child.stdin.once('drain', resolve));
    }
  }
}

async function alive(run) {
  run.write({ method: '_chord/note', params: { alive: true } });
  await sleep(500);

  return run.events().some((e) => e.ev === '_chord/note');
}

if (want(++cases)) {
  const run = start();

  run.prompt(`flood-unique:${256 * 1024 * 1024}`);
  await sleep(4000);
  report(run, 'unique notifications, 256 MiB, nobody reads', {
    handlerStillAnswers: await alive(run),
  });
}

if (want(++cases)) {
  const run = start();
  const padding = 'p'.repeat(8 * 1024);

  await pour(run, 20_000, (i) =>
    line({ id: 10_000 + i, method: '_chord/ping', params: { i, padding } }),
  );
  await sleep(2000);
  report(run, 'responses from a handler, 160 MiB, nobody reads', {
    handlerStillAnswers: await alive(run),
  });
}

if (want(++cases)) {
  const run = start();

  await pour(run, 500_000, (i) =>
    line({ id: 10_000 + i, method: '_chord/absent', params: {} }),
  );
  await sleep(2000);
  report(run, 'the SDK own -32601, 500k requests, nobody reads', {
    handlerStillAnswers: await alive(run),
  });
}

if (want(++cases)) {
  const run = start();

  await Promise.race([
    pour(run, 100_000, (i) =>
      line({ id: 10_000 + i, method: 'session/new', params: { cwd: 1 } }),
    ),
    sleep(20_000),
  ]);
  await sleep(2000);
  report(run, 'the SDK own -32602, 100k requests, nobody reads', {
    handlerStillAnswers: await alive(run),
  });
}

if (want(++cases)) {
  const run = start();

  await Promise.race([
    pour(run, 100_000, () => 'not json\n'),
    sleep(5000),
  ]);
  await sleep(500);
  report(run, 'parse errors, nobody reads: does later input still arrive', {
    laterInputHandled: await alive(run),
  });
}

if (want(++cases)) {
  const run = start();

  run.prompt(`flood:${256 * 1024 * 1024}`);
  await sleep(1000);

  // The agent alone: signalling the reader too would unblock the pipe.
  const ps = spawn('pgrep', ['-g', String(run.child.pid)], {
    stdio: ['ignore', 'pipe', 'ignore'],
  });
  let out = '';

  ps.stdout.on('data', (data) => {
    out += data;
  });
  await new Promise((resolve) => ps.on('exit', resolve));
  await sleep(100);

  const named = spawn('ps', ['-o', 'pid=,comm=', '-p', out.trim().split('\n').join(',')], {
    stdio: ['ignore', 'pipe', 'ignore'],
  });
  let names = '';

  named.stdout.on('data', (data) => {
    names += data;
  });
  await new Promise((resolve) => named.on('exit', resolve));
  await sleep(100);

  const agent = names
    .trim()
    .split('\n')
    .map((row) => row.trim().split(/\s+/))
    .find(([pid, comm]) => Number(pid) !== run.child.pid && !/sleep|sh$/.test(comm));
  const at = performance.now();

  if (agent) {
    process.kill(Number(agent[0]), 'SIGTERM');
  }

  while (
    performance.now() - at < 3000 &&
    !run.events().some((e) => e.ev === 'exit')
  ) {
    await sleep(10);
  }

  report(run, 'SIGTERM while stdout is already blocked', {
    exitMs: run.events().some((e) => e.ev === 'exit')
      ? Math.round(performance.now() - at)
      : 'not within 3s',
    saw: run
      .events()
      .filter((e) => /SIG|after|exit/.test(e.ev))
      .map((e) => e.ev),
  });
}

if (want(++cases)) {
  // stdout to this process, stderr to a pipe nobody reads.
  const run = start('exec 3>&1; "$@" 2>&1 >&3 3>&- | sleep 60');

  run.prompt(`stderr-flood:${64 * 1024 * 1024}`);
  await sleep(1500);

  const answered = run.seen.stdout.includes('stderr written');

  run.write({ id: 7, method: '_chord/ping', params: {} });
  await sleep(1000);

  const pong = run.seen.stdout.includes('"id":7');

  console.log(
    JSON.stringify({
      target: label,
      case: 'stderr nobody reads, 64 MiB written unawaited',
      turnWentOn: answered,
      loopAnswersAfter: pong,
    }),
  );
  run.kill();
}

process.exit(0);
