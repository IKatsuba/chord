import { describe, expect, test } from 'bun:test';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  copyFile,
  mkdir,
  mkdtemp,
  readdir,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { trackedFiles, uncovered } from '../../../scripts/dev/covered.ts';

const root = '/work/chord';

test('a tracked TypeScript file missing from tsc’s list is named, by its exact case (CHD-474)', () => {
  const tracked = [
    'src/main.tsx',
    'tests/ui/app/strip_test.ts',
    'tests/ui/app/Strip_test.tsx',
    'README.md',
    'scripts/mark.svg',
  ];
  // As tsc lists them on a file system that ignores case: one of the pair,
  // and files outside the tree, Bun's types among them.
  const listed = [
    `${root}/node_modules/bun-types/index.d.ts`,
    `${root}/src/main.tsx`,
    `${root}/tests/ui/app/strip_test.ts`,
  ];

  expect(uncovered(tracked, listed, root)).toStrictEqual([
    'tests/ui/app/Strip_test.tsx',
  ]);
  expect(
    uncovered(
      tracked,
      [...listed, `${root}/tests/ui/app/Strip_test.tsx`],
      root,
    ),
  ).toStrictEqual([]);
});

test('eslint.config.ts is found missing like any other tracked file (CHD-475)', () => {
  expect(
    uncovered(['eslint.config.ts', 'lint/style.ts'], [], root),
  ).toStrictEqual(['eslint.config.ts', 'lint/style.ts']);
});

