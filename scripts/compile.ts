/**
 * Compile chord into standalone binaries with `bun build --compile`.
 *
 *   bun run compile             this machine's target, into dist/<target>/
 *   bun run compile --all       every target in scripts/targets.ts
 *   bun run compile --install   this machine's target, into ~/.local/bin/chord
 */
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import manifest from '../package.json' with { type: 'json' };
import { TARGETS } from './targets.ts';

const { values: args } = parseArgs({
  args: process.argv.slice(2),
  options: { all: { type: 'boolean' }, install: { type: 'boolean' } },
});
const root = new URL('..', import.meta.url).pathname;

// Every build flag below was tried on this range, and nothing older was.
if (!Bun.semver.satisfies(Bun.version, manifest.engines.bun)) {
  console.error(
    `chord compiles on Bun ${manifest.engines.bun}; this is Bun ${Bun.version}.`,
  );
  process.exit(1);
}

const host = TARGETS.find(
  (target) => target.os === process.platform && target.cpu === process.arch,
);
const targets = args.all ? TARGETS : host ? [host] : [];

if (targets.length === 0) {
  console.error(
    `No target for ${process.platform}-${process.arch}; pass --all for the release set.`,
  );
  process.exit(1);
}

// A binary embeds only the clipboard addon that is installed, which is
// otherwise the host's alone, so a cross-compiled one could not read it.
run(['install', '--os=*', '--cpu=*']);

for (const target of targets) {
  const output = args.install
    ? join(homedir(), '.local', 'bin', 'chord')
    : join(root, 'dist', target.bun, 'chord');

  run([
    'build',
    '--compile',
    // @opentui/react imports react-devtools-core, its peer, only when
    // DEV=true. Bundled in, a binary run with DEV=true connects to a devtools
    // server that is not there and never exits after quit; external and split
    // into a chunk, the import stays behind OpenTUI's own lazy import, fails,
    // and OpenTUI warns and carries on (CHD-309).
    '--external',
    'react-devtools-core',
    '--splitting',
    // Nothing sets NODE_ENV, so React would load its development build, which
    // keeps a performance.measure for every render and a stack on every fiber,
    // never cleared (CHD-344). Defined rather than --production, which also
    // minifies and leaves heap snapshots and stack traces without names.
    '--define',
    'process.env.NODE_ENV:"production"',
    '--target',
    target.bun,
    '--outfile',
    output,
    join(root, 'src', 'main.tsx'),
  ]);
  console.log(output);
}

function run(argv: string[]) {
  const { status } = spawnSync(process.execPath, argv, {
    cwd: root,
    stdio: 'inherit',
  });

  if (status !== 0) {
    process.exit(status ?? 1);
  }
}
