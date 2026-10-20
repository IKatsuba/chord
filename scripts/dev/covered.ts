/**
 * Whether tsc checks every TypeScript file git tracks (CHD-474). On a file
 * system that ignores case, tsc's own discovery keeps one file of each pair
 * whose names differ only by case (`Strip_test.tsx` beside
 * `strip_test.ts`), so a type error in the other passes the local check and
 * fails CI on Linux; tsconfig.json's `files` lists such files by name.
 * Run as a script, it compares `tsc --listFilesOnly` with `git ls-files -z`
 * and exits 1, naming each file left out.
 */
import { spawnSync } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { relative, sep } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

// Real paths on both sides: Bun gives a script its real path, tsc lists
// files by the one they were found by (`/tmp` for `/private/tmp`).
const root = realpathSync(fileURLToPath(new URL('../..', import.meta.url)));

/**
 * Tracked files tsc is not asked to check. eslint.config.ts: checking it
 * finds two errors where eslint-plugin-react-hooks's and typescript-eslint's
 * types disagree with ESLint 10's `Plugin`; how to settle them is the
 * owner's, CHD-474's Q64 on the board.
 */
export const EXEMPT: readonly string[] = ['eslint.config.ts'];

/**
 * The tracked `.ts` and `.tsx` files, from the root, but `EXEMPT`'s, that
 * tsc's list leaves out: `listed` is its absolute paths, a file in node_modules or Bun's types
 * among them; `tracked` git's paths. Compared by exact name, as a file
 * system that ignores case would not.
 */
export function uncovered(
  tracked: readonly string[],
  listed: readonly string[],
  from: string,
): string[] {
  const checked = new Set(
    listed.map((file) => relative(from, file).split(sep).join('/')),
  );

  return tracked.filter(
    (file) =>
      /\.tsx?$/.test(file) && !checked.has(file) && !EXEMPT.includes(file),
  );
}

/**
 * `argv`'s output from `cwd`, split at `separator`; a failure ends the
 * script with the command's status.
 */
function output(
  argv: readonly string[],
  cwd: string,
  separator: string,
): string[] {
  const [command = '', ...args] = argv;
  const child = spawnSync(command, args, { cwd, encoding: 'utf8' });

  if (child.status !== 0) {
    process.stderr.write(child.stderr);
    process.exit(child.status ?? 1);
  }

  return child.stdout.split(separator).filter((each) => each !== '');
}

/**
 * The files git tracks in `cwd`'s repository, from its root, by their
 * actual names: NUL-separated, as git quotes a name with a quote, a
 * non-ASCII character or a control character in its plain listing.
 */
export function trackedFiles(cwd: string): string[] {
  return output(['git', 'ls-files', '-z'], cwd, '\0');
}

if (import.meta.main) {
  const left = uncovered(
    trackedFiles(root),
    output([process.execPath, 'run', 'tsc', '--listFilesOnly'], root, '\n').map(
      (file) => realpathSync(file),
    ),
    root,
  );

  if (left.length > 0) {
    process.stderr.write(
      `tsc leaves out ${left.length} tracked file${left.length === 1 ? '' : 's'}; ` +
        "list each in tsconfig.json's files:\n" +
        left.map((file) => `  ${file}\n`).join(''),
    );
    process.exit(1);
  }
}
