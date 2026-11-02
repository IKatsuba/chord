// What chord's own way of starting does to stdout (CHD-573's library gate).
// `bun chord_start.mjs <repo> <work>` builds, into <work>, chord's binary and a
// binary that loads src/main.tsx's whole import graph and then runs agent.mjs,
// both with the build options `bun dev compile` uses, and reads what each writes
// under a HOME and XDG directories of its own. `bun dev compile` itself is not
// run: it runs `bun install` first, in a checkout others share.
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [repo, work] = process.argv.slice(2);
const { buildOptions } = await import(join(repo, 'scripts/dev/compile.ts'));
const home = join(work, 'home');
const place = join(work, 'place');

for (const dir of [home, place, join(home, 'config'), join(home, 'state')]) {
  mkdirSync(dir, { recursive: true });
}

symlinkSync(repo, join(work, 'repo'));
copyFileSync(new URL('./agent.mjs', import.meta.url).pathname, join(work, 'agent.mjs'));
writeFileSync(
  join(work, 'probe_before.mjs'),
  `globalThis.__probe = {
  at: performance.now(),
  log: console.log,
  stdoutWrite: process.stdout.write,
  counts: () => Object.fromEntries(
    ['SIGTERM', 'SIGINT', 'SIGHUP', 'exit', 'beforeExit', 'uncaughtException', 'unhandledRejection']
      .map((name) => [name, process.listenerCount(name)])),
};
globalThis.__probe.before = globalThis.__probe.counts();
`,
);
writeFileSync(
  join(work, 'probe_after.mjs'),
  `const p = globalThis.__probe;
process.stderr.write(JSON.stringify({
  ev: 'graph',
  loadMs: Math.round(performance.now() - p.at),
  listenersBefore: p.before,
  listenersAfter: p.counts(),
  consoleLogPatched: console.log !== p.log,
  stdoutWritePatched: process.stdout.write !== p.stdoutWrite,
  stdinRaw: process.stdin.isRaw === true,
  rssMiB: Math.round(process.memoryUsage().rss / 1048576),
}) + '\\n');
`,
);
writeFileSync(
  join(work, 'graph.mjs'),
  `import './probe_before.mjs';
import './repo/src/main.tsx';
import './probe_after.mjs';
import './agent.mjs';
`,
);

async function build(entry, outfile) {
  const options = buildOptions(entry, { compiled: true });
  const built = await Bun.build({
    ...options,
    compile: { outfile },
  });

  if (!built.success) {
    throw new Error(built.logs.map(String).join('\n'));
  }

  return statSync(outfile).size;
}

const sizes = {
  chord: await build(join(repo, 'src/main.tsx'), join(work, 'chord-bin')),
  graph: await build(join(work, 'graph.mjs'), join(work, 'graph-bin')),
};
const env = {
  PATH: process.env.PATH,
  HOME: home,
  XDG_CONFIG_HOME: join(home, 'config'),
  XDG_STATE_HOME: join(home, 'state'),
};
const scrub = (text) =>
  text.replaceAll(repo, '<repo>').replaceAll(work, '<work>').slice(0, 1500);
const fake = `${process.execPath} ${join(repo, 'tests/fixtures/fake_agent/main.ts')}`;
const runs = {
  'source --version': [process.execPath, join(repo, 'src/main.tsx'), '--version'],
  'source -p on the fake agent': [
    process.execPath,
    join(repo, 'src/main.tsx'),
    '-p',
    'hi',
    '--agent-command',
    fake,
  ],
  'binary --version': [join(work, 'chord-bin'), '--version'],
  'binary -p on the fake agent': [
    join(work, 'chord-bin'),
    '-p',
    'hi',
    '--agent-command',
    fake,
  ],
  'source graph, then the trial agent, stdin at EOF': [
    process.execPath,
    join(work, 'graph.mjs'),
    'v1',
  ],
  'binary graph, then the trial agent, stdin at EOF': [
    join(work, 'graph-bin'),
    'v1',
  ],
  // What a Cliffy parse gives `chord acp` today: no such command.
  'binary acp (no such command yet)': [join(work, 'chord-bin'), 'acp', 'x'],
};

console.log(JSON.stringify({ sizes }));

for (const [name, argv] of Object.entries(runs)) {
  const started = performance.now();
  const run = spawnSync(argv[0], argv.slice(1), {
    cwd: place,
    env,
    input: '',
    encoding: 'utf8',
    timeout: 30_000,
  });

  console.log(
    JSON.stringify({
      run: name,
      status: run.status,
      signal: run.signal,
      ms: Math.round(performance.now() - started),
      stdoutBytes: run.stdout.length,
      stdout: scrub(run.stdout),
      stderr: scrub(run.stderr),
    }),
  );
}
