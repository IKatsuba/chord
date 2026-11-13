/**
 * Every platform chord ships a binary for. `bun` is the target `bun build
 * --compile` takes; `npm` names the platform package the way npm's `os` and
 * `cpu` fields spell it, so the shim can find the one installed beside it from
 * `process.platform` and `process.arch` alone.
 */
export interface Target {
  bun: Bun.Build.CompileTarget;
  os: 'darwin' | 'linux';
  cpu: 'arm64' | 'x64';
}

export const TARGETS: readonly Target[] = [
  { bun: 'bun-darwin-arm64', os: 'darwin', cpu: 'arm64' },
  { bun: 'bun-darwin-x64', os: 'darwin', cpu: 'x64' },
  { bun: 'bun-linux-x64', os: 'linux', cpu: 'x64' },
  { bun: 'bun-linux-arm64', os: 'linux', cpu: 'arm64' },
];

export const SCOPE = '@chorded';

export function platformPackage(target: Target): string {
  return `${SCOPE}/chord-${target.os}-${target.cpu}`;
}
