/**
 * chord's steps (CHD-623): its checks, in order, for `bun dev quality chord`,
 * ESLint's argv for `bun dev lint chord`, and its release's stages. Each
 * leaves `packages/`, the other packages' own, out.
 */
import type { Release } from './scripts/dev/release/lib.ts';
import type { PackageSteps } from './scripts/dev/steps.ts';

const bun = process.execPath;
// ESLint runs as `bun run eslint`, on Bun through bunfig.toml: Bun finds
// the bin in node_modules/.bin and, by `[run] bun = true`, runs it on Bun,
// when `bun scripts/dev.ts` is started directly (the release) as much as
// through `bun dev`.
const eslint = [bun, 'run', 'eslint', '.'];
// Loaded only when a stage runs, so parsing any `bun dev` command loads no release module.
const stages = async () =>
  (await import('./scripts/dev/release/stages.ts')).chord;
// Signing and notarisation need this Mac's keychain and Rosetta.
const ARM_MAC = { platform: 'darwin', arch: 'arm64' };
// One function for both stages that sign, so the release asks for the
// identity once.
const identity = async (release: Release) => (await stages()).identity(release);
// What the release's state records the sums of: the binaries compile builds
// (sign signs the macOS two in place), and pack's tarballs.
const BINARIES = [
  'dist/bun-darwin-arm64/chord',
  'dist/bun-darwin-x64/chord',
  'dist/bun-linux-arm64/chord',
  'dist/bun-linux-x64/chord',
];
const NPM = [
  '@chorded/chord-darwin-arm64',
  '@chorded/chord-darwin-x64',
  '@chorded/chord-linux-arm64',
  '@chorded/chord-linux-x64',
  '@chorded/chord',
];

export default {
  checks: [
    { name: 'types', static: true, run: [bun, 'check'] },
    { name: 'covered', static: true, run: [bun, 'scripts/dev/covered.ts'] },
    { name: 'eslint', static: true, run: eslint },
    // A pattern, not .prettierignore: an ignore file would leave a
    // package's own `bun fmt --check packages/<name>` nothing to check.
    {
      name: 'format',
      static: true,
      run: [bun, 'fmt', '--check', '--ignore-pattern=packages/', '.'],
    },
    { name: "lint/'s tests", static: true, run: [bun, 'test', 'lint/'] },
    { name: 'the suite', run: [bun, 'scripts/dev.ts', 'test'] },
  ],
  lint: eslint,
  release: [
    {
      name: 'install',
      about: 'bun install --frozen-lockfile',
      run: async (release) => (await stages()).install(release),
    },
    {
      name: 'quality',
      about: 'bun dev quality chord',
      run: async (release) => (await stages()).quality(release),
    },
    {
      name: 'natives',
      about: "every platform's packages; macOS libraries signed",
      machine: ARM_MAC,
      ready: identity,
      run: async (release) => (await stages()).natives(release),
    },
    {
      name: 'compile',
      about: 'bun dev compile --all, each kind checked',
      versioned: true,
      outputs: () => BINARIES,
      run: async (release) => (await stages()).compile(release),
    },
    {
      name: 'sign',
      about: 'both macOS binaries signed and verified',
      machine: ARM_MAC,
      ready: identity,
      outputs: () => BINARIES.filter((binary) => binary.includes('darwin')),
      run: async (release) => (await stages()).sign(release),
    },
    {
      name: 'selftest',
      about: 'each macOS binary on the fake agent',
      run: async (release) => (await stages()).selftest(release),
    },
    {
      name: 'notarise',
      about: "one zip to Apple; cdhashes in Apple's log",
      machine: ARM_MAC,
      ready: async (release) => (await stages()).notary(release),
      run: async (release) => (await stages()).notarise(release),
    },
    {
      name: 'pack',
      about: 'five packages packed, sums recorded, installed and checked',
      outputs: (_release, version) =>
        NPM.map(
          (name) =>
            `dist/release/tgz/${name.replace('@', '').replace('/', '-')}-${version}.tgz`,
        ),
      run: async (release) => (await stages()).pack(release),
    },
    {
      name: 'publish',
      npm: NPM,
      tag: 'v{version}',
      githubRelease: true,
    },
  ],
} satisfies PackageSteps;