test('a tracked name git would quote, with a quote or a non-ASCII letter, is read as it is and found missing (CHD-474)', async () => {
  const repo = await mkdtemp(join(tmpdir(), 'chord-covered-'));

  try {
    const names = ['a"b.ts', 'café.tsx', 'plain.ts'];
    const git = (...args: string[]) =>
      execFileSync('git', args, { cwd: repo, stdio: 'pipe' });

    git('init', '-q');

    for (const name of names) {
      await writeFile(join(repo, name), 'export {};\n');
    }

    git('add', '.');

    // git ls-files without -z would give "a\"b.ts" and "caf\303\251.tsx".
    expect(trackedFiles(repo).toSorted()).toStrictEqual(names.toSorted());
    expect(
      uncovered(trackedFiles(repo), [join(repo, 'plain.ts')], repo).toSorted(),
    ).toStrictEqual(['a"b.ts', 'café.tsx']);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

describe('CHD-474 tester: actual guard process boundaries', () => {
  const names = [
    'scripts/dev/covered.ts',
    'compiler.ts',
    'src/case.ts',
    'src/Case.tsx',
    'src/café.tsx',
    'src/a"b.ts',
    'types/public.d.ts',
  ];

  async function withRepo(
    body: (repo: string, alias: string) => void | Promise<void>,
  ) {
    const repo = await mkdtemp(join(tmpdir(), 'chord-coverage-tester-'));
    const alias = `${repo} alias café`;

    try {
      await mkdir(join(repo, 'scripts', 'dev'), { recursive: true });
      await mkdir(join(repo, 'src'));
      await mkdir(join(repo, 'types'));
      await copyFile(
        new URL('../../../scripts/dev/covered.ts', import.meta.url),
        join(repo, 'scripts', 'dev', 'covered.ts'),
      );
      await writeFile(
        join(repo, 'package.json'),
        JSON.stringify({ scripts: { tsc: 'bun compiler.ts' } }),
      );
      await writeFile(
        join(repo, 'compiler.ts'),
        [
          "import { writeFileSync } from 'node:fs';",
          "writeFileSync(process.env.COVERED_MARKER!, 'called');",
          "const files = JSON.parse(process.env.COVERED_LISTED ?? '[]');",
          "if (process.argv.includes('--listFilesOnly')) {",
          "process.stdout.write(files.join('\\n') + '\\n');",
          '}',
          "process.stderr.write(process.env.COVERED_ERROR ?? '');",
          "process.exit(Number(process.env.COVERED_STATUS ?? '0'));",
        ].join('\n'),
      );

      for (const name of names.slice(2)) {
        await writeFile(join(repo, name), 'export {};\n');
      }

      execFileSync('git', ['init', '-q'], { cwd: repo, stdio: 'pipe' });
      execFileSync('git', ['add', '--', '.'], { cwd: repo, stdio: 'pipe' });
      await symlink(repo, alias, 'dir');
      await body(repo, alias);
    } finally {
      await rm(alias, { force: true });
      await rm(repo, { recursive: true, force: true });
    }
  }

  function run(
    repo: string,
    options: {
      alias?: string;
      cwd?: string;
      listed?: readonly string[];
      status?: number;
      path?: string;
    } = {},
  ) {
    const base = options.alias ?? repo;
    const result = spawnSync(
      process.execPath,
      [join(base, 'scripts', 'dev', 'covered.ts')],
      {
        cwd: options.cwd ?? repo,
        encoding: 'utf8',
        env: {
          ...process.env,
          ...(options.path === undefined ? {} : { PATH: options.path }),
          COVERED_MARKER: join(repo, 'compiler.called'),
          COVERED_LISTED: JSON.stringify(
            options.listed ?? names.map((name) => join(base, name)),
          ),
          COVERED_STATUS: String(options.status ?? 0),
          COVERED_ERROR: options.status ? 'compiler refused on purpose\n' : '',
        },
      },
    );

    expect(result.error).toBeUndefined();

    return result;
  }

  test('root and compiler aliases with spaces and Unicode work from a nested cwd', () =>
    withRepo((repo, alias) => {
      const result = run(repo, { alias, cwd: join(alias, 'src') });

      expect(result.status).toBe(0);
      expect(result.stderr).toBe('');
      expect(trackedFiles(repo)).toContain('src/Case.tsx');
      expect(trackedFiles(repo)).toContain('src/case.ts');
    }));

  test('a green compiler cannot cover a missing differently cased file', () =>
    withRepo((repo, alias) => {
      const result = run(repo, {
        alias,
        listed: names
          .filter((name) => name !== 'src/Case.tsx')
          .map((name) => join(alias, name)),
      });

      expect(result.status).toBe(1);
      expect(result.stderr).toBe(
        "tsc leaves out 1 tracked file; list each in tsconfig.json's files:\n" +
          '  src/Case.tsx\n',
      );
    }));

  test('quoted and non-ASCII omissions retain their real Git names', () =>
    withRepo((repo) => {
      const omitted = ['src/café.tsx', 'src/a"b.ts'];
      const result = run(repo, {
        listed: names
          .filter((name) => !omitted.includes(name))
          .map((name) => join(repo, name)),
      });

      expect(result.status).toBe(1);
      expect(result.stderr).toContain('tsc leaves out 2 tracked files');

      for (const name of omitted) {
        expect(result.stderr).toContain(`  ${name}\n`);
      }
    }));

  test('compiler failure keeps its status and diagnostics', () =>
    withRepo((repo) => {
      const result = run(repo, { status: 23 });

      expect(result.status).toBe(23);
      expect(result.stderr).toContain('compiler refused on purpose');
      expect(result.stderr).not.toContain('tsc leaves out');
    }));

  test('Git failure keeps its status and never starts the compiler', () =>
    withRepo(async (repo) => {
      const bin = join(repo, 'bin');

      await mkdir(bin);
      await writeFile(
        join(bin, 'git'),
        '#!/bin/sh\nprintf "git refused on purpose\\n" >&2\nexit 19\n',
        { mode: 0o755 },
      );

      const result = run(repo, { path: `${bin}:${process.env.PATH ?? ''}` });

      expect(result.status).toBe(19);
      expect(result.stderr).toContain('git refused on purpose');
      expect(await readdir(repo)).not.toContain('compiler.called');
    }));

  test('declarations stay covered and the provisional exemption names only the root config', () => {
    expect(
      uncovered(
        [
          'types/public.d.ts',
          'eslint.config.ts',
          'scripts/eslint.config.ts',
          'readme.js',
        ],
        [`${root}-other/types/public.d.ts`],
        root,
      ),
    ).toEqual(['types/public.d.ts', 'scripts/eslint.config.ts']);
    expect(
      uncovered(
        ['types/public.d.ts'],
        [`${root}/src/../types/public.d.ts`],
        root,
      ),
    ).toEqual([]);
  });
});
