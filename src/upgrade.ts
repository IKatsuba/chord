/**
 * `chord upgrade`: cliffy's upgrade command over the package manager that
 * installed the running chord, found from the binary's real path, so it
 * upgrades the install it runs from and never puts a second chord
 * elsewhere. Ported from board's, which works the same way.
 */
import { spawn } from 'node:child_process';
import { UpgradeCommand } from '@cliffy/command/upgrade';
import type { ProviderUpgradeOptions, Versions } from '@cliffy/upgrade';
import { NpmProvider } from '@cliffy/upgrade/provider/npm';

/** The published package a person installs. */
export const PACKAGE = '@chorded/chord';

/** A package manager chord can upgrade itself through. */
export type Manager = 'npm' | 'bun' | 'pnpm' | 'yarn';

type Env = Readonly<Record<string, string | undefined>>;

/**
 * Where each manager puts a global install, first match wins. Every row
 * needs a platform package's path, so a Bun or a Node that happens to sit
 * under a global node_modules never matches.
 */
const ROWS: readonly (readonly [RegExp, Manager | null])[] = [
  // npx and bunx are caches, not installs.
  [/\/_npx\/[^/]+\/node_modules\/@chorded\/chord-(?:darwin|linux)-/, null],
  [/\/bunx-[^/]+\/node_modules\/@chorded\/chord-(?:darwin|linux)-/, null],
  // $BUN_INSTALL (default ~/.bun), the platform package hoisted.
  [/\/install\/global\/node_modules\/@chorded\/chord-(?:darwin|linux)-/, 'bun'],
  // global/5/… before pnpm 11, global/v11/<hash>-<n>/… from 11.
  [
    /\/global\/[^/]+\/(?:[^/]+\/)?node_modules\/\.pnpm\/@chorded\+chord-(?:darwin|linux)-/,
    'pnpm',
  ],
  // yarn classic's default global folder.
  [/\/yarn\/global\/node_modules\/@chorded\/chord-(?:darwin|linux)-/, 'yarn'],
  // npm under any prefix (nvm, Homebrew, fnm, Volta), nested in the main
  // package.
  [
    /\/lib\/node_modules\/@chorded\/chord\/node_modules\/@chorded\/chord-(?:darwin|linux)-/,
    'npm',
  ],
];

/**
 * The manager that installed the binary at `realPath`; null when no
 * supported global install is identified (a copy, a build from source, a
 * local install, npx, bunx), as a guess would install a second chord.
 */
export function detectManager(realPath: string): Manager | null {
  for (const [pattern, manager] of ROWS) {
    if (pattern.test(realPath)) {
      return manager;
    }
  }

  return null;
}

/**
 * The manager's own global install of an exact version. Never `@*` or
 * `@latest`: `bun add -g pkg@*` leaves an installed version alone and exits
 * 0, so the version is always named.
 */
export function installArgv(manager: Manager, version: string): string[] {
  const spec = `${PACKAGE}@${version}`;

  switch (manager) {
    case 'npm':
      return ['npm', 'install', '--global', spec];
    case 'bun':
      return ['bun', 'add', '--global', spec];
    case 'pnpm':
      return ['pnpm', 'add', '--global', spec];
    case 'yarn':
      return ['yarn', 'global', 'add', spec];
  }
}

/**
 * Runs a manager as a person would type it: looked up on the PATH of
 * `env`, its stdio the terminal's, so its progress shows and its prompts
 * (an OTP, corepack) can be answered; no timeout, as an install downloads
 * a large tarball. A manager missing from PATH rejects with its ENOENT.
 */
export function runManager(argv: readonly string[], env: Env): Promise<void> {
  const [command = '', ...args] = argv;

  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { env: { ...env }, stdio: 'inherit' });

    child.on('error', reject);
    child.on('exit', (code, signal) => {
      if (signal !== null) {
        reject(new Error(`${argv.join(' ')} was killed by ${signal}.`));
      } else if (code !== 0) {
        reject(new Error(`${argv.join(' ')} exited with status ${code}.`));
      } else {
        resolve();
      }
    });
  });
}

/** Upgrades chord through the manager that installed it globally. */
export class ManagerProvider extends NpmProvider {
  override name: Manager;

  constructor(
    manager: Manager,
    private readonly env: Env,
    /**
     * The real path of a chord no supported install was identified for;
     * the upgrade then refuses with how to upgrade it by hand.
     */
    private readonly unidentified?: string,
    private readonly run: typeof runManager = runManager,
  ) {
    super({ package: PACKAGE });

    this.name = manager;
  }

  // An exact version for every manager: under `@*`, which NpmProvider
  // delegates `latest` to, bun leaves an installed chord alone and exits 0.
  override async resolveVersion(
    name: string,
    version: string,
  ): Promise<string> {
    return version === 'latest'
      ? (await this.getVersions(name)).latest
      : version;
  }

  override async getVersions(name: string): Promise<Versions> {
    try {
      return await super.getVersions(name);
    } catch (error) {
      throw new Error(
        `chord could not read the versions of ${PACKAGE} from the npm registry: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  // Not a permission check: in cliffy 1.3.1 its only caller is the version
  // check on help and --version, and false keeps either from reaching the
  // registry.
  override hasRequiredPermissions(): Promise<boolean> {
    return Promise.resolve(false);
  }

  override async upgrade(options: ProviderUpgradeOptions): Promise<void> {
    if (this.unidentified !== undefined) {
      throw new Error(unidentifiedText(this.unidentified, options.to));
    }

    const argv = installArgv(this.name, options.to);

    this.logger.log(`$ ${argv.join(' ')}`);

    try {
      await this.run(argv, this.env);
    } catch (error) {
      if ((error as { code?: unknown }).code === 'ENOENT') {
        throw new Error(
          `${this.name} is not on PATH. Install ${this.name}, or upgrade chord with the manager that installed it.`,
        );
      }

      throw error;
    }

    this.logger.info(
      `A chord already running keeps ${options.from} until it is started again.`,
    );
  }
}

function unidentifiedText(path: string, version: string): string {
  const lines = (['npm', 'bun', 'pnpm', 'yarn'] as const).map((manager) =>
    installArgv(manager, version).join(' '),
  );

  return `chord cannot tell which package manager installed ${path}. If one did, upgrade with it: ${lines.join(', ')}. A build from source upgrades with git pull and bun run dev compile --install.`;
}

/**
 * cliffy's command over the provider of the manager that installed the
 * chord at `execPath` (its real path), or npm's, which refuses, when none
 * is identified: cliffy needs one.
 */
export function upgradeCommand(execPath: string, env: Env) {
  const manager = detectManager(execPath);
  const provider = new ManagerProvider(
    manager ?? 'npm',
    env,
    manager === null ? execPath : undefined,
  );

  // standalone: false sends cliffy to the provider's upgrade rather than its
  // own binary swap; no spinner, as the manager writes to the same terminal.
  return new UpgradeCommand({ provider, standalone: false, spinner: false });
}
