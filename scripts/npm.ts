/**
 * Lay out the npm packages from the binaries in dist/, the way esbuild and
 * biome ship native code: one package per platform carrying the binary, with
 * `os` and `cpu` so npm installs only the matching one, and `@chorded/chord`
 * depending on all of them optionally and holding a small shim as its `bin`.
 * No Node build of chord exists; the shim only finds and execs the binary.
 *
 *   bun run compile --all && bun run npm   writes npm/
 * `scripts/release.sh` runs it on the signed binaries, packs and publishes.
 */
import { chmod, copyFile, mkdir, rm, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import manifest from '../package.json' with { type: 'json' };
import { platformPackage, SCOPE, TARGETS } from './targets.ts';

const SHIM = `#!/usr/bin/env node
// The \`chord\` command npm installs: it runs the binary of this machine's
// platform package with the same arguments and stdio, and leaves as the
// binary left. A Node script, because npm runs \`bin\` with the user's Node
// and the user need not have Bun.
const { spawn } = require("node:child_process");

const pkg = \`${SCOPE}/chord-\${process.platform}-\${process.arch}\`;
let bin;
try {
  bin = require.resolve(\`\${pkg}/bin/chord\`);
} catch {
  process.stderr.write(
    \`chord: no \${pkg} is installed. chord runs on macOS and Linux, arm64 and x64; reinstall @chorded/chord on one of those, with optional dependencies.\\n\`,
  );
  process.exit(1);
}

// spawn, not spawnSync: a blocked event loop cannot forward a signal, and a
// SIGTERM to this process alone would leave the binary running.
const child = spawn(bin, process.argv.slice(2), { stdio: "inherit" });
const forwarded = ["SIGINT", "SIGTERM", "SIGHUP"];
for (const signal of forwarded) {
  process.on(signal, () => child.kill(signal));
}
child.on("error", (error) => {
  process.stderr.write(\`chord: \${bin} did not start: \${error.message}\\n\`);
  process.exit(1);
});
child.on("exit", (status, signal) => {
  if (signal) {
    // Re-raise the child's signal, so a chord ended by one still ends by it
    // as the shell sees it; the handlers go first, or they would catch it.
    for (const name of forwarded) process.removeAllListeners(name);
    process.kill(process.pid, signal);
    return;
  }
  process.exit(status ?? 1);
});
`;

const root = new URL('..', import.meta.url).pathname;
const out = join(root, 'npm');
const version = manifest.version;
const common = {
  version,
  license: 'MIT',
  repository: { type: 'git', url: 'git+https://github.com/IKatsuba/chord.git' },
};

const missing = [];

for (const target of TARGETS) {
  const path = join(root, 'dist', target.bun, 'chord');

  if (!(await stat(path).catch(() => null))) {
    missing.push(path);
  }
}

if (missing.length > 0) {
  console.error(
    `Missing binaries; run \`bun run compile --all\` first:\n${missing.join(
      '\n',
    )}`,
  );
  process.exit(1);
}

await rm(out, { recursive: true, force: true });

for (const target of TARGETS) {
  const name = platformPackage(target);
  const dir = join(out, name.replace(`${SCOPE}/`, ''));

  await mkdir(join(dir, 'bin'), { recursive: true });
  await copyFile(
    join(root, 'dist', target.bun, 'chord'),
    join(dir, 'bin', 'chord'),
  );
  await chmod(join(dir, 'bin', 'chord'), 0o755).catch(() => {});

  await copyFile(join(root, 'LICENSE'), join(dir, 'LICENSE'));
  await writeJson(join(dir, 'package.json'), {
    name,
    ...common,
    description: `The chord binary for ${target.os}-${target.cpu}.`,
    os: [target.os],
    cpu: [target.cpu],
    files: ['bin/'],
  });
}

const main = join(out, 'chord');

await mkdir(join(main, 'bin'), { recursive: true });
await copyFile(join(root, 'README.md'), join(main, 'README.md'));
await copyFile(join(root, 'LICENSE'), join(main, 'LICENSE'));
await writeFile(join(main, 'bin', 'chord.js'), SHIM);
await chmod(join(main, 'bin', 'chord.js'), 0o755);
await writeJson(join(main, 'package.json'), {
  name: `${SCOPE}/chord`,
  ...common,
  description: 'A full-screen terminal client for ACP coding agents.',
  bin: { chord: 'bin/chord.js' },
  files: ['bin/'],
  optionalDependencies: Object.fromEntries(
    TARGETS.map((target) => [platformPackage(target), version]),
  ),
});
console.log(out);

async function writeJson(path: string, value: unknown) {
  await writeFile(path, JSON.stringify(value, null, 2) + '\n');
}
