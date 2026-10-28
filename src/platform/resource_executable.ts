/** Existing official PATH commands; compatibility does not establish publisher or auth identity. */
import { which } from '@david/which';
import { fileTypeFromBuffer } from 'file-type';
import { open, realpath } from 'node:fs/promises';
import process from 'node:process';
import { finished } from 'node:stream/promises';
import {
  ResourceReadError,
  resourceSignal,
  resourceWait,
  withResourceProcess,
} from './resource_process.ts';

export type ResourceProvider = 'codex' | 'claude';
export type ResourceExecutable =
  | { readonly path: string; readonly version: string }
  | { readonly unavailable: string };

const VERSION_OUTPUT = {
  codex: /^codex-cli (\S+)$/,
  claude: /^(\S+) \(Claude Code\)$/,
} as const;

/** Factored for fake resolver tests; ordinary collectors use the public defaults. */
export interface ExecutableInspection {
  readonly platform: string;
  readonly arch: string;
  lookup(name: string): Promise<string | undefined>;
  native(path: string): Promise<boolean>;
  version(path: string, cwd: string, signal: AbortSignal): Promise<string>;
}

async function native(path: string): Promise<boolean> {
  const file = await open(path, 'r');

  try {
    const buffer = Buffer.alloc(4100);
    const read = await file.read(buffer, 0, buffer.length, 0);
    const type = await fileTypeFromBuffer(buffer.subarray(0, read.bytesRead));

    return type?.ext === 'macho' || type?.ext === 'elf';
  } finally {
    await file.close();
  }
}

function version(
  path: string,
  cwd: string,
  signal: AbortSignal,
): Promise<string> {
  return withResourceProcess(
    [path, '--version'],
    { cwd, signal },
    async (group, total) => {
      const output: Buffer[] = [];
      let bytes = 0;

      group.child.stdout!.on('data', (chunk: Buffer) => {
        bytes += chunk.length;

        if (bytes <= 4096) {
          output.push(chunk);
        }
      });

      const [exit] = await resourceWait(
        Promise.all([group.exit, finished(group.child.stdout!)]),
        resourceSignal(total, 3000),
      );

      if (exit.code !== 0 || bytes > 4096) {
        return '';
      }

      return Buffer.concat(output).toString('utf8').trim();
    },
  );
}

const INSPECTION: ExecutableInspection = {
  platform: process.platform,
  arch: process.arch,
  lookup: async (name) => {
    const path = await which(name);

    return path === undefined ? undefined : realpath(path);
  },
  native,
  version,
};

export async function resolveResourceExecutable(
  provider: ResourceProvider,
  options: {
    readonly cwd: string;
    readonly signal: AbortSignal;
    readonly customCommand: boolean;
  },
  inspect: ExecutableInspection = INSPECTION,
): Promise<ResourceExecutable> {
  if (options.customCommand) {
    return {
      unavailable:
        'Custom ACP command has no verified association with the official native provider authentication.',
    };
  }

  if (inspect.platform !== 'darwin' || inspect.arch !== 'arm64') {
    return {
      unavailable:
        'Resource collector compatibility is not verified on this platform.',
    };
  }

  try {
    const path = await inspect.lookup(provider);

    if (path === undefined) {
      return {
        unavailable:
          'Official native provider executable is missing from PATH.',
      };
    }

    if (!(await inspect.native(path))) {
      if (provider !== 'codex') {
        return {
          unavailable:
            'The Claude collector requires the official native executable.',
        };
      }

      if ((await inspect.lookup('node')) === undefined) {
        return {
          unavailable:
            'The official npm Codex launcher requires an existing Node installation.',
        };
      }
    }

    const version = VERSION_OUTPUT[provider].exec(
      await inspect.version(path, options.cwd, options.signal),
    )?.[1];

    if (version === undefined) {
      return { unavailable: 'Native provider version could not be read.' };
    }

    return { path, version };
  } catch (error) {
    if (
      options.signal.aborted ||
      (error instanceof ResourceReadError && error.kind === 'cleanup')
    ) {
      throw error;
    }

    return {
      unavailable: 'Official provider executable could not be verified.',
    };
  }
}
