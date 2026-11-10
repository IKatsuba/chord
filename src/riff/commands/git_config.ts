/**
 * Adapted from vercel-labs/fx v0.0.16,
 * src/core/indexer/{layout,git_config,bounded_read}.zig and indexer.zig,
 * Apache-2.0. chord uses trusted git to parse bounded config files instead
 * of porting the text parser; discovery and every-include limits follow fx.
 */
import { Buffer } from 'node:buffer';
import { constants } from 'node:fs';
import { open, stat } from 'node:fs/promises';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { notFound } from '../../not_found.ts';

export type GitLayout = { gitDir: string; commonDir: string };

/** Refuses links, devices and growing files instead of acting on partial data. */
async function readBounded(
  path: string,
  limit: number,
): Promise<Buffer | null> {
  let file;

  try {
    file = await open(
      path,
      constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK,
    );
  } catch (error) {
    if (
      notFound(error) ||
      (error as NodeJS.ErrnoException).code === 'ENOTDIR'
    ) {
      return null;
    }

    throw error;
  }

  try {
    const info = await file.stat();

    if (!info.isFile() || info.size > limit) {
      throw new Error('Metadata unavailable');
    }

    const bytes = Buffer.alloc(Math.min(info.size + 1, limit + 1));
    let count = 0;

    while (count < bytes.length) {
      const { bytesRead } = await file.read(
        bytes,
        count,
        bytes.length - count,
        count,
      );

      if (bytesRead === 0) {
        break;
      }

      count += bytesRead;
    }

    if (count > info.size) {
      throw new Error('Metadata grew during read');
    }

    return bytes.subarray(0, count);
  } finally {
    await file.close();
  }
}

async function gitDirs(gitDir: string): Promise<GitLayout | null> {
  const head = await readBounded(join(gitDir, 'HEAD'), 4096);

  if (head === null) {
    return null;
  }

  const text = head.subarray(0, 255).toString();

  if (
    !/^ref:[ \t\r\n\v\f]*refs\//.test(text) &&
    !/^(?:[a-fA-F0-9]{64}|[a-fA-F0-9]{40})/.test(text)
  ) {
    return null;
  }

  const common = await readBounded(join(gitDir, 'commondir'), 4096);
  const raw = common?.toString().replace(/[ \t\r\n]+$/, '');

  if (raw === '') {
    return null;
  }

  const commonDir = raw === undefined ? gitDir : resolve(gitDir, raw);

  for (const name of ['objects', 'refs']) {
    try {
      if (!(await stat(join(commonDir, name))).isDirectory()) {
        return null;
      }
    } catch {
      return null;
    }
  }

  return { gitDir, commonDir };
}

/** Discovers .git directories and gitdir/commondir pointers, never bare cwd. */
export async function discoverRepository(
  cwd: string,
): Promise<GitLayout | null> {
  if (!isAbsolute(cwd)) {
    throw new Error('Relative repository directory');
  }

  let candidate = resolve(cwd);

  for (;;) {
    const dot = join(candidate, '.git');
    let info;

    try {
      info = await stat(dot);
    } catch (error) {
      if (!notFound(error)) {
        throw error;
      }
    }

    if (info?.isDirectory()) {
      const layout = await gitDirs(dot);

      if (layout) {
        return layout;
      }
    } else if (info?.isFile()) {
      const content = (await readBounded(dot, 4096))?.toString();

      if (!content?.startsWith('gitdir: ')) {
        throw new Error('Invalid gitdir file');
      }

      const raw = content.slice(8).replace(/[ \t\r\n]+$/, '');

      if (!raw) {
        throw new Error('Invalid gitdir file');
      }

      const layout = await gitDirs(resolve(candidate, raw));

      if (!layout) {
        throw new Error('Invalid gitdir target');
      }

      return layout;
    }

    const parent = dirname(candidate);

    if (parent === candidate) {
      return null;
    }

    candidate = parent;
  }
}

/** Every conditional include is loaded, so no condition can hide a driver. */
export async function repositoryFilters(
  layout: GitLayout | null,
  home: string | undefined,
  parseFile: (path: string, bytes: Buffer) => Promise<string | null>,
): Promise<string[]> {
  const names = new Set<string>();
  let files = 0;
  let total = 0;
  const load = async (path: string, depth: number): Promise<void> => {
    if (files++ >= 64 || depth > 10) {
      throw new Error('Config include limit');
    }

    if (path === '/dev/null') {
      return;
    }

    const bytes = await readBounded(path, 1024 * 1024);

    if (bytes === null) {
      return;
    }

    total += bytes.length;

    if (total > 1024 * 1024) {
      throw new Error('Config byte limit');
    }

    // git's no-includes list emits key LF value NUL, preserving repeated keys.
    const parsed = await parseFile(path, bytes);

    if (parsed === null) {
      throw new Error('Config parse failed');
    }

    for (const entry of parsed.split('\0')) {
      if (!entry) {
        continue;
      }

      const at = entry.indexOf('\n');
      const key = at < 0 ? entry : entry.slice(0, at);
      const value = at < 0 ? null : entry.slice(at + 1);
      const filter = /^filter\.(.*)\.(?:clean|smudge|process)$/.exec(key);

      if (filter) {
        names.add(filter[1]!);
      }

      if (
        value === null ||
        !(key === 'include.path' || /^includeif\..*\.path$/.test(key))
      ) {
        continue;
      }

      if (!value || (value.startsWith('~') && !value.startsWith('~/'))) {
        continue;
      }

      if (value.startsWith('~/') && home === undefined) {
        continue;
      }

      const expanded = value.startsWith('~/')
        ? join(home!, value.slice(2))
        : value;

      await load(
        isAbsolute(expanded) ? expanded : resolve(dirname(path), expanded),
        depth + 1,
      );
    }
  };

  if (layout) {
    await load(join(layout.commonDir, 'config'), 0);
    await load(join(layout.gitDir, 'config.worktree'), 0);
  }

  return [...names];
}
