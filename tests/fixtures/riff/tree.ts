/**
 * A temporary project for riff's tools: the cases where fff's file set is
 * not git's (CHD-485, "Tools"; evidence/CHD-485/search.md), so a test pins
 * each difference and an fff upgrade that changes one fails.
 */
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, realpath, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

/** Every file the tree holds, by path, with what it says. */
export const FILES: Readonly<Record<string, string>> = {
  'src/a.ts': 'before\nneedle one\nafter\n',
  'src/deep/b.ts': 'needle two\n',
  'notes.md': 'static int\nfoo_probe(void);\n',
  '.hidden': 'needle hidden\n',
  'node_modules/pkg/index.js': 'needle module\n',
  // Ignored by .gitignore but added with -f: git lists it, fff leaves it out.
  'tracked.log': 'needle tracked\n',
  // Ignored and untracked: neither lists it.
  'ignored/x.ts': 'needle ignored\n',
  // In .git/info/exclude: git leaves it out, fff lists it.
  'excluded.txt': 'needle excluded\n',
};

function git(cwd: string, ...args: string[]) {
  const run = spawnSync('git', args, {
    cwd,
    encoding: 'utf8',
    env: {
      ...process.env,
      GIT_CONFIG_GLOBAL: '/dev/null',
      GIT_CONFIG_NOSYSTEM: '1',
    },
  });

  if (run.status !== 0) {
    throw new Error(`git ${args.join(' ')}: ${run.stderr}`);
  }
}

/**
 * Makes the tree in a new temporary directory and answers its real path;
 * `repository` makes it a git repository, as fff's rules differ by that.
 */
export async function makeTree(repository: boolean): Promise<string> {
  const root = await realpath(
    await mkdtemp(join(tmpdir(), 'chord-riff-tree-')),
  );

  for (const [path, text] of Object.entries(FILES)) {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), text);
  }

  await writeFile(join(root, '.gitignore'), 'ignored/\n*.log\n');
  // fff never lists a symlink, to a file or a directory.
  await symlink(join(root, 'notes.md'), join(root, 'link.md'));
  await symlink(join(root, 'src'), join(root, 'linked'));

  if (repository) {
    git(root, 'init', '-q');
    git(root, 'config', 'core.ignorecase', 'false');
    await writeFile(join(root, '.git', 'info', 'exclude'), 'excluded.txt\n');
    git(root, 'add', '.');
    git(root, 'add', '-f', 'tracked.log');
  }

  return root;
}
